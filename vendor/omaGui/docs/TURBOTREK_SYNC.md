<!--
    Project: omaGUI
    File: TURBOTREK_SYNC.md
    Purpose: Record the shared runtime merge between TurboTrek and Tiko.
    Responsibilities: Identify the retained APIs and source-tree boundaries.
    This file contains no application state, build outputs, or remote Git history.
-->

# TurboTrek and Tiko synchronization, 2026-10-05

The merged source tree is shared by:

- `C:\Nextcloud\games\TurboTrek\src\omaGui`
- `C:\fb_corpus\tiko-editor\src\omaGUI-main`

Tiko supplied the newer backend, font packs, editor text styles, ordered input,
touch support, filesystem abstraction, CHM/LZX reader, RTF viewer, image scaling,
nested menus, modal stack, and retained-rendering implementation. Its existing
gfxlib3 point batching and display APIs retain the corresponding TurboTrek work.

TurboTrek supplied copied/inherited theme overrides, panel motif fields and the
theme-frame widget, five-role ListBox colors, a tab-aligned name/value layout,
textbox guidance, and the any-key API. The copied themes now coexist with Tiko's
borrowed dialog palettes. Retained-rendering observations include both kinds of
palette and the additional panel fields.

The theme-frame widget retains its supplied application fill and its existing
border/corner-bracket outline. The additional theme fields remain available as
application design tokens; they do not select nine separate frame renderers.

Local tests already referenced missing base-widget, pointer-diagnostic, and
placeholder-query helpers. Those helpers were completed, including placeholder
limits, wrong-widget checks, and rejection of hidden/disabled polled buttons.
The any-key query retains buffered press events and now also reports held keys,
as required by its existing local test. The theme inheritance test samples the
actual button face instead of expecting an accent at the classic button border.

Snapshot capture now reads the displayed page after a double-buffered flip and
restores the work page before returning. A dedicated regression checks that
behavior and the retained single-page path. The native interface gallery checks
the resulting pixels across nine palettes.

Both copies retain their legacy development fonts. `SNAPSHOT.sha256` includes
the redistributable runtime and the theme-frame module; its font policy remains
unchanged. `TREE.sha256` describes the complete development source and asset
tree. Generated executables belong outside these dependency directories.

Only the two named omaGUI folders are synchronized. TurboTrek's entry point
explicitly enables the host clipboard bridge, retaining its previous behavior
under the library's newer opt-in policy. Settings, the other shared omaGUI
copies remain outside this operation. The shared dependency alone is committed
and pushed to Tiko's configured `fbxl-sj0/tiko-editor` fork. Its local Git
attributes preserve the exact bytes covered by the manifests.

<!-- end of TURBOTREK_SYNC.md -->
