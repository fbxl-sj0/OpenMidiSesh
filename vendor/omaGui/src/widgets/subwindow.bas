/'
    Project: omaGUI
    ---------------

    File: subwindow.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements subwindow.bi; declarations there define the interface.

    Purpose:
        Implement a movable, resizable, ordered, closable child window.

    Responsibilities:
        - render a title bar and optional close control
        - move the window while retaining its parent-relative coordinates
        - resize sizable windows through a pointer-captured corner grip
        - keep the window inside its parent client area or GUI viewport
        - notify the owning application when close is requested
        - render an optional client-area color without changing the theme
        - retain independent title colors without changing menu selections
        - render four validated portable border modes
        - collapse and maximize windows without platform-native APIs
        - keep non-normal geometry synchronized with a resized container
        - reflow anchored descendants when the window rectangle changes
        - render and dispatch portable control-box, minimize, and maximize buttons

    This file intentionally does NOT contain:
        - registry ordering and input dispatch
        - recursive child destruction
        - platform-native window management
'/

#lang "fb"
#include once "src/widgets/subwindow.bi"
#include once "src/backend/theme.bi"

Const SUBWINDOW_TITLEBAR_HEIGHT As Integer = 20
Const SUBWINDOW_DIALOG_TITLEBAR_HEIGHT As Integer = 28
Const SUBWINDOW_TITLE_FILL_HEIGHT As Integer = 18
Const SUBWINDOW_TITLE_TEXT_X_OFFSET As Integer = 5
Const SUBWINDOW_TITLE_TEXT_Y_OFFSET As Integer = 4
Const SUBWINDOW_CLOSE_SIZE As Integer = 14
Const SUBWINDOW_CLOSE_RIGHT_INSET As Integer = 4
Const SUBWINDOW_CLOSE_TOP_INSET As Integer = 3
Const SUBWINDOW_TITLE_BUTTON_GAP As Integer = 2
Const SUBWINDOW_CLIENT_LEFT_INSET As Integer = 1
Const SUBWINDOW_CLIENT_RIGHT_INSET As Integer = 1
Const SUBWINDOW_CLIENT_BOTTOM_INSET As Integer = 1
Const SUBWINDOW_DOUBLE_BORDER_INSET As Integer = 2
Const SUBWINDOW_RESIZE_GRIP_SIZE As Integer = 12
Const SUBWINDOW_RESIZE_GRIP_LINE_STEP As Integer = 4
Const SUBWINDOW_MINIMUM_WIDTH As Integer = 48
Const SUBWINDOW_MINIMUM_HEIGHT As Integer = 32
Const SUBWINDOW_MINIMIZED_WIDTH As Integer = 180
Const SUBWINDOW_PARENT_GUARD As Integer = 64
Const SUBWINDOW_TITLE_BUTTON_CLOSE As Integer = 1
Const SUBWINDOW_TITLE_BUTTON_MAXIMIZE As Integer = 2
Const SUBWINDOW_TITLE_BUTTON_MINIMIZE As Integer = 3

' -------------------------------------------------------------------------
' Private geometry helpers
' -------------------------------------------------------------------------

Private Function subwindow_GetTitleButtonRectangle( _
    ByVal w As Widget Ptr, ByVal window_data As SubWindowData Ptr, _
    ByVal button_kind As Integer, _
    ByRef buttonX As Integer, ByRef buttonY As Integer _
) As Integer
    Dim As Integer nextX

    buttonX = 0
    buttonY = 0
    If w = 0 OrElse window_data = 0 Then Return 0
    If window_data->border_style = SUBWINDOW_BORDER_NONE Then Return 0
    If w->w < SUBWINDOW_CLOSE_RIGHT_INSET + SUBWINDOW_CLOSE_SIZE OrElse _
       w->h < SUBWINDOW_CLOSE_TOP_INSET + SUBWINDOW_CLOSE_SIZE Then Return 0

    nextX = w->ax + w->w - SUBWINDOW_CLOSE_RIGHT_INSET - _
        SUBWINDOW_CLOSE_SIZE
    buttonY = w->ay + (window_data->titlebar_height - SUBWINDOW_CLOSE_SIZE) \ 2
    If window_data->closable Then
        If button_kind = SUBWINDOW_TITLE_BUTTON_CLOSE Then
            buttonX = nextX
            Return -1
        End If
        nextX -= SUBWINDOW_CLOSE_SIZE + SUBWINDOW_TITLE_BUTTON_GAP
    End If
    If window_data->maximize_button Then
        If nextX < w->ax + 1 Then Return 0
        If button_kind = SUBWINDOW_TITLE_BUTTON_MAXIMIZE Then
            buttonX = nextX
            Return -1
        End If
        nextX -= SUBWINDOW_CLOSE_SIZE + SUBWINDOW_TITLE_BUTTON_GAP
    End If
    If window_data->minimize_button AndAlso _
       window_data->window_state <> SUBWINDOW_STATE_MINIMIZED Then
        If nextX < w->ax + 1 Then Return 0
        If button_kind = SUBWINDOW_TITLE_BUTTON_MINIMIZE Then
            buttonX = nextX
            Return -1
        End If
    End If

    Return 0
End Function


Private Function subwindow_PointInTitleButton( _
    ByVal w As Widget Ptr, ByVal window_data As SubWindowData Ptr, _
    ByVal button_kind As Integer, _
    ByVal pointerX As Integer, ByVal pointerY As Integer _
) As Integer
    Dim As Integer buttonX
    Dim As Integer buttonY

    If subwindow_GetTitleButtonRectangle( _
        w, window_data, button_kind, buttonX, buttonY _
    ) = 0 Then Return 0

    If pointerX >= buttonX AndAlso _
       pointerX < buttonX + SUBWINDOW_CLOSE_SIZE AndAlso _
       pointerY >= buttonY AndAlso _
       pointerY < buttonY + SUBWINDOW_CLOSE_SIZE Then
        Return -1
    End If

    Return 0
End Function


Private Function subwindow_PointInResizeGrip( _
    ByVal w As Widget Ptr, _
    ByVal pointerX As Integer, _
    ByVal pointerY As Integer _
) As Integer
    Dim As Integer gripWidth
    Dim As Integer gripHeight
    Dim As SubWindowData Ptr window_data

    If w = 0 OrElse w->data = 0 OrElse w->w < 1 OrElse w->h < 1 Then _
        Return 0
    window_data = Cast(SubWindowData Ptr, w->data)
    If window_data->border_style <> SUBWINDOW_BORDER_SIZABLE_SINGLE Then _
        Return 0
    If window_data->window_state <> SUBWINDOW_STATE_NORMAL Then Return 0
    gripWidth = IIf(w->w < SUBWINDOW_RESIZE_GRIP_SIZE, _
        w->w, SUBWINDOW_RESIZE_GRIP_SIZE)
    gripHeight = IIf(w->h < SUBWINDOW_RESIZE_GRIP_SIZE, _
        w->h, SUBWINDOW_RESIZE_GRIP_SIZE)
    Return IIf( _
        pointerX >= w->ax + w->w - gripWidth AndAlso _
        pointerX < w->ax + w->w AndAlso _
        pointerY >= w->ay + w->h - gripHeight AndAlso _
        pointerY < w->ay + w->h, -1, 0 _
    )
End Function


Private Sub subwindow_ApplyBorderStyle( _
    ByVal w As Widget Ptr, _
    ByVal window_data As SubWindowData Ptr _
)
    If w = 0 OrElse window_data = 0 Then Exit Sub

    Select Case window_data->border_style
    Case SUBWINDOW_BORDER_NONE
        w->child_clip_x = 0
        w->child_clip_y = 0
        w->child_clip_right = 0
        w->child_clip_bottom = 0
    Case SUBWINDOW_BORDER_FIXED_DOUBLE
        w->child_clip_x = SUBWINDOW_DOUBLE_BORDER_INSET
        w->child_clip_y = window_data->titlebar_height
        w->child_clip_right = SUBWINDOW_DOUBLE_BORDER_INSET
        w->child_clip_bottom = SUBWINDOW_DOUBLE_BORDER_INSET
    Case Else
        w->child_clip_x = SUBWINDOW_CLIENT_LEFT_INSET
        w->child_clip_y = window_data->titlebar_height
        w->child_clip_right = SUBWINDOW_CLIENT_RIGHT_INSET
        w->child_clip_bottom = SUBWINDOW_CLIENT_BOTTOM_INSET
    End Select
End Sub


Private Sub subwindow_GetContainerRectangle( _
    ByVal w As Widget Ptr, _
    ByRef containerX As Integer, ByRef containerY As Integer, _
    ByRef containerWidth As Integer, ByRef containerHeight As Integer _
)
    If w = 0 Then
        containerX = 0
        containerY = 0
        containerWidth = 1
        containerHeight = 1
        Exit Sub
    End If

    If w->parent <> 0 Then
        containerX = w->parent->child_clip_x
        containerY = w->parent->child_clip_y
        containerWidth = w->parent->w - containerX - _
            w->parent->child_clip_right
        containerHeight = w->parent->h - containerY - _
            w->parent->child_clip_bottom
    Else
        containerX = 0
        containerY = 0
        gui_GetViewportSize containerWidth, containerHeight
    End If
    If containerWidth < 1 Then containerWidth = 1
    If containerHeight < 1 Then containerHeight = 1
End Sub


Private Sub subwindow_ClearDescendantFocus(ByVal w As Widget Ptr)
    Dim As Widget Ptr current = gui_GetFocus()
    Dim As Integer parentDepth

    While current <> 0 AndAlso parentDepth < SUBWINDOW_PARENT_GUARD
        If current = w Then
            gui_SetFocus 0
            Exit Sub
        End If
        current = current->parent
        parentDepth += 1
    Wend
End Sub


Private Function subwindow_ApplyStateGeometry( _
    ByVal w As Widget Ptr, ByVal window_data As SubWindowData Ptr, _
    ByVal containerX As Integer, ByVal containerY As Integer, _
    ByVal containerWidth As Integer, ByVal containerHeight As Integer _
) As Integer
    Dim As Integer previousHeight
    Dim As Integer previousWidth
    Dim As Integer previousX
    Dim As Integer previousY

    If w = 0 OrElse window_data = 0 Then Return 0
    If window_data->window_state = SUBWINDOW_STATE_NORMAL Then Return 0
    previousX = w->x
    previousY = w->y
    previousWidth = w->w
    previousHeight = w->h

    Select Case window_data->window_state
    Case SUBWINDOW_STATE_MINIMIZED
        w->w = SUBWINDOW_MINIMIZED_WIDTH
        If w->w > containerWidth Then w->w = containerWidth
        w->h = window_data->titlebar_height
        If w->h > containerHeight Then w->h = containerHeight
        If w->x < containerX Then w->x = containerX
        If w->x + w->w > containerX + containerWidth Then _
            w->x = containerX + containerWidth - w->w
        w->y = containerY + containerHeight - w->h
    Case SUBWINDOW_STATE_MAXIMIZED
        w->x = containerX
        w->y = containerY
        w->w = containerWidth
        w->h = containerHeight
    Case Else
        ' The public setter rejects every other retained state.
        Return 0
    End Select

    Return IIf( _
        w->x <> previousX OrElse w->y <> previousY OrElse _
        w->w <> previousWidth OrElse w->h <> previousHeight, -1, 0 _
    )
End Function


Private Sub subwindow_ResizeToPointer( _
    ByVal w As Widget Ptr, ByVal window_data As SubWindowData Ptr, _
    ByVal pointerX As Integer, ByVal pointerY As Integer _
)
    Dim As Integer maximumWidth
    Dim As Integer maximumHeight
    Dim As Integer minimumWidth = SUBWINDOW_MINIMUM_WIDTH
    Dim As Integer minimumHeight = SUBWINDOW_MINIMUM_HEIGHT
    Dim As Integer viewportWidth
    Dim As Integer viewportHeight
    Dim As LongInt requestedWidth
    Dim As LongInt requestedHeight

    If w = 0 OrElse window_data = 0 Then Exit Sub
    If w->parent <> 0 Then
        maximumWidth = w->parent->w - w->parent->child_clip_right - w->x
        maximumHeight = w->parent->h - w->parent->child_clip_bottom - w->y
    Else
        gui_GetViewportSize viewportWidth, viewportHeight
        maximumWidth = viewportWidth - w->x
        maximumHeight = viewportHeight - w->y
    End If
    If maximumWidth < 1 Then maximumWidth = 1
    If maximumHeight < 1 Then maximumHeight = 1
    If minimumWidth > maximumWidth Then minimumWidth = maximumWidth
    If minimumHeight > maximumHeight Then minimumHeight = maximumHeight

    ' LONGINT arithmetic keeps hostile or synthetic pointer coordinates from
    ' overflowing before the requested rectangle is clamped to its container.
    requestedWidth = CLngInt(window_data->resize_start_w) + _
        CLngInt(pointerX) - window_data->resize_start_x
    requestedHeight = CLngInt(window_data->resize_start_h) + _
        CLngInt(pointerY) - window_data->resize_start_y
    If requestedWidth < minimumWidth Then requestedWidth = minimumWidth
    If requestedHeight < minimumHeight Then requestedHeight = minimumHeight
    If requestedWidth > maximumWidth Then requestedWidth = maximumWidth
    If requestedHeight > maximumHeight Then requestedHeight = maximumHeight
    w->w = CInt(requestedWidth)
    w->h = CInt(requestedHeight)
    /'
        A sizable window is an anchor container. Rebase the window itself,
        then let omaGUI apply the parent-size delta to its children before the
        next pointer target is resolved.
    '/
    If w->layout_initialized Then gui_SetAnchors w, w->anchor_flags
    gui_SynchronizeLayout
End Sub


Private Sub subwindow_ClampPosition(ByVal w As Widget Ptr)
    Dim As Integer maximumX
    Dim As Integer maximumY
    Dim As Integer minimumX
    Dim As Integer minimumY
    Dim As Integer viewportHeight
    Dim As Integer viewportWidth

    If w = 0 Then Exit Sub

    If w->parent <> 0 Then
        minimumX = w->parent->child_clip_x
        minimumY = w->parent->child_clip_y
        maximumX = w->parent->w - w->parent->child_clip_right - w->w
        maximumY = w->parent->h - w->parent->child_clip_bottom - w->h
    Else
        gui_GetViewportSize viewportWidth, viewportHeight
        minimumX = 0
        minimumY = 0
        maximumX = viewportWidth - w->w
        maximumY = viewportHeight - w->h
    End If

    If maximumX < minimumX Then maximumX = minimumX
    If maximumY < minimumY Then maximumY = minimumY

    If w->x < minimumX Then w->x = minimumX
    If w->y < minimumY Then w->y = minimumY
    If w->x > maximumX Then w->x = maximumX
    If w->y > maximumY Then w->y = maximumY
End Sub


Sub subwindow_CancelInput(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    With *Cast(SubWindowData Ptr, w->data)
        .dragging = 0
        .resizing = 0
        .close_latch = 0
        .minimize_latch = 0
        .maximize_latch = 0
    End With
End Sub


Sub subwindow_Update(ByVal w As Widget Ptr)
    Dim As SubWindowData Ptr d
    Dim As Integer parentAbsoluteX
    Dim As Integer parentAbsoluteY
    Dim As Integer mx
    Dim As Integer my
    Dim As Integer mb

    If w = 0 OrElse w->data = 0 Then Exit Sub
    d = Cast(SubWindowData Ptr, w->data)
    If d->window_state <> SUBWINDOW_STATE_NORMAL Then
        Dim As Integer containerX
        Dim As Integer containerY
        Dim As Integer containerWidth
        Dim As Integer containerHeight
        subwindow_GetContainerRectangle w, containerX, containerY, _
            containerWidth, containerHeight
        /'
            A parent or host resize changes the meaning of both portable
            non-normal states. Defer input for the one frame in which the
            manager must re-resolve absolute descendant geometry.
        '/
        If subwindow_ApplyStateGeometry( _
            w, d, containerX, containerY, containerWidth, containerHeight _
        ) Then
            If w->layout_initialized Then _
                gui_SetAnchors w, w->anchor_flags
            gui_SynchronizeLayout
            subwindow_CancelInput w
            Exit Sub
        End If
    End If
    mx = input_MouseX()
    my = input_MouseY()
    mb = input_MouseButtons()

    If (mb And 1) Then
        If d->close_latch OrElse d->minimize_latch OrElse _
           d->maximize_latch Then
            d->dragging = 0
            d->resizing = 0
            Exit Sub
        End If

        If d->resizing Then
            d->dragging = 0
            subwindow_ResizeToPointer w, d, mx, my
            Exit Sub
        End If

        If subwindow_PointInTitleButton( _
            w, d, SUBWINDOW_TITLE_BUTTON_CLOSE, mx, my _
        ) Then
            d->close_latch = -1
            d->dragging = 0
            d->resizing = 0
            Exit Sub
        End If

        If subwindow_PointInTitleButton( _
            w, d, SUBWINDOW_TITLE_BUTTON_MAXIMIZE, mx, my _
        ) Then
            d->maximize_latch = -1
            d->dragging = 0
            d->resizing = 0
            Exit Sub
        End If

        If subwindow_PointInTitleButton( _
            w, d, SUBWINDOW_TITLE_BUTTON_MINIMIZE, mx, my _
        ) Then
            d->minimize_latch = -1
            d->dragging = 0
            d->resizing = 0
            Exit Sub
        End If

        If subwindow_PointInResizeGrip(w, mx, my) Then
            d->resizing = -1
            d->resize_start_x = mx
            d->resize_start_y = my
            d->resize_start_w = w->w
            d->resize_start_h = w->h
            d->dragging = 0
            Exit Sub
        End If

        If d->dragging Then
            If d->move_parent <> 0 AndAlso w->parent <> 0 Then
                Dim As Widget Ptr owner = w->parent
                parentAbsoluteX = 0
                parentAbsoluteY = 0
                If owner->parent <> 0 Then
                    parentAbsoluteX = owner->parent->ax
                    parentAbsoluteY = owner->parent->ay
                End If
                owner->x = mx - parentAbsoluteX - w->x - d->drag_off_x
                owner->y = my - parentAbsoluteY - w->y - d->drag_off_y
                subwindow_ClampPosition owner
                gui_SynchronizeLayout
                Exit Sub
            End If
            If w->parent <> 0 Then
                parentAbsoluteX = w->parent->ax
                parentAbsoluteY = w->parent->ay
            End If

            w->x = mx - parentAbsoluteX - d->drag_off_x
            If d->window_state = SUBWINDOW_STATE_NORMAL Then _
                w->y = my - parentAbsoluteY - d->drag_off_y
            subwindow_ClampPosition w
        Elseif d->window_state <> SUBWINDOW_STATE_MAXIMIZED AndAlso _
               (d->border_style <> SUBWINDOW_BORDER_NONE OrElse _
                d->window_state = SUBWINDOW_STATE_MINIMIZED) AndAlso _
               mx >= w->ax AndAlso mx < w->ax + w->w AndAlso _
               my >= w->ay AndAlso _
               my < w->ay + d->titlebar_height Then
            d->dragging = 1
            d->drag_off_x = mx - w->ax
            d->drag_off_y = my - w->ay
        End If
    ElseIf d->resizing Then
        d->resizing = 0
        d->dragging = 0
    ElseIf d->close_latch Then
        /'
            The close box follows the same release-inside rule as an ordinary
            button. An operator can press it, move away after reconsidering,
            and release without closing a setup or method dialog.
        '/
        Dim As Integer close_activated = subwindow_PointInTitleButton( _
            w, d, SUBWINDOW_TITLE_BUTTON_CLOSE, mx, my _
        )
        d->dragging = 0
        d->close_latch = 0
        If close_activated Then
            d->close_requested = -1
            If d->close_handler <> 0 Then
                Cast(Sub(ByVal As Widget Ptr), d->close_handler)(w)
            Else
                w->visible = 0
                w->enabled = 0
            End If
        End If
    ElseIf d->maximize_latch Then
        Dim As Integer maximize_activated = subwindow_PointInTitleButton( _
            w, d, SUBWINDOW_TITLE_BUTTON_MAXIMIZE, mx, my _
        )
        Dim As Integer maximize_target = IIf( _
            d->window_state = SUBWINDOW_STATE_MAXIMIZED, _
            SUBWINDOW_STATE_NORMAL, SUBWINDOW_STATE_MAXIMIZED _
        )
        d->maximize_latch = 0
        d->dragging = 0
        If maximize_activated Then _
            subwindow_SetWindowState w, maximize_target
    ElseIf d->minimize_latch Then
        Dim As Integer minimize_activated = subwindow_PointInTitleButton( _
            w, d, SUBWINDOW_TITLE_BUTTON_MINIMIZE, mx, my _
        )
        d->minimize_latch = 0
        d->dragging = 0
        If minimize_activated Then _
            subwindow_SetWindowState w, SUBWINDOW_STATE_MINIMIZED
    Else
        d->dragging = 0
        d->resizing = 0
    End If
End Sub

' -------------------------------------------------------------------------
' Rendering and lifecycle
' -------------------------------------------------------------------------

Sub subwindow_Render(ByVal w As Widget Ptr)
    Dim As SubWindowData Ptr d
    Dim As Integer buttonX
    Dim As Integer buttonY
    Dim As Integer titleHeight
    Dim As Integer titleInsetX
    Dim As Integer titleInsetY
    Dim As Integer titleWidth
    Dim As ULong client_color

    If w = 0 OrElse w->data = 0 OrElse w->w < 1 OrElse w->h < 1 Then _
        Exit Sub
    d = Cast(SubWindowData Ptr, w->data)
    client_color = theme_GetColor(GUI_COLOR_WINDOW_BG)
    If d->client_color_override Then client_color = d->client_color

    If d->border_style = SUBWINDOW_BORDER_NONE AndAlso _
       d->window_state <> SUBWINDOW_STATE_MINIMIZED Then
        backend_Rect w->ax, w->ay, w->w, w->h, client_color, -1
        Exit Sub
    End If

    If current_theme.control_style = GUI_CONTROL_STYLE_FLAT Then
        ' The rounded dialog skin uses the window's scoped appearance. Keep
        ' the local title controls available with their original hit boxes.
        backend_RoundRect w->ax, w->ay, w->w, w->h, 6, client_color, 1
        backend_RoundRect w->ax, w->ay, w->w, w->h, 6, current_theme.win_border, 0
        If w->w > 2 AndAlso d->titlebar_height > 1 Then
            backend_RoundRect w->ax + 1, w->ay + 1, w->w - 2, _
                d->titlebar_height - 1, 5, current_theme.title_background, 1
            If d->titlebar_height > 6 Then _
                backend_Rect w->ax + 1, w->ay + 6, w->w - 2, _
                    d->titlebar_height - 6, current_theme.title_background, 1
        End If
        backend_Print w->ax + d->title_text_inset, _
            w->ay + (d->titlebar_height - backend_GetTextHeight()) \ 2 + _
                d->title_text_y_offset, _
            current_theme.title_text, d->title
        If subwindow_GetTitleButtonRectangle(w, d, SUBWINDOW_TITLE_BUTTON_CLOSE, buttonX, buttonY) Then
            Dim As ULong close_color = current_theme.title_text
            If subwindow_PointInTitleButton(w, d, SUBWINDOW_TITLE_BUTTON_CLOSE, _
                input_MouseX(), input_MouseY()) Then
                backend_Rect buttonX, buttonY, SUBWINDOW_CLOSE_SIZE, _
                    SUBWINDOW_CLOSE_SIZE, RGB(232, 17, 35), 1
                close_color = RGB(255, 255, 255)
            End If
            backend_Line buttonX + 3, buttonY + 3, buttonX + 10, buttonY + 10, close_color
            backend_Line buttonX + 10, buttonY + 3, buttonX + 3, buttonY + 10, close_color
        End If
        If subwindow_GetTitleButtonRectangle(w, d, SUBWINDOW_TITLE_BUTTON_MAXIMIZE, buttonX, buttonY) Then
            backend_Rect buttonX + 3, buttonY + 3, 8, 8, current_theme.title_text, 0
        End If
        If subwindow_GetTitleButtonRectangle(w, d, SUBWINDOW_TITLE_BUTTON_MINIMIZE, buttonX, buttonY) Then
            backend_Line buttonX + 3, buttonY + 10, buttonX + 10, buttonY + 10, current_theme.title_text
        End If
        Exit Sub
    End If

    If theme_GetClassicShadow() Then _
        backend_Rect w->ax + 3, w->ay + 3, w->w, w->h, _
            current_theme.bg_dark, -1
    backend_Rect w->ax, w->ay, w->w, w->h, client_color, -1
    backend_Rect w->ax, w->ay, w->w, w->h, _
        theme_GetClassicColor(GUI_CLASSIC_COLOR_ACTIVE_BORDER_TEXT), 0
    If w->w > 2 AndAlso w->h > 2 Then _
        backend_Rect w->ax + 1, w->ay + 1, w->w - 2, w->h - 2, _
            theme_GetClassicColor( _
                GUI_CLASSIC_COLOR_ACTIVE_BORDER_BACKGROUND _
            ), 0
    If d->border_style = SUBWINDOW_BORDER_FIXED_DOUBLE AndAlso _
       w->w > 4 AndAlso w->h > 4 Then
        backend_Rect w->ax + 2, w->ay + 2, w->w - 4, w->h - 4, _
            theme_GetClassicColor(GUI_CLASSIC_COLOR_ACTIVE_BORDER_TEXT), 0
    End If
    Dim As ULong title_background = theme_GetColor(GUI_COLOR_SELECT_BG)
    Dim As ULong title_foreground = theme_GetColor(GUI_COLOR_SELECT_TEXT)
    If d->title_color_override Then
        title_background = d->title_background
        title_foreground = d->title_foreground
    End If
    titleInsetX = IIf(w->w > 4, 2, 0)
    titleInsetY = IIf(w->h > 2, 2, 0)
    titleWidth = w->w - titleInsetX * 2
    titleHeight = d->titlebar_height - 2
    If titleHeight > w->h - titleInsetY Then _
        titleHeight = w->h - titleInsetY
    If titleWidth > 0 AndAlso titleHeight > 0 Then _
        backend_Rect w->ax + titleInsetX, w->ay + titleInsetY, _
            titleWidth, titleHeight, title_background, 1
    If w->w > SUBWINDOW_TITLE_TEXT_X_OFFSET AndAlso _
       w->h > SUBWINDOW_TITLE_TEXT_Y_OFFSET Then _
        backend_Print w->ax + d->title_text_inset, _
            w->ay + (d->titlebar_height - backend_GetTextHeight()) \ 2 + _
                d->title_text_y_offset, _
            title_foreground, d->title

    If subwindow_GetTitleButtonRectangle( _
        w, d, SUBWINDOW_TITLE_BUTTON_CLOSE, buttonX, buttonY _
    ) Then
        backend_Rect buttonX, buttonY, SUBWINDOW_CLOSE_SIZE, _
            SUBWINDOW_CLOSE_SIZE, current_theme.bg_face, 1
        backend_Rect buttonX, buttonY, SUBWINDOW_CLOSE_SIZE, _
            SUBWINDOW_CLOSE_SIZE, current_theme.win_border, 0
        backend_Line buttonX + 3, buttonY + 3, _
            buttonX + SUBWINDOW_CLOSE_SIZE - 4, _
            buttonY + SUBWINDOW_CLOSE_SIZE - 4, current_theme.text_main
        backend_Line buttonX + SUBWINDOW_CLOSE_SIZE - 4, buttonY + 3, _
            buttonX + 3, buttonY + SUBWINDOW_CLOSE_SIZE - 4, _
            current_theme.text_main
    End If
    If subwindow_GetTitleButtonRectangle( _
        w, d, SUBWINDOW_TITLE_BUTTON_MAXIMIZE, buttonX, buttonY _
    ) Then
        backend_Rect buttonX, buttonY, SUBWINDOW_CLOSE_SIZE, _
            SUBWINDOW_CLOSE_SIZE, current_theme.bg_face, 1
        backend_Rect buttonX, buttonY, SUBWINDOW_CLOSE_SIZE, _
            SUBWINDOW_CLOSE_SIZE, current_theme.win_border, 0
        If d->window_state = SUBWINDOW_STATE_MAXIMIZED Then
            backend_Rect buttonX + 3, buttonY + 5, 7, 6, _
                current_theme.text_main, 0
            backend_Rect buttonX + 5, buttonY + 3, 6, 6, _
                current_theme.text_main, 0
        Else
            backend_Rect buttonX + 3, buttonY + 3, 8, 8, _
                current_theme.text_main, 0
        End If
    End If
    If subwindow_GetTitleButtonRectangle( _
        w, d, SUBWINDOW_TITLE_BUTTON_MINIMIZE, buttonX, buttonY _
    ) Then
        backend_Rect buttonX, buttonY, SUBWINDOW_CLOSE_SIZE, _
            SUBWINDOW_CLOSE_SIZE, current_theme.bg_face, 1
        backend_Rect buttonX, buttonY, SUBWINDOW_CLOSE_SIZE, _
            SUBWINDOW_CLOSE_SIZE, current_theme.win_border, 0
        backend_Line buttonX + 3, buttonY + SUBWINDOW_CLOSE_SIZE - 4, _
            buttonX + SUBWINDOW_CLOSE_SIZE - 4, _
            buttonY + SUBWINDOW_CLOSE_SIZE - 4, current_theme.text_main
    End If
    If d->window_state = SUBWINDOW_STATE_NORMAL AndAlso _
       d->border_style = SUBWINDOW_BORDER_SIZABLE_SINGLE AndAlso _
       w->w >= SUBWINDOW_RESIZE_GRIP_SIZE AndAlso _
       w->h >= SUBWINDOW_RESIZE_GRIP_SIZE Then
        Dim As Integer gripRight = w->ax + w->w - 3
        Dim As Integer gripBottom = w->ay + w->h - 3
        For gripOffset As Integer = 0 To SUBWINDOW_RESIZE_GRIP_SIZE - 4 _
            Step SUBWINDOW_RESIZE_GRIP_LINE_STEP
            backend_Line gripRight - gripOffset, gripBottom, _
                gripRight, gripBottom - gripOffset, _
                theme_GetColor(GUI_COLOR_BORDER)
        Next gripOffset
    End If
End Sub

Sub subwindow_Destroy(ByVal w As Widget Ptr)
    If w = 0 Then Exit Sub
    If w->data <> 0 Then Delete Cast(SubWindowData Ptr, w->data)
    w->data = 0
End Sub

Function subwindow_Create( _
    ByVal nm As String, ByVal titl As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal closable As Integer _
) As Widget Ptr
    Dim As Widget Ptr res = New Widget
    Dim As SubWindowData Ptr d

    If res = 0 Then Return 0
    res->name = nm : res->x = x : res->y = y : res->w = w : res->h = h
    res->update = @subwindow_Update : res->render = @subwindow_Render : res->destroy = @subwindow_Destroy
    res->visible = 1 : res->enabled = 1
    res->is_window = -1
    res->cancel_input = @subwindow_CancelInput
    res->clip_children = -1
    res->child_clip_x = SUBWINDOW_CLIENT_LEFT_INSET
    res->child_clip_y = SUBWINDOW_TITLEBAR_HEIGHT
    res->child_clip_right = SUBWINDOW_CLIENT_RIGHT_INSET
    res->child_clip_bottom = SUBWINDOW_CLIENT_BOTTOM_INSET
    d = New SubWindowData
    If d = 0 Then
        Delete res
        Return 0
    End If
    d->title = gui_TransformText(titl)
    d->titlebar_height = SUBWINDOW_TITLEBAR_HEIGHT
    d->title_text_inset = SUBWINDOW_TITLE_TEXT_X_OFFSET
    d->title_text_y_offset = 0
    d->dragging = 0
    d->resizing = 0
    d->closable = IIf(closable <> 0, -1, 0)
    d->close_requested = 0
    d->close_latch = 0
    d->minimize_button = -1
    d->minimize_latch = 0
    d->maximize_button = -1
    d->maximize_latch = 0
    d->close_handler = 0
    d->client_color_override = 0
    d->border_style = SUBWINDOW_BORDER_FIXED_SINGLE
    d->window_state = SUBWINDOW_STATE_NORMAL
    d->restore_valid = 0
    res->suspend_children = 0
    subwindow_ApplyBorderStyle res, d
    res->data = d : Return res
End Function

' -------------------------------------------------------------------------
' Public state API
' -------------------------------------------------------------------------

Sub subwindow_SetCloseHandler( _
    ByVal w As Widget Ptr, ByVal closeHandler As Any Ptr _
)
    If w = 0 OrElse w->data = 0 Then Exit Sub
    Cast(SubWindowData Ptr, w->data)->close_handler = closeHandler
End Sub

Function subwindow_SetTitle( _
    ByVal w As Widget Ptr, ByRef title_text As Const String _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @subwindow_Destroy Then _
        Return 0
    Cast(SubWindowData Ptr, w->data)->title = gui_TransformText(title_text)
    Return -1
End Function

Function subwindow_GetTitle(ByVal w As Widget Ptr) As String
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @subwindow_Destroy Then _
        Return ""
    Return Cast(SubWindowData Ptr, w->data)->title
End Function


Sub subwindow_SetClosable(ByVal w As Widget Ptr, ByVal closable As Integer)
    subwindow_SetControlBox w, closable
End Sub


Sub subwindow_SetDialogStyle(ByVal w As Widget Ptr)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @subwindow_Destroy Then Exit Sub
    Dim As SubWindowData Ptr d = Cast(SubWindowData Ptr, w->data)
    theme_InitDialog d->appearance
    w->appearance = @d->appearance
    d->titlebar_height = SUBWINDOW_DIALOG_TITLEBAR_HEIGHT
    subwindow_ApplyBorderStyle w, d
End Sub


Sub subwindow_SetTitleBar(ByVal w As Widget Ptr, ByVal height As Integer, ByVal textInset As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @subwindow_Destroy Then Exit Sub
    If height < 16 OrElse height > 64 OrElse textInset < 5 OrElse textInset > 128 Then Exit Sub
    Dim As SubWindowData Ptr d = Cast(SubWindowData Ptr, w->data)
    d->titlebar_height = height
    d->title_text_inset = textInset
    subwindow_ApplyBorderStyle w, d
End Sub


Function subwindow_SetTitleTextYOffset( _
    ByVal w As Widget Ptr, ByVal offsetPixels As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @subwindow_Destroy Then Return 0
    If offsetPixels < -16 OrElse offsetPixels > 16 Then Return 0

    Cast(SubWindowData Ptr, w->data)->title_text_y_offset = offsetPixels
    Return -1
End Function


Sub subwindow_SetTheme(ByVal w As Widget Ptr, ByRef appearance As GUI_Theme)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @subwindow_Destroy Then Exit Sub
    Dim As SubWindowData Ptr d = Cast(SubWindowData Ptr, w->data)
    d->appearance = appearance
    w->appearance = @d->appearance
End Sub


Sub subwindow_SetMoveParent(ByVal w As Widget Ptr, ByVal moveParent As Integer)
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @subwindow_Destroy Then Exit Sub
    Cast(SubWindowData Ptr, w->data)->move_parent = IIf(moveParent <> 0, -1, 0)
End Sub


Function subwindow_SetControlBox( _
    ByVal w As Widget Ptr, ByVal enabled As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @subwindow_Destroy Then Return 0
    With *Cast(SubWindowData Ptr, w->data)
        .closable = IIf(enabled <> 0, -1, 0)
        If .closable = 0 Then .close_latch = 0
    End With
    Return -1
End Function


Function subwindow_GetControlBox( _
    ByVal w As Widget Ptr, ByRef enabled As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @subwindow_Destroy Then Return 0
    enabled = Cast(SubWindowData Ptr, w->data)->closable
    Return -1
End Function


Function subwindow_SetMinButton( _
    ByVal w As Widget Ptr, ByVal enabled As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @subwindow_Destroy Then Return 0
    With *Cast(SubWindowData Ptr, w->data)
        .minimize_button = IIf(enabled <> 0, -1, 0)
        If .minimize_button = 0 Then .minimize_latch = 0
    End With
    Return -1
End Function


Function subwindow_GetMinButton( _
    ByVal w As Widget Ptr, ByRef enabled As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @subwindow_Destroy Then Return 0
    enabled = Cast(SubWindowData Ptr, w->data)->minimize_button
    Return -1
End Function


Function subwindow_SetMaxButton( _
    ByVal w As Widget Ptr, ByVal enabled As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @subwindow_Destroy Then Return 0
    With *Cast(SubWindowData Ptr, w->data)
        .maximize_button = IIf(enabled <> 0, -1, 0)
        If .maximize_button = 0 Then .maximize_latch = 0
    End With
    Return -1
End Function


Function subwindow_GetMaxButton( _
    ByVal w As Widget Ptr, ByRef enabled As Integer _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @subwindow_Destroy Then Return 0
    enabled = Cast(SubWindowData Ptr, w->data)->maximize_button
    Return -1
End Function


Function subwindow_CloseRequested(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Return Cast(SubWindowData Ptr, w->data)->close_requested
End Function


Sub subwindow_Reopen(ByVal w As Widget Ptr)
    Dim As SubWindowData Ptr windowData

    If w = 0 OrElse w->data = 0 Then Exit Sub

    windowData = Cast(SubWindowData Ptr, w->data)
    windowData->close_requested = 0
    windowData->close_latch = 0
    windowData->minimize_latch = 0
    windowData->maximize_latch = 0
    windowData->dragging = 0
    w->visible = -1
    w->enabled = -1
    gui_BringToFront w
End Sub


Function subwindow_SetClientColor( _
    ByVal w As Widget Ptr, _
    ByVal color_value As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    With *Cast(SubWindowData Ptr, w->data)
        .client_color = color_value
        .client_color_override = -1
    End With
    Return -1
End Function


Function subwindow_ClearClientColor(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Cast(SubWindowData Ptr, w->data)->client_color_override = 0
    Return -1
End Function


Function subwindow_GetClientColor( _
    ByVal w As Widget Ptr, _
    ByRef color_value As ULong _
) As Integer
    Dim As SubWindowData Ptr window_data

    color_value = 0
    If w = 0 OrElse w->data = 0 Then Return 0
    window_data = Cast(SubWindowData Ptr, w->data)
    If window_data->client_color_override = 0 Then Return 0
    color_value = window_data->client_color
    Return -1
End Function


Function subwindow_SetBorderStyle( _
    ByVal w As Widget Ptr, _
    ByVal border_style As Integer _
) As Integer
    Dim As SubWindowData Ptr window_data

    If w = 0 OrElse w->data = 0 Then Return 0
    If border_style < SUBWINDOW_BORDER_NONE OrElse _
       border_style > SUBWINDOW_BORDER_FIXED_DOUBLE Then Return 0
    window_data = Cast(SubWindowData Ptr, w->data)
    window_data->border_style = border_style
    If border_style <> SUBWINDOW_BORDER_SIZABLE_SINGLE Then _
        window_data->resizing = 0
    If border_style = SUBWINDOW_BORDER_NONE Then
        window_data->close_latch = 0
        window_data->minimize_latch = 0
        window_data->maximize_latch = 0
    End If
    subwindow_ApplyBorderStyle w, window_data
    Return -1
End Function


Function subwindow_GetBorderStyle( _
    ByVal w As Widget Ptr, _
    ByRef border_style As Integer _
) As Integer
    border_style = SUBWINDOW_BORDER_FIXED_SINGLE
    If w = 0 OrElse w->data = 0 Then Return 0
    border_style = Cast(SubWindowData Ptr, w->data)->border_style
    Return -1
End Function


Function subwindow_GetClientTopInset(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 Then Return 0
    Return w->child_clip_y
End Function


Function subwindow_IsResizing(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @subwindow_Destroy Then Return 0
    Return IIf(Cast(SubWindowData Ptr, w->data)->resizing <> 0, -1, 0)
End Function


Function subwindow_SetWindowState( _
    ByVal w As Widget Ptr, ByVal window_state As Integer _
) As Integer
    Dim As Integer containerX
    Dim As Integer containerY
    Dim As Integer containerWidth
    Dim As Integer containerHeight
    Dim As SubWindowData Ptr window_data

    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @subwindow_Destroy Then Return 0
    If window_state < SUBWINDOW_STATE_NORMAL OrElse _
       window_state > SUBWINDOW_STATE_MAXIMIZED Then Return 0
    window_data = Cast(SubWindowData Ptr, w->data)
    If window_data->window_state = window_state Then Return -1

    If window_data->window_state = SUBWINDOW_STATE_NORMAL Then
        window_data->restore_x = w->x
        window_data->restore_y = w->y
        window_data->restore_w = w->w
        window_data->restore_h = w->h
        window_data->restore_valid = -1
    End If

    gui_CancelInput w
    subwindow_GetContainerRectangle w, containerX, containerY, _
        containerWidth, containerHeight
    Select Case window_state
    Case SUBWINDOW_STATE_NORMAL
        w->suspend_children = 0
        If window_data->restore_valid Then
            w->x = window_data->restore_x
            w->y = window_data->restore_y
            w->w = window_data->restore_w
            w->h = window_data->restore_h
        End If
        If w->w > containerWidth Then w->w = containerWidth
        If w->h > containerHeight Then w->h = containerHeight
        If w->w < 1 Then w->w = 1
        If w->h < 1 Then w->h = 1
        subwindow_ClampPosition w
    Case SUBWINDOW_STATE_MINIMIZED
        w->suspend_children = -1
        subwindow_ClearDescendantFocus w
        window_data->window_state = SUBWINDOW_STATE_MINIMIZED
        subwindow_ApplyStateGeometry w, window_data, containerX, containerY, _
            containerWidth, containerHeight
    Case SUBWINDOW_STATE_MAXIMIZED
        w->suspend_children = 0
        window_data->window_state = SUBWINDOW_STATE_MAXIMIZED
        subwindow_ApplyStateGeometry w, window_data, containerX, containerY, _
            containerWidth, containerHeight
    Case Else
        ' The range check above makes this defensive branch unreachable.
        Return 0
    End Select
    window_data->dragging = 0
    window_data->resizing = 0
    window_data->window_state = window_state
    If w->layout_initialized Then gui_SetAnchors w, w->anchor_flags
    gui_SynchronizeLayout
    gui_BringToFront w
    Return -1
End Function


Function subwindow_GetWindowState( _
    ByVal w As Widget Ptr, ByRef window_state As Integer _
) As Integer
    window_state = SUBWINDOW_STATE_NORMAL
    If w = 0 OrElse w->data = 0 OrElse _
       w->destroy <> @subwindow_Destroy Then Return 0
    window_state = Cast(SubWindowData Ptr, w->data)->window_state
    Return -1
End Function

Function subwindow_SetTitleColors( _
    ByVal w As Widget Ptr, ByVal background_color As ULong, ByVal foreground_color As ULong _
) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @subwindow_Destroy Then Return 0
    With *Cast(SubWindowData Ptr, w->data)
        .title_background = background_color
        .title_foreground = foreground_color
        .title_color_override = -1
    End With
    Return -1
End Function

Function subwindow_ClearTitleColors(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @subwindow_Destroy Then Return 0
    Cast(SubWindowData Ptr, w->data)->title_color_override = 0
    Return -1
End Function

Function subwindow_GetTitleColors( _
    ByVal w As Widget Ptr, ByRef background_color As ULong, ByRef foreground_color As ULong _
) As Integer
    ' A failed query leaves caller storage unchanged, including a wrong kind.
    If w = 0 OrElse w->data = 0 OrElse w->destroy <> @subwindow_Destroy Then Return 0
    With *Cast(SubWindowData Ptr, w->data)
        If .title_color_override = 0 Then Return 0
        background_color = .title_background
        foreground_color = .title_foreground
    End With
    Return -1
End Function

/' end of subwindow.bas '/
