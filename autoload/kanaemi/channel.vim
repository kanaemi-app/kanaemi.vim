" A line-oriented TCP channel, over Vim's channels or Neovim's sockets.
"
" open() returns {'send': {message -> ...}, 'close': {-> ...}}; send() writes
" a:message as one JSON line. on_line(line) gets each line without its LF,
" and on_close() is called once when the other side ends it, never after
" close().

function! kanaemi#channel#open(address, timeout, on_line, on_close) abort
  return has('nvim')
        \ ? kanaemi#channel#nvim#open(a:address, a:on_line, a:on_close)
        \ : kanaemi#channel#vim#open(a:address, a:timeout, a:on_line, a:on_close)
endfunction

" Waits until a:cond() holds or a:timeout milliseconds pass, taking lines
" meanwhile.
function! kanaemi#channel#wait(timeout, cond) abort
  return has('nvim')
        \ ? kanaemi#channel#nvim#wait(a:timeout, a:cond)
        \ : kanaemi#channel#vim#wait(a:timeout, a:cond)
endfunction
