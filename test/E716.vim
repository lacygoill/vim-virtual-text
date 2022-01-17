vim9script noclear

execute 'source ' .. expand('<sfile>:p:h') .. '/setup.vim'

tab split
edit
:1 tabnext
# `E716` should not be given
quit
