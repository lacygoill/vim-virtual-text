vim9script noclear

exe 'so ' .. expand('<sfile>:p:h') .. '/setup.vim'
exe 'so ' .. expand('<sfile>:p:h') .. '/setup.vim'

# even though we've invoked `VirtualTextAdd()` twice for 4 lines, we should only
# have 4 popups, and not 8
popup_list()->len()->assert_equal(4)
# and on one of those 4 lines, there should be only 1 text property; not 2
search('Ozymandias')->prop_list()->len()->assert_equal(1)
