" Vim script
" Author: Peter Odding
" Last Change: July 30, 2010
" URL: http://peterodding.com/code/vim/session/
" Version: 1.2.2

" Support for automatic update using the GLVS plug-in.
" GetLatestVimScripts: 3150 1 :AutoInstall: session.zip

" Don't load the plug-in when &compatible is set or it was already loaded.
if &cp || exists('g:loaded_session')
  finish
endif

" Automatic loading of the default session is disabled by default.
if !exists('g:session_autoload')
  let g:session_autoload = 0
endif

" Automatic saving of the default session is disabled by default.
if !exists('g:session_autosave')
  let g:session_autosave = 0
endif

" The default directory where session scripts are stored.
if !exists('g:session_directory')
  if has('win32') || has('win64')
    let g:session_directory = '~\vimfiles\sessions'
  else
    let g:session_directory = '~/.vim/sessions'
  endif
endif

" Make sure the session scripts directory exists and is writable.
let s:directory = fnamemodify(g:session_directory, ':p')
if !isdirectory(s:directory)
  call mkdir(s:directory, 'p')
endif
if filewritable(s:directory) != 2
  let s:msg = "session.vim: The sessions directory %s isn't writable!"
  call xolox#warning(s:msg, string(s:directory))
  unlet s:msg
  finish
endif
unlet s:directory

" Define automatic commands for automatic session management.
augroup PluginSession
  autocmd!
  au VimEnter * nested call session#auto_load()
  au VimLeavePre * call session#auto_save()
  au VimLeavePre * call session#auto_unlock()
  au TabEnter,WinEnter * call session#auto_dirty_check()
augroup END

" Define commands that enable users to manage multiple named sessions.
command! -bar -bang -nargs=? -complete=customlist,session#complete_names OpenSession call session#open_cmd(<q-args>, <q-bang>)
command! -bar -bang -nargs=? -complete=customlist,session#complete_names SaveSession call session#save_cmd(<q-args>, <q-bang>)
command! -bar -bang -nargs=? -complete=customlist,session#complete_names DeleteSession call session#delete_cmd(<q-args>, <q-bang>)
command! -bar -bang CloseSession call session#close_cmd(<q-bang>, 0)
command! -bar -bang RestartVim call session#restart_cmd(<q-bang>)

" Don't reload the plug-in once it has loaded successfully.
let g:loaded_session = 1

" vim: ts=2 sw=2 et
