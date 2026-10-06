/'
    Project: omaGUI
    ---------------

    File: theme.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for theme.

    Purpose:

        Declare the shared classic widget color theme.

    Responsibilities:

        - define the color fields consumed by standard widgets
        - expose normal, dark, and black palette selection
        - expose portable classic shadow and three-dimensional effects
        - expose independent classic menu, border, command, and scrollbar colors
        - expose semantic color lookup for standard widgets

    This file intentionally does NOT contain:

        - widget rendering
        - theme persistence or file parsing
        - platform-native appearance discovery
'/

#ifndef __THEME_BI__
#define __THEME_BI__

#include "backend.bi"

Type GUI_Theme
    As ULong bg_face
    ' Widget-scoped appearance can differ from the desktop palette.
    As ULong bg_widget
    As ULong bg_dark
    As ULong bg_light
    As ULong text_main
    As ULong text_select
    As ULong bg_select
    As ULong win_border
    ' Panel motifs are independent of the classic/flat control treatment.
    As ULong panel_face, accent_secondary
    As Integer visual_style
    As ULong menu_background, menu_text
    As ULong menu_selected_background, menu_selected_text
    As ULong menu_separator, menu_disabled_text
    As Integer control_style
    As ULong title_background, title_text
    As ULong classic_access_text
    As ULong classic_active_border_background
    As ULong classic_active_border_text
    As ULong classic_command_text
    As ULong classic_disabled_text
    As ULong classic_menu_background
    As ULong classic_menu_text
    As ULong classic_menu_selected_background
    As ULong classic_menu_selected_text
    As ULong classic_scrollbar_background
    As ULong classic_scrollbar_text
    As ULong syntax_keyword_color
    As ULong syntax_comment_color
    As ULong syntax_string_color
    As ULong syntax_number_color
    As ULong syntax_preprocessor_color
    As ULong syntax_type_color
    As ULong syntax_command_color
    As ULong syntax_procedure_color
    As ULong syntax_macro_color
    As ULong syntax_variable_color
    As ULong syntax_constant_color
    As ULong syntax_member_color
    As ULong syntax_label_color
    As ULong syntax_object_color
    As Integer mode
End Type

Extern current_theme As GUI_Theme
Declare Sub theme_InitClassic()
Declare Sub theme_SetCurrent(ByRef theme_value As GUI_Theme)
Declare Sub theme_GetCurrent(ByRef theme_value As GUI_Theme)
Declare Sub theme_InitDialog(ByRef dialogTheme As GUI_Theme)
Const GUI_CONTROL_STYLE_CLASSIC As Integer = 0
Const GUI_CONTROL_STYLE_FLAT As Integer = 1
Declare Sub theme_SetMode(ByVal theme_mode As Integer)
Declare Function theme_GetMode() As Integer
Declare Sub theme_SetClassicEffects( _
    ByVal shadow_enabled As Integer, ByVal three_d_enabled As Integer _
)
Declare Function theme_GetClassicShadow() As Integer
Declare Function theme_GetClassicThreeD() As Integer

Enum GUI_CLASSIC_COLOR
    GUI_CLASSIC_COLOR_ACCESS_TEXT = 0
    GUI_CLASSIC_COLOR_ACTIVE_BORDER_BACKGROUND
    GUI_CLASSIC_COLOR_ACTIVE_BORDER_TEXT
    GUI_CLASSIC_COLOR_COMMAND_TEXT
    GUI_CLASSIC_COLOR_DISABLED_TEXT
    GUI_CLASSIC_COLOR_MENU_BACKGROUND
    GUI_CLASSIC_COLOR_MENU_TEXT
    GUI_CLASSIC_COLOR_MENU_SELECTED_BACKGROUND
    GUI_CLASSIC_COLOR_MENU_SELECTED_TEXT
    GUI_CLASSIC_COLOR_SCROLLBAR_BACKGROUND
    GUI_CLASSIC_COLOR_SCROLLBAR_TEXT
    GUI_CLASSIC_COLOR_COUNT
End Enum

' Label frame outlines share the existing active window-border color role.
Const GUI_CLASSIC_COLOR_WINDOW_FRAME As Integer = _
    GUI_CLASSIC_COLOR_ACTIVE_BORDER_TEXT

Declare Function theme_SetClassicColor( _
    ByVal color_role As Integer, ByVal color_value As ULong _
) As Integer
Declare Function theme_GetClassicColor( _
    ByVal color_role As Integer _
) As ULong

Const GUI_THEME_MODE_NORMAL As Integer = 0
Const GUI_THEME_MODE_DARK As Integer = 1
Const GUI_THEME_MODE_BLACK As Integer = 2

' TurboTrek retains these identities as presentation tokens. omaGUI widgets
' consume the shared color fields, while application frame renderers may use
' the style to choose a faction-specific structural motif.
Const GUI_THEME_STYLE_CLASSIC As Integer = 0
Const GUI_THEME_STYLE_FORTIFIED As Integer = 1
Const GUI_THEME_STYLE_INSCRIBED As Integer = 2
Const GUI_THEME_STYLE_MODULAR As Integer = 3
Const GUI_THEME_STYLE_SWEPT As Integer = 4
Const GUI_THEME_STYLE_CHEVRON As Integer = 5
Const GUI_THEME_STYLE_ORBITAL As Integer = 6
Const GUI_THEME_STYLE_FACETED As Integer = 7
Const GUI_THEME_STYLE_NODAL As Integer = 8
Const GUI_THEME_STYLE_RIGGED As Integer = 9

Enum GUI_THEME_COLOR
    GUI_COLOR_BORDER = 0
    GUI_COLOR_WINDOW_BG
    GUI_COLOR_WIDGET_BG
    GUI_COLOR_SELECT_BG
    GUI_COLOR_SELECT_TEXT
    GUI_COLOR_TEXT
End Enum

Declare Function theme_GetColor(ByVal colorId As Integer) As ULong

#endif

' end of theme.bi
