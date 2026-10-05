/'
    Project: omaGUI
    File: textsurface.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for textsurface.
    Purpose: Declare a bounded, retained byte-cell drawing surface.
    Responsibilities: Own cells independently of a widget's caption and layout.

    This file intentionally does NOT contain:

        - BASIC PRINT parsing, cursor policy,
        input dispatch, or automatic repaint/lifetime policy.

    The containing widget owns the surface and calls textsurface_Release before
    destruction. Do not copy an initialized surface by value: cells is owned.
    All operations belong to the GUI thread. Resizing preserves only the old
    and new client intersection; writes outside the current grid are clipped.
'/
#ifndef __TEXTSURFACE_BI__
#define __TEXTSURFACE_BI__

' 255 by 255 bounds storage below 1 MiB even with aligned color-bearing cells.
Const TEXTSURFACE_MAX_DIMENSION As Integer = 255

Type GuiTextCell
    As ULong foreground_color, background_color
    As UByte character_code, occupied
End Type

Type GuiTextSurface
    As GuiTextCell Ptr cells
    As Integer columns, rows
End Type

Declare Function textsurface_Resize(ByRef surface As GuiTextSurface, ByVal columns As Integer, ByVal rows As Integer) As Integer
Declare Sub textsurface_Release(ByRef surface As GuiTextSurface)
Declare Sub textsurface_Clear(ByRef surface As GuiTextSurface)
Declare Function textsurface_WriteByte( _
    ByRef surface As GuiTextSurface, ByVal column As Integer, ByVal row As Integer, _
    ByVal character_code As Integer, ByVal foreground_color As ULong, ByVal background_color As ULong _
) As Integer
Declare Function textsurface_ReadCell( _
    ByRef surface As Const GuiTextSurface, ByVal column As Integer, ByVal row As Integer, ByRef cell As GuiTextCell _
) As Integer
Declare Sub textsurface_Render( _
    ByRef surface As Const GuiTextSurface, ByVal origin_x As Integer, ByVal origin_y As Integer, _
    ByVal cell_width As Integer, ByVal cell_height As Integer _
)

#endif
/' end of textsurface.bi '/
