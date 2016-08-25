" Git branch info
" Last change: March 20 2010
" Version> 0.1.5
" Maintainer: Eustáquio 'TaQ' Rangel
" License: GPL
" URL: git://github.com/taq/vim-git-branch-info.git

let s:menu_on = 0
let s:checking = ""
let s:rebase_msg = 'Rebasing,merging,bisecting?'
let b:gbi_git_dir = ""
let b:gbi_git_load_branch = ""

augroup GitBranchInfoAuto
    au!
    autocmd BufEnter * call s:GitBranchInfoInit()
augroup END

if exists("g:git_branch_check_write")
    autocmd BufWriteCmd * call s:GitBranchInfoWriteCheck()
endif

function! GitBranchInfoString()
    let l:tokens = GitBranchInfoTokens()
    if len(l:tokens) == 1 " no git here
        call s:GitBranchInfoRemoveMenu()
        return l:tokens[0]
    end
    let s:current = l:tokens[0]  " the current branch is the first one
    let l:branches = l:tokens[1] " the other branches are the last one
    let l:remotes = l:tokens[2]  " remote branches
    if exists("g:git_branch_status_around")
        if strlen(g:git_branch_status_around) == 2
            let l:around = split(g:git_branch_status_around, '\zs')
        else
            let l:around = ["", ""]
        endif
    else
        let l:around = ["[", "]"]
    endif
    if exists("g:git_branch_status_text")
        let l:text = g:git_branch_status_text
    else
        let l:text = " Git "
    endif
    if s:menu_on == 0
        call s:GitBranchInfoShowMenu(l:tokens[0], l:tokens[1], l:tokens[2])
    endif
    if exists("g:git_branch_status_head_current")
        let l:tail = ""
    else
        let l:tail = l:around[0] . join(l:branches, ",") . l:around[1]
    return l:text . l:around[0] . s:current . l:around[1] . l:tail
endfunction

function! GitBranchInfoLoadBranch()
    return b:gbi_git_load_branch
endfunction

function! GitBranchInfoTokens()
    if !s:GitBranchInfoCheckGitDir()
        let s:current = ''
        if exists("g:git_branch_status_nogit")
            return g:git_branch_status_nogit
        else
            return "No git."
        endif
    endif
    if !s:GitBranchInfoCheckReadable()
        let s:current = ''
        return [s:current, [], []]
    endif
    try
        let l:contents = readfile(b:gbi_git_dir . "/HEAD", '', 1)[0]
        if stridx(l:contents, "/") < 0
            let s:current = s:rebase_msg
            return [s:current, [], []]
        endif
        let s:current = substitute(l:contents, "^.*refs\/heads\/", "", "")
        if exists("g:git_branch_status_head_current")
            let l:heads = []
        else
            let l:heads = split(glob(b:gbi_git_dir . "/refs/heads/*"), "\n")
            let l:mp = 'substitute(v:val, b:gbi_git_dir . "/refs/heads/", "", "")'
            call map(l:heads, l:mp)
            call sort(filter(l:heads, 'v:val !~ s:current'))
        endif
        if exists("g:git_branch_status_ignore_remotes")
            let l:remotes = []
        else
            let l:remotes = split(glob(b:gbi_git_dir . "/refs/remotes/*/**"), "\n")
            let l:mp = 'substitute(v:val, b:gbi_git_dir . "/refs/remotes/", "", "")'
            call sort(map(l:remotes, l:mp))
        endif
        let l:checking = s:current . join(l:heads) . join(l:remotes)
        if l:checking != s:checking && has("gui")
            call s:GitBranchInfoRenewMenu(s:current, l:heads, l:remotes)
        endif
        let s:checking = l:checking
    catch /.*/
        let s:current = '???'
        let l:heads = []
        let l:remotes = []
    endtry
    return [s:current, l:heads, l:remotes]
endfunction

function! <SID>GitBranchInfoCheckout(branch)
    let l:tokens = GitBranchInfoTokens()
    let l:checkout = "git\ checkout\ " . a:branch
    let l:where = substitute(b:gbi_git_dir, ".git$", "", "")
    if strlen(l:where) > 0
        let l:cmd = "!cd\ " . l:where . ";\ " . l:checkout
    else
        let l:cmd = "!" . l:checkout
    endif
    exe l:cmd
    call s:GitBranchInfoRenewMenu(l:tokens[0], l:tokens[1], l:tokens[2])
endfunction

function! <SID>GitBranchInfoFetch(remote)
    let l:tokens = GitBranchInfoTokens()
    let l:fetch = "git\ fetch\ " . a:remote
    let l:where = substitute(b:gbi_git_dir, ".git$", "", "")
    if strlen(l:where) > 0
        let l:cmd = "!cd\ " . l:where . ";\ " . l:fetch
    else
        let l:cmd = "!" . l:fetch
    endif
    exe l:cmd
endfunction

function! s:GitBranchInfoCheckGitDir()
    return exists("b:gbi_git_dir") && !empty(b:gbi_git_dir)
endfunction

function! s:GitBranchInfoCheckReadable()
    return filereadable(b:gbi_git_dir . "/HEAD")
endfunction

function! s:GitBranchInfoWriteCheck()
    let l:writecmd = v:cmdbang == 1 ? "write!" : "write"
    " not controlled by Git, write this thing!
    if !s:GitBranchInfoCheckGitDir()
        exec l:writecmd expand("<afile>")
        return 1
    endif
    " just write normal buffers
    let l:buftype = getbufvar(bufnr("%"), '&buftype')
    if strlen(l:buftype) > 0
        echohl WarningMsg
        let l:msg = "Not writing if it's not a normal buffer"
        echo l:msg . " (found a " . l:buftype . " buffer)."
        echohl None
        return 0
    endif
    " if the branches are the same, no problem
    let l:current = GitBranchInfoTokens()[0]
    if l:current == b:gbi_git_load_branch
        exec l:writecmd expand("<afile>")
        return 1
    endif
    " if we're rebasing, merging or bisecting, write the file
    if l:current == s:rebase_msg
        exec l:writecmd expand("<afile>")
        return 1
    endif
    " ask what we will do
    echohl ErrorMsg
    let l:answer = tolower(input("Loaded from \'" . b:gbi_git_load_branch . "\' branch but saving on \'" . l:current . "\' branch, confirm [y/n]? ", "n"))
    echohl None
    let l:msg = "File " . (l:answer == "y" ? "" : "NOT ") . "saved on branch \'" . l:current . "\'."
    " ok, save even with different branches
    if l:answer == "y"
        exec l:writecmd expand("<afile>")
    endif
    " show message
    echohl WarningMsg
    echo l:msg
    echohl None
    return l:answer == "y"
endfunction

function! s:GitBranchInfoInit()
    call s:GitBranchInfoFindDir()
    let l:current = GitBranchInfoTokens()
    let b:gbi_git_load_branch = l:current[0]
endfunction

function! s:GitBranchInfoFindDir()
    let l:bufname = getcwd() . "/" . expand("%:t")
    let l:buflist = strlen(l:bufname) > 0 ? split(l:bufname, "/") : [""]
    let l:prefix = l:bufname =~ "^/" ? "/" : ""
    let b:gbi_git_dir = ""
    while len(l:buflist) > 0
        let l:pre_path = l:prefix.join(l:buflist,"/") . l:prefix
        let l:path = l:pre_path . ".git"
        if !empty(finddir(l:path))
            let b:gbi_git_dir = l:path
            break
        elseif filereadable(l:path)
            let b:gbi_git_dir = l:pre_path . split(readfile(l:path, "", 1)[0], "gitdir: ")[0]
            break
        endif
        call remove(l:buflist, -1)
    endwhile
    return b:gbi_git_dir
endfunction

function! s:GitBranchInfoGitDir()
    return b:gbi_git_dir
endfunction

function! s:GitBranchInfoRenewMenu(current, heads, remotes)
    call s:GitBranchInfoRemoveMenu()
    call s:GitBranchInfoShowMenu(a:current, a:heads, a:remotes)
endfunction

function! s:GitBranchInfoShowMenu(current, heads, remotes)
    if !has("gui")
        return
    endif
    let s:menu_on = 1
    let l:compare = a:current
    let l:current = [a:current]
    let l:heads = len(a:heads) > 0 ? a:heads : []
    let l:remotes = len(a:remotes) > 0 ? a:remotes : []
    let l:locals = sort(extend(l:current, l:heads))
    for l:branch in l:locals
        let l:moption = (l:branch == l:compare ? "Working\\ \\on\\ " : "Checkout\\ ") . l:branch
        let l:mcom = (l:branch == l:compare ? ":echo 'Already\ on\ branch\ \''" . l:branch . "\''.'<CR>" : "call <SID>GitBranchInfoCheckout('" . l:branch . "')<CR><CR>")
        exe ":menu <silent> Plugin.Git\\ Info." . l:moption . " :" . l:mcom
    endfor
    exe ":menu <silent> Plugin.Git\\ Info.-Local- :"
    let l:lastone = ""
    for l:branch in l:remotes
        let l:tokens = split(l:branch, "/")
        if l:tokens[0] == l:lastone
            continue
        endif
        let l:lastone = l:tokens[0]
        exe "menu <silent> Plugin.Git\\ Info.Fetch\\ " . l:tokens[0] . " :call <SID>GitBranchInfoFetch('" . l:tokens[0] . "')<CR><CR>"
    endfor
endfunction

function! s:GitBranchInfoRemoveMenu()
    if !has("gui") || s:menu_on == 0
        return
    endif
    exe ":unmenu Plugin.Git\\ Info"
    let s:menu_on = 0
endfunction
