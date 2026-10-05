/'
    Project: OpenSesh
    ---------------------------

    File: tests/user_preferences_smoke.bas

    Module API: Test executable; process status reports failed behavioral assertions.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Verify visual and interaction preferences survive restarts without
        accepting corrupt input or damaging the last valid settings file.

    Responsibilities:

        - round-trip Light, Dark, and Black preferences
        - round-trip precise-pointer and touch interaction preferences
        - round-trip an optional SoundFont path without platform rewriting
        - load legacy theme-only version 1 preferences as precise-pointer UI
        - pin the versioned canonical settings representation
        - reject malformed, duplicate, oversized, and binary input
        - prove failed saves preserve the previous valid file
        - keep every test artifact in a caller-selected temporary location

    This file intentionally does NOT contain:

        - access to the real user profile
        - GUI construction
        - document serialization
'/

#lang "fb"

#include once "../src/user_preferences.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Sub test_WriteData( _
    ByVal filename As String, _
    ByRef fileData As String _
)
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Write As #fileNumber) <> 0 Then _
        test_Fail "could not create malformed-input fixture"
    Put #fileNumber, 1, fileData
    Close #fileNumber
End Sub


Private Function test_ReadData(ByVal filename As String) As String
    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then _
        test_Fail "could not read preference fixture"
    Dim As LongInt fileBytes = Lof(fileNumber)
    Dim As String fileData
    If fileBytes > 0 Then
        fileData = Space(CInt(fileBytes))
        Get #fileNumber, 1, fileData
    End If
    Close #fileNumber
    Return fileData
End Function


Private Sub test_ExpectInvalid( _
    ByVal filename As String, _
    ByRef fileData As String, _
    ByVal caseName As String, _
    ByRef rejectedCount As Integer _
)
    test_WriteData filename, fileData
    Dim As OseUserPreferences retainedPreferences
    retainedPreferences.themeMode = 77
    retainedPreferences.interactionMode = 78
    retainedPreferences.soundFontPath = "retained.sf2"
    If userPreferences_Load(filename, retainedPreferences) <> _
        OSE_PREFERENCES_LOAD_INVALID OrElse _
        retainedPreferences.themeMode <> 77 OrElse _
        retainedPreferences.interactionMode <> 78 OrElse _
        retainedPreferences.soundFontPath <> "retained.sf2" Then _
        test_Fail caseName + " was accepted or changed caller state"
    rejectedCount += 1
End Sub


Dim As String filename = Trim(Command(1))
If filename = "" Then
    test_Fail "temporary preference filename is required"
End If

Dim As OseUserPreferences preferences
userPreferences_Default preferences
If preferences.themeMode <> OSE_UI_THEME_LIGHT Then _
    test_Fail "default theme is not Light"
If preferences.interactionMode <> OSE_UI_INTERACTION_FINE Then _
    test_Fail "default interaction is not precise-pointer"
If preferences.soundFontPath <> "" Then _
    test_Fail "default SoundFont path is not empty"

Dim As Integer roundTripCount
For themeMode As Integer = OSE_UI_THEME_LIGHT To OSE_UI_THEME_BLACK
    For interactionMode As Integer = OSE_UI_INTERACTION_FINE To _
        OSE_UI_INTERACTION_TOUCH
        preferences.themeMode = themeMode
        preferences.interactionMode = interactionMode
        If userPreferences_Save(filename, preferences) = 0 Then _
            test_Fail "valid preference pair could not be saved"
        Dim As OseUserPreferences loadedPreferences
        loadedPreferences.themeMode = 99
        loadedPreferences.interactionMode = 98
        If userPreferences_Load(filename, loadedPreferences) <> _
            OSE_PREFERENCES_LOAD_OK OrElse _
            loadedPreferences.themeMode <> themeMode OrElse _
            loadedPreferences.interactionMode <> interactionMode Then _
            test_Fail "saved preference pair did not round-trip"
        roundTripCount += 1
    Next
Next

Dim As String lineBreak = Chr(10)
Dim As String canonicalBlack = _
    "format=OpenSeshPreferences" + lineBreak + _
    "version=1" + lineBreak + _
    "theme=black" + lineBreak + _
    "interaction=touch" + lineBreak
If test_ReadData(filename) <> canonicalBlack Then _
    test_Fail "canonical Black preference bytes changed"
If Dir(filename + ".ose-tmp-*") <> "" Then _
    test_Fail "successful save left an atomic temporary file"

Dim As String soundFontPath = "C:\SoundFonts\Timbres of Heaven 4.00.sf2" ' fblint: disable-line FBL007 REASON: This path is parser/serialization test data; the test does not open a Windows file.
preferences.soundFontPath = soundFontPath
If userPreferences_Save(filename, preferences) = 0 Then _
    test_Fail "SoundFont preference could not be saved"
Dim As OseUserPreferences soundFontPreferences
If userPreferences_Load(filename, soundFontPreferences) <> _
    OSE_PREFERENCES_LOAD_OK OrElse _
    soundFontPreferences.soundFontPath <> soundFontPath Then _
    test_Fail "SoundFont preference path did not round-trip"

Dim As OseUserPreferences missingPreferences
missingPreferences.themeMode = 88
missingPreferences.interactionMode = 87
missingPreferences.soundFontPath = "missing-retained.sf2"
Dim As String missingFilename = filename + ".missing"
If userPreferences_Load(missingFilename, missingPreferences) <> _
    OSE_PREFERENCES_LOAD_MISSING OrElse _
    missingPreferences.themeMode <> 88 OrElse _
    missingPreferences.interactionMode <> 87 OrElse _
    missingPreferences.soundFontPath <> "missing-retained.sf2" Then _
    test_Fail "missing file was not reported transactionally"

Dim As String legacyData = _
    "format=OpenSessionEditorPreferences" + lineBreak + _
    "version=1" + lineBreak + _
    "theme=dark" + lineBreak
test_WriteData filename, legacyData
Dim As OseUserPreferences legacyPreferences
If userPreferences_Load(filename, legacyPreferences) <> _
    OSE_PREFERENCES_LOAD_OK OrElse _
    legacyPreferences.themeMode <> OSE_UI_THEME_DARK OrElse _
    legacyPreferences.interactionMode <> OSE_UI_INTERACTION_FINE Then _
    test_Fail "legacy product preference did not load with precise-pointer UI"

Dim As Integer rejectedCount
Dim As String invalidData
invalidData = "": test_ExpectInvalid filename, invalidData, _
    "empty file", rejectedCount
invalidData = Space(8193): test_ExpectInvalid filename, invalidData, _
    "oversized file", rejectedCount
invalidData = "format=OpenSeshPreferences" + Chr(0) + lineBreak + _
    "version=1" + lineBreak + "theme=light" + lineBreak
test_ExpectInvalid filename, invalidData, "NUL byte", rejectedCount
invalidData = "malformed" + lineBreak
test_ExpectInvalid filename, invalidData, "line without equals", rejectedCount
invalidData = "version=1" + lineBreak + "theme=light" + lineBreak
test_ExpectInvalid filename, invalidData, "missing format", rejectedCount
invalidData = "format=OpenSeshPreferences" + lineBreak + _
    "theme=light" + lineBreak
test_ExpectInvalid filename, invalidData, "missing version", rejectedCount
invalidData = "format=OpenSeshPreferences" + lineBreak + _
    "version=1" + lineBreak
test_ExpectInvalid filename, invalidData, "missing theme", rejectedCount
invalidData = "format=OpenSeshPreferences" + lineBreak + _
    "format=OpenSeshPreferences" + lineBreak + _
    "version=1" + lineBreak + "theme=light" + lineBreak
test_ExpectInvalid filename, invalidData, "duplicate format", rejectedCount
invalidData = "format=OpenSeshPreferences" + lineBreak + _
    "version=1" + lineBreak + "version=1" + lineBreak + _
    "theme=light" + lineBreak
test_ExpectInvalid filename, invalidData, "duplicate version", rejectedCount
invalidData = "format=OpenSeshPreferences" + lineBreak + _
    "version=1" + lineBreak + "theme=light" + lineBreak + _
    "theme=dark" + lineBreak
test_ExpectInvalid filename, invalidData, "duplicate theme", rejectedCount
invalidData = "format=OpenSeshPreferences" + lineBreak + _
    "version=2" + lineBreak + "theme=light" + lineBreak
test_ExpectInvalid filename, invalidData, "unsupported version", rejectedCount
invalidData = "format=OpenSeshPreferences" + lineBreak + _
    "version=1" + lineBreak + "theme=sepia" + lineBreak
test_ExpectInvalid filename, invalidData, "unknown theme", rejectedCount
invalidData = "format=OpenSeshPreferences" + lineBreak + _
    "version=1" + lineBreak + "theme=light" + lineBreak + _
    "interaction=joystick" + lineBreak
test_ExpectInvalid filename, invalidData, "unknown interaction", rejectedCount
invalidData = "format=OpenSeshPreferences" + lineBreak + _
    "version=1" + lineBreak + "theme=light" + lineBreak + _
    "interaction=fine" + lineBreak + "interaction=touch" + lineBreak
test_ExpectInvalid filename, invalidData, "duplicate interaction", rejectedCount
invalidData = "format=OpenSeshPreferences" + lineBreak + _
    "version=1" + lineBreak + "theme=light" + lineBreak + _
    "soundfont=first.sf2" + lineBreak + "soundfont=second.sf2" + lineBreak
test_ExpectInvalid filename, invalidData, "duplicate SoundFont", rejectedCount
invalidData = "format=OpenSeshPreferences" + lineBreak + _
    "version=1" + lineBreak + "future=" + Space(4353) + lineBreak + _
    "theme=light" + lineBreak
test_ExpectInvalid filename, invalidData, "overlong line", rejectedCount
invalidData = "format=OpenSeshPreferences" + Chr(13) + _
    "version=1" + lineBreak + "theme=light" + lineBreak
test_ExpectInvalid filename, invalidData, "bare carriage return", rejectedCount

' Unknown keys are retained for forward-compatible readers. They are ignored
' only after the line itself has passed the same size and syntax checks.
Dim As String futureData = "format=OpenSeshPreferences" + lineBreak + _
    "version=1" + lineBreak + "future_feature=enabled" + lineBreak + _
    "theme=dark" + lineBreak
test_WriteData filename, futureData
Dim As OseUserPreferences futurePreferences
If userPreferences_Load(filename, futurePreferences) <> _
    OSE_PREFERENCES_LOAD_OK OrElse _
    futurePreferences.themeMode <> OSE_UI_THEME_DARK OrElse _
    futurePreferences.interactionMode <> OSE_UI_INTERACTION_FINE Then _
    test_Fail "forward-compatible unknown key was rejected"

' A rejected save must not touch the last valid image. This is the important
' atomicity contract from the caller's perspective, not merely a temp-file test.
Dim As String retainedData = test_ReadData(filename)
preferences.themeMode = 999
If userPreferences_Save(filename, preferences) <> 0 OrElse _
    test_ReadData(filename) <> retainedData Then _
    test_Fail "invalid save damaged the retained settings file"

Print "user_preferences=ok"
Print "preference_pair_round_trips="; roundTripCount; _
    " malformed_rejections="; rejectedCount; " atomic_preservation=1"
End 0

/' end of tests/user_preferences_smoke.bas '/
