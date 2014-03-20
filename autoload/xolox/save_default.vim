function! xolox#save_default#get_git_branch() " {{{2
  " Return current branch as a list, normalized to ascii word characters.
  " Failure returns an empty list.
  let branch = system('git rev-parse --abbrev-ref HEAD')
  if v:shell_error != 0
    return []
  elseif branch =~ 'fatal: Not a git repository'
    return []
  elseif branch =~ 'HEAD'
    return []
  endif
  let branch = substitute(branch , '\n$', '', '')
  let branch = substitute(branch , '\W', '-', 'g')
  return [branch]
endfunction
