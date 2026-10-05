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

omaGUI is MIT licensed; see `LICENSE`. Generated font subsets use the SIL Open
Font License 1.1; see `assets/fonts/OFL-1.1.txt`. The CHM reader uses
libmspack code under LGPL-2.1-or-later, and Spleen is BSD-2-Clause. Their
notices and the other font-pack licenses are in `LICENSES/`.

<!-- end of DEPENDENCY.md -->