/'
    Project: OpenSesh
    ---------------------------

    File: user_preferences.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: userPreferences_* defaults/load/save/path operations with OseUserPreferences.

    Purpose:

        Declare the bounded application preferences stored between launches.

    Responsibilities:

        - hold the selected Light, Dark, or Black theme
        - hold the precise-pointer or touch interaction profile
        - hold the optional user-selected SoundFont path
        - expose transactional load and atomic save operations
        - resolve the platform-appropriate per-user settings filename

    This file intentionally does NOT contain:

        - widget or menu code
        - document settings
        - registry access
'/

#ifndef __OSE_USER_PREFERENCES_BI__
#define __OSE_USER_PREFERENCES_BI__

#include once "dir.bi"
#include once "ui_style.bi"
#include once "ui_interaction.bi"

Const OSE_PREFERENCES_LOAD_INVALID As Integer = -1
Const OSE_PREFERENCES_LOAD_MISSING As Integer = 0
Const OSE_PREFERENCES_LOAD_OK As Integer = 1

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type OseUserPreferences
    As Integer themeMode
    As Integer interactionMode
    As String soundFontPath
End Type

Declare Sub userPreferences_Default(ByRef preferences As OseUserPreferences)

Declare Function userPreferences_Load( _
    ByVal filename As String, _
    ByRef preferences As OseUserPreferences _
) As Integer

Declare Function userPreferences_Save( _
    ByVal filename As String, _
    ByRef preferences As OseUserPreferences _
) As Integer

Declare Function userPreferences_DefaultFilename( _
    ByVal createDirectories As Integer = 0 _
) As String

#endif

/' end of user_preferences.bi '/
