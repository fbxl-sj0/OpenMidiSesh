/'
    Project: omaGUI
    ---------------
    File: theme.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements theme.bi; declarations there define the interface.
    Purpose: GUI Theme implementation for normal, dark, and black palettes.

    Responsibilities:

        - retain the active palette used by standard omaGUI widgets
        - retain classic shadow and three-dimensional rendering switches
        - retain classic semantic colors without coupling unrelated widgets
        - provide syntax-color defaults for editor textboxes, including
          semantic command, procedure, macro, variable, type, object, and
          member roles
        - reject invalid palette modes by falling back to normal mode

    This file intentionally does NOT contain:

        - settings-menu commands
        - persistent configuration file access
        - widget-specific rendering
'/
#lang "fb"
#include once "src/widgets/widgets.bi"

' -------------------------------------------------------------------------
' Global State
' -------------------------------------------------------------------------

Dim Shared current_theme As GUI_Theme
Dim Shared As Integer theme_classic_shadow
Dim Shared As Integer theme_classic_three_d = -1

' -------------------------------------------------------------------------
' Initialization
' -------------------------------------------------------------------------

Private Sub theme_ApplyNormal()
    current_theme.bg_face     = RGB(212, 208, 200)
    current_theme.bg_dark     = RGB(128, 128, 128)
    current_theme.bg_light    = RGB(255, 255, 255)
    current_theme.text_main   = RGB(0, 0, 0)
    current_theme.text_select = RGB(255, 255, 255)
    current_theme.bg_select   = RGB(0, 84, 227)
    current_theme.win_border  = RGB(0, 0, 0)
    current_theme.syntax_keyword_color = RGB(0, 0, 160)
    current_theme.syntax_comment_color = RGB(0, 128, 0)
    current_theme.syntax_string_color = RGB(128, 64, 0)
    current_theme.syntax_number_color = RGB(0, 96, 96)
    current_theme.syntax_preprocessor_color = RGB(128, 0, 128)
    current_theme.syntax_type_color = RGB(0, 0, 128)
    current_theme.syntax_command_color = RGB(128, 0, 0)
    current_theme.syntax_procedure_color = RGB(0, 0, 128)
    current_theme.syntax_macro_color = RGB(160, 0, 160)
    current_theme.syntax_variable_color = RGB(0, 64, 128)
    current_theme.syntax_constant_color = RGB(128, 64, 0)
    current_theme.syntax_member_color = RGB(0, 96, 96)
    current_theme.syntax_label_color = RGB(128, 0, 0)
    current_theme.syntax_object_color = RGB(0, 0, 160)
End Sub


Private Sub theme_ApplyDark()
    current_theme.bg_face     = RGB(45, 45, 48)
    current_theme.bg_dark     = RGB(20, 20, 20)
    current_theme.bg_light    = RGB(30, 30, 30)
    current_theme.text_main   = RGB(230, 230, 230)
    current_theme.text_select = RGB(255, 255, 255)
    current_theme.bg_select   = RGB(38, 79, 120)
    current_theme.win_border  = RGB(90, 90, 90)
    current_theme.syntax_keyword_color = RGB(86, 156, 214)
    current_theme.syntax_comment_color = RGB(87, 166, 74)
    current_theme.syntax_string_color = RGB(214, 157, 133)
    current_theme.syntax_number_color = RGB(181, 206, 168)
    current_theme.syntax_preprocessor_color = RGB(197, 134, 192)
    current_theme.syntax_type_color = RGB(78, 201, 176)
    current_theme.syntax_command_color = RGB(220, 220, 170)
    current_theme.syntax_procedure_color = RGB(78, 201, 176)
    current_theme.syntax_macro_color = RGB(197, 134, 192)
    current_theme.syntax_variable_color = RGB(212, 212, 212)
    current_theme.syntax_constant_color = RGB(255, 203, 107)
    current_theme.syntax_member_color = RGB(156, 220, 254)
    current_theme.syntax_label_color = RGB(240, 180, 120)
    current_theme.syntax_object_color = RGB(86, 156, 214)
End Sub


Private Sub theme_ApplyBlack()
    current_theme.bg_face     = RGB(0, 0, 0)
    current_theme.bg_dark     = RGB(32, 32, 32)
    current_theme.bg_light    = RGB(0, 0, 0)
    current_theme.text_main   = RGB(255, 255, 255)
    current_theme.text_select = RGB(0, 0, 0)
    current_theme.bg_select   = RGB(192, 192, 192)
    current_theme.win_border  = RGB(160, 160, 160)
    current_theme.syntax_keyword_color = RGB(0, 255, 255)
    current_theme.syntax_comment_color = RGB(0, 255, 0)
    current_theme.syntax_string_color = RGB(255, 255, 0)
    current_theme.syntax_number_color = RGB(0, 255, 255)
    current_theme.syntax_preprocessor_color = RGB(255, 0, 255)
    current_theme.syntax_type_color = RGB(0, 255, 128)
    current_theme.syntax_command_color = RGB(255, 255, 0)
    current_theme.syntax_procedure_color = RGB(0, 255, 255)
    current_theme.syntax_macro_color = RGB(255, 0, 255)
    current_theme.syntax_variable_color = RGB(255, 255, 255)
    current_theme.syntax_constant_color = RGB(255, 255, 0)
    current_theme.syntax_member_color = RGB(0, 255, 128)
    current_theme.syntax_label_color = RGB(255, 128, 0)
    current_theme.syntax_object_color = RGB(128, 128, 255)
End Sub


Private Sub theme_ResetClassicColors()
    /'
        The broad normal/dark/black themes predate the VBDOS palette. Derive
        sensible semantic defaults from those fields so existing applications
        retain their appearance until they deliberately override one role.
    '/
    current_theme.classic_access_text = current_theme.text_main
    current_theme.classic_active_border_background = current_theme.bg_face
    current_theme.classic_active_border_text = current_theme.win_border
    current_theme.classic_command_text = current_theme.text_main
    current_theme.classic_disabled_text = current_theme.bg_dark
    current_theme.classic_menu_background = current_theme.bg_face
    current_theme.classic_menu_text = current_theme.text_main
    current_theme.classic_menu_selected_background = current_theme.bg_select
    current_theme.classic_menu_selected_text = current_theme.text_select
    current_theme.classic_scrollbar_background = current_theme.bg_face
    current_theme.classic_scrollbar_text = current_theme.text_main
End Sub


Sub theme_InitClassic()
    ' Preserve omaGUI's historical no-shadow default. VBDOS explicitly applies
    ' its ControlPanel defaults after initializing the toolkit.
    theme_classic_shadow = 0
    theme_classic_three_d = -1
    theme_SetMode GUI_THEME_MODE_NORMAL
End Sub


Sub theme_SetCurrent(ByRef theme_value As GUI_Theme)
    /'
        Application shells such as TurboTrek build a complete faction palette
        outside omaGUI. Their profiles predate the library's optional classic
        semantic roles, so derive those roles after copying the shared fields.
        This keeps labels, menus, and command buttons readable without asking
        every host application to duplicate the backend's default palette.
    '/
    current_theme = theme_value
    If current_theme.panel_face = 0 Then _
        current_theme.panel_face = current_theme.bg_face
    If current_theme.accent_secondary = 0 Then _
        current_theme.accent_secondary = current_theme.bg_select
    theme_ResetClassicColors
    ' Older complete palettes predate the dialog-specific roles. Derive them
    ' together only when that extension was not supplied by the caller.
    If current_theme.bg_widget = 0 AndAlso _
       current_theme.menu_background = 0 AndAlso _
       current_theme.title_background = 0 Then
        current_theme.bg_widget = current_theme.bg_light
        current_theme.menu_background = current_theme.classic_menu_background
        current_theme.menu_text = current_theme.classic_menu_text
        current_theme.menu_selected_background = current_theme.bg_select
        current_theme.menu_selected_text = current_theme.text_select
        current_theme.menu_separator = current_theme.bg_dark
        current_theme.menu_disabled_text = current_theme.classic_disabled_text
        current_theme.title_background = current_theme.bg_face
        current_theme.title_text = current_theme.text_main
    End If
End Sub

Sub theme_GetCurrent(ByRef theme_value As GUI_Theme)
    theme_value = current_theme
End Sub

Sub theme_SetMode(ByVal theme_mode As Integer)
    Select Case theme_mode
        Case GUI_THEME_MODE_DARK
            current_theme.mode = GUI_THEME_MODE_DARK
            theme_ApplyDark
        Case GUI_THEME_MODE_BLACK
            current_theme.mode = GUI_THEME_MODE_BLACK
            theme_ApplyBlack
        Case Else
            current_theme.mode = GUI_THEME_MODE_NORMAL
            theme_ApplyNormal
    End Select
    theme_ResetClassicColors
    current_theme.bg_widget = current_theme.bg_light
    current_theme.menu_background = current_theme.classic_menu_background
    current_theme.menu_text = current_theme.classic_menu_text
    current_theme.menu_selected_background = current_theme.classic_menu_selected_background
    current_theme.menu_selected_text = current_theme.classic_menu_selected_text
    current_theme.menu_separator = current_theme.bg_dark
    current_theme.menu_disabled_text = current_theme.classic_disabled_text
    current_theme.panel_face = current_theme.bg_face
    current_theme.accent_secondary = current_theme.bg_select
    current_theme.visual_style = GUI_THEME_STYLE_CLASSIC
    current_theme.control_style = GUI_CONTROL_STYLE_CLASSIC
    current_theme.title_background = current_theme.bg_face
    current_theme.title_text = current_theme.text_main
End Sub

Sub theme_InitDialog(ByRef dialogTheme As GUI_Theme)
    ' Start with valid classic and syntax roles, then select a light reading
    ' surface for a widget without changing the desktop palette.
    dialogTheme = current_theme
    dialogTheme.bg_face = RGB(240, 240, 240)
    dialogTheme.bg_widget = RGB(255, 255, 255)
    dialogTheme.bg_dark = RGB(128, 135, 145)
    dialogTheme.bg_light = dialogTheme.bg_widget
    dialogTheme.text_main = RGB(0, 0, 0)
    dialogTheme.text_select = RGB(255, 255, 255)
    dialogTheme.bg_select = RGB(0, 120, 215)
    dialogTheme.win_border = RGB(180, 180, 180)
    dialogTheme.menu_background = dialogTheme.bg_widget
    dialogTheme.menu_text = dialogTheme.text_main
    dialogTheme.menu_selected_background = dialogTheme.bg_select
    dialogTheme.menu_selected_text = dialogTheme.text_select
    dialogTheme.menu_separator = dialogTheme.bg_dark
    dialogTheme.menu_disabled_text = dialogTheme.bg_dark
    dialogTheme.control_style = GUI_CONTROL_STYLE_FLAT
    dialogTheme.title_background = RGB(243, 243, 243)
    dialogTheme.title_text = dialogTheme.text_main
End Sub


Function theme_GetMode() As Integer
    If current_theme.mode < GUI_THEME_MODE_NORMAL OrElse _
       current_theme.mode > GUI_THEME_MODE_BLACK Then
        Return GUI_THEME_MODE_NORMAL
    End If
    Return current_theme.mode
End Function


Sub theme_SetClassicEffects( _
    ByVal shadow_enabled As Integer, ByVal three_d_enabled As Integer _
)
    theme_classic_shadow = IIf(shadow_enabled <> 0, -1, 0)
    theme_classic_three_d = IIf(three_d_enabled <> 0, -1, 0)
End Sub


Function theme_GetClassicShadow() As Integer
    Return theme_classic_shadow
End Function


Function theme_GetClassicThreeD() As Integer
    Return theme_classic_three_d
End Function


Function theme_SetClassicColor( _
    ByVal color_role As Integer, ByVal color_value As ULong _
) As Integer
    Select Case color_role
        Case GUI_CLASSIC_COLOR_ACCESS_TEXT
            current_theme.classic_access_text = color_value
        Case GUI_CLASSIC_COLOR_ACTIVE_BORDER_BACKGROUND
            current_theme.classic_active_border_background = color_value
        Case GUI_CLASSIC_COLOR_ACTIVE_BORDER_TEXT
            current_theme.classic_active_border_text = color_value
        Case GUI_CLASSIC_COLOR_COMMAND_TEXT
            current_theme.classic_command_text = color_value
        Case GUI_CLASSIC_COLOR_DISABLED_TEXT
            current_theme.classic_disabled_text = color_value
        Case GUI_CLASSIC_COLOR_MENU_BACKGROUND
            current_theme.classic_menu_background = color_value
        Case GUI_CLASSIC_COLOR_MENU_TEXT
            current_theme.classic_menu_text = color_value
        Case GUI_CLASSIC_COLOR_MENU_SELECTED_BACKGROUND
            current_theme.classic_menu_selected_background = color_value
        Case GUI_CLASSIC_COLOR_MENU_SELECTED_TEXT
            current_theme.classic_menu_selected_text = color_value
        Case GUI_CLASSIC_COLOR_SCROLLBAR_BACKGROUND
            current_theme.classic_scrollbar_background = color_value
        Case GUI_CLASSIC_COLOR_SCROLLBAR_TEXT
            current_theme.classic_scrollbar_text = color_value
        Case Else
            Return 0
    End Select
    Return -1
End Function


Function theme_GetClassicColor(ByVal color_role As Integer) As ULong
    Select Case color_role
        Case GUI_CLASSIC_COLOR_ACCESS_TEXT
            Return current_theme.classic_access_text
        Case GUI_CLASSIC_COLOR_ACTIVE_BORDER_BACKGROUND
            Return current_theme.classic_active_border_background
        Case GUI_CLASSIC_COLOR_ACTIVE_BORDER_TEXT
            Return current_theme.classic_active_border_text
        Case GUI_CLASSIC_COLOR_COMMAND_TEXT
            Return current_theme.classic_command_text
        Case GUI_CLASSIC_COLOR_DISABLED_TEXT
            Return current_theme.classic_disabled_text
        Case GUI_CLASSIC_COLOR_MENU_BACKGROUND
            Return current_theme.classic_menu_background
        Case GUI_CLASSIC_COLOR_MENU_TEXT
            Return current_theme.classic_menu_text
        Case GUI_CLASSIC_COLOR_MENU_SELECTED_BACKGROUND
            Return current_theme.classic_menu_selected_background
        Case GUI_CLASSIC_COLOR_MENU_SELECTED_TEXT
            Return current_theme.classic_menu_selected_text
        Case GUI_CLASSIC_COLOR_SCROLLBAR_BACKGROUND
            Return current_theme.classic_scrollbar_background
        Case GUI_CLASSIC_COLOR_SCROLLBAR_TEXT
            Return current_theme.classic_scrollbar_text
    End Select
    Return current_theme.text_main
End Function


Function theme_GetColor(ByVal colorId As Integer) As ULong
    Select Case colorId
        Case GUI_COLOR_BORDER
            Return current_theme.win_border
        Case GUI_COLOR_WINDOW_BG
            Return current_theme.bg_face
        Case GUI_COLOR_WIDGET_BG
            Return current_theme.bg_light
        Case GUI_COLOR_SELECT_BG
            Return current_theme.bg_select
        Case GUI_COLOR_SELECT_TEXT
            Return current_theme.text_select
        Case GUI_COLOR_TEXT
            Return current_theme.text_main
        Case Else
            Return current_theme.text_main
    End Select
End Function

' end of theme.bas
