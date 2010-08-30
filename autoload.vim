" Vim script
" Author: Peter Odding
" Last Change: August 30, 2010
" URL: http://peterodding.com/code/vim/session/

" Public API for session persistence. {{{1

" The functions in this fold take a single list argument in which the Vim
" script lines are stored that should be executed to restore the (relevant
" parts of the) current Vim editing session. The only exception to this is
" session#save_session() which expects the target filename as 2nd argument:

function! session#save_session(commands, filename) " {{{2
  call add(a:commands, '" ' . a:filename . ': Vim session script.')
  call add(a:commands, '" Created by session.vim on ' . strftime('%d %B %Y at %H:%M:%S.'))
  call add(a:commands, '" Open this file in Vim and run :source % to restore your session.')
  call add(a:commands, '')
  call add(a:commands, 'set guioptions=' . escape(&go, ' "\'))
  call add(a:commands, 'set guifont=' . escape(&gfn, ' "\'))
  call session#save_features(a:commands)
  call session#save_colors(a:commands)
  call session#save_qflist(a:commands)
  call session#save_state(a:commands)
  call session#save_fullscreen(a:commands)
  call add(a:commands, '')
  call add(a:commands, '" vim: ft=vim ro nowrap smc=128')
endfunction

function! session#save_features(commands) " {{{2
  let template = "if exists('%s') != %i | %s %s | endif"
  for [global, command] in [
          \ ['g:syntax_on', 'syntax'],
          \ ['g:did_load_filetypes', 'filetype'],
          \ ['g:did_load_ftplugin', 'filetype plugin'],
          \ ['g:did_indent_on', 'filetype indent']]
    let active = exists(global)
    let toggle = active ? 'on' : 'off'
    call add(a:commands, printf(template, global, active, command, toggle))
  endfor
endfunction

function! session#save_colors(commands) " {{{2
  if exists('g:colors_name') && type(g:colors_name) == type('') && g:colors_name != ''
    let template = "if !exists('g:colors_name') || g:colors_name != %s | colorscheme %s | endif"
    call add(a:commands, printf(template, string(g:colors_name), fnameescape(g:colors_name)))
  endif
endfunction

function! session#save_fullscreen(commands) " {{{2
  try
    if xolox#shell#is_fullscreen()
      call add(a:commands, "if has('gui_running')")
      call add(a:commands, "  try")
      call add(a:commands, "    call xolox#shell#fullscreen()")
      " XXX Without this hack Vim on GTK doesn't restore &lines and &columns.
      call add(a:commands, "    call feedkeys(\":set lines=" . &lines . " columns=" . &columns . "\\<CR>\")")
      call add(a:commands, "  catch " . '/^Vim\%((\a\+)\)\=:E117/')
      call add(a:commands, "    \" Ignore missing full-screen plug-in.")
      call add(a:commands, "  endtry")
      call add(a:commands, "endif")
    endif
  catch /^Vim\%((\a\+)\)\=:E117/
    " Ignore missing full-screen functionality.
  endtry
endfunction

function! session#save_qflist(commands) " {{{2
  if has('quickfix')
    let qf_list = []
    for qf_entry in getqflist()
      if has_key(qf_entry, 'bufnr')
        if !has_key(qf_entry, 'filename')
          let qf_entry.filename = bufname(qf_entry.bufnr)
        endif
        unlet qf_entry.bufnr
      endif
      call add(qf_list, qf_entry)
    endfor
    call add(a:commands, 'call setqflist(' . string(qf_list) . ')')
  endif
endfunction

function! session#save_state(commands) " {{{2
  let tempfile = tempname()
  let ssop_save = &sessionoptions
  try
    " The default value of &sessionoptions includes "options" which causes
    " :mksession to include all Vim options and mappings in generated session
    " scripts. This can significantly increase the size of session scripts
    " which makes them slower to generate and evaluate. It can also be a bit
    " buggy, e.g. it breaks Ctrl-S when :runtime mswin.vim has been used. The
    " value of &sessionoptions is changed temporarily to avoid these issues.
    set ssop-=options ssop+=resize
    execute 'mksession' fnameescape(tempfile)
    let lines = readfile(tempfile)
    if lines[-1] == '" vim: set ft=vim :'
      call remove(lines, -1)
    endif
    call session#save_special_windows(lines)
    call extend(a:commands, lines)
    return 1
  finally
    let &sessionoptions = ssop_save
    call delete(tempfile)
  endtry
endfunction

" Integration between :mksession, :NERDTree and :Project. {{{3

function! session#save_special_windows(session)
  if exists(':NERDTree') == 2 && match(a:session, '\<NERD_tree_\d\+$') >= 0
          \ || exists(':Project') == 2 && exists('g:proj_running')
    let tabpage = tabpagenr()
    let window = winnr()
    try
      if &sessionoptions =~ '\<tabpages\>'
        tabdo windo call s:check_special_window(a:session)
      else
        windo call s:check_special_window(a:session)
      endif
    finally
      execute 'tabnext' tabpage
      execute window . 'wincmd w'
      if &sessionoptions =~ '\<tabpages\>'
        call add(a:session, 'tabnext ' . tabpage)
      endif
      call add(a:session, window . 'wincmd w')
    endtry
  endif
endfunction

function! s:check_special_window(session)
  if exists('b:NERDTreeRoot')
    let command = 'NERDTree'
    let argument = b:NERDTreeRoot.path.str()
  elseif exists('g:proj_running') && g:proj_running == bufnr('%')
    let command = 'Project'
    let argument = expand('%:p')
  endif
  if exists('command')
    if &sessionoptions =~ '\<tabpages\>'
      call add(a:session, 'tabnext ' . tabpagenr())
    endif
    call add(a:session, winnr() . 'wincmd w')
    call add(a:session, 'bwipeout')
    let argument = fnamemodify(argument, ':~')
    if &sessionoptions =~ '\<slash\>'
      let argument = substitute(argument, '\', '/', 'g')
    endif
    call add(a:session, command . ' ' . fnameescape(argument))
  endif
endfunction

" Automatic commands to manage the default session. {{{1

function! session#auto_load() " {{{2
  " Check that the user has started Vim without editing any files.
  if bufnr('$') == 1 && bufname('%') == '' && !&mod && getline(1, '$') == ['']
    " Check whether a session matching the user-specified server name exists.
    if v:servername !~ '^\cgvim\d*$'
      for session in session#get_names()
        if v:servername ==? session
          execute 'OpenSession' fnameescape(session)
          return
        endif
      endfor
    endif
    " Check whether the default session should be loaded.
    let path = session#name_to_path('default')
    if filereadable(path) && !s:session_is_locked(path)
      let msg = "Do you want to restore your default editing session?"
      if s:prompt(msg, 'g:session_autoload')
        OpenSession default
      endif
    endif
  endif
endfunction

function! session#auto_save() " {{{2
  if !v:dying
    let name = s:get_name('', 0)
    if name != '' && exists('s:session_is_dirty')
      let msg = "Do you want to save your editing session before quitting Vim?"
      if s:prompt(msg, 'g:session_autosave')
        execute 'SaveSession' fnameescape(name)
      endif
    endif
  endif
endfunction

function! session#auto_unlock() " {{{2
  let i = 0
  while i < len(s:lock_files)
    let lock_file = s:lock_files[i]
    if delete(lock_file) == 0
      call remove(s:lock_files, i)
    else
      let i += 1
    endif
  endwhile
endfunction

function! session#auto_dirty_check() " {{{2
  " This function is called each time a WinEnter event fires to detect when
  " the current tab page is changed in some way. This enables the plug-in to
  " not bother with the auto-save dialog when the session hasn't changed.
  if v:this_session == ''
    " Don't waste CPU time when no session is loaded.
    return
  elseif !exists('s:cached_layouts')
    let s:cached_layouts = {}
  else
    " Clear non-existing tab pages from s:cached_layouts.
    let last_tabpage = tabpagenr('$')
    call filter(s:cached_layouts, 'v:key <= last_tabpage')
  endif
  let tabpagenr = tabpagenr()
  let keys = ['tabpage:' . tabpagenr]
  let buflist = tabpagebuflist()
  for winnr in range(1, winnr('$'))
    " Create a string that describes the state of the window {winnr}.
    call add(keys, printf('width:%i,height:%i,buffer:%i',
          \ winwidth(winnr), winheight(winnr), buflist[winnr - 1]))
  endfor
  let layout = join(keys, "\n")
  let cached_layout = get(s:cached_layouts, tabpagenr, '')
  if cached_layout != '' && cached_layout != layout
    let s:session_is_dirty = 1
  endif
  let s:cached_layouts[tabpagenr] = layout
endfunction

function! s:prompt(msg, var) " {{{2
  if eval(a:var)
    return 1
  else
    let format = "%s Note that you can permanently disable this dialog by adding the following line to your %s script:\n\n\t:let %s = 1"
    let vimrc = has('win32') || has('win64') ? '~\_vimrc' : '~/.vimrc'
    let prompt = printf(format, a:msg, vimrc, a:var)
    return confirm(prompt, "&Yes\n&No", 1, 'Question') == 1
  endif
endfunction

" Commands that enable users to manage multiple sessions. {{{1

function! session#open_cmd(name, bang) abort " {{{2
  let name = s:select_name(s:unescape(a:name), 'restore')
  if name != ''
    let path = session#name_to_path(name)
    if !filereadable(path)
      let msg = "session.vim: The %s session at %s doesn't exist!"
      call xolox#warning(msg, string(name), fnamemodify(path, ':~'))
    elseif a:bang == '!' || !s:session_is_locked(path, 'OpenSession')
      call session#close_cmd(a:bang, 1)
      call s:lock_session(path)
      execute 'source' fnameescape(path)
      unlet! s:session_is_dirty
      call xolox#message("session.vim: Opened %s session from %s.", string(name), fnamemodify(path, ':~'))
    endif
  endif
endfunction

function! session#view_cmd(name) abort " {{{2
  let name = s:select_name(s:get_name(s:unescape(a:name), 0), 'view')
  if name != ''
    let path = session#name_to_path(name)
    if !filereadable(path)
      let msg = "session.vim: The %s session at %s doesn't exist!"
      call xolox#warning(msg, string(name), fnamemodify(path, ':~'))
    else
      execute 'tab drop' fnameescape(path)
      call xolox#message("session.vim: Viewing session script %s.", fnamemodify(path, ':~'))
    endif
  endif
endfunction

function! session#save_cmd(name, bang) abort " {{{2
  let name = s:get_name(s:unescape(a:name), 1)
  let path = session#name_to_path(name)
  let friendly_path = fnamemodify(path, ':~')
  if a:bang == '!' || !s:session_is_locked(path, 'SaveSession')
    let lines = []
    call session#save_session(lines, friendly_path)
    let is_dos = has('dos16') || has('dos32')
    let is_windows = has('win32') || has('win64')
    if (is_dos || is_windows) && &ssop !~ '\<unix\>'
      call map(lines, 'v:val . "\r"')
    endif
    if writefile(lines, path) != 0
      let msg = "session.vim: Failed to save %s session to %s!"
      call xolox#warning(msg, string(name), friendly_path)
    else
      let msg = "session.vim: Saved %s session to %s."
      call xolox#message(msg, string(name), friendly_path)
      let v:this_session = path
      call s:lock_session(path)
      unlet! s:session_is_dirty
    endif
  endif
endfunction

function! session#delete_cmd(name, bang) " {{{2
  let name = s:select_name(s:unescape(a:name), 'delete')
  if name != ''
    let path = session#name_to_path(name)
    if !filereadable(path)
      let msg = "session.vim: The %s session at %s doesn't exist!"
      call xolox#warning(msg, string(name), fnamemodify(path, ':~'))
    elseif a:bang == '!' || !s:session_is_locked(path, 'DeleteSession')
      if delete(path) != 0
        let msg = "session.vim: Failed to delete %s session at %s!"
        call xolox#warning(msg, string(name), fnamemodify(path, ':~'))
      else
        call s:unlock_session(path)
        let msg = "session.vim: Deleted %s session at %s."
        call xolox#message(msg, string(name), fnamemodify(path, ':~'))
      endif
    endif
  endif
endfunction

function! session#close_cmd(bang, silent) abort " {{{2
  let name = s:get_name('', 0)
  if name != '' && exists('s:session_is_dirty')
    let msg = "Do you want to save your current editing session before closing it?"
    if s:prompt(msg, 'g:session_autosave')
      SaveSession
    endif
    call s:unlock_session(session#name_to_path(name))
  endif
  if tabpagenr('$') > 1
    execute 'tabonly' . a:bang
  endif
  if winnr('$') > 1
    execute 'only' . a:bang
  endif
  execute 'enew' . a:bang
  unlet! s:session_is_dirty
  if v:this_session == ''
    if !a:silent
      let msg = "session.vim: Closed session."
      call xolox#message(msg)
    endif
  else
    if !a:silent
      let msg = "session.vim: Closed session %s."
      call xolox#message(msg, fnamemodify(v:this_session, ':~'))
    endif
    let v:this_session = ''
  endif
  return 1
endfunction

function! session#restart_cmd(bang) abort " {{{2
  let name = s:get_name('', 0)
  if name == '' | let name = 'restart' | endif
  execute 'SaveSession' . a:bang fnameescape(name)
  let progname = shellescape(fnameescape(v:progname))
  let servername = shellescape(fnameescape(name))
  let command = progname . ' --servername ' . servername
  let command .= ' -c ' . shellescape('OpenSession\! ' . fnameescape(name))
  if has('win32') || has('win64')
    execute '!start' command
  else
    let term = shellescape(fnameescape($TERM))
    let encoding = "--cmd ':set enc=" . escape(&enc, '\ ') . "'"
    silent execute '! TERM=' . term command encoding '&'
  endif
  execute 'CloseSession' . a:bang
  quitall
endfunction

" Miscellaneous functions. {{{1

function! s:unescape(s) " {{{2
  return substitute(a:s, '\\\(.\)', '\1', 'g')
endfunction

function! s:select_name(name, action) " {{{2
  if a:name != ''
    return a:name
  endif
  let sessions = sort(session#get_names())
  if empty(sessions)
    return 'default'
  elseif len(sessions) == 1
    return sessions[0]
  endif
  let lines = copy(sessions)
  for i in range(len(sessions))
    let lines[i] = ' ' . (i + 1) . '. ' . lines[i]
  endfor
  redraw
  sleep 100 m
  echo "\nPlease select the session to " . a:action . ":"
  sleep 100 m
  let i = inputlist([''] + lines + [''])
  return i >= 1 && i <= len(sessions) ? sessions[i - 1] : ''
endfunction

function! s:get_name(name, use_default) " {{{2
  let name = a:name
  if name == '' && v:this_session != ''
    let this_session_dir = fnamemodify(v:this_session, ':p:h')
    if xolox#path#equals(this_session_dir, g:session_directory)
      let name = session#path_to_name(v:this_session)
    endif
  endif
  return name != '' ? name : a:use_default ? 'default' : ''
endfunction

function! session#name_to_path(name) " {{{2
  let directory = xolox#path#absolute(g:session_directory)
  let filename = xolox#path#encode(a:name) . '.vim'
  return xolox#path#merge(directory, filename)
endfunction

function! session#path_to_name(path) " {{{2
  return xolox#path#decode(fnamemodify(a:path, ':t:r'))
endfunction

function! session#get_names() " {{{2
  let directory = xolox#path#absolute(g:session_directory)
  let filenames = split(glob(xolox#path#merge(directory, '*.vim')), "\n")
  return map(filenames, 'fnameescape(xolox#path#decode(fnamemodify(v:val, ":t:r")))')
endfunction

function! session#complete_names(arg, line, pos) " {{{2
  return filter(session#get_names(), 'v:val =~ a:arg')
endfunction

" Lock file management: {{{2

if !exists('s:lock_files')
  let s:lock_files = []
endif

function! s:lock_session(session_path)
  let lock_file = a:session_path . '.lock'
  if writefile([v:servername], lock_file) == 0
    if index(s:lock_files, lock_file) == -1
      call add(s:lock_files, lock_file)
    endif
    return 1
  endif
endfunction

function! s:unlock_session(session_path)
  let lock_file = a:session_path . '.lock'
  if delete(lock_file) == 0
    let idx = index(s:lock_files, lock_file)
    if idx >= 0
      call remove(s:lock_files, idx)
    endif
    return 1
  endif
endfunction

function! s:session_is_locked(session_path, ...)
  let lock_file = a:session_path . '.lock'
  if filereadable(lock_file)
    let lines = readfile(lock_file)
    if lines[0] !=? v:servername
      if a:0 >= 1
        let msg = "session.vim: The %s session is locked by another Vim instance named %s! Use :%s! to override."
        call xolox#warning(msg, string(fnamemodify(a:session_path, ':t:r')), string(lines[0]), a:1)
      endif
      return 1
    endif
  endif
endfunction

" vim: ts=2 sw=2 et
