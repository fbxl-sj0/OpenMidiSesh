/'
    Project: OpenSesh
    ---------------------------

    File: sfx_runtime.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements sfx_runtime.bi; declarations there define the shared interface.

    Purpose:

        Release sfxlib worker threads and process-wide audio resources before
        the FreeBASIC runtime begins its own finalization.

    Responsibilities:

        - initialize and restart the audio engine through supported sfxlib calls
        - advance a generation whenever retained mixer state becomes invalid
        - call the public sfxlib shutdown entry point explicitly
        - preserve the library's documented idempotent shutdown behavior

    This file intentionally does NOT contain:

        - audio-device enumeration or selection
        - playback or capture state
        - emergency process termination
'/

#lang "fb"

#inclib "sfx" ' fblint: disable-line FBL930 REASON: The supported FreeBASIC toolchain supplies sfx on Windows and Linux.
#include once "sfx_runtime.bi"

/'
    sfxlib runtime contract

    fb_sfxInit is idempotent and fb_sfxExit accepts repeated calls. Exit stops
    the active driver and capture workers, shuts down the mixer and buffers,
    and clears FreeBASIC's registered sfxlib exit callback. Any configuration
    retained by an application is therefore tied to one runtime generation.
'/
Declare Function fb_sfxInit CDecl Alias "fb_sfxInit" () As Long
Declare Sub fb_sfxExit CDecl Alias "fb_sfxExit" ()

' fblint: disable-next-line FBL301 REASON: this module owns the process-wide runtime generation.
Dim Shared sfxRuntime_Generation As Integer = 1


Private Sub sfxRuntime_AdvanceGeneration()
    Const maximumGeneration As Integer = 2147483647
    If sfxRuntime_Generation = maximumGeneration Then
        sfxRuntime_Generation = 1
    Else
        sfxRuntime_Generation += 1
    End If
End Sub


Public Function sfxRuntime_EnsureReady() As Integer
    Return IIf(fb_sfxInit() = 0, -1, 0)
End Function


Public Function sfxRuntime_Restart() As Integer
    sfxRuntime_Shutdown()
    Return sfxRuntime_EnsureReady()
End Function


Public Function sfxRuntime_GetGeneration() As Integer
    Return sfxRuntime_Generation
End Function


Public Sub sfxRuntime_Shutdown()
    fb_sfxExit()
    sfxRuntime_AdvanceGeneration()
End Sub

/' end of sfx_runtime.bas '/
