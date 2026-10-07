/'
    Project: omaGUI
    ---------------
    File: backend.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for backend.

    Purpose:
        Declare the gfxlib graphics, text, clipping, and window interface.

    Responsibilities:
        - configure fixed or resizable platform windows
        - configure true-color and balanced indexed-color display modes
        - report the live drawable area after a window resize
        - expose primitive and alpha-aware drawing operations
        - expose embedded-font measurement and rendering operations
        - load complete Unicode glyph packs for UTF-8 text
        - expose bitmap italic rendering without changing glyph advance

    This file intentionally does NOT contain:
        - widget-specific behavior
        - input polling
        - application-specific layout rules
'/

#ifndef __BACKEND_BI__
#define __BACKEND_BI__

#include "fbgfx.bi"

#ifndef RGB
#define RGB(r,g,b) (((CUInt(r) And &hFF) Shl 16) Or ((CUInt(g) And &hFF) Shl 8) Or (CUInt(b) And &hFF))
#endif

#ifndef RGBA
#define RGBA(r,g,b,a) (((CUInt(a) And &hFF) Shl 24) Or ((CUInt(r) And &hFF) Shl 16) Or ((CUInt(g) And &hFF) Shl 8) Or (CUInt(b) And &hFF))
#endif

' -------------------------------------------------------------------------
' Text constants
' -------------------------------------------------------------------------

Const BACKEND_FONT_DEFAULT As Integer = 0
Const BACKEND_FONT_ARIAL_10_REGULAR As Integer = 1
Const BACKEND_FONT_ARIAL_12_BOLD As Integer = 2
Const BACKEND_FONT_LIBERATION_SANS_18_BOLD As Integer = 3
Const BACKEND_FONT_LIBERATION_SERIF_18_REGULAR As Integer = 4
Const BACKEND_FONT_CUSTOM As Integer = 5
Const BACKEND_FONT_CASCADIA_MONO As Integer = 6
' Supplemental code points loaded from a complete Unicode font pack.
Const BACKEND_FONT_UNICODE_FALLBACK As Integer = 7
' Fixed-cell Spleen 8x16 bitmap font bundled for the legacy Terminal option.
Const BACKEND_FONT_TERMINAL As Integer = 8

' OpenSesh's redistributable font names use the same embedded slots.
Const BACKEND_FONT_UI_10_REGULAR As Integer = BACKEND_FONT_ARIAL_10_REGULAR
Const BACKEND_FONT_UI_12_BOLD As Integer = BACKEND_FONT_ARIAL_12_BOLD
Const BACKEND_FONT_UI_18_BOLD As Integer = BACKEND_FONT_LIBERATION_SANS_18_BOLD
Const BACKEND_FONT_UI_SERIF_18_REGULAR As Integer = _
    BACKEND_FONT_LIBERATION_SERIF_18_REGULAR

' Synthetic styles preserve glyph advances and the selected font height.
Const BACKEND_TEXT_STYLE_NORMAL As Integer = 0
Const BACKEND_TEXT_STYLE_BOLD As Integer = 1
Const BACKEND_TEXT_STYLE_ITALIC As Integer = 2
Const BACKEND_TEXT_STYLE_UNDERLINE As Integer = 4
Const BACKEND_TEXT_STYLE_STRIKEOUT As Integer = 8
Const BACKEND_TEXT_STYLE_ALL As Integer = 15

Const BACKEND_ALIGN_LEFT As Integer = 0
Const BACKEND_ALIGN_CENTER As Integer = 1
Const BACKEND_ALIGN_RIGHT As Integer = 2

Const BACKEND_ALIGN_TOP As Integer = 0
Const BACKEND_ALIGN_MIDDLE As Integer = 1
Const BACKEND_ALIGN_BOTTOM As Integer = 2

' -------------------------------------------------------------------------
' Backend API
' -------------------------------------------------------------------------

Const BACKEND_WINDOW_FIXED As UInteger = 0
Const BACKEND_WINDOW_RESIZABLE As UInteger = 1
Const BACKEND_WINDOW_FULLSCREEN As UInteger = 2
Const BACKEND_DISPLAY_ENABLED As Integer = 0
Const BACKEND_HEADLESS As Integer = -1
' A null gfxlib screen keeps pixels available for renderer tests.
Const BACKEND_HEADLESS_DRAWABLE As Integer = -2

Const BACKEND_COLOR_DEPTH_MONOCHROME As Integer = 1
Const BACKEND_COLOR_DEPTH_16_COLOR As Integer = 4
Const BACKEND_COLOR_DEPTH_256_COLOR As Integer = 8
Const BACKEND_COLOR_DEPTH_HIGH_COLOR As Integer = 16
Const BACKEND_COLOR_DEPTH_TRUE_COLOR As Integer = 32

Declare Sub backend_Init( _
    ByVal w As Integer, _
    ByVal h As Integer, _
    ByVal headless As Integer = 0, _
    ByVal windowFlags As UInteger = BACKEND_WINDOW_FIXED, _
    ByVal colorDepth As Integer = BACKEND_COLOR_DEPTH_TRUE_COLOR _
)
Declare Sub backend_Exit()
' Select one persistent visible page for damage-based drawing. Call while
' ScreenLock is held and repaint fully when it reports a page-mode change.
Declare Function backend_UseRetainedPage() As Integer
Declare Function backend_GetFontGeneration() As ULongInt
Declare Function backend_WindowCloseRequested() As Integer
/'
    Ask the active window system to restore and raise the gfxlib window.
    Platforms without a supported activation path return zero.
'/
Declare Function backend_RaiseWindow() As Integer
/'
    Recreate both gfx pages while changing between fixed, resizable, and
    full-screen modes. The function returns zero when gfxlib rejects the mode.
'/
Declare Function backend_SetWindowMode( _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal windowFlags As UInteger _
) As Integer
Declare Sub backend_GetSize(ByRef w As Integer, ByRef h As Integer)
Declare Function backend_IsResizable() As Integer
Declare Function backend_GetColorDepth() As Integer
Declare Function backend_SetColorDepth(ByVal colorDepth As Integer) As Integer

Type BackendDisplayState
    As Integer width, height, color_depth, headless
    As UInteger window_flags
End Type
Declare Function backend_CaptureDisplay(ByRef display_state As BackendDisplayState) As Integer
Declare Function backend_RestoreDisplay(ByRef display_state As Const BackendDisplayState) As Integer

Declare Sub backend_Clear(ByVal clr As ULong = 0)
Declare Sub backend_Flip()
/'
    Wait between foreground GUI polls, outside drawing and application locks.
    Nonpositive waits return immediately; waits are capped at one second.
    OMAGUI_DOSBOX_X_IDLE selects the qualified DOSBox-X host idle API on DOS.
'/
Declare Sub backend_Idle(ByVal milliseconds As Integer)
Declare Function backend_GetWorkPage() As Integer

/'
    Allocate and load gfxlib image buffers for omaGUI's native image widgets.
    Callers own returned buffers and release them with ImageDestroy.
'/
Declare Function backend_CreateImage( _
    ByVal imageWidth As Integer, ByVal imageHeight As Integer, _
    ByVal backgroundColor As ULong, ByVal imageDepth As Integer _
) As Any Ptr
Declare Function backend_LoadImageFile( _
    ByVal filePath As String, ByVal imageBuffer As Any Ptr _
) As Integer

Declare Sub backend_Rect(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, ByVal clr As ULong, ByVal filled As Integer = 0)
Declare Sub backend_Line(ByVal x1 As Integer, ByVal y1 As Integer, ByVal x2 As Integer, ByVal y2 As Integer, ByVal clr As ULong)
/'
    Return zero when the caller should use its ordinary software fallback.
    The gfxlib3 path queues one bounded packet for each call.
'/
Declare Function backend_DrawHorizontalSpans( _
    ByVal spanCount As Integer, ByVal spanX1 As Integer Ptr, _
    ByVal spanX2 As Integer Ptr, ByVal spanY As Integer Ptr, _
    ByVal clr As ULong, ByVal alpha As Integer _
) As Integer
Declare Function backend_DrawAlphaMask( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal maskWidth As Integer, ByVal maskHeight As Integer, _
    ByVal coverage As UByte Ptr, ByVal clr As ULong _
) As Integer
Declare Sub backend_LineEx(ByVal x1 As Integer, ByVal y1 As Integer, ByVal x2 As Integer, ByVal y2 As Integer, ByVal clr As ULong, ByVal line_width As Integer = 1, ByVal alpha As Integer = 255)
Declare Sub backend_RectEx(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, ByVal clr As ULong, ByVal filled As Integer = 0, ByVal line_width As Integer = 1, ByVal alpha As Integer = 255)
Declare Sub backend_PSet(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong)
Declare Sub backend_PSetAlpha(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal alpha As Integer)
Declare Sub backend_Circle(ByVal x As Integer, ByVal y As Integer, ByVal r As Integer, ByVal clr As ULong, ByVal filled As Integer = 0)
' Rounded corners are bounded to 32 pixels and use the same clipping as lines.
Declare Sub backend_RoundRect( _
    ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, _
    ByVal radius As Integer, ByVal clr As ULong, ByVal filled As Integer = 0 _
)
Declare Sub backend_Curve(ByVal x1 As Integer, ByVal y1 As Integer, ByVal x2 As Integer, ByVal y2 As Integer, ByVal x3 As Integer, ByVal y3 As Integer, ByVal clr As ULong)
Declare Sub backend_DrawImage( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal imageBuffer As Any Ptr, ByVal useAlpha As Integer = -1, _
    ByVal preserveTransparent As Integer = 0 _
)

Declare Sub backend_Print(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal text As String)
Declare Sub backend_PrintByte(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal character_code As Integer)
Declare Sub backend_PrintBytes(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByRef bytes_text As Const String)
Declare Sub backend_PrintStyled( _
    ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, _
    ByVal text As String, ByVal text_style As Integer, _
    ByVal font_id As Integer = BACKEND_FONT_DEFAULT _
)
Declare Sub backend_SetCustomFont(ByVal glyphs As UByte Ptr Ptr)
/'
    Register a caller-owned, code-point-sorted Unicode glyph table. The arrays
    and glyph data must remain valid until the table is replaced or cleared.
'/
Declare Function backend_SetUnicodeGlyphs( _
    ByVal codepoints As UInteger Ptr, _
    ByVal glyphs As UByte Ptr Ptr, _
    ByVal glyph_count As Integer _
) As Integer
/'
    Load a sorted OGF1 bitmap font pack into a backend-owned font slot.
    Default, Arial, Cascadia, Terminal, and Unicode fallback slots accept
    packs. For missing non-ASCII glyphs, the CJK pack is searched first and
    the default UI pack supplies mapped marks or symbols it does not contain.
    Its zero-advance mark takes precedence when the selected or CJK face gives
    the same combining codepoint a spacing advance.
    Loading an embedded slot overrides its face until packs are cleared.
    Load UI packs before creating controls so their measurements stay valid.
'/
Declare Function backend_LoadFontPack( _
    ByVal font_id As Integer, ByVal filename As String _
) As Integer
Declare Sub backend_ClearFontPacks()
Declare Function backend_IsFontAvailable(ByVal font_id As Integer) As Integer
Declare Function backend_GetFontPointSize(ByVal font_id As Integer) As Integer
Declare Function backend_GetFontAscent(ByVal font_id As Integer) As Integer
' Decode one scalar from UTF-8; byteIndex is zero-based and advances on errors.
Declare Function backend_ReadUTF8Codepoint(ByRef text As Const String, ByRef byteIndex As Integer) As Integer
Declare Sub backend_PrintScaled(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal text As String, ByVal scale_x As Integer = 1, ByVal scale_y As Integer = 1)
' Font size and temporary editor zoom compose into a 25..900 percent scale.
' These limits bound glyph rendering; textbox zoom itself remains 50..300.
Const BACKEND_MIN_FONT_PERCENT As Integer = 25
Const BACKEND_MAX_FONT_PERCENT As Integer = 900
Declare Sub backend_PrintPercent(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal text As String, ByVal percent As Integer)
' Font-aware percentage rendering keeps editor geometry aligned with glyphs.
Declare Sub backend_PrintFontPercent( _
    ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, _
    ByVal text As String, ByVal font_id As Integer, ByVal percent As Integer _
)
' Italic text shears glyph rows but keeps the regular glyph advance.
Declare Sub backend_PrintItalicPercent( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal clr As ULong, ByVal text As String, ByVal percent As Integer _
)
Declare Sub backend_PrintItalicFontPercent( _
    ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, _
    ByVal text As String, ByVal font_id As Integer, ByVal percent As Integer _
)
Declare Sub backend_PrintFont(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal text As String, ByVal font_id As Integer)
Declare Sub backend_PrintFontAlpha(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal text As String, ByVal font_id As Integer, ByVal alpha As Integer)
Declare Sub backend_PrintScaledFont(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal text As String, ByVal font_id As Integer, ByVal scale_x As Integer = 1, ByVal scale_y As Integer = 1)
Declare Sub backend_PrintScaledFontAlpha( _
    ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, _
    ByVal text As String, ByVal font_id As Integer, _
    ByVal scale_x As Integer = 1, ByVal scale_y As Integer = 1, _
    ByVal alpha As Integer = 255 _
)
Declare Sub backend_PrintAligned( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, ByVal clr As ULong, _
    ByVal text As String, ByVal font_id As Integer = BACKEND_FONT_DEFAULT, _
    ByVal horizontal_align As Integer = BACKEND_ALIGN_LEFT, _
    ByVal vertical_align As Integer = BACKEND_ALIGN_TOP _
)
Declare Sub backend_PrintAlignedAlpha( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, ByVal clr As ULong, _
    ByVal text As String, ByVal font_id As Integer = BACKEND_FONT_DEFAULT, _
    ByVal horizontal_align As Integer = BACKEND_ALIGN_LEFT, _
    ByVal vertical_align As Integer = BACKEND_ALIGN_TOP, _
    ByVal alpha As Integer = 255 _
)
Declare Sub backend_PrintAlignedScaled( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, ByVal clr As ULong, _
    ByVal text As String, ByVal font_id As Integer = BACKEND_FONT_DEFAULT, _
    ByVal horizontal_align As Integer = BACKEND_ALIGN_LEFT, _
    ByVal vertical_align As Integer = BACKEND_ALIGN_TOP, _
    ByVal scale_x As Integer = 1, ByVal scale_y As Integer = 1 _
)
Declare Sub backend_PrintAlignedScaledAlpha( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, ByVal clr As ULong, _
    ByVal text As String, ByVal font_id As Integer = BACKEND_FONT_DEFAULT, _
    ByVal horizontal_align As Integer = BACKEND_ALIGN_LEFT, _
    ByVal vertical_align As Integer = BACKEND_ALIGN_TOP, _
    ByVal scale_x As Integer = 1, ByVal scale_y As Integer = 1, _
    ByVal alpha As Integer = 255 _
)
Declare Function backend_GetTextWidth(ByVal text As String) As Integer
Declare Function backend_GetTextWidthScaled(ByVal text As String, ByVal scale_x As Integer = 1) As Integer
Declare Function backend_GetTextWidthPercent(ByVal text As String, ByVal percent As Integer) As Integer
Declare Function backend_GetTextWidthFontPercent( _
    ByVal text As String, ByVal font_id As Integer, ByVal percent As Integer _
) As Integer
Declare Function backend_GetTextWidthFont(ByVal text As String, ByVal font_id As Integer) As Integer
Declare Function backend_GetTextWidthScaledFont(ByVal text As String, ByVal font_id As Integer, ByVal scale_x As Integer = 1) As Integer
Declare Function backend_GetTextHeight() As Integer
Declare Function backend_GetTextHeightScaled(ByVal scale_y As Integer = 1) As Integer
Declare Function backend_GetTextHeightPercent(ByVal percent As Integer) As Integer
Declare Function backend_GetTextHeightFontPercent( _
    ByVal font_id As Integer, ByVal percent As Integer _
) As Integer
Declare Function backend_GetTextHeightFont(ByVal font_id As Integer) As Integer
Declare Function backend_GetTextHeightScaledFont(ByVal font_id As Integer, ByVal scale_y As Integer = 1) As Integer

Declare Sub backend_SetClip(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer)
Declare Sub backend_GetClip(ByRef x As Integer, ByRef y As Integer, ByRef w As Integer, ByRef h As Integer)
Declare Sub backend_ResetClip()

Declare Sub backend_SaveSnapshot(ByVal filename As String)

#endif

' end of backend.bi
