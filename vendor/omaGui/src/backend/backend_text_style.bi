/'
    Project: omaGUI
    File: backend_text_style.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for backend_text_style.
    Purpose: Render optional styles using the embedded bitmap glyph coverage.
    Responsibilities:
        - synthesize bold and italic without platform font dependencies
        - draw underline and strikeout within the existing line height
        - preserve advance widths, clipping, and the ordinary rendering path

    This file intentionally does NOT contain:

        - widget state or text layout
    Private implementation include for backend_gfxlib.bas. Drawing stays on the
    GUI thread and borrows immutable glyph tables from backend_FontGlyph.
'/
#ifndef __BACKEND_TEXT_STYLE_BI__
#define __BACKEND_TEXT_STYLE_BI__

Sub backend_PrintStyled( _
    ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, _
    ByVal text As String, ByVal text_style As Integer, _
    ByVal font_id As Integer _
)
    ' Drawable tests own a real framebuffer; only screenless mode omits text.
    ' fblint: disable-next-line FBL310 -- state is declared by the including backend module.
    If backend_HeadlessActive = BACKEND_HEADLESS Then Exit Sub
    If (text_style And Not BACKEND_TEXT_STYLE_ALL) <> 0 Then Exit Sub
    If text_style = BACKEND_TEXT_STYLE_NORMAL Then
        backend_PrintFont x, y, clr, text, font_id
        Exit Sub
    End If
    ' Match the bounded coordinate policy used by the backend's byte renderer.
    ' Every subsequent addition is a glyph dimension, at most 255 pixels.
    If x < -1000000 OrElse x > 1000000 OrElse y < -1000000 OrElse y > 1000000 Then Exit Sub
    Dim As Integer clip_x, clip_y, clip_width, clip_height
    backend_GetClip clip_x, clip_y, clip_width, clip_height
    If clip_width <= 0 OrElse clip_height <= 0 Then Exit Sub
    Dim As Integer current_x = x
    Dim As Integer font_height = backend_GetTextHeightFont(font_id)
    Dim As Integer bold_extra = IIf(text_style And BACKEND_TEXT_STYLE_BOLD, 1, 0)
    For character_index As Integer = 0 To Len(text) - 1
        If current_x >= clip_x + clip_width Then Exit For
        Dim As Integer character_code = Asc(text, character_index + 1)
        Dim As UByte Ptr glyph = backend_FontGlyph(font_id, character_code)
        If glyph = 0 Then Continue For
        ' The embedded generator owns each block: byte width, byte height,
        ' then exactly width * height row-major coverage bytes. Bold's extra
        ' column reads only the preceding source pixel, never beyond the block.
        Dim As Integer glyph_width = glyph[0]
        Dim As Integer glyph_height = glyph[1]
        ' Italic rows move right by one pixel for each four rows above the
        ' baseline. Overhang is ink only; caret and selection advances stay put.
        Dim As Integer overhang = bold_extra
        If text_style And BACKEND_TEXT_STYLE_ITALIC Then overhang += font_height \ 4
        Dim As Integer render_height = IIf(glyph_height > font_height, glyph_height, font_height)
        If current_x + glyph_width + overhang > clip_x AndAlso y + render_height > clip_y AndAlso y < clip_y + clip_height Then
            For pixel_y As Integer = 0 To glyph_height - 1
                If y + pixel_y < clip_y OrElse y + pixel_y >= clip_y + clip_height Then Continue For
                Dim As Integer row_shift = 0
                If (text_style And BACKEND_TEXT_STYLE_ITALIC) AndAlso pixel_y < font_height Then row_shift = (font_height - 1 - pixel_y) \ 4
                For pixel_x As Integer = 0 To glyph_width - 1 + bold_extra
                    Dim As Integer alpha = 0
                    If pixel_x < glyph_width Then alpha = glyph[2 + pixel_y * glyph_width + pixel_x]
                    If bold_extra AndAlso pixel_x > 0 Then
                        Dim As Integer left_alpha = glyph[2 + pixel_y * glyph_width + pixel_x - 1]
                        ' Union coverage once, rather than darkening overlapping
                        ' antialiased pixels by painting the same glyph twice.
                        If left_alpha > alpha Then alpha = left_alpha
                    End If
                    If alpha > 0 Then backend_PSetAlpha current_x + pixel_x + row_shift, y + pixel_y, clr, alpha
                Next pixel_x
            Next pixel_y
            ' Descenders may have taller bitmaps. Decorations must use one
            ' face-wide position so a mixed run does not acquire a wavy line.
            If glyph_width > 0 AndAlso font_height > 1 Then
                If text_style And BACKEND_TEXT_STYLE_UNDERLINE Then _
                    backend_Line current_x, y + font_height - 2, current_x + glyph_width - 1, y + font_height - 2, clr
                If text_style And BACKEND_TEXT_STYLE_STRIKEOUT Then _
                    backend_Line current_x, y + font_height \ 2, current_x + glyph_width - 1, y + font_height \ 2, clr
            End If
        End If
        current_x += glyph_width
    Next character_index
End Sub

#endif
/' end of backend_text_style.bi '/
