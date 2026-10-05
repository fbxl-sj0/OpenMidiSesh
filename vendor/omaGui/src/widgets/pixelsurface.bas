/'
    Project: omaGUI
    ---------------

    File: pixelsurface.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements pixelsurface.bi; declarations there define the interface.

    Purpose:

        Retain and redraw a bounded pixel surface without depending on
        a host bitmap or a platform graphics API.

    Responsibilities:

        - allocate color and presence buffers transactionally
        - preserve a checked resize intersection
        - retain explicit RGB or RGBA color values, including black
        - clip ordinary and 16-bit patterned line and rectangle rasterization
        - redraw contiguous same-color runs through the portable backend

    This file intentionally does NOT contain:

        - widget ownership, input handling, or automatic layout decisions
        - image decoding, screen-mode management, or file persistence
        - unbounded raster drawing algorithms

    Ownership and threading:

        Each surface owns two zeroed allocations. Release pairs both with
        Deallocate. Operations are synchronous on the graphics-owning GUI
        thread, so resize never races rendering or a pixel write.
'/

#lang "fb"

#include once "src/widgets/pixelsurface.bi"
#include once "src/backend/backend.bi"

' -------------------------------------------------------------------------
' Storage and checked pixel access
' -------------------------------------------------------------------------

Private Function pixelsurface_IsValidSize( _
    ByVal width_value As Integer, ByVal height_value As Integer _
) As Integer
    Dim As ULongInt pixel_count

    If width_value < 0 OrElse height_value < 0 OrElse _
       width_value > PIXELSURFACE_MAX_DIMENSION OrElse _
       height_value > PIXELSURFACE_MAX_DIMENSION Then Return 0
    pixel_count = CULngInt(width_value) * CULngInt(height_value)
    If pixel_count > PIXELSURFACE_MAX_PIXELS Then Return 0
    Return -1
End Function


Sub pixelsurface_Release(ByRef surface As GuiPixelSurface)
    If surface.colors <> 0 Then Deallocate surface.colors
    If surface.occupied <> 0 Then Deallocate surface.occupied
    surface.colors = 0
    surface.occupied = 0
    surface.width = 0
    surface.height = 0
End Sub


Function pixelsurface_Resize( _
    ByRef surface As GuiPixelSurface, ByVal width_value As Integer, _
    ByVal height_value As Integer _
) As Integer
    Dim As ULongInt pixel_count
    Dim As ULong Ptr new_colors
    Dim As UByte Ptr new_occupied
    Dim As Integer kept_width
    Dim As Integer kept_height

    If pixelsurface_IsValidSize(width_value, height_value) = 0 Then Return 0
    If width_value = 0 OrElse height_value = 0 Then
        pixelsurface_Release surface
        Return -1
    End If
    If width_value = surface.width AndAlso height_value = surface.height AndAlso _
       surface.colors <> 0 AndAlso surface.occupied <> 0 Then Return -1

    pixel_count = CULngInt(width_value) * CULngInt(height_value)
    new_colors = Callocate(CUInt(pixel_count * SizeOf(ULong)))
    If new_colors = 0 Then Return 0
    new_occupied = Callocate(CUInt(pixel_count))
    If new_occupied = 0 Then
        Deallocate new_colors
        Return 0
    End If

    If surface.colors <> 0 AndAlso surface.occupied <> 0 AndAlso _
       surface.width > 0 AndAlso surface.height > 0 Then
        kept_width = IIf(width_value < surface.width, width_value, surface.width)
        kept_height = IIf(height_value < surface.height, height_value, surface.height)
        For row_index As Integer = 0 To kept_height - 1
            For column_index As Integer = 0 To kept_width - 1
                Dim As ULongInt new_index = CULngInt(row_index) * width_value + column_index
                Dim As ULongInt old_index = CULngInt(row_index) * surface.width + column_index
                ' Both offsets lie inside their checked resize intersection.
                ' fblint: disable-next-line FBL525
                new_colors[new_index] = surface.colors[old_index]
                ' fblint: disable-next-line FBL525
                new_occupied[new_index] = surface.occupied[old_index]
            Next column_index
        Next row_index
    End If

    If surface.colors <> 0 Then Deallocate surface.colors
    If surface.occupied <> 0 Then Deallocate surface.occupied
    surface.colors = new_colors
    surface.occupied = new_occupied
    surface.width = width_value
    surface.height = height_value
    Return -1
End Function


Sub pixelsurface_Clear(ByRef surface As GuiPixelSurface)
    Dim As ULongInt pixel_count

    If surface.occupied = 0 OrElse surface.width < 1 OrElse _
       surface.height < 1 Then Exit Sub
    pixel_count = CULngInt(surface.width) * CULngInt(surface.height)
    For pixel_index As ULongInt = 0 To pixel_count - 1
        surface.occupied[pixel_index] = 0
    Next pixel_index
End Sub


Function pixelsurface_SetPixel( _
    ByRef surface As GuiPixelSurface, ByVal x As Integer, ByVal y As Integer, _
    ByVal color_value As ULong _
) As Integer
    Dim As ULongInt pixel_index

    ' Off-client output is deliberately not retained for a later expansion.
    If x < 0 OrElse y < 0 OrElse x >= surface.width OrElse y >= surface.height Then Return -1
    If surface.colors = 0 OrElse surface.occupied = 0 Then Return 0
    pixel_index = CULngInt(y) * surface.width + x
    surface.colors[pixel_index] = color_value
    surface.occupied[pixel_index] = 1
    Return -1
End Function


' -------------------------------------------------------------------------
' Clipped line rasterization
' -------------------------------------------------------------------------

Private Function pixelsurface_LineOutCode( _
    ByVal pixel_x As Double, ByVal pixel_y As Double, _
    ByVal surface_width As Integer, ByVal surface_height As Integer _
) As Integer
    Dim As Integer result_code

    If pixel_x < 0 Then
        result_code Or= 1
    ElseIf pixel_x > surface_width - 1 Then
        result_code Or= 2
    End If
    If pixel_y < 0 Then
        result_code Or= 4
    ElseIf pixel_y > surface_height - 1 Then
        result_code Or= 8
    End If
    Return result_code
End Function


Private Function pixelsurface_ClipLine( _
    ByRef start_x As Double, ByRef start_y As Double, _
    ByRef end_x As Double, ByRef end_y As Double, _
    ByVal surface_width As Integer, ByVal surface_height As Integer _
) As Integer
    ' Cohen-Sutherland clipping bounds all later integer subtraction to the
    ' small canvas rectangle, even when a caller supplies extreme endpoints.
    ' fblint: disable-next-line FBL311 REASON: The loop counter bounds repeated work; the cursor or stream state supplies each value.
    For pass_index As Integer = 1 To 8
        Dim As Integer start_code = pixelsurface_LineOutCode( _
            start_x, start_y, surface_width, surface_height)
        Dim As Integer end_code = pixelsurface_LineOutCode( _
            end_x, end_y, surface_width, surface_height)
        If start_code = 0 AndAlso end_code = 0 Then Return -1
        If (start_code And end_code) <> 0 Then Return 0

        Dim As Integer outside_code = IIf(start_code <> 0, start_code, end_code)
        Dim As Double clipped_x
        Dim As Double clipped_y
        If (outside_code And 8) <> 0 Then
            If end_y = start_y Then Return 0
            clipped_x = start_x + (end_x - start_x) * _
                ((surface_height - 1) - start_y) / (end_y - start_y)
            clipped_y = surface_height - 1
        ElseIf (outside_code And 4) <> 0 Then
            If end_y = start_y Then Return 0
            clipped_x = start_x + (end_x - start_x) * (0 - start_y) / (end_y - start_y)
            clipped_y = 0
        ElseIf (outside_code And 2) <> 0 Then
            If end_x = start_x Then Return 0
            clipped_y = start_y + (end_y - start_y) * _
                ((surface_width - 1) - start_x) / (end_x - start_x)
            clipped_x = surface_width - 1
        Else
            If end_x = start_x Then Return 0
            clipped_y = start_y + (end_y - start_y) * (0 - start_x) / (end_x - start_x)
            clipped_x = 0
        End If

        If outside_code = start_code Then
            start_x = clipped_x
            start_y = clipped_y
        Else
            end_x = clipped_x
            end_y = clipped_y
        End If
    Next pass_index
    Return 0
End Function


Function pixelsurface_DrawLine( _
    ByRef surface As GuiPixelSurface, ByVal start_x As Integer, ByVal start_y As Integer, _
    ByVal end_x As Integer, ByVal end_y As Integer, ByVal color_value As ULong _
) As Integer
    Dim As Double clipped_start_x = start_x
    Dim As Double clipped_start_y = start_y
    Dim As Double clipped_end_x = end_x
    Dim As Double clipped_end_y = end_y
    Dim As Integer raster_start_x
    Dim As Integer raster_start_y
    Dim As Integer raster_end_x
    Dim As Integer raster_end_y
    Dim As Integer delta_x
    Dim As Integer delta_y
    Dim As Integer step_x
    Dim As Integer step_y
    Dim As Integer line_error

    If surface.colors = 0 OrElse surface.occupied = 0 OrElse _
       surface.width < 1 OrElse surface.height < 1 Then Return 0
    If pixelsurface_ClipLine( _
        clipped_start_x, clipped_start_y, clipped_end_x, clipped_end_y, _
        surface.width, surface.height) = 0 Then Return -1

    raster_start_x = CInt(clipped_start_x)
    raster_start_y = CInt(clipped_start_y)
    raster_end_x = CInt(clipped_end_x)
    raster_end_y = CInt(clipped_end_y)
    delta_x = Abs(raster_end_x - raster_start_x)
    delta_y = -Abs(raster_end_y - raster_start_y)
    step_x = IIf(raster_start_x < raster_end_x, 1, -1)
    step_y = IIf(raster_start_y < raster_end_y, 1, -1)
    line_error = delta_x + delta_y

    Do
        pixelsurface_SetPixel surface, raster_start_x, raster_start_y, color_value
        If raster_start_x = raster_end_x AndAlso raster_start_y = raster_end_y Then Exit Do
        Dim As Integer doubled_error = 2 * line_error
        If doubled_error >= delta_y Then
            line_error += delta_y
            raster_start_x += step_x
        End If
        If doubled_error <= delta_x Then
            line_error += delta_x
            raster_start_y += step_y
        End If
    Loop
    Return -1
End Function


' -------------------------------------------------------------------------
' Clipped styled-line rasterization
' -------------------------------------------------------------------------

Private Function pixelsurface_StyleDrawsPixel( _
    ByVal style_value As ULong, ByVal raster_index As ULongInt _
) As Integer
    Dim As ULong bit_mask = Cast(ULong, &h8000) Shr CInt(raster_index And 15)
    Return IIf((style_value And bit_mask) <> 0, -1, 0)
End Function


Function pixelsurface_DrawStyledLine( _
    ByRef surface As GuiPixelSurface, ByVal start_x As Integer, ByVal start_y As Integer, _
    ByVal end_x As Integer, ByVal end_y As Integer, ByVal color_value As ULong, _
    ByVal style_value As ULong _
) As Integer
    Dim As Double clipped_start_x = start_x
    Dim As Double clipped_start_y = start_y
    Dim As Double clipped_end_x = end_x
    Dim As Double clipped_end_y = end_y
    Dim As Integer raster_start_x
    Dim As Integer raster_start_y
    Dim As Integer raster_end_x
    Dim As Integer raster_end_y
    Dim As Integer delta_x
    Dim As Integer delta_y
    Dim As Integer step_x
    Dim As Integer step_y
    Dim As Integer line_error
    Dim As LongInt horizontal_offset
    Dim As LongInt vertical_offset
    Dim As ULongInt pattern_index

    If surface.colors = 0 OrElse surface.occupied = 0 OrElse _
       surface.width < 1 OrElse surface.height < 1 Then Return 0
    If pixelsurface_ClipLine( _
        clipped_start_x, clipped_start_y, clipped_end_x, clipped_end_y, _
        surface.width, surface.height) = 0 Then Return -1

    raster_start_x = CInt(clipped_start_x)
    raster_start_y = CInt(clipped_start_y)
    raster_end_x = CInt(clipped_end_x)
    raster_end_y = CInt(clipped_end_y)

    ' Bresenham advances the dominant axis once for each raster pixel. Keep
    ' this count in 64 bits because a public Integer endpoint can be far
    ' outside the retained canvas even though only clipped pixels are drawn.
    horizontal_offset = Cast(LongInt, raster_start_x) - Cast(LongInt, start_x)
    vertical_offset = Cast(LongInt, raster_start_y) - Cast(LongInt, start_y)
    If horizontal_offset < 0 Then horizontal_offset = -horizontal_offset
    If vertical_offset < 0 Then vertical_offset = -vertical_offset
    If horizontal_offset > vertical_offset Then
        pattern_index = horizontal_offset
    Else
        pattern_index = vertical_offset
    End If

    delta_x = Abs(raster_end_x - raster_start_x)
    delta_y = -Abs(raster_end_y - raster_start_y)
    step_x = IIf(raster_start_x < raster_end_x, 1, -1)
    step_y = IIf(raster_start_y < raster_end_y, 1, -1)
    line_error = delta_x + delta_y

    Do
        If pixelsurface_StyleDrawsPixel(style_value, pattern_index) Then _
            pixelsurface_SetPixel surface, raster_start_x, raster_start_y, color_value
        If raster_start_x = raster_end_x AndAlso raster_start_y = raster_end_y Then Exit Do
        pattern_index += 1
        Dim As Integer doubled_error = 2 * line_error
        If doubled_error >= delta_y Then
            line_error += delta_y
            raster_start_x += step_x
        End If
        If doubled_error <= delta_x Then
            line_error += delta_x
            raster_start_y += step_y
        End If
    Loop
    Return -1
End Function


' -------------------------------------------------------------------------
' Clipped rectangle rasterization
' -------------------------------------------------------------------------

Private Sub pixelsurface_SetStyledRectanglePixel( _
    ByRef surface As GuiPixelSurface, ByVal pixel_x As Integer, _
    ByVal pixel_y As Integer, ByVal color_value As ULong, _
    ByVal style_value As ULong, ByRef pattern_index As ULongInt _
)
    If pixelsurface_StyleDrawsPixel(style_value, pattern_index) Then _
        pixelsurface_SetPixel surface, pixel_x, pixel_y, color_value
    pattern_index += 1
End Sub


Function pixelsurface_DrawStyledRectangle( _
    ByRef surface As GuiPixelSurface, ByVal start_x As Integer, _
    ByVal start_y As Integer, ByVal end_x As Integer, ByVal end_y As Integer, _
    ByVal color_value As ULong, ByVal filled As Integer, _
    ByVal style_value As ULong _
) As Integer
    Dim As LongInt low_x = IIf(start_x < end_x, start_x, end_x)
    Dim As LongInt high_x = IIf(start_x > end_x, start_x, end_x)
    Dim As LongInt low_y = IIf(start_y < end_y, start_y, end_y)
    Dim As LongInt high_y = IIf(start_y > end_y, start_y, end_y)
    Dim As Integer clipped_low_x
    Dim As Integer clipped_high_x
    Dim As Integer clipped_low_y
    Dim As Integer clipped_high_y
    Dim As ULongInt pattern_index
    Dim As ULong normalized_style = style_value And &hFFFF

    If surface.colors = 0 OrElse surface.occupied = 0 OrElse _
       surface.width < 1 OrElse surface.height < 1 Then Return 0
    ' The FreeBASIC BF path fills before consulting style. Keep that behavior
    ' so retained output agrees with native VBDOS programs using a style field.
    If filled Then Return pixelsurface_DrawRectangle( _
        surface, start_x, start_y, end_x, end_y, color_value, -1)

    ' The installed graphics library normalizes the two physical endpoints
    ' before clipping. Do the range comparisons in LongInt so an Integer
    ' minimum coordinate cannot overflow while its clipped phase is derived.
    If high_x < 0 OrElse low_x >= surface.width OrElse _
       high_y < 0 OrElse low_y >= surface.height Then Return -1
    clipped_low_x = IIf(low_x < 0, 0, CInt(low_x))
    clipped_high_x = IIf(high_x >= surface.width, surface.width - 1, CInt(high_x))
    clipped_low_y = IIf(low_y < 0, 0, CInt(low_y))
    clipped_high_y = IIf(high_y >= surface.height, surface.height - 1, CInt(high_y))

    /'
        FreeBASIC box pattern order

        gfxlib begins at the bottom edge, then visits top, right, and left.
        It does not restart the 16-bit mask at any edge. The adjustments after
        a clipped or fully hidden edge are intentionally the same as gfx_box.c,
        including duplicate corner visits. A clear pattern bit never erases a
        retained old pixel, just as a native styled LINE does not erase one.
    '/
    pattern_index = CULngInt(Cast(LongInt, clipped_low_x) - low_x)

    If high_y < surface.height Then
        For pixel_x As Integer = clipped_low_x To clipped_high_x
            pixelsurface_SetStyledRectanglePixel surface, pixel_x, CInt(high_y), _
                color_value, normalized_style, pattern_index
        Next pixel_x
    Else
        pattern_index += clipped_high_x - clipped_low_x + 1
    End If
    pattern_index += CULngInt((high_x - clipped_high_x) + (clipped_low_x - low_x))

    If low_y >= 0 Then
        For pixel_x As Integer = clipped_low_x To clipped_high_x
            pixelsurface_SetStyledRectanglePixel surface, pixel_x, CInt(low_y), _
                color_value, normalized_style, pattern_index
        Next pixel_x
    Else
        pattern_index += clipped_high_x - clipped_low_x + 1
    End If
    pattern_index += CULngInt((high_x - clipped_high_x) + (clipped_low_y - low_y))

    If high_x < surface.width Then
        For pixel_y As Integer = clipped_low_y To clipped_high_y
            pixelsurface_SetStyledRectanglePixel surface, CInt(high_x), pixel_y, _
                color_value, normalized_style, pattern_index
        Next pixel_y
    Else
        pattern_index += clipped_high_y - clipped_low_y + 1
    End If
    pattern_index += CULngInt((high_y - clipped_high_y) + (clipped_low_y - low_y))

    If low_x >= 0 Then
        For pixel_y As Integer = clipped_low_y To clipped_high_y
            pixelsurface_SetStyledRectanglePixel surface, CInt(low_x), pixel_y, _
                color_value, normalized_style, pattern_index
        Next pixel_y
    End If
    Return -1
End Function

Function pixelsurface_DrawRectangle( _
    ByRef surface As GuiPixelSurface, ByVal start_x As Integer, _
    ByVal start_y As Integer, ByVal end_x As Integer, ByVal end_y As Integer, _
    ByVal color_value As ULong, ByVal filled As Integer _
) As Integer
    Dim As Integer low_x = IIf(start_x < end_x, start_x, end_x)
    Dim As Integer high_x = IIf(start_x > end_x, start_x, end_x)
    Dim As Integer low_y = IIf(start_y < end_y, start_y, end_y)
    Dim As Integer high_y = IIf(start_y > end_y, start_y, end_y)
    Dim As Integer clipped_low_x
    Dim As Integer clipped_high_x
    Dim As Integer clipped_low_y
    Dim As Integer clipped_high_y

    If surface.colors = 0 OrElse surface.occupied = 0 OrElse _
       surface.width < 1 OrElse surface.height < 1 Then Return 0
    If filled = 0 Then
        pixelsurface_DrawLine surface, low_x, low_y, high_x, low_y, color_value
        pixelsurface_DrawLine surface, low_x, high_y, high_x, high_y, color_value
        pixelsurface_DrawLine surface, low_x, low_y, low_x, high_y, color_value
        pixelsurface_DrawLine surface, high_x, low_y, high_x, high_y, color_value
        Return -1
    End If

    ' Clipping converts an unbounded caller rectangle into at most the owned
    ' canvas area before the nested fill loops begin.
    clipped_low_x = IIf(low_x < 0, 0, low_x)
    clipped_high_x = IIf(high_x >= surface.width, surface.width - 1, high_x)
    clipped_low_y = IIf(low_y < 0, 0, low_y)
    clipped_high_y = IIf(high_y >= surface.height, surface.height - 1, high_y)
    If clipped_low_x > clipped_high_x OrElse clipped_low_y > clipped_high_y Then Return -1
    For pixel_y As Integer = clipped_low_y To clipped_high_y
        For pixel_x As Integer = clipped_low_x To clipped_high_x
            pixelsurface_SetPixel surface, pixel_x, pixel_y, color_value
        Next pixel_x
    Next pixel_y
    Return -1
End Function


' -------------------------------------------------------------------------
' Clipped circle and ellipse rasterization
' -------------------------------------------------------------------------

Private Sub pixelsurface_SetCirclePixel( _
    ByRef surface As GuiPixelSurface, ByVal pixel_x As LongInt, _
    ByVal pixel_y As LongInt, ByVal color_value As ULong _
)
    ' Keep additions in LongInt until the canvas check proves the values can
    ' narrow safely on every target. Off-client circle points are clipped.
    If pixel_x < 0 OrElse pixel_y < 0 OrElse _
       pixel_x >= surface.width OrElse pixel_y >= surface.height Then Exit Sub
    pixelsurface_SetPixel surface, CInt(pixel_x), CInt(pixel_y), color_value
End Sub


Private Sub pixelsurface_SetCircleOctants( _
    ByRef surface As GuiPixelSurface, ByVal center_x As LongInt, _
    ByVal center_y As LongInt, ByVal offset_x As LongInt, _
    ByVal offset_y As LongInt, ByVal color_value As ULong _
)
    pixelsurface_SetCirclePixel surface, center_x + offset_x, center_y + offset_y, color_value
    pixelsurface_SetCirclePixel surface, center_x + offset_y, center_y + offset_x, color_value
    pixelsurface_SetCirclePixel surface, center_x - offset_y, center_y + offset_x, color_value
    pixelsurface_SetCirclePixel surface, center_x - offset_x, center_y + offset_y, color_value
    pixelsurface_SetCirclePixel surface, center_x - offset_x, center_y - offset_y, color_value
    pixelsurface_SetCirclePixel surface, center_x - offset_y, center_y - offset_x, color_value
    pixelsurface_SetCirclePixel surface, center_x + offset_y, center_y - offset_x, color_value
    pixelsurface_SetCirclePixel surface, center_x + offset_x, center_y - offset_y, color_value
End Sub


Function pixelsurface_DrawCircle( _
    ByRef surface As GuiPixelSurface, ByVal center_x As Integer, _
    ByVal center_y As Integer, ByVal radius As Integer, _
    ByVal color_value As ULong _
) As Integer
    Dim As LongInt offset_x
    Dim As LongInt offset_y
    Dim As LongInt decision_value

    If radius < 0 OrElse radius > PIXELSURFACE_MAX_DRAW_RADIUS Then Return 0
    If surface.colors = 0 OrElse surface.occupied = 0 OrElse _
       surface.width < 1 OrElse surface.height < 1 Then Return 0
    offset_x = radius
    offset_y = 0
    decision_value = 1 - offset_x
    Do While offset_x >= offset_y
        pixelsurface_SetCircleOctants surface, center_x, center_y, _
            offset_x, offset_y, color_value
        offset_y += 1
        If decision_value < 0 Then
            decision_value += 2 * offset_y + 1
        Else
            offset_x -= 1
            decision_value += 2 * (offset_y - offset_x) + 1
        End If
    Loop
    Return -1
End Function


Private Function pixelsurface_RoundCoordinate(ByVal coordinate_value As Double) As LongInt
    ' gfxlib's CIRCLE samples round a trigonometric component to its nearest
    ' physical pixel. Spell that conversion out instead of relying on a
    ' target-specific implicit narrowing rule.
    If coordinate_value >= 0 Then
        Return CLngInt(Fix(coordinate_value + 0.5))
    End If
    Return CLngInt(Fix(coordinate_value - 0.5))
End Function


Private Function pixelsurface_GetEllipseAxes( _
    ByVal radius As Integer, ByVal aspect_value As Double, _
    ByRef axis_x As Double, ByRef axis_y As Double _
) As Integer
    Dim As Double normalized_aspect = aspect_value

    axis_x = 0
    axis_y = 0
    If normalized_aspect <> normalized_aspect OrElse normalized_aspect < 0 OrElse _
       normalized_aspect > PIXELSURFACE_MAX_DRAW_RADIUS Then Return 0
    ' A zero aspect is the documented request for the current display aspect.
    ' omaGUI pixels are square, so its portable default is one.
    If normalized_aspect = 0 Then normalized_aspect = 1
    If normalized_aspect > 1 Then
        axis_x = radius / normalized_aspect
        axis_y = radius
    Else
        axis_x = radius
        axis_y = radius * normalized_aspect
    End If
    Return -1
End Function


Private Sub pixelsurface_SetEllipsePoint( _
    ByRef surface As GuiPixelSurface, ByVal center_x As LongInt, _
    ByVal center_y As LongInt, ByVal axis_x As Double, ByVal axis_y As Double, _
    ByVal angle_value As Double, ByVal color_value As ULong _
)
    Dim As Double component_x = CDbl(Cos(angle_value)) * axis_x
    Dim As Double component_y = CDbl(Sin(angle_value)) * axis_y
    Dim As LongInt offset_x = pixelsurface_RoundCoordinate(component_x)
    Dim As LongInt offset_y = pixelsurface_RoundCoordinate(component_y)

    ' Screen Y grows downward, so the mathematical positive arc direction
    ' must subtract its sine component.
    pixelsurface_SetCirclePixel surface, center_x + offset_x, _
        center_y - offset_y, color_value
End Sub


Private Function pixelsurface_DrawEllipseSamples( _
    ByRef surface As GuiPixelSurface, ByVal center_x As LongInt, _
    ByVal center_y As LongInt, ByVal axis_x As Double, ByVal axis_y As Double, _
    ByVal start_angle As Double, ByVal end_angle As Double, _
    ByVal color_value As ULong _
) As Integer
    Dim As Double increment_value
    Dim As Double angle_span = end_angle - start_angle
    Dim As LongInt sample_count

    If axis_x < 0.5 OrElse axis_y < 0.5 Then
        ' Degenerate aspect ratios are valid inputs. Retain the center point
        ' rather than dividing by a near-zero sampling product.
        pixelsurface_SetCirclePixel surface, center_x, center_y, color_value
        Return -1
    End If
    increment_value = 1.0 / (Sqr(axis_x) * Sqr(axis_y) * 1.5)
    If increment_value <= 0 OrElse increment_value <> increment_value Then Return 0
    sample_count = CLngInt(Fix(angle_span / increment_value + 0.5))
    If sample_count < 0 OrElse sample_count > PIXELSURFACE_MAX_ARC_STEPS Then Return 0
    For sample_index As LongInt = 0 To sample_count
        pixelsurface_SetEllipsePoint surface, center_x, center_y, axis_x, axis_y, _
            start_angle + sample_index * increment_value, color_value
    Next sample_index
    Return -1
End Function


Private Function pixelsurface_FillEllipse( _
    ByRef surface As GuiPixelSurface, ByVal center_x As LongInt, _
    ByVal center_y As LongInt, ByVal axis_x As Double, ByVal axis_y As Double, _
    ByVal color_value As ULong _
) As Integer
    Dim As LongInt first_y
    Dim As LongInt last_y

    If axis_x < 0.5 AndAlso axis_y < 0.5 Then
        pixelsurface_SetCirclePixel surface, center_x, center_y, color_value
        Return -1
    End If
    If axis_y < 0.5 Then
        Return pixelsurface_DrawLine( _
            surface, CInt(center_x - pixelsurface_RoundCoordinate(axis_x)), _
            CInt(center_y), _
            CInt(center_x + pixelsurface_RoundCoordinate(axis_x)), _
            CInt(center_y), color_value)
    End If
    first_y = center_y - pixelsurface_RoundCoordinate(axis_y)
    last_y = center_y + pixelsurface_RoundCoordinate(axis_y)
    If first_y < 0 Then first_y = 0
    If last_y >= surface.height Then last_y = surface.height - 1
    For pixel_y As LongInt = first_y To last_y
        Dim As Double normalized_y = (pixel_y - center_y) / axis_y
        Dim As Double horizontal_square = 1.0 - normalized_y * normalized_y
        Dim As LongInt horizontal_radius
        If horizontal_square < 0 Then Continue For
        horizontal_radius = pixelsurface_RoundCoordinate( _
            axis_x * Sqr(horizontal_square))
        pixelsurface_DrawLine surface, _
            CInt(center_x - horizontal_radius), CInt(pixel_y), _
            CInt(center_x + horizontal_radius), CInt(pixel_y), color_value
    Next pixel_y
    Return -1
End Function


Function pixelsurface_DrawEllipse( _
    ByRef surface As GuiPixelSurface, ByVal center_x As Integer, _
    ByVal center_y As Integer, ByVal radius As Integer, _
    ByVal aspect_value As Double, ByVal start_angle As Double, _
    ByVal end_angle As Double, ByVal filled As Integer, _
    ByVal color_value As ULong _
) As Integer
    Dim As Double axis_x
    Dim As Double axis_y
    Dim As Double normalized_start = start_angle
    Dim As Double normalized_end = end_angle
    ' fblint: disable-next-line FBL311 REASON: The loop counter bounds repeated work; the cursor or stream state supplies each value.
    Dim As LongInt turn_count

    If radius < 0 OrElse radius > PIXELSURFACE_MAX_DRAW_RADIUS Then Return 0
    If start_angle <> start_angle OrElse end_angle <> end_angle OrElse _
       Abs(start_angle) > 65536.0 OrElse Abs(end_angle) > 65536.0 Then Return 0
    If pixelsurface_GetEllipseAxes(radius, aspect_value, axis_x, axis_y) = 0 Then Return 0
    ' Keep radial-line endpoint casts safe for direct omaGUI callers whose
    ' center is near an Integer boundary. VBDOS itself has tighter coordinates.
    If CDbl(center_x) - axis_x < -2147483648.0 OrElse _
       CDbl(center_x) + axis_x > 2147483647.0 OrElse _
       CDbl(center_y) - axis_y < -2147483648.0 OrElse _
       CDbl(center_y) + axis_y > 2147483647.0 Then Return 0
    If surface.colors = 0 OrElse surface.occupied = 0 OrElse _
       surface.width < 1 OrElse surface.height < 1 Then Return 0

    If start_angle = 0 AndAlso end_angle = PIXELSURFACE_FULL_CIRCLE Then
        If filled Then Return pixelsurface_FillEllipse( _
            surface, center_x, center_y, axis_x, axis_y, color_value)
        If axis_x = radius AndAlso axis_y = radius Then Return _
            pixelsurface_DrawCircle(surface, center_x, center_y, radius, color_value)
        Return pixelsurface_DrawEllipseSamples( _
            surface, center_x, center_y, axis_x, axis_y, start_angle, end_angle, color_value)
    End If

    ' This normalization deliberately follows gfxlib's order. Negative angles
    ' request a radial line before their absolute arc endpoint is considered.
    If normalized_start < 0 Then normalized_start = -normalized_start
    If normalized_end < 0 Then normalized_end = -normalized_end
    For turn_count = 1 To 10430
        If normalized_end >= normalized_start Then Exit For
        normalized_end += PIXELSURFACE_FULL_CIRCLE
    Next turn_count
    If normalized_end < normalized_start Then Return 0
    For turn_count = 1 To 10430
        If normalized_end - normalized_start <= PIXELSURFACE_FULL_CIRCLE Then Exit For
        normalized_start += PIXELSURFACE_FULL_CIRCLE
    Next turn_count
    If normalized_end - normalized_start > PIXELSURFACE_FULL_CIRCLE Then Return 0
    ' Check the bounded sample plan before a negative-angle radial line can
    ' mutate the retained surface.
    If axis_x >= 0.5 AndAlso axis_y >= 0.5 Then
        Dim As Double increment_value = 1.0 / (Sqr(axis_x) * Sqr(axis_y) * 1.5)
        Dim As LongInt sample_count = CLngInt(Fix( _
            (normalized_end - normalized_start) / increment_value + 0.5))
        If increment_value <= 0 OrElse sample_count < 0 OrElse _
           sample_count > PIXELSURFACE_MAX_ARC_STEPS Then Return 0
    End If
    If start_angle < 0 Then
        Dim As LongInt radial_x = center_x + pixelsurface_RoundCoordinate( _
            Cos(normalized_start) * axis_x)
        Dim As LongInt radial_y = center_y - pixelsurface_RoundCoordinate( _
            Sin(normalized_start) * axis_y)
        pixelsurface_DrawLine surface, center_x, center_y, _
            CInt(radial_x), CInt(radial_y), color_value
    End If
    If end_angle < 0 Then
        Dim As LongInt radial_x = center_x + pixelsurface_RoundCoordinate( _
            Cos(normalized_end) * axis_x)
        Dim As LongInt radial_y = center_y - pixelsurface_RoundCoordinate( _
            Sin(normalized_end) * axis_y)
        pixelsurface_DrawLine surface, center_x, center_y, _
            CInt(radial_x), CInt(radial_y), color_value
    End If
    ' gfxlib ignores F for arcs. The retained primitive intentionally does too.
    Return pixelsurface_DrawEllipseSamples( _
        surface, center_x, center_y, axis_x, axis_y, normalized_start, _
        normalized_end, color_value)
End Function


Function pixelsurface_ReadPixel( _
    ByRef surface As Const GuiPixelSurface, ByVal x As Integer, ByVal y As Integer, _
    ByRef color_value As ULong, ByRef occupied As Integer _
) As Integer
    Dim As ULongInt pixel_index

    color_value = 0
    occupied = 0
    If surface.colors = 0 OrElse surface.occupied = 0 OrElse _
       x < 0 OrElse y < 0 OrElse x >= surface.width OrElse y >= surface.height Then Return 0
    pixel_index = CULngInt(y) * surface.width + x
    color_value = surface.colors[pixel_index]
    occupied = IIf(surface.occupied[pixel_index], -1, 0)
    Return -1
End Function

' -------------------------------------------------------------------------
' Rendering
' -------------------------------------------------------------------------

Private Sub pixelsurface_DrawRun( _
    ByVal start_x As Integer, ByVal end_x As Integer, ByVal pixel_y As Integer, _
    ByVal color_value As ULong _
)
    If end_x < start_x Then Exit Sub
    If start_x = end_x Then
        backend_PSet start_x, pixel_y, color_value
    Else
        backend_Line start_x, pixel_y, end_x, pixel_y, color_value
    End If
End Sub


Sub pixelsurface_Render( _
    ByRef surface As Const GuiPixelSurface, ByVal origin_x As Integer, _
    ByVal origin_y As Integer _
)
    Dim As Integer clip_x
    Dim As Integer clip_y
    Dim As Integer clip_width
    Dim As Integer clip_height
    Dim As Integer run_active
    Dim As Integer run_start_x
    Dim As ULong run_color

    If surface.colors = 0 OrElse surface.occupied = 0 OrElse _
       surface.width < 1 OrElse surface.height < 1 Then Exit Sub
    ' The bounded canvas fits safely around this conservative origin range.
    If origin_x < -1000000 OrElse origin_x > 1000000 OrElse _
       origin_y < -1000000 OrElse origin_y > 1000000 Then Exit Sub
    backend_GetClip clip_x, clip_y, clip_width, clip_height
    If clip_width < 1 OrElse clip_height < 1 Then Exit Sub

    For row_index As Integer = 0 To surface.height - 1
        Dim As Integer destination_y = origin_y + row_index
        If destination_y < clip_y OrElse destination_y >= clip_y + clip_height Then Continue For
        run_active = 0
        For column_index As Integer = 0 To surface.width - 1
            Dim As Integer destination_x = origin_x + column_index
            Dim As ULongInt pixel_index = CULngInt(row_index) * surface.width + column_index
            Dim As Integer visible_pixel = _
                surface.occupied[pixel_index] <> 0 AndAlso _
                destination_x >= clip_x AndAlso _
                destination_x < clip_x + clip_width
            If visible_pixel Then
                Dim As ULong color_value = surface.colors[pixel_index]
                If run_active = 0 Then
                    run_active = -1
                    run_start_x = destination_x
                    run_color = color_value
                ElseIf color_value <> run_color Then
                    pixelsurface_DrawRun run_start_x, destination_x - 1, _
                        destination_y, run_color
                    run_start_x = destination_x
                    run_color = color_value
                End If
            ElseIf run_active Then
                pixelsurface_DrawRun run_start_x, destination_x - 1, _
                    destination_y, run_color
                run_active = 0
            End If
        Next column_index
        If run_active Then
            pixelsurface_DrawRun run_start_x, origin_x + surface.width - 1, _
                destination_y, run_color
        End If
    Next row_index
End Sub

/' end of pixelsurface.bas '/
