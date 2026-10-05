/'
    Project: omaGUI
    ---------------

    File: statusbar.bi

    Purpose:

        Declare a portable Windows-style status bar with bounded panels.

    Responsibilities:

        - retain fixed-width and flexible text panels
        - expose checked panel construction, text updates, and alignment
        - provide a noninteractive widget lifecycle

    This file intentionally does NOT contain:

        - application status policy
        - pointer or keyboard input
        - platform-native status-bar declarations
'/

#ifndef __STATUSBAR_BI__
#define __STATUSBAR_BI__

#include once "src/widgets/widgets.bi"

Const STATUSBAR_MAX_PANELS As Integer = 8
Const STATUSBAR_MAX_TEXT_BYTES As Integer = 512

Type StatusBarData
    As String panel_text(0 To STATUSBAR_MAX_PANELS - 1)
    As Integer panel_width(0 To STATUSBAR_MAX_PANELS - 1)
    As Integer panel_alignment(0 To STATUSBAR_MAX_PANELS - 1)
    As Integer panel_count
End Type

Declare Function statusbar_Create( _
    ByVal widget_name As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal bar_width As Integer, _
    ByVal bar_height As Integer = 24 _
) As Widget Ptr
Declare Function statusbar_AddPanel( _
    ByVal bar_widget As Widget Ptr, _
    ByVal panel_text As String, _
    ByVal panel_width As Integer = 0 _
) As Integer
Declare Function statusbar_SetPanelText( _
    ByVal bar_widget As Widget Ptr, _
    ByVal panel_index As Integer, _
    ByVal panel_text As String _
) As Integer
Declare Function statusbar_SetPanelAlignment( _
    ByVal bar_widget As Widget Ptr, _
    ByVal panel_index As Integer, _
    ByVal horizontal_alignment As Integer _
) As Integer
Declare Function statusbar_GetPanelText( _
    ByVal bar_widget As Widget Ptr, _
    ByVal panel_index As Integer _
) As String
Declare Function statusbar_GetPanelAlignment( _
    ByVal bar_widget As Widget Ptr, _
    ByVal panel_index As Integer _
) As Integer
Declare Function statusbar_GetPanelCount( _
    ByVal bar_widget As Widget Ptr _
) As Integer
Declare Sub statusbar_Render(ByVal bar_widget As Widget Ptr)
Declare Sub statusbar_Destroy(ByVal bar_widget As Widget Ptr)

#endif

/' end of statusbar.bi '/
