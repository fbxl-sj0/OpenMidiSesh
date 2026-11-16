<!--
    Project: omaGUI
    File: DESIGNER_SUPPORT.md
    Purpose: Document portable library behavior used by form-design tools.
    Responsibilities: Explain APIs, compatibility, ownership, and verification.
    This file intentionally does NOT contain: VB language or event semantics.
-->

# Form-designer support

These additions are native FreeBASIC implementations using omaGUI's existing
widgets and gfxlib backend. They require no platform GUI framework, Windows
SDK, C/C++ source, new binary dependency, or current-directory mutation.

## File pattern alternatives

`filelistbox_TryRefreshPatterns(widget, path, patterns)` accepts semicolon-
separated alternatives such as `*.bmp;*.ico;sample.*`. It trims each alternative,
rejects empty alternatives and path separators, and returns the existing
`FILESYSTEMLISTBOX_REFRESH_*` status values.

All searches populate one bounded snapshot before the live list changes.
Overlapping alternatives produce one row per returned filename. Distinct
case-sensitive filenames remain distinct on Unix. Successful refreshes sort
the combined result and clear selection; failures preserve rows and selection.
The existing 1024-row and 4 MiB item-text bounds apply to the combined result.
Wildcard interpretation follows the host's FreeBASIC Dir behavior.

The original `filelistbox_TryRefresh` and `filelistbox_Refresh` continue treating
the pattern as one string. A literal semicolon in a filename retains its old
meaning through those APIs. The new behavior is explicitly selected by callers.

Directory and file refreshes accept filesystem roots as well as ordinary
directories. On Windows, Dir does not return a dot entry at a drive/share root.
The library recognizes only structural roots and checks their existence through
FreeBASIC's supplied C-runtime header. Child enumeration still uses Dir. The
Unix route uses its existing native enumeration. Invalid paths remain failures;
an empty directory or no matching filenames remains a successful empty result.

## Bounded label rendering

`label_SetClipToBounds(widget, enabled)` opts a label into clipping against its
current width and height. It returns zero for an invalid widget and nonzero on
success. `label_GetClipToBounds(widget)` returns the retained setting.

Clipping is off by default. Existing labels with no explicit dimensions keep
their previous behavior. When enabled, zero-sized rectangles draw nothing, and
text, background, wrapping, and mnemonic decoration share the same clip. The
renderer restores the caller's clip after drawing.

```freebasic
Dim As Widget Ptr statusLabel = label_Create("status", "Selected filename", 10, 10)
If statusLabel <> 0 Then
    statusLabel->w = 200
    statusLabel->h = 24
    label_SetClipToBounds statusLabel, -1
    gui_AddWidget statusLabel
End If
```

## First-frame list rendering

Listboxes synchronize their owned scrollbar rectangles during rendering as
well as input updates. A newly constructed, moved, or resized list renders its
scrollbar correctly after layout, even when no input frame has run. Rendering
does not generate selection or activation events.

## Label measurement and borders

`label_GetTextSize(widget, width, height)` measures the current rendered text
layout without resizing the widget. Wrapping, explicit paragraphs, the selected
embedded font, and the existing maximum-line/ellipsis policy all use the same
layout routine as rendering. Empty text measures one font-height line. The
function returns nonzero on success; invalid widgets or unusable wrapped client
widths return zero with both outputs zero. Measurement accepts at most 1 MiB
of text and widget widths from 0 through 1,000,000 pixels.

`label_SetBorderStyle(widget, style)` accepts 0 (none) or 1 (fixed single).
`label_GetBorderStyle(widget)` returns the retained setting. Borderless remains
the default and retains the original renderer. A fixed border uses the theme's
border color and a two-pixel inset on each side. Measurement includes these
insets; wrapping uses the remaining client width. Invalid styles preserve the
previous state. Rendering borrows a stack copy of the widget rectangle and
restores the caller's clip; it does not change registry geometry or ownership.

The VB3 host uses this measurement for Label AutoSize. Label rendering and
font metrics stay in omaGUI; the host decides whether to change width, height,
or both in VB units. Run `tools/verify_omagui_labels.ps1` from the enclosing
Optical directory for measurement, independent pixel, and existing label/font/
keyboard regressions. It accepts `-CompilerPath` for a specific installation.

## Optional canvas clicks

`canvas_SetClickable(widget, enabled)` enables complete primary-pointer clicks
on a canvas. It returns zero for null or other widget types. Clicks are off by
default, and enabling them does not change focusability, rendering callbacks,
update callbacks, or the existing inside-only pointer getters.

`canvas_GetActivationCount(widget)` returns an unsigned 64-bit counter. Compare
it with the previously observed value after `gui_UpdateAll` to dispatch host
events outside input traversal. A press must originate inside the routed
canvas and release inside it. Captured movement can leave and return; release
outside cancels. Occluding widgets, modal exclusion, hiding, disabling, and
changing click policy cancel pending input. A held press cannot become a new
click merely because the canvas becomes eligible again. Secondary buttons do
not increment this counter. Cancellation preserves the existing pointer API.

VB3 Image controls use this counter; their source handlers can change which
overlapping image is visible after the release has been completely processed.
Run `tools/verify_omagui_canvas.ps1 -CompilerPath <compiler>` from the enclosing
Optical directory for click/capture tests, existing canvas/modal/shape input
regressions, Linux code generation, and strict lint.

## Validation

The focused suite is available from the enclosing Optical FreeBASIC root:

```powershell
.\tools\verify_omagui_vb3.ps1
```

Seven standalone tests pass with native FreeBASIC on Windows x64 and Linux x64:
filesystem patterns, designer rendering, existing filesystem lists, capacity
handling, listbox activation, item mutation, and label state. Graphics checks
use gfxlib's null driver and verify pixels without a desktop. Capacity tests
reject 1025 entries transactionally and accept 1024 even with overlapping
patterns. The Linux pattern test also retains two names differing only in case.

PICVIEW uses these APIs in its original VB3 handlers. Its 42 assertions, eight
drive-switch assertions, malformed-input checks, and graphical rendering pass
after removal of the equivalent VB3-local workarounds. VB event dispatch,
App.Path, picture ownership, and source compilation remain in the VB runtime.

<!-- end of DESIGNER_SUPPORT.md -->
