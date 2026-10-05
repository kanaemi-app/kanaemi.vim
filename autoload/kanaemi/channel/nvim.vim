function! kanaemi#channel#nvim#open(address, on_line, on_close) abort
  " Neovim hands over data in chunks; the part after the last LF waits in
  " 'pending' for the rest of its line.
  let state = {'pending': '', 'closed': 0, 'on_line': a:on_line, 'on_close': a:on_close}
  let id = sockconnect('tcp', a:address, {'on_data': function('s:on_data', [state])})
  if id <= 0
    throw printf('kanaemi: cannot connect to %s', a:address)
  endif
  return {
        \ 'send': function('s:send', [id]),
        \ 'close': function('s:close', [state, id]),
        \}
endfunction

function! kanaemi#channel#nvim#wait(timeout, cond) abort
  call wait(a:timeout, a:cond, 1)
endfunction

function! s:send(id, message) abort
  call chansend(a:id, json_encode(a:message) .. "\n")
endfunction

function! s:close(state, id) abort
  let a:state.closed = 1
  silent! call chanclose(a:id)
endfunction

function! s:on_data(state, id, data, event) abort
  if a:state.closed
    return
  endif
  if a:data == ['']
    let a:state.closed = 1
    call a:state.on_close()
    return
  endif
  let lines = copy(a:data)
  let lines[0] = a:state.pending .. lines[0]
  let a:state.pending = remove(lines, -1)
  for line in lines
    call a:state.on_line(line)
  endfor
endfunction
