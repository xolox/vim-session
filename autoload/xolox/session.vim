" Vim script
" Author: Peter Odding
" Last Change: April 21, 2013
" URL: http://peterodding.com/code/vim/session/

let g:xolox#session#version = '1.5.10'

call xolox#misc#compat#check('session', 1)

" Public API for session persistence. {{{1

" The functions in this fold take a single list argument in which the Vim
" script lines are stored that should be executed to restore the (relevant
" parts of the) current Vim editing session. The only exception to this is
" xolox#session#save_session() which expects the target filename as 2nd
" argument:

function! xolox#session#save_session(commands, filename) " {{{2
  call add(a:commands, '" ' . a:filename . ': Vim session script.')
  call add(a:commands, '" Created by session.vim ' . g:xolox#session#version . ' on ' . strftime('%d %B %Y at %H:%M:%S.'))
  call add(a:commands, '" Open this file in Vim and run :source % to restore your session.')
  call add(a:commands, '')
  call add(a:commands, 'set guioptions=' . escape(&go, ' "\'))
  call add(a:commands, 'silent! set guifont=' . escape(&gfn, ' "\'))
  call xolox#session#save_globals(a:commands)
  call xolox#session#save_features(a:commands)
  call xolox#session#save_colors(a:commands)
  call xolox#session#save_qflist(a:commands)
  call xolox#session#save_state(a:commands)
  call xolox#session#save_fullscreen(a:commands)
  call add(a:commands, 'doautoall SessionLoadPost')
  call add(a:commands, 'unlet SessionLoad')
  call add(a:commands, '" vim: ft=vim ro nowrap smc=128')
endfunction

function! xolox#session#save_globals(commands) " {{{2
  for global in g:session_persist_globals
    call add(a:commands, printf("let %s = %s", global, string(eval(global))))
  endfor
endfunction

function! xolox#session#save_features(commands) " {{{2
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

function! xolox#session#save_colors(commands) " {{{2
  call add(a:commands, 'if &background != ' . string(&background))
  call add(a:commands, "\tset background=" . &background)
  call add(a:commands, 'endif')
  if exists('g:colors_name') && type(g:colors_name) == type('') && g:colors_name != ''
    let template = "if !exists('g:colors_name') || g:colors_name != %s | colorscheme %s | endif"
    call add(a:commands, printf(template, string(g:colors_name), fnameescape(g:colors_name)))
  endif
endfunction

function! xolox#session#save_fullscreen(commands) " {{{2
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

function! xolox#session#save_qflist(commands) " {{{2
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

function! xolox#session#save_state(commands) " {{{2
  let tempfile = tempname()
  let ssop_save = &sessionoptions
  try
    " The default value of &sessionoptions includes "options" which causes
    " :mksession to include all Vim options and mappings in generated session
    " scripts. This can significantly increase the size of session scripts
    " which makes them slower to generate and evaluate. It can also be a bit
    " buggy, e.g. it breaks Ctrl-S when :runtime mswin.vim has been used. The
    " value of &sessionoptions is changed temporarily to avoid these issues.
    set ssop-=options
    execute 'mksession' fnameescape(tempfile)
    let lines = readfile(tempfile)
    " Remove the mode line added by :mksession because we'll add our own in
    " xolox#session#save_session().
    call s:eat_trailing_line(lines, '" vim: set ft=vim :')
    " Remove the "SessionLoadPost" event firing at the end of the :mksession
    " output. We will fire the event ourselves when we're really done.
    call s:eat_trailing_line(lines, 'unlet SessionLoad')
    call s:eat_trailing_line(lines, 'doautoall SessionLoadPost')
    call xolox#session#save_special_windows(lines)
    call extend(a:commands, map(lines, 's:state_filter(v:val)'))
    return 1
  finally
    let &sessionoptions = ssop_save
    call delete(tempfile)
  endtry
endfunction

function! s:eat_trailing_line(session, line)
  if a:session[-1] == a:line
    call remove(a:session, -1)
  endif
endfunction

function! s:state_filter(line)
  if a:line =~ '^normal!\? zo$'
    " Silence "E490: No fold found" errors.
    return 'silent! ' . a:line
  elseif a:line =~ '^file .\{-}\<NERD_tree_\d\+$'
    " Silence "E95: Buffer with this name already exists" when restoring
    " mirrored NERDTree windows.
    return '" ' . a:line
  elseif a:line =~ '^file .\{-}\[BufExplorer\]$'
    " Same trick (about the E95) for BufExplorer.
    return '" ' . a:line
  elseif a:line =~ '^args '
    " The :mksession command adds an :args line to the session file, but when
    " :args is executed during a session restore it edits the first file it is
    " given, thereby breaking the session that the user was expecting to
    " get... I consider this to be a bug in :mksession, but anyway :-).
    return '" ' . a:line
  elseif a:line =~ '^\(argglobal\|\dargu\)$'
    " Because we disabled the :args command above we cause a potential error
    " when :mksession adds corresponding :argglobal and/or :argument commands
    " to the session script.
    return '" ' . a:line
  else
    return a:line
  endif
endfunction

function! xolox#session#save_special_windows(session) " {{{2
  " Integration between :mksession, :NERDTree and :Project.
  let tabpage = tabpagenr()
  let window = winnr()
  let s:nerdtrees = {}
  try
    if &sessionoptions =~ '\<tabpages\>'
      tabdo call s:check_special_tabpage(a:session)
    else
      call s:check_special_tabpage(a:session)
    endif
  finally
    unlet s:nerdtrees
    execute 'tabnext' tabpage
    execute window . 'wincmd w'
    call s:jump_to_window(a:session, tabpage, window)
  endtry
endfunction

function! s:check_special_tabpage(session)
  let status = 0
  windo let status += s:check_special_window(a:session)
  if status > 0 && winnr('$') > 1
    call add(a:session, winrestcmd())
  endif
endfunction

function! s:check_special_window(session)
  if exists('b:NERDTreeRoot')
    if !has_key(s:nerdtrees, bufnr('%'))
      let command = 'NERDTree'
      let argument = b:NERDTreeRoot.path.str()
      let s:nerdtrees[bufnr('%')] = 1
    else
      let command = 'NERDTreeMirror'
      let argument = ''
    endif
  elseif expand('%:t') == '[BufExplorer]'
    let command = 'BufExplorer'
    let argument = ''
  elseif exists('g:proj_running') && g:proj_running == bufnr('%')
    let command = 'Project'
    let argument = expand('%:p')
  elseif &filetype == 'netrw'
    let command = 'edit'
    let argument = bufname('%')
  elseif &buftype == 'quickfix'
    let command = 'cwindow'
    let argument = ''
  endif
  if exists('command')
    call s:jump_to_window(a:session, tabpagenr(), winnr())
    call add(a:session, 'let s:bufnr_save = bufnr("%")')
    call add(a:session, 'let s:cwd_save = getcwd()')
    if argument == ''
      call add(a:session, command)
    else
      let argument = fnamemodify(argument, ':~')
      if &sessionoptions =~ '\<slash\>'
        let argument = substitute(argument, '\', '/', 'g')
      endif
      call add(a:session, command . ' ' . fnameescape(argument))
    endif
    call add(a:session, 'execute "bwipeout" s:bufnr_save')
    call add(a:session, 'execute "cd" fnameescape(s:cwd_save)')
    return 1
  endif
endfunction

function! s:jump_to_window(session, tabpage, window)
  if &sessionoptions =~ '\<tabpages\>'
    call add(a:session, 'tabnext ' . a:tabpage)
  endif
  call add(a:session, a:window . 'wincmd w')
endfunction

function! s:nerdtree_persist()
  " Remember current working directory and whether NERDTree is loaded.
  if exists('b:NERDTreeRoot')
    return 'NERDTree ' . fnameescape(b:NERDTreeRoot.path.str()) . ' | only'
  else
    return 'cd ' . fnameescape(getcwd())
  endif
endfunction

" Automatic commands to manage the default session. {{{1

function! xolox#session#auto_load() " {{{2
  if g:session_autoload == 'no'
    return
  endif
  " Check that the user has started Vim without editing any files.
  if bufnr('$') == 1 && bufname('%') == '' && !&mod && getline(1, '$') == ['']
    " Check whether a session matching the user-specified server name exists.
    if v:servername !~ '^\cgvim\d*$'
      for session in xolox#session#get_names()
        if v:servername ==? session
          call xolox#session#open_cmd(session, '')
          return
        endif
      endfor
    endif
    " Default to the last used session or the session named `default'?
    let session = s:last_session_recall()
    let path = xolox#session#name_to_path(session)
    if filereadable(path) && !s:session_is_locked(path)
      let msg = "Do you want to restore your %s editing session?"
      let label = session != 'default' ? 'last used' : 'default'
      if s:prompt(printf(msg, label), 'g:session_autoload')
        call xolox#session#open_cmd(session, '')
      endif
    endif
  endif
endfunction

function! xolox#session#auto_save() " {{{2
  if !v:dying && g:session_autosave != 'no'
    let name = s:get_name('', 0)
    if name != ''
      let msg = "Do you want to save your editing session before quitting Vim?"
      if s:prompt(msg, 'g:session_autosave')
        call xolox#session#save_cmd(name, '')
      endif
    endif
  endif
endfunction

function! xolox#session#auto_unlock() " {{{2
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

" Commands that enable users to manage multiple sessions. {{{1

function! s:prompt(msg, var)
  let value = eval(a:var)
  if value == 'yes' || (type(value) != type('') && value)
    return 1
  else
    let format = "%s Note that you can permanently disable this dialog by adding the following line to your %s script:\n\n\t:let %s = 'no'"
    let vimrc = xolox#misc#os#is_win() ? '~\_vimrc' : '~/.vimrc'
    let prompt = printf(format, a:msg, vimrc, a:var)
    return confirm(prompt, "&Yes\n&No", 1, 'Question') == 1
  endif
endfunction

function! xolox#session#open_cmd(name, bang) abort " {{{2
  let name = s:select_name(s:unescape(a:name), 'restore')
  if name != ''
    let starttime = xolox#misc#timer#start()
    let path = xolox#session#name_to_path(name)
    if !filereadable(path)
      let msg = "session.vim %s: The %s session at %s doesn't exist!"
      call xolox#misc#msg#warn(msg, g:xolox#session#version, string(name), fnamemodify(path, ':~'))
    elseif a:bang == '!' || !s:session_is_locked(path, 'OpenSession')
      let oldcwd = s:nerdtree_persist()
      call xolox#session#close_cmd(a:bang, 1, name != s:get_name('', 0))
      let s:oldcwd = oldcwd
      call s:lock_session(path)
      execute 'source' fnameescape(path)
      call s:last_session_persist(name)
      call xolox#misc#timer#stop("session.vim %s: Opened %s session in %s.", g:xolox#session#version, string(name), starttime)
      call xolox#misc#msg#info("session.vim %s: Opened %s session from %s.", g:xolox#session#version, string(name), fnamemodify(path, ':~'))
    endif
  endif
endfunction

function! xolox#session#view_cmd(name) abort " {{{2
  let name = s:select_name(s:get_name(s:unescape(a:name), 0), 'view')
  if name != ''
    let path = xolox#session#name_to_path(name)
    if !filereadable(path)
      let msg = "session.vim %s: The %s session at %s doesn't exist!"
      call xolox#misc#msg#warn(msg, g:xolox#session#version, string(name), fnamemodify(path, ':~'))
    else
      execute 'tab drop' fnameescape(path)
      call xolox#misc#msg#info("session.vim %s: Viewing session script %s.", g:xolox#session#version, fnamemodify(path, ':~'))
    endif
  endif
endfunction

function! xolox#session#save_cmd(name, bang) abort " {{{2
  let starttime = xolox#misc#timer#start()
  let name = s:get_name(s:unescape(a:name), 1)
  let path = xolox#session#name_to_path(name)
  let friendly_path = fnamemodify(path, ':~')
  if a:bang == '!' || !s:session_is_locked(path, 'SaveSession')
    let lines = []
    call xolox#session#save_session(lines, friendly_path)
    if xolox#misc#os#is_win() && &ssop !~ '\<unix\>'
      call map(lines, 'v:val . "\r"')
    endif
    if writefile(lines, path) != 0
      let msg = "session.vim %s: Failed to save %s session to %s!"
      call xolox#misc#msg#warn(msg, g:xolox#session#version, string(name), friendly_path)
    else
      call s:last_session_persist(name)
      call xolox#misc#timer#stop("session.vim %s: Saved %s session in %s.", g:xolox#session#version, string(name), starttime)
      call xolox#misc#msg#info("session.vim %s: Saved %s session to %s.", g:xolox#session#version, string(name), friendly_path)
      let v:this_session = path
      call s:lock_session(path)
    endif
  endif
endfunction

function! xolox#session#delete_cmd(name, bang) " {{{2
  let name = s:select_name(s:unescape(a:name), 'delete')
  if name != ''
    let path = xolox#session#name_to_path(name)
    if !filereadable(path)
      let msg = "session.vim %s: The %s session at %s doesn't exist!"
      call xolox#misc#msg#warn(msg, g:xolox#session#version, string(name), fnamemodify(path, ':~'))
    elseif a:bang == '!' || !s:session_is_locked(path, 'DeleteSession')
      if delete(path) != 0
        let msg = "session.vim %s: Failed to delete %s session at %s!"
        call xolox#misc#msg#warn(msg, g:xolox#session#version, string(name), fnamemodify(path, ':~'))
      else
        call s:unlock_session(path)
        let msg = "session.vim %s: Deleted %s session at %s."
        call xolox#misc#msg#info(msg, g:xolox#session#version, string(name), fnamemodify(path, ':~'))
      endif
    endif
  endif
endfunction

function! xolox#session#close_cmd(bang, silent, save_allowed) abort " {{{2
  let name = s:get_name('', 0)
  if name != ''
    if a:save_allowed
      let msg = "Do you want to save your current editing session before closing it?"
      if s:prompt(msg, 'g:session_autosave')
        call xolox#session#save_cmd(name, a:bang)
      endif
    else
      call xolox#misc#msg#debug("session.vim %s: Session reset requested, not saving changes to session ..", g:xolox#session#version)
    endif
    call s:unlock_session(xolox#session#name_to_path(name))
  endif
  " Close al but the current tab page.
  if tabpagenr('$') > 1
    execute 'tabonly' . a:bang
  endif
  " Close all but the current window.
  if winnr('$') > 1
    execute 'only' . a:bang
  endif
  " Start editing a new, empty buffer.
  execute 'enew' . a:bang
  " Close all but the current buffer.
  let bufnr_keep = bufnr('%')
  for bufnr in range(1, bufnr('$'))
    if buflisted(bufnr) && bufnr != bufnr_keep
      execute 'silent bdelete' bufnr
    endif
  endfor
  " Restore working directory (and NERDTree?) from before :OpenSession.
  if exists('s:oldcwd')
    execute s:oldcwd
    unlet s:oldcwd
  endif
  if v:this_session == ''
    if !a:silent
      let msg = "session.vim %s: Closed session."
      call xolox#misc#msg#info(msg, g:xolox#session#version)
    endif
  else
    if !a:silent
      let msg = "session.vim %s: Closed session %s."
      call xolox#misc#msg#info(msg, g:xolox#session#version, fnamemodify(v:this_session, ':~'))
    endif
    let v:this_session = ''
  endif
  return 1
endfunction

function! xolox#session#restart_cmd(bang, args) abort " {{{2
  if !has('gui_running')
    " In console Vim we can't start a new Vim and kill the old one...
    let msg = "session.vim %s: The :RestartVim command only works in graphical Vim!"
    call xolox#misc#msg#warn(msg, g:xolox#session#version)
  else
    let name = s:get_name('', 0)
    if name == '' | let name = 'restart' | endif
    call xolox#session#save_cmd(name, a:bang)
    let progname = xolox#misc#escape#shell(fnameescape(v:progname))
    let command = progname . ' -c ' . xolox#misc#escape#shell('OpenSession\! ' . fnameescape(name))
    let args = matchstr(a:args, '^\s*|\s*\zs.\+$')
    if !empty(args)
      let command .= ' -c ' . xolox#misc#escape#shell(args)
    endif
    if xolox#misc#os#is_win()
      execute '!start' command
    else
      let cmdline = []
      for variable in g:session_restart_environment
        call add(cmdline, variable . '=' . xolox#misc#escape#shell(fnameescape(eval('$' . variable))))
      endfor
      call add(cmdline, command)
      call add(cmdline, printf("--cmd ':set enc=%s'", escape(&enc, '\ ')))
      silent execute '!' join(cmdline, ' ') '&'
    endif
    call xolox#session#close_cmd(a:bang, 0, 1)
    silent quitall
  endif
endfunction

" Miscellaneous functions. {{{1

function! s:unescape(s) " {{{2
  return substitute(a:s, '\\\(.\)', '\1', 'g')
endfunction

function! s:select_name(name, action) " {{{2
  if a:name != ''
    return a:name
  endif
  let sessions = sort(xolox#session#get_names())
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
    if xolox#misc#path#equals(this_session_dir, g:session_directory)
      let name = xolox#session#path_to_name(v:this_session)
    endif
  endif
  return name != '' ? name : a:use_default ? 'default' : ''
endfunction

function! xolox#session#name_to_path(name) " {{{2
  let directory = xolox#misc#path#absolute(g:session_directory)
  let filename = xolox#misc#path#encode(a:name) . '.vim'
  return xolox#misc#path#merge(directory, filename)
endfunction

function! xolox#session#path_to_name(path) " {{{2
  return xolox#misc#path#decode(fnamemodify(a:path, ':t:r'))
endfunction

function! xolox#session#get_names() " {{{2
  let directory = xolox#misc#path#absolute(g:session_directory)
  let filenames = split(glob(xolox#misc#path#merge(directory, '*.vim')), "\n")
  return map(filenames, 'xolox#session#path_to_name(v:val)')
endfunction

function! xolox#session#complete_names(arg, line, pos) " {{{2
  let names = filter(xolox#session#get_names(), 'v:val =~ a:arg')
  return map(names, 'fnameescape(v:val)')
endfunction

" Default to last used session: {{{2

function! s:last_session_file()
  let directory = xolox#misc#path#absolute(g:session_directory)
  return xolox#misc#path#merge(directory, 'last-session.txt')
endfunction

function! s:last_session_persist(name)
  if g:session_default_to_last
    if writefile([a:name], s:last_session_file()) != 0
      call xolox#misc#msg#warn("session.vim %s: Failed to persist name of last used session!", g:xolox#session#version)
    endif
  endif
endfunction

function! s:last_session_recall()
  if g:session_default_to_last
    let fname = s:last_session_file()
    if filereadable(fname)
      return readfile(fname)[0]
    endif
  endif
  return 'default'
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
        let msg = "session.vim %s: The %s session is locked by another Vim instance named %s! Use :%s! to override."
        let name = string(fnamemodify(a:session_path, ':t:r'))
        call xolox#misc#msg#warn(msg, g:xolox#session#version, name, string(lines[0]), a:1)
      endif
      return 1
    endif
  endif
endfunction

" vim: ts=2 sw=2 et
