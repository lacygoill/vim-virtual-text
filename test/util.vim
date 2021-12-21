vim9script noclear

const SETUP_SCRIPT: string = expand('<sfile>:p:h') .. '/setup.vim'

def g:Reset()
    silent! only
    silent! tabonly
    silent :% bwipeout!
    execute 'source ' .. SETUP_SCRIPT
enddef
