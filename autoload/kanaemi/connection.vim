" The one connection to the control port that every call shares.
"
" Requests carry an id and wait for the answer with the same id; lines
" without one are about watching, and go to kanaemi#watcher.

let s:host = '127.0.0.1'

" The open channel: {'port', 'send', 'close'}, or v:null.
let s:channel = v:null
" Counts the channels opened, so lines from a channel let go are ignored.
let s:generation = 0
let s:next_request = 0
" Answers by request id, until their request takes them.
let s:answers = {}
" Whether changes are wanted, and whether the open channel asked for them.
let s:wants_watch = 0
let s:watching = 0
let s:retry = -1

" Sends a:message and returns the answer, throwing the error it tells.
function! kanaemi#connection#request(message) abort
  call s:connect()
  let s:next_request += 1
  let id = s:next_request
  let generation = s:generation
  call s:channel.send(extend({'id': id}, a:message))
  call kanaemi#channel#wait(s:timeout(),
        \ { -> has_key(s:answers, id) || s:generation != generation || s:channel is# v:null })
  if !has_key(s:answers, id)
    throw s:generation == generation && s:channel isnot# v:null
          \ ? 'kanaemi: no answer from the IME'
          \ : 'kanaemi: the connection to the IME ended'
  endif
  let answer = remove(s:answers, id)
  if has_key(answer, 'error')
    throw printf('kanaemi: %s: %s', answer.error, get(answer, 'message', ''))
  endif
  return answer
endfunction

" Asks for changes, on this channel and on every one opened after it.
function! kanaemi#connection#watch() abort
  let s:wants_watch = 1
  call s:connect()
  call s:ask_changes()
endfunction

" Stops asking for changes on channels opened from now on. The open one
" goes on telling them, as the IME has no way to stop it.
function! kanaemi#connection#unwatch() abort
  let s:wants_watch = 0
  call s:stop_retry()
endfunction

function! s:connect() abort
  let port = get(g:, 'kanaemi_port', v:null)
  if type(port) != v:t_number
    throw 'kanaemi: g:kanaemi_port is not set; set it to the port in the [control] section of the Kanaemi settings'
  endif
  if s:channel isnot# v:null
    if s:channel.port == port
      return
    endif
    call s:channel.close()
    call s:lost()
  endif
  let address = printf('%s:%d', s:host, port)
  let s:generation += 1
  try
    let channel = kanaemi#channel#open(address, s:timeout(),
          \ function('s:on_line', [s:generation]),
          \ function('s:on_close', [s:generation]))
  catch /^kanaemi:/
    throw v:exception
  catch
    throw printf('kanaemi: cannot connect to %s: %s', address, v:exception)
  endtry
  let s:channel = extend(channel, {'port': port})
  let s:watching = 0
  if s:wants_watch
    call s:ask_changes()
  endif
endfunction

function! s:ask_changes() abort
  if !s:watching
    call s:channel.send({'op': 'watch-mode'})
    let s:watching = 1
  endif
endfunction

" The channel went away: nobody knows the mode until another is open.
function! s:lost() abort
  let s:channel = v:null
  let s:watching = 0
  call kanaemi#watcher#lost()
endfunction

function! s:timeout() abort
  return get(g:, 'kanaemi_timeout', 1000)
endfunction

function! s:on_line(generation, line) abort
  if a:generation != s:generation
    return
  endif
  try
    let message = json_decode(a:line)
  catch
    return
  endtry
  if type(message) != v:t_dict
    return
  endif
  if has_key(message, 'id')
    let s:answers[message.id] = message
  elseif get(message, 'event', '') ==# 'mode'
    call kanaemi#watcher#tell(get(message, 'mode', v:null))
  elseif has_key(message, 'mode')
    call kanaemi#watcher#start(message.mode)
  endif
endfunction

function! s:on_close(generation) abort
  if a:generation != s:generation || s:channel is# v:null
    return
  endif
  call s:lost()
  if s:wants_watch
    call s:start_retry()
  endif
endfunction

function! s:start_retry() abort
  if s:retry == -1
    let s:retry = timer_start(
          \ get(g:, 'kanaemi_reconnect_interval', 5000),
          \ function('s:on_retry'),
          \ {'repeat': -1})
  endif
endfunction

function! s:stop_retry() abort
  if s:retry != -1
    call timer_stop(s:retry)
    let s:retry = -1
  endif
endfunction

function! s:on_retry(timer) abort
  try
    call s:connect()
    call s:stop_retry()
  catch /^kanaemi:/
  endtry
endfunction
