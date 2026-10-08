/'
    Project: omaGUI
    ---------------

    File: clipboard.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements clipboard.bi; declarations there define the interface.

    Purpose:

        Exchange bounded plain text through a portable process-local clipboard
        and, when an application explicitly requests it, a host bridge.

    Responsibilities:

        - make the bounded process-local clipboard the default implementation
        - use the Win32 text clipboard only in opted-in Windows builds
        - use Wayland, X11 and optional Tk bridges in opted-in Unix builds
        - allow applications to force the portable implementation
        - reject unbounded clipboard payload growth

    This file intentionally does NOT contain:

        - widget focus or selection rules
        - rich-text conversion
        - image clipboard formats
'/

#lang "fb"

#include once "src/backend/clipboard.bi"

/'
    Clipboard backend selection

    The default build uses only omaGUI's bounded process-local text store. This
    matters for applications which need one native FreeBASIC source path across
    hosted and non-hosted targets.

    An application may define OMAGUI_ENABLE_HOST_CLIPBOARD before
    OMAGUI_IMPLEMENTATION to opt into the matching host bridge. The existing
    OMAGUI_DISABLE_HOST_CLIPBOARD and OMAGUI_PORTABLE_ONLY switches override
    that opt-in and always select the process-local implementation.
'/
#If Defined(OMAGUI_ENABLE_HOST_CLIPBOARD) AndAlso _
    Not Defined(OMAGUI_DISABLE_HOST_CLIPBOARD) AndAlso _
    Not Defined(OMAGUI_PORTABLE_ONLY) AndAlso _
    Defined(__FB_WIN32__)
    #Define OMAGUI_CLIPBOARD_WIN32
    #Include Once "src/backend/backend_windows.bi"
#ElseIf Defined(OMAGUI_ENABLE_HOST_CLIPBOARD) AndAlso _
    Not Defined(OMAGUI_DISABLE_HOST_CLIPBOARD) AndAlso _
    Not Defined(OMAGUI_PORTABLE_ONLY) AndAlso _
    (Defined(__FB_LINUX__) Or Defined(__FB_FREEBSD__) Or _
     Defined(__FB_OPENBSD__))
    #Define OMAGUI_CLIPBOARD_UNIX
#EndIf

' -------------------------------------------------------------------------
' Process-local fallback
' -------------------------------------------------------------------------

/'
    FreeBASIC does not currently expose a common host-clipboard API. This
    bounded copy remains available when the selected host integration cannot
    be compiled or reached, and it keeps intra-application editing reliable.
'/
' This is boundary-owned process state. FB-LINTER: DISABLE-NEXT-LINE FBL301
Dim Shared clipboard_FallbackText As String


Private Function clipboard_BoundedText(ByVal textValue As String) As String

    If Len(textValue) > CLIPBOARD_MAX_TEXT_BYTES Then
        Return Left(textValue, CLIPBOARD_MAX_TEXT_BYTES)
    End If

    Return textValue

End Function

' -------------------------------------------------------------------------
' Windows clipboard backend
' -------------------------------------------------------------------------

#If Defined(OMAGUI_CLIPBOARD_WIN32)

Const CLIPBOARD_WINDOWS_OPEN_ATTEMPTS As Integer = 5
Const CLIPBOARD_WINDOWS_RETRY_MILLISECONDS As Integer = 1


Private Function clipboard_WindowsOpen() As Integer

    ' fblint: disable-next-line FBL311 REASON: The loop counter bounds repeated work; the cursor or stream state supplies each value.
    For attemptIndex As Integer = 1 To CLIPBOARD_WINDOWS_OPEN_ATTEMPTS
        If omaGUI_NativeWindows.OpenClipboard(0) <> 0 Then Return 1
        Sleep CLIPBOARD_WINDOWS_RETRY_MILLISECONDS, 1
    Next attemptIndex

    Return 0

End Function


Private Function clipboard_WindowsGetText() As String

    Dim byteCount As UInteger
    Dim clipboardHandle As Any Ptr
    Dim clipboardMemory As Any Ptr
    Dim resultText As String

    If omaGUI_NativeWindows.IsClipboardFormatAvailable(omaGUI_NativeWindows.TextFormat) = 0 Then Return ""
    If clipboard_WindowsOpen() = 0 Then Return ""

    clipboardHandle = omaGUI_NativeWindows.GetClipboardData(omaGUI_NativeWindows.TextFormat)

    If clipboardHandle <> 0 Then
        clipboardMemory = omaGUI_NativeWindows.GlobalLock(clipboardHandle)

        If clipboardMemory <> 0 Then
            byteCount = omaGUI_NativeWindows.GlobalSize(clipboardHandle)

            If byteCount > 0 Then
                If byteCount > CLIPBOARD_MAX_TEXT_BYTES Then byteCount = CLIPBOARD_MAX_TEXT_BYTES
                Dim As UByte Ptr bytes = clipboardMemory
                Dim As UInteger textBytes
                While textBytes < byteCount
                    If bytes[textBytes] = 0 Then Exit While
                    textBytes += 1
                Wend
                resultText = Space(textBytes)
                If textBytes > 0 Then
                For byteIndex As UInteger = 0 To textBytes - 1
                    resultText[byteIndex] = bytes[byteIndex]
                Next
                End If
            End If

            ' Win32 import exists only inside this backend. FB-LINTER: DISABLE-NEXT-LINE FBL310
            omaGUI_NativeWindows.GlobalUnlock clipboardHandle
        End If
    End If

    omaGUI_NativeWindows.CloseClipboard()
    Return resultText

End Function


Private Function clipboard_WindowsSetText( _
    ByVal textValue As String _
) As Integer

    Dim allocationFlags As ULong
    Dim clipboardHandle As Any Ptr
    Dim clipboardMemory As Any Ptr
    Dim clipboardResult As Any Ptr

    If clipboard_WindowsOpen() = 0 Then Return 0

    If omaGUI_NativeWindows.EmptyClipboard() = 0 Then
        omaGUI_NativeWindows.CloseClipboard()
        Return 0
    End If

    ' Movable ownership is required by omaGUI_NativeWindows.SetClipboardData. FB-LINTER: DISABLE-NEXT-LINE FBL310
    allocationFlags = omaGUI_NativeWindows.MovableMemory Or omaGUI_NativeWindows.ZeroedMemory
    clipboardHandle = omaGUI_NativeWindows.GlobalAlloc(allocationFlags, Len(textValue) + 1)

    If clipboardHandle = 0 Then
        omaGUI_NativeWindows.CloseClipboard()
        Return 0
    End If

    clipboardMemory = omaGUI_NativeWindows.GlobalLock(clipboardHandle)

    If clipboardMemory = 0 Then
        omaGUI_NativeWindows.GlobalFree clipboardHandle ' Conditional Win32 import. FB-LINTER: DISABLE-LINE FBL310
        omaGUI_NativeWindows.CloseClipboard()
        Return 0
    End If

    *Cast(ZString Ptr, clipboardMemory) = textValue
    omaGUI_NativeWindows.GlobalUnlock clipboardHandle ' Conditional Win32 import. FB-LINTER: DISABLE-LINE FBL310
    clipboardResult = omaGUI_NativeWindows.SetClipboardData(omaGUI_NativeWindows.TextFormat, clipboardHandle)

    If clipboardResult = 0 Then _
        omaGUI_NativeWindows.GlobalFree clipboardHandle ' Conditional Win32 import. FB-LINTER: DISABLE-LINE FBL310
    omaGUI_NativeWindows.CloseClipboard()

    Return IIf(clipboardResult <> 0, 1, 0)

End Function

#EndIf

' Host bridges keep native FILE opaque and import only their required APIs.
#ifdef OMAGUI_CLIPBOARD_UNIX
Namespace omaGUI_NativeClipboard
Extern "C"
    Declare Function popen(ByVal commandText As Const ZString Ptr, ByVal modeText As Const ZString Ptr) As Any Ptr
    Declare Function pclose(ByVal fileHandle As Any Ptr) As Long
    Declare Function fread(ByVal buffer As Any Ptr, ByVal itemSize As UInteger, ByVal itemCount As UInteger, ByVal fileHandle As Any Ptr) As UInteger
    Declare Function fwrite(ByVal buffer As Const Any Ptr, ByVal itemSize As UInteger, ByVal itemCount As UInteger, ByVal fileHandle As Any Ptr) As UInteger
End Extern
End Namespace

Private Function clipboard_UnixCommandAvailable(ByVal programName As String) As Integer
    ' Names are fixed internal constants, never pasted text.
    Return IIf(Shell("command -v " & programName & " >/dev/null 2>&1") = 0, -1, 0)
End Function

Private Function clipboard_UnixReadCommand(ByVal commandText As String, ByRef resultText As String) As Integer
    Dim As Any Ptr stream = omaGUI_NativeClipboard.popen(StrPtr(commandText), StrPtr("r"))
    If stream = 0 Then Return 0
    resultText = Space(CLIPBOARD_MAX_TEXT_BYTES)
    Dim As UInteger receivedBytes
    While receivedBytes < CLIPBOARD_MAX_TEXT_BYTES
        Dim As UInteger count = omaGUI_NativeClipboard.fread(StrPtr(resultText) + receivedBytes, 1, _
            CLIPBOARD_MAX_TEXT_BYTES - receivedBytes, stream)
        If count = 0 Then Exit While
        receivedBytes += count
    Wend
    ' Closing the read end bounds oversized producers instead of collecting
    ' their entire output. A successful empty clipboard remains an empty string.
    Dim As Long status = omaGUI_NativeClipboard.pclose(stream)
    resultText = Left(resultText, receivedBytes)
    Return IIf(status = 0 OrElse receivedBytes = CLIPBOARD_MAX_TEXT_BYTES, -1, 0)
End Function

Private Function clipboard_UnixWriteCommand(ByVal programName As String, ByVal commandText As String, ByVal textValue As String) As Integer
    If clipboard_UnixCommandAvailable(programName) = 0 Then Return 0
    Dim As Any Ptr stream = omaGUI_NativeClipboard.popen(StrPtr(commandText), StrPtr("w"))
    If stream = 0 Then Return 0
    Dim As UInteger expectedBytes = Len(textValue)
    Dim As UInteger writtenBytes = omaGUI_NativeClipboard.fwrite(StrPtr(textValue), 1, expectedBytes, stream)
    Dim As Long status = omaGUI_NativeClipboard.pclose(stream)
    Return IIf(writtenBytes = expectedBytes AndAlso status = 0, -1, 0)
End Function

Private Function clipboard_UnixGetText() As String
    Dim As String resultText
    If Environ("WAYLAND_DISPLAY") <> "" AndAlso clipboard_UnixCommandAvailable("wl-paste") Then
        If clipboard_UnixReadCommand("wl-paste --no-newline 2>/dev/null", resultText) Then Return resultText
    End If
    If Environ("DISPLAY") <> "" Then
        If clipboard_UnixCommandAvailable("xclip") Then
            If clipboard_UnixReadCommand("xclip -o -selection clipboard 2>/dev/null", resultText) Then Return resultText
        End If
        If clipboard_UnixCommandAvailable("xsel") Then
            If clipboard_UnixReadCommand("xsel --clipboard --output 2>/dev/null", resultText) Then Return resultText
        End If
        If clipboard_UnixCommandAvailable("python3") Then
            If clipboard_UnixReadCommand("python3 -c 'import sys, tkinter as t; r=t.Tk(); r.withdraw(); sys.stdout.write(r.clipboard_get()); r.destroy()' 2>/dev/null", resultText) Then Return resultText
        End If
    End If
    Return clipboard_FallbackText
End Function

Private Function clipboard_UnixStartTkOwner( _
    ByVal textValue As String _
) As Integer

    Dim ownerScript As String
    Dim commandText As String

    If Environ("DISPLAY") = "" Then Return 0
    If clipboard_UnixCommandAvailable("python3") = 0 Then Return 0

    /'
        Tk normally owns the X11 selection from its process. Keep a small
        helper alive to answer later paste requests, then exit after another
        application replaces the clipboard owner.
    '/
    ownerScript = _
        "import sys, tkinter as t" & Chr(10) & _
        "r=t.Tk()" & Chr(10) & _
        "r.withdraw()" & Chr(10) & _
        "payload=sys.stdin.read()" & Chr(10) & _
        "r.clipboard_clear()" & Chr(10) & _
        "r.clipboard_append(payload)" & Chr(10) & _
        "r.update()" & Chr(10) & _
        "def check_owner():" & Chr(10) & _
        "    try:" & Chr(10) & _
        "        if r.selection_own_get(selection=""CLIPBOARD"") != r._w:" & Chr(10) & _
        "            r.destroy()" & Chr(10) & _
        "            return" & Chr(10) & _
        "    except t.TclError:" & Chr(10) & _
        "        r.destroy()" & Chr(10) & _
        "        return" & Chr(10) & _
        "    r.after(500, check_owner)" & Chr(10) & _
        "r.after(500, check_owner)" & Chr(10) & _
        "r.mainloop()"

    /'
        Keep the payload on the pipe rather than embedding it in the shell
        command. The background process owns the selection after this call
        returns and will relinquish it when a new clipboard owner appears.
    '/
    commandText = _
        "python3 -c '" & ownerScript & _
        "' <&0 >/dev/null 2>&1 &"

    Return clipboard_UnixWriteCommand("python3", commandText, textValue)
End Function

Private Sub clipboard_UnixSetText(ByVal textValue As String)
    If Environ("WAYLAND_DISPLAY") <> "" Then
        If clipboard_UnixWriteCommand("wl-copy", "wl-copy 2>/dev/null", textValue) Then Exit Sub
    End If
    If Environ("DISPLAY") <> "" Then
        If clipboard_UnixWriteCommand("xclip", "xclip -selection clipboard 2>/dev/null", textValue) Then Exit Sub
        If clipboard_UnixWriteCommand("xsel", "xsel --clipboard --input 2>/dev/null", textValue) Then Exit Sub
        clipboard_UnixStartTkOwner textValue
    End If
End Sub
#EndIf

' -------------------------------------------------------------------------
' Public clipboard API
' -------------------------------------------------------------------------

Function clipboard_GetText() As String

#If Defined(OMAGUI_CLIPBOARD_WIN32)
    Dim resultText As String

    resultText = clipboard_WindowsGetText()
    Return clipboard_BoundedText(resultText)
#ElseIf Defined(OMAGUI_CLIPBOARD_UNIX)
    Return clipboard_BoundedText(clipboard_UnixGetText())
#Else
    Return clipboard_BoundedText(clipboard_FallbackText)
#EndIf

End Function


Sub clipboard_SetText(ByVal txt As String)

    clipboard_FallbackText = clipboard_BoundedText(txt)

#If Defined(OMAGUI_CLIPBOARD_WIN32)
    clipboard_WindowsSetText clipboard_FallbackText
#ElseIf Defined(OMAGUI_CLIPBOARD_UNIX)
    clipboard_UnixSetText clipboard_FallbackText
#EndIf

End Sub

#If Defined(OMAGUI_CLIPBOARD_WIN32)
    #Undef OMAGUI_CLIPBOARD_WIN32
#EndIf
#ifdef OMAGUI_CLIPBOARD_UNIX
    #Undef OMAGUI_CLIPBOARD_UNIX
#EndIf

' end of clipboard.bas
