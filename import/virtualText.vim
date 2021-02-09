vim9 noclear

const TYPE_PREFIX: string = 'virtualText'

# TODO: We should be able  to add virtual text in an  arbitrary buffer; not just
# the current one.

# TODO: Truncate the virtual  text so that it doesn't overflow  beyond the right
# border of a window.  Use `popup_settext()` to reset the text.

# TODO: We should be able to use different highlight groups for different chunks
# of the virtual text.  This would be useful, for example, to highlight a prefix
# in a different color.

# TODO: Implement `VirtualTextClear()`{{{
#
# To remove  arbitrary virtual  texts, inside  arbitrary range  of lines,  in an
# arbitrary buffer.
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
#
# ---
#
# We should remove the listener if we remove all virtual texts from a buffer.
#}}}

# TODO: We should be able to *only* pass a line number and some text to `VirtualTextAdd()`.
# In such a case, the function should not tie the virtual text to any real text.
# It should stay visible on the line as long as the latter is not removed.

# TODO: We  need to  use this  feature as  frequently as  possible, to  test and
# improve its reliability.  Any idea how we would use it?
# Suggestion: Supercharge the `m` command so that when  we set a mark on a line,
# its name is appended at the end of the line.
# Also, `ma` could simply use the text  `a`, while `m CTRL-a` could ask the user
# for a short annotation which would be appended after the mark's name.

# FIXME: Doesn't work well when joining lines with virtual texts.{{{
#
# Example: Delete the first  3 lines (the ones which don't  have virtual texts),
# then join the  new first 2 lines  (the one which do have  virtual texts), then
# undo, and finally append  text on the first line: the  inserted text is hidden
# behind the popup.
#
# Update: Actually, can  repro just by  deleting the third line,  then appending
# text on the new 3rd line.
#}}}
# FIXME: Doesn't work well when cutting lines.{{{
#
# Example: Press `cj` while on the "shattered" line:
#
#     Half sunk a shattered visage lies, whose frown,
#     And wrinkled lip, and sneer of cold command,
#
# The second virtual text is correctly removed, but not the first one.
# This trailing text remains:
#
#     en into many pieces
#
# It's a Vim bug, and I don't think there is much we can do to fix it on our side.
# Although, you  could install a  custom mapping  which would clear  a remaining
# virtual text on-demand.   But note that in  that case, if you  undo, you won't
# recover it.
#}}}

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
# in turn  causes popups attached to  text properties to lose  their `textprop*`
# options.  This needs to be fixed for virtual texts to persist across reloads.
#}}}
var db: dict<dict<any>> = {}
var counters: dict<number> = {}

# Autocmds {{{1

augroup VirtualTextReplicatePopups | au!
    au BufWinLeave,QuitPre * CloseStalePopups()
    # Do *not* mirror popups on `WinEnter`.{{{
    #
    # Because  the current  buffer might  be still  wrong on  `WinEnter`.  As  a
    # result, the guard  at the top of `MirrorPopups()` might  fail to correctly
    # bail out.
    #
    # You can observe this by executing from a window with virtual texts:
    #
    #     :echo popup_list()->len()
    #     # some number N
    #     :tabnew
    #     :echo popup_list()->len()
    #     # 2 * N
    #
    # ---
    #
    # You could be tempted to delay `MirrorPopups()` with a timer or `SafeState`.
    # Don't.  It would make the code less predictable, and harder to reason with.
    #
    # For example, using `SafeState`:
    #
    #     :tab sp | 1tabnext | q
    #     # E716: Key not present in Dictionary: "padding"
    #
    #     :tab sp | 1tabnext
    #     :q
    #     # E716: Key not present in Dictionary: "padding"
    #
    #     :tab sp
    #     :1tabnext | q
    #     # no error
    #
    #     :sp | wincmd w | call feedkeys('ii', 'nxt')
    #     E716: Key not present in Dictionary: "1005"
    #
    # A  timer wouldn't  fix this issue;  but the latter  would be  triggered by
    # different commands (e.g. `:sp | q`).
    #}}}
    au BufEnter,BufWinEnter * MirrorPopups()
    # `WinNew` is necessary if we split a window displaying virtual texts.{{{
    #
    # And it works no matter how we split: `:sp`, `:vert sp`, `:tab sp`.
    #}}}
    # OK, but why the delay?{{{
    #
    # To prevent undesirable popups from being created.
    # Indeed, when  `WinNew` is fired, the  current buffer has not  been updated
    # yet; so the guard  at the top of `MirrorPopups()` might  not bail out like
    # it should.
    #}}}
    au WinNew * au SafeState * ++once MirrorPopups()
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
    RemoveStaleVirtualText(buf, lnum)

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
        listener_add(UpdatePadding, buf)
        extend(db, {[buf]: {}})
        extend(counters, {[buf]: 1})
    else
        counters[buf] = counters[buf] + 1
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
    type_id = counters[buf]

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

        extend(db[buf], {[TYPE_PREFIX .. type_id]: {
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
            | FixPopups()
    augroup END
enddef

def g:VirtualTextDb(): dict<dict<any>> #{{{3
# only useful for debugging purpose
    return db
enddef
#}}}2
# Core {{{2
def RemoveStaleVirtualText(buf: number, lnum: number) #{{{3
    var proplist: list<dict<any>> = prop_list(lnum)
    var idx: number
    while idx >= 0
        idx = proplist->match(TYPE_PREFIX)
        if idx == -1
            break
        endif

        # close stale popup(s)
        var stale_virtualtext: string = proplist[idx]['type']
        var stale_popups: list<number> =
            db[buf][stale_virtualtext]['win2popup']->values()
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
        db[buf]->remove(stale_virtualtext)
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
    var left_padding: number =
        col([start, '$']) - textprop.col - textprop.length + 1
    # TODO: Try to cache `win_findbuf()` to optimize the performance.
    # Clear the cache on `WinLeave` and `BufWinLeave`.
    for winid in win_findbuf(buf)
        var popup_id: number = db[buf][textprop.type]['win2popup'][winid]
        popup_setoptions(popup_id, {
            mask: [[1, left_padding, 1, 1]],
            padding: [0, 0, 0, left_padding],
            })
    endfor
enddef

def CloseStalePopups() #{{{3
    var buf: number = expand('<abuf>')->str2nr()
    # return if the buffer doesn't have any virtual text
    if !db->has_key(buf)
        return
    endif
    var curwin: number = win_getid()
    var win2popup: dict<number>
    for textprop in db[buf]->keys()
        win2popup = db[buf][textprop]['win2popup']
        # The function might already have removed the key.{{{
        #
        # That happens when closing a window.
        # In that case, `QuitPre` is fired before `BufWinEnter`.
        # BTW, don't  worry about  the popup;  on `QuitPre`,  it's automatically
        # destroyed (probably  because Vim  sees that  the `textpropwin`  key no
        # longer matches an existing window).
        #}}}
        if win2popup->has_key(curwin)
            # The popup we're about to close might be the last one for a given virtual text.
            # If so, we need to save its options.{{{
            #
            # Indeed, `MirrorPopups()` needs this info.
            # It's better to get it by inspecting the options of an existing and
            # relevant  popup (because  more up-to-date).   But that's  bound to
            # fail if there's no longer any popup.  So, we need a fallback.
            #}}}
            db[buf][textprop]->extend({fallback_opts: popup_getoptions(win2popup[curwin])})
            win2popup[curwin]->popup_close()
            # if the  window no longer  displays the current buffer,  remove its
            # key from `win2popup`
            win2popup->remove(curwin)
        endif
    endfor
enddef

def MirrorPopups() #{{{3
    var buf: string = expand('<abuf>')
    var curwin: number = win_getid()
    var curtab: number = tabpagenr()

    # return if the buffer doesn't have any virtual text
    if !db->has_key(buf)
    # bail out if the popups have already been created on the current window
    # TODO: Is `TYPE_PREFIX .. counters[buf]` correct?
    # What if the the last virtual text has been removed, and the db has been updated?
    # It will probably raise an error...
    # Maybe we need another dictionary which maps buffers to the virtual texts they contain...
    || db[buf][TYPE_PREFIX .. counters[buf]]['win2popup']->keys()->index(string(curwin)) >= 0
        return
    endif

    # iterate over the virtual texts
    # (i.e. their text, the name of their text property, and their popup ids)
    for [text, textprop, win2popup] in db[buf]
        ->mapnew((k, v) => [v.text, k, v.win2popup])
        ->values()

        var opts: dict<any>
        if win2popup->values() != []
            # derive the  options of our new  popup from an existing  one; let's
            # pick the first one arbitrarily (hence `[0]`)
            # TODO: Instead, maybe we should use a new key in the db.
            # It would be updated on some event(s).
            # It would match a window ID displaying the popup we want to mirror...
            opts = win2popup->values()[0]->popup_getoptions()
        else
            opts = db[buf][textprop]['fallback_opts']
        endif
        # `popup_getoptions()` doesn't give us `mask`: https://github.com/vim/vim/issues/7774
        # let's derive it from `padding`
        var left_padding: number = opts.padding[3]
        extend(opts, {
            mask: [[1, left_padding, 1, 1]],
            tabpage: curtab,
            textpropwin: curwin,
            })

        # replicate popup in current window
        var new_popupid: number = popup_create(text, opts)

        # update the db
        extend(win2popup, {[curwin]: new_popupid})
    endfor
enddef

def SaveTextPropertiesBeforeReload() #{{{3
# the lines on which we applied text properties might have been moved,
# we need to update the db to get their new current positions
    var buf: string = expand('<abuf>')
    if !db->has_key(buf)
        return
    endif

    var types: list<string> = db[buf]->keys()
    for type in types
        try
            var newpos: dict<any> = {type: type}->prop_find('f')
            if newpos == {}
                newpos = {type: type}->prop_find('b')
            endif
            db[buf][type]['pos'] = newpos
            remove(db[buf][type]['pos'], 'type')
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
    var types: list<string> = db[buf]->keys()
    for type in types
        var type_info: dict<any> = db[buf][type]
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

def FixPopups() #{{{3
# Problem: After a buffer is reloaded, the popup windows are still there, but they're no longer visible.{{{
#
# When attached to a text property, a popup has 3 text-property-related options:
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
# But after  a buffer  is reloaded,  such a popup  loses its  `textprop` option,
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

    var buf: string = expand('<abuf>')
    if !db->has_key(buf)
        return
    endif

    for [textprop, win2popup] in db[buf]
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
    if has_key(counters, buf)
        remove(counters, buf)
    endif
enddef

