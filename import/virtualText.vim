vim9 noclear

const TYPE_PREFIX: string = 'virtualText'

# TODO: We need to re-create the popups in any window displaying the buffer.{{{
#
# That's what Neovim does, and I think that's what people would expect.
#
# ---
#
# Note that the 'textpropwin' option controls in which windows Vim will look for
# the text property:
#
#    > textpropwin     What window to search for the text property.  **When**
#    >                 **omitted** or invalid **the current window is used**.
#
# Also, I think that  popups are destroyed when they're tied  to a text property
# in a certain window, and that window is closed.
#
# ---
#
# Here are some tests to check whether your implementation is working:
#
#     # test 1
#     :sp
#
#     # test 2
#     :sp | q
#
#     # test 3
#     :sp
#     :q
#
#     # test 4
#     :h | q
#
#     # test 5
#     :h
#     :q
#
#     # test 6
#     :vert sp ~/.shrc
#
#     # test 7
#     :sp
#     :e ~/.shrc
#
#     # test 8
#     :e ~/.shrc | sp | e #
#
# ---
#
# We'll also need to re-create the popups if the buffer gets hidden, and then is
# later re-displayed in a window (hence `BufWinEnter`).
#
# ---
#
# In the db, we need to update the paddings when a buffer gets hidden.
#}}}

# TODO: Do we  need to  update the  db when  a window  displaying a  buffer with
# virtual texts suddenly displays another buffer?
#
# I mean, if a window no longer displays  virtual text, do we need to remove its
# id from  all `win2popup`  dictionaries, as well  as from  the `handled_winids`
# list?
#
# We could try to to listen some events but that looks brittle.
# Idea: Whenever you  iterate over virtual  texts in  the db, check  whether the
# window  ids  still  display  virtual  texts.   How?   Inspect  the  output  of
# `popup_getoptions()` for a popup displaying virtual text in that window.
# If it  no longer  has any `textprop`  key, then it  probably means  there's no
# virtual text anymore.

# TODO: We should be able  to add virtual text in an  arbitrary buffer; not just
# the current one.

# TODO: We should be able to use different highlight groups for different chunks
# of the virtual text.  This would be useful, for example, to highlight a prefix
# in a different color.

# TODO: Implement `VirtualTextClear()` to remove arbitrary virtual texts, inside
# arbitrary range of lines, in an arbitrary buffer.
#
# Signature:
#
#     # consider putting all arguments into a single dictionary
#     VirtualTextClear(
#         buffer: number,  # buffer handle, or 0 for current buffer
#         ns_id: number,   # namespace to clear, or -1 to clear all namespaces
#         lnum1: number    # start of range of lines to clear
#         lnum2: number    # end of range of lines to clear
#         )
#
# About the `ns_id` argument: it will require some refactoring.
# We'll need `VirtualTextAdd()` to map a virtual text to an arbitrary namespace.
# The db will also need to be refactored to include the namespace info.

# FIXME: Doesn't work well when joining lines with virtual texts.
#
# Example: Delete the first  3 lines (the ones which don't  have virtual texts),
# then join the  new first 2 lines  (the one which do have  virtual texts), then
# undo, and finally append  text on the first line: the  inserted text is hidden
# behind the popup.
#
# Update: Actually, can  repro just by  deleting the third line,  then appending
# text on the new 3rd line.

# TODO: We should be able to *only* pass a line number and some text to `VirtualTextAdd()`.
# In such a case, the function should not tie the virtual text to any real text.
# It should stay visible on the line as long as the latter is not removed.

# TODO: We  need to  use this  feature as  frequently as  possible, to  test and
# improve its reliability.  Any idea how we would use it?
# Suggestion: Supercharge the `m` command so that when  we set a mark on a line,
# its name is appended at the end of the line.
# Also, `ma` could simply use the text  `a`, while `m CTRL-a` could ask the user
# for a short annotation which would be appended after the mark's name.

# Init {{{1

# What does this db do?{{{
#
# It maps a buffer number to arbitrary  virtual texts, as well as a counter, and
# a list of window IDs.
#
# The counter is necessary to generate unique property type names.
# It's incremented every time a virtual text is added into to the buffer.
# It's *never* decremented; even if a virtual text is later removed.
#
# The list  of window IDs  match the windows where  the buffer is  displayed and
# where the popups have been created.
#
# A virtual text is stored as a  dictionary mapping a text property type name to
# various information which we need when we want to:
#
#    - reload the buffer
#
#    - "mirror" the virtual text in all windows displaying the buffer
#
#    - update the padding between the left border of the popup and its text,
#      because some text has been inserted/deleted
#
# Regarding the first bullet point, remember that Vim automatically removes text
# properties when a buffer is reloaded,  if they're local to this buffer.  Which
# in  turn causes  popups  tied to  text properties  to  lose their  `textprop*`
# options.  This needs to be fixed for virtual texts to persist across reloads.
#}}}
var db: dict<dict<any>> = {}

# Autocmds {{{1

augroup VirtualTextReplicatePopups | au!
    # Why `SafeState`?{{{
    #
    # Because the current buffer might be still wrong on `WinEnter`.
    # As a  result, the guard  at the top of  `MirrorPopupsOnAllWindows()` might
    # fail to correctly bail out.
    # You can observe this by executing from a window with virtual texts:
    #
    #     :echo popup_list()
    #     # some number N
    #     :tabnew
    #     :echo popup_list()
    #     # 2 * N
    #
    # In turn,  this might  cause weird  issues; like a  duplicate popup  in the
    # tabline after creating a tab page, then focusing back the previous tab.
    #}}}
    au WinEnter,BufWinEnter * au SafeState * ++once MirrorPopupsOnAllWindows()
    au BufWipeOut * RemoveWipedBuffersFromDb()
augroup END

# Functions {{{1
# Interface {{{2
export def VirtualTextAdd(props: dict<any>) #{{{3
    var text: string = props.text

    var lnum: number = props.lnum
    var col: number = props.col
    var length: number = props.length

    var highlight_real: string = has_key(props, 'highlights')
        && has_key(props.highlights, 'real')
        ? props.highlights.real
        : 'Normal'
    var highlight_virtual: string = has_key(props, 'highlights')
        && has_key(props.highlights, 'virtual')
        ? props.highlights.virtual
        : 'Normal'

    var buf: number = bufnr('%')

    # Some cleanup is necessary if we ask to add virtual text on a line where there is already one.{{{
    #
    # Close the popups (one per window displaying the buffer).
    # And remove the old text property;  otherwise some real text might be still
    # wrongly highlighted.
    #}}}
    CleanUp(buf, lnum)

    # Do *not* use `lnum` as a unique ID.{{{
    #
    # It's not a good proxy for a property type.
    # Remember that a line  on which we apply a text property  can move, e.g. if
    # we remove the line above, its address will decrease by 1.
    #
    # I think it could cause a property type to be wrongly shared between 2 texts:
    #
    #     VirtualTextAdd({lnum: 123, highlight_real: 'Foo', ...})
    #     # delete line 122
    #     VirtualTextAdd({lnum: 123, highlight_real: 'Bar', ...})
    #     # 'Foo' will *probably* be used for the 2 virtual texts
    #}}}
    var type_id: number
    if !db->has_key(buf)
        # TODO: We should remove the listener if we remove all virtual texts.
        listener_add(UpdatePadding, buf)
        extend(db, {
            [buf]: {
                counter: 1,
                virtualtexts: {},
                handled_winids: [],
                }
            })
    else
        db[buf]['counter'] = db[buf]['counter'] + 1
    endif
    # A dummy counter is probably the only reliable way to avoid conflicts.{{{
    #
    # Don't try to be smart by inspecting the length of `virtualtexts`:
    #
    #     ✘
    #     type_id = db[buf]->keys()->len()
    #
    # I suspect  that it could lead  to some conflicts when  text properties are
    # removed, making  the id  decrease.  The id  should always  increase.  Just
    # like when Vim  gives a number to a buffer,  it's always incremented.  Even
    # if a buffer has been removed, Vim doesn't reuse its number.
    #}}}
    type_id = db[buf]['counter']

    # create text property
    if prop_type_list({bufnr: buf})->index(TYPE_PREFIX .. type_id) == -1
        prop_type_add(TYPE_PREFIX .. type_id, {
            bufnr: buf,
            highlight: highlight_real,
            })
    endif
    prop_add(lnum, col, {
        bufnr: buf,
        length: length,
        type: TYPE_PREFIX .. type_id,
        })

    var left_padding: number = col([lnum, '$']) - col - length + 1
    # iterate over *all* the windows where the current buffer is displayed
    for winid in win_findbuf(buf)
        # create the popup
        # FIXME: doesn't work in another tab page
        var popup_id: number = popup_create(text, {
            fixed: true,
            highlight: highlight_virtual,
            line: -1,
            mask: [[1, left_padding, 1, 1]],
            padding: [0, 0, 0, left_padding],
            textprop: TYPE_PREFIX .. type_id,
            textpropwin: winid,
            wrap: false,
            zindex: 1,
            tabpage: win_id2tabwin(winid)[0],
            })

        # update the db
        var handled_winids: list<number> = db[buf]['handled_winids']
        if index(handled_winids, winid) == -1
            extend(handled_winids, [winid])
        endif
        extend(db[buf]['virtualtexts'], {[TYPE_PREFIX .. type_id]: {
            highlight_real: highlight_real,
            padding: left_padding,
            pos: {},
            text: text,
            win2popup: {[winid]: popup_id},
            }})
    endfor

    # Vim  automatically clears  all text  properties  from a  buffer when  it's
    # reloaded; we need to save and restore them.
    augroup VirtualTextPersistAfterReload
        au! * <buffer>
        au BufUnload <buffer> SaveTextPropertiesBeforeReload()
        au BufReadPost <buffer> RestoreTextPropertiesAfterReload()
            | RecreatePopupsInOtherWindows()
    augroup END
enddef

def g:VirtualTextDb(): dict<dict<any>> #{{{3
# only useful for debugging purpose
    return db
enddef
#}}}2
# Core {{{2
def CleanUp(buf: number, lnum: number) #{{{3
    var proplist: list<dict<any>> = prop_list(lnum)
    var idx: number
    while idx >= 0
        idx = proplist->match(TYPE_PREFIX)
        if idx == -1
            break
        endif

        # close stale popup(s)
        var stale_virtualtext: string = proplist[idx]['type']
        var stale_popups: list<number> = db[buf]['virtualtexts'][stale_virtualtext]['win2popup']->values()
        for id in stale_popups
            popup_close(id)
        endfor
        remove(proplist, idx)

        # remove stale text property
        prop_remove({
            type: stale_virtualtext,
            bufnr: buf,
            all: true
            }, lnum)
        prop_type_delete(stale_virtualtext, {bufnr: buf})
        db[buf]['virtualtexts']->remove(stale_virtualtext)
    endwhile
enddef

def UpdatePadding(buf: number, start: number, ...l: any) #{{{3
    if start > line('$') || !db->has_key(buf)
        return
    endif

    # get info about the text property implementing the virtual text on the changed line
    var prop_list: list<dict<any>> = start->prop_list()
    var i: number = prop_list->match(TYPE_PREFIX)
    if i == -1
        return
    endif
    var textprop: dict<any> = prop_list[i]

    # update the padding and the mask in *all* windows displaying the buffer
    var left_padding: number = col([start, '$']) - textprop.col - textprop.length + 1
    for winid in db[buf]['handled_winids']
        var popup_id: number = db[buf]['virtualtexts'][textprop.type]['win2popup'][winid]
        popup_setoptions(popup_id, {
            mask: [[1, left_padding, 1, 1]],
            padding: [0, 0, 0, left_padding],
            })
    endfor
enddef

def MirrorPopupsOnAllWindows() #{{{3
    var buf: string = expand('<abuf>')
    var curwin: number = win_getid()
    var curtab: number = tabpagenr()

    # return if the buffer doesn't have any virtual text
    if !db->has_key(buf)
    # or if the popups are still there
    || db[buf]['handled_winids']->index(curwin) >= 0
        return
    endif

    # iterate over the virtual texts
    # (i.e. their text, the name of their text property, and their popup ids)
    for [text, textprop, win2popup] in db[buf]['virtualtexts']
        ->mapnew((k, v) => [v.text, k, v.win2popup])
        ->values()

        # derive the options of our new popup from an existing one
        var existing_popupid: number = win2popup
            ->values()
            # let's pick the first one arbitrarily
            ->get(0)
        var opts: dict<any> = popup_getoptions(existing_popupid)
        # `popup_getoptions()` doesn't give us `mask`:
        # https://github.com/vim/vim/issues/7774
        # let's derive it from `padding`
        var left_padding: number = opts.padding[3]
        extend(opts, {
            mask: [[1, left_padding, 1, 1]],
            tabpage: curtab,
            # Why do we need to reset `textprop`?{{{
            #
            # If we don't,  the popups are invisible or  wrongly positioned when
            # executing sth like `:tab sp` in a window with virtual texts.
            #
            # The issue  is caused by  `popup_getoptions()` which fails  to give
            # the  `textprop*`  options  for  a  popup  window  displayed  in  a
            # non-focused tab page: https://github.com/vim/vim/issues/7786
            #}}}
            textprop: textprop,
            textpropwin: curwin,
            })

        # replicate popup in current window
        var new_popupid: number = popup_create(text, opts)

        # update the db so that it knows that there is a new popup to handle
        extend(win2popup, {[curwin]: new_popupid})
        extend(db[buf]['handled_winids'], [curwin])
    endfor
enddef

def SaveTextPropertiesBeforeReload() #{{{3
# the lines on which we applied text properties might have been moved,
# we need to update the db to get their new current positions
    var buf: string = expand('<abuf>')
    if !db->has_key(buf)
        return
    endif

    var types: list<string> = db[buf]['virtualtexts']->keys()
    for type in types
        try
            var newpos: dict<any> = {type: type}->prop_find('f')
            if newpos == {}
                newpos = {type: type}->prop_find('b')
            endif
            db[buf]['virtualtexts'][type]['pos'] = newpos
            remove(db[buf]['virtualtexts'][type]['pos'], 'type')
        # Vim:E971: Property type virtualText123 does not exist
        catch /^Vim\%((\a\+)\)\=:E971:/
        endtry
    endfor
enddef

def RestoreTextPropertiesAfterReload() #{{{3
    var buf: number = expand('<abuf>')->str2nr()
    if !db->has_key(buf)
        return
    endif
    var types: list<string> = db[buf]['virtualtexts']->keys()
    for type in types
        var type_info: dict<any> = db[buf]['virtualtexts'][type]
        var highlight: string = type_info.highlight_real
        var pos: dict<number> = type_info.pos
        prop_type_add(type, {
            bufnr: buf,
            highlight: highlight,
            })
        prop_add(pos.lnum, pos.col, {
            bufnr: buf,
            length: pos.length,
            type: type,
            })
        # don't need the info anymore, let's clear it to keep the db as simple/light as possible
        type_info.pos = {}
    endfor
enddef

def RecreatePopupsInOtherWindows() #{{{3
    var buf: string = expand('<abuf>')
    if !db->has_key(buf)
        return
    endif

    # Problem: After a buffer is reloaded, the popup windows are still there, but they're no longer visible.{{{
    #
    # When tied to a text property, a popup has 3 text-property-related options:
    #
    #    > textprop	When present the popup is positioned next to a text
    #    >                property with this name and will move when the text
    #    >                property moves.  Use an empty string to remove.
    #    >
    #    > textpropwin	What window to search for the text property.  When
    #    >                omitted or invalid the current window is used.
    #    >
    #    > textpropid	Used to identify the text property when "textprop" is
    #    >                present. Use zero to reset.
    #
    # For example:
    #
    #     textprop = 'virtualText123'
    #     textpropid = 0
    #     textpropwin = 4567
    #
    # But after a buffer is reloaded,  such a popup loses its `textprop` option,
    # which probably prevents it from being visible.
    #
    #     vim9
    #     setline(1, 'text')
    #     sil sav! /tmp/file
    #     var buf = bufnr('%')
    #     prop_type_add('textprop', {bufnr: buf})
    #     prop_add(1, 1, {type: 'textprop', length: 1, bufnr: buf})
    #     var id = popup_create('', {textprop: 'textprop'})
    #     sil e
    #     echo popup_getoptions(id)->keys()->filter((_, v) => v =~ 'textprop')
    #
    #     ['textpropid', 'textpropwin']~
    #
    # Note that this is only the case if the text property is local to the buffer.
    #}}}
    # Solution: Restore the `textprop` and `textpropwin` options.
    # FIXME: `:tab sp | e | 1tabnext`{{{
    #
    # No virtual texts.
    #
    # ---
    #
    # `:tab sp | e | 1tabnext | q`
    #
    #     E716: Key not present in Dictionary: "padding"~
    #
    # ---
    #
    # I  *think*  the  issue comes  from  the  fact  that  popups tied  to  text
    # properties lose their `textprop*` options when their buffer is reloaded in
    # a different window in a *different* tab page:
    #
    #     vim9
    #     setline(1, 'text')
    #     sil sav! /tmp/file
    #     prop_type_add('textprop', {})
    #     prop_add(1, 1, {type: 'textprop', length: 1})
    #     var id = popup_create('', {textprop: 'textprop'})
    #     echom "'textprop*' options BEFORE reload: " .. popup_getoptions(id)
    #         ->keys()
    #         ->filter((_, v) => v =~ 'textprop')
    #         ->string()
    #     tab sp
    #     sil e
    #     echom "'textprop*' options AFTER reload: " .. popup_getoptions(id)
    #         ->keys()
    #         ->filter((_, v) => v =~ 'textprop')
    #         ->string()
    #
    #     textprop* options BEFORE reload: ['textprop', 'textpropid', 'textpropwin']~
    #     textprop* options AFTER reload: []~
    #
    # That doesn't happen when  we reload a buffer in a  different window in the
    # *same* tab page.   Is it a Vim  bug?  I could understand  that the current
    # window matters  when deciding whether  the options are preserved,  but why
    # would the current tab page matter?
    #
    # ---
    #
    # Let's try to restore the `textprop*` options here, and see whether it helps.
    #
    # Update: It doesn't always work because `popup_setoptions()` fails to reset
    # `textpropwin` when the popup is in a different tab page.
    #
    #     vim9
    #     setline(1, 'text')
    #     sil sav! /tmp/file
    #     prop_type_add('textprop', {})
    #     prop_add(1, 1, {type: 'textprop', length: 1})
    #     var id = popup_create('', {textprop: 'textprop'})
    #     tab sp
    #     sil e
    #     popup_setoptions(id, {textprop: 'textprop', textpropwin: 1000})
    #     echom popup_getoptions(id).textpropwin
    #
    #     # expected: 1000
    #     # actual: 1002
    #
    # Is it a Vim bug?
    #
    # Idea: `popup_setoptions()`  is fine  for popups in  the current  tab page.
    # But for popups in other tab pages, I guess you need to close and re-create
    # the popups entirely.
    # All  in all,  it  might be  simpler  to just  close  and re-create  popups
    # regardless of where they are.
    #
    # Try to not write too much new code.
    # Borrow as much as possible from `MirrorPopupsOnAllWindows()`.
    #}}}
    for [textprop, win2popup] in db[buf]['virtualtexts']
            ->mapnew((_, v) => v.win2popup)
            ->items()
        # We need to do that for *all* windows displaying the buffer.{{{
        #
        # Otherwise:
        #
        #     :sp | e | wincmd w
        #     # no more virtual texts
        #}}}
        for [textpropwin, id] in win2popup->items()
            popup_setoptions(id, {
                textprop: textprop,
                # We need to also reset `textpropwin`.{{{
                #
                # Resetting `textprop` causes `textpropwin` to be reset with the
                # id of the current window: https://github.com/vim/vim/issues/7785
                #}}}
                textpropwin: textpropwin->str2nr(),
                })
        endfor
    endfor
enddef

def RemoveWipedBuffersFromDb() #{{{3
    var buf: string = expand('<abuf>')
    if has_key(db, buf)
        remove(db, buf)
    endif
enddef

