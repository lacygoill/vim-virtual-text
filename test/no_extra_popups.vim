vim9 noclear

exe 'so ' .. expand('<sfile>:p:h') .. '/setup.vim'

# Test that no extra undesirable popups are created when we split a window
# which doesn't display any virtual text.
new
popup_list()->len()->assert_equal(4)

