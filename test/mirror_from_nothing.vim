vim9script noclear

exe 'so ' .. expand('<sfile>:p:h') .. '/setup.vim'

# Test that we  can mirror a popup even  if there is no longer  any existing one
# from which we can derive the options.
enew
sp
e %%

