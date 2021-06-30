vim9script noclear

execute 'source ' .. expand('<sfile>:p:h') .. '/setup.vim'

# Test that we  can mirror a popup even  if there is no longer  any existing one
# from which we can derive the options.
enew
split
edit %%

