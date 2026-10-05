/'
    Project: omaGUI
    File: retained_render.bas
    Purpose: Keep unchanged scene pixels and collect bounded repaint regions.
    Responsibilities: Observe GUI-thread visual keys, retain old widget bounds,
        merge overlapping damage and recover from layout or registry changes.
    This file contains no input dispatch, widget drawing or page switching.
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

Sub gui_InvalidateRect(ByVal x As Integer, ByVal y As Integer, _
    ByVal widthValue As Integer, ByVal heightValue As Integer)
    Dim As Integer screenWidth, screenHeight
    backend_GetSize screenWidth, screenHeight
    ' Imported line/shape widgets may use negative or zero extents. Match the
    ' ordinary scene renderer's normalized rectangle before clipping damage.
    Dim As LongInt leftEdge = x, topEdge = y
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
            rightEdge = x + widthValue
            bottomEdge = y + heightValue
            If r->x < x Then x = r->x
            If r->y < y Then y = r->y
            If r->x + r->w > rightEdge Then rightEdge = r->x + r->w
            If r->y + r->h > bottomEdge Then bottomEdge = r->y + r->h
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

Private Function gui_RetainedPaletteKey(ByRef themePalette As Const GUI_Theme) As String
    Dim As String themeKey
    #define RETAIN_THEME_FIELD(field) themeKey &= MKLongInt(themePalette.field)
    RETAIN_THEME_FIELD(bg_face)
    RETAIN_THEME_FIELD(bg_widget)
    RETAIN_THEME_FIELD(bg_dark)
    RETAIN_THEME_FIELD(bg_light)
    RETAIN_THEME_FIELD(text_main)
    RETAIN_THEME_FIELD(text_select)
    RETAIN_THEME_FIELD(bg_select)
    RETAIN_THEME_FIELD(win_border)
    RETAIN_THEME_FIELD(menu_background)
    RETAIN_THEME_FIELD(menu_text)
    RETAIN_THEME_FIELD(menu_selected_background)
    RETAIN_THEME_FIELD(menu_selected_text)
    RETAIN_THEME_FIELD(menu_separator)
    RETAIN_THEME_FIELD(menu_disabled_text)
    RETAIN_THEME_FIELD(control_style)
    RETAIN_THEME_FIELD(title_background)
    RETAIN_THEME_FIELD(title_text)
    RETAIN_THEME_FIELD(classic_access_text)
    RETAIN_THEME_FIELD(classic_active_border_background)
    RETAIN_THEME_FIELD(classic_active_border_text)
    RETAIN_THEME_FIELD(classic_command_text)
    RETAIN_THEME_FIELD(classic_disabled_text)
    RETAIN_THEME_FIELD(classic_menu_background)
    RETAIN_THEME_FIELD(classic_menu_text)
    RETAIN_THEME_FIELD(classic_menu_selected_background)
    RETAIN_THEME_FIELD(classic_menu_selected_text)
    RETAIN_THEME_FIELD(classic_scrollbar_background)
    RETAIN_THEME_FIELD(classic_scrollbar_text)
    RETAIN_THEME_FIELD(syntax_keyword_color)
    RETAIN_THEME_FIELD(syntax_comment_color)
    RETAIN_THEME_FIELD(syntax_string_color)
    RETAIN_THEME_FIELD(syntax_number_color)
    RETAIN_THEME_FIELD(syntax_preprocessor_color)
    RETAIN_THEME_FIELD(syntax_type_color)
    RETAIN_THEME_FIELD(syntax_command_color)
    RETAIN_THEME_FIELD(syntax_procedure_color)
    RETAIN_THEME_FIELD(syntax_macro_color)
    RETAIN_THEME_FIELD(syntax_variable_color)
    RETAIN_THEME_FIELD(syntax_constant_color)
    RETAIN_THEME_FIELD(syntax_member_color)
    RETAIN_THEME_FIELD(syntax_label_color)
    RETAIN_THEME_FIELD(syntax_object_color)
    RETAIN_THEME_FIELD(mode)
    #undef RETAIN_THEME_FIELD
    Return themeKey
End Function

Function gui_PrepareRetainedFrame() As Integer
    Dim As Integer screenWidth, screenHeight
    backend_GetSize screenWidth, screenHeight
    gui_ResolveLayout
    Dim As String themeKey
    ' Palette and font replacements can affect every widget, including
    ' controls whose own content key has not changed.
    themeKey = MKLongInt(backend_GetFontGeneration()) & gui_RetainedPaletteKey(current_theme) & _
        MKLongInt(theme_GetClassicShadow()) & MKLongInt(theme_GetClassicThreeD())
    If screenWidth <> gui_RetainedWidth OrElse screenHeight <> gui_RetainedHeight _
       OrElse themeKey <> gui_RetainedTheme Then gui_InvalidateAll
    gui_RetainedWidth = screenWidth
    gui_RetainedHeight = screenHeight
    gui_RetainedTheme = themeKey
    Dim As Widget Ptr w = widget_list_head
    While w <> 0
        Dim As String key
        If w->evis <> 0 Then
            ' Legacy renderers may animate or draw decorations outside their
            ' nominal bounds. Without an observation contract, preserve a
            ' complete scene repaint rather than leave stale pixels behind.
            If w->render <> 0 AndAlso w->render_observation = 0 Then gui_InvalidateAll
            ' Native-style windows can draw shadows outside their own bounds.
            ' Keep full repainting while one is visible until it supplies an
            ' explicit damage contract for those decorations.
            If w->is_window <> 0 Then gui_InvalidateAll
            Dim As Integer clipX, clipY, clipWidth, clipHeight
            gui_GetWidgetRenderClip w, clipX, clipY, clipWidth, clipHeight
            key = MKLongInt(clipX) & MKLongInt(clipY) & _
                MKLongInt(clipWidth) & MKLongInt(clipHeight)
            Dim As Widget Ptr owner = w
            Dim As Integer ownerDepth
            While owner <> 0 AndAlso ownerDepth < GUI_LAYOUT_PARENT_GUARD
                If owner->appearance <> 0 Then
                    key &= gui_RetainedPaletteKey(*owner->appearance)
                    Exit While
                End If
                owner = owner->parent
                ownerDepth += 1
            Wend
            ' Convert addresses through the native integer width first. ARM32
            ' rejects a direct pointer-to-LongInt cast; cache fields stay 8 bytes.
            key &= MKLongInt(w->een) & MKLongInt(w->has_focus) & _
                MKLongInt(gui_KeyboardFocusVisible) & MKLongInt(CLngInt(CUInt(w->render)))
            If w->render_observation <> 0 Then key &= w->render_observation(w)
        End If
        Dim As Integer changed = IIf(w->retained_valid = 0 OrElse _
            w->retained_visible <> w->evis OrElse w->retained_x <> w->ax OrElse _
            w->retained_y <> w->ay OrElse w->retained_w <> w->w OrElse _
            w->retained_h <> w->h OrElse key <> w->retained_key OrElse _
            (w->evis <> 0 AndAlso w->render_observation = 0), -1, 0)
        If changed <> 0 Then
            Dim As Integer narrowDamage, damageX, damageY, damageWidth, damageHeight
            If w->render_damage <> 0 AndAlso w->retained_valid <> 0 AndAlso _
               w->evis <> 0 AndAlso w->retained_visible = w->evis AndAlso _
               w->retained_x = w->ax AndAlso w->retained_y = w->ay AndAlso _
               w->retained_w = w->w AndAlso w->retained_h = w->h Then
                narrowDamage = w->render_damage(w, w->retained_key, key, _
                    damageX, damageY, damageWidth, damageHeight)
            End If
            If narrowDamage <> 0 Then
                gui_InvalidateRect damageX, damageY, damageWidth, damageHeight
            Else
                If w->retained_visible <> 0 Then gui_InvalidateRect _
                    w->retained_x, w->retained_y, w->retained_w, w->retained_h
                If w->evis <> 0 Then gui_InvalidateRect w->ax, w->ay, w->w, w->h
            End If
        End If
        w->retained_key = key
        w->retained_valid = -1
        w->retained_visible = w->evis
        w->retained_x = w->ax: w->retained_y = w->ay
        w->retained_w = w->w: w->retained_h = w->h
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
