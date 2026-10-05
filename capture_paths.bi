/'
    Project: OpenSesh
    ---------------------------

    File: capture_paths.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: capturePaths_* filename allocation and path operations.

    Purpose:

        Declare portable path helpers for retained microphone and audio takes.

    Responsibilities:

        - join a directory and leaf name with the target separator
        - obtain the parent directory of Windows or Unix-style paths
        - select a bounded unused capture filename without overwriting data

    This file intentionally does NOT contain:

        - user-directory policy
        - directory creation
        - audio capture or WAV writing
'/

#ifndef __OSE_CAPTURE_PATHS_BI__
#define __OSE_CAPTURE_PATHS_BI__

#include once "dir.bi"

Const OSE_CAPTURE_PATH_MAX_BYTES As Integer = 4096
Const OSE_CAPTURE_PATH_CANDIDATES As Integer = 1000

Declare Function capturePaths_Separator() As String

Declare Function capturePaths_Join( _
    ByVal directoryName As String, _
    ByVal leafName As String _
) As String

Declare Function capturePaths_ParentDirectory( _
    ByVal filename As String _
) As String

Declare Function capturePaths_NewFilename( _
    ByVal directoryName As String, _
    ByVal filenameStem As String, _
    ByVal extensionText As String _
) As String

#endif

/' end of capture_paths.bi '/
