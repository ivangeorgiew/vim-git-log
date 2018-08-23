" The MIT License (MIT)
"
" Copyright (c) 2016 Junegunn Choi
"
" Permission is hereby granted, free of charge, to any person obtaining a copy
" of this software and associated documentation files (the "Software"), to deal
" in the Software without restriction, including without limitation the rights
" to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
" copies of the Software, and to permit persons to whom the Software is
" furnished to do so, subject to the following conditions:
"
" The above copyright notice and this permission notice shall be included in
" all copies or substantial portions of the Software.
"
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
" IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
" FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
" AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
" LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
" OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
" THE SOFTWARE.

function! s:warn(message)
  echohl WarningMsg | echom a:message | echohl None
endfunction

function! s:shrug()
  call s:warn('¯\_(ツ)_/¯')
endfunction

function! gv#sha(...)
  return matchstr(get(a:000, 0, getline('.')), '^[^a-f0-9]*\zs[a-f0-9]\{6,}')
endfunction

function! s:browse(url)
  call netrw#BrowseX(b:git_origin.a:url, 0)
endfunction

function! s:gbrowse()
  let sha = gv#sha()
  if empty(sha)
    return s:shrug()
  endif
  execute 'Gbrowse' sha
endfunction

function! s:type(visual)
  if a:visual
    let shas = filter(map(getline("'<", "'>"), 'gv#sha(v:val)'), '!empty(v:val)')
    if len(shas) < 2
      return [0, 0]
    endif
    return ['diff', fugitive#repo().git_command('diff', shas[-1], shas[0])]
  endif

  if exists('b:git_origin')
    let syn = synIDattr(synID(line('.'), col('.'), 0), 'name')
    if syn == 'gvGitHub'
      return ['link', '/issues/'.expand('<cword>')[1:]]
    elseif syn == 'gvTag'
      let tag = matchstr(getline('.'), '(tag: \zs[^ ,)]\+')
      return ['link', '/releases/'.tag]
    endif
  endif

  let sha = gv#sha()
  if !empty(sha)
    return ['commit', 'fugitive://'.b:git_dir.'//'.sha]
  endif
  return [0, 0]
endfunction

function! s:split(tab)
  if a:tab
    execute 'tabnew'
  elseif getwinvar(winnr('$'), 'gv')
    $wincmd w
    enew
  else
    vertical botright new
  endif
  let w:gv = 1
endfunction

function! s:open(visual, ...)
  let [type, target] = s:type(a:visual)

  if empty(type)
    return s:shrug()
  elseif type == 'link'
    return s:browse(target)
  endif

  call s:split(a:0)
  if type == 'commit'
    execute 'e' escape(target, ' ')
    nnoremap <silent> <buffer> gb :Gbrowse<cr>
  elseif type == 'diff'
    call s:scratch()
    call s:fill(target)
    setf diff
  endif
  nnoremap <silent> <buffer> q :close<cr>
  let bang = a:0 ? '!' : ''
  if exists('#User#GV'.bang)
    execute 'doautocmd <nomodeline> User GV'.bang
  endif
  wincmd p
  echo
endfunction

function! s:dot()
  let sha = gv#sha()
  return empty(sha) ? '' : ':Git  '.sha."\<s-left>\<left>"
endfunction

function! s:syntax()
  setf GV
  syn clear
  syn match gvSymbols /^\([\*\\|\/]\| \)\+/ contains=gvAll,gvLine nextgroup=gvInfo
  syn match gvAll     /\*/ contained
  syn match gvLine    /[\\|\/]/ contained
  syn match gvInfo    /[a-f0-9]\{6,}\s\+".\+"\s\+([^)]\+)$/ contained contains=gvSha,gvAuthor,gvDate
  syn match gvSha     /[a-f0-9]\{6,}/ contained
  syn match gvAuthor  /".\+"/ contained
  syn match gvDate    /([^)]\+)/ contained
  hi def link gvAuthor Include
  hi def link gvSha    Number
  hi def link gvDate   Identifier
  hi def link gvAll    Conditional
  hi def link gvLine   Type

  syn match gvAdded     "^\W*\zsA\t.*"
  syn match gvDeleted   "^\W*\zsD\t.*"
  hi def link gvAdded    diffAdded
  hi def link gvDeleted  diffRemoved

  syn match diffAdded   "^+.*"
  syn match diffRemoved "^-.*"
  syn match diffLine    "^@.*"
  syn match diffFile    "^diff\>.*"
  syn match diffFile    "^+++ .*"
  syn match diffNewFile "^--- .*"
  hi def link diffFile    Type
  hi def link diffNewFile diffFile
  hi def link diffAdded   Identifier
  hi def link diffRemoved Special
  hi def link diffFile    Type
  hi def link diffLine    Statement
endfunction

function! s:maps()
  nnoremap <silent> <buffer> q     :$wincmd w <bar> close<cr>
  nnoremap <silent> <buffer> gb    :call <sid>gbrowse()<cr>
  nnoremap <silent> <buffer> <cr>  :call <sid>open(0)<cr>
  nnoremap <silent> <buffer> o     :call <sid>open(0)<cr>
  nnoremap <silent> <buffer> <C-t> :call <sid>open(0, 1)<cr>
  xnoremap <silent> <buffer> <cr>  :<c-u>call <sid>open(1)<cr>
  xnoremap <silent> <buffer> o     :<c-u>call <sid>open(1)<cr>
  xnoremap <silent> <buffer> <C-t> :<c-u>call <sid>open(1, 1)<cr>
endfunction

function! s:setup(git_dir, git_origin)
  if (line('$') != 1 || getline(1) != '') && &ft != 'GV'
    execute 'tabnew'
  endif
  call s:scratch()

  if exists('g:fugitive_github_domains')
    let domain = join(map(extend(['github.com'], g:fugitive_github_domains),
          \ 'escape(substitute(split(v:val, "://")[-1], "/*$", "", ""), ".")'), '\|')
  else
    let domain = '.*github.\+'
  endif
  " https://  github.com  /  junegunn/gv.vim  .git
  " git@      github.com  :  junegunn/gv.vim  .git
  let pat = '^\(https\?://\|git@\)\('.domain.'\)[:/]\([^@:/]\+/[^@:/]\{-}\)\%(.git\)\?$'
  let origin = matchlist(a:git_origin, pat)
  if !empty(origin)
    let scheme = origin[1] =~ '^http' ? origin[1] : 'https://'
    let b:git_origin = printf('%s%s/%s', scheme, origin[2], origin[3])
  endif
  let b:git_dir = a:git_dir
endfunction

function! s:git_dir()
  if empty(get(b:, 'git_dir', ''))
    return fugitive#extract_git_dir(expand('%:p'))
  endif
  return b:git_dir
endfunction

function! s:scratch()
  setlocal buftype=nofile bufhidden=wipe noswapfile
endfunction

function! s:fill(cmd)
  setlocal modifiable
  silent execute '0r' escape('!'.a:cmd, '%')
  silent execute '%s/\s\+$//e'
  normal! gg
  setlocal nomodifiable
endfunction

function! s:tracked(fugitive_repo, file)
  call system(a:fugitive_repo.git_command('ls-files', '--error-unmatch', a:file))
  return !v:shell_error
endfunction

function! s:check_buffer(fugitive_repo, current)
  if empty(a:current)
    throw 'untracked buffer'
  elseif !s:tracked(a:fugitive_repo, a:current)
    throw a:current.' is untracked'
  endif
endfunction

function! s:log_opts(fugitive_repo, bang, visual, line1, line2)
  if a:visual || a:bang
    let current = expand('%')
    call s:check_buffer(a:fugitive_repo, current)
    return a:visual ? [printf('-L%d,%d:%s', a:line1, a:line2, current)] : ['--follow', current]
  endif
  return ['--graph']
endfunction

function! s:list(fugitive_repo, log_opts)
  let default_opts = ['--color=never', '--graph', '--full-history', '--date=relative', '--format=%h "%an" (%cd) %n%s%n']
  let git_args = ['log'] + default_opts + a:log_opts
  let git_log_cmd = call(a:fugitive_repo.git_command, git_args, a:fugitive_repo)

  let repo_short_name = fnamemodify(substitute(a:fugitive_repo.dir(), '[\\/]\.git[\\/]\?$', '', ''), ':t')
  let bufname = repo_short_name.' '.join(a:log_opts)
  silent exe (bufexists(bufname) ? 'buffer' : 'file') fnameescape(bufname)

  call s:fill(git_log_cmd)
  setlocal wrap tabstop=8 cursorline iskeyword+=#

  if !exists(':Gbrowse')
    doautocmd <nomodeline> User Fugitive
  endif
  call s:maps()
  call s:syntax()
  redraw
  echo 'o: open split / C-t: open tab / gb: Gbrowse / q: quit'
endfunction

function! s:trim(arg)
  let arg = substitute(a:arg, '\s*$', '', '')
  return arg =~ "^'.*'$" ? substitute(arg[1:-2], "''", '', 'g')
     \ : arg =~ '^".*"$' ? substitute(substitute(arg[1:-2], '""', '', 'g'), '\\"', '"', 'g')
     \ : substitute(substitute(arg, '""\|''''', '', 'g'), '\\ ', ' ', 'g')
endfunction

function! gv#shellwords(arg)
  let words = []
  let contd = 0
  for token in split(a:arg, '\%(\%(''\%([^'']\|''''\)\+''\)\|\%("\%(\\"\|[^"]\)\+"\)\|\%(\%(\\ \|\S\)\+\)\)\s*\zs')
    let trimmed = s:trim(token)
    if contd
      let words[-1] .= trimmed
    else
      call add(words, trimmed)
    endif
    let contd = token !~ '\s\+$'
  endfor
  return words
endfunction

function! s:gl(buf, visual)
  if !exists(':Gllog')
    return
  endif
  tab split
  silent execute a:visual ? "'<,'>" : "" 'Gllog'
  call setloclist(0, insert(getloclist(0), {'bufnr': a:buf}, 0))
  b #
  lopen
  xnoremap <buffer> o :call <sid>gld()<cr>
  nnoremap <buffer> o <cr><c-w><c-w>
  nnoremap <buffer> O :call <sid>gld()<cr>
  nnoremap <buffer> q :tabclose<cr>
  call matchadd('Conceal', '^fugitive://.\{-}\.git//')
  call matchadd('Conceal', '^fugitive://.\{-}\.git//\x\{7}\zs.\{-}||')
  setlocal concealcursor=nv conceallevel=3 nowrap
  let w:quickfix_title = 'o: open / o (in visual): diff / O: open (tab) / q: quit'
endfunction

function! s:gld() range
  let [to, from] = map([a:firstline, a:lastline], 'split(getline(v:val), "|")[0]')
  execute (tabpagenr()-1).'tabedit' escape(to, ' ')
  if from !=# to
    execute 'vsplit' escape(from, ' ')
    windo diffthis
  endif
endfunction

function! s:gv(bang, visual, line1, line2, args) abort
  if !exists('g:loaded_fugitive')
    return s:warn('fugitive not found')
  endif

  let git_dir = s:git_dir()
  if empty(git_dir)
    return s:warn('not in git repo')
  endif

  let fugitive_repo = fugitive#repo(git_dir)
  let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd' : 'cd'
  let cwd = getcwd()
  let root = fugitive_repo.tree()
  try
    if cwd !=# root
      execute cd escape(root, ' ')
    endif
    if a:args =~ '?$'
      if len(a:args) > 1
        return s:warn('invalid arguments')
      endif
      call s:check_buffer(fugitive_repo, expand('%'))
      call s:gl(bufnr(''), a:visual)
    else
      let log_opts = extend(gv#shellwords(a:args), s:log_opts(fugitive_repo, a:bang, a:visual, a:line1, a:line2))
      call s:setup(git_dir, fugitive_repo.config('remote.origin.url'))
      call s:list(fugitive_repo, log_opts)
      call fugitive#detect(@#)
    endif
  catch
    return s:warn(v:exception)
  finally
    if getcwd() !=# cwd
      cd -
    endif
  endtry
endfunction

function! s:gvcomplete(a, l, p) abort
  return fugitive#repo().superglob(a:a)
endfunction

command! -bang -nargs=* -range=0 -complete=customlist,s:gvcomplete GV call s:gv(<bang>0, <count>, <line1>, <line2>, <q-args>)
