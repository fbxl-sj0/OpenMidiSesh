<!--
    Project: omaGUI
    ---------------------------

    File: DEPENDENCY.md

    Purpose:

        Describe the shared development tree and its source release subset.

    Responsibilities:

        - explain the two SHA-256 manifests
        - identify the font and license boundaries

    This file intentionally does NOT contain:

        - application-specific build instructions
        - private build-tool locations
        - the license text
-->

# omaGUI dependency snapshot

OpenSesh maintains this copy downstream of the Tiko fork's omaGUI tree at
`42ff302a9eb225b31c15671b9825fa502dd0215a` (2026-10-06). The update includes
batched glyph rendering, byte-span helpers, text caches, retained palette
tracking, and the theme-frame widget.

OpenSesh retains its source documentation, narrowly explained lint annotations,
CSS selector bounds checks, and the allocation query before image byte-array
bound checks. Portable label text styles and literal label colors remain
available, including the distinction between opaque white and theme-following
text. Existing public declarations and third-party notices are preserved.
The manifests identify the resulting downstream bytes; they do not claim
byte identity with Tiko or that our remaining changes were pushed upstream.

This directory is the common omaGUI development tree. `TREE.sha256` records
every file in the tree except itself, including this document and
`SNAPSHOT.sha256`. A project can use any byte-identical copy of the tree by
pointing its FreeBASIC include path at that copy.

`SNAPSHOT.sha256` records the smaller source release subset used by projects
that distribute omaGUI with redistributable fonts. Its paths are a selected
part of the full tree. A source archive containing this subset, this document,
and `SNAPSHOT.sha256` remains independently verifiable without `TREE.sha256`.
The subset contains the runtime modules, four neutral bitmap font tables,
five OGF1 font packs, and their license documents. It omits development
tests, examples, tools, generated executables, and the historical
Arial-derived bitmap tables. Applications using that subset must define
`OMAGUI_REDISTRIBUTABLE_FONTS` before including `omaGUI.bi`.

The full local tree retains the historical font tables for existing projects.
They are development assets and are not part of the redistributable subset.
Font sources and license details are described in `assets/fonts/FONTS.md`.

omaGUI is MIT licensed; see `LICENSE`. Generated font subsets use the SIL Open
Font License 1.1; see `assets/fonts/OFL-1.1.txt`. The CHM reader uses
libmspack code under LGPL-2.1-or-later, and Spleen is BSD-2-Clause. Their
notices and the other font-pack licenses are in `LICENSES/`.

<!-- end of DEPENDENCY.md -->
