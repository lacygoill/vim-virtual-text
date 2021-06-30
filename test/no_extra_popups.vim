vim9script noclear

execute 'source ' .. expand('<sfile>:p:h') .. '/setup.vim'
execute 'source ' .. expand('<sfile>:p:h') .. '/util.vim'

# Test that no extra undesirable popups are  created when we split a window, and
# the new one doesn't display any virtual text.
new
popup_list()->len()->assert_equal(4)

# Test that no extra undesirable popups are  created when we load a buffer which
# doesn't contain any virtual text in a split which used to contain virtual texts.
Reset()
vsplit
enew
popup_list()->len()->assert_equal(4)

