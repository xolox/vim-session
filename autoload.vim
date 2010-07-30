" Vim script
" Author: Peter Odding
" Last Change: July 30, 2010
" URL: http://peterodding.com/code/vim/session/

" Public API for session persistence. {{{1

" All of the functions in this fold take a single list argument in which the
" Vim script lines are stored that should be executed to restore the (relevant
" part of the) current Vim editing session.

function! session#save_config(commands) " {{{2

  " Save the Vim configuration including the GUI font and options, the
  " position and size of the Vim window, whether syntax highlighting, file
  " type detection, file type plug-ins and indentation plug-ins are enabled
  " and which color scheme is loaded. The result is a list of Vim commands
  " that restore the Vim configuration when they're executed.

  " Save the GUI font & options and the window position and size?
  if has('gui_running')
    call add(a:commands, "if has('gui_running')")
    call add(a:commands, "\tset guifont=" . escape(&gfn, ' "\'))
    call add(a:commands, "\tset guioptions=" . escape(&go, ' "\'))
    call add(a:commands, "\tset lines=" . &lines . ' columns=' . &columns)
    call add(a:commands, "\twinpos " . getwinposx() . ' ' . getwinposy())
    call extend(a:commands, ['endif', ''])
  endif

  " Save the state of syntax highlighting and file type detection.
  let features = []
  call add(features, ['syntax_on', 'syntax'])
  call add(features, ['did_load_filetypes', 'filetype'])
  call add(features, ['did_load_ftplugin', 'filetype plugin'])
  call add(features, ['did_indent_on', 'filetype indent'])
  for [global, command] in features
    call add(a:commands, 'if exists(' . string(global) . ') != ' . exists('g:' . global))
    call add(a:commands, "\t" . command . ' ' . (exists('g:' . global) ? 'on' : 'off'))
    call extend(a:commands, ['endif', ''])
  endfor

  " Save the loaded color scheme.
  if exists('g:colors_name') && type(g:colors_name) == type('') && g:colors_name != ''
    call add(a:commands, "if !exists('colors_name') || colors_name != " . string(g:colors_name))
    call add(a:commands, "\tcolorscheme " . fnameescape(g:colors_name))
    call extend(a:commands, ['endif', ''])
  endif

endfunction

function! session#save_fullscreen(commands) " {{{2
  try
    if xolox#shell#is_fullscreen()
      call add(a:commands, "")
      call add(a:commands, "if has('gui_running')")
      call add(a:commands, "\ttry")
      call add(a:commands, "\t\tcall xolox#shell#fullscreen()")
      call add(a:commands, "\tcatch " . '/^Vim\%((\a\+)\)\=:E117/')
      call add(a:commands, "\t\t\" Ignore missing full-screen plug-in.")
      call add(a:commands, "\tendtry")
      call add(a:commands, "endif")
    endif
  catch /^Vim\%((\a\+)\)\=:E117/
    " Ignore missing full-screen functionality.
  endtry
endfunction

function! session#save_state(commands) " {{{2

  " Persist the open tab pages and windows and related state like the working
  " directory, argument list, quick-fix list and the file and buffer type of
  " each visible buffer.

  " It seemed like a cool idea to persist global variables and Vim options but
  " this causes all sorts of trouble so I guess it isn't worth it...
  " call session#save_globals(a:commands)
  " call session#save_options(a:commands)

  call session#save_cwd(a:commands)
  call session#save_buffers(a:commands)
  " call extend(a:commands, split(xolox#swapchoice#change('PluginSessionSwapExistsHack', 'e'), "\n"))
  " call add(a:commands, '')
  call session#save_args(a:commands)
  call session#save_qflist(a:commands)

  " Save open tab pages & windows.
  call add(a:commands, '')
  let tabpagenr_save = tabpagenr()
  let split_cmd = 'split'
  try
    for tabpagenr in range(1, tabpagenr('$'))
      execute 'tabnext' tabpagenr
      let winnr_save = winnr()
      try
        let restore_nerd_tree = 0
        for winnr in range(1, winnr('$'))
          call add(a:commands, '')
          execute winnr . 'wincmd w'
          if has('quickfix') && &bt == 'quickfix'
            call add(a:commands, 'cwindow')
          else
            if &bt != '' && &ft == 'nerdtree'
              " Don't create a split window for the NERD tree because the
              " plug-in will create its own split window from :NERDtree.
              let restore_nerd_tree = 1
            else
              let bufname_absolute = expand('%:p')
              let bufname_friendly = expand('%:p:~')
              if winnr > 1 && !restore_nerd_tree
                let cmd = 'rightbelow ' . split_cmd
              elseif tabpagenr > 1 && winnr == 1
                let cmd = 'tabnew'
              else
                let cmd = 'edit'
              endif
              let split_cmd = winwidth(winnr) == &columns ? 'split' : 'vsplit'
              if bufname('%') =~ '^\w\+://' || filereadable(bufname_absolute)
                call add(a:commands, 'silent ' . cmd . ' ' . fnameescape(bufname_friendly))
              else
                call add(a:commands, cmd == 'edit' ? 'enew' : cmd)
                if bufname_absolute != ''
                  call add(a:commands, 'file ' . fnameescape(bufname_friendly))
                endif
              endif
              if haslocaldir()
                call add(a:commands, 'lcd ' . fnameescape(getcwd()))
              endif
              if &ft == 'netrw' && isdirectory(bufname_absolute)
                call add(a:commands, 'doautocmd BufAdd ' . fnameescape(bufname_absolute))
              else
                for option_name in ['filetype', 'buftype']
                  let option_value = eval('&' . option_name)
                  if option_value != ''
                    call add(a:commands, 'if &' . option_name . ' != ' . string(option_value))
                    call add(a:commands, "\tsetlocal " . option_name . '=' . option_value)
                    call add(a:commands, 'endif')
                  endif
                endfor
                for option_name in ['wrap', 'foldenable']
                  let option_value = eval('&' . option_name)
                  call add(a:commands, 'setlocal ' . (option_value ? '' : 'no') . option_name)
                endfor
                if &previewwindow
                  call add(a:commands, 'setlocal previewwindow')
                endif
              endif
            endif
          endif
        endfor
        if restore_nerd_tree
          call add(a:commands, 'NERDTree')
        endif
        call add(a:commands, winrestcmd())
        " Restore the topline and cursor position in each window *after*
        " creating the windows in the tab page (it doesn't work before that).
        for winnr in range(1, winnr('$'))
          execute winnr . 'wincmd w'
          call add(a:commands, winnr . 'wincmd w')
          call add(a:commands, 'call winrestview(' . string(winsaveview()) . ')')
        endfor
        if winnr != winnr_save
          call add(a:commands, winnr_save . 'wincmd w')
        endif
      finally
        execute winnr_save . 'wincmd w'
      endtry
    endfor
    if tabpagenr() != tabpagenr_save
      call add(a:commands, 'tabnext ' . tabpagenr_save)
    endif
  finally
    execute 'tabnext' tabpagenr_save
  endtry
  call add(a:commands, '')
  " Show/hide/redraw the tab line after restoring the tab pages.
  call add(a:commands, 'let &stal = ' . &stal)
  " call extend(a:commands, split(xolox#swapchoice#restore('PluginSessionSwapExistsHack'), "\n"))

endfunction

function! session#save_globals(commands) " {{{2
  let format = 'let g:%s = %s'
  for [global, value] in items(g:)
    let string = string(value)
    if string !~ '\n'
      call add(a:commands, printf(format, global, string))
    endif
    unlet value
  endfor
endfunction

function! session#save_options(commands) " {{{2
  redir => listing
  silent set all
  redir END
  let options = {}
  for name in split(listing, '\W\+')
    let name = substitute(name, '^no', '', '')
    let name = substitute(name, '=.*$', '', '')
    if exists('&' . name)
      let options[name] = 1
    endif
  endfor
  for name in sort(keys(options))
    let value = string(eval('&' . name))
    call add(a:commands, printf('let &%s = %s', name, value))
  endfor
endfunction

function! session#save_cwd(commands) " {{{2
  if !&autochdir && &sessionoptions =~ '\<curdir\>'
    let directory = fnamemodify(getcwd(), ':p')
    call add(a:commands, 'cd ' . fnameescape(directory))
  endif
endfunction

function! session#save_buffers(commands) " {{{2
  if &sessionoptions =~ '\<buffers\>'
    for bufnr in range(1, bufnr('$'))
      if bufexists(bufnr)
        let bufname = bufname(bufnr)
        if bufname != ''
          let pathname = fnamemodify(bufname, ':p:~')
          call add(a:commands, 'badd ' . fnameescape(pathname))
        endif
      endif
    endfor
    if exists('pathname')
      call add(a:commands, '')
    endif
  endif
endfunction

function! session#save_args(commands) " {{{2
  if has('listcmds')
    if argc() > 0
      " Restore argument list.
      let args = map(argv(), 'fnameescape(v:val)')
      call add(a:commands, 'silent args ' . join(args))
    else
      " Clear argument list.
      call add(a:commands, "if argc() > 0")
      call add(a:commands, "\targdelete *")
      call add(a:commands, "endif")
    endif
  endif
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
    let path = session#get_path('default')
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
  " the user has significantly changed the current tab page, which enables the
  " plug-in to not bother you with the auto-save dialog when you haven't
  " changed your session.
  if v:this_session == ''
    " Don't bother checking the layout when no session is loaded.
    return
  elseif !exists('s:cached_layouts')
    let s:cached_layouts = {}
  else
    " Clear non-existing tab pages from s:cached_layouts.
    let last_tabpage = tabpagenr('$')
    call filter(s:cached_layouts, 'v:key <= last_tabpage')
  endif
  let keys = []
  let buflist = tabpagebuflist()
  for winnr in range(1, winnr('$'))
    " Create a string that describes the state of the window {winnr}.
    let attrs = []
    call add(attrs, 'width:' . winwidth(winnr))
    call add(attrs, 'height:' . winheight(winnr))
    call add(attrs, 'buffer:' . buflist[winnr - 1])
    call add(attrs, 'wrap:' . getwinvar(winnr, '&wrap'))
    call add(attrs, 'type:' . string(getwinvar(winnr, '&ft')))
    call add(keys, join(attrs, ','))
  endfor
  let tabpagenr = tabpagenr()
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
  let name = s:select_name(a:name, 'restore')
  if name != ''
    let path = session#get_path(name)
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

function! session#save_cmd(name, bang) abort " {{{2
  let name = s:get_name(a:name, 1)
  let path = session#get_path(name)
  let friendly_path = fnamemodify(path, ':~')
  if a:bang == '!' || !s:session_is_locked(path, 'SaveSession')
    let lines = ['" ' . friendly_path . ': Vim session script.']
    call add(lines, '" Created by session.vim on ' . strftime('%d %B %Y at %H:%M:%S.'))
    call extend(lines, ['" Open this file in Vim and run :source % to restore your session.'])
    call extend(lines, ['', 'let v:this_session = ' . string(path), ''])
    call session#save_config(lines)
    call session#save_state(lines)
    call session#save_fullscreen(lines)
    call extend(lines, ['', 'doautoall SessionLoadPost', '', '" vim: ro nowrap smc=128'])
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
  let name = s:select_name(a:name, 'delete')
  if name != ''
    let path = session#get_path(name)
    if !filereadable(path)
      let msg = "session.vim: The %s session at %s doesn't exist!"
      call xolox#warning(msg, string(name), fnamemodify(path, ':~'))
    elseif a:bang == '!' || !s:session_is_locked(path, 'DeleteSession')
      if delete(path) != 0
        let msg = "session.vim: Failed to delete %s session at %s!"
        call xolox#warning(msg, string(name), fnamemodify(path, ':~'))
      else
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
    call s:unlock_session(session#get_path(name))
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
  if has('win32') || has('win64')
    execute '!start' command
  else
    let term = shellescape(fnameescape($TERM))
    let encoding = "--cmd ':set enc=" . escape(&enc, '\ ') . "'"
    execute '! TERM=' . term command encoding '&'
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
    return s:unescape(a:name)
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
      let name = fnamemodify(v:this_session, ':t:r')
    endif
  endif
  return name != '' ? name : a:use_default ? 'default' : ''
endfunction

function! session#get_path(name) " {{{2
  let directory = xolox#path#absolute(g:session_directory)
  let filename = xolox#path#encode(a:name) . '.vim'
  return xolox#path#merge(directory, filename)
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
