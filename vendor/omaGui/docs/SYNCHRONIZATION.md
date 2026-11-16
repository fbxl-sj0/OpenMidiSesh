<!--
    Project: omaGUI
    File: SYNCHRONIZATION.md
    Purpose: Explain the shared November 16, 2026 source consolidation.
    Responsibilities: Record fork contributions and compatibility boundaries.
    This file does not certify application releases or remote platforms.
-->

# Shared source consolidation

The active libraries in Templari, Tiko, OpenMidiSesh, Optical FreeBASIC,
NewJRPG, FS4, HART, TurboTrek, WSR, Scorched Earth, Stunts, AZdecrypt,
the older Midisoft checkout, two fbVNC locations and fbCAD share this source.
Development snapshots, archived releases, backups and diagnostic build trees
remain historical evidence. They are not deployment targets.

Templari contributes native repeat events, Unicode and ordered DOS/Wii input,
browser clipboard and touch handling, bounded drag scrolling, focus tracking,
responsive dialogs and physical-raster display scaling. Optical and NewJRPG
contribute editor metrics and syntax checkpoints, bounded row damage, static
layout and pointer caches, frame-scoped viewport sampling, ordered control
events, TextSurface subwindows, dialog styling and optional host clipboard
policy. Tiko and OpenMidiSesh contribute menu item removal, registered subtree
queries, device classification and bounded text-input coordinate mapping.
FS4 contributes optional OpenGL display modes and renderer-owned letterbox
input mapping. TurboTrek's platform-specific display bounds remain included.

The newer physical-raster navigation transform supersedes the older WINDOW
transform and its point-footprint workaround. Text and image scaling use one
coordinate model. Keyboard-reserved layout dimensions never replace physical
drawable dimensions in display restoration or input-region scaling.

Widget.text_input and Widget.is_text_input alias the same integer through an
anonymous union. Navigation fields remain present in the shared Widget record
even when a translation unit disables the optional navigation profile. Rebuild
every object in an application after updating this public library; old objects
must not be mixed with the changed Widget or BackendDisplayState layouts.

backend_ClearSoftKeyboardRegions and backend_SetSoftKeyboardRegion forward to
the mobile bridge. Linux publishes only the focused editor's clipped region;
browsers publish eligible clipped editor regions for trusted pointer events.
One cached publisher replaces the overlapping per-frame publication loops.

Native repeat unlocks textbox editing and navigation without repeating Return
submission. Cancelling Return removes its carriage-return control bytes while
preserving adjacent printable text. KeyDown/KeyUp notifications retain the raw
ordered identity even when an action edge is remapped or consumed.

OMAGUI_ENABLE_HOST_CLIPBOARD opts into the clipboard bridge independently of
OMAGUI_PORTABLE_ONLY. OMAGUI_DISABLE_HOST_CLIPBOARD always forces local storage.
clipboard_SetHostEnabled temporarily selects local storage at runtime, including
the browser bridge. Scripted tests must disable host access explicitly.

OMAGUI_SOURCE.sha256 identifies shared BASIC source, fixtures and font includes.
TREE.sha256 describes each consumer's actual local tree. SNAPSHOT.sha256 retains
that consumer's existing release subset and includes new runtime modules.
Consumer assets, font files, licenses and generated binaries are retained in
their original locations. Historical font exclusions remain in force.

Validation and rollback receipts for this consolidation are retained under
E:/Templari/work/omagui-sync-20261115. Native Windows, gfxlib2, gfxlib3 and browser
checks qualify the exercised contracts. The source refresh does not rebuild
or certify every platform package, install executables, or deploy devices.

The fbCAD reconciliation adds external font slots through BACKEND_FONT_LAST,
borrowed glyph metrics, checked image capture, retained GPU surfaces and native
primitive batching where the SDK declares the required APIs. Older SDK headers
retain software fallbacks. Physical-raster navigation keeps its existing path.
File dialogs gain optional preview, read-only, initial-view and save controls,
application Options actions, support paths and bounded recursive Places search.
Tables support six columns, header identity and context-click observations.
RTF runs retain source font identity and half-point sizes.

OMAGUI_ORDERED_TEXT_INPUT opts desktop consumers into command-boundary text
delivery, including input_SetTextBoundaryKey. Existing consumers retain their
frame behavior. Raw pointer coordinates, native double-click markers and an
optional application input-route handler remain available. The clipboard
SetHostClipboardEnabled spelling aliases the existing shared host policy.
Textbox latch refresh is frame-scoped, preserving repeats and preventing a
second update from editing twice. TextBoxData now includes key_latch_frame;
rebuild all application objects after updating this public record.

The fbCAD qualification and guarded rollback receipts are retained under
E:/Templari/work/omagui-fbcad-sync-20261116. Windows null-driver rendering checks
exercise software fallback behavior; they do not establish hardware GPU or
other-platform runtime acceptance.

<!-- end of SYNCHRONIZATION.md -->
