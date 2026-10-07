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
        - an upstream commit identity
        - the license text
-->

# Shared omaGUI tree

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

The October 7 shared snapshot starts from Tiko's optimized tree at
`e5a29867c3bef9dea5b4a796459dd80407906854`, which incorporates OpenSesh's
maintained overlay on `40cd4f73835973b69ed692bd51619449626bf0ff`.
Both copies retain the CSS
selector bounds checks, unallocated image-array guard, label styles and
literal-color support. The shared APIs include byte-span comparison, font
metrics, palette roles, bounded menu update scopes, cached display captions,
clipped popup replay and retained paint bounds.

The Optical FreeBASIC and newjrpg copies contribute VBDOS border styles,
same-frame TextBox KeyDown remapping, guarded modal dialog registration, and
duplicate-widget protection. The OpenSesh copy contributes the allocation
query for raster input, a bounds check for bare CSS class selectors, and
trailing-NUL handling in RTF input.

The retained renderer and textbox compare cached observations without
constructing temporary strings. Raster palette fields retain their named
components. Observation matching stays on the GUI thread and checks the
recorded lengths and offsets before comparing source bytes. DOSBox-X timed
idle remains opt-in and requires a gfxlib with the matching backend entrypoint.

Semantic lint must compile `omaGUI.bi` with `OMAGUI_IMPLEMENTATION` in a real
root and select the same platform and font definitions as the application.
Implementation `.bas` files are includes, so compiling them independently
does not represent the library's build model. A validator must reject missing
compiler facts rather than fall back to heuristic name resolution.

omaGUI is MIT licensed; see `LICENSE`. Generated font subsets use the SIL Open
Font License 1.1; see `assets/fonts/OFL-1.1.txt`. The CHM reader uses
libmspack code under LGPL-2.1-or-later, and Spleen is BSD-2-Clause. Their
notices and the other font-pack licenses are in `LICENSES/`.

<!-- end of DEPENDENCY.md -->