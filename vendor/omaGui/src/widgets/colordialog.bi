/'
    Project: omaGUI
    ---------------

    File: colordialog.bi

    Purpose:

        Declare a modal chooser for the classic sixteen-color palette.

    Responsibilities:

        - create an OMAGUI-owned palette dialog
        - expose accept, cancel, and selected-index state
        - provide the canonical classic palette index to RGB mapping

    This file intentionally does NOT contain:

        - application-specific theme mutation
        - operating-system color-dialog calls
        - arbitrary true-color editing
'/

#ifndef __COLORDIALOG_BI__
#define __COLORDIALOG_BI__

#include once "src/widgets/widgets.bi"

Const COLORDIALOG_COLOR_COUNT As Integer = 16

Declare Function colordialog_Create( _
    ByVal widget_name As String, _
    ByVal title_text As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal initial_color_index As Integer = 0 _
) As Widget Ptr
Declare Function colordialog_GetResultState( _
    ByVal dialog_widget As Widget Ptr _
) As Integer
Declare Function colordialog_GetSelectedIndex( _
    ByVal dialog_widget As Widget Ptr _
) As Integer
Declare Function colordialog_GetClassicColor( _
    ByVal color_index As Integer _
) As ULong

#endif

/' end of colordialog.bi '/
