<!--
    Project: omaGUI
    File: TEXT_STYLES.md
    Purpose: Document optional embedded-font styling and its editor contract.
    Responsibilities: Describe API flags, rendering, compatibility and limits.
    This file intentionally does NOT define a platform font-selection system.
-->

# Optional text styles

`textbox_SetTextStyle(widget, flags)` combines the following backend constants:

| Flag | Value | Effect |
| --- | --- | --- |
| `BACKEND_TEXT_STYLE_NORMAL` | 0 | Existing rendering |
| `BACKEND_TEXT_STYLE_BOLD` | 1 | Add one pixel of horizontal glyph coverage |
| `BACKEND_TEXT_STYLE_ITALIC` | 2 | Shear upper glyph rows to the right |
| `BACKEND_TEXT_STYLE_UNDERLINE` | 4 | Draw a line below the face's baseline area |
| `BACKEND_TEXT_STYLE_STRIKEOUT` | 8 | Draw a line through the face's middle |

Use `Or` to combine flags, or pass zero to restore normal rendering. The setter
returns nonzero on success. Null/non-TextBox widgets, negative values, and unknown
bits fail without changing the previous style. `textbox_GetTextStyle` returns the
current combination, or zero for an invalid target.

```freebasic
textbox_SetTextStyle editor, BACKEND_TEXT_STYLE_BOLD Or BACKEND_TEXT_STYLE_ITALIC
textbox_SetTextStyle editor, BACKEND_TEXT_STYLE_NORMAL
```

Style is per widget. Ordinary, selected, masked, and syntax-colored text use the
same flags. Line-number gutters keep their existing appearance. Changing style
does not change text, selection, caret position, scrolling, wrapping, or undo
history. Existing constructors default to normal rendering. The appended
TextBoxData field requires consumers to rebuild with the current header, as with
other extensions to that internal record.

Backend clients can use
`backend_PrintStyled(x, y, color, text, flags, font_id)` directly. The last argument
defaults to `BACKEND_FONT_DEFAULT`. Zero flags delegate to the existing font
renderer, preserving its pixels and fast path. Styled output uses the existing
clip and alpha-aware pixel APIs. Invalid flags and positions outside the same
bounded coordinate range used by the byte renderer produce no styled output.

These are synthetic styles of the embedded printable-ASCII glyphs. Bold merges
coverage with a one-pixel shift before blending; italic shifts upper rows one
pixel per four rows above the baseline. Both retain the original advance width.
Their extra ink can overhang a cell and is clipped by the normal widget client
rectangle. Decorations use the face's common height, rather than each glyph's
height, so descenders do not move the underline or strikeout between characters.

The API does not select operating-system fonts, load TrueType faces, change
point sizes, or promise Windows font metrics. Glyph advance and editor layout
stay with the existing embedded face. The implementation remains native
FreeBASIC and introduces no platform-specific font dependency or shared style
state.

`tests/textbox_style_smoke.bas` runs 106 checks on a gfxlib null-driver framebuffer.
It verifies unchanged normal pixels, increased bold coverage, italic shape,
level decorations, clipping, flag validation, retained editing/history state,
password selection, and syntax-colored spans. Existing syntax, password,
selection, history, input-limit, compact-editor, and bundled-font tests also
passed when this API was added.

<!-- end of TEXT_STYLES.md -->
