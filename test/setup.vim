vim9 noclear

var lines: list<string> =<< trim END
    I met a traveller from an antique land,
    Who said—“Two vast and trunkless legs of stone
    Stand in the desert. . . . Near them, on the sand,
    Half sunk a shattered visage lies, whose frown,
    And wrinkled lip, and sneer of cold command,
    Tell that its sculptor well those passions read
    Which yet survive, stamped on these lifeless things,
    The hand that mocked them, and the heart that fed;
    And on the pedestal, these words appear:
    My name is Ozymandias, King of Kings;
    Look on my Works, ye Mighty, and despair!
    Nothing beside remains. Round the decay
    Of that colossal Wreck, boundless and bare
    The lone and level sands stretch far away.”
END
writefile(lines, '/tmp/file')
sil e /tmp/file

import VirtualTextAdd from 'virtualText.vim'

var shattered_pos: list<number> = searchpos('shattered', 'n')
VirtualTextAdd({
    lnum: shattered_pos[0],
    col: shattered_pos[1],
    length: strlen('shattered'),
    text: 'broken into many pieces',
    highlight_text: 'DiffAdd',
    highlight_virtualtext: 'MoreMsg',
    })

var sneer_pos: list<number> = searchpos('sneer', 'n')
VirtualTextAdd({
    lnum: sneer_pos[0],
    col: sneer_pos[1],
    length: strlen('sneer'),
    text: 'a contemptuous or mocking smile, remark, or tone',
    highlight_text: 'DiffAdd',
    highlight_virtualtext: 'MoreMsg',
    })

var ozymandias_pos: list<number> = searchpos('Ozymandias', 'n')
VirtualTextAdd({
    lnum: ozymandias_pos[0],
    col: ozymandias_pos[1],
    length: strlen('Ozymandias'),
    text: 'Greek name for Ramesses II, pharaoh of Egypt',
    highlight_text: 'DiffAdd',
    highlight_virtualtext: 'MoreMsg',
    })

var wreck_pos: list<number> = searchpos('Wreck', 'n')
VirtualTextAdd({
    lnum: wreck_pos[0],
    col: wreck_pos[1],
    length: strlen('Wreck'),
    text: 'something that has been badly damaged or destroyed',
    highlight_text: 'DiffAdd',
    highlight_virtualtext: 'MoreMsg',
    })

