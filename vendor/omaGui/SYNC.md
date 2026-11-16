This dependency uses the common omaGUI source maintained in Tiko. The local
refresh combines its retained renderer, textbox and lifetime fixes with reviewed
features from the active game and editor forks. OMAGUI_SOURCE.sha256 identifies
all common FreeBASIC source files, including development tests and tools.

The optional controller, touch, layout and logical viewport profile is documented
in NAVIGATION.md. Host clipboard integration remains explicit opt-in. Existing
application palettes, assets and source archives are retained separately.

The October 7, 2026 refresh qualified common native Windows contracts, full
application builds for WSR, Scorched Earth, AZdecrypt, HART, the older Midisoft
editor and three fbVNC copies, FS4 native objects, Stunts font integration and the
NewJRPG editor source. WSR runtime tests and Scorched shop/setup interaction tests
also passed. Final independent HTML, Windows import and font-generator changes
received focused qualification. These local checks do not certify remote targets
or public packages, and this refresh does not install application executables.

Development trees retain historical font sources. Redistributable snapshots keep
Arial-derived font data excluded and retain the existing reviewed open-font
payloads and notices. TREE.sha256 describes each complete local dependency;
SNAPSHOT.sha256 describes its existing redistributable subset where present.

The October 8, 2026 file-browser upgrade is documented in FILEDIALOG.md.
Browser contracts passed on Windows, Midcom Linux and Haiku, with a native
Windows fbVNC consumer build and clean focused lint. This source update
preserves unrelated consumer work and does not install application binaries.

The November 4 handheld follow-up exposes gfxlib focus transitions through
`input_WindowHasFocus()`. Templari uses that state to keep model and network
polling active while it pauses hidden rendering and waits 100 ms between
background loop passes.

The November 4 handheld follow-up adds bounded vertical drag-to-scroll to
HTMLView and the Templari chat timeline. Touch contacts enter the shared
gfxlib pointer stream, so native and browser targets use the same gesture
logic; crossing the threshold cancels the click or link that began the
drag.

The October 20, 2026 widget lifecycle update adds `gui_SetEnabled` and
`gui_GetEnabled`. Disabling a registered widget tree clears focus and pointer
capture before the disabled state is stored. The geometry API smoke covers
invalid handles, focus and capture cleanup, and re-enabling a control.

The October 20, 2026 TextBox update adds `textbox_GetLineNumberVisibility` so
editors can distinguish a hidden number display from an allocated gutter.
This keeps breakpoint layout independent from the user's line-number display
preference. The syntax smoke and VBDOS Studio interaction checks cover both
states.

The October 21, 2026 editor-path optimization caches cursor line/column by
cursor position and TextBox change serial, scans source bytes without per-byte
temporary strings, and reports text length, revision, equality, and selection
length without copying the queried text. Both omaGUI copies carry the same
implementation and refreshed source, snapshot, and tree manifests.

The October 21, 2026 syntax-path optimization builds a bounded semantic symbol
index once per TextBox source revision. Macro, procedure, type, and object
classification now uses the two-pass index for ordinary files; if its 256
slots fill, missing names retain the original exact source-scanner behavior.
The syntax smoke covers both normal colors and overflow fallback.

The October 21, 2026 combined-render optimization resolves widget layout once
for both desktop and window layers in `gui_RenderAll`. The standalone layer
renderers still resolve layout independently. The opaque-render smoke verifies
layer order, framebuffer replay, and current geometry through each entry point.
This removes one widget-list layout walk per combined frame; it is not a
measured Guacamole latency claim.

The October 21, 2026 input-path optimization exposes typed frame activity while
preserving the existing Boolean activity API. Studio skips app-level IDE
reconciliation on unpressed pointer-only frames and avoids a full scene repaint
while the pointer remains over the same editor with a native cursor and stable
viewport/caret. Keyboard, button, drag, touch, hover-target, custom-cursor, and
caret changes retain the repaint path. Keyboard, touch, and Studio editor
smokes cover the activity flags and redraw policy. No end-to-end Guacamole
latency measurement is available.

Static-screen clients may now call `gui_UpdateAll(0)` to skip hit testing and
widget update callbacks on idle frames. Input sampling, viewport/layout
synchronization, focus validation, and active or held pointer, key, and touch
input are preserved. The no-argument call retains the ordinary timer and
animation update behavior. VBDOS Studio opts in only while the IDE is active;
form previews and runtime modes keep the default call. Builds with the optional
navigation profile keep the full update path so controller presses, repeats,
and releases are not starved. The widget-registry and navigation-profile
smokes cover both paths. This reduces local idle work, but does not establish a
measured Guacamole latency change.

Static clients that also own every geometry and visibility change may pass
`gui_UpdateAll(0, -1)`. On input-free frames with an unchanged viewport, this
skips the widget layout-resolution walk as well as hit testing and callbacks.
Input and resize frames still resolve layout. Callers must synchronize any
programmatic geometry, visibility, or focus changes before the next idle frame;
the default second argument preserves the original synchronization behavior.
VBDOS Studio opts in only in IDE mode and resolves its explicit workspace
changes before rendering. The registry smoke counts layout passes for stable
idle, resize, and pointer-input cases.

Applications that must reconcile their own geometry before widget input may
call `gui_PrepareUpdateFrame`, read the current logical viewport, then pass
`-1` as the third argument to `gui_UpdateAll`. The prepared size is consumed by
that update, so the application and widget manager share one backend sample
without changing the default API path. VBDOS Studio uses this only in IDE mode;
the registry smoke checks both resize and idle samples and the default update.
This removes a redundant local `ScreenInfo` query per IDE frame. It is not an
end-to-end Guacamole latency or bandwidth measurement.

The backend also exposes `backend_IsDoubleBuffered()` so an application can
preserve page consistency when it updates only clipped regions. VBDOS Studio
uses it for focused editor text changes and caret blinking: each bounded frame
rebuilds the menu/toolbar band, editor, and status region on the work page
before flipping. It does not redraw those same regions a second time on the
hidden page. Every subsequent bounded frame rebuilds all regions this path can
change before that page is shown; full IDE frames still repaint and mirror the
whole scene because they may change content elsewhere. Commands, focus
transitions, size changes, and other interaction paths retain a full redraw.
The snapshot-page smoke checks the new query in both double-buffered and
retained-page modes. It also redraws the same bounded clip on alternating
pages and compares complete displayed snapshots byte for byte. This bounds
local IDE drawing work; no end-to-end Guacamole latency or bandwidth result
is claimed.

The October 22, 2026 TextBox metrics update retains the `change_serial` used to
build each scroll-metric snapshot. A redraw with the same source revision and
layout inputs reuses those metrics without comparing the full document; when
the revision changes, an exact-byte comparison still validates the cache
before the single-row update or full remeasurement path. Direct writes to
`TextBoxData.text` must advance `change_serial`. The expanded metrics smoke
covers an API edit and a same-length direct replacement with the revision
advanced. Windows smoke, Linux x86_64 C emission, and focused source-only
FBLint passed. This is a reduction in local editor work, not a measured
Guacamole latency result.

The October 22, 2026 syntax-render update lets an editor disable optional
source-wide semantic lookup while retaining lexical syntax colors. VBDOS Studio
opts out because rebuilding the symbol index after every edited source revision
adds work without changing the Studio editor's color contract; other omaGUI
TextBoxes keep semantic lookup enabled by default. The renderer also seeds
multiline block-comment state once at the first painted source row, then carries
it forward across clipped rows instead of rescanning the whole source prefix
for every visible line. The syntax smoke checks both the default and opt-out
lookup paths and verifies comment state across rows. No Guacamole latency
measurement is available.

The October 23, 2026 pointer-query update adds `gui_GetPointerDetailsAt` so an
input caller can retrieve the pointer target and inherited cursor style from a
single widget traversal. VBDOS Studio uses it after `gui_UpdateAll` has resolved
layout in IDE mode, avoiding two additional layout resolutions on pointer
motion. The registry smoke verifies both returned values and layout-resolution
counts for the normal and caller-resolved paths. This reduces redundant local
input work; no Guacamole latency measurement is available.

The follow-up pointer-motion update lets a caller reuse pointer and inherited
cursor details from an unchanged pure-pointer-motion `gui_UpdateAll` frame.
VBDOS Studio uses that result instead of repeating the widget hit test after
input dispatch. Geometry, registry, visibility, enabled state, parent, modal,
and stacking changes invalidate the result; custom `pointer_test` changes can
call `gui_InvalidateLastUpdatePointerDetails`. The registry smoke checks one
search per pointer frame, equivalence with a fresh query, and mutation
invalidation. This saves a local widget traversal, not a measured Guacamole
latency change.

The October 23 large-document syntax update adds fixed-capacity block-comment
and string-scanner checkpoints to unwrapped multiline TextBoxes using built-in
FreeBASIC syntax. It reuses the existing 32 row positions, invalidates only
later checkpoints after a same-line edit, and lazily rebuilds that suffix as
the viewport reaches it. Custom lexer callbacks and unsupported layouts keep
their existing paths. The regression smoke compares cached and full-scan
framebuffers byte for byte on a 10,000-line source, including a malformed
multiline string with a false comment opener and an edit to a later comment
delimiter. Windows execution and Linux x86_64 C source emission passed. The
test asserts bounded prefix-scan reductions; these local checks do not measure
live Guacamole latency.

The October 23 selector-input update shares registration, allocation, frame
identity and callback-reentry checks across Button, ComboBox and ListBox
KeyDown/KeyUp delivery. The ordered input snapshot remains the source for
scan-code mappings, while each widget retains its own navigation behavior.
`button_keyevents_smoke` and `selector_keyevents_smoke` cover event order,
modifiers, mapping and callback lifetime. File-list refresh also retains the
original APIs and adds opt-in portable attribute exclusions alongside the
semicolon-pattern union.

The October 24 TextBox damage update bounds unwrapped cursor moves across nearby
visual rows to the old and new caret rows. Selection changes, wrapped text,
viewport changes and longer jumps retain the full-widget fallback. The drawable
smoke compares the clipped result with a full framebuffer render; this reduces
local editor paint work but is not a measured Guacamole latency result.

The October 24 render-observation update adds an opt-in serial fast path for
TextBoxes whose text changes go through the omaGUI editing APIs. It avoids
comparing the entire source buffer on caret-only render observations. The
default still checks source bytes exactly for clients that may write the public
TextBox data directly. VBDOS Studio enables the fast path for its managed IDE
editor. The row-damage smoke covers both the serial path and default-compatible
fallback behavior; local smokes do not measure live Guacamole latency.

After this update, the Optical and NewJRPG development trees were checked
against `TREE.sha256`: all 283 listed files matched, with no missing, changed,
or extra files.

The October 27 clipboard update adds `clipboard_SetHostEnabled` so applications
can choose between omaGUI's native clipboard bridge and its bounded local
store. Interactive VBDOS runs enable the host bridge when the platform backend
is compiled. Scripted sample runs explicitly select the local store, avoiding
changes to the user's desktop clipboard. The API remains in FreeBASIC and does
not add a Windows SDK dependency.

Strict FBLint passed for the clipboard sources on Windows and Linux, and for
the VBDOS runtime on Windows. The host-enabled HELPUTIL sample compiled and
passed its 15 scripted events; script mode verifies the local clipboard policy,
not a live desktop clipboard exchange. A live clipboard write was left
unexercised to preserve the user's current clipboard. The linked copy received
the reviewed source, manual and synchronization notes, then both manifests were
regenerated and checked against the resulting trees.

## Portable clipboard opt-in, 2026-10-27

The VBDOS runtime and Studio define OMAGUI_PORTABLE_ONLY and separately opt in
to OMAGUI_ENABLE_HOST_CLIPBOARD. The clipboard switch enables only omaGUI's
host clipboard bridge; filesystem and input backends retain their portable
paths. OMAGUI_DISABLE_HOST_CLIPBOARD still forces the bounded local store.
This keeps the feature opt-in without broadening native platform behavior.

Strict source-only FBLint passed on Windows and Linux for clipboard.bas,
vbdos_runtime.bas, and vbdos_studio.bas with zero errors, warnings, and
informational findings. The HELPUTIL candidate
E:\codex-build-temp\vbdoscli01\clipboard_scope_narrowing_20261027\candidate\helputil_clipboard_scope_native_20261027.exe
(SHA-256 0C104489791FEBD151354F1E982028D217FA1F265F86416BBE88DD81FEBDD9D5)
passed all 15 scripted event lines with empty stderr. Script mode selected the
process-local clipboard; no live host clipboard exchange was attempted.

The isolated Studio candidate
E:\codex-build-temp\vbdoscli01\studio_clipboard_scope_20261027\candidate\vbdos_studio_clipboard_scope_20261027.exe
(SHA-256 6BD882F79A3A8E8F988F10D3A3A921CA1983E386F470F54F38B9E02B9F28828D)
compiled successfully and passed the four headless startup-profile smokes. It
was not launched or installed. The installed 478AD/3B pair was not rebuilt;
the earlier full VBDOS gate predates this clipboard source change. Build and
test receipts remain under E:\codex-build-temp\vbdoscli01.

The November 4 handheld follow-up adds a JavaScript touch bridge to the shared
gfxlib input backend. It maps contacts from the canvas CSS rectangle to
framebuffer coordinates and suppresses browser page scrolling while the canvas
owns the gesture. Native touch continues to use gfxlib's contact polling.

The shared input API includes `InputVerticalScrollGesture`: it applies a pixel
drag threshold, clamps scroll offsets, and consumes a dragged release so links
and other controls are not activated. HTMLView uses the gesture in its content
viewport. The focused touch-input and HTMLView smoke tests cover jitter, movement,
release, scroll limits, and link cancellation.


The November 16, 2026 consolidation combines the active C: and E: forks.
Editor metrics, semantic checkpoints, row damage, frame caching, control key
events, dialog styling, subtree queries, removable menu entries and optional
OpenGL modes now share the newer mobile input, responsive windows, physical
raster scaling and native textbox repeat implementation. See
docs/SYNCHRONIZATION.md for the preserved boundaries and verification scope.

The subsequent fbCAD reconciliation shares its renderer, font, ordered-input,
file-dialog, table and RTF improvements with all sixteen active libraries.
Compatibility fixes preserve older SDKs, mobile scaling and textbox repeat.

<!-- end of SYNC.md -->
