function! kanaemi#channel#vim#open(address, timeout, on_line, on_close) abort
  let state = {'closed': 0}
  let handle = ch_open(a:address, {
        \ 'mode': 'nl',
        \ 'waittime': a:timeout,
        \ 'callback': function('s:on_line', [a:on_line]),
        \ 'close_cb': function('s:on_close', [state, a:on_close]),
        \})
  if ch_status(handle) !=# 'open'
    throw printf('kanaemi: cannot connect to %s', a:address)
  endif
  return {
        \ 'send': function('s:send', [handle]),
        \ 'close': function('s:close', [state, handle]),
        \}
endfunction

function! kanaemi#channel#vim#wait(timeout, cond) abort
  " Vim takes channel lines while it sleeps.
  let start = reltime()
  let timeout = a:timeout / 1000.0
  while !a:cond() && reltimefloat(reltime(start)) < timeout
    sleep 1m
  endwhile
endfunction

function! s:send(handle, message) abort
  call ch_sendraw(a:handle, json_encode(a:message) .. "\n")
endfunction

function! s:close(state, handle) abort
  let a:state.closed = 1
  silent! call ch_close(a:handle)
endfunction

function! s:on_line(on_line, handle, line) abort
  call a:on_line(a:line)
endfunction

function! s:on_close(state, on_close, handle) abort
  if !a:state.closed
    let a:state.closed = 1
    call a:on_close()
  endif
endfunction
