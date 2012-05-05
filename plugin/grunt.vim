" grunt - A plugin to help working with Grunt
" Maintainer: mklabs

if exists("g:loaded_grunt") || v:version < 700 || &cp
  finish
endif

let g:loaded_grunt = 1

let s:cwd = getcwd()
let s:dirname=expand('<sfile>:h:h')

"
" todo:
"   - should probably do the grunt detect only on buff enter, instead of
"   once at VimEnter. Mappings and commands would only take effect on
"   current buffer
"   - if it gets longer (and it will), put the bulk of the plugin in
"   autoload.
"

"
" Utility
"

" spawn helper, basic wrapper to :!
function! s:Grunt(bang, args)
  let cmd = 'grunt --no-color '.a:args
  execute ':!'.cmd
endfunction

" Set base path utility, for easier `:find`, super simplified here.
" Should be improved. (:h find)
function! s:SetBasePath()
  " current directory + tasks and bin
  let path = ['', 'tasks/', 'bin/']
  :let &path=join(path, ',')
endfunction

" Used in gf command. Set includeexpr to append .js / .coffee files
" automatically. Make it possible to easily 'goto file' with tasks.
" (:h includeexpr).
function! s:InitFind()
  " :let &includeexpr=substitute(v:fname,'$','\\.js','g')

  " or simply
  :let &suffixesadd=".js,.coffee"
endfunction

" completion filter helper. borrowed to vim-rails:
" https://github.com/tpope/vim-rails/blob/master/autoload/rails.vim#L2162-2173
function! s:completion_filter(results,A)
  let results = sort(type(a:results) == type("") ? split(a:results,"\n") : copy(a:results))
  call filter(results,'v:val !~# "\\~$"')
  let filtered = filter(copy(results),'s:startswith(v:val,a:A)')
  if !empty(filtered) | return filtered | endif
  let regex = s:gsub(a:A,'[^/]','[&].*')
  let filtered = filter(copy(results),'v:val =~# "^".regex')
  if !empty(filtered) | return filtered | endif
  let regex = s:gsub(a:A,'.','[&].*')
  let filtered = filter(copy(results),'v:val =~# regex')
  return filtered
endfunction

" same here: https://github.com/tpope/vim-rails/blob/master/autoload/rails.vim#L35-41
function! s:gsub(str,pat,rep)
  return substitute(a:str,'\v\C'.a:pat,a:rep,'g')
endfunction

function! s:startswith(string,prefix)
  return strpart(a:string, 0, strlen(a:prefix)) ==# a:prefix
endfunction

function! s:error(str)
  echohl ErrorMsg
  echo  a:str
  echohl None
endfunction


" Setup openURL command at starup, borrowed to vim-rails
" https://github.com/tpope/vim-rails/blob/master/autoload/rails.vim#L1331-1345
function! s:initOpenURL()
  if !exists(":OpenURL")
    if has("gui_mac") || has("gui_macvim") || exists("$SECURITYSESSIONID")
      command -bar -nargs=1 OpenURL :!open <args>
    elseif has("gui_win32")
      command -bar -nargs=1 OpenURL :!start cmd /cstart /b <args>
    elseif executable("sensible-browser")
      command -bar -nargs=1 OpenURL :!sensible-browser <args>
    elseif executable('launchy')
      command -bar -nargs=1 OpenURL :!launchy <args>
    elseif executable('git')
      command -bar -nargs=1 OpenURL :!git web--browse <args>
    endif
  endif
endfunction

"
" Commands
"

" define commands loaded only on GruntDetect
function! s:GruntCommands()
  command! -bar -bang -nargs=* -complete=customlist,s:Complete_task Gtask call s:GTask(<bang>0,<q-args>)
  command! -bar -nargs=1 -bang -complete=customlist,s:Complete_docs Gdoc call s:GDoc(<bang>0,<q-args>)
endfunction

"
" Completion
"
" will probably write a node script to get this back from github api
" for now, a simple
"
"     $('.js-slide-to[id]').map(function(i, el) { return el.innerText; });
"
" in my devtool at https://github.com/cowboy/grunt/tree/master/docs
function! s:Complete_docs(A,L,P)
  let pages = [
    \ 'api', 'api_config', 'api_fail', 'api_file', 'api_log',
    \ 'api_task', 'api_template', 'api_utils', 'contributing',
    \ 'example_gruntfiles', 'exit_codes', 'faq', 'getting_started',
    \ 'helpers_directives', 'plugins', 'task_concat', 'task_init',
    \ 'task_lint', 'task_min', 'task_qunit', 'task_server',
    \ 'toc', 'types_of_tasks']

  return s:completion_filter(pages, a:A)
endfunction

" Completion helper for Gtask. Globs the tasks/ directory for any
" .js or .coffee files. This currently implies and won't work if pathogen is
" not used. But pathogen is pretty common in vim config now, should probably
" add a few safeguard checks.
function! s:Complete_task(A,L,P)
  let taskjs = pathogen#glob('tasks/**/*.js')
  let taskcs = pathogen#glob('tasks/**/*.coffee')
  " really? array concat in vimscript simply means using the + operator
  " love it
  return s:completion_filter(taskjs + taskcs, a:A)
endfunction


" Task command -> :Gdoc
"
" Open a given grunt doc page in default browser
" borrowed to vim-rails
function! s:GDoc(bang, page)
  let url = 'https://github.com/cowboy/grunt/blob/master/docs/'.a:page.'.md'
  echo '... Opening ' . url . ' ...'
  if exists(':OpenURL')
    exe 'OpenURL '.url
  else
    return s:error('No :OpenURL command found')
  endif
endfunction

"
" Task command -> :Gtask
" todo:
"   - see if it has `/` in it. In which case, prepend the tasks/ dir
"   - see if it has an extension. If not, append .js / .coffee.
"   - ensure we always open a new buffer (or reuse opened buffer if task
"   already in buffer list)
function! s:GTask(bang, args)
  " now a simple wrapper to `:edit` in tasks dir. Not even checking if
  " file exists, completion, etc. to be improved
  " - should edit / create buffer instead

  " for now, we handle just the first arg
  let file = get(split(a:args), 0)

  " dumb-guess of task path, this is now always the cwd/tasks/:file
  let task = join([s:cwd, file], '/')

  let taskname = fnamemodify(task, ':.')

  let readable = filereadable(task)

  if !readable
    " todo: put this in function. add plaholder ability, replace
    " placeholder based on taskname.
    echo "No ". taskname ." task created yet"
    let template=join([s:dirname, 'template', 'task.js'], '/')
    echo "Loading from template ".template
    exe "edit" task
    exe "silent! 0r" template
    setlocal filetype=javascript
    return
  endif

  execute "edit" task
endfunction


"
" Initialization
"

" detect a grunt project, a little crude right now, just checking cwd's
" gruntfile exists todo: it shoulld detect on both cwd (when starting
" vim from console) and actual vim path (eg. vim ./some/nested/path) to
" handle both case
function! s:Detect()
  let gruntfile = join([s:cwd, 'grunt.js'], '/')
  if filereadable(gruntfile)
    return s:GruntInit()
  endif

  let gruntfile = join([s:cwd, 'Gruntfile.js'], '/')
  if filereadable(gruntfile)
    return s:GruntInit()
  endif

  let gruntfile = join([s:cwd, 'grunt.coffee'], '/')
  if filereadable(gruntfile)
    return s:GruntInit()
  endif

  let gruntfile = join([s:cwd, 'Gruntfile.coffee'], '/')
  if filereadable(gruntfile)
    return s:GruntInit()
  endif
endfunction


" Grunt init
function! s:GruntInit()
  " narrow the path for easier find
  call s:SetBasePath()
  " setup openURL command
  call s:initOpenURL()
  " grunt-project commands
  call s:GruntCommands()
  " grunt-project specific gf extension
  call s:InitFind()
endfunction

augroup gruntDetect
  autocmd!
  autocmd VimEnter * call s:Detect()
augroup END

command! -bar -bang -nargs=* Grunt call s:Grunt(<bang>0,<q-args>)


" todo: should integrate with other plugins
"
" like NERDTree, auto refresh on some command


" vim:set sw=2 sts=2:

