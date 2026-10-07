/'
    Project: omaGUI
    ---------------
    File: backend_gfxlib.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI backend_gfxlib implementation imported through omaGUI.bi.

    Purpose:
        Implement omaGUI drawing and window management with FreeBASIC gfxlib.

    Responsibilities:
        - create fixed or resizable double-buffered gfxlib screens
        - recreate those screens when an application changes window mode
        - expose supported native window activation through one backend call
        - configure predictable palettes for indexed-color modes
        - report the live drawable size to reactive GUI layouts
        - swap complete pages at the display refresh boundary
        - own one balanced Windows timer request while a visible legacy screen exists
        - draw primitives and alpha-mapped embedded fonts
        - load and render Unicode font packs with glyph metrics

    Ownership:
        The active gfxlib screen, reusable point packet, and loaded font packs
        belong to this module and are released by backend_Exit. Image buffers
        returned to callers belong to those callers.

    This file intentionally does NOT contain:
        - widget layout or input dispatch
        - application-specific rendering
'/

#lang "fb"

#include once "src/backend/backend.bi"
#include once "src/backend/input.bi"
#include once "src/backend/font_data.bi"
#include once "src/backend/theme.bi"
#include once "crt/string.bi"
#include once "src/backend/backend_idle.bi"
#If Defined(__FB_WIN32__) AndAlso Not Defined(OMAGUI_PORTABLE_ONLY)
#include once "windows.bi"
#EndIf
#If Defined(__FB_WIN32__) And Not Defined(__FB_GFXLIB3__) And _
    Not Defined(OMAGUI_PORTABLE_ONLY)
#include once "win/mmsystem.bi"
#EndIf
#Ifdef __FB_GFXLIB3__
#include once "fbgfx3.bi"
#EndIf

#Ifdef __FB_RISCOS__
/'
    The Wimp driver presents dirty rows when gfxlib releases its drawing
    lock. ScreenSet page switching traps on that driver, so use one page.
'/
Const BACKEND_GFX_VISIBLE_PAGE As Integer = 0
Const BACKEND_GFX_WORK_PAGE As Integer = 0
Const BACKEND_GFX_PAGE_COUNT As Integer = 1
#Else
Const BACKEND_GFX_VISIBLE_PAGE As Integer = 0
Const BACKEND_GFX_WORK_PAGE As Integer = 1
Const BACKEND_GFX_PAGE_COUNT As Integer = 2
#EndIf
Private Dim Shared As UByte Ptr Ptr backend_CustomFontGlyphs
Private Dim Shared As UInteger Ptr backend_UnicodeCodepoints
Private Dim Shared As UByte Ptr Ptr backend_UnicodeGlyphs
Private Dim Shared As Integer backend_UnicodeGlyphCount
Private Type BackendFontGlyphIndex
    As UInteger codepoint
    As UByte Ptr bitmap
    As Integer advance
    As Integer bearing_x, bearing_y
End Type
Private Type BackendFontPack
    As BackendFontGlyphIndex Ptr glyphs
    ' Printable ASCII has 95 codepoints. Entries borrow this pack's glyph
    ' storage and are replaced or cleared with it, on the GUI thread.
    As BackendFontGlyphIndex Ptr ascii_glyphs(32 To 126)
    As UByte Ptr bitmap_storage
    As Integer glyph_count
    As Integer line_height, ascent
    As Integer point_size
End Type
' Bound both temporary file data and retained bitmaps during pack loading.
Private Const BACKEND_FONT_PACK_MAX_BYTES As ULongInt = 67108864
' Maximum scalar values after excluding UTF-8 controls and surrogates.
Private Const BACKEND_FONT_PACK_MAX_GLYPHS As Integer = 1111999
Private Const BACKEND_FONT_PACK_HEADER_BYTES As Integer = 20
Private Const BACKEND_FONT_PACK_GLYPH_HEADER_BYTES As Integer = 14
Private Dim Shared As BackendFontPack backend_FontPacks( _
    0 To BACKEND_FONT_TERMINAL _
)
Const BACKEND_CURVE_STEP As Double = 0.05
Const BACKEND_8BIT_COLOR_CUBE_SIZE As Integer = 216
Const BACKEND_8BIT_GRAY_COUNT As Integer = 40
' A 12% glyph-height shear provides a small bitmap italic slant.
Const BACKEND_ITALIC_SHEAR_PERCENT As Integer = 12
Const BACKEND_8BIT_GRAY_THRESHOLD As Integer = 18
Const BACKEND_CLIP_STACK_CAPACITY As Integer = 128
Const BACKEND_PRESENTATION_HZ As Double = 60.0
Const BACKEND_COARSE_WAIT_MARGIN_SECONDS As Double = 0.001
#Ifdef __FB_GFXLIB3__
/'
    Bound temporary glyph packets so an unexpectedly long label cannot make
    the UI allocate an arbitrary amount of memory. Larger text retains the
    established pixel renderer as a correctness fallback.
'/
Const BACKEND_GFX3_TEXT_POINT_LIMIT As ULongInt = 262144
Const BACKEND_GFX3_SPAN_POINT_LIMIT As ULongInt = 262144

Private Function backend_Gfx3Alpha( _
    ByVal alpha As Integer _
) As ULong
    If alpha <= 0 Then Return 0
    If alpha >= 255 Then Return 255

    /'
        gfxlib alpha primitives divide by 256, while omaGUI's established
        software renderer divides by 255. Advancing a partial alpha value by
        one preserves the closest integer result without changing transparent
        or opaque pixels. Channel rounding can still differ by at most one.
    '/
    Return CULng(alpha + 1)
End Function
#EndIf

/'
    Backend-local module state

    The backend runtime owns this fixed-capacity state. It has static lifetime
    because independent drawing entry points share one active gfxlib screen.
    No widget or application code mutates it directly.
'/
Dim Shared backend_DoubleBufferActive As Integer
Dim Shared As ULongInt backend_FontGeneration
Dim Shared backend_GfxWorkPage As Integer
Dim Shared backend_GfxVisiblePage As Integer
Dim Shared backend_Resizable As Integer
Dim Shared backend_RequestedWidth As Integer
Private Dim Shared As Integer backend_HeadlessActive
Dim Shared backend_RequestedHeight As Integer
Dim Shared backend_WindowFlags As UInteger
Dim Shared backend_ColorDepth As Integer
Dim Shared backend_ClipDepth As Integer
Dim Shared backend_ClipOverflowDepth As Integer
Dim Shared backend_ClipX1(0 To BACKEND_CLIP_STACK_CAPACITY - 1) As Integer
Dim Shared backend_ClipY1(0 To BACKEND_CLIP_STACK_CAPACITY - 1) As Integer
Dim Shared backend_ClipX2(0 To BACKEND_CLIP_STACK_CAPACITY - 1) As Integer
Dim Shared backend_ClipY2(0 To BACKEND_CLIP_STACK_CAPACITY - 1) As Integer
Dim Shared backend_LastPresentationClock As Double
#If Defined(__FB_WIN32__) And Not Defined(__FB_GFXLIB3__) And _
    Not Defined(OMAGUI_PORTABLE_ONLY)
Const BACKEND_TIMER_PERIOD_MILLISECONDS As ULong = 1
Dim Shared backend_TimerPeriodActive As Integer
#EndIf
#Ifdef __FB_GFXLIB3__
' gfxlib3 copies a submitted packet before this reusable array changes.
Dim Shared backend_Gfx3SpanPoints() As fb.Gfx3Point
Dim Shared backend_Gfx3SpanPointCapacity As ULongInt
#EndIf

' -------------------------------------------------------------------------
' Helpers: Screen configuration
' -------------------------------------------------------------------------

#If Defined(__FB_WIN32__) And Not Defined(__FB_GFXLIB3__) And _
    Not Defined(OMAGUI_PORTABLE_ONLY)
Private Sub backend_SetPresentationTiming(ByVal active As Integer)
    /'
        Coarse Windows waits can consume the remainder of a 60 Hz frame.
        Keep one balanced timer-resolution request for a visible legacy
        gfxlib window. The frame clock itself remains Timer.
    '/
    If active <> 0 Then
        If backend_TimerPeriodActive = 0 Then
            If timeBeginPeriod(BACKEND_TIMER_PERIOD_MILLISECONDS) = 0 Then _
                backend_TimerPeriodActive = -1
        End If
    ElseIf backend_TimerPeriodActive <> 0 Then
        ' fblint: disable-next-line FBL310 REASON: The Windows-only branch uses declarations supplied by windows.bi and the system headers.
        timeEndPeriod BACKEND_TIMER_PERIOD_MILLISECONDS
        backend_TimerPeriodActive = 0
    End If
End Sub
#EndIf

Private Function backend_IsSupportedColorDepth( _
    ByVal colorDepth As Integer _
) As Integer

    Select Case colorDepth
    Case BACKEND_COLOR_DEPTH_MONOCHROME, _
         BACKEND_COLOR_DEPTH_16_COLOR, _
         BACKEND_COLOR_DEPTH_256_COLOR, _
         BACKEND_COLOR_DEPTH_HIGH_COLOR, _
         BACKEND_COLOR_DEPTH_TRUE_COLOR
        Return -1
    End Select

    Return 0
End Function


Private Sub backend_Get16ColorPaletteEntry( _
    ByVal colorIndex As Integer, _
    ByRef redValue As Integer, _
    ByRef greenValue As Integer, _
    ByRef blueValue As Integer _
)

    /'
        The 16-color mode uses the conventional VGA palette. In particular,
        color 0 is black and color 15 is white, so low-depth applications get
        stable results instead of depending on a platform driver palette.
    '/
    Select Case colorIndex
    Case 0  : redValue = 0   : greenValue = 0   : blueValue = 0
    Case 1  : redValue = 0   : greenValue = 0   : blueValue = 170
    Case 2  : redValue = 0   : greenValue = 170 : blueValue = 0
    Case 3  : redValue = 0   : greenValue = 170 : blueValue = 170
    Case 4  : redValue = 170 : greenValue = 0   : blueValue = 0
    Case 5  : redValue = 170 : greenValue = 0   : blueValue = 170
    Case 6  : redValue = 170 : greenValue = 85  : blueValue = 0
    Case 7  : redValue = 170 : greenValue = 170 : blueValue = 170
    Case 8  : redValue = 85  : greenValue = 85  : blueValue = 85
    Case 9  : redValue = 85  : greenValue = 85  : blueValue = 255
    Case 10 : redValue = 85  : greenValue = 255 : blueValue = 85
    Case 11 : redValue = 85  : greenValue = 255 : blueValue = 255
    Case 12 : redValue = 255 : greenValue = 85  : blueValue = 85
    Case 13 : redValue = 255 : greenValue = 85  : blueValue = 255
    Case 14 : redValue = 255 : greenValue = 255 : blueValue = 85
    Case Else
        redValue = 255 : greenValue = 255 : blueValue = 255
    End Select
End Sub


Private Sub backend_ConfigureIndexedPalette(ByVal colorDepth As Integer)
    Dim As Integer colorIndex
    Dim As Integer redValue
    Dim As Integer greenValue
    Dim As Integer blueValue

    Select Case colorDepth
    Case BACKEND_COLOR_DEPTH_MONOCHROME
        Palette 0, 0, 0, 0
        Palette 1, 255, 255, 255

    Case BACKEND_COLOR_DEPTH_16_COLOR
        For colorIndex = 0 To 15
            backend_Get16ColorPaletteEntry _
                colorIndex, redValue, greenValue, blueValue
            Palette colorIndex, redValue, greenValue, blueValue
        Next colorIndex

    Case BACKEND_COLOR_DEPTH_256_COLOR
        /'
            The first 216 entries form a 6 x 6 x 6 RGB cube. The remaining 40
            entries form a grayscale ramp. The dedicated ramp prevents neutral
            GUI colors from taking on the blue or green cast common to 3:3:2
            palettes while retaining a useful range of saturated colors.
        '/
        For colorIndex = 0 To BACKEND_8BIT_COLOR_CUBE_SIZE - 1
            redValue = (colorIndex \ 36) * 51
            greenValue = ((colorIndex \ 6) Mod 6) * 51
            blueValue = (colorIndex Mod 6) * 51
            Palette colorIndex, redValue, greenValue, blueValue
        Next colorIndex

        For colorIndex = 0 To BACKEND_8BIT_GRAY_COUNT - 1
            redValue = (colorIndex * 255) \ _
                (BACKEND_8BIT_GRAY_COUNT - 1)
            Palette BACKEND_8BIT_COLOR_CUBE_SIZE + colorIndex, _
                redValue, redValue, redValue
        Next colorIndex
    End Select
End Sub


Private Function backend_CreateScreen( _
    ByVal w As Integer, _
    ByVal h As Integer, _
    ByVal windowFlags As UInteger, _
    ByVal colorDepth As Integer _
) As Integer

    Dim As Integer actualDepth
    Dim As Integer actualHeight
    Dim As Integer actualWidth
    Dim As Integer screenResult
    Dim As UInteger gfxFlags
#Ifdef __FB_RISCOS__
    Dim As Integer desktopDepth, desktopWidth, desktopHeight
    Dim As Integer safeWidth, safeHeight
#EndIf

    If w < 1 OrElse h < 1 Then Return 0
    If backend_IsSupportedColorDepth(colorDepth) = 0 Then Return 0

#Ifdef __FB_RISCOS__
    /'
        Oversized ScreenRes requests trap in the Wimp driver. Leave room for
        window furniture and the icon bar when fitting to the desktop.
    '/
    ScreenInfo desktopWidth, desktopHeight, desktopDepth
    safeWidth = (desktopWidth \ 5) * 4
    safeHeight = (desktopHeight \ 5) * 4
    If safeWidth > 0 AndAlso w > safeWidth Then w = safeWidth
    If safeHeight > 0 AndAlso h > safeHeight Then h = safeHeight
#EndIf

    If backend_HeadlessActive = BACKEND_HEADLESS Then
        Screen 0
        backend_GfxWorkPage = BACKEND_GFX_VISIBLE_PAGE
        backend_GfxVisiblePage = BACKEND_GFX_VISIBLE_PAGE
        backend_DoubleBufferActive = 0
        backend_Resizable = 0
        backend_RequestedWidth = w
        backend_RequestedHeight = h
        backend_WindowFlags = windowFlags
        backend_ColorDepth = colorDepth
        backend_ClipDepth = 0
        backend_ClipOverflowDepth = 0
        Return -1
    End If

    gfxFlags = 0
    If (windowFlags And BACKEND_WINDOW_RESIZABLE) <> 0 Then
#If __FB_VERSION__ >= "1.20.0"
#If Not Defined(__FB_ANDROID__) And Not Defined(__FB_AROS__) And _
    Not Defined(__FB_RISCOS__) And Not Defined(__FB_DOS__)
        /'
            The stable 1.10 gfxlib header has no resizable-window flag. Leave
            that mode fixed-size. Android owns surface resizing, while AROS
            and RISC OS expose fixed gfxlib windows. DOS uses fixed BIOS modes
            and its drivers do not provide the resize callback gfxlib requires.
        '/
        gfxFlags Or= FB.GFX_RESIZABLE
#EndIf
#EndIf
    End If
    If (windowFlags And BACKEND_WINDOW_FULLSCREEN) <> 0 Then
        gfxFlags Or= FB.GFX_FULLSCREEN
    End If
    ' The null driver retains the complete software framebuffer without a
    ' display connection or window-manager lifetime, which deterministic
    ' rendering tests do not need. GFX_NULL is a mode value, not a bit mask.
    If backend_HeadlessActive <> 0 Then gfxFlags = FB.GFX_NULL

    screenResult = ScreenRes( _
        w, h, colorDepth, BACKEND_GFX_PAGE_COUNT, gfxFlags _
    )

    If screenResult <> 0 Then
        screenResult = ScreenRes( _
            w, h, colorDepth, BACKEND_GFX_PAGE_COUNT, _
            gfxFlags Or FB.GFX_NO_SWITCH _
        )
    End If

    If screenResult <> 0 Then Return 0

#Ifndef __FB_RISCOS__
    ScreenSet BACKEND_GFX_WORK_PAGE, BACKEND_GFX_VISIBLE_PAGE
#EndIf
    ScreenInfo actualWidth, actualHeight, actualDepth

    backend_GfxWorkPage = BACKEND_GFX_WORK_PAGE
    backend_GfxVisiblePage = BACKEND_GFX_VISIBLE_PAGE
    backend_DoubleBufferActive = IIf( _
        BACKEND_GFX_PAGE_COUNT > 1, -1, 0 _
    )
    backend_Resizable = 0
#If __FB_VERSION__ >= "1.20.0"
    If (gfxFlags And FB.GFX_RESIZABLE) <> 0 Then backend_Resizable = -1
#EndIf
    backend_RequestedWidth = w
    backend_RequestedHeight = h
    backend_WindowFlags = windowFlags
    If backend_Resizable = 0 Then _
        backend_WindowFlags And= Not BACKEND_WINDOW_RESIZABLE
    backend_ColorDepth = actualDepth
    backend_ClipDepth = 0
    backend_ClipOverflowDepth = 0
    backend_LastPresentationClock = 0.0
    backend_ConfigureIndexedPalette actualDepth

    Return -1
End Function


Private Function backend_PresentationElapsedSeconds( _
    ByVal startClock As Double, ByVal endClock As Double _
) As Double

    Dim As Double elapsedSeconds = endClock - startClock
    If elapsedSeconds < 0.0 Then elapsedSeconds += 86400.0
    Return elapsedSeconds

End Function


Private Sub backend_WaitForPresentationCadence()

    Const secondsPerFrame As Double = 1.0 / BACKEND_PRESENTATION_HZ
    Dim As Double currentClock = Timer

    If backend_LastPresentationClock <= 0.0 Then
        backend_LastPresentationClock = currentClock
        Exit Sub
    End If

    Dim As Double secondsRemaining = secondsPerFrame - _
        backend_PresentationElapsedSeconds( _
            backend_LastPresentationClock, currentClock _
        )

    If secondsRemaining > BACKEND_COARSE_WAIT_MARGIN_SECONDS Then
        Dim As Integer coarseMilliseconds = CInt(Int( _
            (secondsRemaining - BACKEND_COARSE_WAIT_MARGIN_SECONDS) * 1000.0 _
        ))
        If coarseMilliseconds > 0 Then Sleep coarseMilliseconds, 1
    End If

    Do
        currentClock = Timer
        secondsRemaining = secondsPerFrame - _
            backend_PresentationElapsedSeconds( _
                backend_LastPresentationClock, currentClock _
            )
    Loop While secondsRemaining > 0.0

    backend_LastPresentationClock = currentClock

End Sub

' -------------------------------------------------------------------------
' Helpers: Degraded Color Mapping
' -------------------------------------------------------------------------
Private Function MapColor(ByVal clr As ULong) As ULong
    Dim As Integer w, h, d, bpp, pitch
    ScreenInfo w, h, d, bpp, pitch
    If d >= 16 Then Return clr

    Dim As UByte r = (clr Shr 16) And &HFF
    Dim As UByte g = (clr Shr 8) And &HFF
    Dim As UByte b = clr And &HFF

    If d = BACKEND_COLOR_DEPTH_256_COLOR Then
        Dim As Integer highestChannel = r
        Dim As Integer lowestChannel = r
        Dim As UInteger luminance

        If g > highestChannel Then highestChannel = g
        If b > highestChannel Then highestChannel = b
        If g < lowestChannel Then lowestChannel = g
        If b < lowestChannel Then lowestChannel = b

        If highestChannel - lowestChannel <= BACKEND_8BIT_GRAY_THRESHOLD Then
            luminance = (CUInt(r) * 299) + (CUInt(g) * 587) + _
                (CUInt(b) * 114)
            Return BACKEND_8BIT_COLOR_CUBE_SIZE + _
                (((luminance \ 1000) * _
                (BACKEND_8BIT_GRAY_COUNT - 1)) + 127) \ 255
        End If

        Return (((CUInt(r) * 5) + 127) \ 255) * 36 + _
            (((CUInt(g) * 5) + 127) \ 255) * 6 + _
            (((CUInt(b) * 5) + 127) \ 255)
    Elseif d = BACKEND_COLOR_DEPTH_16_COLOR Then
        Dim As Integer colorIndex
        Dim As Integer paletteRed
        Dim As Integer paletteGreen
        Dim As Integer paletteBlue
        Dim As LongInt redDistance
        Dim As LongInt greenDistance
        Dim As LongInt blueDistance
        Dim As LongInt colorDistance
        Dim As LongInt nearestDistance = &H7FFFFFFF
        Dim As Integer nearestIndex

        For colorIndex = 0 To 15
            backend_Get16ColorPaletteEntry _
                colorIndex, paletteRed, paletteGreen, paletteBlue
            redDistance = CInt(r) - paletteRed
            greenDistance = CInt(g) - paletteGreen
            blueDistance = CInt(b) - paletteBlue
            colorDistance = (redDistance * redDistance) + _
                (greenDistance * greenDistance) + _
                (blueDistance * blueDistance)

            If colorDistance < nearestDistance Then
                nearestDistance = colorDistance
                nearestIndex = colorIndex
            End If
        Next colorIndex

        Return nearestIndex
    Elseif d = BACKEND_COLOR_DEPTH_MONOCHROME Then
        /'
            ITU-R BT.601 luma weights provide a more faithful black/white
            threshold than adding the channels with equal importance.
        '/
        Return IIf( _
            (CUInt(r) * 299) + (CUInt(g) * 587) + (CUInt(b) * 114) >= 128000, _
            1, 0 _
        )
    End If
    Return clr
End Function

' -------------------------------------------------------------------------
' Lifecycle
' -------------------------------------------------------------------------

#include once "src/backend/backend_font_span.bi"

Sub backend_Init( _
    ByVal w As Integer, _
    ByVal h As Integer, _
    ByVal headless As Integer, _
    ByVal windowFlags As UInteger, _
    ByVal colorDepth As Integer _
)

    /'
        Drawable headless tests use gfxlib's null driver with a framebuffer.
        Screenless tests leave gfxlib closed until an image operation needs a
        temporary null context.
    '/
#If Defined(__FB_WIN32__) And Not Defined(__FB_GFXLIB3__) And _
    Not Defined(OMAGUI_PORTABLE_ONLY)
    backend_SetPresentationTiming 0
#EndIf
    backend_DoubleBufferActive = 0
    Select Case headless
    Case BACKEND_HEADLESS
        backend_HeadlessActive = BACKEND_HEADLESS
    Case BACKEND_HEADLESS_DRAWABLE
        backend_HeadlessActive = BACKEND_HEADLESS_DRAWABLE
    Case Else
        backend_HeadlessActive = BACKEND_DISPLAY_ENABLED
    End Select
    backend_GfxWorkPage = BACKEND_GFX_VISIBLE_PAGE
    backend_GfxVisiblePage = BACKEND_GFX_VISIBLE_PAGE
    backend_Resizable = 0
    backend_RequestedWidth = w
    backend_RequestedHeight = h
    backend_WindowFlags = windowFlags
    backend_ColorDepth = 0

    If backend_CreateScreen(w, h, windowFlags, colorDepth) = 0 Then
        /'
            A caller may request a low-depth mode that the active driver does
            not implement. Preserve the historical guarantee that backend_Init
            still provides a usable screen by falling back to 32-bit color.
        '/
        backend_CreateScreen _
            w, h, windowFlags, BACKEND_COLOR_DEPTH_TRUE_COLOR
    End If

#If Defined(__FB_WIN32__) And Not Defined(__FB_GFXLIB3__) And _
    Not Defined(OMAGUI_PORTABLE_ONLY)
    backend_SetPresentationTiming IIf( _
        backend_HeadlessActive = BACKEND_DISPLAY_ENABLED AndAlso _
        backend_DoubleBufferActive <> 0, -1, 0 _
    )
#EndIf

    font_init_pointers()
    theme_InitClassic()
End Sub

Sub backend_Exit()
    backend_FontSpanRelease
    If backend_HeadlessActive <> BACKEND_HEADLESS Then Screen 0
#If Defined(__FB_WIN32__) And Not Defined(__FB_GFXLIB3__) And _
    Not Defined(OMAGUI_PORTABLE_ONLY)
    backend_SetPresentationTiming 0
#EndIf
    backend_ClearFontPacks()
    backend_DoubleBufferActive = 0
    backend_GfxWorkPage = BACKEND_GFX_VISIBLE_PAGE
    backend_GfxVisiblePage = BACKEND_GFX_VISIBLE_PAGE
    backend_Resizable = 0
    backend_HeadlessActive = 0
    backend_ColorDepth = 0
    backend_ClipDepth = 0
    backend_ClipOverflowDepth = 0
    backend_LastPresentationClock = 0.0
#Ifdef __FB_GFXLIB3__
    Erase backend_Gfx3SpanPoints
    backend_Gfx3SpanPointCapacity = 0
#EndIf
End Sub


Private Function backend_FontPackReadU16( _
    ByVal bytes As UByte Ptr, ByRef bytePosition As ULongInt _
) As UInteger

    Dim As UInteger value = bytes[bytePosition]
    value Or= CUInt(bytes[bytePosition + 1]) Shl 8
    bytePosition += 2
    Return value

End Function


Private Function backend_FontPackReadU32( _
    ByVal bytes As UByte Ptr, ByRef bytePosition As ULongInt _
) As UInteger

    Dim As UInteger value = bytes[bytePosition]
    value Or= CUInt(bytes[bytePosition + 1]) Shl 8
    value Or= CUInt(bytes[bytePosition + 2]) Shl 16
    value Or= CUInt(bytes[bytePosition + 3]) Shl 24
    bytePosition += 4
    Return value

End Function


Private Function backend_FontPackReadS16( _
    ByVal bytes As UByte Ptr, ByRef bytePosition As ULongInt _
) As Integer

    Dim As Integer value = backend_FontPackReadU16(bytes, bytePosition)
    If value >= 32768 Then value -= 65536
    Return value

End Function


Private Function backend_HasFontPack(ByVal font_id As Integer) As Integer

    If font_id < LBound(backend_FontPacks) OrElse font_id > UBound(backend_FontPacks) OrElse _
       font_id = BACKEND_FONT_CUSTOM Then Return 0
    Return IIf(backend_FontPacks(font_id).glyph_count > 0, -1, 0)

End Function

Private Function backend_FontPackFind( _
    ByVal font_id As Integer, ByVal codepoint As Integer _
) As BackendFontGlyphIndex Ptr

    If backend_HasFontPack(font_id) = 0 OrElse codepoint < 0 Then Return 0

#Ifndef OMAGUI_DISABLE_FONT_ASCII_INDEX
    ' Most editor text is ASCII. Avoid searching the same sorted pack again
    ' for every width, advance and bitmap query. Missing glyphs remain NULL.
    If codepoint >= 32 AndAlso codepoint <= 126 Then _
        Return backend_FontPacks(font_id).ascii_glyphs(codepoint)
#EndIf

    Dim As Integer lowerIndex = 0
    Dim As Integer upperIndex = backend_FontPacks(font_id).glyph_count - 1
    Dim As UInteger wantedCodepoint = CUInt(codepoint)

    While lowerIndex <= upperIndex
        Dim As Integer middleIndex = lowerIndex + _
            ((upperIndex - lowerIndex) \ 2)
        Dim As BackendFontGlyphIndex Ptr candidate = _
            @backend_FontPacks(font_id).glyphs[middleIndex]

        If candidate->codepoint = wantedCodepoint Then Return candidate
        If candidate->codepoint < wantedCodepoint Then
            lowerIndex = middleIndex + 1
        Else
            upperIndex = middleIndex - 1
        End If
    Wend

    Return 0

End Function


Private Function backend_FontPackPreferZeroAdvance( _
    ByVal codepoint As Integer, _
    ByVal glyph As BackendFontGlyphIndex Ptr _
) As BackendFontGlyphIndex Ptr

    Dim As BackendFontGlyphIndex Ptr markGlyph

    If glyph = 0 OrElse codepoint < 128 OrElse codepoint = 127 OrElse _
       glyph->advance <= 0 Then Return glyph

    /'
        Some fixed-cell fonts encode Unicode combining marks as spacing
        accents. Prefer the UI pack's nonspacing bitmap when it provides one;
        textbox geometry then keeps the mark in the previous character cell.
    '/
    markGlyph = backend_FontPackFind(BACKEND_FONT_DEFAULT, codepoint)
    If markGlyph <> 0 AndAlso markGlyph->advance = 0 Then Return markGlyph
    Return glyph

End Function


Private Function backend_FontPackTextGlyph( _
    ByVal font_id As Integer, ByVal codepoint As Integer _
) As BackendFontGlyphIndex Ptr

    Dim As BackendFontGlyphIndex Ptr glyph

    glyph = backend_FontPackFind(font_id, codepoint)
    If glyph <> 0 Then _
        Return backend_FontPackPreferZeroAdvance(codepoint, glyph)

    glyph = backend_FontPackFind( _
        BACKEND_FONT_UNICODE_FALLBACK, codepoint _
    )
    Return backend_FontPackPreferZeroAdvance(codepoint, glyph)

End Function


Private Function backend_FontGlyphAdvance( _
    ByVal font_id As Integer, ByVal codepoint As Integer, _
    ByVal glyph As UByte Ptr _
) As Integer

    Dim As BackendFontGlyphIndex Ptr packedGlyph

    If glyph = 0 Then Return 0

    If backend_HasFontPack(font_id) <> 0 Then
        packedGlyph = backend_FontPackFind(font_id, codepoint)
        If packedGlyph <> 0 AndAlso packedGlyph->bitmap = glyph Then _
            Return packedGlyph->advance
    End If

    If codepoint >= 128 AndAlso codepoint <> 127 Then
        packedGlyph = backend_FontPackFind( _
            BACKEND_FONT_UNICODE_FALLBACK, codepoint _
        )
        If packedGlyph <> 0 AndAlso packedGlyph->bitmap = glyph Then _
            Return packedGlyph->advance

        packedGlyph = backend_FontPackFind(BACKEND_FONT_DEFAULT, codepoint)
        If packedGlyph <> 0 AndAlso packedGlyph->bitmap = glyph Then _
            Return packedGlyph->advance
    End If

    Return glyph[0]

End Function


Private Function backend_FontAscent(ByVal font_id As Integer) As Integer

    If backend_HasFontPack(font_id) <> 0 Then _
        Return backend_FontPacks(font_id).ascent

    Select Case font_id
    Case BACKEND_FONT_DEFAULT, BACKEND_FONT_ARIAL_10_REGULAR
        /'
            These fixed bitmap tables were generated from complete line
            surfaces without storing their font metrics. Their capital
            glyphs share a baseline ten pixels below the line origin.
        '/
        Return 10
    Case BACKEND_FONT_ARIAL_12_BOLD
        /'
            The 12-point bold bitmap table uses a twelve-pixel ascent.
        '/
        Return 12
    End Select

    Return -1

End Function


Private Function backend_ZeroAdvanceGlyphPenX( _
    ByVal current_x As Integer, _
    ByVal previous_cell_x As Integer, _
    ByVal previous_cell_advance As Integer, _
    ByVal glyph_advance As Integer, _
    ByVal glyph_width As Integer, _
    ByVal bearing_x As Integer, _
    ByVal scale_numerator As Integer, _
    ByVal scale_denominator As Integer _
) As Integer

    Dim As Integer scaled_cell_advance
    Dim As Integer scaled_glyph_width
    Dim As Integer scaled_bearing_x

    If glyph_advance <> 0 OrElse previous_cell_advance <= 0 OrElse _
       glyph_width <= 0 OrElse scale_numerator <= 0 OrElse _
       scale_denominator <= 0 Then Return current_x

    /'
        SDL_ttf reports combining marks with no advance. The glyph's own
        bearing is measured from its pen origin, so center it in the previous
        advancing character cell instead of leaving it in the next cell.
    '/
    scaled_cell_advance = _
        (previous_cell_advance * scale_numerator + _
         (scale_denominator \ 2)) \ scale_denominator
    scaled_glyph_width = _
        (glyph_width * scale_numerator + (scale_denominator \ 2)) \ _
        scale_denominator
    scaled_bearing_x = _
        (bearing_x * scale_numerator) \ scale_denominator

    Return previous_cell_x + _
        ((scaled_cell_advance - scaled_glyph_width) \ 2) - _
        scaled_bearing_x

End Function


Private Sub backend_FontGlyphBearing( _
    ByVal font_id As Integer, ByVal codepoint As Integer, _
    ByVal glyph As UByte Ptr, _
    ByRef bearing_x As Integer, ByRef bearing_y As Integer _
)

    Dim As BackendFontGlyphIndex Ptr packedGlyph
    Dim As Integer selectedAscent
    Dim As Integer fallbackFontId

    bearing_x = 0
    bearing_y = 0

    If backend_HasFontPack(font_id) <> 0 Then
        packedGlyph = backend_FontPackFind(font_id, codepoint)
        If packedGlyph <> 0 AndAlso packedGlyph->bitmap = glyph Then
            bearing_x = packedGlyph->bearing_x
            bearing_y = packedGlyph->bearing_y
            Return
        End If
    End If

    If codepoint >= 128 AndAlso codepoint <> 127 Then
        packedGlyph = backend_FontPackFind( _
            BACKEND_FONT_UNICODE_FALLBACK, codepoint _
        )
        fallbackFontId = BACKEND_FONT_UNICODE_FALLBACK
        If packedGlyph = 0 OrElse packedGlyph->bitmap <> glyph Then
            /'
                The UI face covers common combining marks which are outside
                the selected bitmap face and the CJK fallback cmap.
            '/
            packedGlyph = backend_FontPackFind( _
                BACKEND_FONT_DEFAULT, codepoint _
            )
            fallbackFontId = BACKEND_FONT_DEFAULT
            If packedGlyph <> 0 AndAlso packedGlyph->bitmap <> glyph Then _
                packedGlyph = 0
        End If

        If packedGlyph <> 0 Then
            bearing_x = packedGlyph->bearing_x
            bearing_y = packedGlyph->bearing_y
            /'
                Fallback glyphs share a row with the selected text font.
                Move the fallback's top bearing to that font's baseline so
                its different ascent does not shift text vertically.
            '/
            selectedAscent = backend_FontAscent(font_id)
            If selectedAscent >= 0 Then
                bearing_y += _
                    selectedAscent - backend_FontPacks(fallbackFontId).ascent
            End If
        Else
            /'
                The locale supplement and built-in replacement table use the
                legacy ten-pixel baseline rather than OGF ascent metrics.
            '/
            selectedAscent = backend_FontAscent(font_id)
            If selectedAscent >= 0 Then _
                bearing_y = selectedAscent - 10
        End If
    End If

End Sub


Sub backend_ClearFontPacks()
    backend_FontGeneration += 1

    For fontIndex As Integer = 0 To BACKEND_FONT_TERMINAL
        For codepoint As Integer = 32 To 126
            backend_FontPacks(fontIndex).ascii_glyphs(codepoint) = 0
        Next codepoint
        If backend_FontPacks(fontIndex).glyphs <> 0 Then _
            Deallocate backend_FontPacks(fontIndex).glyphs
        If backend_FontPacks(fontIndex).bitmap_storage <> 0 Then _
            Deallocate backend_FontPacks(fontIndex).bitmap_storage
        backend_FontPacks(fontIndex).glyphs = 0
        backend_FontPacks(fontIndex).bitmap_storage = 0
        backend_FontPacks(fontIndex).glyph_count = 0
        backend_FontPacks(fontIndex).line_height = 0
        backend_FontPacks(fontIndex).ascent = 0
        backend_FontPacks(fontIndex).point_size = 0
    Next fontIndex

End Sub


Function backend_IsFontAvailable(ByVal font_id As Integer) As Integer

    Select Case font_id
    Case BACKEND_FONT_DEFAULT, BACKEND_FONT_ARIAL_10_REGULAR, _
         BACKEND_FONT_ARIAL_12_BOLD
        Return -1
    Case BACKEND_FONT_CUSTOM
        Return IIf(backend_CustomFontGlyphs <> 0, -1, 0)
    Case BACKEND_FONT_CASCADIA_MONO, BACKEND_FONT_UNICODE_FALLBACK, _
         BACKEND_FONT_TERMINAL
        Return IIf( _
            backend_FontPacks(font_id).glyph_count > 0, -1, 0 _
        )
    End Select

    Return 0

End Function

Function backend_GetFontPointSize(ByVal font_id As Integer) As Integer
    If backend_HasFontPack(font_id) <> 0 Then Return backend_FontPacks(font_id).point_size
    Select Case font_id
    Case BACKEND_FONT_ARIAL_12_BOLD, BACKEND_FONT_TERMINAL
        Return 12
    Case BACKEND_FONT_CASCADIA_MONO
        Return 11
    Case Else
        Return 10
    End Select
End Function

Function backend_GetFontAscent(ByVal font_id As Integer) As Integer
    Dim As Integer ascent = backend_FontAscent(font_id)
    If ascent < 0 Then ascent = backend_GetTextHeightFont(font_id)
    Return ascent
End Function


Function backend_LoadFontPack( _
    ByVal font_id As Integer, ByVal filename As String _
) As Integer
    backend_FontGeneration += 1

    /'
        Read the bounded OGF1 file into a FreeBASIC string, validate its full
        sorted glyph table, then copy the bitmaps into backend-owned storage.
        The current pack remains installed until every validation and
        allocation succeeds, so a bad replacement cannot break existing text.
    '/

    Dim As Integer fileNumber
    Dim As Integer invalidPack
    Dim As Integer fontLineHeight
    Dim As Integer fontAscent
    Dim As LongInt fileLength
    Dim As UInteger fileSize
    Dim As UInteger version
    Dim As UInteger headerSize
    Dim As UInteger glyphCount
    Dim As UInteger fontPointSize
    Dim As UInteger fontFaceIndex
    Dim As UInteger codepoint
    Dim As UInteger previousCodepoint
    Dim As UInteger bitmapWidth
    Dim As UInteger bitmapHeight
    Dim As UInteger advance
    Dim As Integer bearingX
    Dim As Integer bearingY
    Dim As ULongInt bytePosition
    Dim As ULongInt pixelCount
    Dim As ULongInt bitmapStorageSize
    Dim As ULongInt bitmapStoragePosition
    Dim As String fontFileData
    Dim As UByte Ptr fontBytes
    Dim As UByte Ptr newBitmapStorage
    Dim As BackendFontGlyphIndex Ptr newGlyphs
    Dim As BackendFontGlyphIndex Ptr newAsciiGlyphs(32 To 126)

    If font_id < LBound(backend_FontPacks) OrElse font_id > UBound(backend_FontPacks) OrElse _
       font_id = BACKEND_FONT_CUSTOM OrElse filename = "" Then _
        Return 0 ' fblint: disable-line FBL-IO-004 REASON: A failed Open acquires no handle; every successful open is closed below.

    fileNumber = FreeFile
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        Return 0 ' fblint: disable-line FBL-IO-004 REASON: A failed Open acquires no handle; every successful open is closed below.
    End If
    fileLength = Lof(fileNumber)
    If fileLength < BACKEND_FONT_PACK_HEADER_BYTES OrElse _
       fileLength > BACKEND_FONT_PACK_MAX_BYTES Then
        Close #fileNumber
        Return 0 ' fblint: disable-line FBL-IO-004 REASON: A failed Open acquires no handle; every successful open is closed below.
    End If
    fileSize = CUInt(fileLength)

    fontFileData = Space(CInt(fileSize))
    If Get(fileNumber, , fontFileData) <> 0 Then
        Close #fileNumber
        Return 0 ' fblint: disable-line FBL-IO-004 REASON: A failed Open acquires no handle; every successful open is closed below.
    End If
    Close #fileNumber
    fontBytes = Cast(UByte Ptr, StrPtr(fontFileData))
    If fontBytes = 0 OrElse Left(fontFileData, 4) <> "OGF1" Then Return 0

    bytePosition = 4
    version = backend_FontPackReadU16(fontBytes, bytePosition)
    headerSize = backend_FontPackReadU16(fontBytes, bytePosition)
    glyphCount = backend_FontPackReadU32(fontBytes, bytePosition)
    fontLineHeight = backend_FontPackReadU16(fontBytes, bytePosition)
    fontAscent = backend_FontPackReadU16(fontBytes, bytePosition)
    fontPointSize = backend_FontPackReadU16(fontBytes, bytePosition)
    fontFaceIndex = backend_FontPackReadU16(fontBytes, bytePosition)

    If version <> 1 OrElse headerSize <> BACKEND_FONT_PACK_HEADER_BYTES OrElse _
       glyphCount = 0 OrElse _
       glyphCount > BACKEND_FONT_PACK_MAX_GLYPHS OrElse _
       fontLineHeight < 1 OrElse fontLineHeight > 1024 OrElse _
       fontAscent > 1024 OrElse fontPointSize = 0 OrElse _
       fontPointSize > 255 Then Return 0

    bytePosition = headerSize
    bitmapStorageSize = 0
    previousCodepoint = 0
    For glyphIndex As UInteger = 0 To glyphCount - 1
        If bytePosition > CULngInt(fileSize) - _
            BACKEND_FONT_PACK_GLYPH_HEADER_BYTES Then
            invalidPack = -1
            Exit For
        End If

        codepoint = backend_FontPackReadU32(fontBytes, bytePosition)
        bitmapWidth = backend_FontPackReadU16(fontBytes, bytePosition)
        bitmapHeight = backend_FontPackReadU16(fontBytes, bytePosition)
        advance = backend_FontPackReadU16(fontBytes, bytePosition)
        bearingX = backend_FontPackReadS16(fontBytes, bytePosition)
        bearingY = backend_FontPackReadS16(fontBytes, bytePosition)
        pixelCount = CULngInt(bitmapWidth) * CULngInt(bitmapHeight)

        If codepoint < 32 OrElse codepoint > &H10FFFF OrElse _
           (codepoint >= &HD800 AndAlso codepoint <= &HDFFF) OrElse _
           (codepoint >= &H7F AndAlso codepoint <= &H9F) OrElse _
           bitmapWidth > 255 OrElse bitmapHeight > 255 OrElse _
           (glyphIndex > 0 AndAlso codepoint <= previousCodepoint) OrElse _
           pixelCount > CULngInt(fileSize) - bytePosition Then
            invalidPack = -1
            Exit For
        End If

        If pixelCount > BACKEND_FONT_PACK_MAX_BYTES - 2 OrElse _
           bitmapStorageSize > BACKEND_FONT_PACK_MAX_BYTES - _
               (pixelCount + 2) Then
            invalidPack = -1
            Exit For
        End If
        bitmapStorageSize += pixelCount + 2
        bytePosition += pixelCount
        previousCodepoint = codepoint
    Next glyphIndex

    If invalidPack <> 0 OrElse bytePosition <> CULngInt(fileSize) Then _
        Return 0 ' fblint: disable-line FBL-IO-004 REASON: A failed Open acquires no handle; every successful open is closed below.

    ' fblint: disable-next-line FBL310 -- this record type is private to the backend module.
    newGlyphs = Callocate(CULngInt(glyphCount) * SizeOf(BackendFontGlyphIndex))
    If newGlyphs = 0 Then Return 0
    newBitmapStorage = Allocate(bitmapStorageSize)
    If newBitmapStorage = 0 Then
        Deallocate newGlyphs
        Return 0 ' fblint: disable-line FBL-IO-004 REASON: A failed Open acquires no handle; every successful open is closed below.
    End If

    bytePosition = headerSize
    bitmapStoragePosition = 0
    For glyphIndex As UInteger = 0 To glyphCount - 1
        codepoint = backend_FontPackReadU32(fontBytes, bytePosition)
        bitmapWidth = backend_FontPackReadU16(fontBytes, bytePosition)
        bitmapHeight = backend_FontPackReadU16(fontBytes, bytePosition)
        advance = backend_FontPackReadU16(fontBytes, bytePosition)
        bearingX = backend_FontPackReadS16(fontBytes, bytePosition)
        bearingY = backend_FontPackReadS16(fontBytes, bytePosition)
        pixelCount = CULngInt(bitmapWidth) * CULngInt(bitmapHeight)

        newBitmapStorage[bitmapStoragePosition] = bitmapWidth
        newBitmapStorage[bitmapStoragePosition + 1] = bitmapHeight
        newGlyphs[glyphIndex].codepoint = codepoint
        newGlyphs[glyphIndex].bitmap = _
            @newBitmapStorage[bitmapStoragePosition]
        newGlyphs[glyphIndex].advance = advance
        newGlyphs[glyphIndex].bearing_x = bearingX
        newGlyphs[glyphIndex].bearing_y = bearingY
        If codepoint >= 32 AndAlso codepoint <= 126 Then _
            newAsciiGlyphs(codepoint) = @newGlyphs[glyphIndex]
        bitmapStoragePosition += 2

        /'
            Spaces and other advance-only glyphs have no bitmap pixels.
            Both spans were bounded by the validation pass. memcpy avoids
            per-pixel 64-bit indexing on 32-bit targets; source and destination
            belong to distinct allocations. Keep empty glyphs out of the copy.
        '/
        If pixelCount > 0 Then
            memcpy(@newBitmapStorage[bitmapStoragePosition], _
                @fontBytes[bytePosition], CUInt(pixelCount))
        End If
        bitmapStoragePosition += pixelCount
        bytePosition += pixelCount
    Next glyphIndex

    If backend_FontPacks(font_id).glyphs <> 0 Then _
        Deallocate backend_FontPacks(font_id).glyphs
    If backend_FontPacks(font_id).bitmap_storage <> 0 Then _
        Deallocate backend_FontPacks(font_id).bitmap_storage
    backend_FontPacks(font_id).glyphs = newGlyphs
    backend_FontPacks(font_id).bitmap_storage = newBitmapStorage
    backend_FontPacks(font_id).glyph_count = glyphCount
    backend_FontPacks(font_id).line_height = fontLineHeight
    backend_FontPacks(font_id).ascent = fontAscent
    backend_FontPacks(font_id).point_size = fontPointSize
    ' Publish the new direct lookup only after the complete replacement pack
    ' succeeds. A rejected file leaves the previous glyphs and lookup intact.
    For asciiCodepoint As Integer = 32 To 126
        backend_FontPacks(font_id).ascii_glyphs(asciiCodepoint) = newAsciiGlyphs(asciiCodepoint)
    Next asciiCodepoint

    Return -1

End Function


Function backend_WindowCloseRequested() As Integer

    /'
        input_Update drains gfxlib ScreenEvent so fast pointer transitions are
        retained for widgets. It records the native window-close request in a
        latch; consuming that latch here keeps the event queue owned by input.
    '/
    Return input_TakeWindowCloseRequested()

End Function


Function backend_RaiseWindow() As Integer

#If Defined(__FB_WIN32__) AndAlso Not Defined(OMAGUI_PORTABLE_ONLY)
#If Defined(__FB_64BIT__)
    Dim As LongInt nativeHandleValue
#Else
    Dim As Integer nativeHandleValue
#EndIf
    Dim As Any Ptr nativeHandle

    ScreenControl FB.GET_WINDOW_HANDLE, nativeHandleValue
    nativeHandle = CPtr(Any Ptr, nativeHandleValue)
    If nativeHandle = 0 Then Return 0

    /'
        Restore only minimized windows. SW_RESTORE also unmaximizes a normal
        maximized window, which would surprise users when they open a file.
    '/
    ' fblint: disable-next-line FBL310 REASON: The Windows-only branch uses declarations supplied by windows.bi and the system headers.
    If IsIconic(nativeHandle) <> 0 Then ShowWindow nativeHandle, SW_RESTORE
    If SetForegroundWindow(nativeHandle) = 0 Then Return 0
    Return -1
#Else
    Return 0
#EndIf

End Function


Function backend_SetWindowMode( _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal windowFlags As UInteger _
) As Integer
    Dim As Integer previousHeight
    Dim As Integer previousWidth
    Dim As Integer previousDepth
    Dim As UInteger previousFlags

    /'
        Reuse the same guarded creation path as initialization so both pages,
        the work/visible selection, clipping state, and live-size fallback are
        reset together after a windowed/full-screen transition. ScreenRes may
        discard the old screen before rejecting a mode, so restore the last
        working mode when the requested mode is unavailable.
    '/
    previousWidth = backend_RequestedWidth
    previousHeight = backend_RequestedHeight
    previousFlags = backend_WindowFlags
    previousDepth = backend_ColorDepth

    If backend_CreateScreen(w, h, windowFlags, previousDepth) <> 0 Then _
        Return -1

    If previousWidth > 0 AndAlso previousHeight > 0 AndAlso previousDepth > 0 Then
        backend_CreateScreen _
            previousWidth, previousHeight, previousFlags, previousDepth
    End If

    Return 0
End Function

Sub backend_GetSize(ByRef w As Integer, ByRef h As Integer)
    If backend_HeadlessActive = BACKEND_HEADLESS Then
        w = backend_RequestedWidth
        h = backend_RequestedHeight
        Exit Sub
    End If
    w = 0
    h = 0
    ScreenInfo w, h

    If w <= 0 Then w = backend_RequestedWidth
    If h <= 0 Then h = backend_RequestedHeight
End Sub

Function backend_IsResizable() As Integer
    Return backend_Resizable
End Function


Function backend_GetColorDepth() As Integer
    Dim As Integer actualDepth
    Dim As Integer actualHeight
    Dim As Integer actualWidth

    ScreenInfo actualWidth, actualHeight, actualDepth
    If actualDepth > 0 Then backend_ColorDepth = actualDepth

    Return backend_ColorDepth
End Function


Function backend_SetColorDepth(ByVal colorDepth As Integer) As Integer
    Dim As Integer currentHeight
    Dim As Integer currentWidth
    Dim As Integer oldDepth

    If backend_IsSupportedColorDepth(colorDepth) = 0 Then Return 0

    oldDepth = backend_GetColorDepth()
    If oldDepth = colorDepth Then Return -1

    backend_GetSize currentWidth, currentHeight
    If backend_CreateScreen( _
        currentWidth, currentHeight, backend_WindowFlags, colorDepth _
    ) Then
        Return -1
    End If

    /'
        ScreenRes may discard the old display before reporting a driver error.
        Make a best effort to restore the last working mode before returning.
    '/
    If oldDepth > 0 Then
        backend_CreateScreen _
            currentWidth, currentHeight, backend_WindowFlags, oldDepth
    End If

    Return 0
End Function


Private Function backend_BeginTemporaryImageMode() As Integer
    If backend_HeadlessActive <> BACKEND_HEADLESS Then Return -1

    Dim As Integer imageWidth = backend_RequestedWidth
    Dim As Integer imageHeight = backend_RequestedHeight
    If imageWidth < 1 Then imageWidth = 1
    If imageHeight < 1 Then imageHeight = 1

    /'
        ImageCreate and BLoad require a live gfxlib context. The null driver
        supplies one briefly while ordinary screenless tests keep Print usable.
    '/
    If ScreenRes( _
        imageWidth, imageHeight, BACKEND_COLOR_DEPTH_TRUE_COLOR, 1, _
        FB.GFX_NULL _
    ) <> 0 Then Return 0
    Return -1
End Function


Private Sub backend_EndTemporaryImageMode()
    If backend_HeadlessActive <> BACKEND_HEADLESS Then Exit Sub
    Screen 0
    backend_DoubleBufferActive = 0
    backend_GfxWorkPage = BACKEND_GFX_VISIBLE_PAGE
    backend_GfxVisiblePage = BACKEND_GFX_VISIBLE_PAGE
End Sub


Function backend_CreateImage( _
    ByVal imageWidth As Integer, ByVal imageHeight As Integer, _
    ByVal backgroundColor As ULong, ByVal imageDepth As Integer _
) As Any Ptr

    If imageWidth < 1 OrElse imageHeight < 1 OrElse imageDepth < 1 Then _
        Return 0

    If backend_BeginTemporaryImageMode() = 0 Then Return 0
    ' The caller owns this gfxlib image and releases it with ImageDestroy.
    Dim As Any Ptr imageBuffer = ImageCreate( _
        imageWidth, imageHeight, backgroundColor, imageDepth _
    )
    backend_EndTemporaryImageMode()
    Return imageBuffer

End Function


Function backend_LoadImageFile( _
    ByVal filePath As String, ByVal imageBuffer As Any Ptr _
) As Integer

    If imageBuffer = 0 OrElse Len(Trim(filePath)) = 0 Then Return 1
    If backend_BeginTemporaryImageMode() = 0 Then Return 1
    Dim As Integer loadResult = BLoad(filePath, imageBuffer)
    backend_EndTemporaryImageMode()
    Return loadResult

End Function

' -------------------------------------------------------------------------
' Rendering
' -------------------------------------------------------------------------

Sub backend_Clear(ByVal clr As ULong)
    Dim As Integer screen_w
    Dim As Integer screen_h

    ScreenInfo screen_w, screen_h

    If screen_w <= 0 Then screen_w = 800
    If screen_h <= 0 Then screen_h = 600

    backend_Rect(0, 0, screen_w, screen_h, clr, 1)
End Sub

Function backend_GetWorkPage() As Integer
    If backend_HeadlessActive = BACKEND_HEADLESS OrElse _
       backend_DoubleBufferActive = 0 Then Return BACKEND_GFX_VISIBLE_PAGE
    Return backend_GfxWorkPage
End Function

Function backend_UseRetainedPage() As Integer
    If backend_DoubleBufferActive = 0 Then Return 0
    ' Alternating pages would bring back pixels from two frames ago. A locked
    ' visible page lets gfxlib publish only the scanlines actually touched.
    ScreenSet BACKEND_GFX_VISIBLE_PAGE, BACKEND_GFX_VISIBLE_PAGE
    backend_GfxWorkPage = BACKEND_GFX_VISIBLE_PAGE
    backend_GfxVisiblePage = BACKEND_GFX_VISIBLE_PAGE
    backend_DoubleBufferActive = 0
    Return -1
End Function

Function backend_GetFontGeneration() As ULongInt
    Return backend_FontGeneration
End Function

Sub backend_Flip()
    If backend_DoubleBufferActive = 0 Then Exit Sub

    /'
        ScreenSet switches the visible page after the complete frame is
        drawn. ScreenSync before this swap can wait an extra refresh boundary
        on windowed gfxlib drivers. Pace after the swap so rendering and
        presentation share one 60 Hz frame budget.
    '/
    backend_GfxVisiblePage = backend_GfxWorkPage

    If backend_GfxWorkPage = BACKEND_GFX_VISIBLE_PAGE Then
        backend_GfxWorkPage = BACKEND_GFX_WORK_PAGE
    Else
        backend_GfxWorkPage = BACKEND_GFX_VISIBLE_PAGE
    End If

    ScreenSet backend_GfxWorkPage, backend_GfxVisiblePage
#Ifndef __FB_GFXLIB3__
    backend_WaitForPresentationCadence()
#EndIf
End Sub

Sub backend_Rect(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, ByVal clr As ULong, ByVal filled As Integer)
    If filled Then : Line (x, y)-(x + w - 1, y + h - 1), MapColor(clr), BF : Else : Line (x, y)-(x + w - 1, y + h - 1), MapColor(clr), B : End If
End Sub

Sub backend_Line(ByVal x1 As Integer, ByVal y1 As Integer, ByVal x2 As Integer, ByVal y2 As Integer, ByVal clr As ULong)
    Line (x1, y1)-(x2, y2), MapColor(clr)
End Sub


Function backend_DrawHorizontalSpans( _
    ByVal spanCount As Integer, _
    ByVal spanX1 As Integer Ptr, _
    ByVal spanX2 As Integer Ptr, _
    ByVal spanY As Integer Ptr, _
    ByVal clr As ULong, _
    ByVal alpha As Integer _
) As Integer
    If backend_HeadlessActive = BACKEND_HEADLESS Then Return -1
    If alpha <= 0 Then Return -1
    If spanCount <= 0 OrElse spanCount > 4096 OrElse _
        spanX1 = 0 OrElse spanX2 = 0 OrElse spanY = 0 Then Return 0

#Ifdef __FB_GFXLIB3__
    Dim As Integer screenWidth
    Dim As Integer screenHeight
    Dim As Integer screenDepth
    ScreenInfo screenWidth, screenHeight, screenDepth
    If screenWidth <= 0 OrElse screenHeight <= 0 OrElse _
        screenDepth <> BACKEND_COLOR_DEPTH_TRUE_COLOR Then Return 0

    If alpha > 255 Then alpha = 255
    Dim As ULongInt pointCount
    For spanIndex As Integer = 0 To spanCount - 1
        Dim As Integer firstX = spanX1[spanIndex]
        Dim As Integer lastX = spanX2[spanIndex]
        Dim As Integer rowY = spanY[spanIndex]
        If rowY < 0 OrElse rowY >= screenHeight OrElse _
            lastX < 0 OrElse firstX >= screenWidth Then Continue For
        If firstX < 0 Then firstX = 0
        If lastX >= screenWidth Then lastX = screenWidth - 1
        If lastX < firstX Then Continue For

        Dim As ULongInt spanWidth = CULngInt(lastX - firstX) + 1
        If spanWidth > BACKEND_GFX3_SPAN_POINT_LIMIT - pointCount Then Return 0
        pointCount += spanWidth
    Next
    If pointCount = 0 Then Return -1

    If backend_Gfx3SpanPointCapacity < pointCount Then
        ReDim backend_Gfx3SpanPoints(0 To CInt(pointCount) - 1)
        backend_Gfx3SpanPointCapacity = pointCount
    End If

    Dim As Integer pointIndex
    For spanIndex As Integer = 0 To spanCount - 1
        Dim As Integer firstX = spanX1[spanIndex]
        Dim As Integer lastX = spanX2[spanIndex]
        Dim As Integer rowY = spanY[spanIndex]
        If rowY < 0 OrElse rowY >= screenHeight OrElse _
            lastX < 0 OrElse firstX >= screenWidth Then Continue For
        If firstX < 0 Then firstX = 0
        If lastX >= screenWidth Then lastX = screenWidth - 1
        For pixelX As Integer = firstX To lastX
            backend_Gfx3SpanPoints(pointIndex).x = pixelX
            backend_Gfx3SpanPoints(pointIndex).y = rowY
            backend_Gfx3SpanPoints(pointIndex).color = clr
            backend_Gfx3SpanPoints(pointIndex).alpha = backend_Gfx3Alpha(alpha)
            pointIndex += 1
        Next
    Next

    If fb.Gfx3DrawPoints( _
        0, @backend_Gfx3SpanPoints(0), pointIndex) = 0 Then Return -1
#EndIf
    Return 0
End Function

Function backend_DrawAlphaMask( _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal maskWidth As Integer, _
    ByVal maskHeight As Integer, _
    ByVal coverage As UByte Ptr, _
    ByVal clr As ULong _
) As Integer
    If backend_HeadlessActive = BACKEND_HEADLESS Then Return -1
    If maskWidth <= 0 OrElse maskHeight <= 0 OrElse coverage = 0 Then Return 0

#Ifdef __FB_GFXLIB3__
    If CULngInt(maskWidth) > _
        BACKEND_GFX3_SPAN_POINT_LIMIT \ CULngInt(maskHeight) Then Return 0
    Dim As Integer screenWidth
    Dim As Integer screenHeight
    Dim As Integer screenDepth
    ScreenInfo screenWidth, screenHeight, screenDepth
    If screenWidth <= 0 OrElse screenHeight <= 0 OrElse _
        screenDepth <> BACKEND_COLOR_DEPTH_TRUE_COLOR Then Return 0

    Dim As ULongInt pointCount
    For maskY As Integer = 0 To maskHeight - 1
        ' The mask origin may be near the signed limit. Keep clipping arithmetic
        ' wide enough that an offscreen mask cannot wrap into the drawable area.
        Dim As LongInt pixelY = CLngInt(y) + maskY
        If pixelY < 0 OrElse pixelY >= screenHeight Then Continue For
        For maskX As Integer = 0 To maskWidth - 1
            Dim As LongInt pixelX = CLngInt(x) + maskX
            If pixelX >= 0 AndAlso pixelX < screenWidth AndAlso _
                coverage[maskY * maskWidth + maskX] <> 0 Then pointCount += 1
        Next maskX
    Next maskY
    If pointCount = 0 Then Return -1

    If backend_Gfx3SpanPointCapacity < pointCount Then
        ReDim backend_Gfx3SpanPoints(0 To CInt(pointCount) - 1)
        backend_Gfx3SpanPointCapacity = pointCount
    End If

    Dim As Integer pointIndex
    For maskY As Integer = 0 To maskHeight - 1
        Dim As LongInt pixelY = CLngInt(y) + maskY
        If pixelY < 0 OrElse pixelY >= screenHeight Then Continue For
        For maskX As Integer = 0 To maskWidth - 1
            Dim As LongInt pixelX = CLngInt(x) + maskX
            Dim As Integer alpha = coverage[maskY * maskWidth + maskX]
            If pixelX < 0 OrElse pixelX >= screenWidth OrElse alpha <= 0 Then _
                Continue For
            backend_Gfx3SpanPoints(pointIndex).x = pixelX
            backend_Gfx3SpanPoints(pointIndex).y = pixelY
            backend_Gfx3SpanPoints(pointIndex).color = clr
            backend_Gfx3SpanPoints(pointIndex).alpha = backend_Gfx3Alpha(alpha)
            pointIndex += 1
        Next maskX
    Next maskY

    If fb.Gfx3DrawPoints( _
        0, @backend_Gfx3SpanPoints(0), pointIndex) = 0 Then Return -1
#EndIf
    Return 0
End Function


Private Function backend_BlendImagePixel(ByVal sourcePixel As ULong, _
    ByVal destinationPixel As ULong, ByVal userData As Any Ptr) As ULong
    Dim As ULong alphaValue = sourcePixel Shr 24
    If alphaValue = 0 Then Return destinationPixel
    If alphaValue = 255 Then Return sourcePixel

    Dim As ULong resultPixel
    ' gfxlib uses (alpha + 1) / 256 for partially transparent pixels.
    For channelShift As Integer = 0 To 24 Step 8
        Dim As ULong sourceValue = (sourcePixel Shr channelShift) And 255
        Dim As ULong destinationValue = (destinationPixel Shr channelShift) And 255
        resultPixel Or= (((sourceValue * (alphaValue + 1) + _
            destinationValue * (255 - alphaValue)) Shr 8) Shl channelShift)
    Next channelShift
    Return resultPixel
End Function

Sub backend_DrawImage( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal imageBuffer As Any Ptr, ByVal useAlpha As Integer, _
    ByVal preserveTransparent As Integer _
)

    If imageBuffer = 0 Then Exit Sub
    ' Layout-only headless tests keep image ownership but have no gfxlib screen.
    If backend_HeadlessActive = BACKEND_HEADLESS Then Exit Sub

    /'
        Raster decoders return gfxlib image buffers. Alpha mode preserves GIF
        transparency and PNG alpha; opaque images use ordinary palette mapping.
    '/
    If useAlpha <> 0 Then
        If preserveTransparent AndAlso backend_ColorDepth = BACKEND_COLOR_DEPTH_TRUE_COLOR Then
            Put (x, y), imageBuffer, Custom, @backend_BlendImagePixel
        Else
            Put (x, y), imageBuffer, Alpha
        End If
    Else
        Put (x, y), imageBuffer, PSet
    End If

End Sub

Sub backend_PSetAlpha(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal alpha As Integer)
    Dim As Integer screen_w
    Dim As Integer screen_h
    Dim As Integer screen_d
    Dim As ULong bg
    Dim As ULong r
    Dim As ULong g
    Dim As ULong b
    Dim As ULong br
    Dim As ULong bg_g
    Dim As ULong bb
    Dim As ULong rr
    Dim As ULong rg
    Dim As ULong rb

    If alpha <= 0 Then Exit Sub

    ScreenInfo screen_w, screen_h, screen_d

    If x < 0 Or y < 0 Or x >= screen_w Or y >= screen_h Then
        Exit Sub
    End If

    If alpha >= 255 Or screen_d < 16 Then
        PSet (x, y), MapColor(clr)
        Exit Sub
    End If

#Ifdef __FB_GFXLIB3__
    /'
        A gfxlib3 page is normally authoritative on the GPU. POINT would
        download that complete page before blending one pixel, which is
        especially expensive after an application has drawn a scaled surface.
        The extension preserves gfxlib's alpha arithmetic in the queued GPU
        command and therefore does not cross the CPU/GPU ownership boundary.
    '/
    If screen_d = 32 Then
        Dim As fb.Gfx3Point gpu_point

        gpu_point.x = x
        gpu_point.y = y
        gpu_point.color = clr
        gpu_point.alpha = backend_Gfx3Alpha(alpha)

        If fb.Gfx3DrawPoints(0, @gpu_point, 1) = 0 Then
            Exit Sub
        End If
    End If
#EndIf

    bg = Point(x, y)

    r = (clr Shr 16) And &HFF
    g = (clr Shr 8) And &HFF
    b = clr And &HFF

    br = (bg Shr 16) And &HFF
    bg_g = (bg Shr 8) And &HFF
    bb = bg And &HFF

    rr = ((r * alpha) + (br * (255 - alpha))) \ 255
    rg = ((g * alpha) + (bg_g * (255 - alpha))) \ 255
    rb = ((b * alpha) + (bb * (255 - alpha))) \ 255

    PSet (x, y), RGB(rr, rg, rb)
End Sub

Private Sub backend_DrawLineAlpha(ByVal x1 As Integer, ByVal y1 As Integer, _
                                  ByVal x2 As Integer, ByVal y2 As Integer, _
                                  ByVal clr As ULong, ByVal alpha As Integer)
    /'
        Gfxlib's LINE statement does not blend. The imported graphics renderer
        needs object transparency, so transparent strokes use a small
        Bresenham rasterizer and route every pixel through backend_PSetAlpha.
    '/

    Dim As Integer dx = Abs(x2 - x1)
    Dim As Integer sx = IIf(x1 < x2, 1, -1)
    Dim As Integer dy = -Abs(y2 - y1)
    Dim As Integer sy = IIf(y1 < y2, 1, -1)
    Dim As Integer err_value = dx + dy
    Dim As Integer e2
    Dim As Integer cx = x1
    Dim As Integer cy = y1

    Do
        backend_PSetAlpha(cx, cy, clr, alpha)

        If cx = x2 And cy = y2 Then
            Exit Do
        End If

        e2 = err_value * 2

        If e2 >= dy Then
            err_value += dy
            cx += sx
        End If

        If e2 <= dx Then
            err_value += dx
            cy += sy
        End If
    Loop
End Sub

Sub backend_LineEx(ByVal x1 As Integer, ByVal y1 As Integer, _
                   ByVal x2 As Integer, ByVal y2 As Integer, _
                   ByVal clr As ULong, ByVal line_width As Integer, _
                   ByVal alpha As Integer)
    Dim As Integer first_offset
    Dim As Integer last_offset
    Dim As Integer offset

    If alpha < 0 Then alpha = 0
    If alpha > 255 Then alpha = 255

    If line_width <= 0 Or alpha <= 0 Then
        Exit Sub
    End If

    If line_width = 1 And alpha >= 255 Then
        backend_Line(x1, y1, x2, y2, clr)
        Exit Sub
    End If

    /'
        Imported System Platform line widths are literal pixel widths.

        The old radius-based widening drew -radius..radius, so width 2 and
        width 3 both occupied three pixels.  Even widths cannot be perfectly
        centered on a one-pixel raster line, so they are biased down/right by
        one pixel while still drawing exactly the requested width.
    '/
    first_offset = -((line_width - 1) \ 2)
    last_offset = first_offset + line_width - 1

    If Abs(x2 - x1) >= Abs(y2 - y1) Then
        For offset = first_offset To last_offset
            If alpha >= 255 Then
                backend_Line(x1, y1 + offset, x2, y2 + offset, clr)
            Else
                backend_DrawLineAlpha(x1, y1 + offset, x2, y2 + offset, clr, alpha)
            End If
        Next offset
    Else
        For offset = first_offset To last_offset
            If alpha >= 255 Then
                backend_Line(x1 + offset, y1, x2 + offset, y2, clr)
            Else
                backend_DrawLineAlpha(x1 + offset, y1, x2 + offset, y2, clr, alpha)
            End If
        Next offset
    End If
End Sub

Sub backend_RectEx(ByVal x As Integer, ByVal y As Integer, _
                   ByVal w As Integer, ByVal h As Integer, _
                   ByVal clr As ULong, ByVal filled As Integer, _
                   ByVal line_width As Integer, ByVal alpha As Integer)
    Dim As Integer px
    Dim As Integer py
    Dim As Integer inset

    If w <= 0 Or h <= 0 Then Exit Sub
    If alpha < 0 Then alpha = 0
    If alpha > 255 Then alpha = 255

    If alpha <= 0 Then
        Exit Sub
    End If

    If alpha >= 255 And line_width = 1 Then
        backend_Rect(x, y, w, h, clr, filled)
        Exit Sub
    End If

    If filled <> 0 Then
        If alpha >= 255 Then
            backend_Rect(x, y, w, h, clr, 1)
        Else
            For py = y To y + h - 1
                For px = x To x + w - 1
                    backend_PSetAlpha(px, py, clr, alpha)
                Next px
            Next py
        End If
    Else
        If line_width <= 0 Then
            Exit Sub
        End If

        For inset = 0 To line_width - 1
            backend_LineEx(x + inset, y + inset, x + w - 1 - inset, y + inset, clr, 1, alpha)
            backend_LineEx(x + inset, y + h - 1 - inset, x + w - 1 - inset, y + h - 1 - inset, clr, 1, alpha)
            backend_LineEx(x + inset, y + inset, x + inset, y + h - 1 - inset, clr, 1, alpha)
            backend_LineEx(x + w - 1 - inset, y + inset, x + w - 1 - inset, y + h - 1 - inset, clr, 1, alpha)
        Next inset
    End If
End Sub

Sub backend_PSet(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong) : PSet (x, y), MapColor(clr) : End Sub

Sub backend_Circle(ByVal x As Integer, ByVal y As Integer, ByVal r As Integer, ByVal clr As ULong, ByVal filled As Integer)
    If filled Then : Circle (x, y), r, MapColor(clr), , , , F : Else : Circle (x, y), r, MapColor(clr) : End If
End Sub

Sub backend_RoundRect( _
    ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer, _
    ByVal radius As Integer, ByVal clr As ULong, ByVal filled As Integer _
)
    If w < 1 OrElse h < 1 Then Exit Sub
    ' GUI corners never need a large radius. Bound the work for bad layouts.
    If radius > 32 Then radius = 32
    If radius > (w - 1) \ 2 Then radius = (w - 1) \ 2
    If radius > (h - 1) \ 2 Then radius = (h - 1) \ 2
    If radius < 1 Then
        backend_Rect(x, y, w, h, clr, filled)
        Exit Sub
    End If

    If filled <> 0 Then
        backend_Rect(x, y + radius, w, h - radius * 2, clr, 1)
    Else
        backend_Line(x, y + radius, x, y + h - radius - 1, clr)
        backend_Line(x + w - 1, y + radius, x + w - 1, y + h - radius - 1, clr)
    End If

    For rowIndex As Integer = 0 To radius - 1
        Dim As Integer distance = radius - rowIndex
        Dim As Integer inset = radius - Int(Sqr(radius * radius - distance * distance))
        If filled <> 0 OrElse rowIndex = 0 Then
            backend_Line(x + inset, y + rowIndex, x + w - inset - 1, y + rowIndex, clr)
            backend_Line(x + inset, y + h - rowIndex - 1, x + w - inset - 1, y + h - rowIndex - 1, clr)
        Else
            ' The difference between adjacent arc rows fills the border's steps.
            Dim As Integer previousDistance = distance + 1
            Dim As Integer previousInset = radius - Int(Sqr(radius * radius - previousDistance * previousDistance))
            backend_Line(x + inset, y + rowIndex, x + previousInset, y + rowIndex, clr)
            backend_Line(x + w - previousInset - 1, y + rowIndex, x + w - inset - 1, y + rowIndex, clr)
            backend_Line(x + inset, y + h - rowIndex - 1, x + previousInset, y + h - rowIndex - 1, clr)
            backend_Line(x + w - previousInset - 1, y + h - rowIndex - 1, x + w - inset - 1, y + h - rowIndex - 1, clr)
        End If
    Next rowIndex
End Sub

Sub backend_Curve(ByVal x1 As Integer, ByVal y1 As Integer, ByVal x2 As Integer, ByVal y2 As Integer, ByVal x3 As Integer, ByVal y3 As Integer, ByVal clr As ULong)
    Dim As Double t
    Dim As Double pixelX
    Dim As Double pixelY
    Dim As Integer oldX
    Dim As Integer oldY
    Dim As ULong mappedColor = MapColor(clr)

    For t = 0.0 To 1.0 Step BACKEND_CURVE_STEP
        pixelX = (1.0 - t) ^ 2 * x1 + 2.0 * (1.0 - t) * t * x2 + t ^ 2 * x3
        pixelY = (1.0 - t) ^ 2 * y1 + 2.0 * (1.0 - t) * t * y2 + t ^ 2 * y3

        If t > 0.0 Then
            Line (oldX, oldY)-(CInt(pixelX), CInt(pixelY)), mappedColor
        End If

        oldX = CInt(pixelX)
        oldY = CInt(pixelY)
    Next
End Sub

' -------------------------------------------------------------------------
' Text (Alpha Blended)
' -------------------------------------------------------------------------

Private Function backend_UnicodeGlyph( _
    ByVal codepoint As Integer _
) As UByte Ptr

    Dim As BackendFontGlyphIndex Ptr packedGlyph = backend_FontPackFind( _
        BACKEND_FONT_UNICODE_FALLBACK, codepoint _
    )
    If packedGlyph <> 0 Then Return packedGlyph->bitmap

    Dim As Integer lowerIndex = 0
    Dim As Integer upperIndex = backend_UnicodeGlyphCount - 1

    While lowerIndex <= upperIndex
        Dim As Integer middleIndex = lowerIndex + _
            ((upperIndex - lowerIndex) \ 2)
        Dim As UInteger candidate = backend_UnicodeCodepoints[middleIndex]

        If candidate = CUInt(codepoint) Then _
            Return backend_UnicodeGlyphs[middleIndex]
        If candidate < CUInt(codepoint) Then
            lowerIndex = middleIndex + 1
        Else
            upperIndex = middleIndex - 1
        End If
    Wend

    Return 0

End Function


Private Function backend_FontGlyph(ByVal font_id As Integer, _
                                   ByVal char_code As Integer) As UByte Ptr

    If backend_HasFontPack(font_id) <> 0 Then
        Dim As BackendFontGlyphIndex Ptr packedGlyph = _
            backend_FontPackFind(font_id, char_code)
        If packedGlyph <> 0 Then
            packedGlyph = backend_FontPackPreferZeroAdvance( _
                char_code, packedGlyph _
            )
            Return packedGlyph->bitmap
        End If
    End If

    If char_code >= 32 AndAlso char_code <= 126 Then
        Select Case font_id
        Case BACKEND_FONT_CUSTOM
            If backend_CustomFontGlyphs = 0 Then Return 0
            Return backend_CustomFontGlyphs[char_code - 32]
        Case BACKEND_FONT_ARIAL_10_REGULAR
#ifdef OMAGUI_REDISTRIBUTABLE_FONTS
            Return font_omagui_sans_10_regular_chars(char_code)
#else
            Return font_arial_10_regular_chars(char_code)
#endif
        Case BACKEND_FONT_ARIAL_12_BOLD
#ifdef OMAGUI_REDISTRIBUTABLE_FONTS
            Return font_omagui_sans_12_bold_chars(char_code)
#else
            Return font_arial_12_bold_chars(char_code)
#endif
        Case BACKEND_FONT_LIBERATION_SANS_18_BOLD
#ifdef OMAGUI_REDISTRIBUTABLE_FONTS
            Return font_omagui_sans_18_bold_chars(char_code)
#else
            Return font_liberation_sans_18_bold_chars(char_code)
#endif
        Case BACKEND_FONT_LIBERATION_SERIF_18_REGULAR
#ifdef OMAGUI_REDISTRIBUTABLE_FONTS
            Return font_omagui_serif_18_regular_chars(char_code)
#else
            Return font_liberation_serif_18_regular_chars(char_code)
#endif
        Case Else
            Return font_chars(char_code)
        End Select
    End If

    If char_code < 32 OrElse char_code = 127 Then Return 0

    Dim As BackendFontGlyphIndex Ptr unicodeGlyph = _
        backend_FontPackTextGlyph(font_id, char_code)
    If unicodeGlyph <> 0 Then Return unicodeGlyph->bitmap

    Dim As UByte Ptr glyph = backend_UnicodeGlyph(char_code)
    If glyph <> 0 Then Return glyph

    /'
        The CJK pack does not map every combining mark or common symbol.
        Reuse the already loaded UI face before replacing those with '?' .
    '/
    Dim As BackendFontGlyphIndex Ptr uiGlyph = _
        backend_FontPackFind(BACKEND_FONT_DEFAULT, char_code)
    If uiGlyph <> 0 Then Return uiGlyph->bitmap

    ' Keep unsupported Unicode visible and measurable instead of dropping bytes.
    Return font_chars(Asc("?"))

End Function


Private Function backend_InvalidUTF8(ByRef byteIndex As Integer) As Integer
    byteIndex += 1
    Return Asc("?")
End Function

Function backend_ReadUTF8Codepoint( _
    ByRef text As Const String, ByRef byteIndex As Integer _
) As Integer

    Dim As Integer textLength = Len(text)
    Dim As Integer firstByte
    Dim As Integer secondByte
    Dim As Integer thirdByte
    Dim As Integer fourthByte
    Dim As Integer codepoint

    If byteIndex < 0 OrElse byteIndex >= textLength Then Return 0
    firstByte = text[byteIndex]

    If firstByte < &H80 Then
        byteIndex += 1
        Return firstByte
    End If

    If firstByte >= &HC2 AndAlso firstByte <= &HDF Then
        If byteIndex + 1 >= textLength Then _
            Return backend_InvalidUTF8(byteIndex)
        secondByte = text[byteIndex + 1]
        If secondByte < &H80 OrElse secondByte > &HBF Then _
            Return backend_InvalidUTF8(byteIndex)
        codepoint = ((firstByte And &H1F) Shl 6) Or _
                    (secondByte And &H3F)
        byteIndex += 2
        Return codepoint
    End If

    If firstByte >= &HE0 AndAlso firstByte <= &HEF Then
        If byteIndex + 2 >= textLength Then _
            Return backend_InvalidUTF8(byteIndex)
        secondByte = text[byteIndex + 1]
        thirdByte = text[byteIndex + 2]
        If secondByte < &H80 OrElse secondByte > &HBF OrElse _
           thirdByte < &H80 OrElse thirdByte > &HBF Then _
            Return backend_InvalidUTF8(byteIndex)
        If (firstByte = &HE0 AndAlso secondByte < &HA0) OrElse _
           (firstByte = &HED AndAlso secondByte > &H9F) Then _
            Return backend_InvalidUTF8(byteIndex)
        codepoint = ((firstByte And &HF) Shl 12) Or _
                    ((secondByte And &H3F) Shl 6) Or _
                    (thirdByte And &H3F)
        byteIndex += 3
        Return codepoint
    End If

    If firstByte >= &HF0 AndAlso firstByte <= &HF4 Then
        If byteIndex + 3 >= textLength Then _
            Return backend_InvalidUTF8(byteIndex)
        secondByte = text[byteIndex + 1]
        thirdByte = text[byteIndex + 2]
        fourthByte = text[byteIndex + 3]
        If secondByte < &H80 OrElse secondByte > &HBF OrElse _
           thirdByte < &H80 OrElse thirdByte > &HBF OrElse _
           fourthByte < &H80 OrElse fourthByte > &HBF Then _
            Return backend_InvalidUTF8(byteIndex)
        If (firstByte = &HF0 AndAlso secondByte < &H90) OrElse _
           (firstByte = &HF4 AndAlso secondByte > &H8F) Then _
            Return backend_InvalidUTF8(byteIndex)
        codepoint = ((firstByte And &H7) Shl 18) Or _
                    ((secondByte And &H3F) Shl 12) Or _
                    ((thirdByte And &H3F) Shl 6) Or _
                    (fourthByte And &H3F)
        byteIndex += 4
        Return codepoint
    End If

    ' Stray continuation bytes and excluded leading bytes still consume one byte.
    Return backend_InvalidUTF8(byteIndex)

End Function

Sub backend_SetCustomFont(ByVal glyphs As UByte Ptr Ptr)
    backend_FontGeneration += 1
    ' The caller owns the glyph table for the lifetime of the backend.
    backend_CustomFontGlyphs = glyphs
End Sub


Function backend_SetUnicodeGlyphs( _
    ByVal codepoints As UInteger Ptr, _
    ByVal glyphs As UByte Ptr Ptr, _
    ByVal glyph_count As Integer _
) As Integer
    backend_FontGeneration += 1

    If glyph_count <= 0 Then
        backend_UnicodeCodepoints = 0
        backend_UnicodeGlyphs = 0
        backend_UnicodeGlyphCount = 0
        Return -1
    End If
    If codepoints = 0 OrElse glyphs = 0 Then Return 0

    For glyphIndex As Integer = 0 To glyph_count - 1
        Dim As UInteger codepoint = codepoints[glyphIndex]
        If codepoint > &H10FFFF OrElse _
           (codepoint >= &HD800 AndAlso codepoint <= &HDFFF) OrElse _
           glyphs[glyphIndex] = 0 Then Return 0
        If glyphIndex > 0 AndAlso _
           codepoint <= codepoints[glyphIndex - 1] Then Return 0
    Next glyphIndex

    backend_UnicodeCodepoints = codepoints
    backend_UnicodeGlyphs = glyphs
    backend_UnicodeGlyphCount = glyph_count
    Return -1

End Function

#Ifdef __FB_GFXLIB3__
Private Function backend_DrawTextGfx3( _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal clr As ULong, _
    ByVal text As String, _
    ByVal font_id As Integer, _
    ByVal scale_x As Integer, _
    ByVal scale_y As Integer, _
    ByVal text_alpha As Integer _
) As Integer
    Dim As Integer screen_w
    Dim As Integer screen_h
    Dim As Integer screen_d
    Dim As Integer character_code
    Dim As Integer byte_index
    Dim As Integer glyph_width
    Dim As Integer glyph_height
    Dim As Integer glyph_alpha
    Dim As Integer point_count
    Dim As Integer current_x
    Dim As Integer previous_cell_x
    Dim As Integer previous_cell_advance
    Dim As Integer glyph_draw_x
    Dim As Integer glyph_advance
    Dim As Integer bearing_x
    Dim As Integer bearing_y
    Dim As ULongInt point_capacity
    Dim As ULongInt glyph_capacity
    Dim As UByte Ptr glyph
    Dim points() As fb.Gfx3Point

    If scale_x < 1 Or scale_y < 1 Or text_alpha <= 0 Then
        Return -1
    End If
    If text_alpha > 255 Then text_alpha = 255

    ScreenInfo screen_w, screen_h, screen_d
    If screen_d <> 32 Then Return 0

    /'
        Size the packet before allocation. Gfx3DrawPoints copies it into the
        renderer queue before returning, so this temporary array never escapes
        the call and can be released by FreeBASIC at function exit.
    '/
    byte_index = 0
    While byte_index < Len(text)
        character_code = backend_ReadUTF8Codepoint(text, byte_index)
        glyph = backend_FontGlyph(font_id, character_code)

        If glyph <> 0 Then
            glyph_capacity = CULngInt(glyph[0]) * CULngInt(glyph[1]) * _
                             CULngInt(scale_x) * CULngInt(scale_y)
            If glyph_capacity > BACKEND_GFX3_TEXT_POINT_LIMIT - point_capacity Then
                Return 0
            End If
            point_capacity += glyph_capacity
        End If
    Wend

    If point_capacity = 0 Then Return -1
    ReDim points(0 To CInt(point_capacity) - 1)

    current_x = x
    previous_cell_x = x
    byte_index = 0
    While byte_index < Len(text)
        character_code = backend_ReadUTF8Codepoint(text, byte_index)
        glyph = backend_FontGlyph(font_id, character_code)

        If glyph <> 0 Then
            glyph_width = glyph[0]
            glyph_height = glyph[1]
            glyph_advance = backend_FontGlyphAdvance( _
                font_id, character_code, glyph _
            )
            backend_FontGlyphBearing( _
                font_id, character_code, glyph, bearing_x, bearing_y _
            )
            glyph_draw_x = backend_ZeroAdvanceGlyphPenX( _
                current_x, previous_cell_x, previous_cell_advance, _
                glyph_advance, glyph_width, bearing_x, scale_x, 1 _
            )

            For pixel_y As Integer = 0 To glyph_height - 1
                For pixel_x As Integer = 0 To glyph_width - 1
                    glyph_alpha = (CInt(glyph[2 + pixel_y * glyph_width + pixel_x]) * _
                                   text_alpha) \ 255

                    If glyph_alpha > 0 Then
                        For scaled_y As Integer = 0 To scale_y - 1
                            For scaled_x As Integer = 0 To scale_x - 1
                                points(point_count).x = glyph_draw_x + _
                                    (bearing_x * scale_x) + _
                                    (pixel_x * scale_x) + scaled_x
                                points(point_count).y = y + _
                                    (bearing_y * scale_y) + _
                                    (pixel_y * scale_y) + scaled_y
                                points(point_count).color = clr
                                points(point_count).alpha = _
                                    backend_Gfx3Alpha(glyph_alpha)
                                point_count += 1
                            Next scaled_x
                        Next scaled_y
                    End If
                Next pixel_x
            Next pixel_y

            If glyph_advance > 0 Then
                previous_cell_x = current_x
                previous_cell_advance = glyph_advance
            End If
            current_x += glyph_advance * scale_x
        End If
    Wend

    If point_count = 0 Then Return -1
    If fb.Gfx3DrawPoints(0, @points(0), point_count) <> 0 Then Return 0
    Return -1
End Function

Private Function backend_DrawTextGfx3Percent( _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal clr As ULong, _
    ByVal text As String, _
    ByVal percent As Integer, _
    ByVal italic As Integer _
) As Integer

    Dim As Integer screen_w
    Dim As Integer screen_h
    Dim As Integer screen_d
    Dim As Integer scaled_width
    Dim As Integer scaled_height
    Dim As Integer source_x
    Dim As Integer source_y
    Dim As Integer row_shift_hundredths
    Dim As Integer row_content_width_hundredths
    Dim As Integer shear_maximum
    Dim As Integer source_x_hundredths
    Dim As Integer source_x_next
    Dim As Integer source_fraction
    Dim As Integer first_alpha
    Dim As Integer second_alpha
    Dim As Integer glyph_alpha
    Dim As Integer point_count
    Dim As Integer current_x
    Dim As Integer previous_cell_x
    Dim As Integer previous_cell_advance
    Dim As Integer glyph_draw_x
    Dim As Integer glyph_advance
    Dim As Integer bearing_x
    Dim As Integer bearing_y
    Dim As Integer byte_index
    Dim As Integer character_code
    Dim As ULongInt point_capacity
    Dim As ULongInt glyph_capacity
    Dim As UByte Ptr glyph
    Dim points() As fb.Gfx3Point

    If percent < BACKEND_MIN_FONT_PERCENT OrElse percent > BACKEND_MAX_FONT_PERCENT Then Return 0

    ScreenInfo screen_w, screen_h, screen_d
    If screen_d <> 32 Then Return 0

    byte_index = 0
    While byte_index < Len(text)
        character_code = backend_ReadUTF8Codepoint(text, byte_index)
        glyph = backend_FontGlyph(BACKEND_FONT_DEFAULT, character_code)
        If glyph <> 0 Then
            If glyph[0] = 0 OrElse glyph[1] = 0 Then Continue While
            scaled_width = (CInt(glyph[0]) * percent + 50) \ 100
            scaled_height = (CInt(glyph[1]) * percent + 50) \ 100
            If scaled_width < 1 Then scaled_width = 1
            If scaled_height < 1 Then scaled_height = 1
            glyph_capacity = CULngInt(scaled_width) * _
                             CULngInt(scaled_height)
            If glyph_capacity > _
               BACKEND_GFX3_TEXT_POINT_LIMIT - point_capacity Then Return 0
            point_capacity += glyph_capacity
        End If
    Wend

    If point_capacity = 0 Then Return -1
    ReDim points(0 To CInt(point_capacity) - 1)

    current_x = x
    previous_cell_x = x
    byte_index = 0
    While byte_index < Len(text)
        character_code = backend_ReadUTF8Codepoint(text, byte_index)
        glyph = backend_FontGlyph(BACKEND_FONT_DEFAULT, character_code)
        If glyph = 0 Then Continue While
        glyph_advance = backend_FontGlyphAdvance( _
            BACKEND_FONT_DEFAULT, character_code, glyph _
        )
        If glyph[0] = 0 OrElse glyph[1] = 0 Then
            ' An advance-only glyph still occupies its measured text width.
            If glyph_advance > 0 Then
                previous_cell_x = current_x
                previous_cell_advance = glyph_advance
            End If
            current_x += (glyph_advance * percent + 50) \ 100
            Continue While
        End If

        backend_FontGlyphBearing( _
            BACKEND_FONT_DEFAULT, character_code, glyph, bearing_x, bearing_y _
        )

        scaled_width = (CInt(glyph[0]) * percent + 50) \ 100
        scaled_height = (CInt(glyph[1]) * percent + 50) \ 100
        If scaled_width < 1 Then scaled_width = 1
        If scaled_height < 1 Then scaled_height = 1
        glyph_draw_x = backend_ZeroAdvanceGlyphPenX( _
            current_x, previous_cell_x, previous_cell_advance, _
            glyph_advance, glyph[0], bearing_x, percent, 100 _
        )

        For dest_y As Integer = 0 To scaled_height - 1
            source_y = (dest_y * 100) \ percent
            row_shift_hundredths = 0
            row_content_width_hundredths = scaled_width * 100
            If italic <> 0 AndAlso scaled_width > 1 AndAlso _
               scaled_height > 1 Then
                shear_maximum = _
                    scaled_height * BACKEND_ITALIC_SHEAR_PERCENT
                If shear_maximum > (scaled_width - 1) * 100 Then _
                    shear_maximum = (scaled_width - 1) * 100
                If shear_maximum > 0 Then
                    row_shift_hundredths = (shear_maximum * _
                        (scaled_height - 1 - dest_y)) \ _
                        (scaled_height - 1)
                    row_content_width_hundredths = _
                        scaled_width * 100 - row_shift_hundredths
                End If
            End If

            For dest_x As Integer = 0 To scaled_width - 1
                If row_shift_hundredths = 0 Then
                    source_x = (dest_x * 100) \ percent
                Else
                    source_x_hundredths = _
                        (dest_x * 100 - row_shift_hundredths) * glyph[0] * 100
                    If source_x_hundredths < 0 Then Continue For
                    source_x_hundredths = _
                        source_x_hundredths \ row_content_width_hundredths
                    If source_x_hundredths > (glyph[0] - 1) * 100 Then _
                        source_x_hundredths = (glyph[0] - 1) * 100
                    source_x = source_x_hundredths \ 100
                    source_x_next = source_x + 1
                    If source_x_next >= glyph[0] Then _
                        source_x_next = glyph[0] - 1
                    source_fraction = source_x_hundredths Mod 100
                    first_alpha = _
                        glyph[2 + source_y * glyph[0] + source_x]
                    second_alpha = _
                        glyph[2 + source_y * glyph[0] + source_x_next]
                    glyph_alpha = (first_alpha * (100 - source_fraction) + _
                        second_alpha * source_fraction) \ 100
                End If
                If row_shift_hundredths = 0 Then _
                    glyph_alpha = _
                        glyph[2 + source_y * glyph[0] + source_x]
                If glyph_alpha <= 0 Then Continue For

                points(point_count).x = glyph_draw_x + _
                    ((bearing_x * percent) \ 100) + dest_x
                points(point_count).y = y + _
                    ((bearing_y * percent) \ 100) + dest_y
                points(point_count).color = clr
                points(point_count).alpha = backend_Gfx3Alpha(glyph_alpha)
                point_count += 1
            Next dest_x
        Next dest_y

        If glyph_advance > 0 Then
            previous_cell_x = current_x
            previous_cell_advance = glyph_advance
        End If
        current_x += ((glyph_advance * percent + 50) \ 100)
    Wend

    If point_count = 0 Then Return -1
    If fb.Gfx3DrawPoints(0, @points(0), point_count) <> 0 Then Return 0
    Return -1

End Function
#EndIf

Private Function backend_AlignedX(ByVal x As Integer, ByVal w As Integer, _
                                  ByVal text_w As Integer, _
                                  ByVal horizontal_align As Integer) As Integer
    Select Case horizontal_align
    Case BACKEND_ALIGN_CENTER
        Return x + ((w - text_w) \ 2)
    Case BACKEND_ALIGN_RIGHT
        Return x + w - text_w
    Case Else
        Return x
    End Select
End Function

Private Function backend_AlignedY(ByVal y As Integer, ByVal h As Integer, _
                                  ByVal text_h As Integer, _
                                  ByVal vertical_align As Integer) As Integer
    Select Case vertical_align
    Case BACKEND_ALIGN_MIDDLE
        Return y + ((h - text_h) \ 2)
    Case BACKEND_ALIGN_BOTTOM
        Return y + h - text_h
    Case Else
        Return y
    End Select
End Function


Private Function backend_ScaleFontOffsetPercent( _
    ByVal font_offset As Integer, ByVal percent As Integer _
) As Integer

    If font_offset < 0 Then
        Return -((Abs(font_offset) * percent + 50) \ 100)
    End If
    Return (font_offset * percent + 50) \ 100

End Function

Private Sub DrawCharFont(ByVal x As Integer, ByVal y As Integer, _
                         ByVal charCode As Integer, ByVal clr As ULong, _
                         ByVal font_id As Integer, ByVal text_alpha As Integer, _
                         ByVal screenDepth As Integer)
    Dim As UByte Ptr p = backend_FontGlyph(font_id, charCode) : If p = 0 Then Exit Sub
    Dim As Integer bearing_x
    Dim As Integer bearing_y
    backend_FontGlyphBearing(font_id, charCode, p, bearing_x, bearing_y)

    Dim As Integer w = p[0]
    Dim As Integer h = p[1]
    Dim As ULong r = (clr Shr 16) And &HFF
    Dim As ULong g = (clr Shr 8) And &HFF
    Dim As ULong b = clr And &HFF

    If backend_FontSpanVisible(CLngInt(x) + bearing_x, CLngInt(y) + bearing_y, _
        w, h) = 0 Then Exit Sub

    If text_alpha <= 0 Then Exit Sub
    If text_alpha > 255 Then text_alpha = 255

    If backend_FontSpanBegin(w, h, screenDepth) <> 0 Then
        For py As Integer = 0 To h - 1
            For px As Integer = 0 To w - 1
                Dim As ULong coverage = p[2 + py * w + px]
                If text_alpha <> 255 Then coverage = (coverage * text_alpha) \ 255
                ' fblint: disable-next-line FBL310 -- private mask state is declared in backend_font_span.bi.
                backend_FontSpanPixels[py * backend_FontSpanPitch + px] = coverage Shl 24
            Next px
        Next py
        backend_FontSpanEnd x + bearing_x, y + bearing_y, w, h, clr
        Exit Sub
    End If

    For py As Integer = 0 To h - 1
        For px As Integer = 0 To w - 1
            Dim As Integer alpha = (CInt(p[2 + py * w + px]) * text_alpha) \ 255

            If alpha > 0 Then
                If screenDepth < 16 Then
                    If alpha > 128 Then PSet _
                        (x + bearing_x + px, y + bearing_y + py), MapColor(clr)
                Elseif alpha = 255 Then
                    PSet _
                        (x + bearing_x + px, y + bearing_y + py), MapColor(clr)
                Else
                    Dim As ULong bg = Point( _
                        x + bearing_x + px, y + bearing_y + py _
                    )
                    Dim As ULong br = (bg Shr 16) And &HFF
                    Dim As ULong bg_g = (bg Shr 8) And &HFF
                    Dim As ULong bb = bg And &HFF

                    Dim As ULong resR = (r * alpha + br * (255 - alpha)) \ 255
                    Dim As ULong resG = (g * alpha + bg_g * (255 - alpha)) \ 255
                    Dim As ULong resB = (b * alpha + bb * (255 - alpha)) \ 255

                    PSet _
                        (x + bearing_x + px, y + bearing_y + py), _
                        RGB(resR, resG, resB)
                End If
            End If
        Next
    Next
End Sub

Private Sub DrawCharScaledFont(ByVal x As Integer, ByVal y As Integer, _
                               ByVal charCode As Integer, ByVal clr As ULong, _
                               ByVal font_id As Integer, _
                               ByVal scale_x As Integer, ByVal scale_y As Integer, _
                               ByVal text_alpha As Integer)
    Dim As UByte Ptr p
    Dim As Integer w
    Dim As Integer h
    Dim As Integer alpha
    Dim As Integer px
    Dim As Integer py
    Dim As Integer sx
    Dim As Integer sy
    Dim As Integer bearing_x
    Dim As Integer bearing_y

    If scale_x < 1 Then scale_x = 1
    If scale_y < 1 Then scale_y = 1
    If text_alpha <= 0 Then Exit Sub
    If text_alpha > 255 Then text_alpha = 255

    p = backend_FontGlyph(font_id, charCode)
    If p = 0 Then Exit Sub

    w = p[0]
    h = p[1]
    backend_FontGlyphBearing(font_id, charCode, p, bearing_x, bearing_y)

    If backend_FontSpanVisible(CLngInt(x) + CLngInt(bearing_x) * scale_x, _
        CLngInt(y) + CLngInt(bearing_y) * scale_y, _
        CLngInt(w) * scale_x, CLngInt(h) * scale_y) = 0 Then Exit Sub

    For py = 0 To h - 1
        For px = 0 To w - 1
            alpha = (CInt(p[2 + py * w + px]) * text_alpha) \ 255

            If alpha > 0 Then
                For sy = 0 To scale_y - 1
                    For sx = 0 To scale_x - 1
                        backend_PSetAlpha( _
                            x + (bearing_x * scale_x) + _
                                (px * scale_x) + sx, _
                            y + (bearing_y * scale_y) + _
                                (py * scale_y) + sy, _
                                          clr, alpha)
                    Next sx
                Next sy
            End If
        Next px
    Next py
End Sub

Sub backend_PrintFont(ByVal x As Integer, ByVal y As Integer, _
                      ByVal clr As ULong, ByVal text As String, _
                      ByVal font_id As Integer)
    backend_PrintFontAlpha x, y, clr, text, font_id, 255
End Sub

Sub backend_PrintFontAlpha(ByVal x As Integer, ByVal y As Integer, _
                           ByVal clr As ULong, ByVal text As String, _
                           ByVal font_id As Integer, ByVal alpha As Integer)
#Ifdef __FB_GFXLIB3__
    If backend_DrawTextGfx3(x, y, clr, text, font_id, 1, 1, alpha) Then
        Exit Sub
    End If
#EndIf

    Dim As Integer screenDepth = backend_FontSpanDepth()
    Dim As Integer curX = x
    Dim As Integer previousCellX = x
    Dim As Integer previousCellAdvance
    Dim As Integer glyphDrawX
    Dim As Integer bearingX
    Dim As Integer bearingY
    Dim As Integer byteIndex = 0
    While byteIndex < Len(text)
        Dim As Integer charCode = _
            backend_ReadUTF8Codepoint(text, byteIndex)
        Dim As UByte Ptr glyph = backend_FontGlyph(font_id, charCode)
        If glyph <> 0 Then
            Dim As Integer glyphAdvance = _
                backend_FontGlyphAdvance(font_id, charCode, glyph)
            backend_FontGlyphBearing( _
                font_id, charCode, glyph, bearingX, bearingY _
            )
            glyphDrawX = backend_ZeroAdvanceGlyphPenX( _
                curX, previousCellX, previousCellAdvance, _
                glyphAdvance, glyph[0], bearingX, 1, 1 _
            )
            DrawCharFont(glyphDrawX, y, charCode, clr, font_id, alpha, screenDepth)
            If glyphAdvance > 0 Then
                previousCellX = curX
                previousCellAdvance = glyphAdvance
            End If
            curX += glyphAdvance
        End If
    Wend
End Sub

Sub backend_Print(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal text As String)
    backend_PrintFont x, y, clr, text, BACKEND_FONT_DEFAULT
End Sub

Private Sub backend_PrintPercentStyled( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal clr As ULong, ByVal text As String, _
    ByVal font_id As Integer, ByVal percent As Integer, _
    ByVal italic As Integer _
)

    Dim As Integer glyph_width
    Dim As Integer glyph_height
    Dim As Integer source_x
    Dim As Integer source_y
    Dim As Integer current_x = x
    Dim As Integer previous_cell_x = x
    Dim As Integer previous_cell_advance
    Dim As Integer glyph_draw_x
    Dim As Integer scaled_width
    Dim As Integer scaled_height
    Dim As Integer font_ascent
    Dim As Integer scaled_ascent
    Dim As Integer glyph_bottom_offset
    Dim As Integer scaled_bottom_offset
    Dim As Integer glyph_draw_y
    Dim As Integer row_shift_hundredths
    Dim As Integer row_content_width_hundredths
    Dim As Integer shear_maximum
    Dim As Integer source_x_hundredths
    Dim As Integer source_x_next
    Dim As Integer source_fraction
    Dim As Integer first_alpha
    Dim As Integer second_alpha
    Dim As Integer glyph_alpha
    Dim As Integer byte_index
    Dim As Integer character_code
    Dim As Integer bearing_x
    Dim As Integer bearing_y
    Dim As Integer glyph_advance
    Dim As UByte Ptr glyph

    If percent < BACKEND_MIN_FONT_PERCENT Then percent = BACKEND_MIN_FONT_PERCENT
    If percent > BACKEND_MAX_FONT_PERCENT Then percent = BACKEND_MAX_FONT_PERCENT
    If backend_HasFontPack(font_id) <> 0 Then
        font_ascent = backend_FontAscent(font_id)
    Else
        ' The fixed legacy tables keep their original top-aligned bitmap canvas.
        font_ascent = -1
    End If
    If font_ascent >= 0 Then _
        scaled_ascent = (font_ascent * percent + 50) \ 100

#Ifdef __FB_GFXLIB3__
    If font_id = BACKEND_FONT_DEFAULT AndAlso backend_HasFontPack(font_id) = 0 AndAlso backend_DrawTextGfx3Percent( _
        x, y, clr, text, percent, italic _
    ) Then Exit Sub
#EndIf

    Dim As Integer screenDepth = backend_FontSpanDepth()
    byte_index = 0
    While byte_index < Len(text)
        character_code = backend_ReadUTF8Codepoint(text, byte_index)
        glyph = backend_FontGlyph(font_id, character_code)
        If glyph = 0 Then Continue While
        glyph_advance = backend_FontGlyphAdvance( _
            font_id, character_code, glyph _
        )
        If glyph[0] = 0 OrElse glyph[1] = 0 Then
            If glyph_advance > 0 Then
                previous_cell_x = current_x
                previous_cell_advance = glyph_advance
            End If
            current_x += (glyph_advance * percent + 50) \ 100
            Continue While
        End If
        backend_FontGlyphBearing( _
            font_id, character_code, glyph, bearing_x, bearing_y _
        )

        glyph_width = glyph[0]
        glyph_height = glyph[1]
        ' Normal-sized upright text needs no resampling. The span check keeps
        ' indexed-color and GPU pages on their established raster paths.
        If percent = 100 AndAlso italic = 0 AndAlso _
           backend_FontSpanBegin(glyph_width, glyph_height, screenDepth) <> 0 Then
            glyph_draw_x = backend_ZeroAdvanceGlyphPenX( _
                current_x, previous_cell_x, previous_cell_advance, _
                glyph_advance, glyph_width, bearing_x, 100, 100 _
            )
            DrawCharFont glyph_draw_x, y, character_code, clr, font_id, 255, screenDepth
            If glyph_advance > 0 Then
                previous_cell_x = current_x
                previous_cell_advance = glyph_advance
            End If
            current_x += glyph_advance
            Continue While
        End If
        scaled_width = (glyph_width * percent + 50) \ 100
        scaled_height = (glyph_height * percent + 50) \ 100
        If scaled_width < 1 Then scaled_width = 1
        If scaled_height < 1 Then scaled_height = 1
        If font_ascent >= 0 Then
            ' Scale the glyph's bottom offset around the shared font baseline.
            glyph_bottom_offset = bearing_y + glyph_height - font_ascent
            scaled_bottom_offset = backend_ScaleFontOffsetPercent( _
                glyph_bottom_offset, percent _
            )
            glyph_draw_y = y + scaled_ascent + scaled_bottom_offset - _
                scaled_height
        Else
            glyph_draw_y = y + ((bearing_y * percent) \ 100)
        End If
        glyph_draw_x = backend_ZeroAdvanceGlyphPenX( _
            current_x, previous_cell_x, previous_cell_advance, _
            glyph_advance, glyph_width, bearing_x, percent, 100 _
        )
        If backend_FontSpanVisible(CLngInt(glyph_draw_x) + _
            ((CLngInt(bearing_x) * percent) \ 100), glyph_draw_y, _
            scaled_width, scaled_height) = 0 Then
            If glyph_advance > 0 Then
                previous_cell_x = current_x
                previous_cell_advance = glyph_advance
            End If
            current_x += (glyph_advance * percent + 50) \ 100
            Continue While
        End If
        Dim As Integer useFontSpan = backend_FontSpanBegin(scaled_width, scaled_height, screenDepth)
        For dest_y As Integer = 0 To scaled_height - 1
            source_y = (dest_y * 100) \ percent
            row_shift_hundredths = 0
            row_content_width_hundredths = scaled_width * 100
            If italic <> 0 AndAlso scaled_width > 1 AndAlso _
               scaled_height > 1 Then
                shear_maximum = _
                    scaled_height * BACKEND_ITALIC_SHEAR_PERCENT
                If shear_maximum > (scaled_width - 1) * 100 Then _
                    shear_maximum = (scaled_width - 1) * 100
                If shear_maximum > 0 Then
                    row_shift_hundredths = (shear_maximum * _
                        (scaled_height - 1 - dest_y)) \ _
                        (scaled_height - 1)
                    row_content_width_hundredths = _
                        scaled_width * 100 - row_shift_hundredths
                End If
            End If

            For dest_x As Integer = 0 To scaled_width - 1
                If row_shift_hundredths = 0 Then
                    source_x = (dest_x * 100) \ percent
                Else
                    source_x_hundredths = _
                        (dest_x * 100 - row_shift_hundredths) * _
                        glyph_width * 100
                    If source_x_hundredths < 0 Then
                        ' Shear leaves empty leading pixels. Clear their coverage
                        ' because the reusable mask may still contain a prior glyph.
                        If useFontSpan <> 0 Then
                            ' fblint: disable-next-line FBL310 -- private mask state is declared in backend_font_span.bi.
                            backend_FontSpanPixels[dest_y * backend_FontSpanPitch + dest_x] = 0
                        End If
                        Continue For
                    End If
                    source_x_hundredths = _
                        source_x_hundredths \ row_content_width_hundredths
                    If source_x_hundredths > (glyph_width - 1) * 100 Then _
                        source_x_hundredths = (glyph_width - 1) * 100
                    source_x = source_x_hundredths \ 100
                    source_x_next = source_x + 1
                    If source_x_next >= glyph_width Then _
                        source_x_next = glyph_width - 1
                    source_fraction = source_x_hundredths Mod 100
                    first_alpha = _
                        glyph[2 + source_y * glyph_width + source_x]
                    second_alpha = _
                        glyph[2 + source_y * glyph_width + source_x_next]
                    glyph_alpha = (first_alpha * (100 - source_fraction) + _
                        second_alpha * source_fraction) \ 100
                End If
                If row_shift_hundredths = 0 Then _
                    glyph_alpha = _
                        glyph[2 + source_y * glyph_width + source_x]
                If useFontSpan <> 0 Then
                    ' fblint: disable-next-line FBL310 -- private mask state is declared in backend_font_span.bi.
                    backend_FontSpanPixels[dest_y * backend_FontSpanPitch + dest_x] = CULng(glyph_alpha) Shl 24
                Else
                    backend_PSetAlpha( _
                        glyph_draw_x + ((bearing_x * percent) \ 100) + dest_x, _
                        glyph_draw_y + dest_y, clr, _
                        glyph_alpha _
                    )
                End If
            Next dest_x
        Next dest_y
        If useFontSpan <> 0 Then backend_FontSpanEnd _
            glyph_draw_x + ((bearing_x * percent) \ 100), glyph_draw_y, _
            scaled_width, scaled_height, clr
        If glyph_advance > 0 Then
            previous_cell_x = current_x
            previous_cell_advance = glyph_advance
        End If
        current_x += (glyph_advance * percent + 50) \ 100
    Wend

End Sub


Sub backend_PrintPercent( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal clr As ULong, ByVal text As String, ByVal percent As Integer _
)

    backend_PrintPercentStyled _
        x, y, clr, text, BACKEND_FONT_DEFAULT, percent, 0

End Sub


Sub backend_PrintFontPercent( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal clr As ULong, ByVal text As String, _
    ByVal font_id As Integer, ByVal percent As Integer _
)

    backend_PrintPercentStyled x, y, clr, text, font_id, percent, 0

End Sub


Sub backend_PrintItalicPercent( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal clr As ULong, ByVal text As String, ByVal percent As Integer _
)

    backend_PrintPercentStyled _
        x, y, clr, text, BACKEND_FONT_DEFAULT, percent, -1

End Sub


Sub backend_PrintItalicFontPercent( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal clr As ULong, ByVal text As String, _
    ByVal font_id As Integer, ByVal percent As Integer _
)

    backend_PrintPercentStyled x, y, clr, text, font_id, percent, -1

End Sub

Sub backend_PrintScaledFont(ByVal x As Integer, ByVal y As Integer, _
                            ByVal clr As ULong, ByVal text As String, _
                            ByVal font_id As Integer, _
                            ByVal scale_x As Integer, ByVal scale_y As Integer)
    backend_PrintScaledFontAlpha x, y, clr, text, font_id, scale_x, scale_y, 255
End Sub

Sub backend_PrintScaledFontAlpha(ByVal x As Integer, ByVal y As Integer, _
                                 ByVal clr As ULong, ByVal text As String, _
                                 ByVal font_id As Integer, _
                                 ByVal scale_x As Integer, ByVal scale_y As Integer, _
                                 ByVal alpha As Integer)
    Dim As Integer cur_x = x
    Dim As Integer previous_cell_x = x
    Dim As Integer previous_cell_advance
    Dim As Integer glyph_draw_x
    Dim As Integer char_code
    Dim As Integer byte_index
    Dim As Integer glyph_advance
    Dim As Integer bearing_x
    Dim As Integer bearing_y
    Dim As UByte Ptr glyph

    If scale_x < 1 Then scale_x = 1
    If scale_y < 1 Then scale_y = 1

#Ifdef __FB_GFXLIB3__
    If backend_DrawTextGfx3(x, y, clr, text, font_id, scale_x, scale_y, alpha) Then
        Exit Sub
    End If
#EndIf

    byte_index = 0
    While byte_index < Len(text)
        char_code = backend_ReadUTF8Codepoint(text, byte_index)
        glyph = backend_FontGlyph(font_id, char_code)
        If glyph <> 0 Then
            glyph_advance = backend_FontGlyphAdvance( _
                font_id, char_code, glyph _
            )
            backend_FontGlyphBearing( _
                font_id, char_code, glyph, bearing_x, bearing_y _
            )
            glyph_draw_x = backend_ZeroAdvanceGlyphPenX( _
                cur_x, previous_cell_x, previous_cell_advance, _
                glyph_advance, glyph[0], bearing_x, scale_x, 1 _
            )
            DrawCharScaledFont( _
                glyph_draw_x, y, char_code, clr, font_id, _
                scale_x, scale_y, alpha _
            )
            If glyph_advance > 0 Then
                previous_cell_x = cur_x
                previous_cell_advance = glyph_advance
            End If
            cur_x += glyph_advance * scale_x
        End If
    Wend
End Sub

Sub backend_PrintScaled(ByVal x As Integer, ByVal y As Integer, _
                        ByVal clr As ULong, ByVal text As String, _
                        ByVal scale_x As Integer, ByVal scale_y As Integer)
    backend_PrintScaledFont x, y, clr, text, BACKEND_FONT_DEFAULT, scale_x, scale_y
End Sub

Sub backend_PrintAlignedScaled(ByVal x As Integer, ByVal y As Integer, _
                               ByVal w As Integer, ByVal h As Integer, _
                               ByVal clr As ULong, ByVal text As String, _
                               ByVal font_id As Integer, _
                               ByVal horizontal_align As Integer, _
                               ByVal vertical_align As Integer, _
                               ByVal scale_x As Integer, _
                               ByVal scale_y As Integer)
    backend_PrintAlignedScaledAlpha x, y, w, h, clr, text, font_id, _
                                    horizontal_align, vertical_align, _
                                    scale_x, scale_y, 255
End Sub

Sub backend_PrintAlignedScaledAlpha(ByVal x As Integer, ByVal y As Integer, _
                                    ByVal w As Integer, ByVal h As Integer, _
                                    ByVal clr As ULong, ByVal text As String, _
                                    ByVal font_id As Integer, _
                                    ByVal horizontal_align As Integer, _
                                    ByVal vertical_align As Integer, _
                                    ByVal scale_x As Integer, _
                                    ByVal scale_y As Integer, _
                                    ByVal alpha As Integer)
    Dim text_w As Integer
    Dim text_h As Integer
    Dim draw_x As Integer
    Dim draw_y As Integer

    If scale_x < 1 Then scale_x = 1
    If scale_y < 1 Then scale_y = 1
    If alpha <= 0 Then Exit Sub
    If alpha > 255 Then alpha = 255

    text_w = backend_GetTextWidthScaledFont(text, font_id, scale_x)
    text_h = backend_GetTextHeightScaledFont(font_id, scale_y)
    draw_x = backend_AlignedX(x, w, text_w, horizontal_align)
    draw_y = backend_AlignedY(y, h, text_h, vertical_align)

    backend_PrintScaledFontAlpha draw_x, draw_y, clr, text, font_id, _
                                 scale_x, scale_y, alpha
End Sub

Sub backend_PrintAligned(ByVal x As Integer, ByVal y As Integer, _
                         ByVal w As Integer, ByVal h As Integer, _
                         ByVal clr As ULong, ByVal text As String, _
                         ByVal font_id As Integer, _
                         ByVal horizontal_align As Integer, _
                         ByVal vertical_align As Integer)
    backend_PrintAlignedAlpha x, y, w, h, clr, text, font_id, _
                              horizontal_align, vertical_align, 255
End Sub

Sub backend_PrintAlignedAlpha(ByVal x As Integer, ByVal y As Integer, _
                              ByVal w As Integer, ByVal h As Integer, _
                              ByVal clr As ULong, ByVal text As String, _
                              ByVal font_id As Integer, _
                              ByVal horizontal_align As Integer, _
                              ByVal vertical_align As Integer, _
                              ByVal alpha As Integer)
    backend_PrintAlignedScaledAlpha x, y, w, h, clr, text, font_id, _
                                    horizontal_align, vertical_align, _
                                    1, 1, alpha
End Sub

Function backend_GetTextWidth(ByVal text As String) As Integer
    Return backend_GetTextWidthFont(text, BACKEND_FONT_DEFAULT)
End Function

Function backend_GetTextWidthFont(ByVal text As String, ByVal font_id As Integer) As Integer
    Dim As Integer w = 0
    Dim As Integer byte_index = 0
    Dim As Integer character_code
    Dim As UByte Ptr glyph

    While byte_index < Len(text)
        character_code = backend_ReadUTF8Codepoint(text, byte_index)
        glyph = backend_FontGlyph(font_id, character_code)

        If glyph <> 0 Then
            w += backend_FontGlyphAdvance(font_id, character_code, glyph)
        End If
    Wend

    Return w
End Function

Function backend_GetTextWidthScaled(ByVal text As String, ByVal scale_x As Integer) As Integer
    Return backend_GetTextWidthScaledFont(text, BACKEND_FONT_DEFAULT, scale_x)
End Function

Function backend_GetTextWidthScaledFont(ByVal text As String, _
                                        ByVal font_id As Integer, _
                                        ByVal scale_x As Integer) As Integer
    If scale_x < 1 Then scale_x = 1
    Return backend_GetTextWidthFont(text, font_id) * scale_x
End Function

Function backend_GetTextWidthPercent( _
    ByVal text As String, ByVal percent As Integer _
) As Integer

    Return backend_GetTextWidthFontPercent( _
        text, BACKEND_FONT_DEFAULT, percent _
    )

End Function


Function backend_GetTextWidthFontPercent( _
    ByVal text As String, ByVal font_id As Integer, _
    ByVal percent As Integer _
) As Integer

    Dim As Integer text_width
    Dim As Integer glyph_advance
    Dim As Integer byte_index = 0
    Dim As Integer character_code
    Dim As UByte Ptr glyph

    If percent < BACKEND_MIN_FONT_PERCENT Then percent = BACKEND_MIN_FONT_PERCENT
    If percent > BACKEND_MAX_FONT_PERCENT Then percent = BACKEND_MAX_FONT_PERCENT

    While byte_index < Len(text)
        character_code = backend_ReadUTF8Codepoint(text, byte_index)
        glyph = backend_FontGlyph(font_id, character_code)
        If glyph <> 0 Then
            glyph_advance = backend_FontGlyphAdvance( _
                font_id, character_code, glyph _
            )
            text_width += (glyph_advance * percent + 50) \ 100
        End If
    Wend

    Return text_width

End Function

Function backend_GetTextHeight() As Integer
    If backend_HasFontPack(BACKEND_FONT_DEFAULT) <> 0 Then _
        Return backend_FontPacks(BACKEND_FONT_DEFAULT).line_height
    Return 14
End Function

Function backend_GetTextHeightPercent(ByVal percent As Integer) As Integer

    Return backend_GetTextHeightFontPercent(BACKEND_FONT_DEFAULT, percent)

End Function


Function backend_GetTextHeightFontPercent( _
    ByVal font_id As Integer, ByVal percent As Integer _
) As Integer

    Dim As Integer scaled_height
    Dim As Integer font_height
    If percent < BACKEND_MIN_FONT_PERCENT Then percent = BACKEND_MIN_FONT_PERCENT
    If percent > BACKEND_MAX_FONT_PERCENT Then percent = BACKEND_MAX_FONT_PERCENT
    /'
        The default editor font keeps its established two-pixel leading. Other
        embedded fonts use their measured glyph height as their line height.
    '/
    If font_id = BACKEND_FONT_DEFAULT Then
        font_height = backend_GetTextHeight()
    Else
        font_height = backend_GetTextHeightFont(font_id)
    End If
    scaled_height = (font_height * percent + 50) \ 100
    If scaled_height < 1 Then scaled_height = 1
    Return scaled_height
End Function

Function backend_GetTextHeightScaled(ByVal scale_y As Integer) As Integer
    Return backend_GetTextHeightScaledFont(BACKEND_FONT_DEFAULT, scale_y)
End Function

Function backend_GetTextHeightFont(ByVal font_id As Integer) As Integer
    Dim glyph As UByte Ptr

    If backend_HasFontPack(font_id) <> 0 Then _
        Return backend_FontPacks(font_id).line_height

    glyph = backend_FontGlyph(font_id, Asc("M"))

    If glyph <> 0 Then
        Return glyph[1]
    End If

    Return 14
End Function

Function backend_GetTextHeightScaledFont(ByVal font_id As Integer, _
                                         ByVal scale_y As Integer) As Integer
    If scale_y < 1 Then scale_y = 1
    Return backend_GetTextHeightFont(font_id) * scale_y
End Function

' -------------------------------------------------------------------------
' Clipping
' -------------------------------------------------------------------------

Sub backend_SetClip(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer)
    Dim screen_w As Integer
    Dim screen_h As Integer
    Dim x1 As Integer
    Dim y1 As Integer
    Dim x2 As Integer
    Dim y2 As Integer

    Dim stackIndex As Integer

    /'
        Gfxlib clipping is global state. Treat SetClip and ResetClip as a
        balanced push and pop so the GUI manager can install a parent client
        clip while a textbox, list, or graphic shape adds a narrower local
        clip for its own renderer.
    '/

    If backend_ClipDepth >= BACKEND_CLIP_STACK_CAPACITY Then
        backend_ClipOverflowDepth += 1
        Exit Sub
    End If

    If w <= 0 Or h <= 0 Then
        w = 1
        h = 1
    End If

    ScreenInfo screen_w, screen_h

    If screen_w <= 0 Or screen_h <= 0 Then
        screen_w = 1
        screen_h = 1
    End If

    x1 = x
    y1 = y
    x2 = x + w - 1
    y2 = y + h - 1

    If x1 < 0 Then x1 = 0
    If y1 < 0 Then y1 = 0
    If x2 >= screen_w Then x2 = screen_w - 1
    If y2 >= screen_h Then y2 = screen_h - 1

    If backend_ClipDepth > 0 Then
        stackIndex = backend_ClipDepth - 1

        If x1 < backend_ClipX1(stackIndex) Then _
            x1 = backend_ClipX1(stackIndex)
        If y1 < backend_ClipY1(stackIndex) Then _
            y1 = backend_ClipY1(stackIndex)
        If x2 > backend_ClipX2(stackIndex) Then _
            x2 = backend_ClipX2(stackIndex)
        If y2 > backend_ClipY2(stackIndex) Then _
            y2 = backend_ClipY2(stackIndex)
    End If

    If x2 < x1 Or y2 < y1 Then
        x1 = 0
        y1 = 0
        x2 = 0
        y2 = 0
    End If

    stackIndex = backend_ClipDepth
    backend_ClipX1(stackIndex) = x1
    backend_ClipY1(stackIndex) = y1
    backend_ClipX2(stackIndex) = x2
    backend_ClipY2(stackIndex) = y2
    backend_ClipDepth += 1
    View Screen (x1, y1)-(x2, y2)
End Sub

Sub backend_ResetClip()
    Dim stackIndex As Integer

    If backend_ClipOverflowDepth > 0 Then
        backend_ClipOverflowDepth -= 1
        Exit Sub
    End If

    If backend_ClipDepth > 0 Then backend_ClipDepth -= 1

    If backend_ClipDepth = 0 Then
        View Screen
    Else
        stackIndex = backend_ClipDepth - 1
        View Screen _
            (backend_ClipX1(stackIndex), backend_ClipY1(stackIndex))- _
            (backend_ClipX2(stackIndex), backend_ClipY2(stackIndex))
    End If
End Sub

Private Sub backend_WriteBmpByte(ByVal file_number As Integer, _
                                 ByVal value As Integer)
    Dim byte_value As UByte = value And &HFF

    Put #file_number, , byte_value
End Sub

Private Sub backend_WriteBmpU16(ByVal file_number As Integer, _
                                ByVal value As UInteger)
    backend_WriteBmpByte file_number, value And &HFF
    backend_WriteBmpByte file_number, (value Shr 8) And &HFF
End Sub

Private Sub backend_WriteBmpU32(ByVal file_number As Integer, _
                                ByVal value As UInteger)
    backend_WriteBmpByte file_number, value And &HFF
    backend_WriteBmpByte file_number, (value Shr 8) And &HFF
    backend_WriteBmpByte file_number, (value Shr 16) And &HFF
    backend_WriteBmpByte file_number, (value Shr 24) And &HFF
End Sub

Sub backend_SaveSnapshot(ByVal filename As String)
    Dim screen_w As Integer
    Dim screen_h As Integer
    Dim screen_depth As Integer
    Dim screen_bpp As Integer
    Dim screen_pitch As Integer
    Dim bytes_per_pixel As Integer
    Dim file_number As Integer
    Dim row_stride As Integer
    Dim pixel_data_size As UInteger
    Dim file_size As UInteger
    Dim x As Integer
    Dim y As Integer
    Dim screen_buffer As Any Ptr
    Dim row_ptr As UByte Ptr
    Dim pixel_ptr As UByte Ptr
    Dim blue_value As Integer
    Dim green_value As Integer
    Dim red_value As Integer

    /'
        Snapshot file format

        Test and extraction tools need deterministic BMP files from headless
        renders. The writer below emits a plain 24-bit Windows BMP:

            14 bytes : BMP file header
            40 bytes : BITMAPINFOHEADER
            rows     : bottom-up BGR pixels, padded to a 4-byte boundary

        gfxlib screens in this backend are created as 32-bit RGB surfaces.
        Reading the framebuffer directly avoids small-preview quirks in BSave.
    '/

    If Len(filename) = 0 Then Exit Sub

    ScreenInfo screen_w, screen_h, screen_depth, screen_bpp, screen_pitch

    If screen_w <= 0 Or screen_h <= 0 Then Exit Sub

    bytes_per_pixel = screen_bpp

    If bytes_per_pixel > 8 Then
        bytes_per_pixel = bytes_per_pixel \ 8
    End If

    If bytes_per_pixel <= 0 Then
        bytes_per_pixel = screen_depth \ 8
    End If

    If bytes_per_pixel < 3 Then Exit Sub

    If screen_pitch <= 0 Then
        screen_pitch = screen_w * bytes_per_pixel
    End If

    row_stride = ((screen_w * 3 + 3) \ 4) * 4
    pixel_data_size = row_stride * screen_h
    file_size = 54 + pixel_data_size

    If Dir(filename) <> "" Then
        Kill filename
    End If

    file_number = FreeFile

    If Open(filename For Binary Access Write As #file_number) <> 0 Then
        Exit Sub
    End If

    /'
        ScreenPtr addresses the current work page. After backend_Flip that
        page is the next frame, not the completed visible frame. Select the
        visible page while reading, then restore the backend's work page.
        ScreenLock synchronizes queued gfxlib3 drawing before CPU readback.
        These calls belong to the graphics-owning thread.
    '/
    If backend_DoubleBufferActive Then _
        ScreenSet backend_GfxVisiblePage, backend_GfxVisiblePage
    ScreenLock
    screen_buffer = ScreenPtr()
    If screen_buffer <> 0 Then
        backend_WriteBmpByte file_number, Asc("B")
        backend_WriteBmpByte file_number, Asc("M")
        backend_WriteBmpU32 file_number, file_size
        backend_WriteBmpU32 file_number, 0
        backend_WriteBmpU32 file_number, 54

        backend_WriteBmpU32 file_number, 40
        backend_WriteBmpU32 file_number, screen_w
        backend_WriteBmpU32 file_number, screen_h
        backend_WriteBmpU16 file_number, 1
        backend_WriteBmpU16 file_number, 24
        backend_WriteBmpU32 file_number, 0
        backend_WriteBmpU32 file_number, pixel_data_size
        backend_WriteBmpU32 file_number, 2835
        backend_WriteBmpU32 file_number, 2835
        backend_WriteBmpU32 file_number, 0
        backend_WriteBmpU32 file_number, 0

        For y = screen_h - 1 To 0 Step -1
            row_ptr = Cast(UByte Ptr, screen_buffer) + (y * screen_pitch)

            For x = 0 To screen_w - 1
                pixel_ptr = row_ptr + (x * bytes_per_pixel)
                blue_value = pixel_ptr[0]
                green_value = pixel_ptr[1]
                red_value = pixel_ptr[2]

                backend_WriteBmpByte file_number, blue_value
                backend_WriteBmpByte file_number, green_value
                backend_WriteBmpByte file_number, red_value
            Next x

            For x = (screen_w * 3) + 1 To row_stride
                backend_WriteBmpByte file_number, 0
            Next x
        Next y
    End If

    Close #file_number
    ScreenUnlock
    If backend_DoubleBufferActive Then _
        ScreenSet backend_GfxWorkPage, backend_GfxVisiblePage
End Sub

Private Function backend_ValidDisplayState(ByRef display_state As Const BackendDisplayState) As Integer
    ' At most 128 MiB for a double-buffered 32-bit restore.
    Const MAX_RESTORE_PIXELS As Integer = 16777216
    If display_state.width < 1 OrElse display_state.height < 1 Then Return 0
    If display_state.width > MAX_RESTORE_PIXELS \ display_state.height Then Return 0
    If backend_IsSupportedColorDepth(display_state.color_depth) = 0 Then Return 0
    If display_state.headless <> BACKEND_DISPLAY_ENABLED AndAlso _
       display_state.headless <> BACKEND_HEADLESS AndAlso _
       display_state.headless <> BACKEND_HEADLESS_DRAWABLE Then Return 0
    If (display_state.window_flags And Not(BACKEND_WINDOW_RESIZABLE Or BACKEND_WINDOW_FULLSCREEN)) <> 0 Then Return 0
    Return -1
End Function

Function backend_CaptureDisplay(ByRef display_state As BackendDisplayState) As Integer
    Dim As BackendDisplayState captured_state
    If ScreenPtr = 0 AndAlso backend_HeadlessActive <> BACKEND_HEADLESS Then Return 0
    captured_state.headless = backend_HeadlessActive
    captured_state.color_depth = backend_ColorDepth
    captured_state.window_flags = backend_WindowFlags
    backend_GetSize captured_state.width, captured_state.height
    If backend_ValidDisplayState(captured_state) = 0 Then Return 0
    display_state = captured_state
    Return -1
End Function

Function backend_RestoreDisplay(ByRef display_state As Const BackendDisplayState) As Integer
    Dim As BackendDisplayState previous_state
    Dim As Integer have_previous_state
    If backend_ValidDisplayState(display_state) = 0 Then Return 0

    have_previous_state = backend_CaptureDisplay(previous_state)
    backend_HeadlessActive = display_state.headless
    If backend_CreateScreen( _
        display_state.width, display_state.height, _
        display_state.window_flags, display_state.color_depth _
    ) <> 0 Then Return -1

    ' ScreenRes may have destroyed the previous screen on failure.
    If have_previous_state <> 0 Then
        backend_HeadlessActive = previous_state.headless
        backend_CreateScreen _
            previous_state.width, previous_state.height, _
            previous_state.window_flags, previous_state.color_depth
    End If
    Return 0
End Function

/'
    The native byte surface uses gfxlib's current console font. It is kept
    separate from UTF-8 text rendering because callers address CP437 cells.
'/
Sub backend_PrintByte(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByVal character_code As Integer)
    If character_code < 0 OrElse character_code > 255 Then Exit Sub
    backend_PrintBytes x, y, clr, Chr(character_code)
End Sub

Sub backend_PrintBytes(ByVal x As Integer, ByVal y As Integer, ByVal clr As ULong, ByRef bytes_text As Const String)
    If Len(bytes_text) > 65536 Then Exit Sub
    If x < -1000000 OrElse x > 1000000 OrElse y < -1000000 OrElse y > 1000000 Then Exit Sub
    Draw String (x, y), bytes_text, MapColor(clr)
End Sub

Sub backend_GetClip(ByRef x As Integer, ByRef y As Integer, ByRef w As Integer, ByRef h As Integer)
    x = 0
    y = 0
    If backend_ClipDepth = 0 Then
        backend_GetSize w, h
    Else
        Dim As Integer clip_index = backend_ClipDepth - 1
        x = backend_ClipX1(clip_index)
        y = backend_ClipY1(clip_index)
        w = backend_ClipX2(clip_index) - x + 1
        h = backend_ClipY2(clip_index) - y + 1
    End If
End Sub

' The style renderer borrows the same glyph tables and clip stack.
#include once "src/backend/backend_text_style.bi"

' end of backend_gfxlib.bas
