" Runs every s:test_* against tests/fake_server.py, whose ports come in
" $KANAEMI_TEST_PORT and $KANAEMI_TEST_ADMIN. Exits non-zero on a failure.

let s:root = expand('<sfile>:p:h:h')
let s:port = str2nr($KANAEMI_TEST_PORT)
let s:admin = $KANAEMI_TEST_ADMIN
execute 'set runtimepath^=' .. fnameescape(s:root)

function! s:admin(command) abort
  call system(printf('python3 %s %s %s',
        \ shellescape(s:root .. '/tests/admin.py'), s:admin, a:command))
endfunction

function! s:wait_until(cond) abort
  let start = reltime()
  while !a:cond()
    if reltimefloat(reltime(start)) > 3.0
      throw 'timed out waiting'
    endif
    sleep 10m
  endwhile
endfunction

" Like assert_fails(), which makes Neovim print the exception it catches.
function! s:assert_throws(command, prefix) abort
  try
    execute a:command
    call assert_report(printf('%s did not throw', a:command))
  catch
    call assert_equal(a:prefix, v:exception[: len(a:prefix) - 1], a:command)
  endtry
endfunction

function! s:settle() abort
  " Lets lines already on their way arrive.
  sleep 200m
endfunction

function! s:setup() abort
  let g:kanaemi_port = s:port
  unlet! g:kanaemi_reconnect_interval
  call s:admin('focus')
  call s:admin('user kana')
  " The change above is told to a connection still watching; it belongs to
  " the test before.
  call s:settle()
endfunction

function! s:test_get_mode_answers_the_mode_of_the_field() abort
  call assert_equal('kana', kanaemi#get_mode())
  call s:admin('user abc')
  call assert_equal('abc', kanaemi#get_mode())
endfunction

function! s:test_set_mode_changes_the_mode_and_answers_it() abort
  call assert_equal('abc', kanaemi#set_mode('abc'))
  call assert_equal('abc', kanaemi#get_mode())
  call assert_equal('kana', kanaemi#set_mode('kana'))
endfunction

function! s:test_set_mode_refuses_an_unknown_mode() abort
  call s:assert_throws("call kanaemi#set_mode('hira')", 'kanaemi: mode is kana or abc')
endfunction

function! s:test_without_a_focused_field_requests_fail() abort
  call s:admin('blur')
  call s:assert_throws('call kanaemi#get_mode()', 'kanaemi: no-field')
  call s:assert_throws("call kanaemi#set_mode('abc')", 'kanaemi: no-field')
endfunction

function! s:test_without_a_port_requests_fail() abort
  unlet g:kanaemi_port
  call s:assert_throws('call kanaemi#get_mode()', 'kanaemi: g:kanaemi_port')
endfunction

function! s:test_without_the_ime_listening_requests_fail() abort
  let g:kanaemi_port = 1
  call s:assert_throws('call kanaemi#get_mode()', 'kanaemi: cannot connect')
endfunction

function! s:test_watch_mode_tells_each_change() abort
  let told = []
  let Unwatch = kanaemi#watch_mode({ mode -> add(told, mode) })
  try
    call s:settle()
    call assert_equal([], told, 'the mode at the start is no change')
    call s:admin('user abc')
    call s:wait_until({ -> len(told) >= 1 })
    call kanaemi#set_mode('kana')
    call s:wait_until({ -> len(told) >= 2 })
    call s:admin('blur')
    call s:wait_until({ -> len(told) >= 3 })
    call s:settle()
    call assert_equal(['abc', 'kana', v:null], told)
  finally
    call Unwatch()
  endtry
endfunction

function! s:test_unwatch_stops_telling() abort
  let first = []
  let second = []
  let Unwatch = kanaemi#watch_mode({ mode -> add(first, mode) })
  let Keep = kanaemi#watch_mode({ mode -> add(second, mode) })
  try
    call Unwatch()
    call s:admin('user abc')
    call s:wait_until({ -> len(second) >= 1 })
    call s:settle()
    call assert_equal([], first)
    call assert_equal(['abc'], second)
  finally
    call Keep()
  endtry
endfunction

function! s:test_a_failing_watcher_does_not_stop_the_others() abort
  let told = []
  let Broken = kanaemi#watch_mode({ mode -> execute('throw "broken"') })
  let Unwatch = kanaemi#watch_mode({ mode -> add(told, mode) })
  try
    silent! call s:admin('user abc')
    call s:wait_until({ -> len(told) >= 1 })
    call assert_equal(['abc'], told)
  finally
    call Broken()
    call Unwatch()
  endtry
endfunction

function! s:test_watch_mode_comes_back_after_the_connection_ends() abort
  let g:kanaemi_reconnect_interval = 100
  let told = []
  let Unwatch = kanaemi#watch_mode({ mode -> add(told, mode) })
  try
    call s:settle()
    call s:admin('close')
    call s:wait_until({ -> len(told) >= 1 })
    call assert_equal([v:null], told, 'the mode is unknown once the IME is gone')
    call s:wait_until({ -> len(told) >= 2 })
    call assert_equal([v:null, 'kana'], told, 'the mode is known again once back')
    call s:admin('user abc')
    call s:wait_until({ -> len(told) >= 3 })
    call assert_equal([v:null, 'kana', 'abc'], told)
    call assert_equal('abc', kanaemi#get_mode())
  finally
    call Unwatch()
  endtry
endfunction

function! s:test_watch_mode_follows_a_new_port() abort
  let told = []
  let Unwatch = kanaemi#watch_mode({ mode -> add(told, mode) })
  try
    call s:settle()
    let g:kanaemi_port = 1
    call s:assert_throws('call kanaemi#get_mode()', 'kanaemi: cannot connect')
    let g:kanaemi_port = s:port
    call assert_equal('kana', kanaemi#get_mode())
    call s:admin('user abc')
    call s:wait_until({ -> len(told) >= 3 })
    call s:settle()
    call assert_equal([v:null, 'kana', 'abc'], told)
  finally
    call Unwatch()
  endtry
endfunction

function! s:test_requests_connect_again_after_the_connection_ends() abort
  call assert_equal('kana', kanaemi#get_mode())
  call s:admin('close')
  call s:settle()
  call assert_equal('kana', kanaemi#get_mode())
endfunction

function! s:run() abort
  let names = sort(map(
        \ filter(split(execute('function /_test_'), "\n"), 'v:val =~# "^function"'),
        \ { _, v -> matchstr(v, '<SNR>\d\+_test_\w\+') }))
  let failed = 0
  for name in names
    let v:errors = []
    try
      call s:setup()
      call call(name, [])
    catch
      call add(v:errors, v:throwpoint .. ': ' .. v:exception)
    endtry
    let label = substitute(name, '^<SNR>\d\+_test_', '', '')
    if empty(v:errors)
      call writefile(['ok   ' .. label], '/dev/stdout', 'a')
    else
      let failed += 1
      call writefile(['FAIL ' .. label] + map(copy(v:errors), '"     " .. v:val'), '/dev/stdout', 'a')
    endif
  endfor
  if failed
    cquit!
  endif
  qall!
endfunction

call s:run()
