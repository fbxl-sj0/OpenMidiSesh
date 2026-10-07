/'
    Project: omaGUI
    ---------------

    File: picturebox.bi

    Purpose:

        Declare a framed display surface compatible with classic PictureBox
        controls.

    Responsibilities:

        - retain optional display text
        - own a copied raster image beneath retained drawings and text
        - own separate, lazily allocated byte-cell and pixel drawing surfaces
        - retain optional caller-supplied client and text colors
        - expose flat, single-line, and sunken border styles
        - provide a clipped client area for child widgets

    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Declarations for the picturebox component in the omaGUI include graph.

    This file intentionally does NOT contain:

        - bitmap decoding or drawing algorithms
        - application-specific drawing callbacks
        - pointer or keyboard behavior
'/

#ifndef __PICTUREBOX_BI__
#define __PICTUREBOX_BI__

#include once "src/widgets/widgets.bi"
#include once "src/widgets/textsurface.bi"
#include once "src/widgets/pixelsurface.bi"
#include once "src/images/raster_image.bi"

Const PICTUREBOX_BORDER_NONE As Integer = 0
Const PICTUREBOX_BORDER_SINGLE As Integer = 1
Const PICTUREBOX_BORDER_SUNKEN As Integer = 2
' Keep this distinct from SUNKEN for VBDOS Double Line controls.
Const PICTUREBOX_BORDER_DOUBLE As Integer = 3

Type PictureBoxData
    As String text
    As Integer border_style
    As Integer background_color_override
    As ULong background_color
    As Integer foreground_color_override
    As ULong foreground_color
    As GuiTextSurface print_surface
    As Integer print_columns, print_rows, print_cell_width, print_cell_height
    As Integer print_inset_x, print_inset_y
    As GuiPixelSurface pixel_surface
    As Integer pixel_width, pixel_height, pixel_inset_x, pixel_inset_y
    As Integer pixel_tracks_client
    ' Owned copy, drawn below retained pixels and text on the GUI thread.
    As RasterImage Ptr display_image
End Type

' Copy decoded pixels; the caller keeps ownership and may release its image
' immediately. Null clears the image. Failed replacement preserves the old
' image. Drawings and the widget rectangle are unaffected by assignment.
Declare Function picturebox_SetImage( _
    ByVal picture_widget As Widget Ptr, ByVal source_image As RasterImage Ptr _
) As Integer

' Configuring the print client does not allocate until an in-client byte is
' written. Caption changes never clear these cells. The caller owns cursor and
' repaint policy; rows/columns are bounded by TEXTSURFACE_MAX_DIMENSION.
Declare Function picturebox_SetPrintGrid( _
    ByVal picture_widget As Widget Ptr, ByVal columns As Integer, ByVal rows As Integer, _
    ByVal cell_width As Integer, ByVal cell_height As Integer, ByVal inset_x As Integer = 0, ByVal inset_y As Integer = 0 _
) As Integer
Declare Function picturebox_WriteByte(ByVal picture_widget As Widget Ptr, ByVal column As Integer, ByVal row As Integer, ByVal character_code As Integer) As Integer
Declare Sub picturebox_ClearPrint(ByVal picture_widget As Widget Ptr)
Declare Function picturebox_ReadPrintCell(ByVal picture_widget As Widget Ptr, ByVal column As Integer, ByVal row As Integer, ByRef cell As GuiTextCell) As Integer

' The fixed canvas remains at the selected logical size and is clipped to the
' PictureBox client. The client canvas follows later widget resizes, preserving
' the retained old/new intersection. Neither call allocates until SetPixel.
Declare Function picturebox_SetPixelCanvas( _
    ByVal picture_widget As Widget Ptr, ByVal width_value As Integer, _
    ByVal height_value As Integer, ByVal inset_x As Integer = 0, _
    ByVal inset_y As Integer = 0 _
) As Integer
Declare Function picturebox_SetPixelCanvasToClient( _
    ByVal picture_widget As Widget Ptr, ByVal inset_x As Integer = 0, _
    ByVal inset_y As Integer = 0 _
) As Integer
' SetPixel accepts an explicit ULong color. Out-of-canvas coordinates are
' clipped successfully; allocation failure is the only failure result.
Declare Function picturebox_SetPixel( _
    ByVal picture_widget As Widget Ptr, ByVal x As Integer, ByVal y As Integer, _
    ByVal color_value As ULong _
) As Integer
' Lines retain their clipped client pixels, so a later desktop redraw does
' not depend on a platform graphics context remaining alive.
Declare Function picturebox_DrawLine( _
    ByVal picture_widget As Widget Ptr, ByVal start_x As Integer, ByVal start_y As Integer, _
    ByVal end_x As Integer, ByVal end_y As Integer, ByVal color_value As ULong _
) As Integer
' Styled lines retain their 16-bit bitmask phase through clipping and redraw.
Declare Function picturebox_DrawStyledLine( _
    ByVal picture_widget As Widget Ptr, ByVal start_x As Integer, ByVal start_y As Integer, _
    ByVal end_x As Integer, ByVal end_y As Integer, ByVal color_value As ULong, _
    ByVal style_value As ULong _
) As Integer
' Styled rectangles retain native FreeBASIC B/BF style behavior. BF fills the
' client rectangle and ignores its style mask, matching gfxlib semantics.
Declare Function picturebox_DrawStyledRectangle( _
    ByVal picture_widget As Widget Ptr, ByVal start_x As Integer, _
    ByVal start_y As Integer, ByVal end_x As Integer, ByVal end_y As Integer, _
    ByVal color_value As ULong, ByVal filled As Integer, _
    ByVal style_value As ULong _
) As Integer
' Rectangle endpoints remain physical client pixels. A nonzero filled flag
' selects clipped fill; zero retains only the four inclusive edges.
Declare Function picturebox_DrawRectangle( _
    ByVal picture_widget As Widget Ptr, ByVal start_x As Integer, _
    ByVal start_y As Integer, ByVal end_x As Integer, ByVal end_y As Integer, _
    ByVal color_value As ULong, ByVal filled As Integer _
) As Integer
' Circles use the same retained client canvas and clipped redraw contract as
' lines. The radius is a physical client-pixel distance.
Declare Function picturebox_DrawCircle( _
    ByVal picture_widget As Widget Ptr, ByVal center_x As Integer, _
    ByVal center_y As Integer, ByVal radius As Integer, _
    ByVal color_value As ULong _
) As Integer
' Retain a QuickBASIC-compatible ellipse or arc on the PictureBox client
' canvas. See pixelsurface_DrawEllipse for aspect, fill, and negative-angle
' radial-line semantics.
Declare Function picturebox_DrawEllipse( _
    ByVal picture_widget As Widget Ptr, ByVal center_x As Integer, _
    ByVal center_y As Integer, ByVal radius As Integer, _
    ByVal aspect_value As Double, ByVal start_angle As Double, _
    ByVal end_angle As Double, ByVal filled As Integer, _
    ByVal color_value As ULong _
) As Integer
Declare Function picturebox_ReadPixel( _
    ByVal picture_widget As Widget Ptr, ByVal x As Integer, ByVal y As Integer, _
    ByRef color_value As ULong, ByRef occupied As Integer _
) As Integer
Declare Sub picturebox_ClearPixels(ByVal picture_widget As Widget Ptr)

Declare Function picturebox_Create( _
    ByVal widget_name As String, _
    ByVal display_text As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal picture_width As Integer, _
    ByVal picture_height As Integer, _
    ByVal border_style As Integer = PICTUREBOX_BORDER_SUNKEN _
) As Widget Ptr
Declare Sub picturebox_Render(ByVal picture_widget As Widget Ptr)
Declare Sub picturebox_Destroy(ByVal picture_widget As Widget Ptr)
Declare Function picturebox_SetText( _
    ByVal picture_widget As Widget Ptr, _
    ByRef display_text As Const String _
) As Integer
Declare Function picturebox_SetBorderStyle( _
    ByVal picture_widget As Widget Ptr, _
    ByVal border_style As Integer _
) As Integer
Declare Function picturebox_SetBackgroundColor( _
    ByVal picture_widget As Widget Ptr, _
    ByVal background_color As ULong _
) As Integer
Declare Function picturebox_ClearBackgroundColor( _
    ByVal picture_widget As Widget Ptr _
) As Integer
Declare Function picturebox_GetBackgroundColor( _
    ByVal picture_widget As Widget Ptr, _
    ByRef background_color As ULong _
) As Integer
Declare Function picturebox_SetForegroundColor( _
    ByVal picture_widget As Widget Ptr, _
    ByVal foreground_color As ULong _
) As Integer
Declare Function picturebox_ClearForegroundColor( _
    ByVal picture_widget As Widget Ptr _
) As Integer
Declare Function picturebox_GetForegroundColor( _
    ByVal picture_widget As Widget Ptr, _
    ByRef foreground_color As ULong _
) As Integer

#endif

/' end of picturebox.bi '/
