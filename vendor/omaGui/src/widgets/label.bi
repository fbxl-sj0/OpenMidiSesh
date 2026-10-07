/'
    Project: omaGUI
    ---------------

    File: label.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for label.

    Purpose:

        Declare a noninteractive text-label widget.

    Responsibilities:

        - retain label text, color, and selected embedded font
        - retain portable bold, italic, underline, and strikeout styles
        - expose checked text replacement and retrieval
        - retain an optional bounded client background color
        - expose bounded pixel-width word wrapping for narrow layouts
        - align fixed-rectangle text without replacing the widget renderer
        - measure that layout and retain an optional fixed border
        - expose an optional bounded fixed-rectangle border
        - report the measured size of the same wrapped layout used for drawing
        - expose label creation and rendering lifecycle entry points

    This file intentionally does NOT contain:

        - text editing or input handling
        - text editing, scrolling, or rich-text layout
'/

#ifndef __LABEL_BI__
#define __LABEL_BI__

#include once "src/widgets/widgets.bi"

Const LABEL_MAXIMUM_WRAPPED_LINES As Integer = 256
Const LABEL_MAXIMUM_ALIGNED_TEXT_BYTES As Integer = 1048576
Const LABEL_BORDER_NONE As Integer = 0
Const LABEL_BORDER_SINGLE As Integer = 1
Const LABEL_BORDER_DOUBLE As Integer = 2

Type LabelData
    As String text
    As ULong clr
    As Integer fontId
    As Integer fontPercent
    As Integer wordWrap
    As Integer maximumLines
    As Integer backgroundColorOverride
    As ULong backgroundColor
    As Integer clipToBounds
    ' Appended state keeps the layout of existing members intact. Alignment
    ' is opt-in; ordinary labels retain their original rendering defaults.
    As Integer alignmentOverride
    As Integer horizontalAlignment, verticalAlignment
    ' Optional fixed border. Existing labels retain their zero-inset layout.
    As Integer borderStyle
    ' Appended flags reuse the backend's portable synthetic text styles.
    As Integer textStyle
    ' Theme-following is separate from the 32-bit color value because opaque
    ' white can use the same bit pattern as LABEL_COLOR_THEME_TEXT.
    As Integer textColorUsesTheme
End Type

' A sentinel keeps a label's text tied to the active theme at render time.
Const LABEL_COLOR_THEME_TEXT As ULong = &HFFFFFFFF

Declare Function label_Create( _
    ByVal nm As String, ByVal txt As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal clr As ULong = RGB(0, 0, 0), _
    ByVal fontId As Integer = BACKEND_FONT_DEFAULT _
) As Widget Ptr
Declare Function label_CreateWithColor( _
    ByVal nm As String, ByVal txt As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal clr As ULong, _
    ByVal fontId As Integer = BACKEND_FONT_DEFAULT _
) As Widget Ptr
Declare Function label_SetText( _
    ByVal w As Widget Ptr, ByRef text_value As Const String _
) As Integer
Declare Function label_GetText(ByVal w As Widget Ptr) As String
Declare Sub label_SetFont(ByVal w As Widget Ptr, ByVal fontId As Integer)
Declare Sub label_SetFontScalePercent(ByVal w As Widget Ptr, ByVal percent As Integer)
' Style bits use BACKEND_TEXT_STYLE_*; invalid combinations leave state unchanged.
Declare Function label_SetTextStyle(ByVal w As Widget Ptr, ByVal textStyle As Integer) As Integer
Declare Function label_GetTextStyle(ByVal w As Widget Ptr) As Integer
Declare Function label_SetTextColor( _
    ByVal w As Widget Ptr, ByVal textColor As ULong _
) As Integer
' Literal colors remain literal even when their bits equal the theme sentinel.
Declare Function label_SetTextColorLiteral( _
    ByVal w As Widget Ptr, ByVal textColor As ULong _
) As Integer
Declare Function label_GetTextColor( _
    ByVal w As Widget Ptr, ByRef textColor As ULong _
) As Integer
Declare Function label_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal backgroundColor As ULong _
) As Integer
Declare Function label_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
Declare Function label_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef backgroundColor As ULong _
) As Integer
Declare Sub label_SetWordWrap( _
    ByVal w As Widget Ptr, ByVal maximumWidth As Integer, _
    ByVal maximumLines As Integer = 0 _
)
Declare Function label_GetRenderedLineCount(ByVal w As Widget Ptr) As Integer
' Measure the same bounded layout used by rendering, including border insets.
' Does not resize the widget. Empty text retains one font-height line.
Declare Function label_GetTextSize(ByVal w As Widget Ptr, ByRef textWidth As Integer, ByRef textHeight As Integer) As Integer
Declare Function label_SetBorderStyle(ByVal w As Widget Ptr, ByVal borderStyle As Integer) As Integer
Declare Function label_GetBorderStyle(ByVal w As Widget Ptr) As Integer
' Unclipped rendering remains the default, including labels with no explicit
' width/height. Hosts with fixed designer rectangles can opt into clipping.
Declare Function label_SetClipToBounds(ByVal w As Widget Ptr, ByVal enabled As Integer) As Integer
Declare Function label_GetClipToBounds(ByVal w As Widget Ptr) As Integer
Declare Function label_SetAlignment( _
    ByVal w As Widget Ptr, ByVal horizontalAlignment As Integer, _
    ByVal verticalAlignment As Integer = BACKEND_ALIGN_TOP _
) As Integer
Declare Function label_GetAlignment( _
    ByVal w As Widget Ptr, ByRef horizontalAlignment As Integer, _
    ByRef verticalAlignment As Integer _
) As Integer
Declare Function label_ClearAlignment(ByVal w As Widget Ptr) As Integer
Declare Sub label_Render(ByVal w As Widget Ptr)
Declare Sub label_Destroy(ByVal w As Widget Ptr)

#endif

/' end of label.bi '/
