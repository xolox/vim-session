" Vim script
" Author: Peter Odding
" Last Change: May 13, 2013
" URL: http://peterodding.com/code/vim/session/

let g:xolox#session#version = '2.3'

call xolox#misc#compat#check('session', 3)

" Public API for session persistence. {{{1

" The functions in this fold take a single list argument in which the Vim
" script lines are stored that should be executed to restore the (relevant
" parts of the) current Vim editing session. The only exception to this is
" xolox#session#save_session() which expects the target filename as 2nd
" argument:

function! xolox#session#save_session(commands, filename) " {{{2
  let is_all_tabs = xolox#session#include_tabs()
  call add(a:commands, '" ' . a:filename . ':')
  call add(a:commands, '" Vim session script' . (is_all_tabs ? '' : ' for a single tab page') . '.')
  call add(a:commands, '" Created by session.vim ' . g:xolox#session#version . ' on ' . strftime('%d %B %Y at %H:%M:%S.'))
  call add(a:commands, '" Open this file in Vim and run :source % to restore your session.')
  call add(a:commands, '')
  if is_all_tabs
    call add(a:commands, 'set guioptions=' . escape(&go, ' "\'))
    call add(a:commands, 'silent! set guifont=' . escape(&gfn, ' "\'))
  endif
  call xolox#session#save_globals(a:commands)
  if is_all_tabs
    call xolox#session#save_features(a:commands)
    call xolox#session#save_colors(a:commands)
  endif
  call xolox#session#save_qflist(a:commands)
  call xolox#session#save_state(a:commands)
  if is_all_tabs
    call xolox#session#save_fullscreen(a:commands)
  endif
  if is_all_tabs
    call add(a:commands, 'doautoall SessionLoadPost')
  else
    call add(a:commands, 'windo doautocmd SessionLoadPost')
    call s:jump_to_window(a:commands, tabpagenr(), winnr())
  endif
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
    if !xolox#session#include_tabs()
      " Customize the output of :mksession for tab scoped sessions.
      let buffers = tabpagebuflist()
      call map(lines, 's:tabpage_filter(buffers, v:val)')
    endif
    call extend(a:commands, map(lines, 's:state_filter(v:val)'))
    return 1
  finally
    let &sessionoptions = ssop_save
    call delete(tempfile)
  endtry
endfunction

function! s:eat_trailing_line(session, line) " {{{3
  " Remove matching, trailing strings from a list of strings.
  if a:session[-1] == a:line
    call remove(a:session, -1)
  endif
endfunction

function! s:tabpage_filter(buffers, line) " {{{3
  " Change output of :mksession if for single tab page.
  if a:line =~ '^badd +\d\+ '
    " The :mksession command adds all open buffers to a session even for tab
    " scoped sessions. That makes sense, but we want only the buffers in the
    " tab page to be included. That's why we filter out any references to the
    " rest of the buffers from the script generated by :mksession.
    let pathname = matchstr(a:line, '^badd +\d\+ \zs.*')
    let bufnr = bufnr('^' . pathname . '$')
    if index(a:buffers, bufnr) == -1
      return '" ' . a:line
    endif
  elseif a:line =~ '^let v:this_session\s*='
    " The :mksession command unconditionally adds the global v:this_session
    " variable definition to the session script, but we want a differently
    " scoped variable for tab scoped sessions.
    return substitute(a:line, 'v:this_session', 't:this_session', 'g')
  endif
  " Preserve all other lines.
  return a:line
endfunction

function! s:state_filter(line) " {{{3
  " Various changes to the output of :mksession.
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
    if xolox#session#include_tabs()
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
  " If we detected a special window and the argument to the command is not a
  " pathname, this variable should be set to false to disable normalization.
  let do_normalize_path = 1
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
  elseif exists('b:ConqueTerm_Idx')
    let command = 'ConqueTerm'
    let argument = g:ConqueTerm_Terminals[b:ConqueTerm_Idx]['program_name']
    let do_normalize_path = 0
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
      if do_normalize_path
        let argument = fnamemodify(argument, ':~')
        if xolox#session#options_include('slash')
          let argument = substitute(argument, '\', '/', 'g')
        endif
      endif
      call add(a:session, command . ' ' . fnameescape(argument))
    endif
    call add(a:session, 'if bufnr("%") != s:bufnr_save')
    call add(a:session, '  execute "bwipeout" s:bufnr_save')
    call add(a:session, 'endif')
    call add(a:session, 'execute "cd" fnameescape(s:cwd_save)')
    return 1
  endif
endfunction

function! s:jump_to_window(session, tabpage, window)
  if xolox#session#include_tabs()
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
  " Automatically load the default / last used session when Vim starts.
  if g:session_autoload == 'no'
    return
  endif
  " Check that the user has started Vim without editing any files.
  let current_buffer_is_empty = (&modified == 0 && getline(1, '$') == [''])
  let buffer_list_is_empty = (bufnr('$') == 1 && bufname('%') == '')
  let buffer_list_is_persistent = (index(xolox#misc#option#split(&viminfo), '%') >= 0)
  if current_buffer_is_empty && (buffer_list_is_empty || buffer_list_is_persistent)
    " Check whether a session matching the user-specified server name exists.
    if v:servername !~ '^\cgvim\d*$'
      for session in xolox#session#get_names()
        if v:servername ==? session
          call xolox#session#open_cmd(session, '', 'OpenSession')
          return
        endif
      endfor
    endif
    " Default to the last used session or the default session?
    let [has_last_session, session] = s:get_last_or_default_session()
    let path = xolox#session#name_to_path(session)
    if (g:session_default_to_last == 0 || has_last_session) && filereadable(path) && !s:session_is_locked(path)
      " Compose the message for the prompt.
      let is_default_session = (session == g:session_default_name)
      let msg = printf("Do you want to restore your %s editing session%s?",
            \ is_default_session ? 'default' : 'last used',
            \ is_default_session ? '' : printf(' (%s)', session))
      " Prepare the list of choices.
      let choices = ['&Yes', '&No']
      if !is_default_session
        call add(choices, '&Forget')
      endif
      " Prompt the user (if not configured otherwise).
      let choice = s:prompt(msg, choices, 'g:session_autoload')
      if choice == 1
        call xolox#session#open_cmd(session, '', 'OpenSession')
      elseif choice == 3
        call s:last_session_forget()
      endif
    endif
  endif
endfunction

function! xolox#session#auto_save() " {{{2
  " We won't save the session if Vim is not terminating normally.
  if v:dying
    return
  endif
  " We won't save the session if auto-save is explicitly disabled.
  if g:session_autosave == 'no'
    return
  endif
  " Get the name of the active session (if any).
  let name = s:get_name('', 0)
  " If no session is active and the user doesn't have any sessions yet, help
  " them get started by suggesting to create the default session.
  if empty(name) && empty(xolox#session#get_names())
    let name = g:session_default_name
  endif
  " Prompt the user to save the active or first session?
  if !empty(name)
    let is_tab_scoped = xolox#session#is_tab_scoped()
    let msg = "Do you want to save your %s before quitting Vim?"
    if s:prompt(printf(msg, xolox#session#get_label(name)), ['&Yes', '&No'], 'g:session_autosave') == 1
      if is_tab_scoped
        call xolox#session#save_tab_cmd(name, '', 'SaveTabSession')
      else
        call xolox#session#save_cmd(name, '', 'SaveSession')
      endif
    endif
  endif
endfunction

function! xolox#session#auto_save_periodic() " {{{2
  " Automatically save the session every few minutes?
  if g:session_autosave_periodic > 0
    let interval = g:session_autosave_periodic * 60
    let next_save = s:session_last_flushed + interval
    if next_save > localtime()
      call xolox#misc#msg#debug("session.vim %s: Skipping this beat of 'updatetime' (it's not our time yet).", g:xolox#session#version)
    else
      call xolox#misc#msg#debug("session.vim %s: This is our beat of 'updatetime'!", g:xolox#session#version)
      let name = s:get_name('', 0)
      if !empty(name)
        if xolox#session#is_tab_scoped()
          call xolox#session#save_tab_cmd(name, '', 'SaveTabSession')
        else
          call xolox#session#save_cmd(name, '', 'SaveSession')
        endif
      endif
    endif
  endif
endfunction

function! s:flush_session()
  let s:session_last_flushed = localtime()
endfunction

if !exists('s:session_last_flushed')
  call s:flush_session()
endif

function! xolox#session#auto_unlock() " {{{2
  " Automatically unlock all sessions when Vim quits.
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

function! s:prompt(msg, choices, option_name)
  let option_value = eval(a:option_name)
  if option_value == 'yes'
    return 1
  elseif option_value == 'no'
    return 0
  else
    if g:session_verbose_messages
      let format = "%s Note that you can permanently disable this dialog by adding the following line to your %s script:\n\n\t:let %s = 'no'"
      let prompt = printf(format, a:msg, xolox#misc#os#is_win() ? '~\_vimrc' : '~/.vimrc', a:option_name)
    else
      let prompt = a:msg
    endif
    return confirm(prompt, join(a:choices, "\n"), 1, 'Question')
  endif
endfunction

function! xolox#session#open_cmd(name, bang, command) abort " {{{2
  let name = s:select_name(s:unescape(a:name), 'restore')
  if name != ''
    let starttime = xolox#misc#timer#start()
    let path = xolox#session#name_to_path(name)
    if !filereadable(path)
      let msg = "session.vim %s: The %s session at %s doesn't exist!"
      call xolox#misc#msg#warn(msg, g:xolox#session#version, string(name), fnamemodify(path, ':~'))
    elseif a:bang == '!' || !s:session_is_locked(path, a:command)
      let oldcwd = s:nerdtree_persist()
      call xolox#session#close_cmd(a:bang, 1, name != s:get_name('', 0), a:command)
      if xolox#session#include_tabs()
        let g:session_old_cwd = oldcwd
      else
        let t:session_old_cwd = oldcwd
      endif
      call s:lock_session(path)
      execute 'source' fnameescape(path)
      call s:last_session_persist(name)
      call s:flush_session()
      let session_type = xolox#session#include_tabs() ? 'global' : 'tab scoped'
      call xolox#misc#timer#stop("session.vim %s: Opened %s %s session in %s.", g:xolox#session#version, session_type, string(name), starttime)
      call xolox#misc#msg#info("session.vim %s: Opened %s %s session from %s.", g:xolox#session#version, session_type, string(name), fnamemodify(path, ':~'))
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

function! xolox#session#save_cmd(name, bang, command) abort " {{{2
  let starttime = xolox#misc#timer#start()
  let name = s:get_name(s:unescape(a:name), 1)
  let path = xolox#session#name_to_path(name)
  let friendly_path = fnamemodify(path, ':~')
  if a:bang == '!' || !s:session_is_locked(path, a:command)
    let lines = []
    call xolox#session#save_session(lines, friendly_path)
    if xolox#misc#os#is_win() && !xolox#session#options_include('unix')
      call map(lines, 'v:val . "\r"')
    endif
    if writefile(lines, path) != 0
      let msg = "session.vim %s: Failed to save %s session to %s!"
      call xolox#misc#msg#warn(msg, g:xolox#session#version, string(name), friendly_path)
    else
      call s:last_session_persist(name)
      call s:flush_session()
      let label = xolox#session#get_label(name)
      call xolox#misc#timer#stop("session.vim %s: Saved %s in %s.", g:xolox#session#version, label, starttime)
      call xolox#misc#msg#info("session.vim %s: Saved %s to %s.", g:xolox#session#version, label, friendly_path)
      if xolox#session#include_tabs()
        let v:this_session = path
      else
        let t:this_session = path
      endif
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

function! xolox#session#close_cmd(bang, silent, save_allowed, command) abort " {{{2
  let is_all_tabs = xolox#session#include_tabs()
  let name = s:get_name('', 0)
  if name != ''
    if a:save_allowed
      let msg = "Do you want to save your current %s before closing it?"
      let label = xolox#session#get_label(name)
      if s:prompt(printf(msg, label), ['&Yes', '&No'], 'g:session_autosave') == 1
        call xolox#session#save_cmd(name, a:bang, a:command)
      endif
    else
      call xolox#misc#msg#debug("session.vim %s: Session reset requested, not saving changes to session ..", g:xolox#session#version)
    endif
    call s:unlock_session(xolox#session#name_to_path(name))
  endif
  " Close al but the current tab page?
  if is_all_tabs && tabpagenr('$') > 1
    execute 'tabonly' . a:bang
  endif
  " Close all but the current window.
  if winnr('$') > 1
    execute 'only' . a:bang
  endif
  " Start editing a new, empty buffer.
  execute 'enew' . a:bang
  " Close all but the current buffer.
  let bufnr_save = bufnr('%')
  let all_buffers = is_all_tabs ? range(1, bufnr('$')) : tabpagebuflist()
  for bufnr in all_buffers
    if buflisted(bufnr) && bufnr != bufnr_save
      execute 'silent bdelete' bufnr
    endif
  endfor
  " Restore working directory (and NERDTree?) from before :OpenSession.
  if is_all_tabs && exists('g:session_old_cwd')
    execute g:session_old_cwd
    unlet g:session_old_cwd
  elseif !is_all_tabs && exists('t:session_old_cwd')
    execute t:session_old_cwd
    unlet t:session_old_cwd
  endif
  call s:flush_session()
  if !a:silent
    let msg = "session.vim %s: Closed %s."
    let label = xolox#session#get_label(xolox#session#find_current_session())
    call xolox#misc#msg#info(msg, g:xolox#session#version, label)
  endif
  if xolox#session#is_tab_scoped()
    let t:this_session = ''
  else
    let v:this_session = ''
  endif
  return 1
endfunction

function! xolox#session#open_tab_cmd(name, bang, command) abort " {{{2
  try
    call xolox#session#change_tab_options()
    call xolox#session#open_cmd(a:name, a:bang, a:command)
  finally
    call xolox#session#restore_tab_options()
  endtry
endfunction

function! xolox#session#save_tab_cmd(name, bang, command) abort " {{{2
  try
    call xolox#session#change_tab_options()
    call xolox#session#save_cmd(a:name, a:bang, a:command)
  finally
    call xolox#session#restore_tab_options()
  endtry
endfunction

function! xolox#session#append_tab_cmd(name, bang, count, command) abort " {{{2
  try
    call xolox#session#change_tab_options()
    execute printf('%stabnew', a:count == 94919 ? '' : a:count)
    call xolox#session#open_cmd(a:name, a:bang, a:command)
  finally
    call xolox#session#restore_tab_options()
  endtry
endfunction

function! xolox#session#close_tab_cmd(bang, command) abort " {{{2
  let save_allowed = xolox#session#is_tab_scoped()
  try
    call xolox#session#change_tab_options()
    call xolox#session#close_cmd(a:bang, 0, save_allowed, a:command)
  finally
    call xolox#session#restore_tab_options()
  endtry
endfunction

function! xolox#session#restart_cmd(bang, args) abort " {{{2
  if !has('gui_running')
    " In console Vim we can't start a new Vim and kill the old one...
    let msg = "session.vim %s: The :RestartVim command only works in graphical Vim!"
    call xolox#misc#msg#warn(msg, g:xolox#session#version)
  else
    " Save the current session (if there is no active
    " session we will create a session called "restart").
    let name = s:get_name('', 0)
    if name == '' | let name = 'restart' | endif
    call xolox#session#save_cmd(name, a:bang, 'RestartVim')
    " Generate the Vim command line.
    let progname = xolox#misc#escape#shell(fnameescape(s:find_executable()))
    let command = progname . ' -g -c ' . xolox#misc#escape#shell('OpenSession\! ' . fnameescape(name))
    let args = matchstr(a:args, '^\s*|\s*\zs.\+$')
    if !empty(args)
      let command .= ' -c ' . xolox#misc#escape#shell(args)
    endif
    " Close the session, releasing the session lock.
    call xolox#session#close_cmd(a:bang, 0, 1, 'RestartVim')
    " Start the new Vim instance.
    if xolox#misc#os#is_win()
      " On Microsoft Windows.
      execute '!start' command
    else
      " On anything other than Windows (UNIX like).
      let cmdline = []
      for variable in g:session_restart_environment
        call add(cmdline, variable . '=' . xolox#misc#escape#shell(fnameescape(eval('$' . variable))))
      endfor
      call add(cmdline, command)
      call add(cmdline, printf("--cmd ':set enc=%s'", escape(&enc, '\ ')))
      silent execute '!' join(cmdline, ' ') '&'
    endif
    " Close Vim.
    silent quitall
  endif
endfunction

function! s:find_executable()
  let progname = v:progname
  if has('macunix')
    " Special handling for Mac OS X where MacVim is usually not on the $PATH.
    let segments = xolox#misc#path#split($VIMRUNTIME)
    if segments[-3:] == ['Resources', 'vim', 'runtime']
      let progname = xolox#misc#path#join(segments[0:-4] + ['MacOS', 'Vim'])
    endif
  endif
  return progname
endfunction

" Miscellaneous functions. {{{1

function! s:unescape(s) " {{{2
  " Undo escaping of special characters (preceded by a backslash).
  let s = substitute(a:s, '\\\(.\)', '\1', 'g')
  " Expand any environment variables in the user input.
  let s = substitute(s, '\(\$[A-Za-z0-9_]\+\)', '\=expand(submatch(1))', 'g')
  return s
endfunction

function! s:select_name(name, action) " {{{2
  if a:name != ''
    return a:name
  endif
  let sessions = sort(xolox#session#get_names())
  if empty(sessions)
    return g:session_default_name
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
  if name == ''
    for variable in ['t:this_session', 'v:this_session']
      if exists(variable)
        let value = eval(variable)
        if value != ''
          if xolox#misc#path#equals(fnamemodify(value, ':p:h'), g:session_directory)
            let name = xolox#session#path_to_name(value)
            break
          endif
        endif
      endif
    endfor
  endif
  return name != '' ? name : a:use_default ? g:session_default_name : ''
endfunction

function! xolox#session#name_to_path(name) " {{{2
  let directory = xolox#misc#path#absolute(g:session_directory)
  let filename = xolox#misc#path#encode(a:name) . g:session_extension
  return xolox#misc#path#merge(directory, filename)
endfunction

function! xolox#session#path_to_name(path) " {{{2
  return xolox#misc#path#decode(fnamemodify(a:path, ':t:r'))
endfunction

function! xolox#session#get_names() " {{{2
  let directory = xolox#misc#path#absolute(g:session_directory)
  let filenames = split(glob(xolox#misc#path#merge(directory, '*' . g:session_extension)), "\n")
  return map(filenames, 'xolox#session#path_to_name(v:val)')
endfunction

function! xolox#session#complete_names(arg, line, pos) " {{{2
  let names = filter(xolox#session#get_names(), 'v:val =~ a:arg')
  return map(names, 'fnameescape(v:val)')
endfunction

function! xolox#session#is_tab_scoped() " {{{2
  " Determine whether the current session is tab scoped or global.
  return exists('t:this_session')
endfunction

function! xolox#session#find_current_session() " {{{2
  " Find the name of the current session.
  let pathname = xolox#session#is_tab_scoped() ? t:this_session : v:this_session
  return xolox#session#path_to_name(pathname)
endfunction

function! xolox#session#get_label(name) " {{{2
  if xolox#session#is_tab_scoped()
    let name = xolox#session#path_to_name(t:this_session)
    if a:name == name
      return printf('tab scoped session %s', string(a:name))
    endif
  endif
  return printf('global session %s', string(a:name))
endfunction

function! xolox#session#options_include(value) " {{{2
  return index(xolox#misc#option#split(&sessionoptions), a:value) >= 0
endfunction

" Tab scoped sessions: {{{2

function! xolox#session#include_tabs() " {{{3
  return xolox#session#options_include('tabpages')
endfunction

function! xolox#session#change_tab_options() " {{{3
  " Save the original value of 'sessionoptions'.
  let s:ssop_save = &sessionoptions
  " Only persist the current tab page.
  set sessionoptions-=tabpages
  " Don't persist the size and position of the Vim window.
  set ssop-=winpos ssop-=resize
endfunction

function! xolox#session#restore_tab_options() " {{{3
  " Restore the original value of 'sessionoptions'.
  if exists('s:ssop_save')
    let &ssop = s:ssop_save
    unlet s:ssop_save
  endif
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

function! s:last_session_forget()
  let last_session_file = s:last_session_file()
  if filereadable(last_session_file) && delete(last_session_file) != 0
    call xolox#misc#msg#warn("session.vim %s: Failed to delete name of last used session!", g:xolox#session#version)
  endif
endfunction

function! s:get_last_or_default_session()
  let last_session_file = s:last_session_file()
  let has_last_session = filereadable(last_session_file)
  if g:session_default_to_last && has_last_session
    let lines = readfile(last_session_file)
    return [has_last_session, lines[0]]
  else
    return [has_last_session, g:session_default_name]
  endif
endfunction

" Lock file management: {{{2

if !exists('s:lock_files')
  let s:lock_files = []
endif

function! s:vim_instance_id()
  let id = {'pid': getpid()}
  if !empty(v:servername)
    let id['servername'] = v:servername
  endif
  if !xolox#session#include_tabs()
    let id['tabpage'] = tabpagenr()
  endif
  return id
endfunction

function! s:lock_session(session_path)
  let lock_file = a:session_path . '.lock'
  if writefile([string(s:vim_instance_id())], lock_file) == 0
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
    let this_instance = s:vim_instance_id()
    let other_instance = eval(get(readfile(lock_file), 0, '{}'))
    let name = string(fnamemodify(a:session_path, ':t:r'))
    let arguments = [g:xolox#session#version, name]
    if this_instance == other_instance
      " Session belongs to current Vim instance and tab page.
      return 0
    elseif this_instance['pid'] == other_instance['pid']
      if has_key(other_instance, 'tabpage')
        let msg = "session.vim %s: The %s session is already loaded in tab page %s."
        call add(arguments, other_instance['tabpage'])
      else
        let msg = "session.vim %s: The %s session is already loaded in this Vim."
      endif
    else
      let msg = "session.vim %s: The %s session is locked by another Vim instance %s."
      if has_key(other_instance, 'servername')
        call add(arguments, 'named ' . other_instance['servername'])
      else
        call add(arguments, 'with PID ' . other_instance['pid'])
      endif
    endif
    if exists('a:1')
      let msg .= " Use :%s! to override."
      call add(arguments, a:1)
    endif
    call call('xolox#misc#msg#warn', [msg] + arguments)
    return 1
  endif
endfunction

" vim: ts=2 sw=2 et
