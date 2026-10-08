/'
    Project: omaGUI
    File: retained_render.bas
    Purpose: Keep unchanged scene pixels and collect bounded repaint regions.
    Responsibilities: Observe GUI-thread visual keys, retain old widget bounds,
        merge overlapping damage and recover from layout or registry changes.
    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Implementation unit assembled by omaGUI.bi when OMAGUI_IMPLEMENTATION is defined.

    This file intentionally does NOT contain: input dispatch, widget drawing or page switching.
'/

' This implementation is included by widgets.bas and shares its registry.
' Keys are observations, not hashes: equality cannot hide a hash collision.
' An observer must be read-only and must not alter the widget registry.
Const GUI_DAMAGE_CAPACITY As Integer = 64
Private Type GUI_DamageRect
    As Integer x, y, w, h
End Type
Private Dim Shared As GUI_DamageRect gui_Damage(0 To GUI_DAMAGE_CAPACITY - 1)
Private Dim Shared As Integer gui_DamageCount
Private Dim Shared As Integer gui_DamageFull = -1
Private Dim Shared As Integer gui_RetainedWidth, gui_RetainedHeight
Private Dim Shared As String gui_RetainedTheme

Sub gui_InvalidateAll()
    gui_DamageFull = -1
End Sub

Sub gui_SetRenderObservationMatcher(ByVal w As Widget Ptr, _
    ByVal matchHandler As Function(ByVal As Widget Ptr, ByRef As Const String, _
        ByVal As Integer) As Integer)
    If w = 0 Then Exit Sub
    ' A matcher is valid only for the observer it was written to qualify.
    ' Both callbacks are read-only GUI-thread calls and may not alter registry
    ' membership. Retained bytes remain owned by the manager until they return.
    w->render_observation_match = matchHandler
    w->render_match_owner = w->render_observation
    w->retained_valid = 0
End Sub

Sub gui_SetRenderBoundsHandler(ByVal w As Widget Ptr, _
    ByVal boundsHandler As Function(ByVal As Widget Ptr, ByRef As Integer, _
        ByRef As Integer, ByRef As Integer, ByRef As Integer) As Integer)
    If w = 0 Then Exit Sub
    w->render_bounds = boundsHandler
    w->render_bounds_owner = w->render
    w->retained_valid = 0
End Sub

Sub gui_SetOpaqueRenderBoundsHandler(ByVal w As Widget Ptr, _
    ByVal boundsHandler As Function(ByVal As Widget Ptr, ByRef As Integer, _
        ByRef As Integer, ByRef As Integer, ByRef As Integer) As Integer)
    If w = 0 Then Exit Sub
    ' Bind to this painter only. Replacing it declines the opacity contract.
    w->render_opaque_bounds = boundsHandler
    w->render_opaque_owner = w->render
End Sub

Sub gui_InvalidateRect(ByVal x As Integer, ByVal y As Integer, _
    ByVal widthValue As Integer, ByVal heightValue As Integer)
    Dim As Integer screenWidth, screenHeight
    backend_GetSize screenWidth, screenHeight
    ' Imported line/shape widgets may use negative or zero extents. Match the
    ' ordinary scene renderer's normalized rectangle before clipping damage.
    Dim As LongInt leftEdge = x
    Dim As LongInt topEdge = y
    Dim As LongInt rightEdge = CLngInt(x) + widthValue
    Dim As LongInt bottomEdge = CLngInt(y) + heightValue
    If rightEdge < leftEdge Then Swap rightEdge, leftEdge
    If bottomEdge < topEdge Then Swap bottomEdge, topEdge
    If rightEdge = leftEdge Then rightEdge += 1
    If bottomEdge = topEdge Then bottomEdge += 1
    If leftEdge < 0 Then leftEdge = 0
    If topEdge < 0 Then topEdge = 0
    If rightEdge > screenWidth Then rightEdge = screenWidth
    If bottomEdge > screenHeight Then bottomEdge = screenHeight
    If rightEdge <= leftEdge OrElse bottomEdge <= topEdge Then Exit Sub
    x = leftEdge: y = topEdge
    widthValue = rightEdge - leftEdge
    heightValue = bottomEdge - topEdge
    ' Merge only overlaps. Distant toolbar/caret rectangles must not turn
    ' into a full-editor repaint merely because they changed together.
    Dim As Integer index
    While index < gui_DamageCount
        Dim As GUI_DamageRect Ptr r = @gui_Damage(index)
        If x < r->x + r->w AndAlso y < r->y + r->h AndAlso _
           x + widthValue > r->x AndAlso y + heightValue > r->y Then
            Dim As LongInt mergedLeft = x
            Dim As LongInt mergedTop = y
            rightEdge = x + widthValue
            bottomEdge = y + heightValue
            If r->x < mergedLeft Then mergedLeft = r->x
            If r->y < mergedTop Then mergedTop = r->y
            If r->x + r->w > rightEdge Then rightEdge = r->x + r->w
            If r->y + r->h > bottomEdge Then bottomEdge = r->y + r->h
            ' Crossing thin strips form an L shape. Their bounding rectangle
            ' can cover most of an editor even though very few pixels changed.
            ' Keep both regions when merging would increase the painted area.
            Dim As LongInt mergedArea = (rightEdge - mergedLeft) * (bottomEdge - mergedTop)
            Dim As LongInt firstArea = CLngInt(widthValue) * heightValue
            Dim As LongInt secondArea = CLngInt(r->w) * r->h
            If mergedArea - firstArea > secondArea Then
                index += 1
                Continue While
            End If
            x = CInt(mergedLeft)
            y = CInt(mergedTop)
            widthValue = rightEdge - x
            heightValue = bottomEdge - y
            gui_DamageCount -= 1
            gui_Damage(index) = gui_Damage(gui_DamageCount)
            index = 0
        Else
            index += 1
        End If
    Wend
    If gui_DamageCount = GUI_DAMAGE_CAPACITY Then
        gui_InvalidateAll
        Exit Sub
    End If
    With gui_Damage(gui_DamageCount)
        .x = x: .y = y: .w = widthValue: .h = heightValue
    End With
    gui_DamageCount += 1
End Sub

' -------------------------------------------------------------------------
' Exact visual observation fields
' -------------------------------------------------------------------------
Private Type GUI_RetainedPaletteFields
    As LongInt values(0 To 45)
End Type
#assert SizeOf(GUI_RetainedPaletteFields) = 46 * SizeOf(LongInt)
Private Type GUI_RetainedPrefixFields
    As LongInt values(0 To 7)
End Type
#assert SizeOf(GUI_RetainedPrefixFields) = 8 * SizeOf(LongInt)
Private Sub gui_RetainedFillPalette(ByRef themePalette As Const GUI_Theme, _
    ByRef fields As GUI_RetainedPaletteFields)
    fields.values(0) = themePalette.bg_face
    fields.values(1) = themePalette.bg_widget
    fields.values(2) = themePalette.bg_dark
    fields.values(3) = themePalette.bg_light
    fields.values(4) = themePalette.text_main
    fields.values(5) = themePalette.text_select
    fields.values(6) = themePalette.bg_select
    fields.values(7) = themePalette.win_border
    fields.values(8) = themePalette.menu_background
    fields.values(9) = themePalette.menu_text
    fields.values(10) = themePalette.menu_selected_background
    fields.values(11) = themePalette.menu_selected_text
    fields.values(12) = themePalette.menu_separator
    fields.values(13) = themePalette.menu_disabled_text
    fields.values(14) = themePalette.control_style
    fields.values(15) = themePalette.title_background
    fields.values(16) = themePalette.title_text
    fields.values(17) = themePalette.classic_access_text
    fields.values(18) = themePalette.classic_active_border_background
    fields.values(19) = themePalette.classic_active_border_text
    fields.values(20) = themePalette.classic_command_text
    fields.values(21) = themePalette.classic_disabled_text
    fields.values(22) = themePalette.classic_menu_background
    fields.values(23) = themePalette.classic_menu_text
    fields.values(24) = themePalette.classic_menu_selected_background
    fields.values(25) = themePalette.classic_menu_selected_text
    fields.values(26) = themePalette.classic_scrollbar_background
    fields.values(27) = themePalette.classic_scrollbar_text
    fields.values(28) = themePalette.syntax_keyword_color
    fields.values(29) = themePalette.syntax_comment_color
    fields.values(30) = themePalette.syntax_string_color
    fields.values(31) = themePalette.syntax_number_color
    fields.values(32) = themePalette.syntax_preprocessor_color
    fields.values(33) = themePalette.syntax_type_color
    fields.values(34) = themePalette.syntax_command_color
    fields.values(35) = themePalette.syntax_procedure_color
    fields.values(36) = themePalette.syntax_macro_color
    fields.values(37) = themePalette.syntax_variable_color
    fields.values(38) = themePalette.syntax_constant_color
    fields.values(39) = themePalette.syntax_member_color
    fields.values(40) = themePalette.syntax_label_color
    fields.values(41) = themePalette.syntax_object_color
    fields.values(42) = themePalette.mode
    fields.values(43) = themePalette.panel_face
    fields.values(44) = themePalette.accent_secondary
    fields.values(45) = themePalette.visual_style
End Sub

Private Function gui_RetainedPaletteKey(ByRef themePalette As Const GUI_Theme) As String
    Dim As GUI_RetainedPaletteFields fields
    gui_RetainedFillPalette themePalette, fields
    Dim As String result = String(SizeOf(fields), 0)
    If Len(result) <> SizeOf(fields) Then
        gui_InvalidateAll
        Return ""
    End If
    memcpy StrPtr(result), @fields.values(0), SizeOf(fields)
    Return result
End Function

' These observations are native MKLongInt bytes, not hashes or raw GUI_Theme
' structures. Compare only named fields so padding cannot hide a visual change.
' All pointers are borrowed for the current read-only GUI-thread call.
Private Function gui_RetainedThemeMatches(ByRef key As Const String) As Integer
    Const paletteBytes As Integer = 46 * SizeOf(LongInt)
    Const scalarBytes As Integer = SizeOf(LongInt)
    ' Font generation, named palette fields, shadow and 3D flags, in order.
    If Len(key) <> paletteBytes + 3 * SizeOf(LongInt) Then Return 0
    Dim As GUI_RetainedPaletteFields fields
    gui_RetainedFillPalette current_theme, fields
    Dim As LongInt generation = CLngInt(backend_GetFontGeneration())
    Dim As LongInt shadowValue = theme_GetClassicShadow()
    Dim As LongInt threeDValue = theme_GetClassicThreeD()
    If oma_BytesEqual(StrPtr(key), @generation, scalarBytes) = 0 Then Return 0
    If oma_BytesEqual(StrPtr(key) + scalarBytes, @fields.values(0), paletteBytes) = 0 Then Return 0
    If oma_BytesEqual(StrPtr(key) + scalarBytes + paletteBytes, @shadowValue, scalarBytes) = 0 Then Return 0
    Return oma_BytesEqual(StrPtr(key) + 2 * scalarBytes + paletteBytes, @threeDValue, scalarBytes)
End Function

Private Sub gui_RetainedFillPrefix(ByVal w As Widget Ptr, ByVal clipX As Integer, _
    ByVal clipY As Integer, ByVal clipWidth As Integer, ByVal clipHeight As Integer, _
    ByRef fields As GUI_RetainedPrefixFields)
    fields.values(0) = clipX
    fields.values(1) = clipY
    fields.values(2) = clipWidth
    fields.values(3) = clipHeight
    fields.values(4) = w->een
    fields.values(5) = w->has_focus
    fields.values(6) = gui_KeyboardFocusVisible
    ' Widen through the native unsigned width. ARM32 cannot cast a pointer
    ' directly to LongInt; the retained key still stores an eight-byte value.
    fields.values(7) = CLngInt(CUInt(w->render))
End Sub

Private Function gui_RetainedPrefixMatches(ByVal w As Widget Ptr, _
    ByVal themePalette As Const GUI_Theme Ptr, ByVal clipX As Integer, ByVal clipY As Integer, _
    ByVal clipWidth As Integer, ByVal clipHeight As Integer, ByVal offset As Integer) As Integer
    Const halfBytes As Integer = 4 * SizeOf(LongInt)
    Const paletteBytes As Integer = 46 * SizeOf(LongInt)
    Dim As Integer observedPaletteBytes = IIf(themePalette = 0, 0, paletteBytes)
    If w = 0 Then Return 0
    If offset <> halfBytes * 2 + observedPaletteBytes OrElse offset > Len(w->retained_key) Then Return 0
    Dim As GUI_RetainedPrefixFields fields
    gui_RetainedFillPrefix w, clipX, clipY, clipWidth, clipHeight, fields
    If oma_BytesEqual(StrPtr(w->retained_key), @fields.values(0), halfBytes) = 0 Then Return 0
    If themePalette <> 0 Then
        Dim As GUI_RetainedPaletteFields paletteFields
        gui_RetainedFillPalette *themePalette, paletteFields
        If oma_BytesEqual(StrPtr(w->retained_key) + halfBytes, @paletteFields.values(0), paletteBytes) = 0 Then Return 0
    End If
    ' The comparison returns a boolean; stack addresses do not escape.
    ' fblint: disable-next-line FBL316 REASON: oma_BytesEqual consumes these borrowed spans and returns an integer comparison.
    Return oma_BytesEqual(StrPtr(w->retained_key) + halfBytes + observedPaletteBytes, @fields.values(4), halfBytes)
End Function

Private Function gui_RetainedPrefixKey(ByVal w As Widget Ptr, _
    ByVal themePalette As Const GUI_Theme Ptr, ByVal clipX As Integer, ByVal clipY As Integer, _
    ByVal clipWidth As Integer, ByVal clipHeight As Integer) As String
    Const halfBytes As Integer = 4 * SizeOf(LongInt)
    Const paletteBytes As Integer = 46 * SizeOf(LongInt)
    Dim As Integer observedPaletteBytes = IIf(themePalette = 0, 0, paletteBytes)
    If w = 0 Then Return ""
    Dim As GUI_RetainedPrefixFields fields
    gui_RetainedFillPrefix w, clipX, clipY, clipWidth, clipHeight, fields
    Dim As String result = String(halfBytes * 2 + observedPaletteBytes, 0)
    If Len(result) <> halfBytes * 2 + observedPaletteBytes Then
        gui_InvalidateAll
        Return ""
    End If
    memcpy StrPtr(result), @fields.values(0), halfBytes
    If themePalette <> 0 Then
        Dim As GUI_RetainedPaletteFields paletteFields
        gui_RetainedFillPalette *themePalette, paletteFields
        memcpy StrPtr(result) + halfBytes, @paletteFields.values(0), paletteBytes
    End If
    memcpy StrPtr(result) + halfBytes + observedPaletteBytes, @fields.values(4), halfBytes
    Return result
End Function

' -------------------------------------------------------------------------
' Retained frame preparation
' -------------------------------------------------------------------------
Function gui_PrepareRetainedFrame() As Integer
    Dim As Integer screenWidth, screenHeight
    backend_GetSize screenWidth, screenHeight
    gui_ResolveLayout
    Dim As Integer themeChanged
    If gui_RetainedThemeMatches(gui_RetainedTheme) = 0 Then
        Dim As String themeKey = MKLongInt(backend_GetFontGeneration()) & gui_RetainedPaletteKey(current_theme) & _
            MKLongInt(theme_GetClassicShadow()) & MKLongInt(theme_GetClassicThreeD())
        themeChanged = IIf(themeKey <> gui_RetainedTheme, -1, 0)
        gui_RetainedTheme = themeKey
    End If
    If screenWidth <> gui_RetainedWidth OrElse screenHeight <> gui_RetainedHeight OrElse themeChanged <> 0 Then gui_InvalidateAll
    gui_RetainedWidth = screenWidth
    gui_RetainedHeight = screenHeight
    Dim As Widget Ptr w = widget_list_head
    While w <> 0
        Dim As String key
        Dim As Integer observationMatched, observationOffset
        Dim As Integer paintX = w->ax
        Dim As Integer paintY = w->ay
        Dim As Integer paintWidth = w->w
        Dim As Integer paintHeight = w->h
        Dim As Integer boundsValid
        If w->evis <> 0 Then
            boundsValid = gui_GetRetainedPaintBounds(w, paintX, paintY, paintWidth, paintHeight)
            If boundsValid = 0 Then
                paintX = w->ax: paintY = w->ay: paintWidth = w->w: paintHeight = w->h
            End If
            ' Legacy renderers may animate or draw decorations outside their
            ' nominal bounds. Without an observation contract, preserve a
            ' complete scene repaint rather than leave stale pixels behind.
            If w->render <> 0 AndAlso w->render_observation = 0 Then gui_InvalidateAll
            ' Native-style windows can draw shadows outside their own bounds.
            ' A painter with a validated footprint can bound those decorations;
            ' other windows retain their complete scene repaint.
            If w->is_window <> 0 AndAlso boundsValid = 0 Then gui_InvalidateAll
            Dim As Integer clipX, clipY, clipWidth, clipHeight
            gui_GetWidgetRenderClip w, clipX, clipY, clipWidth, clipHeight
            Dim As Const GUI_Theme Ptr ownerPalette
            Dim As Widget Ptr owner = w
            Dim As Integer ownerDepth
            While owner <> 0 AndAlso ownerDepth < GUI_LAYOUT_PARENT_GUARD
                If owner->theme_override_enabled <> 0 Then
                    ownerPalette = @owner->theme_override
                    Exit While
                End If
                If owner->appearance <> 0 Then
                    ownerPalette = owner->appearance
                    Exit While
                End If
                owner = owner->parent
                ownerDepth += 1
            Wend
            observationOffset = 8 * SizeOf(LongInt)
            If ownerPalette <> 0 Then observationOffset += 46 * SizeOf(LongInt)
            If w->render_observation = 0 Then key = gui_RetainedPrefixKey(w, ownerPalette, clipX, clipY, clipWidth, clipHeight)
            If w->render_observation <> 0 Then
                If w->retained_valid <> 0 AndAlso _
                   w->render_observation_match <> 0 AndAlso _
                   w->render_match_owner = w->render_observation AndAlso _
                   w->retained_visible = w->evis AndAlso _
                   w->retained_x = w->ax AndAlso w->retained_y = w->ay AndAlso _
                   w->retained_w = w->w AndAlso w->retained_h = w->h AndAlso _
                   observationOffset = w->retained_observation_offset AndAlso _
                   observationOffset <= Len(w->retained_key) Then
                    If gui_RetainedPrefixMatches(w, ownerPalette, clipX, clipY, clipWidth, clipHeight, observationOffset) <> 0 Then _
                        observationMatched = w->render_observation_match(w, w->retained_key, observationOffset)
                End If
                If observationMatched = 0 Then
                    key = gui_RetainedPrefixKey(w, ownerPalette, clipX, clipY, clipWidth, clipHeight)
                    ' Decline later reuse if allocation could not preserve the prefix.
                    If Len(key) <> observationOffset Then observationOffset = -1
                    key &= w->render_observation(w)
                End If
            End If
        End If
        Dim As Integer changed = IIf(w->retained_valid = 0 OrElse _
            w->retained_visible <> w->evis OrElse w->retained_x <> w->ax OrElse _
            w->retained_y <> w->ay OrElse w->retained_w <> w->w OrElse _
            w->retained_h <> w->h OrElse _
            w->retained_bounds_valid <> boundsValid OrElse _
            (w->evis <> 0 AndAlso (w->retained_paint_x <> paintX OrElse _
                w->retained_paint_y <> paintY OrElse w->retained_paint_w <> paintWidth OrElse _
                w->retained_paint_h <> paintHeight)) OrElse _
            (observationMatched = 0 AndAlso key <> w->retained_key) OrElse _
            (w->evis <> 0 AndAlso w->render_observation = 0), -1, 0)
        If changed <> 0 Then
            Dim As Integer narrowDamage, damageX, damageY, damageWidth, damageHeight
            If w->render_damage <> 0 AndAlso observationMatched = 0 AndAlso w->retained_valid <> 0 AndAlso _
               w->evis <> 0 AndAlso w->retained_visible = w->evis AndAlso _
               w->retained_x = w->ax AndAlso w->retained_y = w->ay AndAlso _
               w->retained_w = w->w AndAlso w->retained_h = w->h AndAlso _
               w->retained_paint_x = paintX AndAlso w->retained_paint_y = paintY AndAlso _
               w->retained_paint_w = paintWidth AndAlso w->retained_paint_h = paintHeight Then
                narrowDamage = w->render_damage(w, w->retained_key, key, _
                    damageX, damageY, damageWidth, damageHeight)
            End If
            If narrowDamage <> 0 Then
                gui_InvalidateRect damageX, damageY, damageWidth, damageHeight
            Else
                If w->retained_visible <> 0 Then gui_InvalidateRect _
                    w->retained_paint_x, w->retained_paint_y, w->retained_paint_w, w->retained_paint_h
                If w->evis <> 0 Then gui_InvalidateRect paintX, paintY, paintWidth, paintHeight
            End If
            ' The retained key already matches. Do not copy a large key every idle frame.
            If observationMatched = 0 Then
                w->retained_key = key
                w->retained_observation_offset = observationOffset
            End If
        End If
        w->retained_valid = -1
        w->retained_visible = w->evis
        w->retained_x = w->ax: w->retained_y = w->ay
        w->retained_w = w->w: w->retained_h = w->h
        w->retained_bounds_valid = boundsValid
        w->retained_paint_x = paintX: w->retained_paint_y = paintY
        w->retained_paint_w = paintWidth: w->retained_paint_h = paintHeight
        w = w->next_widget
    Wend
    If gui_DamageFull <> 0 Then
        gui_DamageCount = 1
        With gui_Damage(0)
            .x = 0: .y = 0: .w = screenWidth: .h = screenHeight
        End With
    End If
    gui_DamageFull = 0
    Return gui_DamageCount
End Function

' -------------------------------------------------------------------------
' Damage list consumption
' -------------------------------------------------------------------------
Sub gui_GetDamageRect(ByVal index As Integer, ByRef x As Integer, _
    ByRef y As Integer, ByRef widthValue As Integer, ByRef heightValue As Integer)
    x = 0: y = 0: widthValue = 0: heightValue = 0
    If index < 0 OrElse index >= gui_DamageCount Then Exit Sub
    With gui_Damage(index)
        x = .x: y = .y: widthValue = .w: heightValue = .h
    End With
    ' The caller consumes the list in order, before preparing another frame.
    If index = gui_DamageCount - 1 Then gui_DamageCount = 0
End Sub

' end of retained_render.bas
