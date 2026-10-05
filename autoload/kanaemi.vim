function! kanaemi#get_mode() abort
  return kanaemi#connection#request({'op': 'get-mode'}).mode
endfunction

function! kanaemi#set_mode(mode) abort
  if index(['kana', 'abc'], a:mode) < 0
    throw 'kanaemi: mode is kana or abc'
  endif
  return kanaemi#connection#request({'op': 'set-mode', 'mode': a:mode}).mode
endfunction

function! kanaemi#watch_mode(callback) abort
  let id = kanaemi#watcher#add(a:callback)
  try
    call kanaemi#connection#watch()
  catch
    call s:unwatch(id)
    throw v:exception
  endtry
  return function('s:unwatch', [id])
endfunction

function! s:unwatch(id) abort
  if kanaemi#watcher#remove(a:id)
    call kanaemi#connection#unwatch()
  endif
endfunction
