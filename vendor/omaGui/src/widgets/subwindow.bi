/'
    Project: omaGUI
    ---------------

    File: subwindow.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for subwindow.

    Purpose:
        Declare movable, resizable, ordered, closable child windows.

    Responsibilities:
        - expose subwindow construction and lifecycle operations
        - retain pointer-captured move, resize, and close-button state
        - expose an optional application close callback
        - expose checked title replacement and retrieval
        - retain an optional client-area color
        - retain a title palette independently of menu/selection colors
        - retain portable none, single, sizable-single, and double borders
        - retain normal geometry across minimized and maximized states
        - expose portable control-box, minimize, and maximize title controls
        - retain clipped byte-cell output in the client area

    This file intentionally does NOT contain:
        - window ordering policy
        - child rendering or input clipping policy
        - platform-native window management
'/

#ifndef __SUBWINDOW_BI__
#define __SUBWINDOW_BI__

#include once "src/widgets/widgets.bi"
#include once "src/widgets/textsurface.bi"

Const SUBWINDOW_BORDER_NONE As Integer = 0
Const SUBWINDOW_BORDER_FIXED_SINGLE As Integer = 1
Const SUBWINDOW_BORDER_SIZABLE_SINGLE As Integer = 2
Const SUBWINDOW_BORDER_FIXED_DOUBLE As Integer = 3
Const SUBWINDOW_STATE_NORMAL As Integer = 0
Const SUBWINDOW_STATE_MINIMIZED As Integer = 1
Const SUBWINDOW_STATE_MAXIMIZED As Integer = 2

Type SubWindowData
    As String title
    As Integer dragging
    As Integer drag_off_x, drag_off_y
    As Integer resizing
    As Integer resize_start_x, resize_start_y
    As Integer resize_start_w, resize_start_h
    As Integer closable
    As Integer close_requested
    As Integer close_latch
    As Integer minimize_button
    As Integer minimize_latch
    As Integer maximize_button
    As Integer maximize_latch
    As Any Ptr close_handler
    As Integer client_color_override
    As ULong client_color
    As Integer border_style
    As Integer title_color_override
    As ULong title_background, title_foreground
    As Integer window_state
    As Integer restore_valid
    As Integer restore_x, restore_y, restore_w, restore_h
    As Integer move_parent
    As Integer titlebar_height, title_text_inset, title_text_y_offset
    ' A window owns its retained client text; callers own cursor semantics.
    As GuiTextSurface text_surface
    As Integer text_columns, text_rows, text_cell_width, text_cell_height
    As Integer text_inset_x, text_inset_y
    ' Owned palette remains valid for the lifetime of this window.
    As GUI_Theme appearance
End Type

Declare Function subwindow_Create( _
    ByVal nm As String, ByVal title As String, _ ' fblint: disable-line FBL-API-001 -- Widget identity precedes its displayed caption.
    ByVal x As Integer, ByVal y As Integer, _ ' fblint: disable-line FBL-API-001 -- Coordinates, extents and creation options retain the public API order.
    ByVal w As Integer, ByVal h As Integer, _ ' fblint: disable-line FBL-API-001 -- Coordinates, extents and creation options retain the public API order.
    ByVal closable As Integer = -1 _
) As Widget Ptr
Declare Sub subwindow_SetCloseHandler( _
    ByVal w As Widget Ptr, ByVal closeHandler As Any Ptr _
)
Declare Function subwindow_SetTitle( _
    ByVal w As Widget Ptr, ByRef title_text As Const String _
) As Integer
Declare Function subwindow_GetTitle(ByVal w As Widget Ptr) As String
Declare Sub subwindow_SetClosable( _
    ByVal w As Widget Ptr, ByVal closable As Integer _
)
Declare Sub subwindow_SetDialogStyle(ByVal w As Widget Ptr)
Declare Sub subwindow_SetTitleBar(ByVal w As Widget Ptr, ByVal height As Integer, ByVal textInset As Integer = 5) ' fblint: disable-line FBL-API-001 -- Title height precedes its text inset.
Declare Function subwindow_SetTitleTextYOffset( _
    ByVal w As Widget Ptr, ByVal offsetPixels As Integer _
) As Integer
Declare Sub subwindow_SetTheme(ByVal w As Widget Ptr, ByRef appearance As GUI_Theme)
Declare Sub subwindow_SetMoveParent(ByVal w As Widget Ptr, ByVal moveParent As Integer)
Declare Sub subwindow_CancelInput(ByVal w As Widget Ptr)
Declare Function subwindow_SetControlBox( _
    ByVal w As Widget Ptr, ByVal enabled As Integer _
) As Integer
Declare Function subwindow_GetControlBox( _
    ByVal w As Widget Ptr, ByRef enabled As Integer _
) As Integer
Declare Function subwindow_SetMinButton( _
    ByVal w As Widget Ptr, ByVal enabled As Integer _
) As Integer
Declare Function subwindow_GetMinButton( _
    ByVal w As Widget Ptr, ByRef enabled As Integer _
) As Integer
Declare Function subwindow_SetMaxButton( _
    ByVal w As Widget Ptr, ByVal enabled As Integer _
) As Integer
Declare Function subwindow_GetMaxButton( _
    ByVal w As Widget Ptr, ByRef enabled As Integer _
) As Integer
Declare Function subwindow_CloseRequested(ByVal w As Widget Ptr) As Integer
Declare Sub subwindow_Reopen(ByVal w As Widget Ptr)
Declare Function subwindow_SetTextGrid( _
    ByVal w As Widget Ptr, ByVal columns As Integer, ByVal rows As Integer, _
    ByVal cell_width As Integer, ByVal cell_height As Integer, _
    ByVal inset_x As Integer = 0, ByVal inset_y As Integer = 0 _
) As Integer
Declare Function subwindow_WriteTextByte( _
    ByVal w As Widget Ptr, ByVal column As Integer, ByVal row As Integer, _
    ByVal character_code As Integer, ByVal foreground_color As ULong, _
    ByVal background_color As ULong _
) As Integer
Declare Function subwindow_ReadTextCell( _
    ByVal w As Widget Ptr, ByVal column As Integer, ByVal row As Integer, _
    ByRef cell As GuiTextCell _
) As Integer
Declare Sub subwindow_ClearText(ByVal w As Widget Ptr)
Declare Function subwindow_SetClientColor( _
    ByVal w As Widget Ptr, _
    ByVal color_value As ULong _
) As Integer
Declare Function subwindow_ClearClientColor(ByVal w As Widget Ptr) As Integer
Declare Function subwindow_GetClientColor( _
    ByVal w As Widget Ptr, _
    ByRef color_value As ULong _
) As Integer
Declare Function subwindow_SetBorderStyle( _
    ByVal w As Widget Ptr, _
    ByVal border_style As Integer _
) As Integer
Declare Function subwindow_GetBorderStyle( _
    ByVal w As Widget Ptr, _
    ByRef border_style As Integer _
) As Integer
Declare Function subwindow_GetClientTopInset(ByVal w As Widget Ptr) As Integer
Declare Function subwindow_IsResizing(ByVal w As Widget Ptr) As Integer
Declare Function subwindow_SetWindowState( _
    ByVal w As Widget Ptr, ByVal window_state As Integer _
) As Integer
Declare Function subwindow_GetWindowState( _
    ByVal w As Widget Ptr, ByRef window_state As Integer _
) As Integer
Declare Function subwindow_SetTitleColors( _
    ByVal w As Widget Ptr, ByVal background_color As ULong, ByVal foreground_color As ULong _ ' fblint: disable-line FBL-API-001 -- Color roles retain the published drawing/widget order.
) As Integer
Declare Function subwindow_ClearTitleColors(ByVal w As Widget Ptr) As Integer
Declare Function subwindow_GetTitleColors( _
    ByVal w As Widget Ptr, ByRef background_color As ULong, ByRef foreground_color As ULong _ ' fblint: disable-line FBL-API-001 -- Color roles retain the published drawing/widget order.
) As Integer
Declare Sub subwindow_Render(ByVal w As Widget Ptr)
Declare Sub subwindow_Update(ByVal w As Widget Ptr)
Declare Sub subwindow_Destroy(ByVal w As Widget Ptr)

#endif

/' end of subwindow.bi '/
