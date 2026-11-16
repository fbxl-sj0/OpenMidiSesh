/'
    Project: OpenMidiSesh
    File: display_profile.bi
    Targets: Windows/Linux editor builds and the Android display fallback.
    Module API: Private displayProfile_InitialSize and displayProfile_Poll entry points.
    Purpose: Adapt older Android runtimes to the shared logical GUI viewport.
    Responsibilities: Bounded surface sizing and density-normalized coordinates.
    This file intentionally does NOT contain: widgets, input devices or application breakpoints.
    Modern runtimes supply these metrics through omaGUI's display API. The JNI
    fallback keeps older packaged runtimes usable without changing vendor code.
    All framebuffer changes happen on the GUI thread before input or painting.
'/
#ifndef __OSE_DISPLAY_PROFILE_BI__
#define __OSE_DISPLAY_PROFILE_BI__
#if defined(__FB_ANDROID__) And defined(OMAGUI_NAVIGATION_EXTENSIONS)
Extern "C"
    Declare Function displayProfile_AndroidMetric Alias "ose_midi_call" ( _
        ByVal methodText As Const ZString Ptr, ByVal argument As Long, ByVal hasArgument As Long) As Long
End Extern
#endif

Private Sub displayProfile_InitialSize(ByRef widthValue As Integer, ByRef heightValue As Integer)
#if defined(__FB_ANDROID__) And defined(OMAGUI_NAVIGATION_EXTENSIONS)
    Dim As Integer nativeWidth = displayProfile_AndroidMetric("displayWidth", 0, 0)
    Dim As Integer nativeHeight = displayProfile_AndroidMetric("displayHeight", 0, 0)
    If nativeWidth >= 320 AndAlso nativeHeight >= 240 AndAlso _
        nativeWidth <= 8192 AndAlso nativeHeight <= 8192 AndAlso _
        CLngInt(nativeWidth) * nativeHeight <= 8388608 Then
        widthValue = nativeWidth
        heightValue = nativeHeight
    End If
#endif
End Sub

Private Sub displayProfile_Poll()
#if defined(__FB_ANDROID__) And defined(OMAGUI_NAVIGATION_EXTENSIONS)
    ' gui_UpdateAll also polls omaGUI. Do not let an older runtime's missing
    ' density result replace this fallback's logical canvas with raw pixels.
    backend_SetResponsiveDisplay 0
#endif
    backend_PollResponsiveDisplay()
#if defined(__FB_ANDROID__) And defined(OMAGUI_NAVIGATION_EXTENSIONS)
    Dim As Integer nativeWidth = 0, nativeHeight = 0
    displayProfile_InitialSize nativeWidth, nativeHeight
    If nativeWidth = 0 OrElse nativeHeight = 0 Then Exit Sub
    Dim As Integer pixelWidth, pixelHeight
    ScreenInfo pixelWidth, pixelHeight
    If pixelWidth <> nativeWidth OrElse pixelHeight <> nativeHeight Then
        If backend_SetWindowMode(nativeWidth, nativeHeight, BACKEND_WINDOW_RESIZABLE) = 0 Then Exit Sub
    End If
    Dim As Integer dpiValue = displayProfile_AndroidMetric("displayDpi", 0, 0)
    If dpiValue < 72 OrElse dpiValue > 1920 Then dpiValue = 160
    omagui_nav_logical_w = Int(nativeWidth * 160.0 / dpiValue)
    omagui_nav_logical_h = Int(nativeHeight * 160.0 / dpiValue)
    If omagui_nav_logical_w < 320 Then omagui_nav_logical_w = 320
    If omagui_nav_logical_h < 240 Then omagui_nav_logical_h = 240
    backend_NavigationClip 0, 0, omagui_nav_logical_w - 1, omagui_nav_logical_h - 1
#endif
End Sub
#endif
/' end of display_profile.bi '/
