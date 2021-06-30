vim9script noclear

execute 'source ' .. expand('<sfile>:p:h') .. '/setup.vim'

split
quit

# Check the db is correctly updated when we close a window.{{{
#
# There shouldn't be a stale window ID in the `win2popup` dictionary.
#
# For example, we don't want this:
#
#     :split | quit | echo VirtualTextDb().1.virtualText1.win2popup
#     {'1005': 1006, '1000': 1001}˜
#      ^----------^
#      should have been removed
#}}}
VirtualTextDb()
    ->items()[0][1]
    ->items()[0][1]['win2popup']
    ->keys()
    ->len()
    ->assert_equal(1)
