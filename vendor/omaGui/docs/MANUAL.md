# omaGUI Library Manual

This manual describes the public API and behavior of the current omaGUI
implementation. The declarations in `omaGUI.bi` and the public `.bi` files are
the final authority for exact function signatures.

## 1. Architecture

omaGUI has three layers:

1. The gfxlib backend owns the display surface, color mapping, drawing, fonts,
   clipping, snapshots, and raw input polling.
2. The GUI manager owns registered widgets, hierarchy, layout, window order,
   focus, pointer capture, modal routing, update order, and render order.
3. Individual widget modules own control-specific state and behavior.

Application code creates widgets and registers them with the GUI manager. The
manager owns registered widget pointers and calls each widget's update, render,
and destroy callbacks. Removing a parent recursively removes its descendants.

## 2. Building a program

### 2.1 Master include

Define `OMAGUI_IMPLEMENTATION` in exactly one program source file before
including `omaGUI.bi`:

```freebasic
#define OMAGUI_IMPLEMENTATION
#include once "omaGUI.bi"
```

Other source files can include `omaGUI.bi` without the definition. Defining it
in more than one compilation unit would duplicate the implementation.

The master include exposes every backend and widget module, including the
primitive widgets and all graphic-shape APIs.

### 2.2 Initialization and frame loop

Call `backend_Init` before `gui_Init`. A normal frame clears the draw target,
updates the GUI once, renders it once, and flips the gfxlib pages:

```freebasic
backend_Init 800, 600, 0, BACKEND_WINDOW_RESIZABLE
gui_Init

Do
    backend_Clear RGB(236, 236, 236)
    gui_UpdateAll
    gui_RenderAll
    backend_Flip

    If MultiKey(FB.SC_ESCAPE) Then Exit Do
    Sleep 10, 1
Loop

backend_Exit
```

`gui_UpdateAll` polls input and the live drawable size. Do not call
`input_Update` separately in the normal application loop.

### 2.3 Widget creation and ownership

Constructors return a heap-allocated `Widget Ptr`. Register each top-level
widget and each child with `gui_AddWidget`. Then use `gui_SetParent` to bind a
child to its owner:

```freebasic
Dim toolWindow As Widget Ptr
Dim runButton As Widget Ptr

toolWindow = subwindow_Create("tools", "Tools", 40, 40, 260, 180)
runButton = button_Create("run", "Run", 12, 14, 80, 28)

gui_AddWidget toolWindow
gui_AddWidget runButton
gui_SetParent runButton, toolWindow
```

Child `x` and `y` values are local to the parent's client area. The manager
stores the resolved screen position in `ax` and `ay`. Parent cycles and overly
deep invalid hierarchies are rejected.

`gui_AddWidget` makes duplicate names unique by adding a numeric suffix.
Registering the same pointer more than once does not append a duplicate or
change its name. `gui_AddGeneratedWidget` is an importer fast path that skips
the name scan, so its caller must supply unique names.

Use `gui_RemoveWidget(name)` to destroy a widget tree. Do not delete registered
widgets directly. `gui_ResetForTest` destroys every registered widget and
clears manager state.

## 3. Graphics backend

### 3.1 Display creation

```freebasic
backend_Init(width, height, headless, windowFlags, colorDepth)
```

The last four arguments have defaults. Important values are:

| Setting | Values |
| --- | --- |
| Window flags | `BACKEND_WINDOW_FIXED`, `BACKEND_WINDOW_RESIZABLE`, `BACKEND_WINDOW_FULLSCREEN` |
| Color depths | `BACKEND_COLOR_DEPTH_MONOCHROME`, `BACKEND_COLOR_DEPTH_16_COLOR`, `BACKEND_COLOR_DEPTH_256_COLOR`, `BACKEND_COLOR_DEPTH_HIGH_COLOR`, `BACKEND_COLOR_DEPTH_TRUE_COLOR` |

When `headless` is nonzero, no gfxlib screen is created. Drawing and snapshot
operations become no-ops, while dimensions, color depth, clipping state, font
measurement, and widget input remain available. This lets logic suites run on
servers without a display driver. A zero value creates the normal gfxlib
window.

If gfxlib rejects the requested low-depth mode during initialization, omaGUI
falls back to 32-bit color. `backend_GetColorDepth` reports the active depth.
`backend_SetColorDepth` returns nonzero on success and makes a best effort to
restore the previous mode after a driver failure.

### 3.2 Resize behavior

`BACKEND_WINDOW_RESIZABLE` requests a resizable gfxlib surface, while
`BACKEND_WINDOW_FULLSCREEN` requests a full-screen surface.
`backend_GetSize` reports the current drawable size, and `gui_UpdateAll`
automatically updates the GUI viewport from it. `backend_IsResizable` reports
whether the active gfxlib screen accepted the request.

`backend_SetWindowMode(width, height, flags)` recreates both gfx pages and
returns nonzero on success. This is the supported transition between fixed,
resizable, and full-screen operation. A failed transition makes a best effort
to restore the previous mode. Mode changes are unavailable in headless mode.

`backend_GetWorkPage` reports the current drawing page. Applications with
their own retained shapes may offer `backend_DrawHorizontalSpans` or
`backend_DrawAlphaMask` to gfxlib3. A result of -1 means the backend handled
the drawing; 0 means the application should draw it through its ordinary
software path. These helpers require an active 32-bit screen, clip to its
bounds, and limit the packet size. On ordinary gfxlib they return 0.

The GUI reacts to resize and maximize events reported by gfxlib. It does not
emulate native border dragging. If borders cannot be dragged, that behavior is
in the installed gfxlib build or platform driver.

### 3.3 Color depths and palettes

| Constant | Depth | Mapping |
| --- | ---: | --- |
| `BACKEND_COLOR_DEPTH_TRUE_COLOR` | 32 | Direct RGB color |
| `BACKEND_COLOR_DEPTH_HIGH_COLOR` | 16 | Driver high-color mode |
| `BACKEND_COLOR_DEPTH_256_COLOR` | 8 | 216-color RGB cube plus 40 neutral grays |
| `BACKEND_COLOR_DEPTH_16_COLOR` | 4 | Conventional 16-color VGA palette |
| `BACKEND_COLOR_DEPTH_MONOCHROME` | 1 | Black or white from a weighted luma threshold |

The 1-bit mode is deliberately black and white. The backend maps requested RGB
colors through the active indexed palette, so the demo remains readable instead
of depending on driver-specific palette defaults.

### 3.4 Drawing primitives

The direct backend primitives are:

- `backend_PSet` and `backend_PSetAlpha`
- `backend_Line` and alpha-aware `backend_LineEx`
- `backend_Rect` and alpha-aware `backend_RectEx`
- `backend_Circle`
- `backend_Curve`, a quadratic Bezier through two endpoints and one control
  point

`gui_DrawLine`, `gui_DrawRect`, `gui_DrawCircle`, and `gui_DrawCurve` provide
matching high-level helpers.

Alpha values are clamped to the range 0 through 255. A value of 0 draws
nothing, and 255 is opaque. Pixel blending is available in 16-bit and 32-bit
modes. Indexed modes render nonzero alpha through the active palette rather
than blending palette indices.

### 3.5 Text, fonts, scaling, and alignment

`backend_PrintStyled` and `textbox_SetTextStyle` provide optional bold, italic,
underline, and strikeout using the embedded glyphs. Normal rendering and editor
metrics remain unchanged. See [TEXT_STYLES.md](TEXT_STYLES.md) for flags, clipping,
and the distinction between synthetic styling and font-face selection.

The embedded font identifiers are:

- `BACKEND_FONT_DEFAULT`
- `BACKEND_FONT_ARIAL_10_REGULAR`
- `BACKEND_FONT_ARIAL_12_BOLD`
- `BACKEND_FONT_LIBERATION_SANS_18_BOLD`
- `BACKEND_FONT_LIBERATION_SERIF_18_REGULAR`

The printing API includes default-font, selected-font, scaled, alpha, aligned,
and aligned-scaled variants. Horizontal alignment uses
`BACKEND_ALIGN_LEFT`, `BACKEND_ALIGN_CENTER`, or `BACKEND_ALIGN_RIGHT`.
Vertical alignment uses `BACKEND_ALIGN_TOP`, `BACKEND_ALIGN_MIDDLE`, or
`BACKEND_ALIGN_BOTTOM`.

Use the matching `backend_GetTextWidth*` and `backend_GetTextHeight*`
functions when laying out text. Scale factors smaller than one are treated as
one.

With gfxlib3 selected, alpha-mapped glyphs are submitted as one bounded GPU
point packet per string. This avoids a complete page readback when text is
drawn over GPU-resident content. Ordinary gfxlib and non-32-bit screens retain
the established software blend, and oversized or rejected packets fall back
to that same path.

Labels use the default embedded font unless a font is supplied to
`label_Create` or changed with `label_SetFont`. Pass `LABEL_COLOR_THEME_TEXT`
as a label color when its text should follow theme changes while the widget
remains open. Ordinary labels retain their default black text.

`label_SetWordWrap` gives a label a measured pixel width and a bounded line
count. Wrapping prefers spaces,
slashes, backslashes, and hyphens, then breaks an oversized word at a glyph
boundary. `label_GetRenderedLineCount` reports the resulting bounded line
count for application layout and tests. Passing a zero width restores the
original single-line behavior.

```freebasic
backend_PrintAlignedScaledAlpha _
    20, 20, 240, 60, RGB(30, 70, 130), "Status", _
    BACKEND_FONT_ARIAL_12_BOLD, _
    BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE, _
    2, 2, 192
```

### 3.6 Clipping and snapshots

`backend_SetClip(x, y, w, h)` pushes an intersected clip rectangle.
`backend_ResetClip()` pops one level. This stack behavior allows nested parent
and control clips. Every push must have a matching reset. The current stack is
bounded at 128 levels.

`backend_SaveSnapshot(filename)` writes a 24-bit BMP from a framebuffer with at
least three bytes per pixel. It returns without writing when that format cannot
be read safely from the active surface.

### 3.7 Theme colors

`backend_Init` initializes `current_theme` with `theme_InitClassic`.
Applications can replace its public color fields or use `theme_GetColor` with
the semantic `GUI_COLOR_*` identifiers. The built-in widgets read the shared
theme during rendering, so a later color change applies without reconstructing
them.
`theme_SetMode` selects `GUI_THEME_MODE_NORMAL`, `GUI_THEME_MODE_DARK`, or
`GUI_THEME_MODE_BLACK`; `theme_GetMode` returns the active selection. The
palette also supplies default syntax colors for textboxes that have not set a
per-token override. FreeBASIC syntax coloring distinguishes language keywords,
built-in commands, procedure declarations and calls, macros, variables,
constants, members, user-defined object instances, labels, strings, numbers,
comments, and types. The
`TEXTBOX_SYNTAX_COLOR_*` constants identify these categories for
`textbox_SetSyntaxColor` and `textbox_ClearSyntaxColor`.

### 3.8 Portable raster images

The raster module loads local images into owned 32-bit gfxlib buffers. It
sniffs signatures rather than extensions because AMS DD image files commonly
have names such as `device_icon` or `3Image11` with no suffix.

```freebasic
Dim image As RasterImage Ptr
Dim errorMessage As String

If rasterimage_LoadFile("help/device_icon", image, errorMessage) Then
    backend_DrawImage 20, 20, image->pixels, image->hasAlpha
    rasterimage_Destroy image
Else
    Print errorMessage
End If
```

The public operations are:

| API | Purpose |
| --- | --- |
| `rasterimage_LoadFile` | Sniff and decode a local BMP, PNG, GIF, baseline JPEG, or classic ICO |
| `rasterimage_LoadMemory` | Decode supported BMP, PNG, GIF, baseline JPEG, or classic ICO bytes already held by the application |
| `rasterimage_DetectFormat` | Identify one of the supported signatures without decoding it |
| `rasterimage_ScaleToFit` | Proportionally shrink an image using nearest-neighbor sampling |
| `rasterimage_Destroy` | Release both the gfxlib pixels and the metadata record |
| `backend_DrawImage` | Draw an owned gfxlib image with opaque or alpha copying |

BMP and PNG use gfxlib's loader. The additional native GIF and JPEG decoders
cover the formats that the current DD corpus needs: GIF87a/GIF89a with first-frame
transparency and 8-bit baseline sequential grayscale or YCbCr JPEG. The corpus
inventory contained 66 GIFs, six baseline JPEGs, and three PNGs. It contained
no animated or interlaced GIFs and no progressive JPEGs. The GIF decoder still
handles interlaced input; only the first frame is displayed.

Classic ICO decoding additionally supports the first entry's uncompressed
1-, 4-, 8-, or 24-bit bitmap and transparency mask. Other icon encodings and
destination-dependent XOR pixels return an error. PictureBox can own a copy
of any decoded raster through `picturebox_SetImage`; see
[PictureBox images](PICTUREBOX_IMAGES.md) for ownership and format limits.

gfxlib exposes BMP and PNG decoding through a file-oriented `BLoad` API.
`rasterimage_LoadMemory` therefore creates an exclusive scratch directory
under `TMPDIR`, `TEMP`, `TMP`, or the current directory, writes one bounded
image, decodes it, and removes the exact file and directory before returning.
It never reuses or deletes an existing directory. This bridge uses standard
FreeBASIC file operations and works without a platform image API.

`rasterimage_LoadFile` requires an initialized gfxlib display, like the rest
of omaGUI. On success, the caller owns the returned `RasterImage Ptr` and must
eventually pass it to `rasterimage_Destroy`. On failure, the output pointer is
zero and `errorMessage` contains a diagnostic.

## 4. GUI manager

### 4.1 Base widget state

Every `Widget` contains a name, local rectangle, resolved rectangle, visibility
and enabled flags, focus state, hierarchy links, widget-private data, layout
state, and update/render/destroy callbacks.

Applications normally use constructors and public accessors instead of editing
widget-private data. Directly setting `visible`, `enabled`, `x`, `y`, `w`, or
`h` is supported when a dynamic layout needs it. The manager recalculates
effective visibility, enabled state, absolute coordinates, and clips each
frame.

### 4.2 Window order and input routing

Registry order is paint order. A click on a window or any descendant brings
the complete window tree to the front. `gui_BringToFront` provides the same
operation explicitly.

Only the topmost eligible widget sees a pointer event. A held pointer is
captured by the widget where the press started, which keeps drags and text
selections stable. Keyboard input is routed only to `gui_GetFocus()`.
`gui_CancelInput(root)` releases pointer capture in that subtree and calls
its optional `cancel_input` callbacks; a null root selects all widgets. Use it
for immediate hide/disable transitions which can occur between GUI updates.
The manager also notifies hidden, disabled, and modal-external widgets instead
of calling their update callback. Opening a modal root cancels outside input
immediately. Cancellation callbacks run on the GUI thread and must only clear
private state, without changing the registry or calling application handlers.
They may use `input_UnmaskedMouseButtons()` to retain the sampled held-button
state despite another widget's dispatch mask. It does not poll the platform
and must not be used to bypass masked input for activation.

`gui_SetFocus` can change focus explicitly. Tab advances through focusable
widgets in registration order, and Shift+Tab moves backward. Use
`gui_SetTabOrder(widget, index)` to assign a nonnegative explicit traversal
rank without changing paint order. Explicitly ranked controls come first,
equal ranks retain registration order, and a negative index clears the rank.
`gui_GetTabOrder` queries a rank. A widget may opt
into capturing an unmodified Tab for editor input; Shift+Tab and modified Tab
presses still traverse. Traversal wraps and skips hidden, disabled, and
modal-external controls. `gui_MoveFocus` provides the same operation to custom
navigation code. The focused widget is
drawn with a selection-colored inset outline while keyboard-navigation mode is
active. A mouse press retains logical focus for typing or selection but hides
that outline. Tab, navigation keys, Enter, Space, or an Alt mnemonic restores
the cue.

`gui_SetDefaultAction(widget, enabled)` assigns the unmodified Enter key to an
activatable widget; `gui_SetCancelAction` assigns unmodified Escape. The query
functions return each role. The manager resolves roles only within the focused
window, or within the modal tree while a modal root is active. Hidden or
disabled role targets are ignored. A default or cancel target need not accept
focus, which supports classic forms whose command buttons set `TabStop=False`.
Focused buttons, lists, multiline editors, combo boxes, and menu bars reserve
keys they handle locally before role routing occurs.
`inputdialog_Create` assigns this cancel role to its Cancel button, so
unmodified Escape reports the same cancellation result as clicking Cancel.

An activatable control can be assigned an Alt mnemonic with
`gui_SetMnemonic(widget, FB.SC_C)`. The manager focuses and activates the
first eligible matching control. Mnemonics use gfxlib scan codes so their
behavior remains portable across the supported desktop targets.

A noninteractive caption can forward its mnemonic to a focusable widget with
`gui_SetMnemonicTarget(source, target)`. The target is a checked weak registry
reference: removing the target clears every inbound relationship before its
allocation is released. Dispatch also requires source and target to belong to
the same owning window. Passing a null target clears the relationship, and
`gui_GetMnemonicTarget` returns the currently valid target.

Children are clipped and hit-tested inside their parent's client area. A
subwindow title bar remains owned by the window, not by its children. Hiding,
disabling, moving, closing, raising, or removing a parent applies coherently to
its complete tree.

### 4.3 Modal roots

`gui_SetModalRoot(root)` limits input to one registered widget tree while
leaving the desktop visible behind it. `gui_TrySetModalRoot` reports whether a
root could be activated, including when the modal stack is full.
`gui_ClearModalRoot` releases it, and `gui_IsModalOpen` reports the state.
Built-in file, input, color, and confirmation dialog constructors register
their roots and activate modal state before returning. Existing callers may
still call `gui_AddWidget` on the returned root; registering that same pointer
again is harmless. Removing the dialog root releases its modal state.

### 4.4 Anchors

Call `gui_SetAnchors(widget, flags)` after the widget has its intended starting
rectangle. Its container is the parent client area, or the GUI viewport for a
top-level widget.

| Horizontal anchors | Result when the container width changes |
| --- | --- |
| Left and right | Stretch width |
| Right only | Move with the right edge |
| Left only | Keep the starting local rectangle |
| Neither | Stay centered relative to the original layout |

The same rules apply to top and bottom. `GUI_ANCHOR_ALL` stretches on both
axes. `gui_ResetAnchors` returns a widget to ordinary parent-relative layout.
Tests can set a deterministic viewport with `gui_SetViewportSize` and read it
with `gui_GetViewportSize`.

## 5. Standard widgets

### 5.1 Buttons

```freebasic
Declare Sub onRun(ByVal clicked As Widget Ptr)

Dim runButton As Widget Ptr
runButton = button_Create("run", "Run", 20, 20, 90, 28, @onRun)
gui_AddWidget runButton
```

The optional callback receives the clicked widget pointer. Applications can
also poll `gui_ButtonPressed(name)`, which reports the button's completed press
state. Focused buttons activate with Enter or Space. `gui_SetMnemonic` adds an
application-level Alt shortcut without bypassing the normal callback or
polled activation paths.

`button_SetBackgroundColor` installs a retained face color while leaving the
theme bevel, border, focus role, and caption color intact. The matching Get
call distinguishes a literal black override from the default state;
`button_ClearBackgroundColor` returns the face to the active theme.

### 5.2 Labels, checkboxes, and radio buttons

`label_Create` makes noninteractive text. `checkbox_Create` stores a boolean
`checked` state. `radiobox_Create` stores a group identifier and selection
state; selecting one radio button clears the other registered buttons in that
group. Checkboxes and radio buttons participate in Tab traversal and accept
Space while focused. They can also receive an Alt mnemonic through
`gui_SetMnemonic`.

Variable status text should opt into a width and line bound so it cannot draw
over a neighboring control:

```freebasic
Dim statusLabel As Widget Ptr

statusLabel = label_Create( _
    "status", "Waiting for the connected instrument...", _
    12, 40, RGB(65, 65, 65) _
)
label_SetWordWrap statusLabel, 280, 2
gui_AddWidget statusLabel
```

The final line is shortened with an ellipsis when the configured maximum is
reached. A long path can also wrap after a directory separator.

These simple controls expose their state through `CheckBoxData` and
`RadioBoxData` in their public headers.

Prefer `checkbox_SetChecked`/`checkbox_GetChecked` and
`radiobox_SetSelected`/`radiobox_GetSelected` for state changes and queries.
Setters return zero for a null widget/data pointer and -1 on success. Any
nonzero input selects the boolean state; getters return 0 or -1. Selecting a
radio clears other registered radios with the same group identifier. The
legacy retained radio field remains 0/1, while the checkbox field is 0/-1.

`checkbox_GetActivationCount` and `radiobox_GetActivationCount` distinguish
user/programmatic Activate calls from state assignment. Setters do not advance
the counter; each activation does, even if a radio was already selected. Poll
after `gui_UpdateAll` to deliver application events. Pointer activation occurs
on release inside the same control that received the press, using its entire
`w` by `h` rectangle so a sized label is clickable. Releasing outside cancels.
Constructors retain their historical indicator-sized rectangle; set `w`/`h`
to cover the intended label hit area. Keyboard and mnemonic activation remain
edge-driven. These APIs represent two states, not a mixed/grey checkbox value.

CheckBox and RadioBox can independently override their bounded background and
their indicator/caption foreground through matching `*_SetBackgroundColor`
and `*_SetForegroundColor` calls. Each family has Get and Clear calls that
distinguish a literal black value from theme-driven rendering.

Labels retain their constructor foreground color. Applications can change or
query it through `label_SetTextColor` and `label_GetTextColor`. A Label can
also fill its positive `w` by `h` bounds with a retained color through
`label_SetBackgroundColor`; `label_ClearBackgroundColor` returns it to
transparent rendering and `label_GetBackgroundColor` distinguishes that state
from a literal black fill.

### 5.3 Scrollbars

`scrollbar_Create(name, x, y, w, h, maxValue, pageSize, vertical)` creates a
horizontal or vertical scrollbar. The `ScrollBarData` value is always bounded
to its valid range. Listboxes and multiline textboxes own integrated vertical
scrollbar widgets, so applications should not register those internal bars
separately.

Registered scrollbars participate in focus traversal. Left and Right apply
`small_change` to a horizontal scrollbar; Up and Down do the same for a
vertical scrollbar. Page Up and Page Down apply `large_change`, while Home and
End select the signed range endpoints. Every keyboard change uses widened
arithmetic before clamping, so an extreme signed range cannot overflow an
intermediate `Integer`.

`scrollbar_SetRange` accepts ascending signed 32-bit endpoints and clamps an
existing value into the new range. `scrollbar_SetValue` rejects values outside
that range. `scrollbar_SetChanges` accepts positive signed 32-bit increments.
These checked setters return -1 on success and 0 on invalid input or a null
widget. Use them instead of writing the public compatibility record directly.

`scrollbar_SetReverse(widget, true)` reverses the physical direction without
changing the numeric bounds. `scrollbar_SetArrowButtons(widget, true)` enables
end arrows; the default remains arrow-free for existing embedded bars. Both
setters return the same checked success value. `scrollbar_IsDragging` reports
thumb capture, with 0 for a null widget. A programmatic value/range change
cancels a drag or held step when it changes that property. Changing increments,
direction, or arrow geometry also cancels private pointer state.

Thumb dragging retains the grab offset and exact starting value, even when
many values map to one pixel. Clicking the thumb without movement does not
change its value. Dragging outside the track clamps at an endpoint. Track
presses apply LargeChange and arrow presses apply SmallChange immediately.
Holding the same region repeats after 400 ms, then every 50 ms. Moving outside
that region resets the delay; paging pauses when the thumb reaches the pointer.
Late updates coalesce to one step. Hiding, disabling, or modal interruption
cancels a held press on registered bars. Listbox/textbox-owned scrollbars keep
their existing owner-specific input handling; containers must propagate
cancellation and effective state to unregistered child controls themselves.

`scrollbar_SetRepeat(widget, delayMs, intervalMs)` accepts 0..65535 ms for
both fields; a zero interval disables repeat but preserves single-click steps.
It returns -1 on success, 0 on invalid input. To drive a deterministic clock,
call `scrollbar_SetAutomaticRepeat(widget, false)` and then
`scrollbar_AdvanceRepeat(widget, elapsedMs)`. The latter accepts finite
elapsed times of 0..86400000 ms and returns -1 only when the value changed.
Use it after GUI input update, on the same thread. Re-enable automatic timing
for normal input. `scrollbar_CancelPointer(widget)` clears a widget's private
press state; `gui_CancelInput` additionally releases manager-owned capture.

### 5.4 Listboxes

Listboxes hold up to `LISTBOX_MAX_ITEMS`, currently 1024. Pointer selection is
published once when the primary button is released over the same row where the
press began. Releasing outside that row cancels the selection. They also
support edge-triggered Up, Down, Home, End, Page Up, and Page Down keys, an
integrated scrollbar, and mouse-wheel scrolling while the pointer is over the
list. Enter activates the selected row by advancing its `activation_count`.

Use `listbox_AddItem`, `listbox_Clear`, `listbox_GetItemCount`,
`listbox_GetSelectedIndex`, and `listbox_GetSelectedItem`. In the default single
selection mode, the index is zero-based and is `-1` when nothing is selected.
`listbox_GetActivationCount` is a monotonic event counter suitable for polling
after each GUI update. `listbox_ActivateSelected` advances that same counter
for a valid selected row and rejects an empty selection.

`listbox_SetSelectionMode` accepts `LISTBOX_SELECTION_SINGLE` (0),
`LISTBOX_SELECTION_SIMPLE` (1), or `LISTBOX_SELECTION_EXTENDED` (2).
Simple mode toggles rows with a click or Space; navigation moves only the caret.
Extended mode uses ordinary navigation/clicks to replace selection, Shift to
extend a range, Ctrl+click/Space to toggle, and Ctrl+navigation to move only the
caret. Ctrl+Shift adds a range. The pointer retains modifiers from its press.

In either multiple-selection mode, GetSelectedIndex/GetSelectedItem report the
caret row even when it is unselected. `listbox_SetItemSelected` changes one
row without moving the caret or viewport. `listbox_GetItemSelected` returns
status and writes the normalized selection state through its final argument;
invalid queries clear that output. `listbox_GetSelectedCount` counts selected
rows. SetSelectedIndex moves the caret; assigning -1 explicitly clears all rows.
Converting to single selection retains the selected caret, or the first
selected row when the caret is unselected. Mode conversion preserves viewport.

`listbox_GetSelectionChangeCount` returns an invalidation token for polling.
Compare tokens for inequality; they are not counts of user actions. Insertion,
removal, clear and mode conversion also invalidate indexed observations.
Refresh the token after application-owned mutations without firing input
handlers. Activation counters still distinguish completed input gestures from
programmatic changes. Selection flags follow surviving rows and are released
by Clear; all storage remains bounded by LISTBOX_MAX_ITEMS.

For checked mutations, use `listbox_InsertItem`, `listbox_RemoveItem`, and
`listbox_GetItem`. They return zero on failure and nonzero on success.
InsertItem defaults to append (`-1`); otherwise its index is in `0..count`.
GetItem returns text through its final ByRef argument, including valid empty
items. Insert/remove preserve the selected row's identity; removing that row
clears selection. Content changes cancel a pending pointer row without
manufacturing an activation. Clear releases retained item strings.

`listbox_SetItem(widget, index, text)` replaces an existing row without changing
its selection, scroll position or application value. It checks the total text
budget before mutation and cancels gestures aimed at the old content. It does
not synthesize a selection or activation notification.

`listbox_SetItemData(widget, index, value)` retains a signed 64-bit `LongInt`.
`listbox_GetItemData(widget, index, value)` reads through a `ByRef LongInt` and
returns zero on failure, clearing the output to zero. These opaque values move
with their rows through insertion/removal; new rows initialize to zero and Clear
discards them. No pointer ownership is transferred. Use these APIs on the GUI
thread, like other list operations.

`listbox_SetTopIndex` accepts an existing row and clamps to the last full page;
`listbox_GetTopIndex` returns the actual zero-based top row (zero when empty,
-1 for an invalid widget). Both synchronize the owned scrollbar after layout
changes. Setting the top row does not change selection.

`listbox_SetColumnCount` selects vertical layout with zero (the default), or
horizontal layout with a positive count up to `LISTBOX_MAX_COLUMNS` (32767).
`listbox_GetColumnCount` returns that count, or -1 for an invalid widget.
Horizontal lists fill each column from top to bottom, reserve the bottom
scrollbar, and divide the width among visible columns. Counts exceeding the
pixel width use one-pixel columns; item storage and rendering remain bounded.
Long labels clip at their own column boundary. Partial space below the final
complete row is padding, not another selectable row.

Left/Right move the caret by one column, Page Up/Down by the visible cell
count, and wheel input scrolls whole columns. TopIndex stays a row index but
aligns the requested item's column to the left, subject to the last full page.
Changing the count or resizing preserves selection and reclamps the viewport.
SetColumnCount cancels pending pointer gestures and scrollbar dragging.
The library permits switching orientations; language adapters may impose
stricter source-language rules. Column clips use balanced backend push/pop
operations so the parent's clip survives rendering.

Checked insertions enforce both the 1024-item limit and a 4 MiB total item-text
limit. The historical void AddItem API delegates to checked insertion but
cannot report failure, so use InsertItem when completeness matters.

`directorylistbox_Refresh` and `filelistbox_Refresh` enumerate through FreeBASIC's
Dir API and sort case-insensitively. They stage complete results before changing
the widget. An invalid directory, unsafe pattern, or capacity failure returns
zero and leaves old content and selection intact; an empty match set succeeds.
`directorylistbox_TryRefresh` and `filelistbox_TryRefresh` provide the same
transaction but return a `FILESYSTEMLISTBOX_REFRESH_*` reason, allowing a host
runtime to distinguish invalid widgets, paths, patterns, and bounded capacity.
These operations must run on the GUI thread. Dir uses a thread-local search
cursor, so refreshes complete their enumeration before returning. The portable
drive factory lists and selects the current Windows drive, then adds other
populated drive-letter roots which FreeBASIC `Dir` can enumerate. Other targets
list `/`. Empty non-current volumes require platform-specific discovery and are
not included by this SDK-free implementation.

### 5.5 Frames and picture surfaces

`groupbox_Create` provides a labeled classic frame. `picturebox_Create`
provides a framed surface that clips child widgets to its client rectangle.
Both work through gfxlib and do not create a platform-native control.
`groupbox_SetBackgroundColor` and `groupbox_SetForegroundColor` install
retained client and caption colors. Their matching Get and Clear calls expose
the override state and return the frame to theme-driven rendering.

PictureBox uses the active `GUI_COLOR_WINDOW_BG` theme color by default.
`picturebox_SetBackgroundColor` installs a retained client color,
`picturebox_GetBackgroundColor` reports it, and
`picturebox_ClearBackgroundColor` restores theme-driven rendering. The getter
returns zero while no override is installed, so callers can distinguish a
literal black override from the default state.
The matching `picturebox_SetForegroundColor`,
`picturebox_GetForegroundColor`, and `picturebox_ClearForegroundColor` calls
control display text without changing the global theme.

For redraw-safe application graphics, `picturebox_SetPixelCanvas` selects a
fixed logical pixel surface and `picturebox_SetPixelCanvasToClient` follows
the PictureBox client size. Both use a bounded retained surface, allocate
only on the first `picturebox_SetPixel`, `picturebox_DrawLine`,
`picturebox_DrawStyledLine`, `picturebox_DrawStyledRectangle`, or
`picturebox_DrawEllipse`, and preserve the old/new intersection on a
resize. `picturebox_DrawLine` clips a retained Bresenham line to the
configured canvas, including a wholly off-client line that changes nothing.
`picturebox_DrawStyledLine` applies a 16-bit most-significant-bit-first
mask and preserves its phase from the original start through clipping.
`picturebox_DrawStyledRectangle` follows FreeBASIC's `LINE ..., B, style`
perimeter order, including clipping-phase adjustments and duplicate corner
visits. Its nonzero `filled` mode matches `BF`: the inclusive fill deliberately
ignores the style mask.
`picturebox_DrawEllipse` adds a retained QuickBASIC-style `CIRCLE` primitive:
aspect values above one narrow the X radius, values below one narrow Y, and
zero selects omaGUI's square-pixel default. Full turns may fill; partial turns
retain only sampled arc pixels and ignore `filled`. Negative start or end
angles additionally retain the matching center radial line. Angles, sample
counts, radii, and canvas writes are bounded before drawing. The API uses only
FreeBASIC math and the retained client surface, never a host drawing context.
`picturebox_ReadPixel` reports both a color and an
occupied flag, so black is an ordinary retained color. `picturebox_ClearPixels`
releases pixel storage while keeping the canvas configuration. Pixels are
redrawn through gfxlib; no native bitmap, window handle, or platform SDK is
involved. Programs still choose their own circle, paint, and other drawing
algorithms.

### 5.6 HTML document viewer

`htmlview_Create` makes a display-only HTML widget. It is intended for local
help, generated reports, device-description text, and other small technical
documents. The implementation uses omaGUI drawing, embedded fonts, and
standard FreeBASIC file access. It does not depend on an operating-system web
control, a browser engine, or a third-party HTML parser.

```freebasic
Dim helpView As Widget Ptr

helpView = htmlview_Create("help", 12, 12, 520, 340)
gui_AddWidget helpView

If htmlview_SetHtml( _
    helpView, _
    "<h1>Device help</h1><p>Open the <a href='dd:item/42'>" & _
    "status item</a>.</p>" _
) = 0 Then
    Print htmlview_GetLastError(helpView)
End If
```

The public document operations are:

| API | Purpose |
| --- | --- |
| `htmlview_SetHtml` | Replace the document from a FreeBASIC string |
| `htmlview_LoadFile` | Replace the document from a local file |
| `htmlview_BeginSetHtml` | Begin a cooperative replacement from a FreeBASIC string |
| `htmlview_BeginLoadFile` | Begin a cooperative replacement from a local file |
| `htmlview_UpdateLoad` | Perform one caller-budgeted parsing slice |
| `htmlview_IsLoading` | Test whether a cooperative replacement is pending |
| `htmlview_GetLoadState` | Read the idle, loading, complete, failed, or cancelled state |
| `htmlview_GetLoadProgress` | Read approximate source progress from 0 through 100 |
| `htmlview_GetLoadError` | Read the last cooperative-load diagnostic |
| `htmlview_CancelLoad` | Discard a pending replacement without changing the visible document |
| `htmlview_Clear` | Release the source and current layout |
| `htmlview_Reflow` | Rebuild layout after an application changes the width |
| `htmlview_SetBasePath` | Set the directory used by relative local image paths |
| `htmlview_SetColors` | Set the default background, text, and link colors |
| `htmlview_SetImageHandler` | Install an application provider for checked image schemes |
| `htmlview_GetTitle` | Read decoded `TITLE` text |
| `htmlview_GetPlainText` | Read the displayed document as plain text |
| `htmlview_GetLastError` | Read the last load or layout diagnostic |
| `htmlview_GetBasePath` | Read the current local image directory |
| `htmlview_GetContentHeight` | Read the laid-out document height in pixels |
| `htmlview_GetScroll` and `htmlview_SetScroll` | Read or set the vertical pixel offset |

The widget reflows automatically when its width changes. It supports pointer
wheel scrolling, its integrated vertical scrollbar, and the Up, Down, Home,
End, Page Up, and Page Down keys while focused. The scrollbar is owned by the
viewer and must not be added separately to the GUI registry.

#### Cooperative document loading

`htmlview_SetHtml` and `htmlview_LoadFile` remain synchronous for small help
pages and callers that need an immediate result. Applications with large
generated reports or captured pages can use the cooperative entry points:

```freebasic
If htmlview_BeginLoadFile(helpView, "help/large-report.html") = 0 Then
    Print htmlview_GetLoadError(helpView)
End If

' A registered widget advances automatically in gui_UpdateAll.
While htmlview_IsLoading(helpView)
    gui_UpdateAll
    gui_RenderAll
Wend

If htmlview_GetLoadState(helpView) = HTMLVIEW_LOAD_FAILED Then
    Print htmlview_GetLoadError(helpView)
End If
```

The parser runs on omaGUI's existing update thread. Each widget update grants
it a four-millisecond slice, then normal input and rendering continue. An
application that updates a widget outside the GUI manager can call
`htmlview_UpdateLoad(helpView, milliseconds)` explicitly. The requested
budget is clamped to a safe range.

The last completed document, its links, and its scrollable content remain
active throughout parsing. A small progress overlay is drawn over that page.
The staging document becomes visible through one ownership transfer only
after layout succeeds. Failure or `htmlview_CancelLoad` releases the staging
items and leaves the visible document unchanged. A width change restarts the
staged layout at the new width, so progress can return to zero after a resize.

Load state is one of `HTMLVIEW_LOAD_IDLE`, `HTMLVIEW_LOAD_LOADING`,
`HTMLVIEW_LOAD_COMPLETE`, `HTMLVIEW_LOAD_FAILED`, or
`HTMLVIEW_LOAD_CANCELLED`. Progress is approximate because it follows source
position rather than rendered item count. Parsing yields between bounded
parser operations. One token layout or one native image decode remains an
atomic operation on the GUI thread, so applications should retain the public
document and image-size limits.

#### Supported display subset

The parser is deliberately conservative. It handles malformed and unknown
markup safely, but it does not claim to implement a complete web browser.

| Category | Supported elements and behavior |
| --- | --- |
| Document | `html`, `head`, `title`, `body`, and readable `frameset` fallback |
| Blocks | `h1` through `h6`, `p`, `div`, `br`, `hr`, `blockquote`, `pre`, `header`, `nav`, `main`, `section`, `article`, `aside`, `footer`, `details`, `summary`, `figure`, `figcaption`, and `address` |
| Inline text | `b`, `strong`, `i`, `em`, `u`, `ins`, `small`, `big`, `code`, `tt`, `kbd`, `samp`, `span`, `font`, `mark`, `s`, `del`, `sub`, `sup`, `q`, `cite`, `abbr`, `time`, `data`, `var`, `dfn`, `bdi`, and `bdo` |
| Collections | `ul`, `ol`, `li`, `dl`, `dt`, `dd`, `table`, `thead`, `tbody`, `tfoot`, `tr`, `th`, and `td`; table cells accept bounded `colspan` values |
| Navigation | `a` with an `href` value; `frame` and `iframe` sources become deduplicated application-routed links instead of blank nested browsing contexts |
| Images | `img` loads local BMP, PNG, GIF87a/GIF89a, and baseline JPEG; missing or nonlocal sources use bracketed `alt` or `title` text, while an explicit empty `alt` and untitled images no larger than 32 by 32 pixels remain silent |
| Attributes | `src`, `href`, `alt`, `align`, `bgcolor`, `text`, `link`, `color`, and `style` where applicable |
| Inline style | `color`, `background-color`, `font-weight`, `text-decoration`, `white-space`, and `text-align` |
| Colors | `#RGB`, `#RRGGBB`, and a small set of common color names |
| Entities | Common text, punctuation, currency, and symbol names plus checked decimal or hexadecimal numeric references |

Bold text uses the embedded bold font. The current embedded font set has no
italic face, so `i` and `em` retain ordinary text rendering. Unknown tags are
ignored while their ordinary visible text remains. Comments are skipped.
`script` and `style` are treated as HTML raw-text elements. Their complete
contents are skipped with a bounded closing-tag search instead of being
tokenized as markup, so comparison operators and large application-state
blocks cannot confuse or needlessly slow the parser. Inline `svg` trees are
also skipped because their path data and internal titles are implementation
detail rather than readable page content. External style sheets, cascading
layout, forms, media, cookies, storage, and network access are outside this
widget.

If a script, canvas, object, or embedded application supplies no ordinary
fallback text, the viewer displays a short explanation that the interactive
content requires a full browser. This is a successful static fallback, not a
claim that the application ran. Legacy framesets expose up to 32 unique frame
sources as normal links, using familiar names such as `Contents` and `Main
page` when the source document provides the conventional frame names.

Semantic HTML 5 containers are treated as ordinary blocks. NAV links receive
line separation because their spacing is usually supplied by CSS which the
viewer does not execute. Legacy BIG and FONT size markup selects one bounded
larger bitmap style. UTF-8 punctuation and Western European text are reduced
to readable embedded-font characters; invalid multi-byte input falls back to
Latin-1 one byte at a time. Other scripts use a visible replacement marker
instead of silently occupying zero pixels. TEMPLATE contents are not shown.
Historical definition lists may omit `DT` and `DD` end tags; a following term,
definition, or closing `DL` ends the previous item as required by HTML.
Immediately empty `DIV` elements are treated as CSS spacers or graphical
controls and do not allocate blank paragraphs. Directly adjacent links retain
a separating space even when CSS or an empty inline wrapper supplied it.

Tables are measured before their cells are laid out. Column widths therefore
remain aligned between rows, favor columns with wider content, and reflow when
the viewer width changes. Cells have a shared computed row height, padding,
background, and border. Links and inline formatting remain active inside a
cell. `htmlview_GetPlainText` represents cells with tabs and rows with line
breaks so copied technical data remains useful outside the widget. Nested
tables are flattened into the containing cell instead of creating recursive
grids. Legacy page-layout tables, identified by an explicit presentation role,
an obsolete zero border, or nested-table structure without headers or a
caption, are flattened into full-width document flow. This keeps old HTML 4
pages readable without weakening the grid used for genuine data tables. Cells
in a presentation-table row flow inline with separating spaces, while each row
starts a new line.

`htmlview_LoadFile` automatically uses the document's directory as its image
base. Call `htmlview_SetBasePath` before `htmlview_SetHtml` when HTML held in a
string uses relative image paths. Absolute local paths are also accepted.
Anything with a URI scheme, including `http:`, `https:`, `file:`, and `data:`,
falls back to `alt` text. Protocol-relative URLs and UNC network paths are
rejected before any filesystem access so they cannot cause blocking network
share lookups. The application can load or authorize such resources separately
without turning the widget into a network client.

An application-owned image scheme can be supplied with a callback. On
success, ownership of the returned `RasterImage Ptr` transfers to the viewer:

```freebasic
Function loadDocumentImage( _
    ByVal source As String, _
    ByVal context As Any Ptr, _
    ByRef image As RasterImage Ptr, _
    ByRef errorMessage As String _
) As Integer
    If Left(source, 9) <> "dd:image:" Then Return 0
    ' Validate the identifier and decode the caller-owned bytes here.
    Return rasterimage_LoadMemory(imageBytes(), imageByteCount, image, errorMessage)
End Function

htmlview_SetImageHandler helpView, @loadDocumentImage, applicationContext
```

Returning zero leaves normal local-file resolution available. A provider must
return a nonzero result only with a valid owned image pointer.

The raster loader identifies content by signature, so extensionless AMS image
files work. BMP and PNG are decoded by gfxlib. GIF87a and GIF89a, including
single-frame transparency, and 8-bit baseline sequential grayscale or YCbCr
JPEG are decoded by native FreeBASIC code. Animated GIF playback and
progressive JPEG are outside the minimum format set found in the DD corpus.
Oversized images are rejected, and wide images are proportionally fitted to
the document width with deterministic nearest-neighbor sampling.

Input is limited to 2 MiB. Parsing also has a three-second wall-clock safety
budget, checked between parser operations. A layout is limited to 65,536
items, styled nesting to 64 levels, list nesting to 16 levels, legacy frame
navigation to 32 unique links, and retained images to 33,554,432 pixels. Each
image file is limited to 32 MiB, 4,096 pixels on either axis, and 16,777,216
decoded pixels. A malformed raw-text element, time budget, or other limit
failure returns zero and sets `htmlview_GetLastError`; it does not overrun the
bound. UTF-8 source bytes and numeric Unicode entities are retained, but the
embedded bitmap fonts can only draw glyphs present in those fonts.

#### Link handling

The viewer reports links without deciding what they mean. Polling is the
simplest option:

```freebasic
Dim href As String

If htmlview_PopLink(helpView, href) Then
    Print "Navigate to: "; href
End If
```

Applications that prefer a callback can install one with this shape:

```freebasic
Sub onHelpLink( _
    ByVal htmlWidget As Widget Ptr, _
    ByVal href As String, _
    ByVal context As Any Ptr _
)
    ' Map href to application navigation here.
End Sub

htmlview_SetLinkHandler helpView, @onHelpLink, applicationContext
```

A completed click updates the polling value and invokes the callback. The
application can therefore use either interface. omaGUI never opens the URI,
which keeps DD item navigation and security policy in application code.

The standalone `examples/htmlview_demo.bas` program is a compact reusable
example. Pass a local HTML path as its first command-line argument to inspect
a captured page. `tests/htmlview_smoke.bas` covers parsing, loading, layout,
input, limits, rendering, and destruction. `tests/htmlview_site_compat.bas`
covers the legacy FBXL and modern FBXL Lotide landing-page structures.
`tests/htmlview_stress_compat.bas` covers large application shells, malformed
raw-text elements, framesets, and static interactive-content fallbacks.
`tests/htmlview_corpus_audit.bas` accepts a line-oriented list of local HTML
captures and verifies bounded readable layout for every listed page.
`tests/htmlview_incremental_smoke.bas` covers cooperative progress, atomic
replacement, cancellation, failure preservation, resize restart, automatic
GUI update advancement, and staged ownership cleanup.

### 5.6.1 CHM archives and linked resources

The `chmarchive` reader opens version 3 CHM archives with an LZX reset table.
`chmarchive_ReadFile` reads one member with a caller-specified byte limit and
keeps at most one decompressed reset interval cached. It does not extract
members to disk. The decoder is based on libmspack; its license is in
`LICENSES/LGPL-2.1.txt`.

`htmlview_BeginSetHtmlAtPath` gives an in-memory page a base path for relative
links. `htmlview_SetResourceHandler` supplies linked HTML or CSS text, and
`htmlview_SetImageHandler` supplies raster images. `htmlview_GotoAnchor`
scrolls to an element ID or named anchor. These APIs let an application show
help pages from an archive without first extracting its members.

### 5.6.2 RTF documents

`rtfview_Create` creates a read-only document view. Load RTF with
`rtfview_SetRtf`, or UTF-8 text with `rtfview_SetPlainText`. Both report success;
`rtfview_GetError` reports a parse error. `rtfview_SetColors` sets the reading
surface independently of its parent, and `rtfview_SetMargins` sets pixel
insets. The viewer retains paragraph formatting, font sizes, colors, bold,
italic, underline, and Unicode text. Embedded pictures and objects are
skipped. Input is limited to 1 MiB and internal tables have fixed bounds.

### 5.7 Popup menus

Menus hold up to `MENU_MAX_ITEMS`, currently 64. Two callback styles are
available:

- `menu_AddItem` can attach `Sub(ByVal index As Integer)` to each item.
- `menu_SetSelectionHandler` installs one
  `Sub(ByVal context As Any Ptr, ByVal index As Integer)` handler for the menu.

The shared handler is useful for generated combo and date popups because it can
carry the owning control as its context. `menu_ClearItems` resets the current
choices. A click outside a visible menu dismisses it.

`menu_SetTextYOffset` moves captions vertically by a bounded number of pixels
without moving highlights or their pointer hit areas. The default offset is
zero; applications retaining an older popup layout can choose a different
caption position.

### 5.8 Menu bars

`menubar_Create` provides a classic horizontal strip with bounded drop-down
commands. Add headings with `menubar_AddMenu`, retain the returned index, and
add commands or `"-"` separators with `menubar_AddItem`:

```freebasic
Dim bar As Widget Ptr
Dim fileMenu As Integer

bar = menubar_Create("main_menu", 0, 0, 640)
fileMenu = menubar_AddMenu(bar, "&File")
menubar_AddItem bar, fileMenu, "&Open..."
menubar_AddItem bar, fileMenu, "-"
menubar_AddItem bar, fileMenu, "E&xit"
menubar_SetItemChecked bar, fileMenu, 0, -1
menubar_SetItemShortcut _
    bar, fileMenu, 0, FB.SC_O, INPUT_MODIFIER_CONTROL, "Ctrl+O"
menubar_SetSelectionHandler bar, @onMenuCommand, applicationContext
gui_AddWidget bar
```

The shared handler receives `(context, menuIndex, itemIndex)`. Pointer commands
activate on a matching release, while an outside click dismisses the drop-down.
Left and Right switch headings; Up and Down wrap over commands while skipping
separators; Home, End, Enter, Space, and Escape follow desktop conventions.
Ampersands mark visibly underlined A-to-Z mnemonics and are omitted from the
rendered label. Alt plus a heading's mnemonic opens it even when another
control owns keyboard focus; the first heading owns a duplicate mnemonic.
`menubar_ActivateItem(bar, menuIndex, itemIndex)` invokes a command through the
same checked callback path as pointer and keyboard activation. It returns zero
for invalid indexes, disabled commands, and separators. On success it closes
the open menu before invoking the callback, which may destroy the widget.
`menubar_Activate` alone toggles the menu strip; it does not choose a command.

`menubar_SetItemChecked` stores a command's Boolean check state and
`menubar_GetItemChecked` reads it. Separators reject checked-state changes.
The check glyph uses backend line drawing, so it requires neither a symbol font
nor a host menu API. `menubar_SetItemEnabled` dims a disabled command and keeps
pointer and keyboard activation from selecting it; `menubar_GetItemEnabled`
queries that state. Separators reject enabled-state changes. The widget
contains no application policy and does not call a native menu API.
`menubar_SetItemLabel` replaces a command label and recalculates the popup
width. `menubar_SetItemVisible` and `menubar_GetItemVisible` control retained
rows; hidden commands take no popup space and cannot be selected with pointer,
keyboard, or programmatic activation.
`menubar_SetItemShortcutText` stores an optional separately measured hint and
recalculates the popup width; `menubar_GetItemShortcutText` reads it. Use
`menubar_SetItemShortcut(bar, menuIndex, itemIndex, scanCode, modifiers, text)`
when the command should dispatch a key. It accepts one gfxlib scan code and one
exact combination of `INPUT_MODIFIER_CONTROL`, `INPUT_MODIFIER_ALT`, and
`INPUT_MODIFIER_SHIFT`; additional modifiers do not match. A zero scan code,
zero modifiers, and empty text clear a binding. `menubar_GetItemShortcut`
returns the stored scan code and modifier bits only when a binding exists.
The MenuBar receives a bound accelerator while another child has focus, but the
manager routes it to one eligible MenuBar in the active modal/form tree. Hidden,
disabled, and separator commands never dispatch. Plain shortcut text remains a
presentation-only hint, so applications can opt into bindings deliberately.

#### Nested popup trees

Use an ordinary `Menu` as the popup attached to a heading when a command needs
its own submenu. Add the submenu before attaching the root. The MenuBar then
owns the root and all descendant popups, and removing the MenuBar releases the
whole tree. Do not separately destroy an attached popup. Commands in every
level keep the Menu widget's selection handler, checked/enabled/visible state,
and keyboard accelerator behavior. A single ampersand marks an underlined
letter that activates the first eligible matching item while the popup is
open; doubled ampersands display one literal ampersand.

```freebasic
Dim bar As Widget Ptr
Dim filePopup As Widget Ptr
Dim recentPopup As Widget Ptr
Dim fileHeading As Integer

bar = menubar_Create("main_menu", 0, 0, 640)
filePopup = menu_Create("file_popup", 0, 0)
recentPopup = menu_Create("recent_popup", 0, 0)
menu_AddCommand recentPopup, "Project A", 1
menu_AddSubmenu filePopup, "Recent", recentPopup
fileHeading = menubar_AddMenu(bar, "&File")
menubar_SetMenuPopup bar, fileHeading, filePopup
gui_AddWidget bar
```

`menubar_SetMenuPopup` registers a detached root when necessary and transfers
its lifetime to the MenuBar. Do not separately register or destroy that
attached root.

### 5.9 Toolbars

`toolbar_Create` provides a nonfocusable classic command strip. Add commands
with `toolbar_AddButton(widget, text, width)` and visual group separators with
`toolbar_AddSeparator`. A zero button width measures the label and applies
standard padding; an explicit width is checked against the public bound.

```freebasic
Dim tools As Widget Ptr

tools = toolbar_Create("main_tools", 0, 22, 640, 34)
toolbar_AddButton tools, "Open", 72
toolbar_AddButton tools, "Save", 72
toolbar_AddSeparator tools
toolbar_AddButton tools, "Run", 64
toolbar_SetSelectionHandler tools, @onToolCommand, applicationContext
gui_AddWidget tools
```

The handler receives `(context, itemIndex)`. A pointer press activates only if
it is released over the same enabled command. Use `toolbar_SetItemEnabled` and
`toolbar_GetItemEnabled` to share availability policy with menus;
`toolbar_GetItemCount` and `toolbar_GetItemLabel` provide bounded inspection.
`toolbar_ActivateItem` applies the identical checks for programmatic commands.
The toolbar does not assign application shortcuts or call a host toolbar API.

### 5.10 Textboxes

```freebasic
Dim editor As Widget Ptr

editor = textbox_Create( _
    "editor", "Multiline text", 12, 12, 420, 240, _
    -1, -1, TEXTBOX_SCROLLBAR_ALWAYS _
)
gui_AddWidget editor
```

The `m` and `ww` constructor arguments enable multiline mode and word wrapping.
The final argument selects one of three vertical scrollbar policies:

| Policy | Behavior |
| --- | --- |
| `TEXTBOX_SCROLLBAR_NONE` | Never show a vertical bar |
| `TEXTBOX_SCROLLBAR_AUTO` | Show it only when visual rows overflow |
| `TEXTBOX_SCROLLBAR_ALWAYS` | Reserve the gutter and show a disabled bar when content fits |

The auto policy is the default. Use `textbox_SetVerticalScrollbar` to change it
and `textbox_GetVerticalScrollbarMode` to query it.
`textbox_SetHorizontalScrollbar` applies the same policies to an owned bottom
bar, and `textbox_GetHorizontalScrollbarMode` queries it. Horizontal ranges are
measured in pixels from the longest logical line and share the editor's existing
cursor-following offset. The bar is available only for multiline, non-wrapped
text. When both bars are visible they reserve client space from one another and
leave the bottom-right corner outside both tracks.

Multiline rendering, cursor movement, hit testing, selection, and scrolling
share the same wrapped visual-row model. The wheel scrolls three visual rows at
a time while content overflows. Dragging the thumb provides direct access to
the complete document.

Textboxes support pointer selection, Shift selection, Home, End, arrow keys,
Backspace, Delete, Return in multiline mode, and a right-click Copy, Cut, and
Paste menu. They also support these shortcuts:

- Ctrl+A: select all
- Ctrl+C: copy
- Ctrl+X: cut
- Ctrl+V: paste
- Ctrl+Z: undo
- Ctrl+Y: redo

Keyboard focus activates a textbox for editing without requiring a mouse
click. `textbox_SetAcceptsTab(widget, -1)` lets a multiline editor insert
spaces through the next four-column tab stop. `textbox_GetAcceptsTab` returns
the configured preference. Single-line textboxes reject this option.
Shift+Tab, Ctrl+Tab, and Alt+Tab remain focus-navigation inputs. Read-only mode
temporarily releases Tab to traversal and restores capture when editing is
enabled again.

Block indentation is separately opt-in through
`textbox_SetBlockIndent(widget, -1)`; query it with `textbox_GetBlockIndent`.
It enables Ctrl+] to indent and Ctrl+[ to unindent. When Tab capture is also
enabled, Tab indents a nonempty selection instead of replacing it. Tab without
a selection still inserts spaces through the next tab stop. Shift+Tab retains
reverse focus traversal, so opting in never traps keyboard focus in an editor.
Single-line controls reject this option; ordinary textboxes keep their previous
keyboard behaviour until an application enables it.

Application menus can call `textbox_IndentSelection(widget)` and
`textbox_UnindentSelection(widget)` independently of those keyboard settings.
Both operate on whole logical lines touched by the selection, or just the
caret's line if nothing is selected. A selection ending at the next line's
start does not include that next line. Wrapped display rows are not separate
logical lines, and CRLF pairs are never split.

Indent inserts `TEXTBOX_TAB_COLUMNS` spaces at each affected line start.
Unindent removes at most that many leading columns, accepting spaces or tabs
and never deleting other bytes. Empty selected lines can be indented, but an
unselected trailing empty line is left alone. CRLF, LF, CR, and mixed line
endings remain byte-for-byte intact. Selection endpoints move with the original
text, including a reverse selection; a caret in removed indentation clamps to
the start of that line.

These GUI-thread commands return nonzero only when the document changes and
record the whole block as one undo transaction. Invalid widgets, disabled or
read-only textboxes, and single-line controls return zero. Both the old document
and the final result must fit `TEXTBOX_HISTORY_MAX_STORED_BYTES`. Size checks and
buffer construction happen before history changes, so a capacity rejection or
an outdent with no leading whitespace leaves document, selection, and redo
state unchanged.

`textbox_SetLineNumbers(widget, -1)` enables a fixed logical line-number gutter
for a multiline editor; `textbox_GetLineNumbers` returns the configured state.
The gutter follows the active theme, sizes itself for the document's largest
line number, and stays outside text selection and horizontal scrolling. Word
wrapped continuation rows are left unnumbered. Single-line textboxes reject
the option.

`textbox_SetBackgroundColor` and `textbox_SetForegroundColor` install
per-widget client and ordinary text colors. Their Get calls report whether an
override is active, and their Clear calls return rendering to the theme.
Selection colors remain theme-controlled for readable focus feedback.

Application menu callbacks can invoke the identical operations with
`textbox_SelectAll`, `textbox_Copy`, `textbox_Cut`, and `textbox_Paste`.
Copy and selection remain available for display-only content; Cut and Paste
reject disabled textboxes without changing their text.
`textbox_HasSelection`, `textbox_CanUndo`, and `textbox_CanRedo` let a menu or
toolbar update command availability without depending on `TextBoxData`.
`textbox_GetCursorPosition` reports the bounded zero-based byte position,
`textbox_GetSelectionLength` reports selected bytes, and
`textbox_GetLineColumn` returns one-based logical coordinates while treating a
CRLF pair as one line break.
`textbox_GetSelectedText` returns a copy of the current selection.
`textbox_FindText(widget, text, start, matchCase, wrap)` returns the zero-based
match position or `-1`, selects the match, and scrolls it into view. Read-only
text remains searchable because selection is not a mutation.
`textbox_SetCursorPosition` clamps a requested zero-based position and can
optionally extend the current selection. `textbox_GotoLine` accepts one-based
line and column values, clamps the column to that line's end, and rejects a
line beyond the document without changing the cursor.
`textbox_ReplaceSelection` replaces a nonempty selection as one undoable edit.
`textbox_ReplaceAll` returns the number of nonoverlapping matches, performs
optional case folding, preflights the final size, constructs one exact-size
result buffer, and records the complete operation as one undo transaction.
`textbox_SetInputLimit(widget, byteLimit)` optionally bounds user/editor input
by native string bytes; zero keeps the default unlimited behavior. Typing,
paste, Return, Tab, and selection replacement use the remaining room after the
selected bytes are removed. Replace All and block indentation remain atomic.
Changing the limit does not rewrite existing text or constrain programmatic
SetText/Undo/Redo. See [TextBox input limits](TEXTBOX_INPUT_LIMIT.md) for the
full editing-policy contract.

`textbox_SetReadOnly(widget, -1)` keeps the textbox focusable, scrollable,
selectable, and copyable while rejecting typing, deletion, Cut, Paste, Undo,
and Redo. Query the current mode with `textbox_GetReadOnly`. This is distinct
from disabling a widget, which removes it from input and focus routing.

Undo and redo history is local to each textbox. It is bounded to 16 entries and
2,097,152 stored bytes. Repeated typing and deletion are grouped. Use
`textbox_SetText(widget, text, resetHistory)` for programmatic replacement,
and pass nonzero for `resetHistory` when the old editing history must not apply
to the new document.

Editor presentation can be configured with `textbox_SetFont`,
`textbox_SetFontScalePercent`, `textbox_SetZoomPercent`, and
`textbox_SetLineSpacing`. Drawing, wrapping, mouse placement, and caret
positioning use the same scaled metrics. `textbox_CenterPosition` scrolls a
source byte position toward the middle of the viewport.
`textbox_SetCaretVisible` can hide the blinking caret in passive views or
deterministic captures without changing keyboard focus or editing state.

The optional editor gutters support number styles, bookmark or breakpoint
markers, fold symbols, and click callbacks. A line visibility callback can
hide source lines from the visual row map. Current-line and line-range
highlights, indentation guides, and a right-edge column are separate options.
`textbox_SetTextDisplayHandler` changes displayed characters without changing
stored text; color, style, and indicator callbacks receive source positions.
Typed text, context menu, navigation, control shortcut, and ordered key event
callbacks let an application handle editor commands on the GUI thread.

`textbox_SetVirtualSpace` allows the caret and selection to move past an
unwrapped line end. The extra columns remain virtual until insertion, which
materializes them as spaces. Undo and redo restore the virtual caret state.
`TextBoxData.change_serial` advances when omaGUI changes stored text; clients
that edit `TextBoxData.text` directly must advance it themselves. Such direct
changes also need a viewport refresh. `TextBoxData.max_text_bytes` mirrors the
limit set by `textbox_SetMaxTextBytes` or `textbox_SetInputLimit` for clients
that inspect the record. `textbox_SetText` and undo/redo are not constrained
by that insertion limit.

The plain-text clipboard accepts at most `CLIPBOARD_MAX_TEXT_BYTES`, currently
2,097,152 bytes. By default it is a bounded process-local implementation, so
the normal omaGUI build has no host clipboard dependency. Define
`OMAGUI_ENABLE_HOST_CLIPBOARD` before `OMAGUI_IMPLEMENTATION` to opt into the
matching Windows or supported Unix desktop bridge. Define
`OMAGUI_DISABLE_HOST_CLIPBOARD` or the compatible `OMAGUI_PORTABLE_ONLY` name
to force the bounded process-local implementation, even when the host bridge
was enabled.

### 5.11 Status bars

`statusbar_Create` creates a classic noninteractive strip whose panel layout
tracks the widget's current anchored width. Add panels in display order with
`statusbar_AddPanel(widget, text, width)`. A positive width requests a fixed
panel; zero requests a flexible panel that shares remaining space with other
flexible panels.

```freebasic
Dim status As Widget Ptr

status = statusbar_Create("main_status", 0, 456, 640, 24)
statusbar_AddPanel status, "Ready", 0
statusbar_AddPanel status, "Ln 1, Col 1", 140
statusbar_SetPanelAlignment status, 1, BACKEND_ALIGN_RIGHT
gui_AddWidget status
gui_SetAnchors status, _
    GUI_ANCHOR_LEFT Or GUI_ANCHOR_RIGHT Or GUI_ANCHOR_BOTTOM
```

Use `statusbar_SetPanelText` for updates and `statusbar_GetPanelText` or
`statusbar_GetPanelCount` for inspection. Panels use left-aligned text by
default. `statusbar_SetPanelAlignment` validates `BACKEND_ALIGN_LEFT`,
`BACKEND_ALIGN_CENTER`, or `BACKEND_ALIGN_RIGHT`, and
`statusbar_GetPanelAlignment` returns the retained choice. A bar retains at
most `STATUSBAR_MAX_PANELS`, and each stored string is bounded by
`STATUSBAR_MAX_TEXT_BYTES`. Text that cannot fit is drawn with an ellipsis;
the stored string remains unchanged. The implementation uses only OMAGUI
backend primitives and does not create a platform-native status control.

### 5.12 Subwindows

`subwindow_Create` creates a draggable child window with a title bar. The final
constructor argument controls whether the close button is available and
defaults to enabled.
`subwindow_SetTitleTextYOffset` makes a bounded vertical caption adjustment
without changing the title bar, its controls, or the child client area.

Without an application callback, close hides the complete window tree.
`subwindow_CloseRequested` reports that state, and `subwindow_Reopen` restores
and raises the hidden tree. `subwindow_SetClosable` changes close availability.
`subwindow_SetControlBox` is the explicit equivalent used by form-property
bindings, while `subwindow_GetControlBox` reports the retained value.

`subwindow_SetMinButton` and `subwindow_SetMaxButton` independently enable the
portable minimize and maximize controls; their matching getters return
normalized false or true values. A minimize click enters
`SUBWINDOW_STATE_MINIMIZED`. A maximize click toggles between maximized and the
saved normal rectangle, and draws a restore glyph while maximized. The controls
are rendered and hit-tested by omaGUI itself, so headless, X11, and Windows
backends share the same behavior without platform window APIs. Borderless
subwindows retain the configured values but do not display title controls.

`subwindow_SetCloseHandler` installs a
`Sub(ByVal window As Widget Ptr)` callback when the application needs to save,
confirm, or remove the window itself.

`subwindow_SetClientColor` and `subwindow_ClearClientColor` select a retained
client fill without changing the active theme; `subwindow_GetClientColor`
reports whether an override is active. `subwindow_SetBorderStyle` accepts
`SUBWINDOW_BORDER_NONE`, `SUBWINDOW_BORDER_FIXED_SINGLE`,
`SUBWINDOW_BORDER_SIZABLE_SINGLE`, or `SUBWINDOW_BORDER_FIXED_DOUBLE`.
`subwindow_GetBorderStyle` returns the retained mode, and
`subwindow_GetClientTopInset` lets generated child layouts start below the
title bar or at zero for a borderless window. Sizable single windows expose a
captured bottom-right resize grip with checked minimum and container bounds.

`subwindow_SetWindowState` accepts `SUBWINDOW_STATE_NORMAL`,
`SUBWINDOW_STATE_MINIMIZED`, or `SUBWINDOW_STATE_MAXIMIZED`, and
`subwindow_GetWindowState` returns the current value. Minimization retains a
visible title surface at the bottom of the parent or viewport, permits bounded
horizontal placement, and suspends descendant input. Maximization fills the
available container. Both non-normal states follow later parent or host viewport
resizes; input is cancelled for the frame in which absolute geometry is
re-resolved. A borderless minimized window still draws the portable title
surface, including in containers smaller than the normal title dimensions.
Returning to normal restores the rectangle saved before the first state
transition.

### 5.13 File and confirmation dialogs

The file APIs are:

- `filedialog_Create` for an open dialog in the current directory
- `filedialog_CreateAtPath` for an open dialog at an explicit path
- `filedialog_CreateSaveAtPath` for save mode and an initial filename

`confirmdialog_Create` creates a modal message with a configurable confirmation
label and a Cancel option. It retains the established `1`/`-1` result contract
and `<name>_confirm` / `<name>_cancel` child names. Its two action buttons
retain the original right-aligned placement and plain border.
Enter still activates the primary choice when keyboard focus allows the
dialog default action.

`confirmdialog_CreateChoices` creates a portable one-, two-, or three-button
decision dialog. Each nonempty label has a caller-selected nonzero result, and
the optional `closeResult` chooses the value reported by the title-bar close
action. Buttons use `<name>_choice_0` through `<name>_choice_2`; the first is the
default action, and the button matching `closeResult` is the cancel action.
This is suitable for Yes/No/Cancel and Abort/Retry/Ignore prompts without a
platform-native dialog API.

`filedialog_SetFilter(dialog, "*.bas")` restricts file entries while retaining
all navigable directories. A semicolon-delimited list such as
`"*.bas;*.bi"` accepts entries matching either pattern. The bounded matcher
treats `*` and `?` as wildcards, compares case-insensitively on every target,
and rejects path separators, drive separators, control bytes, empty list
entries, lists over `FILEDIALOG_MAX_FILTER_BYTES`, and lists containing more
than `FILEDIALOG_MAX_FILTER_PATTERNS` alternatives.
`filedialog_GetFilter` returns the active value.
`filedialog_SetTitle` replaces the dialog-owned subwindow title with a nonempty
string of at most 255 bytes. It rejects embedded NUL bytes and leaves the
existing title unchanged when validation fails.

`filedialog_GetWindow` and `confirmdialog_GetWindow` return borrowed pointers
to the generated subwindows. `confirmdialog_GetMessageLabel` returns its
generated message label. Callers can use the ordinary widget setters to style
their own dialogs. These accessors return zero for a wrong widget type, and
the pointers expire when the dialog root is removed.

`filedialog_GetResultState` and `confirmdialog_GetResultState` return:

| Value | Meaning |
| ---: | --- |
| `0` | Still pending |
| `1` | Accepted or confirmed |
| `-1` | Cancelled or closed |

`filedialog_GetSelectedFile` returns a path only after acceptance. Poll the
result from the application loop, copy any needed result, then remove the
dialog root with `gui_RemoveWidget`. The manager destroys its descendants and
releases the modal root.

### 5.14 Splitters

`splitter_Create(name, x, y, width, height, orientation)` creates a focusable
divider. `SPLITTER_VERTICAL` is the default and moves along x;
`SPLITTER_HORIZONTAL` moves along y. Positions are local to the parent, not
absolute screen coordinates. Eight pixels (`SPLITTER_DEFAULT_THICKNESS`) is a
useful grip thickness; the host chooses its span and the surrounding pane sizes.

```freebasic
Dim divider As Widget Ptr
divider = splitter_Create("project_divider", 240, 20, 8, 400)
If divider <> 0 Then
    gui_AddWidget divider
    splitter_SetRange divider, 120, 480
End If
```

`splitter_SetRange(widget, minimum, maximum)` accepts an inclusive nonnegative
range up to `SPLITTER_MAXIMUM_EXTENT` (1,048,576 local pixels). An inverted or
out-of-bounds range fails without changing existing state. A valid range clamps
the current position. `splitter_SetPosition` also clamps; both setters return
nonzero on success, including an unchanged position. Neither fires a callback.
`splitter_GetPosition` returns the current x or y, or `-1` for an invalid widget.
`splitter_GetRange` fills two `ByRef Integer` outputs and returns nonzero on
success; failed reads clear both outputs.

Install a `SplitterChangeHandler` with
`splitter_SetChangeHandler(widget, handler, context)`. The callback receives
`ByVal context As Any Ptr` and `ByVal position As Integer`, synchronously on the
GUI thread, after pointer or keyboard input changes the position. The context
is borrowed, not freed by the widget. The callback may resize adjacent panes
or remove the divider through the GUI manager. A null handler disables
notifications. The splitter never takes ownership of adjacent panes.

Dragging preserves the initial grab offset, clamps at the range endpoints,
and includes the final release position. `splitter_IsDragging` reports an
active drag. A focused divider accepts its orientation's arrow keys in
four-pixel steps, Shift+Arrow in sixteen-pixel steps, and Home/End for the
endpoints. Ctrl/Alt combinations remain available to the application.

Hidden, disabled, or modal-blocked dividers cancel a drag and require a fresh
press after release. If application layout moves the containing coordinate
system during a drag, call `gui_CancelInput(divider)` before relayout. This
invalidates the old grab origin without manufacturing a release or a change
notification. The grip uses the active theme and backend drawing primitives,
with no platform-specific control or cursor API.

## 6. Drawing widgets

The following constructors make registry-managed drawing elements:

- `linewidget_Create`
- `rectwidget_Create`
- `circlewidget_Create`
- `curvewidget_Create`

They participate in parent positioning, clipping, visibility, and paint order
like other widgets. The curve is quadratic and stores a control point relative
to its first endpoint.

## 7. Imported graphic shapes

Graphic shapes represent imported HMI elements and lightweight custom drawing.
They are static by default. Call `graphicshape_SetInteractive` only for shapes
that should participate in routed input.

### 7.1 Shape kinds

The supported numeric identifiers are stable:

| Value | Constant | Value | Constant |
| ---: | --- | ---: | --- |
| 1 | `GUI_SHAPE_LINE` | 15 | `GUI_SHAPE_CONNECTOR` |
| 2 | `GUI_SHAPE_RECTANGLE` | 16 | `GUI_SHAPE_CONTROL` |
| 3 | `GUI_SHAPE_ROUNDED_RECTANGLE` | 17 | `GUI_SHAPE_CHECKBOX` |
| 4 | `GUI_SHAPE_ELLIPSE` | 18 | `GUI_SHAPE_COMBOBOX` |
| 5 | `GUI_SHAPE_POLYLINE` | 19 | `GUI_SHAPE_LISTBOX` |
| 6 | `GUI_SHAPE_POLYGON` | 20 | `GUI_SHAPE_EDITBOX` |
| 7 | `GUI_SHAPE_CURVE` | 21 | `GUI_SHAPE_CALENDAR` |
| 8 | `GUI_SHAPE_TEXT` | 22 | `GUI_SHAPE_DATE_TIME_PICKER` |
| 9 | `GUI_SHAPE_TEXTBOX` | 23 | `GUI_SHAPE_RADIO_BUTTON_GROUP` |
| 10 | `GUI_SHAPE_BUTTON` | 24 | `GUI_SHAPE_TREND_CONTROL` |
| 11 | `GUI_SHAPE_IMAGE` | 25 | `GUI_SHAPE_TREND_PEN` |
| 12 | `GUI_SHAPE_ARC` | 26 | `GUI_SHAPE_MULTI_PEN_TREND` |
| 13 | `GUI_SHAPE_PIE` | 27 | `GUI_SHAPE_ALARM_CLIENT` |
| 14 | `GUI_SHAPE_CHORD` | 28 | `GUI_SHAPE_EMBEDDED_SYMBOL` |

### 7.2 Construction and render options

Use `graphicshape_Create` for basic stroke, fill, and label properties.
`graphicshape_CreateStyled*` adds common style and text arguments.
`graphicshape_CreateWithOptions` accepts the complete
`GraphicShapeRenderOptions` structure. Initialize that structure with
`graphicshape_DefaultOptions` before overriding fields.

Options include:

- stroke, fill, gradient, and text colors
- solid, vertical gradient, horizontal gradient, and horizontal edge-gradient
  fill modes
- line width and rounded-corner radius
- object, stroke, and fill alpha
- embedded font, horizontal alignment, vertical alignment, and text fitting
- clipping to the shape bounds
- up to eight positioned gradient stops

Paths accept up to 16 points through `graphicshape_SetPathPoint`.
`graphicshape_SetRenderOptions` replaces the complete option set. Dedicated
setters are available for alpha, gradient, gradient stops, clipping, corner
radius, and path points.

Object alpha multiplies the component alpha. For example, object alpha 128 and
fill alpha 128 produce an effective fill alpha of approximately 64. Text uses
object alpha. `graphicshape_SetOutlineAlpha` is an alias for stroke alpha.

`graphicshape_RenderWithOptions` draws directly without allocating or
registering a widget. It is intended for importers that already own their shape
records.

### 7.3 Interactive imported controls

```freebasic
Declare Sub onModeChanged(ByVal changed As Widget Ptr)

Dim importedCombo As Widget Ptr
importedCombo = graphicshape_Create( _
    "mode", GUI_SHAPE_COMBOBOX, 12, 12, 150, 28, _
    RGB(40, 40, 40), RGB(245, 245, 245), -1, "Mode" _
)

graphicshape_AddItem importedCombo, "Manual"
graphicshape_AddItem importedCombo, "Automatic"
graphicshape_SetInteractive importedCombo, -1, @onModeChanged
gui_AddWidget importedCombo
```

The change callback receives the owning `Widget Ptr`. Read its new state with
the public accessors. `graphicshape_GetChangeCount` also supports deterministic
polling. Programmatic setters do not need applications to manipulate private
shape storage.

| Shape family | Input behavior |
| --- | --- |
| Button | Pointer press and Enter activation |
| Checkbox | Pointer or Enter toggle |
| Textbox and editbox | Focused text input and Backspace |
| Combo box and date-time picker | Real popup option menu, wheel, Up, Down, and Enter |
| Listbox and alarm client | Pointer row selection, wheel, Up, and Down |
| Calendar | Pointer day selection |
| Radio-button group | Pointer, wheel, Up, and Down choice selection |
| Control and trend controls | Pointer and keyboard value changes from 0 through 100 |

Combo and date popups are separate menu widgets, bound to the same owning
window tree. They open upward when there is not enough room below, close after
selection, and dismiss on an outside click. Use
`graphicshape_IsDropdownOpen` when application logic needs to inspect this
state.

Choice controls hold up to `GRAPHICSHAPE_MAX_ITEMS`, currently 16. Editable
shape text is limited to `GRAPHICSHAPE_MAX_INPUT_LENGTH`, currently 256
characters. Use `graphicshape_AddItem`, `graphicshape_ClearItems`,
`graphicshape_GetSelectedIndex`, `graphicshape_GetSelectedItem`,
`graphicshape_SetText`, `graphicshape_GetText`, `graphicshape_SetValue`, and
`graphicshape_GetValue`.

Image and embedded-symbol kinds currently provide generic placeholder
rendering. Decoding external image payloads, galaxy files, animation rules, and
application command policy remain importer or application responsibilities.

## 8. Demo guide

Build and run the demo from the repository root:

```powershell
fbc demo.bas
.\demo.exe
```

The demo intentionally covers the complete widget surface and the major
backend display modes:

- every standard widget and primitive drawing widget
- all 28 graphic-shape kinds
- functional imported buttons, checkboxes, text input, lists, calendars,
  choices, radio groups, control values, trends, and alarm lists
- visible combo and date popup menus
- three multiline textbox scrollbar policies and mouse-wheel scrolling
- overlapping windows with order, parent binding, clipping, close, and reopen
- a resizable anchored layout
- 32-bit, 16-bit, 8-bit, 4-bit, and black-and-white 1-bit modes
- a live 0-to-255 gallery alpha control over a checkerboard

Press Escape to leave the demo. When testing window order, click a window or a
child to raise its complete tree. When testing alpha, use a 16-bit or 32-bit
mode so background blending is visible.

## 9. Deterministic input tests

The input module can replace physical input for one test process:

- `input_MockMouse(x, y, buttons, wheelDelta)`
- `input_MockText(text)`
- `input_MockKey(keycode, state)`
- `input_MockControlShortcut(keycode)`
- `input_ResetForTest()`

The mocks feed the same manager routing path as ordinary input. A test normally
calls `gui_UpdateAll` after changing mock state, then releases the mouse or key
and updates again.

The test programs cover backend colors and alpha, resizable layout, registry
ownership, modal routing, file dialogs, textbox editing and history, wrapped
text scrolling, HTML parsing and navigation, window order and clipping,
restored primitive widgets, release-edge popup menus, and interactive graphic
shapes. `tests/menu_release_smoke.bas` exercises popup input without requiring
a display driver.

To compile and run every test:

```powershell
Get-ChildItem tests -Filter *.bas | ForEach-Object {
    $testExe = $_.FullName -replace '\.bas$', '.exe'
    fbc $_.FullName -x $testExe
    if ($LASTEXITCODE -ne 0) { throw "Compile failed: $($_.Name)" }
    & $testExe
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $($_.Name)" }
}
```

Run the project linter with the configured local installation:

```powershell
& 'C:\Nextcloud\games\newjrpg\fblint\fb_linter.exe' .
```

The font generator is a separate build check:

```powershell
fbc tools\font_gen.bas
```

## 10. Current limits

- Native border resize support depends on gfxlib and its platform driver.
- Indexed color modes use palette mapping and do not blend alpha channels.
- Clip nesting is bounded at 128 levels.
- Listboxes hold 1024 items, popup menus 32 items, and menu bars hold 16
  headings with 32 commands per heading. Graphic-shape choices hold 16 items.
- Graphic-shape paths hold 16 points and gradients hold eight stops.
- Textbox history and clipboard text are bounded to avoid unbounded allocation.
- HTML documents are limited to 2 MiB, 65,536 layout items, 64 styled nesting
  levels, 16 list nesting levels, and a bounded local-image budget. The viewer
  is a display subset, not a general web browser.
- Imported image decoding, galaxy parsing, animation evaluation, and
  application-specific commands are outside this library layer.

## 11. Public API index

This index is a compact map to the declarations. Optional arguments and exact
types remain in the named public header.

### Backend and input

- Lifecycle and display: `backend_Init`, `backend_Exit`, `backend_GetSize`,
  `backend_SetWindowMode`, `backend_IsResizable`, `backend_GetColorDepth`,
  and `backend_SetColorDepth`
- Frame output: `backend_Clear`, `backend_Flip`, and `backend_SaveSnapshot`
- Primitives: `backend_PSet`, `backend_PSetAlpha`, `backend_Line`,
  `backend_LineEx`, `backend_Rect`, `backend_RectEx`, `backend_Circle`, and
  `backend_Curve`
- Text: `backend_Print`, `backend_PrintScaled`, `backend_PrintFont`,
  `backend_PrintFontAlpha`, `backend_PrintScaledFont`,
  `backend_PrintScaledFontAlpha`, `backend_PrintAligned`,
  `backend_PrintAlignedAlpha`, `backend_PrintAlignedScaled`, and
  `backend_PrintAlignedScaledAlpha`
- Measurement: `backend_GetTextWidth`, `backend_GetTextWidthScaled`,
  `backend_GetTextWidthFont`, `backend_GetTextWidthScaledFont`,
  `backend_GetTextHeight`, `backend_GetTextHeightScaled`,
  `backend_GetTextHeightFont`, and `backend_GetTextHeightScaledFont`
- Clip stack: `backend_SetClip` and `backend_ResetClip`
- Input state: `input_MouseX`, `input_MouseY`, `input_MouseButtons`,
  `input_MouseWheel`, `input_KeyPressed`, `input_KeyPressEvent`,
  `input_AnyKeyPressed`, `input_SetKeyEventMapping`,
  `input_ModifiedKeyPressEvent`, `input_ControlShortcutPressed`,
  `input_AltShortcutPressed`, and `input_PollTextInput`
- Test input: `input_MockMouse`, `input_MockKey`, `input_MockKeyPress`,
  `input_MockControlShortcut`, `input_MockText`, and `input_ResetForTest`
- Theme and clipboard: `theme_InitClassic`, `theme_SetMode`, `theme_GetMode`,
  `theme_GetColor`,
  `clipboard_GetText`, and `clipboard_SetText`
- Raster images: `rasterimage_LoadFile`, `rasterimage_LoadMemory`,
  `rasterimage_DetectFormat`, `rasterimage_ScaleToFit`,
  `rasterimage_Destroy`, and `backend_DrawImage`

`input_Update` and `input_SetDispatchMask` are public for custom manager and
test integration. Ordinary omaGUI applications let `gui_UpdateAll` call them.
`font_init_pointers` is assembled by the backend lifecycle and should not be
needed by application code.

### GUI manager

- Registry: `gui_Init`, `gui_ResetForTest`, `gui_AddWidget`,
  `gui_AddGeneratedWidget`, `gui_IsWidgetRegistered`, `gui_RemoveWidget`, and
  `gui_FindWidget`
- Hierarchy and order: `gui_SetParent` and `gui_BringToFront`
- Focus and modal state: `gui_SetFocus`, `gui_GetFocus`, `gui_MoveFocus`,
  `gui_SetTabOrder`, `gui_GetTabOrder`, `gui_SetDefaultAction`,
  `gui_GetDefaultAction`, `gui_SetCancelAction`, `gui_GetCancelAction`,
  `gui_SetMnemonic`, `gui_SetMnemonicTarget`, `gui_GetMnemonicTarget`,
  `gui_IsKeyboardNavigationActive`, `gui_TrySetModalRoot`,
  `gui_SetModalRoot`, `gui_ClearModalRoot`, and `gui_IsModalOpen`
- Layout: `gui_SetViewportSize`, `gui_GetViewportSize`, `gui_SetAnchors`, and
  `gui_ResetAnchors`
- Frame dispatch: `gui_UpdateAll` and `gui_RenderAll`
- Drawing helpers: `gui_DrawLine`, `gui_DrawRect`, `gui_DrawCircle`, and
  `gui_DrawCurve`
- Control helpers: `gui_ButtonPressed` and `gui_DeselectRadioGroup`

### Standard widgets

- Constructors: `button_Create`, `textbox_Create`, `checkbox_Create`,
  `radiobox_Create`, `label_Create`, `scrollbar_Create`, `listbox_Create`,
  `groupbox_Create`, `picturebox_Create`, `htmlview_Create`,
  `subwindow_Create`, `menu_Create`, `menubar_Create`, `toolbar_Create`,
  `statusbar_Create`, `splitter_Create`, `linewidget_Create`, `rectwidget_Create`,
  `circlewidget_Create`, and `curvewidget_Create`
- Label state: `label_CreateWithColor`, `label_SetFont`, `label_SetWordWrap`, and
  `label_GetRenderedLineCount`, `label_SetTextColor`, `label_GetTextColor`,
  `label_SetTextStyle`, `label_GetTextStyle`, `label_SetTextColorLiteral`,
  `label_SetBackgroundColor`, `label_ClearBackgroundColor`,
  `label_GetBackgroundColor`, `label_SetBorderStyle`, and
  `label_GetBorderStyle`
- Button state: `button_SetBackgroundColor`, `button_ClearBackgroundColor`, and
  `button_GetBackgroundColor`
- CheckBox color state: `checkbox_SetBackgroundColor`,
  `checkbox_ClearBackgroundColor`, `checkbox_GetBackgroundColor`,
  `checkbox_SetForegroundColor`, `checkbox_ClearForegroundColor`, and
  `checkbox_GetForegroundColor`
- Toggle state: `checkbox_SetChecked`, `checkbox_GetChecked`,
  `checkbox_GetActivationCount`, `radiobox_SetSelected`, `radiobox_GetSelected`,
  and `radiobox_GetActivationCount`
- RadioBox color state: `radiobox_SetBackgroundColor`,
  `radiobox_ClearBackgroundColor`, `radiobox_GetBackgroundColor`,
  `radiobox_SetForegroundColor`, `radiobox_ClearForegroundColor`, and
  `radiobox_GetForegroundColor`
- Textbox state: `textbox_ClearHistory`, `textbox_BeginEdit`,
  `textbox_EndEditGroup`, `textbox_Undo`, `textbox_Redo`, `textbox_SetText`,
  `textbox_CanUndo`, `textbox_CanRedo`, `textbox_SelectAll`,
  `textbox_HasSelection`, `textbox_GetCursorPosition`,
  `textbox_SetCursorPosition`, `textbox_GotoLine`,
  `textbox_GetSelectionLength`, `textbox_GetSelectedText`,
  `textbox_GetLineColumn`, `textbox_FindText`, `textbox_Copy`, `textbox_Cut`,
  `textbox_ReplaceSelection`, `textbox_ReplaceAll`, `textbox_Paste`,
  `textbox_SetReadOnly`, `textbox_GetReadOnly`,
  `textbox_SetInputLimit`, `textbox_GetInputLimit`,
  `textbox_SetBorderStyle`, `textbox_GetBorderStyle`,
  `textbox_SetBackgroundColor`, `textbox_ClearBackgroundColor`,
  `textbox_GetBackgroundColor`, `textbox_SetForegroundColor`,
  `textbox_ClearForegroundColor`, `textbox_GetForegroundColor`,
  `textbox_SetSyntaxMode`, `textbox_GetSyntaxMode`, `textbox_SetSyntaxColor`,
  `textbox_GetSyntaxColor`, `textbox_ClearSyntaxColor`,
  `textbox_SetLineNumbers`, `textbox_GetLineNumbers`,
  `textbox_SetAcceptsTab`, `textbox_GetAcceptsTab`,
  `textbox_SetBlockIndent`, `textbox_GetBlockIndent`,
  `textbox_IndentSelection`, `textbox_UnindentSelection`,
  `textbox_SetVerticalScrollbar`, `textbox_GetVerticalScrollbarMode`,
  `textbox_SetHorizontalScrollbar`, and `textbox_GetHorizontalScrollbarMode`
  and `textbox_SetCaretVisible`
- Listbox state: `listbox_AddItem`, `listbox_Clear`,
  `listbox_GetItemCount`, `listbox_GetSelectedIndex`,
  `listbox_GetSelectedItem`, `listbox_GetActivationCount`,
  `listbox_ActivateSelected`,
  `listbox_SetBackgroundColor`, `listbox_ClearBackgroundColor`,
  `listbox_GetBackgroundColor`, `listbox_SetForegroundColor`,
  `listbox_ClearForegroundColor`, and `listbox_GetForegroundColor`
- ComboBox colors: `combobox_SetBackgroundColor`,
  `combobox_ClearBackgroundColor`, `combobox_GetBackgroundColor`,
  `combobox_SetForegroundColor`, `combobox_ClearForegroundColor`, and
  `combobox_GetForegroundColor`
- PictureBox state: `picturebox_SetText`, `picturebox_SetBorderStyle`,
  `picturebox_SetBackgroundColor`, `picturebox_ClearBackgroundColor`, and
  `picturebox_GetBackgroundColor`, `picturebox_SetForegroundColor`,
  `picturebox_ClearForegroundColor`, `picturebox_GetForegroundColor`,
  `picturebox_GetBorderStyle`, `picturebox_SetPixelCanvas`, `picturebox_SetPixelCanvasToClient`,
  `picturebox_SetPixel`, `picturebox_ReadPixel`, and `picturebox_ClearPixels`
- GroupBox state: `groupbox_SetText`, `groupbox_SetBackgroundColor`,
  `groupbox_ClearBackgroundColor`, `groupbox_GetBackgroundColor`,
  `groupbox_SetForegroundColor`, `groupbox_ClearForegroundColor`, and
  `groupbox_GetForegroundColor`
- HTML viewer: `htmlview_SetHtml`, `htmlview_LoadFile`,
  `htmlview_BeginSetHtml`, `htmlview_BeginLoadFile`, `htmlview_UpdateLoad`,
  `htmlview_IsLoading`, `htmlview_GetLoadState`, `htmlview_GetLoadProgress`,
  `htmlview_GetLoadError`, `htmlview_CancelLoad`, `htmlview_Clear`,
  `htmlview_Reflow`, `htmlview_SetBasePath`, `htmlview_SetColors`,
  `htmlview_SetLinkHandler`, `htmlview_SetImageHandler`,
  `htmlview_GetTitle`, `htmlview_GetPlainText`, `htmlview_GetLastError`,
  `htmlview_GetBasePath`, `htmlview_GetContentHeight`, `htmlview_GetScroll`,
  `htmlview_SetScroll`, and `htmlview_PopLink`
- Window state: `subwindow_SetCloseHandler`, `subwindow_SetClosable`,
  `subwindow_SetTitleTextYOffset`,
  `subwindow_SetControlBox`, `subwindow_GetControlBox`,
  `subwindow_SetMinButton`, `subwindow_GetMinButton`,
  `subwindow_SetMaxButton`, `subwindow_GetMaxButton`,
  `subwindow_CloseRequested`, `subwindow_Reopen`,
  `subwindow_SetClientColor`, `subwindow_ClearClientColor`,
  `subwindow_GetClientColor`, `subwindow_SetBorderStyle`,
  `subwindow_GetBorderStyle`, `subwindow_GetClientTopInset`,
  `subwindow_SetWindowState`, and `subwindow_GetWindowState`
- Menu state: `menu_AddItem`, `menu_ClearItems`,
  `menu_SetTextYOffset`, and `menu_SetSelectionHandler`
- Menu-bar state: `menubar_AddMenu`, `menubar_AddItem`,
  `menubar_SetSelectionHandler`, `menubar_SetOpenMenu`, `menubar_ActivateItem`,
  `menubar_GetOpenMenu`, `menubar_GetMenuCount`, `menubar_GetItemCount`,
  `menubar_GetMenuLabel`, `menubar_GetItemLabel`,
  `menubar_SetItemLabel`, `menubar_SetItemVisible`, `menubar_GetItemVisible`,
  `menubar_SetItemChecked`, `menubar_GetItemChecked`,
  `menubar_SetItemEnabled`, `menubar_GetItemEnabled`,
  `menubar_SetItemShortcutText`, and `menubar_GetItemShortcutText`
- Toolbar state: `toolbar_AddButton`, `toolbar_AddSeparator`,
  `toolbar_SetSelectionHandler`, `toolbar_SetItemEnabled`,
  `toolbar_GetItemEnabled`, `toolbar_GetItemCount`, `toolbar_GetItemLabel`, and
  `toolbar_ActivateItem`
- Status-bar state: `statusbar_AddPanel`, `statusbar_SetPanelText`,
  `statusbar_GetPanelText`, and `statusbar_GetPanelCount`
- Splitter state: `splitter_SetRange`, `splitter_GetRange`,
  `splitter_SetPosition`, `splitter_GetPosition`, `splitter_IsDragging`, and
  `splitter_SetChangeHandler`
- File dialogs: `filedialog_Create`, `filedialog_CreateAtPath`,
  `filedialog_CreateSaveAtPath`, `filedialog_GetSelectedFile`, and
  `filedialog_GetResultState`, `filedialog_SetFilter`, and
  `filedialog_GetFilter`, and `filedialog_GetWindow`
- Confirmation dialogs: `confirmdialog_Create`,
  `confirmdialog_CreateChoices`, `confirmdialog_GetResultState`, and
  `confirmdialog_GetWindow`, and `confirmdialog_GetMessageLabel`

The `*_Render`, `*_Update`, and `*_Destroy` declarations are widget lifecycle
entry points used by constructors and the manager. Applications normally do
not call them directly.

### SpinButton

`spinbutton_Create` builds a horizontal or vertical bounded numeric control.
The default behavior activates on pointer release or an arrow key, wraps at
the range endpoints, and calls the optional change handler only when Value
changes. `spinbutton_SetRange`, `spinbutton_SetValue`, `spinbutton_SetIncrement`,
`spinbutton_SetWrap`, and `spinbutton_SetOrientation` configure it.

`spinbutton_SetRepeat(widget, milliseconds)` opts into immediate pointer-press
activation and held-pointer/key repetition. Zero disables repetition while
retaining press activation; supported intervals are 0..65535 ms. Updates use
FreeBASIC's clock on the GUI thread, with midnight wrap handling. Delayed frames
coalesce into one step, retaining the sub-interval remainder.

Tests can disable wall-clock advancement with `spinbutton_SetAutomaticRepeat`
and call `spinbutton_AdvanceRepeat` with bounded elapsed milliseconds. A held
direction must first be established by normal input. Release stops repetition.

`spinbutton_SetStepHandler` installs a callback taking `(Widget Ptr, Integer)`.
It replaces the legacy change notification while installed and reports +1/-1
for every accepted user step, including wrap and singleton ranges.
`spinbutton_Step` exposes the same checked activation directly. Notification
occurs after state updates; the callback may destroy its widget. Programmatic
SetValue/SetRange calls do not produce a step callback.

### ComboBox

`combobox_Create` builds a noneditable drop-down choice widget. It retains at
most 256 items and 4 MiB of total item text. `combobox_AddItem` appends;
`combobox_InsertItem` accepts a zero-based position or -1 to append.
`combobox_RemoveItem`, `combobox_GetItem`, and `combobox_GetItemCount` expose
checked list access. Insertion/removal and item reads return -1 on success
or 0 on invalid input; failed reads clear the output string. Capacity failures
leave the list unchanged. Item arguments may refer to existing list strings.

`combobox_SetItem(widget, index, text)` replaces a label without changing its
selection, pending row, popup state, scroll position or application value.
It checks the complete text budget first and invalidates a pending pointer
gesture without invoking the selection callback. `combobox_SetItemData` and
`combobox_GetItemData` provide the same signed 64-bit opaque values and checked
ByRef output contract as the ListBox APIs. Values follow labels when rows move;
new rows start at zero and Clear discards values with the labels. These operations
are native FreeBASIC and run on the GUI thread.

Insertion and removal before the selected item preserve its identity at the
new index. Removing that item clears selection to -1. `combobox_Clear`
releases retained text and clears selection. Mutations cancel pending popup
input, so a release from an old row cannot choose a shifted item. These
operations do not invoke the change handler.

`combobox_SetSelectedIndex` accepts -1 or an existing item index without a
callback. `combobox_GetSelectedIndex` and `combobox_GetSelectedItem` read the
committed choice. `combobox_SetOpen` and `combobox_IsOpen` expose popup state.
Arrow, Home, and End keys navigate; Return/Space commits an open popup and
Escape cancels it. Navigation while open retains a separate pending choice.

`combobox_GetDropDownCount` advances only when pointer, keyboard, or widget
activation opens a nonempty popup. `combobox_SetOpen` remains a programmatic
state operation and does not advance the count. Hosts can therefore poll the
counter after GUI updates and route a DropDown event without installing a
callback that could disturb widget-update lifetime.

The optional change handler runs only when a user commits a different index.
`combobox_GetActivationCount` advances on every valid user commit, including
the current item, for hosts that need a separate Click event. Popup and input
state are finalized before notification, including callbacks which release
the ComboBox's private data. Removing the registered Widget allocation during
`gui_UpdateAll` is not supported; defer registry removal until after update.
All operations and callbacks belong to the GUI thread. The widget's manager
cancellation hook closes private popup input across hidden, disabled, and
modal-external states without calling application code.

### Graphic shapes

- Construction: `graphicshape_DefaultOptions`, `graphicshape_Create`,
  `graphicshape_CreateStyled`, `graphicshape_CreateStyledText`,
  `graphicshape_CreateStyledTextColor`,
  `graphicshape_CreateStyledTextColorFit`, and
  `graphicshape_CreateWithOptions`
- Direct drawing: `graphicshape_RenderWithOptions`
- Rendering state: `graphicshape_SetRenderOptions`,
  `graphicshape_SetCornerRadius`, `graphicshape_SetClipToBounds`,
  `graphicshape_SetObjectAlpha`, `graphicshape_SetStrokeAlpha`,
  `graphicshape_SetOutlineAlpha`, `graphicshape_SetFillAlpha`,
  `graphicshape_SetFillGradient`, `graphicshape_SetFillGradientStops`, and
  `graphicshape_SetPathPoint`
- Input state: `graphicshape_SetInteractive`, `graphicshape_IsInteractive`,
  `graphicshape_SetValue`, `graphicshape_GetValue`, `graphicshape_SetText`,
  `graphicshape_GetText`, `graphicshape_ClearItems`, `graphicshape_AddItem`,
  `graphicshape_GetSelectedIndex`, `graphicshape_GetSelectedItem`,
  `graphicshape_GetChangeCount`, and `graphicshape_IsDropdownOpen`

## Copied themes and game controls

`theme_GetCurrent` copies the active `GUI_Theme`; `theme_SetCurrent` applies a
complete palette and derives classic semantic roles for older application
palettes. `panel_face`, `accent_secondary`, and `GUI_THEME_STYLE_*` describe
panel construction independently of the classic or flat control treatment.

`gui_SetWidgetTheme` stores a palette by value in a widget. Descendants inherit
the nearest palette, and a copied override takes precedence over `appearance`
at the same widget. `gui_ClearWidgetTheme` removes only that copied override;
the borrowed `appearance` pointer remains available. Its owner must keep the
referenced theme alive through widget destruction. `gui_GetEffectiveWidgetTheme`
resolves either form of inheritance without drawing. Rendering restores the
complete prior palette, including custom classic colors, after each control.
Retained rendering observes both forms of palette and the panel motif fields.
These operations belong to the GUI thread.

A focused TextBox calls its KeyDown source handler before built-in navigation
and editing. The handler may remap a scan code or set it to zero to suppress
that input for the current hold. Ordered raw events retain the physical code
so KeyUp can still identify the released key. The input manager clears the
mapping after release.

`themeframe_Create` has the same geometry, fallback color, and filled flag as
`rectwidget_Create`. Filled frames retain the supplied application color in
every theme. Unfilled frames use one border and corner-bracket motif, with
semantic border, selection, and light colors from the effective theme.
`themeframe_SetClassicColor` checks the widget type before changing its data.

`listbox_SetColors` preserves the five-role palette: normal background, border,
normal text, selected background, and selected text. The granular normal-color
functions remain available. `listbox_SetRightColumn` sets a checked pixel offset
for the text after the first tab in ordinary rows. This is a compact name/value
layout; the editor table and flowing-column APIs retain their separate layout.

`textbox_SetPlaceholder` stores at most `TEXTBOX_PLACEHOLDER_MAX_LENGTH` bytes
of guidance. A failed call leaves the prior guidance unchanged, and
`textbox_GetPlaceholder` returns an empty string for an invalid widget. An empty,
inactive textbox draws guidance without inserting it into text, selection,
clipboard data, undo history, or password contents.

`input_AnyKeyPressed` reports held keys and buffered press edges, respecting the
keyboard dispatch mask. `gui_GetPointerWidgetNameAt` reports the same eligible
target used by pointer dispatch, while `gui_GetPointerCaptureName` returns only
a currently registered capture. Both return an empty string when absent.

`gui_CreateWidgetBase` allocates an initialized, visible and enabled base for
custom controls. The caller owns it until registration transfers its lifetime
to the manager. Built-in constructors initialize their own widget state.

Label borders accept `LABEL_BORDER_NONE`, `LABEL_BORDER_SINGLE`, and
`LABEL_BORDER_DOUBLE`. PictureBox accepts the corresponding single and double
styles plus its recessed style; the double style keeps a two-pixel child inset.
TextBox accepts `TEXTBOX_BORDER_NONE` and `TEXTBOX_BORDER_SINGLE`. Changing its
frame leaves the editor's text and caret metrics intact.

<!-- end of MANUAL.md -->
