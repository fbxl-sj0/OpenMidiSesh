# omaGUI

omaGUI is a GUI toolkit for FreeBASIC programs that use the built-in gfxlib
graphics system. It provides a classic desktop widget set, ordered child
windows, modal dialogs, editable text, drawing primitives, and 28 imported
graphic-shape types through one public include. It also includes a portable,
display-only HTML viewer for help pages and generated technical documents.

The current implementation includes the complete widget and graphics surface.
The line, rectangle, circle, curve, graphic-shape, scaled text, aligned text,
alpha, and embedded multi-font APIs are all present in `omaGUI.bi`.

## Requirements

- A recent FreeBASIC compiler with gfxlib support
- Optional gfxlib3 support for GPU-batched alpha text and page presentation
- The repository directory, or `omaGUI.bi`, `src`, and `assets`, available on
  the compiler include path
- No separate GUI framework

## Quick start

Define `OMAGUI_IMPLEMENTATION` in exactly one source file, then include the
master header:

```freebasic
#define OMAGUI_IMPLEMENTATION
#include once "omaGUI.bi"

backend_Init(800, 600, 0, BACKEND_WINDOW_RESIZABLE)
gui_Init()

Dim helloButton As Widget Ptr
helloButton = button_Create("hello", "Hello", 20, 20, 100, 30)
gui_AddWidget helloButton

Do
    backend_Clear RGB(240, 240, 240)
    gui_UpdateAll
    gui_RenderAll
    backend_Flip

    If gui_ButtonPressed("hello") Then Exit Do
    If MultiKey(FB.SC_ESCAPE) Then Exit Do

    Sleep 10, 1
Loop

backend_Exit
```

From the repository root, build it with:

```powershell
fbc app.bas
```

Build with `fbc -gfx3 app.bas` when the installed compiler provides gfxlib3.
The same source remains compatible with the ordinary gfxlib backend.

If a program has several source files, the other files include `omaGUI.bi`
without defining `OMAGUI_IMPLEMENTATION`.

Applications distributing only the licensed neutral bitmap tables can define
`OMAGUI_REDISTRIBUTABLE_FONTS` in the implementation source before including
`omaGUI.bi`. The default font tables remain selected when this symbol is
absent. The neutral tables and their OFL notice are in `assets/fonts`.

### gfxlib3 rendering

When `__FB_GFXLIB3__` is active, omaGUI submits each antialiased text string as
one bounded `Gfx3DrawPoints` packet. This keeps font blending on the renderer
instead of reading the complete work page back through `Point`. Alpha drawing
and text retain the established software path on ordinary gfxlib, indexed
screens, oversized packets, or extension failure.

gfxlib3 also presents a completed work page directly through `ScreenSet`.
Ordinary gfxlib retains the `ScreenSync` call required by its older page-flip
model.

The backend also exposes `backend_GetWorkPage`, `backend_DrawHorizontalSpans`,
and `backend_DrawAlphaMask` for applications with their own retained drawing.
The two batched drawing calls return -1 when the work is complete and 0 when
the caller should use its software path. They clip to the active true-color
screen and bound each gfxlib3 packet to avoid excessive temporary storage.

## Included controls

The shared tree also retains TurboTrek's copied widget themes, theme-aware
panels, five-role ListBox colors and tab-aligned value columns, bounded textbox
guidance, any-key query, and pointer diagnostics. Copied palettes and borrowed
dialog appearances use the same nearest-ancestor rule. See the manual's
"Copied themes and game controls" section and [sync notes](docs/TURBOTREK_SYNC.md).

- Buttons, labels, checkboxes, grouped radio buttons, keyboard-operable signed
  scrollbars, and listboxes
- Push buttons with an optional retained face color that preserves theme bevels
- Labels with retained foreground color and optional bounded background fill
- Labels can opt into the live theme text color with
  `LABEL_COLOR_THEME_TEXT`; existing labels keep their original default
- CheckBox and RadioBox controls with optional per-widget client and
  indicator/caption colors
- A bounded HTML document viewer with wrapping, headings, lists, tables,
  preformatted text, colors, local raster images, links, an owned scrollbar,
  and no browser engine; linked text resources, CSS, and anchors can be
  supplied by an application
- A bounded CHM/LZX member reader and a read-only RTF document viewer for
  application help, with the required decoder license in `LICENSES`
- Single-line and multiline textboxes with selection, clipboard commands,
  bounded undo/redo history, word wrapping, wheel scrolling, and configurable
  vertical scrollbars; application menus can invoke the same operations
  through public Select All, Copy, Cut, and Paste functions
- Per-TextBox retained client and text colors that leave selection colors and
  the global theme unchanged
- Optional caret visibility through `textbox_SetCaretVisible`, useful for
  passive views and repeatable framebuffer captures
- Optional four-column Tab insertion for multiline editor textboxes while
  Shift+Tab and modified Tab presses continue through focus traversal
- Optional block indentation with retained selections, mixed line endings,
  one-step undo, and reusable Increase/Decrease Indent commands
- Optional theme-aware logical line numbers for multiline editors; the fixed
  gutter remains outside selection, document text, and horizontal scrolling
- Editor font packs, zoom, styled text callbacks, fold and marker gutters,
  line hiding, and virtual caret columns after a line end
- Optional explicit tab order with stable registration-order tie breaking;
  paint and pointer stacking continue to use registry order
- Keyboard updates snapshot focus, global-widget ownership, dialog default and
  cancel targets, and mnemonic identities before callbacks run. A callback may
  replace its window tree without routing the remaining keys from that update
  to newly created widgets
- Focusable read-only textbox mode that retains navigation, selection,
  scrolling, and Copy while rejecting typing, Cut, Paste, Undo, and Redo
- Optional FreeBASIC syntax coloring for editor textboxes, with public mode and
  per-token color metadata for keywords, comments, strings, numbers,
  preprocessor directives, built-in types, commands, procedures, macros,
  variables, constants, members, objects, and labels
- Draggable and closable child windows with parent-bound content, client
  clipping, focus, pointer capture, modal routing, and front-to-back ordering
- File-open, file-save, and confirmation dialogs
- Popup menus with per-item callbacks or a shared selection handler
- Bounded Windows-style menu bars with keyboard navigation, separators, and
  one context-aware selection handler for all drop-down commands
- Portable classic toolbars with bounded text commands, separators,
  release-inside activation, and per-command enabled state
- Portable classic status bars with bounded fixed-width and flexible text
  panels that divide current widget width without a host control
- Portable horizontal and vertical splitters with pointer capture, bounded
  positions, keyboard adjustment, and GUI-thread layout callbacks
- Portable GroupBox and clipped PictureBox containers; PictureBox can retain a
  caller-supplied client and display-text colors or return to active theme
  colors, plus a bounded sparse pixel canvas with retained clipped lines,
  rectangles, and circles that
  redraws without a platform bitmap handle
- GroupBox can independently retain client and caption colors without changing
  the application theme
- ListBox and ComboBox can independently retain normal client and text colors;
  selected rows continue to use the theme selection colors
- ListBox exposes checked item-count, selection, and explicit activation
  queries so applications can poll commands without reaching into widget data
- ListBox and ComboBox retain portable 64-bit item values with each row and
  support checked label replacement without losing selection or item identity
- ListBox exposes checked top-row access with page clamping and synchronized
  scrolling, independent of the selected row
- Child windows can retain a caller-supplied client color and select none,
  fixed-single, sizable-single, or fixed-double portable frames while their
  title bar continues to use the active theme
- Line, rectangle, circle, and quadratic curve widgets
- All 28 imported graphic-shape kinds, including opt-in interactive buttons,
  choices, text fields, calendars, trends, and alarm lists
- Solid and gradient fills, line widths, corner radii, clipping, path points,
  embedded fonts, alignment, scaling, and alpha compositing
- 32-bit, 16-bit, 8-bit, 4-bit, and true black-and-white 1-bit display modes
- Fixed, resizable, and full-screen modes with checked runtime transitions
- Parent-relative anchors for layouts that react to gfxlib resize and maximize
  events

## List item state

ListBox and ComboBox can associate a signed `LongInt` value with each row using
`listbox_SetItemData` / `combobox_SetItemData`. The corresponding `GetItemData`
functions return the value through a `ByRef LongInt` argument and return zero
on failure. Failed reads clear that output to zero. Values are opaque IDs;
the widget does not dereference or free them.

Insertion and removal move values with their labels. New rows start at zero,
and Clear discards both labels and values. `listbox_SetItem` and
`combobox_SetItem` replace a label in place, preserving its value and selection.
They validate the full text budget before changing anything and cancel stale
pointer gestures without invoking application callbacks. ComboBox replacement
also preserves its open popup, pending row and scroll position.

`listbox_SetTopIndex` accepts an existing zero-based row and clamps it to the
last full page. `listbox_GetTopIndex` returns the actual top row, or -1 for an
invalid widget. These operations synchronize the owned scrollbar and leave
selection unchanged. All widget mutations belong on the GUI thread.

These APIs use native FreeBASIC storage and the existing portable input layer.
The new `tests/list_item_state_smoke.bas` uses `OMAGUI_PORTABLE_ONLY` and covers
64-bit values, full-capacity shifts, aliases, replacement and rejected writes.
From the Optical FreeBASIC root, `tools/verify_omagui_lists.ps1` runs that test
alongside the existing list, keyboard, modal and filesystem-list regressions.

## Portable HTML viewer

The HTML viewer is a normal omaGUI widget. It uses embedded fonts, gfxlib
drawing, and standard FreeBASIC file I/O, with no operating-system web control
or external HTML library.

```freebasic
Dim helpView As Widget Ptr

helpView = htmlview_Create("help", 20, 20, 500, 320)
gui_AddWidget helpView

If htmlview_LoadFile(helpView, "help/device.html") = 0 Then
    Print htmlview_GetLastError(helpView)
End If
```

Links are reported to the application through `htmlview_PopLink`, or through
an optional callback installed with `htmlview_SetLinkHandler`. The viewer does
not open files, run programs, or fetch URLs. This lets an application map a
link to DD navigation without tying omaGUI to one project or platform.
Applications can provide checked in-memory image schemes with
`htmlview_SetImageHandler`; ordinary relative local files remain available.

Large replacements can be parsed cooperatively with
`htmlview_BeginSetHtml` or `htmlview_BeginLoadFile`. The viewer performs a
bounded slice during each ordinary `gui_UpdateAll` call, keeps the last
completed document visible, and swaps in the replacement only after a
successful layout. This uses no worker thread and does not change omaGUI's
single-threaded update and rendering model. Progress, terminal state, errors,
and cancellation are available through the `htmlview_*Load` APIs described in
the manual.

The supported display subset includes headings, paragraphs, line breaks,
rules, lists, measured and bordered tables, definition lists, block quotes,
preformatted and code text, basic emphasis, text and background colors,
common and numeric entities, local raster images, image alternative text, and
anchors. Table columns reflow with the widget, cells wrap to a shared row
height, and links remain active inside cells. Legacy presentation tables are
flattened into full-width reading order, while genuine data tables keep their
grid. Semantic HTML 5 containers, legacy BIG and FONT size markup, decorative
empty-ALT images, and readable UTF-8 or Latin-1 fallback are handled without
executing CSS. Historical optional definition-list end tags are normalized,
and untitled small presentation images do not create placeholder noise. The
viewer skips large script, style, and inline SVG bodies without tokenizing
their contents, rejects remote and network-share image paths before local file
access, and stops malformed or pathological layouts at a wall-clock budget.
Legacy framesets become ordinary navigable links, while otherwise blank
script, canvas, and WebAssembly application shells explain that their
interactive content requires a full browser.
The content-sniffing image loader uses gfxlib for BMP and PNG and native
FreeBASIC decoders for GIF87a/GIF89a and baseline JPEG. In-memory BMP and PNG
data uses a bounded transient-file bridge because gfxlib exposes those
decoders through `BLoad`. This covers the actual AMS DD corpus, including
files without extensions. The viewer deliberately
excludes scripts, forms, remote images, stylesheet layout, and networking.
See the manual for the exact tag, attribute, limit, and API reference. A
complete standalone example is in `examples/htmlview_demo.bas`.
The example accepts an optional local HTML path for inspecting captured pages.

## Run the demo

```powershell
fbc demo.bas
.\demo.exe
```

The demo exercises every widget family and all 28 graphic-shape kinds. It also
shows real combo and date popup menus, interactive imported controls,
multiline scrollbar policies, mouse-wheel input, overlapping closable windows,
resizable anchors, all color depths, and a live 0-to-255 alpha control over a
checkerboard.

The bounded MenuBar stores checked state per command. Use
`menubar_SetItemChecked` after `menubar_AddItem` and query it with
`menubar_GetItemChecked`. Check marks are drawn with backend lines, so they do
not depend on a host menu API or a particular symbol font.
`menubar_SetItemEnabled` controls whether a command can be selected;
`menubar_GetItemEnabled` queries that state. Disabled commands are dimmed and
skipped during keyboard navigation. `menubar_SetItemLabel` changes retained
command text. `menubar_SetItemVisible` and `menubar_GetItemVisible` manage
dynamic commands; hidden rows take no popup space and cannot be selected.
A single ampersand identifies a visibly
underlined A-to-Z mnemonic, and Alt plus that letter opens the heading.
For recursive popups, attach a `Menu` root to a heading with
`menubar_SetMenuPopup` and compose deeper levels with `menu_AddSubmenu`. The
MenuBar owns an attached popup root and all its descendant widgets. Each menu
retains its own selection handler, item state, and accelerators. Removing the
MenuBar releases the complete tree; do not separately destroy an attached
popup. A single ampersand in a popup caption marks an underlined mnemonic;
pressing that letter while the menu is open activates the first eligible
matching item. A doubled ampersand displays one literal ampersand.
Text editors can drive those states through `textbox_HasSelection`,
`textbox_CanUndo`, and `textbox_CanRedo` without inspecting widget storage.
They can also query `textbox_GetCursorPosition`,
`textbox_GetSelectionLength`, and the one-based `textbox_GetLineColumn` pair.
`textbox_GetSelectedText` copies the bounded selection, while
`textbox_FindText` performs optional case folding and wraparound before
selecting and scrolling the matching byte range into view.
`textbox_ReplaceSelection` performs one history-tracked edit;
`textbox_ReplaceAll` builds one exact-size bounded result and records the whole
operation as one undo transaction.
`textbox_SetCursorPosition` safely clamps direct navigation, and
`textbox_GotoLine` maps one-based logical line and column values while treating
CRLF as a single line break.
`textbox_SetAcceptsTab` opts a multiline editor into four-column space
insertion for unmodified Tab presses; `textbox_GetAcceptsTab` queries the
setting. Single-line controls reject the option, and read-only mode temporarily
releases Tab to focus traversal without losing the configured preference.
`textbox_SetBlockIndent(widget, -1)` additionally enables Ctrl+]/Ctrl+[ and
makes Tab indent selected logical lines instead of replacing the selection.
Tab capture still requires `textbox_SetAcceptsTab`; Shift+Tab remains reverse
focus traversal. Application menus can call `textbox_IndentSelection` and
`textbox_UnindentSelection` directly, without enabling keyboard shortcuts.
Each command preserves line endings and selection direction and records one
undo transaction. With no selection it operates on the caret's line.
`textbox_SetLineNumbers(widget, -1)` adds a fixed, theme-aware gutter to a
multiline editor, and `textbox_GetLineNumbers` queries the setting. Wrapped
continuation rows remain unnumbered, horizontal scrolling moves only document
text, and single-line controls reject the option.
`textbox_SetSyntaxMode` opts a textbox into the built-in FreeBASIC highlighter;
the lexer distinguishes keywords, built-in commands, procedure declarations and
calls, preprocessor directives and macros, variables, constants, members,
labels, strings, numbers, comments, types, and user-defined object instances.
`textbox_SetSyntaxColor`
customizes any of those categories, while `textbox_ClearSyntaxColor` returns
one category to the active theme palette. Syntax coloring is display metadata
and does not change the stored text, selection ranges, or undo history.
Multiline editors can independently select `NONE`, `AUTO`, or `ALWAYS` policies
for their owned vertical and horizontal scrollbars. The horizontal bar drives
the same pixel offset used by cursor visibility and is hidden during word wrap.
`gui_SetTabOrder` assigns a nonnegative keyboard traversal rank without moving
the widget in the registry. Controls with explicit ranks precede unranked
controls; equal ranks retain registration order. Passing a negative rank
clears the override, and `gui_GetTabOrder` queries it.
`gui_SetDefaultAction` and `gui_SetCancelAction` assign Enter and Escape roles
to activatable widgets. Routing stays inside the focused window or active modal
tree, ignores hidden and disabled targets, and permits a role target with focus
disabled. Controls that use either key locally reserve it before dialog routing.
`menubar_SetItemShortcutText` adds a separately measured, right-aligned hint
such as `Ctrl+S`; `menubar_GetItemShortcutText` returns it. For an executable
binding, `menubar_SetItemShortcut` stores one gfxlib scan code, an exact
modifier chord, and its hint. The active form's one foremost MenuBar receives
that chord even while another child owns focus. `menubar_GetItemShortcut`
returns a binding. This remains inside omaGUI's FreeBASIC input layer and uses
no host menu API.

`toolbar_Create` constructs a classic nonfocusable command strip. Add text
commands with `toolbar_AddButton` and visual groups with
`toolbar_AddSeparator`, then install one context-aware handler with
`toolbar_SetSelectionHandler`. Commands fire only after a press and matching
release inside the same enabled item. `toolbar_SetItemEnabled` and its query
counterpart let application menus and toolbars share one availability policy.

`statusbar_Create` constructs a noninteractive classic status strip. Add up to
`STATUSBAR_MAX_PANELS` panels with `statusbar_AddPanel`; a width of zero shares
the available resize slack while positive widths remain fixed where space
permits. `statusbar_SetPanelText`, `statusbar_GetPanelText`, and
`statusbar_GetPanelCount` provide checked bounded access. Per-panel alignment
defaults to `BACKEND_ALIGN_LEFT`; use `statusbar_SetPanelAlignment` and
`statusbar_GetPanelAlignment` to select left, centered, or right text. Long
text is fitted with an ellipsis during rendering without changing the stored
value.

`splitter_Create` adds a focusable pane divider. Vertical dividers move along
their parent-relative x coordinate; horizontal dividers move along y. Set the
allowed positions with `splitter_SetRange`, then connect application pane layout
through `splitter_SetChangeHandler`. Programmatic position and range setters
clamp silently, so a layout callback can resize the surrounding panes without
recursively firing itself. The divider does not own or resize those panes.
Arrow keys move a focused divider by four pixels, Shift+Arrow by sixteen, and
Home/End select its range endpoints. Pointer drags retain the original grab
offset and stop when hidden, disabled, or interrupted by a modal dialog.

File dialogs accept one to sixteen bounded portable wildcard patterns through
`filedialog_SetFilter`; separate alternatives with `;`, such as
`"*.bas;*.bi"`. `filedialog_GetFilter` returns the active pattern list.
Matching supports `*` and `?`, is case-insensitive on every target, never
changes `CurDir`, and leaves directories visible for navigation.
`filedialog_SetTitle` supplies a checked nonempty title of at most 255 bytes
without using a platform-native dialog API.
`filedialog_GetWindow`, `confirmdialog_GetWindow`, and
`confirmdialog_GetMessageLabel` expose borrowed generated children for
application styling. Legacy `confirmdialog_Create` retains its original
right-aligned plain buttons and Enter default action; extended choice dialogs
retain their visible default outline. `menu_SetTextYOffset` and
`subwindow_SetTitleTextYOffset` adjust caption baselines within bounded pixel
ranges.

Native border resizing is requested from gfxlib. The GUI reacts to every size
change gfxlib reports, including maximize. A platform or gfxlib build that does
not provide draggable native borders cannot be made resizable by the widget
layer itself.

Alpha blending is available in 16-bit and 32-bit modes. True color uses the
documented integer blend directly, while 16-bit output is quantized by the
display format. Indexed 1-bit, 4-bit, and 8-bit modes map colors through their
active palettes and render alpha drawing as opaque palette output.

## Test and lint

Each `.bas` file under `tests` is a standalone FreeBASIC program. Build and run the
suite from the repository root. `tests/menu_release_smoke.bas` specifically
exercises popup-menu release behavior without requiring a display driver.
`tests/comprehensive_suite.bas` uses the same real headless backend path, so its
widget assertions also run on servers without a gfxlib display driver. The
`tests/htmlview_incremental_smoke.bas` program verifies cooperative loading,
last-completed-document retention, cancellation, failure, resize restart, and
automatic GUI-update advancement on both supported compiler targets. The
project is also checked with the local fblint executable:

```powershell
Get-ChildItem tests -Filter *.bas | ForEach-Object {
    $testExe = $_.FullName -replace '\.bas$', '.exe'
    fbc $_.FullName -x $testExe
    if ($LASTEXITCODE -ne 0) { throw "Compile failed: $($_.Name)" }
    & $testExe
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $($_.Name)" }
}

& 'C:\Nextcloud\games\newjrpg\fblint\fb_linter.exe' .
```

See [docs/MANUAL.md](docs/MANUAL.md) for the complete programming model, API
guide, widget behavior, limits, and test inventory.
See [docs/DESIGNER_SUPPORT.md](docs/DESIGNER_SUPPORT.md) for transactional
multi-pattern file lists, root-directory handling, label clipping, and first-frame list layout.
See [docs/UPSTREAM_SYNC.md](docs/UPSTREAM_SYNC.md) for the reference-copy
integration record and the local extensions preserved during the merge.

### Bundled heading fonts

omaGUI includes printable-ASCII alpha bitmaps generated by `tools/font_gen.bas`
from the LibreOffice-compatible Liberation Sans and Liberation Serif faces.
`BACKEND_FONT_LIBERATION_SANS_18_BOLD` is used for application headings and
`BACKEND_FONT_LIBERATION_SERIF_18_REGULAR` is used for large HTML headings.
They are embedded at build time, so applications do not depend on a host font
installation. See [assets/fonts/FONTS.md](assets/fonts/FONTS.md) for licensing
and regeneration details.

TextBoxes can opt into embedded bold, italic, underline, and strikeout through
`textbox_SetTextStyle`. Existing editors retain their normal rendering and
metrics. See [docs/TEXT_STYLES.md](docs/TEXT_STYLES.md) for the API and limits.

<!-- end of README.md -->
