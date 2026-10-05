/'
    Project: OpenSesh
    ---------------------------

    File: user_preferences.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements user_preferences.bi; declarations there define the shared interface.

    Purpose:

        Persist application preferences without risking an existing settings
        file when input, output, or replacement fails.

    Responsibilities:

        - parse a small, versioned, human-readable settings format
        - reject malformed or unreasonably large input transactionally
        - write complete settings through the shared atomic-file helper
        - select the conventional Windows or Linux per-user config directory
        - preserve the platform-neutral interaction profile
        - preserve an optional platform-neutral SoundFont filename

    Ownership:

        Load operations own and close their file handles. The atomic-file
        helper owns temporary output files; preference values belong to the
        caller and are replaced only after complete validation.

    This file intentionally does NOT contain:

        - editor-global state
        - GUI status reporting
        - project or MIDI serialization
'/

#lang "fb"

#include once "user_preferences.bi"
#include once "atomic_file_internal.bi"

Const USER_PREFERENCES_MAX_FILE_BYTES As Integer = 8192
Const USER_PREFERENCES_MAX_LINE_BYTES As Integer = 4352
Const USER_PREFERENCES_MAX_SOUNDFONT_PATH_BYTES As Integer = 4096

' -------------------------------------------------------------------------
' Bounded path helpers
' -------------------------------------------------------------------------

Private Function userPreferences_ValidPathText( _
    ByVal pathText As String _
) As Integer
    If pathText = "" OrElse _
        Len(pathText) > ATOMIC_FILE_MAX_PATH_BYTES OrElse _
        InStr(pathText, Chr(0)) > 0 Then
        Return 0
    End If
    Return -1
End Function


Private Function userPreferences_DirectoryExists( _
    ByVal directoryName As String _
) As Integer
    If userPreferences_ValidPathText(directoryName) = 0 Then
        Return 0
    End If
    Return IIf(Dir(directoryName, fbDirectory) <> "", -1, 0)
End Function


Private Function userPreferences_JoinPath( _
    ByVal directoryName As String, _
    ByVal leafName As String _
) As String
    If userPreferences_ValidPathText(directoryName) = 0 OrElse _
        leafName = "" OrElse InStr(leafName, Chr(0)) > 0 Then
        Return ""
    End If

#If Defined(__FB_WIN32__)
    Const pathSeparator As String = "\"
#Else
    Const pathSeparator As String = "/"
#EndIf

    Dim As String joinedPath
    If Right(directoryName, 1) = "\" OrElse _
        Right(directoryName, 1) = "/" Then
        joinedPath = directoryName + leafName
    Else
        joinedPath = directoryName + pathSeparator + leafName
    End If
    If Len(joinedPath) > ATOMIC_FILE_MAX_PATH_BYTES Then
        Return ""
    End If
    Return joinedPath
End Function


Private Function userPreferences_EnsureChildDirectory( _
    ByVal parentDirectory As String, _
    ByVal childName As String _
) As String
    If userPreferences_DirectoryExists(parentDirectory) = 0 Then
        Return ""
    End If
    Dim As String childDirectory = userPreferences_JoinPath( _
        parentDirectory, childName)
    If childDirectory = "" Then
        Return ""
    End If
    If userPreferences_DirectoryExists(childDirectory) = 0 Then
        If MkDir(childDirectory) <> 0 Then
            Return ""
        End If
    End If
    If userPreferences_DirectoryExists(childDirectory) = 0 Then
        Return ""
    End If
    Return childDirectory
End Function

' -------------------------------------------------------------------------
' Preferences format
' -------------------------------------------------------------------------

Private Function userPreferences_ThemeText( _
    ByVal themeMode As Integer _
) As String
    Dim As String resultText
    Select Case themeMode
        Case OSE_UI_THEME_LIGHT
            resultText = "light"
        Case OSE_UI_THEME_DARK
            resultText = "dark"
        Case OSE_UI_THEME_BLACK
            resultText = "black"
        Case Else
            resultText = ""
    End Select
    Return resultText
End Function


Private Function userPreferences_ParseTheme( _
    ByVal themeText As String, _
    ByRef themeMode As Integer _
) As Integer
    Select Case LCase(themeText)
        Case "light"
            themeMode = OSE_UI_THEME_LIGHT
        Case "dark"
            themeMode = OSE_UI_THEME_DARK
        Case "black"
            themeMode = OSE_UI_THEME_BLACK
        Case Else
            Return 0
    End Select
    Return -1
End Function


Private Function userPreferences_Parse( _
    ByRef fileData As String, _
    ByRef preferences As OseUserPreferences _
) As Integer
    If Len(fileData) < 1 OrElse _
        Len(fileData) > USER_PREFERENCES_MAX_FILE_BYTES OrElse _
        InStr(fileData, Chr(0)) > 0 Then
        Return 0
    End If

    Dim As Integer formatCount
    Dim As Integer versionCount
    Dim As Integer themeCount
    Dim As Integer interactionCount
    Dim As Integer soundFontCount
    Dim As OseUserPreferences parsedPreferences
    userPreferences_Default parsedPreferences

    Dim As Integer lineStart = 1
    While lineStart <= Len(fileData)
        Dim As Integer lineEnd = InStr(lineStart, fileData, Chr(10))
        Dim As String lineText
        If lineEnd > 0 Then
            lineText = Mid(fileData, lineStart, lineEnd - lineStart)
            lineStart = lineEnd + 1
        Else
            lineText = Mid(fileData, lineStart)
            lineStart = Len(fileData) + 1
        End If

        If Len(lineText) > USER_PREFERENCES_MAX_LINE_BYTES Then
            Return 0
        End If
        If Right(lineText, 1) = Chr(13) Then
            lineText = Left(lineText, Len(lineText) - 1)
        End If
        If InStr(lineText, Chr(13)) > 0 Then
            Return 0
        End If
        lineText = Trim(lineText)
        If lineText = "" OrElse Left(lineText, 1) = "#" Then
            Continue While
        End If

        Dim As Integer equalsPosition = InStr(lineText, "=")
        If equalsPosition <= 1 Then
            Return 0
        End If
        Dim As String keyText = LCase(Trim(Left( _
            lineText, equalsPosition - 1)))
        Dim As String valueText = Trim(Mid(lineText, equalsPosition + 1))
        If keyText = "" OrElse valueText = "" Then
            Return 0
        End If

        Select Case keyText
            Case "format"
                formatCount += 1
                If formatCount <> 1 OrElse _
                    (valueText <> "OpenSeshPreferences" AndAlso _
                    valueText <> "OpenSessionEditorPreferences") Then
                    Return 0
                End If
            Case "version"
                versionCount += 1
                If versionCount <> 1 OrElse valueText <> "1" Then
                    Return 0
                End If
            Case "theme"
                themeCount += 1
                If themeCount <> 1 OrElse _
                    userPreferences_ParseTheme( _
                        valueText, parsedPreferences.themeMode) = 0 Then
                    Return 0
                End If
            Case "interaction"
                interactionCount += 1
                If interactionCount <> 1 OrElse _
                    uiInteraction_Parse(valueText, _
                        parsedPreferences.interactionMode) = 0 Then
                    Return 0
                End If
            Case "soundfont"
                soundFontCount += 1
                If soundFontCount <> 1 OrElse _
                    Len(valueText) > USER_PREFERENCES_MAX_SOUNDFONT_PATH_BYTES OrElse _
                    InStr(valueText, Chr(0)) > 0 OrElse _
                    InStr(valueText, Chr(10)) > 0 OrElse _
                    InStr(valueText, Chr(13)) > 0 Then
                    Return 0
                End If
                parsedPreferences.soundFontPath = valueText
            Case Else
                ' Unknown well-formed keys are reserved for future versions.
                Continue While
        End Select
    Wend

    If formatCount <> 1 OrElse versionCount <> 1 OrElse _
        themeCount <> 1 Then
        Return 0
    End If
    preferences = parsedPreferences
    Return -1
End Function

' -------------------------------------------------------------------------
' Public lifecycle and storage
' -------------------------------------------------------------------------

Public Sub userPreferences_Default(ByRef preferences As OseUserPreferences)
    Dim As OseUserPreferences emptyPreferences
    preferences = emptyPreferences
    preferences.themeMode = OSE_UI_THEME_LIGHT
    preferences.interactionMode = OSE_UI_INTERACTION_FINE
    preferences.soundFontPath = ""
End Sub


Public Function userPreferences_Load( _
    ByVal filename As String, _
    ByRef preferences As OseUserPreferences _
) As Integer
    If userPreferences_ValidPathText(filename) = 0 Then
        Return OSE_PREFERENCES_LOAD_INVALID
    End If
    If Dir(filename) = "" Then
        Return OSE_PREFERENCES_LOAD_MISSING
    End If

    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        ' fblint: disable-next-line FBL-IO-004 REASON: a failed Open does not own a file handle.
        Return OSE_PREFERENCES_LOAD_INVALID
    End If
    Dim As LongInt fileBytes = Lof(fileNumber)
    If fileBytes < 1 OrElse fileBytes > USER_PREFERENCES_MAX_FILE_BYTES Then
        Close #fileNumber
        Return OSE_PREFERENCES_LOAD_INVALID
    End If
    Dim As String fileData = Space(CInt(fileBytes))
    If binaryFile_ReadExact(fileNumber, 1, StrPtr(fileData), Len(fileData)) = 0 Then
        Close #fileNumber
        Return OSE_PREFERENCES_LOAD_INVALID
    End If
    Close #fileNumber

    Dim As OseUserPreferences parsedPreferences
    If userPreferences_Parse(fileData, parsedPreferences) = 0 Then
        Return OSE_PREFERENCES_LOAD_INVALID
    End If
    preferences = parsedPreferences
    Return OSE_PREFERENCES_LOAD_OK
End Function


Public Function userPreferences_Save( _
    ByVal filename As String, _
    ByRef preferences As OseUserPreferences _
) As Integer
    Dim As String themeText = userPreferences_ThemeText(preferences.themeMode)
    Dim As String interactionText = uiInteraction_PreferenceText( _
        preferences.interactionMode)
    If themeText = "" OrElse interactionText = "" OrElse _
        userPreferences_ValidPathText(filename) = 0 Then
        Return 0
    End If

    Dim As String soundFontLine
    If preferences.soundFontPath <> "" Then
        If Len(preferences.soundFontPath) > _
            USER_PREFERENCES_MAX_SOUNDFONT_PATH_BYTES OrElse _
            InStr(preferences.soundFontPath, Chr(0)) > 0 OrElse _
            InStr(preferences.soundFontPath, Chr(10)) > 0 OrElse _
            InStr(preferences.soundFontPath, Chr(13)) > 0 Then
            Return 0
        End If
        soundFontLine = "soundfont=" + preferences.soundFontPath + Chr(10)
    End If

    Dim As String lineBreak = Chr(10)
    Dim As String fileData = _
        "format=OpenSeshPreferences" + lineBreak + _
        "version=1" + lineBreak + _
        "theme=" + themeText + lineBreak + _
        "interaction=" + interactionText + lineBreak + _
        soundFontLine
    Return atomicFile_WriteVerified(filename, fileData)
End Function


Public Function userPreferences_DefaultFilename( _
    ByVal createDirectories As Integer _
) As String
    Dim As String baseDirectory
    Dim As String applicationDirectory
    Dim As String legacyApplicationDirectory

#If Defined(__FB_WIN32__)
    baseDirectory = Trim(Environ("LOCALAPPDATA")) ' fblint: disable-line FBL750 REASON: Each config-directory candidate is validated; no valid candidate disables persistence.
    If userPreferences_ValidPathText(baseDirectory) = 0 Then
        baseDirectory = Trim(Environ("APPDATA")) ' fblint: disable-line FBL750 REASON: Each config-directory candidate is validated; no valid candidate disables persistence.
    End If
    If userPreferences_ValidPathText(baseDirectory) = 0 Then
        Return ""
    End If
    If createDirectories <> 0 Then
        applicationDirectory = userPreferences_EnsureChildDirectory( _
            baseDirectory, "OpenSesh")
    Else
        applicationDirectory = userPreferences_JoinPath( _
            baseDirectory, "OpenSesh")
    End If
    legacyApplicationDirectory = userPreferences_JoinPath( _
        baseDirectory, "Open Session Editor")
#Else
    baseDirectory = Trim(Environ("XDG_CONFIG_HOME")) ' fblint: disable-line FBL750 REASON: Each config-directory candidate is validated; no valid candidate disables persistence.
    If userPreferences_ValidPathText(baseDirectory) = 0 Then
        Dim As String homeDirectory = Trim(Environ("HOME")) ' fblint: disable-line FBL750 REASON: Each config-directory candidate is validated; no valid candidate disables persistence.
        If userPreferences_ValidPathText(homeDirectory) = 0 Then
            Return ""
        End If
        If createDirectories <> 0 Then
            baseDirectory = userPreferences_EnsureChildDirectory( _
                homeDirectory, ".config")
        Else
            baseDirectory = userPreferences_JoinPath(homeDirectory, ".config")
        End If
    ElseIf createDirectories <> 0 AndAlso _
        userPreferences_DirectoryExists(baseDirectory) = 0 Then
        ' XDG_CONFIG_HOME is allowed to name a new directory, but this bounded
        ' module will not recursively manufacture an untrusted parent chain.
        If MkDir(baseDirectory) <> 0 Then
            Return ""
        End If
    End If
    If createDirectories <> 0 Then
        applicationDirectory = userPreferences_EnsureChildDirectory( _
            baseDirectory, "opensesh")
    Else
        applicationDirectory = userPreferences_JoinPath( _
            baseDirectory, "opensesh")
    End If
    legacyApplicationDirectory = userPreferences_JoinPath( _
        baseDirectory, "open-session-editor")
#EndIf

    If applicationDirectory = "" Then
        Return ""
    End If
    Dim As String preferenceFilename = userPreferences_JoinPath( _
        applicationDirectory, "settings.conf")
    If preferenceFilename = "" Then
        Return ""
    End If

    /'
        Read-only startup lookup retains the old product path as a migration
        bridge. Saving requests directory creation and therefore always writes
        the canonical OpenSesh path.
    '/
    If createDirectories = 0 AndAlso Dir(preferenceFilename) = "" AndAlso _
        legacyApplicationDirectory <> "" Then
        Dim As String legacyFilename = userPreferences_JoinPath( _
            legacyApplicationDirectory, "settings.conf")
        If legacyFilename <> "" AndAlso Dir(legacyFilename) <> "" Then
            Return legacyFilename
        End If
    End If
    Return preferenceFilename
End Function

/' end of user_preferences.bas '/
