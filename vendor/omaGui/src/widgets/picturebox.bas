/'
    Project: omaGUI
    ---------------

    File: picturebox.bas

    Purpose:

        Render a portable classic PictureBox-style display surface.

    Responsibilities:

        - paint a theme-colored client background
        - honor an optional caller-supplied client background color
        - honor an optional caller-supplied display-text color
        - draw the configured border without platform-native controls
        - clip child widgets to the client rectangle
        - own and release PictureBox metadata
        - retain printed byte cells independently of display text
        - retain explicit pixel colors independently of a platform bitmap
        - own a copied raster image beneath retained drawings and text
        - forward clipped 16-bit patterned line requests to the pixel surface

    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Implementation unit assembled by omaGUI.bi when OMAGUI_IMPLEMENTATION is defined.

    This file intentionally does NOT contain:

        - image file loading or raster drawing algorithms
        - application drawing policy
        - input event behavior

    Ownership:

        - the widget owns one PictureBoxData allocation and its retained surfaces
'/

#lang "fb"

#include once "src/widgets/picturebox.bi"
#include once "src/backend/theme.bi"

Const PICTUREBOX_MINIMUM_DIMENSION As Integer = 4
Const PICTUREBOX_SINGLE_INSET As Integer = 1
Const PICTUREBOX_SUNKEN_INSET As Integer = 2
Const PICTUREBOX_DOUBLE_INSET As Integer = 2
Const PICTUREBOX_TEXT_PADDING As Integer = 4

' -------------------------------------------------------------------------
' Private style helpers
' -------------------------------------------------------------------------

Private Function picturebox_IsValidBorderStyle( _
    ByVal border_style As Integer _
) As Integer
    Select Case border_style
    Case PICTUREBOX_BORDER_NONE, PICTUREBOX_BORDER_SINGLE, _
         PICTUREBOX_BORDER_SUNKEN, PICTUREBOX_BORDER_DOUBLE
        Return -1
    End Select
    Return 0
End Function


Private Function picturebox_GetClientInset( _
    ByVal border_style As Integer _
) As Integer
    Select Case border_style
    Case PICTUREBOX_BORDER_SINGLE
        Return PICTUREBOX_SINGLE_INSET
    Case PICTUREBOX_BORDER_SUNKEN
        Return PICTUREBOX_SUNKEN_INSET
    Case PICTUREBOX_BORDER_DOUBLE
        Return PICTUREBOX_DOUBLE_INSET
    End Select
    Return 0
End Function


Private Sub picturebox_ApplyChildClip( _
    ByVal picture_widget As Widget Ptr, _
    ByVal border_style As Integer _
)
    If picture_widget = 0 Then Exit Sub
    Dim As Integer client_inset = picturebox_GetClientInset(border_style)

    picture_widget->clip_children = -1
    picture_widget->child_clip_x = client_inset
    picture_widget->child_clip_y = client_inset
    picture_widget->child_clip_right = client_inset
    picture_widget->child_clip_bottom = client_inset
End Sub


' The client-tracking mode is updated during ordinary GUI updates and again
' before direct rendering. A temporarily too-small client keeps the prior
' canvas intact so a later expansion does not discard retained artwork.
Private Function picturebox_SynchronizePixelCanvas( _
    ByVal picture_widget As Widget Ptr _
) As Integer
    Dim As PictureBoxData Ptr picture_data
    Dim As Integer client_inset
    Dim As Integer canvas_width
    Dim As Integer canvas_height

    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    If picture_data->pixel_tracks_client = 0 Then Return -1
    client_inset = picturebox_GetClientInset(picture_data->border_style)
    canvas_width = picture_widget->w - _
        2 * (client_inset + picture_data->pixel_inset_x)
    canvas_height = picture_widget->h - _
        2 * (client_inset + picture_data->pixel_inset_y)
    If canvas_width < 1 OrElse canvas_height < 1 Then Return 0
    If canvas_width > PIXELSURFACE_MAX_DIMENSION OrElse _
       canvas_height > PIXELSURFACE_MAX_DIMENSION Then Return 0
    If picture_data->pixel_surface.colors <> 0 OrElse _
       picture_data->pixel_surface.occupied <> 0 Then
        If pixelsurface_Resize( _
            picture_data->pixel_surface, canvas_width, canvas_height _
        ) = 0 Then Return 0
    End If
    picture_data->pixel_width = canvas_width
    picture_data->pixel_height = canvas_height
    Return -1
End Function


Private Sub picturebox_Update(ByVal picture_widget As Widget Ptr)
    picturebox_SynchronizePixelCanvas picture_widget
End Sub

' -------------------------------------------------------------------------
' Rendering and lifecycle
' -------------------------------------------------------------------------

Sub picturebox_Render(ByVal picture_widget As Widget Ptr)
    Dim As PictureBoxData Ptr picture_data
    Dim As ULong background_color
    Dim As Integer text_height
    Dim As Integer text_inset
    Dim As Integer text_width
    Dim As ULong text_color
    Dim As Integer pixel_width
    Dim As Integer pixel_height
    Dim As Integer pixel_origin_x
    Dim As Integer pixel_origin_y

    If picture_widget = 0 OrElse picture_widget->data = 0 Then Exit Sub
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)

    background_color = theme_GetColor(GUI_COLOR_WINDOW_BG)
    If picture_data->background_color_override <> 0 Then _
        background_color = picture_data->background_color
    text_color = theme_GetColor(GUI_COLOR_TEXT)
    If picture_data->foreground_color_override <> 0 Then _
        text_color = picture_data->foreground_color

    backend_Rect picture_widget->ax, picture_widget->ay, _
    picture_widget->w, picture_widget->h, _
        background_color, -1

    Select Case picture_data->border_style
    Case PICTUREBOX_BORDER_SINGLE
        backend_Rect picture_widget->ax, picture_widget->ay, _
            picture_widget->w, picture_widget->h, _
            theme_GetColor(GUI_COLOR_BORDER), 0
        text_inset = PICTUREBOX_SINGLE_INSET
    Case PICTUREBOX_BORDER_DOUBLE
        backend_Rect picture_widget->ax, picture_widget->ay, _
            picture_widget->w, picture_widget->h, _
            theme_GetColor(GUI_COLOR_BORDER), 0
        If picture_widget->w > 2 AndAlso picture_widget->h > 2 Then
            backend_Rect picture_widget->ax + 1, picture_widget->ay + 1, _
                picture_widget->w - 2, picture_widget->h - 2, _
                theme_GetColor(GUI_COLOR_BORDER), 0
        End If
        text_inset = PICTUREBOX_DOUBLE_INSET
    Case PICTUREBOX_BORDER_SUNKEN
        /'
            Dark top and left edges plus light bottom and right edges make the
            surface read as recessed on every backend without a native theme
            API. The inner border protects the client on very small widgets.
        '/
        backend_Line picture_widget->ax, picture_widget->ay, _
            picture_widget->ax + picture_widget->w - 1, picture_widget->ay, _
            current_theme.bg_dark
        backend_Line picture_widget->ax, picture_widget->ay, _
            picture_widget->ax, picture_widget->ay + picture_widget->h - 1, _
            current_theme.bg_dark
        backend_Line picture_widget->ax, _
            picture_widget->ay + picture_widget->h - 1, _
            picture_widget->ax + picture_widget->w - 1, _
            picture_widget->ay + picture_widget->h - 1, _
            current_theme.bg_light
        backend_Line picture_widget->ax + picture_widget->w - 1, _
            picture_widget->ay, _
            picture_widget->ax + picture_widget->w - 1, _
            picture_widget->ay + picture_widget->h - 1, _
            current_theme.bg_light
        backend_Rect picture_widget->ax + 1, picture_widget->ay + 1, _
            picture_widget->w - 2, picture_widget->h - 2, _
            theme_GetColor(GUI_COLOR_BORDER), 0
        text_inset = PICTUREBOX_SUNKEN_INSET
    Case Else
        text_inset = 0
    End Select

    If picture_data->display_image <> 0 AndAlso _
       picture_widget->w > 2 * text_inset AndAlso picture_widget->h > 2 * text_inset Then
        backend_SetClip picture_widget->ax + text_inset, picture_widget->ay + text_inset, _
            picture_widget->w - 2 * text_inset, picture_widget->h - 2 * text_inset
        backend_DrawImage picture_widget->ax + text_inset, picture_widget->ay + text_inset, _
            picture_data->display_image->pixels, picture_data->display_image->hasAlpha, -1
        backend_ResetClip
    End If

    picturebox_SynchronizePixelCanvas picture_widget
    pixel_origin_x = picture_widget->ax + text_inset + picture_data->pixel_inset_x
    pixel_origin_y = picture_widget->ay + text_inset + picture_data->pixel_inset_y
    pixel_width = picture_widget->w - _
        2 * (text_inset + picture_data->pixel_inset_x)
    pixel_height = picture_widget->h - _
        2 * (text_inset + picture_data->pixel_inset_y)
    If pixel_width > 0 AndAlso pixel_height > 0 AndAlso _
       picture_data->pixel_surface.colors <> 0 AndAlso _
       picture_data->pixel_surface.occupied <> 0 Then
        backend_SetClip pixel_origin_x, pixel_origin_y, pixel_width, pixel_height
        pixelsurface_Render picture_data->pixel_surface, _
            pixel_origin_x, pixel_origin_y
        backend_ResetClip
    End If

    If Len(picture_data->text) > 0 Then
        text_width = picture_widget->w - _
            (text_inset + PICTUREBOX_TEXT_PADDING) * 2
        text_height = picture_widget->h - _
            (text_inset + PICTUREBOX_TEXT_PADDING) * 2
        If text_width > 0 AndAlso text_height > 0 Then
            backend_PrintAligned _
                picture_widget->ax + text_inset + PICTUREBOX_TEXT_PADDING, _
                picture_widget->ay + text_inset + PICTUREBOX_TEXT_PADDING, _
                text_width, text_height, text_color, _
                picture_data->text
        End If
    End If
    Dim As Integer print_width = picture_widget->w - 2 * picture_data->print_inset_x
    Dim As Integer print_height = picture_widget->h - 2 * picture_data->print_inset_y
    If print_width > 0 AndAlso print_height > 0 AndAlso picture_data->print_surface.cells <> 0 Then
        backend_SetClip picture_widget->ax + picture_data->print_inset_x, _
            picture_widget->ay + picture_data->print_inset_y, print_width, print_height
        textsurface_Render picture_data->print_surface, _
            picture_widget->ax + picture_data->print_inset_x, _
            picture_widget->ay + picture_data->print_inset_y, _
            picture_data->print_cell_width, picture_data->print_cell_height
        backend_ResetClip
    End If
End Sub


Sub picturebox_Destroy(ByVal picture_widget As Widget Ptr)
    If picture_widget = 0 Then Exit Sub
    If picture_widget->data <> 0 Then
        textsurface_Release Cast(PictureBoxData Ptr, picture_widget->data)->print_surface
        pixelsurface_Release Cast(PictureBoxData Ptr, picture_widget->data)->pixel_surface
        rasterimage_Destroy Cast(PictureBoxData Ptr, picture_widget->data)->display_image
        Delete Cast(PictureBoxData Ptr, picture_widget->data)
    End If
    picture_widget->data = 0
End Sub


Function picturebox_SetImage( _
    ByVal picture_widget As Widget Ptr, ByVal source_image As RasterImage Ptr _
) As Integer
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    If picture_widget->render <> @picturebox_Render Then Return 0
    Dim As PictureBoxData Ptr picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    Dim As RasterImage Ptr copied_image
    If source_image <> 0 Then
        If source_image->pixels = 0 Then Return 0
        Dim As Integer image_width, image_height, bytes_per_pixel, image_pitch, image_size
        Dim As Any Ptr image_pixels
        If ImageInfo(source_image->pixels, image_width, image_height, bytes_per_pixel, _
            image_pitch, image_pixels, image_size) <> 0 Then Return 0
        If bytes_per_pixel <> 4 OrElse image_pixels = 0 OrElse _
           image_width < 1 OrElse image_height < 1 OrElse _
           image_width > RASTERIMAGE_MAX_DIMENSION OrElse image_height > RASTERIMAGE_MAX_DIMENSION OrElse _
           image_width <> source_image->width OrElse image_height <> source_image->height Then Return 0
        If image_pitch < image_width * 4 OrElse CLngInt(image_pitch) * image_height > image_size Then Return 0
        copied_image = New RasterImage
        If copied_image = 0 Then Return 0
        copied_image->pixels = backend_CreateImage(image_width, image_height, 0, 32)
        If copied_image->pixels = 0 Then
            Delete copied_image
            Return 0
        End If
        ' Direct rows preserve alpha without requiring a gfxlib screen mode.
        ' Headless design inspection also owns real decoded image buffers.
        Dim As Integer copy_width, copy_height, copy_bpp, copy_pitch, copy_size
        Dim As Any Ptr copy_pixels
        If ImageInfo(copied_image->pixels, copy_width, copy_height, copy_bpp, _
            copy_pitch, copy_pixels, copy_size) <> 0 OrElse copy_bpp <> 4 OrElse copy_pixels = 0 OrElse _
            copy_width <> image_width OrElse copy_height <> image_height OrElse _
            copy_pitch < image_width * 4 OrElse CLngInt(copy_pitch) * image_height > copy_size Then
            rasterimage_Destroy copied_image
            Return 0
        End If
        Dim As ULong Ptr source_row
        Dim As ULong Ptr copy_row
        For row_index As Integer = 0 To image_height - 1
            source_row = Cast(ULong Ptr, _
                Cast(UByte Ptr, image_pixels) + row_index * image_pitch)
            copy_row = Cast(ULong Ptr, _
                Cast(UByte Ptr, copy_pixels) + row_index * copy_pitch)
            For column_index As Integer = 0 To image_width - 1
                ' ImageInfo checks allocation size and pitch before these loops.
                copy_row[column_index] = source_row[column_index]
            Next column_index
        Next row_index
        copied_image->width = image_width
        copied_image->height = image_height
        copied_image->formatKind = source_image->formatKind
        copied_image->hasAlpha = source_image->hasAlpha
    End If
    rasterimage_Destroy picture_data->display_image
    picture_data->display_image = copied_image
    Return -1
End Function


Function picturebox_Create( _
    ByVal widget_name As String, _
    ByVal display_text As String, _
    ByVal left_position As Integer, _
    ByVal top_position As Integer, _
    ByVal picture_width As Integer, _
    ByVal picture_height As Integer, _
    ByVal border_style As Integer _
) As Widget Ptr
    Dim As PictureBoxData Ptr picture_data
    Dim As Widget Ptr picture_widget

    If picture_width < PICTUREBOX_MINIMUM_DIMENSION Then _
        picture_width = PICTUREBOX_MINIMUM_DIMENSION
    If picture_height < PICTUREBOX_MINIMUM_DIMENSION Then _
        picture_height = PICTUREBOX_MINIMUM_DIMENSION
    If picturebox_IsValidBorderStyle(border_style) = 0 Then Return 0

    picture_widget = New Widget
    picture_data = New PictureBoxData
    If picture_widget = 0 OrElse picture_data = 0 Then
        If picture_widget <> 0 Then Delete picture_widget
        If picture_data <> 0 Then Delete picture_data
        Return 0
    End If

    picture_widget->name = widget_name
    picture_widget->x = left_position
    picture_widget->y = top_position
    picture_widget->w = picture_width
    picture_widget->h = picture_height
    picture_widget->visible = -1
    picture_widget->enabled = -1
    picture_widget->render = @picturebox_Render
    picture_widget->update = @picturebox_Update
    picture_widget->destroy = @picturebox_Destroy
    picture_data->text = display_text
    picture_data->border_style = border_style
    picture_data->background_color_override = 0
    picture_data->background_color = 0
    picture_data->foreground_color_override = 0
    picture_data->foreground_color = 0
    picture_widget->data = picture_data
    picturebox_ApplyChildClip picture_widget, border_style
    Return picture_widget
End Function

' -------------------------------------------------------------------------
' Public state API
' -------------------------------------------------------------------------

Function picturebox_SetPrintGrid( _
    ByVal picture_widget As Widget Ptr, ByVal columns As Integer, ByVal rows As Integer, _
    ByVal cell_width As Integer, ByVal cell_height As Integer, ByVal inset_x As Integer, ByVal inset_y As Integer _
) As Integer
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    If columns < 0 OrElse rows < 0 OrElse columns > TEXTSURFACE_MAX_DIMENSION OrElse rows > TEXTSURFACE_MAX_DIMENSION Then Return 0
    If cell_width < 1 OrElse cell_height < 1 OrElse cell_width > 256 OrElse cell_height > 256 Then Return 0
    If inset_x < 0 OrElse inset_y < 0 OrElse inset_x > 65536 OrElse inset_y > 65536 Then Return 0
    With *Cast(PictureBoxData Ptr, picture_widget->data)
        If .print_surface.cells <> 0 Then
            If textsurface_Resize(.print_surface, columns, rows) = 0 Then Return 0
        End If
        .print_columns = columns
        .print_rows = rows
        .print_cell_width = cell_width
        .print_cell_height = cell_height
        .print_inset_x = inset_x
        .print_inset_y = inset_y
    End With
    Return -1
End Function

Function picturebox_WriteByte(ByVal picture_widget As Widget Ptr, ByVal column As Integer, ByVal row As Integer, ByVal character_code As Integer) As Integer
    If picture_widget = 0 OrElse picture_widget->data = 0 OrElse character_code < 0 OrElse character_code > 255 Then Return 0
    With *Cast(PictureBoxData Ptr, picture_widget->data)
        If column < 0 OrElse row < 0 OrElse column >= .print_columns OrElse row >= .print_rows Then Return -1
        If textsurface_Resize(.print_surface, .print_columns, .print_rows) = 0 Then Return 0
        Dim As ULong foreground_color = theme_GetColor(GUI_COLOR_TEXT)
        Dim As ULong background_color = theme_GetColor(GUI_COLOR_WINDOW_BG)
        If .foreground_color_override Then foreground_color = .foreground_color
        If .background_color_override Then background_color = .background_color
        Return textsurface_WriteByte(.print_surface, column, row, character_code, foreground_color, background_color)
    End With
End Function

Sub picturebox_ClearPrint(ByVal picture_widget As Widget Ptr)
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Exit Sub
    textsurface_Release Cast(PictureBoxData Ptr, picture_widget->data)->print_surface
End Sub

Function picturebox_ReadPrintCell(ByVal picture_widget As Widget Ptr, ByVal column As Integer, ByVal row As Integer, ByRef cell As GuiTextCell) As Integer
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    Return textsurface_ReadCell(Cast(PictureBoxData Ptr, picture_widget->data)->print_surface, column, row, cell)
End Function


Function picturebox_SetPixelCanvas( _
    ByVal picture_widget As Widget Ptr, ByVal width_value As Integer, _
    ByVal height_value As Integer, ByVal inset_x As Integer, _
    ByVal inset_y As Integer _
) As Integer
    Dim As PictureBoxData Ptr picture_data

    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    If width_value < 0 OrElse height_value < 0 OrElse _
       width_value > PIXELSURFACE_MAX_DIMENSION OrElse _
       height_value > PIXELSURFACE_MAX_DIMENSION OrElse _
       CULngInt(width_value) * CULngInt(height_value) > _
           PIXELSURFACE_MAX_PIXELS OrElse _
       inset_x < 0 OrElse inset_y < 0 OrElse _
       inset_x > 65536 OrElse inset_y > 65536 Then Return 0
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    If picture_data->pixel_surface.colors <> 0 OrElse _
       picture_data->pixel_surface.occupied <> 0 Then
        If pixelsurface_Resize( _
            picture_data->pixel_surface, width_value, height_value _
        ) = 0 Then Return 0
    End If
    picture_data->pixel_width = width_value
    picture_data->pixel_height = height_value
    picture_data->pixel_inset_x = inset_x
    picture_data->pixel_inset_y = inset_y
    picture_data->pixel_tracks_client = 0
    Return -1
End Function


Function picturebox_SetPixelCanvasToClient( _
    ByVal picture_widget As Widget Ptr, ByVal inset_x As Integer, _
    ByVal inset_y As Integer _
) As Integer
    Dim As PictureBoxData Ptr picture_data
    Dim As Integer client_inset
    Dim As Integer canvas_width
    Dim As Integer canvas_height

    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    If inset_x < 0 OrElse inset_y < 0 OrElse _
       inset_x > 65536 OrElse inset_y > 65536 Then Return 0
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    client_inset = picturebox_GetClientInset(picture_data->border_style)
    canvas_width = picture_widget->w - 2 * (client_inset + inset_x)
    canvas_height = picture_widget->h - 2 * (client_inset + inset_y)
    If canvas_width < 1 OrElse canvas_height < 1 OrElse _
       canvas_width > PIXELSURFACE_MAX_DIMENSION OrElse _
       canvas_height > PIXELSURFACE_MAX_DIMENSION Then Return 0
    If picturebox_SetPixelCanvas( _
        picture_widget, canvas_width, canvas_height, inset_x, inset_y _
    ) = 0 Then Return 0
    picture_data->pixel_tracks_client = -1
    Return -1
End Function


Function picturebox_SetPixel( _
    ByVal picture_widget As Widget Ptr, ByVal x As Integer, ByVal y As Integer, _
    ByVal color_value As ULong _
) As Integer
    Dim As PictureBoxData Ptr picture_data

    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    picturebox_SynchronizePixelCanvas picture_widget
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    If x < 0 OrElse y < 0 OrElse x >= picture_data->pixel_width OrElse _
       y >= picture_data->pixel_height Then Return -1
    If pixelsurface_Resize( _
        picture_data->pixel_surface, picture_data->pixel_width, _
        picture_data->pixel_height _
    ) = 0 Then Return 0
    Return pixelsurface_SetPixel(picture_data->pixel_surface, x, y, color_value)
End Function


Function picturebox_DrawLine( _
    ByVal picture_widget As Widget Ptr, ByVal start_x As Integer, ByVal start_y As Integer, _
    ByVal end_x As Integer, ByVal end_y As Integer, ByVal color_value As ULong _
) As Integer
    Dim As PictureBoxData Ptr picture_data

    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    If picturebox_SynchronizePixelCanvas(picture_widget) = 0 Then Return 0
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    If picture_data->pixel_width < 1 OrElse picture_data->pixel_height < 1 Then Return -1
    If pixelsurface_Resize( _
        picture_data->pixel_surface, picture_data->pixel_width, _
        picture_data->pixel_height _
    ) = 0 Then Return 0
    Return pixelsurface_DrawLine( _
        picture_data->pixel_surface, start_x, start_y, end_x, end_y, color_value)
End Function


Function picturebox_DrawStyledLine( _
    ByVal picture_widget As Widget Ptr, ByVal start_x As Integer, ByVal start_y As Integer, _
    ByVal end_x As Integer, ByVal end_y As Integer, ByVal color_value As ULong, _
    ByVal style_value As ULong _
) As Integer
    Dim As PictureBoxData Ptr picture_data

    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    If picturebox_SynchronizePixelCanvas(picture_widget) = 0 Then Return 0
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    If picture_data->pixel_width < 1 OrElse picture_data->pixel_height < 1 Then Return -1
    If pixelsurface_Resize( _
        picture_data->pixel_surface, picture_data->pixel_width, _
        picture_data->pixel_height _
    ) = 0 Then Return 0
    Return pixelsurface_DrawStyledLine( _
        picture_data->pixel_surface, start_x, start_y, end_x, end_y, _
        color_value, style_value)
End Function


Function picturebox_DrawStyledRectangle( _
    ByVal picture_widget As Widget Ptr, ByVal start_x As Integer, _
    ByVal start_y As Integer, ByVal end_x As Integer, ByVal end_y As Integer, _
    ByVal color_value As ULong, ByVal filled As Integer, _
    ByVal style_value As ULong _
) As Integer
    Dim As PictureBoxData Ptr picture_data

    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    If picturebox_SynchronizePixelCanvas(picture_widget) = 0 Then Return 0
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    If picture_data->pixel_width < 1 OrElse picture_data->pixel_height < 1 Then Return -1
    If pixelsurface_Resize( _
        picture_data->pixel_surface, picture_data->pixel_width, _
        picture_data->pixel_height _
    ) = 0 Then Return 0
    Return pixelsurface_DrawStyledRectangle( _
        picture_data->pixel_surface, start_x, start_y, end_x, end_y, _
        color_value, filled, style_value)
End Function


Function picturebox_DrawRectangle( _
    ByVal picture_widget As Widget Ptr, ByVal start_x As Integer, _
    ByVal start_y As Integer, ByVal end_x As Integer, ByVal end_y As Integer, _
    ByVal color_value As ULong, ByVal filled As Integer _
) As Integer
    Dim As PictureBoxData Ptr picture_data

    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    If picturebox_SynchronizePixelCanvas(picture_widget) = 0 Then Return 0
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    If picture_data->pixel_width < 1 OrElse picture_data->pixel_height < 1 Then Return -1
    If pixelsurface_Resize( _
        picture_data->pixel_surface, picture_data->pixel_width, _
        picture_data->pixel_height _
    ) = 0 Then Return 0
    Return pixelsurface_DrawRectangle( _
        picture_data->pixel_surface, start_x, start_y, end_x, end_y, _
        color_value, filled)
End Function


Function picturebox_DrawCircle( _
    ByVal picture_widget As Widget Ptr, ByVal center_x As Integer, _
    ByVal center_y As Integer, ByVal radius As Integer, _
    ByVal color_value As ULong _
) As Integer
    Dim As PictureBoxData Ptr picture_data

    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    If picturebox_SynchronizePixelCanvas(picture_widget) = 0 Then Return 0
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    If picture_data->pixel_width < 1 OrElse picture_data->pixel_height < 1 Then Return -1
    If pixelsurface_Resize( _
        picture_data->pixel_surface, picture_data->pixel_width, _
        picture_data->pixel_height _
    ) = 0 Then Return 0
    Return pixelsurface_DrawCircle( _
        picture_data->pixel_surface, center_x, center_y, radius, color_value)
End Function


Function picturebox_DrawEllipse( _
    ByVal picture_widget As Widget Ptr, ByVal center_x As Integer, _
    ByVal center_y As Integer, ByVal radius As Integer, _
    ByVal aspect_value As Double, ByVal start_angle As Double, _
    ByVal end_angle As Double, ByVal filled As Integer, _
    ByVal color_value As ULong _
) As Integer
    Dim As PictureBoxData Ptr picture_data

    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    If picturebox_SynchronizePixelCanvas(picture_widget) = 0 Then Return 0
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    If picture_data->pixel_width < 1 OrElse picture_data->pixel_height < 1 Then Return -1
    If pixelsurface_Resize( _
        picture_data->pixel_surface, picture_data->pixel_width, _
        picture_data->pixel_height _
    ) = 0 Then Return 0
    Return pixelsurface_DrawEllipse( _
        picture_data->pixel_surface, center_x, center_y, radius, aspect_value, _
        start_angle, end_angle, filled, color_value)
End Function


Function picturebox_ReadPixel( _
    ByVal picture_widget As Widget Ptr, ByVal x As Integer, ByVal y As Integer, _
    ByRef color_value As ULong, ByRef occupied As Integer _
) As Integer
    color_value = 0
    occupied = 0
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    picturebox_SynchronizePixelCanvas picture_widget
    Return pixelsurface_ReadPixel( _
        Cast(PictureBoxData Ptr, picture_widget->data)->pixel_surface, _
        x, y, color_value, occupied _
    )
End Function


Sub picturebox_ClearPixels(ByVal picture_widget As Widget Ptr)
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Exit Sub
    pixelsurface_Release Cast(PictureBoxData Ptr, picture_widget->data)->pixel_surface
End Sub

Function picturebox_SetText( _
    ByVal picture_widget As Widget Ptr, _
    ByRef display_text As Const String _
) As Integer
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    Cast(PictureBoxData Ptr, picture_widget->data)->text = display_text
    Return -1
End Function


Function picturebox_SetBorderStyle( _
    ByVal picture_widget As Widget Ptr, _
    ByVal border_style As Integer _
) As Integer
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    If picturebox_IsValidBorderStyle(border_style) = 0 Then Return 0

    Cast(PictureBoxData Ptr, picture_widget->data)->border_style = border_style
    picturebox_ApplyChildClip picture_widget, border_style
    Return -1
End Function


Function picturebox_SetBackgroundColor( _
    ByVal picture_widget As Widget Ptr, _
    ByVal background_color As ULong _
) As Integer
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    With *Cast(PictureBoxData Ptr, picture_widget->data)
        .background_color = background_color
        .background_color_override = -1
    End With
    Return -1
End Function


Function picturebox_ClearBackgroundColor( _
    ByVal picture_widget As Widget Ptr _
) As Integer
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    Cast(PictureBoxData Ptr, picture_widget->data)->background_color_override = 0
    Return -1
End Function


Function picturebox_GetBackgroundColor( _
    ByVal picture_widget As Widget Ptr, _
    ByRef background_color As ULong _
) As Integer
    Dim As PictureBoxData Ptr picture_data

    background_color = 0
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    If picture_data->background_color_override = 0 Then Return 0
    background_color = picture_data->background_color
    Return -1
End Function


Function picturebox_SetForegroundColor( _
    ByVal picture_widget As Widget Ptr, _
    ByVal foreground_color As ULong _
) As Integer
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    With *Cast(PictureBoxData Ptr, picture_widget->data)
        .foreground_color = foreground_color
        .foreground_color_override = -1
    End With
    Return -1
End Function


Function picturebox_ClearForegroundColor( _
    ByVal picture_widget As Widget Ptr _
) As Integer
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    Cast(PictureBoxData Ptr, picture_widget->data)->foreground_color_override = 0
    Return -1
End Function


Function picturebox_GetForegroundColor( _
    ByVal picture_widget As Widget Ptr, _
    ByRef foreground_color As ULong _
) As Integer
    Dim As PictureBoxData Ptr picture_data

    foreground_color = 0
    If picture_widget = 0 OrElse picture_widget->data = 0 Then Return 0
    picture_data = Cast(PictureBoxData Ptr, picture_widget->data)
    If picture_data->foreground_color_override = 0 Then Return 0
    foreground_color = picture_data->foreground_color
    Return -1
End Function

/' end of picturebox.bas '/
