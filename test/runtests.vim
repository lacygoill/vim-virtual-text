vim9 noclear

const LOGFILE: string = '/tmp/virtual_text_tests.log'

var testdir: string = expand('<sfile>:p:h')
var current_script: string = expand('<sfile>:t')
var tests: list<string> =
    testdir->readdir((n) => n =~ '.vim$' && n != current_script)

def RunTests()
    for test in tests
        v:errors = []
        try
            exe 'so ' .. testdir .. '/' .. test
        catch
        endtry
        if v:errors != []
            writefile(v:errors, LOGFILE)
        endif
        popup_clear(true)
        sil! only
        sil! tabonly
        :%bw!
    endfor
enddef
RunTests()
