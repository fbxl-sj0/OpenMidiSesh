/'
    Project: omaGUI
    ---------------

    File: rtfview.bi

    Purpose:

        Declare a read-only RTF document widget for native FreeBASIC GUIs.

    Responsibilities:

        - retain bounded RTF paragraphs and character-format runs
        - expose topic text loading and plain-text loading
        - expose rendering, scrolling, and lifecycle entry points

    This file intentionally does NOT contain:

        - file access or help-topic navigation
        - rich text editing or hyperlink activation
        - platform-native rich text controls
'/

#ifndef __RTFVIEW_BI__
#define __RTFVIEW_BI__

#include once "src/widgets/widgets.bi"

Const RTFVIEW_MAX_INPUT_BYTES As Integer = 1048576
Const RTFVIEW_MAX_OUTPUT_BYTES As Integer = RTFVIEW_MAX_INPUT_BYTES * 3
Const RTFVIEW_MAX_RUNS As Integer = 4096
Const RTFVIEW_MAX_PARAGRAPHS As Integer = 2048
Const RTFVIEW_MAX_LINES As Integer = 8192
Const RTFVIEW_MAX_LINE_FRAGMENTS As Integer = 16384
Const RTFVIEW_MAX_GROUP_DEPTH As Integer = 64
Const RTFVIEW_MAX_FONTS As Integer = 64
Const RTFVIEW_MAX_COLORS As Integer = 64
Const RTFVIEW_MAX_FONT_NAME_BYTES As Integer = 128
' Bound type size to four through seventy-two points before bitmap scaling.
Const RTFVIEW_MIN_FONT_HALFPOINTS As Integer = 8
Const RTFVIEW_MAX_FONT_HALFPOINTS As Integer = 144

Type RtfViewFont
    As Integer number, monospaced
    As String name
End Type

Type RtfViewColor
    As ULong color
    As Integer automatic
End Type

Type RtfViewCharacterStyle
    As ULong color
    As Integer bold
    As Integer underline
    As Integer hidden
End Type

Type RtfViewParagraph
    As Integer first_run
    As Integer run_count
    As Integer alignment
    As Integer left_indent
    As Integer first_indent
    As Integer right_indent
    As Integer font_id, font_percent
End Type

Type RtfViewRun
    As Integer start_byte
    As Integer byte_length
    As ULong color
    As Integer font_id
    As Integer font_percent, bold, italic
    As Integer automatic_color
    As Integer underline
End Type

Type RtfViewLineFragment
    As Integer run_index
    As Integer start_byte
    As Integer byte_length
End Type

Type RtfViewLine
    As Integer first_fragment
    As Integer fragment_count
    As Integer alignment
    As Integer left_indent
    As Integer right_indent
    As Integer text_width
    ' Top is document-relative; each line retains its own baseline and height.
    As Integer top, height, ascent, descent
End Type

Type RtfViewData
    As String source_text
    As String display_text
    As Integer display_text_length
    As Integer display_text_capacity
    As String parse_error
    As Integer source_is_rtf
    As Integer paragraph_count
    As Integer run_count
    As Integer visual_line_count
    As Integer line_fragment_count
    As Integer scroll_top
    As Integer scroll_offset, last_scroll_top
    As Integer layout_width
    As Integer layout_dirty
    As Integer scrollbar_dragging
    As Integer font_count, color_count, default_font_number
    As Integer content_left, content_top, content_right, content_bottom
    As Integer document_height
    ' UTF-16 surrogate pairing spans formatting groups, not just brace scope.
    As Integer pending_surrogate
    As RtfViewFont fonts(0 To RTFVIEW_MAX_FONTS - 1)
    As RtfViewColor colors(0 To RTFVIEW_MAX_COLORS - 1)
    As Widget Ptr scrollbar
    ' Optional reading-surface colors have widget lifetime, including the scroll bar.
    As GUI_Theme appearance
    As RtfViewParagraph paragraphs(0 To RTFVIEW_MAX_PARAGRAPHS - 1)
    As RtfViewRun runs(0 To RTFVIEW_MAX_RUNS - 1)
    As RtfViewLine lines(0 To RTFVIEW_MAX_LINES - 1)
    As RtfViewLineFragment fragments( _
        0 To RTFVIEW_MAX_LINE_FRAGMENTS - 1 _
    )
End Type

Declare Function rtfview_Create( _
    ByVal nm As String, ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer _
) As Widget Ptr
Declare Function rtfview_SetRtf( _
    ByVal w As Widget Ptr, ByVal rtfText As String _
) As Integer
Declare Function rtfview_SetPlainText( _
    ByVal w As Widget Ptr, ByVal text As String _
) As Integer
Declare Function rtfview_GetError(ByVal w As Widget Ptr) As String
Declare Sub rtfview_SetColors(ByVal w As Widget Ptr, ByVal backgroundColor As ULong, ByVal textColor As ULong)
Declare Sub rtfview_SetMargins( _
    ByVal w As Widget Ptr, ByVal leftMargin As Integer, ByVal topMargin As Integer, _
    ByVal rightMargin As Integer, ByVal bottomMargin As Integer _
)
Declare Sub rtfview_Render(ByVal w As Widget Ptr)
Declare Sub rtfview_Update(ByVal w As Widget Ptr)
Declare Sub rtfview_Destroy(ByVal w As Widget Ptr)

#endif

/' end of rtfview.bi '/
