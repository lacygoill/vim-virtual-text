vim9script noclear

const LOGFILE: string = '/tmp/virtual_text_tests.log'
delete(LOGFILE)

var testdir: string = expand('<sfile>:p:h')
var current_script: string = expand('<sfile>:t')
var tests: list<string> = testdir
    ->readdir((n: string): bool => n =~ '.vim$' && n != current_script, {sort: 'none'})

# Don't write this in a function.
# We don't want Vim to abort on an error; we want all the tests to be run.
# TODO: In the future, Vim9 might abort when a sourced script encounters an error.{{{
#
# If that happens, we might need to run `:source` from a legacy function/script.
# How does Vim handle this issue in its own test suite?
#}}}
for test in tests
    v:errors = []
    exe 'so ' .. testdir .. '/' .. test
    if v:errors != []
        writefile(v:errors, LOGFILE)
    endif
    popup_clear(true)
    sil! only
    sil! tabonly
    sil :%bw!
endfor

if filereadable(LOGFILE) && !readfile(LOGFILE)->empty()
    exe 'sp ' .. LOGFILE
else
    # Some of our  plugins in our config  cause the message to  be erased; let's
    # prevent that by triggering a hit-enter prompt.
    echo ' '
    echom 'all tests passed'
endif

