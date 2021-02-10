vim9 noclear

const SETUP_SCRIPT: string = expand('<sfile>:p:h') .. '/setup.vim'

def g:Reset()
    sil! only
    sil! tabonly
    sil :%bw!
    exe 'so ' .. SETUP_SCRIPT
enddef

