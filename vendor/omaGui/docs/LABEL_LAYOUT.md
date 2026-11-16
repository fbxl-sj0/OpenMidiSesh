<!--
    Project: omaGUI
    File: LABEL_LAYOUT.md
    Purpose: Describe portable label alignment for fixed form rectangles.
    Responsibilities: Explain the API, retained defaults, limits, and tests.
    This file intentionally does NOT contain: VB event or operating-system semantics.
-->

# Label layout

Labels can now align text inside their existing widget rectangle without
replacing `label_Render`. This uses the bundled bitmap fonts and the existing
FreeBASIC graphics backend. It introduces no platform GUI calls, external font
dependency, worker thread, or image allocation.

```freebasic
Dim As Widget Ptr readout = label_Create("readout", "0.", 10, 10)
If readout <> 0 Then
    readout->w = 160
    readout->h = 24
    label_SetAlignment readout, BACKEND_ALIGN_RIGHT, BACKEND_ALIGN_MIDDLE
    label_SetClipToBounds readout, -1
    gui_AddWidget readout
End If
```

| API | Behavior |
| --- | --- |
| `label_SetAlignment(widget, horizontal, vertical)` | Opt into bounded layout; vertical defaults to `BACKEND_ALIGN_TOP` |
| `label_GetAlignment(widget, horizontal, vertical)` | Return the retained settings through output arguments |
| `label_ClearAlignment(widget)` | Restore the original renderer's layout behavior |

Horizontal values are `BACKEND_ALIGN_LEFT`, `BACKEND_ALIGN_CENTER`, and
`BACKEND_ALIGN_RIGHT`. Vertical values are `BACKEND_ALIGN_TOP`,
`BACKEND_ALIGN_MIDDLE`, and `BACKEND_ALIGN_BOTTOM`. Setters return nonzero on
success. Null widgets, other widget types, and invalid enum values return zero
without changing the label. The getter returns zero for an invalid widget and
initializes its outputs to left/top.

The new settings are appended to `LabelData`. New labels retain the original
left/top rendering behavior until alignment is explicitly enabled. Clearing
alignment restores that behavior without changing text, font, wrapping, colors,
clipping, or widget dimensions. Existing construction calls need no changes.

## Text, wrapping, and decoration

Aligned labels recognize CRLF, CR, and LF paragraph breaks, including when
word wrapping is off. Each line aligns independently. With word wrapping on,
the existing measured word/path breaks, maximum-line bound, and ellipsis
behavior apply. The entire rendered block is positioned vertically using the
selected font height and the existing two-pixel gap between lines. A trailing
line break does not add an extra empty line, matching the existing wrapper.

Unwrapped lines retain their trailing spaces. Wrapped lines retain the
existing trimming behavior. The label uses its current rectangle on every
render, so moving or resizing it needs no alignment reset or input frame.

The access-key underline follows the first matching rendered character,
including on wrapped lines. Its position and width use the same embedded font
as the text. Alignment changes display layout only; keyboard routing and
mnemonic targets still belong to the normal widget registry.

Clipping remains independently controlled by `label_SetClipToBounds`. When
enabled, text, background, and decoration share the label's rectangle and the
renderer restores the caller's clip afterward. Text wider or taller than its
rectangle retains the requested alignment, so clipping can hide its leading
portion when right or bottom aligned.

Aligned rendering requires positive width/height at most 1,000,000 pixels and
absolute coordinates within -1,000,000 through 1,000,000. This bounds the new
coordinate arithmetic on 32-bit as well as 64-bit targets. Invalid rectangles
draw nothing and do not push a clip. Ordinary, unaligned labels retain their
previous rectangle behavior.

Aligned text is bounded to `LABEL_MAXIMUM_ALIGNED_TEXT_BYTES` (1 MiB).
Enabling alignment on a larger existing string fails. While alignment is
enabled, `label_SetText` rejects larger strings without replacing the old text.
Rendering also checks the limit because `LabelData` remains public. Existing
unaligned text setters retain their previous behavior. Layout still has the
existing maximum of 256 wrapped/paragraph lines.

All setters and rendering run on the owning GUI thread, as with other widget
operations. No callback, pointer ownership, or synchronization contract changes.

## Verification and Optical integration

From the enclosing Optical FreeBASIC directory:

```powershell
.\tools\verify_omagui_labels.ps1
.\build-vbwin1.ps1 -SkipRegression
```

The label gate runs five native Windows tests: alignment pixels, existing
label state, designer clipping, keyboard navigation, and embedded fonts. Pixel
checks use gfxlib's null driver and a real 32-bit framebuffer. They cover all
nine alignments in two fonts, paragraphs, wrapping, resize, trailing spaces,
mnemonic placement, clip restoration, invalid input, and restored defaults.
The gate also generates Linux x86-64 compiler output with
`OMAGUI_PORTABLE_ONLY`; this Windows-host check does not link or run Linux code.

VBWIN1's preview now calls the public alignment and clipping APIs. Its private
right/center label render callbacks are removed. VB1 alignment ordinals are
translated in the adapter; the library keeps its existing named alignment
constants and contains no VB-specific control rules. The VB1 gate continues
to verify all 25 original form previews and CALC's actual readout pixels.

<!-- end of LABEL_LAYOUT.md -->
