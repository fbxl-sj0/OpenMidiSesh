/'
    Project: omaGUI
    ---------------

    File: inputdialog.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for inputdialog.

    Purpose:

        Declare a modal two-field text prompt with optional boolean choices.

    Responsibilities:

        - create one or two labeled text inputs in a modal window
        - optionally expose three checkbox choices and an alternate action
        - apply caller-selected portable foreground and background colors
        - return accepted text, option, alternate-action, or cancellation state

    This file intentionally does NOT contain:

        - application validation or side effects
        - native operating-system dialog calls
        - unbounded dynamic field construction
'/

#ifndef __INPUTDIALOG_BI__
#define __INPUTDIALOG_BI__

#include once "src/widgets/widgets.bi"

Const INPUTDIALOG_FIELD_COUNT As Integer = 2
Const INPUTDIALOG_OPTION_COUNT As Integer = 3

Declare Function inputdialog_Create( _
    ByVal widget_name As String, _
    ByVal title_text As String, _
    ByVal first_prompt As String, _
    ByVal first_value As String, _
    ByVal second_prompt As String, _
    ByVal second_value As String, _
    ByVal first_option As String, _
    ByVal first_option_checked As Integer, _
    ByVal second_option As String, _
    ByVal second_option_checked As Integer, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal accept_text As String = "OK", _
    ByVal third_option As String = "", _
    ByVal third_option_checked As Integer = 0, _
    ByVal alternate_text As String = "" _
) As Widget Ptr
' Result state is 0 while pending, 1 for accept, 2 for the alternate action,
' and -1 for Cancel or closing the dialog window.
Declare Function inputdialog_GetResultState( _
    ByVal dialog_widget As Widget Ptr _
) As Integer
Declare Function inputdialog_GetText( _
    ByVal dialog_widget As Widget Ptr, _
    ByVal field_index As Integer _
) As String
Declare Function inputdialog_GetOption( _
    ByVal dialog_widget As Widget Ptr, _
    ByVal option_index As Integer _
) As Integer
Declare Function inputdialog_SetColors( _
    ByVal dialog_widget As Widget Ptr, _
    ByVal foreground_color As ULong, _
    ByVal background_color As ULong _
) As Integer

#endif

/' end of inputdialog.bi '/
