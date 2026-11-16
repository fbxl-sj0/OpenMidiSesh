# TextBox input limits

`textbox_SetInputLimit(widget, byte_limit)` opts a TextBox into a nonnegative
32-bit byte limit. Zero, the default, leaves existing editors unlimited.
`textbox_GetInputLimit(widget)` reads the policy. Invalid widgets and negative
limits fail without changing state. These APIs use native FreeBASIC strings
and the same byte positions as the selection API.

Typing, paste, Return, Tab spaces, `textbox_InsertAtSelection`, and
`textbox_ReplaceSelection` consume the available room after removing the
selected bytes. Only the inserted text is shortened; the unselected prefix
and suffix remain intact. A completely blocked insertion preserves selection
and redo history. An explicitly empty replacement can still delete selection.

`textbox_ReplaceAll` and block indentation remain atomic: an operation that
would grow the text beyond the limit fails before allocation or history
changes. Shrinking already oversized text remains possible. Read-only and
password protections continue to apply.

Changing the limit does not rewrite existing text or discard history.
`textbox_SetText`, Undo and Redo retain their document/state restoration
semantics and may produce text longer than the input limit. Language adapters
that also constrain programmatic assignments must apply that separate policy.
The limit is an editing policy, not a bound on every retained string allocation.

The field is appended to `TextBoxData`; existing field offsets remain stable.
Rebuild clients with the current headers. Compiled record layouts are not a
frozen binary interface. All widget mutation remains on the GUI thread.

The native smoke test covers default behavior, selection capacity, blocked
redo preservation, input paths, bulk commands, and clearing the limit. Run
`tools/verify_omagui_textbox.ps1` from the Optical FreeBASIC workspace to run
it with the existing editor regressions and process-local clipboard backend.

<!-- end of TEXTBOX_INPUT_LIMIT.md -->
