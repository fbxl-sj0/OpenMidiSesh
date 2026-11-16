/'
    Project: omaGUI
    ---------------

    File: clipboard.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for clipboard.

    Purpose:

        Declare the bounded cross-platform clipboard used by editable widgets.

    Responsibilities:

        - expose clipboard text reads and writes
        - allow callers to select host or process-local clipboard access
        - define the maximum accepted clipboard payload
        - expose the host-clipboard policy switch

    This file intentionally does NOT contain:

        - platform backend implementation
        - textbox selection rules
        - rich-text or image clipboard formats
'/

#ifndef __CLIPBOARD_BI__
#define __CLIPBOARD_BI__

Const CLIPBOARD_MAX_TEXT_BYTES As Integer = 2097152

' Browser reads must complete before the caller uses clipboard_GetText.
Const CLIPBOARD_READ_FAILED As Integer = -1
Const CLIPBOARD_READ_PENDING As Integer = 0
Const CLIPBOARD_READ_READY As Integer = 1

#If Defined(__FB_JS__) AndAlso Defined(OMAGUI_ENABLE_HOST_CLIPBOARD) AndAlso _
    Not Defined(OMAGUI_DISABLE_HOST_CLIPBOARD)
    #Define OMAGUI_CLIPBOARD_BROWSER
#EndIf

Declare Function clipboard_GetText() As String
Declare Sub clipboard_SetText(ByVal txt As String)
Declare Sub clipboard_Initialize()
Declare Function clipboard_RequestText() As Integer
Declare Function clipboard_PollText() As Integer
Declare Sub clipboard_CancelRead()
' Retire application data without modifying the user's host clipboard.
Declare Sub clipboard_ClearLocal()

/'
    Host-aware applications can disable desktop access temporarily while
    preserving the same process-local clipboard used by scripted runs.
'/
Declare Sub clipboard_SetHostEnabled(ByVal enabled As Integer)
Declare Sub clipboard_SetHostClipboardEnabled(ByVal enabled As Integer)

#endif
' end of clipboard.bi
