/'
    Project: omaGUI
    ---------------

    File: textbox.bi

    Purpose:

        Declare the reusable editable text widget used by editor popups and
        ordinary single-line controls.

    Responsibilities:

        - define textbox state owned by each widget
        - expose textbox construction and update/render entry points
        - retain bounded per-widget text undo and redo state
        - retain mouse-drag and keyboard selection state
        - expose configurable multiline vertical scrollbar behavior
        - optionally insert spaces at tab stops in multiline editors
        - expose atomic logical-line indentation with retained selections
        - expose an optional fixed line-number gutter for multiline editors
        - expose focusable read-only and public editor-command state
        - expose an optional byte limit for native editing commands
        - retain optional caller-supplied client and text colors
        - optionally style embedded glyphs without changing editor metrics
        - support masked single-line input without replacing editor text
        - expose optional synchronous KeyDown, KeyPress, and KeyUp callbacks
        - retain optional syntax-highlighting mode and semantic color metadata
          for keywords, types, objects, members, procedures, and literals

    Targets:

        FreeBASIC builds with built-in gfxlib; gfxlib3 is optional when supplied by the compiler.

    Module API:

        Declarations for the textbox component in the omaGUI include graph.

    This file intentionally does NOT contain:

        - clipboard implementation
        - keyboard polling
        - application-specific text validation
'/

#ifndef __TEXTBOX_BI__
#define __TEXTBOX_BI__
#include once "src/widgets/widgets.bi"

Const TEXTBOX_HISTORY_MAX_ENTRIES As Integer = 16
Const TEXTBOX_HISTORY_MAX_STORED_BYTES As Integer = 2097152
Const TEXTBOX_HISTORY_GROUP_NONE As Integer = 0
Const TEXTBOX_HISTORY_GROUP_TYPING As Integer = 1
Const TEXTBOX_HISTORY_GROUP_BACKSPACE As Integer = 2
Const TEXTBOX_HISTORY_GROUP_DELETE As Integer = 3
Const TEXTBOX_HISTORY_GROUP_RETURN As Integer = 4
Const TEXTBOX_HISTORY_GROUP_TAB As Integer = 5

Const TEXTBOX_TAB_COLUMNS As Integer = 4
Const TEXTBOX_MAX_VIRTUAL_SPACE As Integer = 4096
Const TEXTBOX_WIDGET_COLOR_DEFAULT As ULong = &hFFFFFFFF
Const TEXTBOX_CUE_BANNER_MAX_BYTES As Integer = 256
Const TEXTBOX_TEXT_STYLE_BOLD As Integer = 1
Const TEXTBOX_TEXT_STYLE_UNDERLINE As Integer = 2
Const TEXTBOX_TEXT_STYLE_ITALIC As Integer = 4
Const TEXTBOX_TEXT_STYLE_BACKGROUND_DEFAULT As ULong = &HFFFFFFFF

Type TextBoxTextColorHandler As Function( _
    ByRef lineText As Const String, ByVal characterIndex As Integer, _
    ByRef state As Integer _
) As ULong

Type TextBoxCharacterStyle
    As ULong foreground, background
    As Integer flags
End Type

Type TextBoxTextStyleHandler As Function( _
    ByRef lineText As Const String, ByVal characterIndex As Integer, _
    ByRef state As Integer, _
    ByRef characterStyle As TextBoxCharacterStyle _
) As Integer
/'
    Optional lexer checkpoint for unwrapped viewports. The application owns
    its syntax state; return zero to retain the ordinary callback replay.
    Successful restoration permits replay to stop below the paint clip once
    caret geometry is known. Final callback state is not a document-end state.
'/
Type TextBoxRenderStateHandler As Function( _
    ByVal w As Widget Ptr, ByVal sourcePosition As Integer, _
    ByRef colorState As Integer, ByRef styleState As Integer _
) As Integer
/'
    Optional exact observation of application-owned line visibility. Equal
    keys must mean equal visible rows for the same source. Called on the GUI
    thread, without retaining a reference to the returned string. Without a
    provider, visibility callbacks retain their conservative layout behavior.
'/
Type TextBoxMetricsStateHandler As Function(ByVal w As Widget Ptr) As String
Const TEXTBOX_INDICATOR_STYLE_BOX As Integer = 0
Const TEXTBOX_INDICATOR_STYLE_FILL As Integer = 1
Type TextBoxTextIndicatorHandler As Function( _
    ByVal w As Widget Ptr, ByVal sourcePosition As Integer, _
    ByRef color As ULong, ByRef alpha As Integer, _
    ByRef style As Integer _
) As Integer
Type TextBoxGutterMarkerHandler As Function( _
    ByVal w As Widget Ptr, ByVal lineNumber As Integer, _
    ByVal lineStart As Integer _
) As ULong
Type TextBoxGutterMarkerStyleHandler As Function( _
    ByVal w As Widget Ptr, ByVal lineNumber As Integer, _
    ByVal lineStart As Integer, ByRef foregroundColor As ULong, _
    ByRef backgroundColor As ULong _
) As Integer
Type TextBoxGutterClickHandler As Sub( _
    ByVal w As Widget Ptr, ByVal lineNumber As Integer, _
    ByVal lineStart As Integer _
)
Type TextBoxFoldMarkerHandler As Function( _
    ByVal w As Widget Ptr, ByVal lineNumber As Integer, _
    ByVal lineStart As Integer _
) As Integer
Type TextBoxFoldClickHandler As Sub( _
    ByVal w As Widget Ptr, ByVal lineNumber As Integer, _
    ByVal lineStart As Integer _
)
Type TextBoxLineVisibilityHandler As Function( _
    ByVal w As Widget Ptr, ByVal lineNumber As Integer, _
    ByVal lineStart As Integer _
) As Integer

/'
    Editor callbacks are borrowed and run during the GUI update. A callback
    that handles a key returns nonzero; text remains owned by the textbox.
'/
Type TextBoxTypedTextHandler As Sub( _
    ByVal w As Widget Ptr, ByRef insertedText As Const String _
)
/'
    A display callback replaces one byte without changing source positions.
    State carries across lines; state 5 is reset at each line ending.
'/
Type TextBoxTextDisplayHandler As Function( _
    ByRef lineText As Const String, ByVal characterIndex As Integer, _
    ByRef state As Integer _
) As Integer
Type TextBoxContextMenuHandler As Sub( _
    ByVal w As Widget Ptr, ByVal mouseX As Integer, ByVal mouseY As Integer _
)
Type TextBoxNavigationHandler As Function( _
    ByVal w As Widget Ptr, ByVal keyCode As Integer _
) As Integer
Type TextBoxControlShortcutHandler As Function( _
    ByVal w As Widget Ptr, ByVal keyCode As Integer _
) As Integer
Type TextBoxKeyEventHandler As Function( _
    ByVal w As Widget Ptr, ByVal keyCode As Integer, _
    ByVal modifierFlags As Integer _
) As Integer

Const TEXTBOX_SCROLLBAR_NONE As Integer = 0
Const TEXTBOX_SCROLLBAR_AUTO As Integer = 1
Const TEXTBOX_SCROLLBAR_ALWAYS As Integer = 2
Const TEXTBOX_BORDER_NONE As Integer = 0
Const TEXTBOX_BORDER_SINGLE As Integer = 1

Const TEXTBOX_SYNTAX_NONE As Integer = 0
Const TEXTBOX_SYNTAX_FREEBASIC As Integer = 1

Const TEXTBOX_SYNTAX_COLOR_KEYWORD As Integer = 0
Const TEXTBOX_SYNTAX_COLOR_COMMENT As Integer = 1
Const TEXTBOX_SYNTAX_COLOR_STRING As Integer = 2
Const TEXTBOX_SYNTAX_COLOR_NUMBER As Integer = 3
Const TEXTBOX_SYNTAX_COLOR_PREPROCESSOR As Integer = 4
Const TEXTBOX_SYNTAX_COLOR_TYPE As Integer = 5
Const TEXTBOX_SYNTAX_COLOR_COMMAND As Integer = 6
Const TEXTBOX_SYNTAX_COLOR_PROCEDURE As Integer = 7
Const TEXTBOX_SYNTAX_COLOR_MACRO As Integer = 8
Const TEXTBOX_SYNTAX_COLOR_VARIABLE As Integer = 9
Const TEXTBOX_SYNTAX_COLOR_CONSTANT As Integer = 10
Const TEXTBOX_SYNTAX_COLOR_MEMBER As Integer = 11
Const TEXTBOX_SYNTAX_COLOR_LABEL As Integer = 12
Const TEXTBOX_SYNTAX_COLOR_OBJECT As Integer = 13

Type TextBoxHistoryEntry
    As String text
    As Integer cursor_pos, sel_start, sel_end, selection_anchor
    As Integer cursor_virtual_space
    As Integer sel_start_virtual_space, sel_end_virtual_space
    As Integer selection_anchor_virtual_space
    As Integer scroll_offset, v_scroll
End Type

' -------------------------------------------------------------------------
' TextBox retained editor state
' -------------------------------------------------------------------------

Type TextBoxData
    As String text
    As Widget Ptr owner
    As Integer active, multiline, wordwrap, read_only, accepts_tab
    As Integer block_indent
    As Integer line_numbers, line_number_gutter_width
    As Integer observed_has_focus
    As Integer cursor_pos, sel_start, sel_end, selection_anchor
    ' Virtual columns exist only beyond an unwrapped logical line end.
    As Integer cursor_virtual_space
    As Integer sel_start_virtual_space, sel_end_virtual_space
    As Integer selection_anchor_virtual_space
    As Integer virtual_space_enabled, observed_cursor_virtual_space
    As Integer scroll_offset, v_scroll
    As Integer key_latch
    As Integer mouse_latch, mouse_selecting
    As Integer scrollbar_dragging, horizontal_scrollbar_dragging
    As Integer scrollbar_mode, scrollbar_visible
    As Integer horizontal_scrollbar_mode, horizontal_scrollbar_visible
    As Integer total_visual_lines
    As Integer viewport_dirty
    As Integer observed_text_length, observed_cursor_pos
    ' Editors can track text changes without comparing the whole buffer.
    ' Direct writes to text must advance this counter too.
    As ULong change_serial
    As Integer background_color_override, foreground_color_override
    As ULong background_color, foreground_color
    As Integer syntax_mode
    As Integer syntax_color_overrides
    As ULong syntax_keyword_color, syntax_comment_color
    As ULong syntax_string_color, syntax_number_color
    As ULong syntax_preprocessor_color, syntax_type_color
    As ULong syntax_command_color, syntax_procedure_color
    As ULong syntax_macro_color, syntax_variable_color
    As ULong syntax_constant_color, syntax_member_color
    As ULong syntax_label_color, syntax_object_color
    As Widget Ptr vertical_scrollbar
    As Widget Ptr horizontal_scrollbar
    As TextBoxHistoryEntry undoEntries(0 To TEXTBOX_HISTORY_MAX_ENTRIES - 1)
    As TextBoxHistoryEntry redoEntries(0 To TEXTBOX_HISTORY_MAX_ENTRIES - 1)
    As Integer undoCount, redoCount
    As LongInt historyStoredBytes
    As Integer historyGroup, historyIdleFrames
    ' Optional key callbacks are borrowed and run on the GUI thread.
    As Any Ptr key_down_handler
    As Any Ptr key_press_handler
    As Any Ptr key_up_handler
    ' Appended opt-in state preserves existing field offsets. Rebuild clients
    ' with this header when the record grows; it is not a frozen binary ABI.
    ' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: These are mask-state fields, not stored source text.
    As Integer password_character, password_saved_wordwrap
    ' FB-LINTER: DISABLE-NEXT-LINE FBL008 FBL-SEC-004 REASON: This cached display contains only mask glyphs.
    As String password_display
    As String placeholder_text
    ' Existing editors keep visible selections on blur unless opted out.
    As Integer hide_selection_on_blur
    ' Optional byte limit for user/editor insertions; zero keeps legacy editors
    ' unlimited. Programmatic SetText and history restoration remain separate.
    As Long input_limit
    ' Compatibility field for editors that inspect the source byte limit.
    As Integer max_text_bytes
    ' Optional embedded-glyph styling keeps editor metrics and history intact.
    As Integer text_style
    As String cue_banner_text
    As ULong cue_banner_color
    As ULong caret_color
    As ULong surface_border_color, surface_background_color, surface_text_color
    As Integer current_line_highlight
    As ULong current_line_background_color
    As Integer line_range_highlight
    As Integer line_range_highlight_first, line_range_highlight_last
    As Integer line_numbers_visible, line_number_text_style_flags
    As ULong line_number_text_color, line_number_background_color
    As Integer auto_indent, indent_width, indent_with_tabs
    As Integer indent_guides_enabled, right_edge_column
    As ULong indent_guides_color, right_edge_color
    As Integer context_menu_latch
    As TextBoxTypedTextHandler typed_text_handler
    As TextBoxContextMenuHandler context_menu_handler
    As TextBoxNavigationHandler navigation_handler
    As TextBoxControlShortcutHandler control_shortcut_handler
    As TextBoxKeyEventHandler key_event_handler
    As TextBoxTextDisplayHandler text_display_handler
    As TextBoxTextColorHandler text_color_handler
    As TextBoxTextStyleHandler text_style_handler
    As TextBoxTextIndicatorHandler text_indicator_handler
    As TextBoxGutterMarkerHandler gutter_marker_handler
    As TextBoxGutterMarkerStyleHandler gutter_marker_style_handler
    As TextBoxGutterClickHandler gutter_click_handler
    As TextBoxFoldMarkerHandler fold_marker_handler
    As TextBoxFoldClickHandler fold_click_handler
    As TextBoxLineVisibilityHandler line_visibility_handler
    As Integer fold_gutter_width
    As ULong fold_margin_background_color
    As ULong fold_symbol_foreground_color, fold_symbol_background_color
    As Integer render_color_state, render_style_state
    As String display_text
    As ULong display_change_serial
    As Integer display_source_length
    As Integer display_valid
    ' Base font and temporary zoom compose without changing stored text.
    As Integer font_id, font_scale_percent, zoom_percent, extra_line_spacing
    ' A caller may hide the blinking caret for a passive or captured view.
    As Integer caret_visible
    ' Borrowed application lexer checkpoint; called only on the GUI thread.
    As TextBoxRenderStateHandler render_state_handler
    ' Exact layout observations avoid rescanning unchanged documents. Strings
    ' belong to this textbox and are released by its normal Delete lifetime.
    As String metrics_key
    As Integer metrics_valid, metrics_maximum_width
    ' A visibility callback may depend on external state. Caching that layout
    ' is opt-in; its owner sets viewport_dirty whenever that state changes.
    As Integer metrics_cache_callbacks
    As TextBoxMetricsStateHandler metrics_state_handler
    As Integer metrics_gutter_width, metrics_total_lines
    As Integer metrics_vertical_visible, metrics_horizontal_visible
    ' A fixed row index belongs to the exact metrics observation above. It
    ' stores unwrapped visible rows only and is consumed after metrics refresh.
    ' Thirty-two checkpoints bound storage on DOS and avoid full prefix walks.
    As Integer metrics_row_count
    As Integer metrics_row_index(0 To 31), metrics_row_position(0 To 31)
    As Integer metrics_row_source_number(0 To 31)
    As Integer metrics_row_source_length
    As String metrics_row_visibility_key
    As TextBoxLineVisibilityHandler metrics_row_visibility_handler
    As TextBoxMetricsStateHandler metrics_row_state_handler
    As Integer rendered_caret_x, rendered_caret_y
    As Integer rendered_caret_w, rendered_caret_h
    ' VBDOS BorderStyle affects the frame without changing editor metrics.
    As Integer border_style
End Type
Declare Function textbox_Create( _
    ByVal nm As String, ByVal txt As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal m As Integer, ByVal ww As Integer, _
    ByVal scrollbarMode As Integer = TEXTBOX_SCROLLBAR_AUTO _
) As Widget Ptr
Declare Sub textbox_Render(ByVal w As Widget Ptr)
' Applications using visual callbacks must append their external model state
' before assigning this observation to Widget.render_observation.
Declare Function textbox_GetRenderObservation(ByVal w As Widget Ptr) As String
Declare Function textbox_RenderObservationMatches(ByVal w As Widget Ptr, _
    ByRef previousKey As Const String, ByVal observationOffset As Integer) As Integer
Declare Function textbox_GetRenderDamage(ByVal w As Widget Ptr, _
    ByRef previousKey As Const String, ByRef nextKey As Const String, _
    ByRef x As Integer, ByRef y As Integer, _
    ByRef widthValue As Integer, ByRef heightValue As Integer) As Integer

' Opt-in row damage requires an observation of every callback-owned dependency.
Declare Function textbox_GetCursorRowRenderDamage(ByVal w As Widget Ptr, _
    ByRef previousKey As Const String, ByRef nextKey As Const String, _
    ByRef x As Integer, ByRef y As Integer, _
    ByRef widthValue As Integer, ByRef heightValue As Integer) As Integer
Declare Sub textbox_Update(ByVal w As Widget Ptr)
Declare Function textbox_GetText(ByVal w As Widget Ptr) As String
' Zero clears mask mode; visible ASCII bytes 33..126 select its glyph.
' Only single-line TextBoxes accept a mask. Text/selection queries stay real.
Declare Function textbox_SetPasswordChar( _
    ByVal w As Widget Ptr, ByVal character_code As Integer _
) As Integer
Declare Function textbox_GetPasswordChar(ByVal w As Widget Ptr) As Integer
' Guidance is presentation text and never becomes editable input.
Const TEXTBOX_PLACEHOLDER_MAX_LENGTH As Integer = 4096
Declare Function textbox_SetPlaceholder( _
    ByVal w As Widget Ptr, ByRef placeholder_text As Const String _
) As Integer
Declare Function textbox_GetPlaceholder(ByVal w As Widget Ptr) As String
Declare Function textbox_SetKeyDownHandler( _
    ByVal w As Widget Ptr, ByVal key_down_handler As Any Ptr _
) As Integer
Declare Function textbox_SetKeyPressHandler( _
    ByVal w As Widget Ptr, ByVal key_press_handler As Any Ptr _
) As Integer
Declare Function textbox_SetKeyUpHandler( _
    ByVal w As Widget Ptr, ByVal key_up_handler As Any Ptr _
) As Integer
Declare Sub textbox_Destroy(ByVal w As Widget Ptr)
Declare Sub textbox_ClearHistory(ByVal w As Widget Ptr)
Declare Function textbox_BeginEdit( _
    ByVal w As Widget Ptr, _
    ByVal groupId As Integer = TEXTBOX_HISTORY_GROUP_NONE _
) As Integer
Declare Sub textbox_EndEditGroup(ByVal w As Widget Ptr)
Declare Function textbox_Undo(ByVal w As Widget Ptr) As Integer
Declare Function textbox_Redo(ByVal w As Widget Ptr) As Integer
Declare Function textbox_CanUndo(ByVal w As Widget Ptr) As Integer
Declare Function textbox_CanRedo(ByVal w As Widget Ptr) As Integer
Declare Function textbox_SelectAll(ByVal w As Widget Ptr) As Integer
Declare Function textbox_HasSelection(ByVal w As Widget Ptr) As Integer
Declare Function textbox_GetCursorPosition(ByVal w As Widget Ptr) As Integer
Declare Function textbox_SetCursorPosition( _
    ByVal w As Widget Ptr, _
    ByVal cursor_position As Integer, _
    ByVal extend_selection As Integer = 0 _
) As Integer
Declare Function textbox_GetSelectionLength(ByVal w As Widget Ptr) As Integer
Declare Function textbox_GetSelectionStart(ByVal w As Widget Ptr) As Integer
Declare Function textbox_SetSelectionRange(ByVal w As Widget Ptr, _
    ByVal start_position As Integer, ByVal selection_length As Integer) As Integer
Declare Function textbox_InsertAtSelection(ByVal w As Widget Ptr, _
    ByRef replacement_text As Const String) As Integer
Declare Function textbox_SetHideSelection(ByVal w As Widget Ptr, ByVal hide_selection As Integer) As Integer
Declare Function textbox_GetHideSelection(ByVal w As Widget Ptr) As Integer
Declare Function textbox_GetSelectedText(ByVal w As Widget Ptr) As String
Declare Function textbox_GetLineColumn( _
    ByVal w As Widget Ptr, _
    ByRef line_number As Integer, _
    ByRef column_number As Integer _
) As Integer
Declare Function textbox_GotoLine( _
    ByVal w As Widget Ptr, _
    ByVal line_number As Integer, _
    ByVal column_number As Integer = 1 _
) As Integer
Declare Function textbox_FindText( _
    ByVal w As Widget Ptr, _
    ByVal search_text As String, _
    ByVal start_position As Integer = 0, _
    ByVal match_case As Integer = 0, _
    ByVal wrap_search As Integer = -1 _
) As Integer
Declare Function textbox_ReplaceSelection( _
    ByVal w As Widget Ptr, _
    ByVal replacement_text As String _
) As Integer
Declare Function textbox_ReplaceAll( _
    ByVal w As Widget Ptr, _
    ByVal search_text As String, _
    ByVal replacement_text As String, _
    ByVal match_case As Integer = 0 _
) As Integer
Declare Function textbox_IndentSelection(ByVal w As Widget Ptr) As Integer
Declare Function textbox_UnindentSelection(ByVal w As Widget Ptr) As Integer
Declare Function textbox_Copy(ByVal w As Widget Ptr) As Integer
Declare Function textbox_Cut(ByVal w As Widget Ptr) As Integer
Declare Function textbox_Paste(ByVal w As Widget Ptr) As Integer
Declare Sub textbox_SetReadOnly( _
    ByVal w As Widget Ptr, ByVal read_only As Integer _
)
Declare Function textbox_GetReadOnly(ByVal w As Widget Ptr) As Integer
' A nonnegative byte limit, with zero meaning unlimited. Changing it preserves
' existing text, selection and history. SetText/Undo/Redo do not truncate.
' Insertion and paste consume the room left after the selected bytes are
' removed; blocked input preserves the selection and pending redo transaction.
Declare Function textbox_SetInputLimit(ByVal w As Widget Ptr, ByVal byte_limit As Long) As Integer
Declare Function textbox_GetInputLimit(ByVal w As Widget Ptr) As Long
Declare Function textbox_SetTextStyle(ByVal w As Widget Ptr, ByVal text_style As Integer) As Integer
Declare Function textbox_GetTextStyle(ByVal w As Widget Ptr) As Integer
Declare Function textbox_SetBorderStyle( _
    ByVal w As Widget Ptr, ByVal border_style As Integer _
) As Integer
Declare Function textbox_GetBorderStyle(ByVal w As Widget Ptr) As Integer
Declare Function textbox_SetBackgroundColor( _
    ByVal w As Widget Ptr, ByVal background_color As ULong _
) As Integer
Declare Function textbox_ClearBackgroundColor(ByVal w As Widget Ptr) As Integer
Declare Function textbox_GetBackgroundColor( _
    ByVal w As Widget Ptr, ByRef background_color As ULong _
) As Integer
Declare Function textbox_SetForegroundColor( _
    ByVal w As Widget Ptr, ByVal foreground_color As ULong _
) As Integer
Declare Function textbox_ClearForegroundColor(ByVal w As Widget Ptr) As Integer
Declare Function textbox_GetForegroundColor( _
    ByVal w As Widget Ptr, ByRef foreground_color As ULong _
) As Integer
Declare Function textbox_SetSyntaxMode( _
    ByVal w As Widget Ptr, ByVal syntax_mode As Integer _
) As Integer
Declare Function textbox_GetSyntaxMode(ByVal w As Widget Ptr) As Integer
Declare Function textbox_SetSyntaxColor( _
    ByVal w As Widget Ptr, _
    ByVal color_kind As Integer, _
    ByVal syntax_color As ULong _
) As Integer
Declare Function textbox_GetSyntaxColor( _
    ByVal w As Widget Ptr, _
    ByVal color_kind As Integer, _
    ByRef syntax_color As ULong _
) As Integer
Declare Function textbox_ClearSyntaxColor( _
    ByVal w As Widget Ptr, ByVal color_kind As Integer _
) As Integer
Declare Function textbox_SetAcceptsTab( _
    ByVal w As Widget Ptr, ByVal accepts_tab As Integer _
) As Integer
Declare Function textbox_GetAcceptsTab(ByVal w As Widget Ptr) As Integer
' Opt in to Ctrl+]/Ctrl+[ and selection-preserving Tab indentation. Plain
' Tab still requires accepts_tab; Shift+Tab remains reverse focus traversal.
Declare Function textbox_SetBlockIndent( _
    ByVal w As Widget Ptr, ByVal block_indent As Integer _
) As Integer
Declare Function textbox_GetBlockIndent(ByVal w As Widget Ptr) As Integer
Declare Function textbox_SetLineNumbers( _
    ByVal w As Widget Ptr, ByVal line_numbers As Integer _
) As Integer
Declare Function textbox_GetLineNumbers(ByVal w As Widget Ptr) As Integer
Declare Function textbox_SetText( _
    ByVal w As Widget Ptr, _
    ByVal textValue As String, _
    ByVal resetHistory As Integer _
) As Integer
Declare Sub textbox_SetVerticalScrollbar( _
    ByVal w As Widget Ptr, ByVal scrollbarMode As Integer _
)
Declare Function textbox_GetVerticalScrollbarMode( _
    ByVal w As Widget Ptr _
) As Integer
Declare Sub textbox_SetScrollbarColors( _
    ByVal w As Widget Ptr, ByVal trackColor As ULong, _
    ByVal thumbColor As ULong, ByVal thumbBorderColor As ULong _
)
Declare Sub textbox_SetMaxTextBytes(ByVal w As Widget Ptr, ByVal maximumBytes As Integer)
Declare Sub textbox_SetCaretColor(ByVal w As Widget Ptr, ByVal caretColor As ULong)
Declare Sub textbox_SetCaretVisible(ByVal w As Widget Ptr, ByVal visible As Integer)
Declare Sub textbox_SetSurfaceColors( _
    ByVal w As Widget Ptr, ByVal borderColor As ULong, _
    ByVal backgroundColor As ULong, ByVal textColor As ULong _
)
Declare Sub textbox_SetCueBanner( _
    ByVal w As Widget Ptr, ByVal cueText As String, ByVal cueColor As ULong _
)
Declare Sub textbox_SetCurrentLineHighlight( _
    ByVal w As Widget Ptr, ByVal enabled As Integer, _
    ByVal backgroundColor As ULong _
)
Declare Sub textbox_SetLineRangeHighlight( _
    ByVal w As Widget Ptr, ByVal firstLine As Integer, _
    ByVal lastLine As Integer, ByVal enabled As Integer _
)
Declare Sub textbox_CenterPosition(ByVal w As Widget Ptr, ByVal position As Integer)
Declare Sub textbox_SetLineNumberGutter( _
    ByVal w As Widget Ptr, ByVal gutterWidth As Integer, _
    ByVal textColor As ULong, ByVal backgroundColor As ULong _
)
Declare Sub textbox_SetLineNumberTextStyle(ByVal w As Widget Ptr, ByVal styleFlags As Integer)
Declare Sub textbox_SetLineNumberVisibility(ByVal w As Widget Ptr, ByVal visible As Integer)
Declare Sub textbox_SetIndentBehavior( _
    ByVal w As Widget Ptr, ByVal indentWidth As Integer, _
    ByVal autoIndent As Integer, ByVal useTabs As Integer = 0 _
)
Declare Sub textbox_SetIndentGuides( _
    ByVal w As Widget Ptr, ByVal enabled As Integer, _
    ByVal guideColor As ULong _
)
Declare Sub textbox_SetRightEdge( _
    ByVal w As Widget Ptr, ByVal columnNumber As Integer, _
    ByVal edgeColor As ULong _
)
Declare Sub textbox_SetTypedTextHandler( _
    ByVal w As Widget Ptr, ByVal typedTextHandler As TextBoxTypedTextHandler _
)
Declare Sub textbox_SetContextMenuHandler( _
    ByVal w As Widget Ptr, ByVal contextMenuHandler As TextBoxContextMenuHandler _
)
Declare Sub textbox_SetNavigationHandler( _
    ByVal w As Widget Ptr, ByVal navigationHandler As TextBoxNavigationHandler _
)
Declare Sub textbox_SetControlShortcutHandler( _
    ByVal w As Widget Ptr, _
    ByVal shortcutHandler As TextBoxControlShortcutHandler _
)
Declare Sub textbox_SetKeyEventHandler( _
    ByVal w As Widget Ptr, ByVal keyEventHandler As TextBoxKeyEventHandler _
)
Declare Sub textbox_SetZoomPercent(ByVal w As Widget Ptr, ByVal percent As Integer)
Declare Sub textbox_SetFontScalePercent( _
    ByVal w As Widget Ptr, ByVal fontPercent As Integer _
)
Declare Sub textbox_SetLineSpacing( _
    ByVal w As Widget Ptr, ByVal extraPixels As Integer _
)
Declare Sub textbox_SetFont(ByVal w As Widget Ptr, ByVal font_id As Integer)
Declare Sub textbox_SetVirtualSpace(ByVal w As Widget Ptr, ByVal enabled As Integer)
Declare Sub textbox_ClearVirtualSpace(ByVal w As Widget Ptr)
Declare Sub textbox_SetTextDisplayHandler( _
    ByVal w As Widget Ptr, ByVal displayHandler As TextBoxTextDisplayHandler _
)
Declare Sub textbox_SetTextColorHandler( _
    ByVal w As Widget Ptr, ByVal colorHandler As TextBoxTextColorHandler _
)
Declare Sub textbox_SetRenderStateHandler( _
    ByVal w As Widget Ptr, ByVal stateHandler As TextBoxRenderStateHandler _
)
Declare Sub textbox_SetMetricsStateHandler( _
    ByVal w As Widget Ptr, ByVal stateHandler As TextBoxMetricsStateHandler _
)
Declare Sub textbox_SetTextStyleHandler( _
    ByVal w As Widget Ptr, ByVal styleHandler As TextBoxTextStyleHandler _
)
Declare Sub textbox_SetTextIndicatorHandler( _
    ByVal w As Widget Ptr, _
    ByVal indicatorHandler As TextBoxTextIndicatorHandler _
)
Declare Sub textbox_SetGutterMarkerHandler( _
    ByVal w As Widget Ptr, ByVal markerHandler As TextBoxGutterMarkerHandler _
)
Declare Sub textbox_SetGutterMarkerStyleHandler( _
    ByVal w As Widget Ptr, _
    ByVal markerHandler As TextBoxGutterMarkerStyleHandler _
)
Declare Sub textbox_SetGutterClickHandler( _
    ByVal w As Widget Ptr, ByVal clickHandler As TextBoxGutterClickHandler _
)
Declare Sub textbox_SetFoldGutter( _
    ByVal w As Widget Ptr, ByVal gutterWidth As Integer, _
    ByVal markerHandler As TextBoxFoldMarkerHandler, _
    ByVal clickHandler As TextBoxFoldClickHandler _
)
Declare Sub textbox_SetFoldColors( _
    ByVal w As Widget Ptr, ByVal marginBackgroundColor As ULong, _
    ByVal symbolForegroundColor As ULong, _
    ByVal symbolBackgroundColor As ULong _
)
Declare Sub textbox_SetLineVisibilityHandler( _
    ByVal w As Widget Ptr, _
    ByVal visibilityHandler As TextBoxLineVisibilityHandler _
)
Declare Sub textbox_SetHorizontalScrollbar( _
    ByVal w As Widget Ptr, ByVal scrollbarMode As Integer _
)
Declare Function textbox_GetHorizontalScrollbarMode( _
    ByVal w As Widget Ptr _
) As Integer
#endif

' end of textbox.bi
