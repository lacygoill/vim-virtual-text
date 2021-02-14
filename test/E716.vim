vim9script noclear

exe 'so ' .. expand('<sfile>:p:h') .. '/setup.vim'

tab sp
e
:1tabnext
# `E716` should not be raised
q
