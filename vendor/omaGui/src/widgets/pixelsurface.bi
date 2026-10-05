/'
    Project: omaGUI
    ---------------

    File: pixelsurface.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for pixelsurface.

    Purpose:

        Declare a bounded, retained sparse pixel surface for widgets that
        need redraw-safe application graphics.

    Responsibilities:

        - own explicit pixel colors and their occupancy state
        - preserve the client intersection when a surface is resized
        - expose checked pixel writes, clipped lines/rectangles/circles, reads, clears, and rendering

    This file intentionally does NOT contain:

        - widget construction or resize policy
        - image decoding, platform bitmap handles, or file I/O
        - flood fills, image decoding, or platform drawing calls

    The containing widget owns the surface and calls pixelsurface_Release
    before destruction. Do not copy an initialized surface by value: both
    storage pointers are owned. Calls belong to the graphics-owning GUI thread.
'/

#ifndef __PIXELSURFACE_BI__
#define __PIXELSURFACE_BI__

' Four million sparse pixels use at most 20 MiB across the color and presence
' buffers. The limit also bounds scanline work during a full redraw.
Const PIXELSURFACE_MAX_DIMENSION As Integer = 2048
Const PIXELSURFACE_MAX_PIXELS As ULongInt = 4194304ULL
' A midpoint circle takes one step per radius unit. This cap keeps a malformed
' public call bounded while still covering a canvas many times larger than its
' maximum dimension.
Const PIXELSURFACE_MAX_DRAW_RADIUS As Integer = 65536
' Native CIRCLE angle calculations never need more than about 620,000 samples
' at the supported radius. Keep a small margin while making public arc work
' bounded even if a future caller changes the coordinate limit.
Const PIXELSURFACE_MAX_ARC_STEPS As LongInt = 750000
Const PIXELSURFACE_FULL_CIRCLE As Double = 6.283185307179586

Type GuiPixelSurface
    As ULong Ptr colors
    As UByte Ptr occupied
    As Integer width, height
End Type

Declare Function pixelsurface_Resize( _
    ByRef surface As GuiPixelSurface, ByVal width_value As Integer, _
    ByVal height_value As Integer _
) As Integer
Declare Sub pixelsurface_Release(ByRef surface As GuiPixelSurface)
Declare Sub pixelsurface_Clear(ByRef surface As GuiPixelSurface)
' An off-client write succeeds without retaining a pixel, matching the
' byte-cell surface's clipped-output policy.
Declare Function pixelsurface_SetPixel( _
    ByRef surface As GuiPixelSurface, ByVal x As Integer, ByVal y As Integer, _
    ByVal color_value As ULong _
) As Integer
' The line is clipped to the retained client before Bresenham rasterization.
' A wholly off-client line succeeds without changing the surface.
Declare Function pixelsurface_DrawLine( _
    ByRef surface As GuiPixelSurface, ByVal start_x As Integer, ByVal start_y As Integer, _
    ByVal end_x As Integer, ByVal end_y As Integer, ByVal color_value As ULong _
) As Integer
' Styled lines apply the most-significant bit of the low 16-bit pattern to
' the original starting pixel, then advance one bit for every raster step.
' Clipping retains that phase instead of restarting at the retained canvas.
Declare Function pixelsurface_DrawStyledLine( _
    ByRef surface As GuiPixelSurface, ByVal start_x As Integer, ByVal start_y As Integer, _
    ByVal end_x As Integer, ByVal end_y As Integer, ByVal color_value As ULong, _
    ByVal style_value As ULong _
) As Integer
' Styled outlines follow the installed FreeBASIC LINE ..., B, style perimeter
' order and retain every clipping-phase adjustment. A nonzero filled flag has
' the BF contract: it fills the inclusive rectangle and deliberately ignores
' the style mask.
Declare Function pixelsurface_DrawStyledRectangle( _
    ByRef surface As GuiPixelSurface, ByVal start_x As Integer, _
    ByVal start_y As Integer, ByVal end_x As Integer, ByVal end_y As Integer, _
    ByVal color_value As ULong, ByVal filled As Integer, _
    ByVal style_value As ULong _
) As Integer
' Rectangle endpoints describe opposite inclusive corners. Filled rectangles
' are clipped before rasterization, so their work never exceeds the canvas.
Declare Function pixelsurface_DrawRectangle( _
    ByRef surface As GuiPixelSurface, ByVal start_x As Integer, _
    ByVal start_y As Integer, ByVal end_x As Integer, ByVal end_y As Integer, _
    ByVal color_value As ULong, ByVal filled As Integer _
) As Integer
' The midpoint circle is clipped by its individual retained-pixel writes.
' Negative or excessively large radii fail without modifying the surface.
Declare Function pixelsurface_DrawCircle( _
    ByRef surface As GuiPixelSurface, ByVal center_x As Integer, _
    ByVal center_y As Integer, ByVal radius As Integer, _
    ByVal color_value As ULong _
) As Integer
' Ellipses use the QuickBASIC and FreeBASIC CIRCLE aspect convention: an
' aspect above one narrows X, while one below one narrows Y. Zero selects the
' portable square-pixel default. A full turn may retain an outline or fill;
' partial turns retain an arc and ignore filled, matching gfxlib behavior.
' Negative start/end angles also draw their documented radial center lines.
Declare Function pixelsurface_DrawEllipse( _
    ByRef surface As GuiPixelSurface, ByVal center_x As Integer, _
    ByVal center_y As Integer, ByVal radius As Integer, _
    ByVal aspect_value As Double, ByVal start_angle As Double, _
    ByVal end_angle As Double, ByVal filled As Integer, _
    ByVal color_value As ULong _
) As Integer
' A successful read may report occupied = 0. That distinguishes a blank cell
' from a stored black RGB(0, 0, 0) pixel without reserving any color value.
Declare Function pixelsurface_ReadPixel( _
    ByRef surface As Const GuiPixelSurface, ByVal x As Integer, ByVal y As Integer, _
    ByRef color_value As ULong, ByRef occupied As Integer _
) As Integer
Declare Sub pixelsurface_Render( _
    ByRef surface As Const GuiPixelSurface, ByVal origin_x As Integer, _
    ByVal origin_y As Integer _
)

#endif

/' end of pixelsurface.bi '/
