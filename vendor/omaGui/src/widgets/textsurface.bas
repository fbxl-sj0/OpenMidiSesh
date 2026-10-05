/'
    Project: omaGUI
    File: textsurface.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements textsurface.bi; declarations there define the interface.
    Purpose: Retain and render bounded, individually colored byte cells.
    Responsibilities: Transactional allocation, clipped writes, and cell redraw.

    This file intentionally does NOT contain:

        - widget creation, input, or PRINT
        formatting. The caller owns layout and cursor advancement.

    Ownership and threading: each surface owns one zeroed byte allocation;
    release pairs it with Deallocate. Calls are synchronous on the graphics-owning thread.
    Cell storage is independent of gfxlib screen mode, so screen handoff cannot
    invalidate it. Only successfully allocated grids replace existing storage.
'/
#lang "fb"
#include once "src/widgets/textsurface.bi"
#include once "src/backend/backend.bi"

' -------------------------------------------------------------------------
' Storage and checked cell access
' -------------------------------------------------------------------------

Sub textsurface_Release(ByRef surface As GuiTextSurface)
    If surface.cells <> 0 Then Deallocate surface.cells
    surface.cells = 0
    surface.columns = 0
    surface.rows = 0
End Sub

Function textsurface_Resize(ByRef surface As GuiTextSurface, ByVal columns As Integer, ByVal rows As Integer) As Integer
    If columns < 0 OrElse rows < 0 OrElse columns > TEXTSURFACE_MAX_DIMENSION OrElse rows > TEXTSURFACE_MAX_DIMENSION Then Return 0
    If columns = 0 OrElse rows = 0 Then
        textsurface_Release surface
        Return -1
    End If
    If columns = surface.columns AndAlso rows = surface.rows Then Return -1
    Dim As ULongInt allocation_bytes = _
        CULngInt(columns) * CULngInt(rows) * SizeOf(GuiTextCell)
    Dim As GuiTextCell Ptr new_cells = Callocate(CUInt(allocation_bytes))
    If new_cells = 0 Then Return 0
    If surface.cells <> 0 Then
        Dim As Integer kept_columns = IIf(columns < surface.columns, columns, surface.columns)
        Dim As Integer kept_rows = IIf(rows < surface.rows, rows, surface.rows)
        For row As Integer = 0 To kept_rows - 1
            For column As Integer = 0 To kept_columns - 1
                ' Both indices lie in the checked old/new grid intersection.
                ' fblint: disable-next-line FBL525
                new_cells[row * columns + column] = surface.cells[row * surface.columns + column]
            Next column
        Next row
        Deallocate surface.cells
    End If
    surface.cells = new_cells
    surface.columns = columns
    surface.rows = rows
    Return -1
End Function

Sub textsurface_Clear(ByRef surface As GuiTextSurface)
    If surface.cells = 0 Then Exit Sub
    For cell_index As Integer = 0 To surface.columns * surface.rows - 1
        surface.cells[cell_index].occupied = 0
    Next cell_index
End Sub

Function textsurface_WriteByte( _
    ByRef surface As GuiTextSurface, ByVal column As Integer, ByVal row As Integer, _
    ByVal character_code As Integer, ByVal foreground_color As ULong, ByVal background_color As ULong _
) As Integer
    If character_code < 0 OrElse character_code > 255 Then Return 0
    ' Off-client output is deliberately discarded, not retained for a resize.
    If column < 0 OrElse row < 0 OrElse column >= surface.columns OrElse row >= surface.rows Then Return -1
    If surface.cells = 0 Then Return 0
    With surface.cells[row * surface.columns + column]
        .character_code = character_code
        .foreground_color = foreground_color
        .background_color = background_color
        .occupied = 1
    End With
    Return -1
End Function

Function textsurface_ReadCell( _
    ByRef surface As Const GuiTextSurface, ByVal column As Integer, ByVal row As Integer, ByRef cell As GuiTextCell _
) As Integer
    If surface.cells = 0 OrElse column < 0 OrElse row < 0 OrElse column >= surface.columns OrElse row >= surface.rows Then Return 0
    cell = surface.cells[row * surface.columns + column]
    Return -1
End Function

' -------------------------------------------------------------------------
' Rendering
' -------------------------------------------------------------------------

Sub textsurface_Render( _
    ByRef surface As Const GuiTextSurface, ByVal origin_x As Integer, ByVal origin_y As Integer, _
    ByVal cell_width As Integer, ByVal cell_height As Integer _
)
    If surface.cells = 0 OrElse cell_width < 1 OrElse cell_height < 1 OrElse cell_width > 256 OrElse cell_height > 256 Then Exit Sub
    ' The supported grid extent is at most 65,280 pixels. Keep additions safe
    ' even when a caller supplies an unreasonable off-screen origin.
    If origin_x < -1000000 OrElse origin_x > 1000000 OrElse origin_y < -1000000 OrElse origin_y > 1000000 Then Exit Sub
    Dim As Integer clip_x, clip_y, clip_width, clip_height
    backend_GetClip clip_x, clip_y, clip_width, clip_height
    If clip_width <= 0 OrElse clip_height <= 0 Then Exit Sub
    For row As Integer = 0 To surface.rows - 1
        For column As Integer = 0 To surface.columns - 1
            ' Resize owns exactly rows * columns cells; no mutation runs while rendering.
            Dim As GuiTextCell Ptr cell = _
                surface.cells + row * surface.columns + column
            If cell->occupied = 0 Then Continue For
            Dim As Integer cell_x = origin_x + column * cell_width
            Dim As Integer cell_y = origin_y + row * cell_height
            If cell_x >= clip_x + clip_width OrElse cell_y >= clip_y + clip_height OrElse _
               cell_x + cell_width <= clip_x OrElse cell_y + cell_height <= clip_y Then Continue For
            backend_SetClip cell_x, cell_y, cell_width, cell_height
            backend_Rect cell_x, cell_y, cell_width, cell_height, cell->background_color, -1
            backend_PrintByte cell_x, cell_y, cell->foreground_color, cell->character_code
            backend_ResetClip
        Next column
    Next row
End Sub

/' end of textsurface.bas '/
