vim9 noclear

exe 'so ' .. expand('<sfile>:p:h') .. '/setup.vim'
exe 'so ' .. expand('<sfile>:p:h') .. '/util.vim'

# Test that no extra undesirable popups are  created when we split a window, and
# the new one doesn't display any virtual text.
new
popup_list()->len()->assert_equal(4)

# Test that no extra undesirable popups are  created when we load a buffer which
# doesn't contain any virtual text in a split which used to contain virtual texts.
Reset()
vs
enew
popup_list()->len()->assert_equal(4)

