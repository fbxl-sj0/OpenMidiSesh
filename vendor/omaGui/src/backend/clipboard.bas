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
        - use xclip only in opted-in supported Unix desktop builds
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
    #Include Once "windows.bi"
#ElseIf Defined(OMAGUI_ENABLE_HOST_CLIPBOARD) AndAlso _
    Not Defined(OMAGUI_DISABLE_HOST_CLIPBOARD) AndAlso _
    Not Defined(OMAGUI_PORTABLE_ONLY) AndAlso _
    (Defined(__FB_LINUX__) Or Defined(__FB_FREEBSD__) Or _
     Defined(__FB_OPENBSD__))
    #Define OMAGUI_CLIPBOARD_XCLIP
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
        If OpenClipboard(0) <> 0 Then Return 1
        Sleep CLIPBOARD_WINDOWS_RETRY_MILLISECONDS, 1
    Next attemptIndex

    Return 0

End Function


Private Function clipboard_WindowsGetText() As String

    Dim byteCount As SIZE_T
    Dim clipboardHandle As HANDLE
    Dim clipboardMemory As Any Ptr
    Dim resultText As String

    If IsClipboardFormatAvailable(CF_TEXT) = 0 Then Return ""
    If clipboard_WindowsOpen() = 0 Then Return ""

    clipboardHandle = GetClipboardData(CF_TEXT)

    If clipboardHandle <> 0 Then
        clipboardMemory = GlobalLock(clipboardHandle)

        If clipboardMemory <> 0 Then
            byteCount = GlobalSize(clipboardHandle)

            If byteCount > 0 Then
                resultText = *Cast(ZString Ptr, clipboardMemory)
                resultText = clipboard_BoundedText(resultText)
            End If

            ' Win32 import exists only inside this backend. FB-LINTER: DISABLE-NEXT-LINE FBL310
            GlobalUnlock clipboardHandle
        End If
    End If

    CloseClipboard()
    Return resultText

End Function


Private Function clipboard_WindowsSetText( _
    ByVal textValue As String _
) As Integer

    Dim allocationFlags As UINT
    Dim clipboardHandle As HANDLE
    Dim clipboardMemory As Any Ptr
    Dim clipboardResult As HANDLE

    If clipboard_WindowsOpen() = 0 Then Return 0

    If EmptyClipboard() = 0 Then
        CloseClipboard()
        Return 0
    End If

    ' Movable ownership is required by SetClipboardData. FB-LINTER: DISABLE-NEXT-LINE FBL310
    allocationFlags = GMEM_MOVEABLE Or GMEM_ZEROINIT
    clipboardHandle = GlobalAlloc(allocationFlags, Len(textValue) + 1)

    If clipboardHandle = 0 Then
        CloseClipboard()
        Return 0
    End If

    clipboardMemory = GlobalLock(clipboardHandle)

    If clipboardMemory = 0 Then
        GlobalFree clipboardHandle ' Conditional Win32 import. FB-LINTER: DISABLE-LINE FBL310
        CloseClipboard()
        Return 0
    End If

    *Cast(ZString Ptr, clipboardMemory) = textValue
    GlobalUnlock clipboardHandle ' Conditional Win32 import. FB-LINTER: DISABLE-LINE FBL310
    clipboardResult = SetClipboardData(CF_TEXT, clipboardHandle)

    If clipboardResult = 0 Then _
        GlobalFree clipboardHandle ' Conditional Win32 import. FB-LINTER: DISABLE-LINE FBL310
    CloseClipboard()

    Return IIf(clipboardResult <> 0, 1, 0)

End Function

#EndIf

' FreeBASIC pipe files let Unix hosts read arbitrary bytes in bounded chunks.
#If Defined(OMAGUI_CLIPBOARD_XCLIP)
Const CLIPBOARD_XCLIP_READ_CHUNK_BYTES As Integer = 4096

Private Function clipboard_XclipGetText() As String
    Dim As Integer fileNumber = FreeFile
    Dim As Integer ioResult
    Dim As Integer bytesRead
    Dim As Integer requestBytes
    Dim As String resultText
    Dim As String chunkText

    If Environ("DISPLAY") = "" Then Return clipboard_FallbackText ' fblint: disable-line FBL750 REASON: An absent DISPLAY uses the in-process clipboard fallback without invoking xclip.
    If Shell("command -v xclip >/dev/null 2>&1") <> 0 Then _
        Return clipboard_FallbackText

    ioResult = Open Pipe( _
        "xclip -o -selection clipboard 2>/dev/null", _
        For Input As #fileNumber _
    )
    If ioResult <> 0 Then Return clipboard_FallbackText
    resultText = Space(CLIPBOARD_MAX_TEXT_BYTES)

    While bytesRead < CLIPBOARD_MAX_TEXT_BYTES
        requestBytes = CLIPBOARD_XCLIP_READ_CHUNK_BYTES
        If requestBytes > CLIPBOARD_MAX_TEXT_BYTES - bytesRead Then _
            requestBytes = CLIPBOARD_MAX_TEXT_BYTES - bytesRead
        chunkText = Input$(requestBytes, #fileNumber)
        If chunkText = "" Then Exit While
        Mid(resultText, bytesRead + 1, Len(chunkText)) = chunkText
        bytesRead += Len(chunkText)
    Wend

    Close #fileNumber
    Return Left(resultText, bytesRead)
End Function

Private Sub clipboard_XclipSetText(ByVal textValue As String)
    Dim As Integer fileNumber = FreeFile
    Dim As Integer ioResult

    If Environ("DISPLAY") = "" Then Exit Sub ' fblint: disable-line FBL750 REASON: An absent DISPLAY uses the in-process clipboard fallback without invoking xclip.
    If Shell("command -v xclip >/dev/null 2>&1") <> 0 Then Exit Sub

    ioResult = Open Pipe( _
        "xclip -selection clipboard 2>/dev/null", _
        For Output As #fileNumber _
    )
    If ioResult <> 0 Then Exit Sub
    If textValue <> "" Then Print #fileNumber, textValue;
    Close #fileNumber
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
#ElseIf Defined(OMAGUI_CLIPBOARD_XCLIP)
    Return clipboard_BoundedText(clipboard_XclipGetText())
#Else
    Return clipboard_BoundedText(clipboard_FallbackText)
#EndIf

End Function


Sub clipboard_SetText(ByVal txt As String)

    clipboard_FallbackText = clipboard_BoundedText(txt)

#If Defined(OMAGUI_CLIPBOARD_WIN32)
    clipboard_WindowsSetText clipboard_FallbackText
#ElseIf Defined(OMAGUI_CLIPBOARD_XCLIP)
    clipboard_XclipSetText clipboard_FallbackText
#EndIf

End Sub

#If Defined(OMAGUI_CLIPBOARD_WIN32)
    #Undef OMAGUI_CLIPBOARD_WIN32
#EndIf
#If Defined(OMAGUI_CLIPBOARD_XCLIP)
    #Undef OMAGUI_CLIPBOARD_XCLIP
#EndIf

' end of clipboard.bas
