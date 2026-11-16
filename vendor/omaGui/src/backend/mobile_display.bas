/'
    Project: omaGUI
    File: mobile_display.bas
    Purpose: Adapt the logical viewport to usable window geometry and density.
    Responsibilities: Bounded mode changes, text-input regions and IME requests.
    This file does not own widgets, application breakpoints or native callbacks.

    Call the display poll on the GUI thread before input and drawing locks.
    Browser metrics are CSS pixels, already normalized for device density.
    A measured overlay keyboard reduces layout space, not the framebuffer or
    coordinate scale. Unknown panel bounds retain focused-field panning.
    Android reports native pixels and uses 160 DPI as its layout baseline.
    Linux handhelds use that mobile baseline too. Compositors may already
    scale the surface, so their reduced DPI must not shrink it below 1:1.
    These control numbers also compile with older SDK headers; unsupported
    runtimes return zero geometry, retaining the existing drawable fallback.
'/
#lang "fb"
#include once "src/backend/mobile_display.bi"
#ifdef __FB_JS__
Extern "C"
    Declare Function display_emscripten_run_script_int _
        Alias "emscripten_run_script_int" _
        (ByVal script_text As Const ZString Ptr) As Integer
End Extern
' Keep the browser surface in CSS pixels. The packed result fits in a signed
' 32-bit integer because both dimensions are bounded at 8192.
Private Const BACKEND_BROWSER_VIEWPORT_SCRIPT As String = _
    "(()=>{const v=window.visualViewport;const w=Math.round(v?v.width:window.innerWidth);" & _
    "const h=Math.round(v?v.height:window.innerHeight);" & _
    "if(!Number.isFinite(w)||!Number.isFinite(h)||w<2||h<2||w>8192||h>8192||w*h>8388608)return 0;" & _
    "return w*16384+h})()"
#endif
Private Dim Shared backend_ResponsiveDisplay As Integer
Private Dim Shared As Integer backend_PendingDisplayWidth, backend_PendingDisplayHeight
Private Dim Shared backend_PendingDisplayAt As Double
Private Dim Shared backend_DisplayResizeFailed As Integer
' GUI-thread request state protects layout while native visibility catches up.
Private Dim Shared backend_KeyboardShowPending As Integer

Sub backend_SetResponsiveDisplay(ByVal enabled As Integer)
    backend_ResponsiveDisplay = IIf(enabled <> 0, -1, 0)
    backend_LayoutHeight = 0
    backend_PendingDisplayWidth = 0: backend_PendingDisplayHeight = 0
    backend_DisplayResizeFailed = 0
    backend_KeyboardShowPending = 0
End Sub

Function backend_PollResponsiveDisplay() As Integer
    If backend_ResponsiveDisplay = 0 OrElse backend_HeadlessActive <> 0 Then Return 0
    Dim As Integer physical_w, physical_h, dpi_value, rotation_value
    Dim As Integer current_w, current_h
    ScreenControl BACKEND_GET_WINDOW_METRICS, physical_w, physical_h, dpi_value, rotation_value
#ifdef __FB_JS__
    /'
        Emscripten's window metrics follow the current framebuffer. Read the
        visual viewport directly so the first frame and later browser resizes
        can move the framebuffer to the CSS viewport size.
    '/
    Dim As Integer packed_viewport = display_emscripten_run_script_int( _
        StrPtr(BACKEND_BROWSER_VIEWPORT_SCRIPT) _
    )
    If packed_viewport > 0 Then
        physical_w = packed_viewport \ 16384
        physical_h = packed_viewport And 16383
    End If
#endif
    ScreenInfo current_w, current_h
    If physical_w < 2 OrElse physical_h < 2 Then physical_w = current_w: physical_h = current_h
    ' Two 32-bit pages at this bound occupy at most 64 MiB. Do not accept an
    ' unbounded allocation from a broken browser geometry or native callback.
    If physical_w < 2 OrElse physical_h < 2 OrElse physical_w > 8192 OrElse physical_h > 8192 Then Return 0
    If CLngInt(physical_w) * physical_h > 8388608 Then Return 0
#if defined(__FB_JS__) Or defined(__FB_ANDROID__)
    If physical_w <> current_w OrElse physical_h <> current_h Then
        Dim current_time As Double = Timer
        If backend_PendingDisplayWidth <> physical_w OrElse backend_PendingDisplayHeight <> physical_h Then
            backend_PendingDisplayWidth = physical_w: backend_PendingDisplayHeight = physical_h
            backend_PendingDisplayAt = current_time
            backend_DisplayResizeFailed = 0
            Return 0
        End If
        Dim elapsed As Double = current_time - backend_PendingDisplayAt
        If elapsed < 0 Then backend_PendingDisplayAt = current_time: Return 0
        ' Coalesce IME animation and rotation callbacks instead of allocating
        ' two new graphics pages for every intermediate animation rectangle.
        If elapsed < IIf(backend_DisplayResizeFailed <> 0,1.0,0.12) Then Return 0
        If backend_SetWindowMode(physical_w, physical_h, BACKEND_WINDOW_FIXED) = 0 Then
            backend_PendingDisplayAt = current_time
            backend_DisplayResizeFailed = -1
            Return 0
        End If
        backend_DisplayResizeFailed = 0
    End If
#else
#if defined(__FB_LINUX__)
    ' Wayland surfaces follow compositor configure events. Recreating a
    ' resizable X11 screen after RandR rotation can restore the prior orientation
    ' on Maemo Leste, so poll only fixed handheld windows here.
    If backend_IsHandheld() <> 0 AndAlso _
       (backend_WindowFlags And BACKEND_WINDOW_RESIZABLE) = 0 Then
        Dim current_driver As String
        ScreenControl FB.GET_DRIVER_NAME, current_driver
        If LCase(current_driver) <> "wayland" Then
        Dim As Integer desktop_w, desktop_h
        ScreenControl FB.GET_DESKTOP_SIZE, desktop_w, desktop_h
        If desktop_w >= 2 AndAlso desktop_h >= 2 AndAlso _
           desktop_w <= 8192 AndAlso desktop_h <= 8192 AndAlso _
           CLngInt(desktop_w) * desktop_h <= 8388608 AndAlso _
           (desktop_w <> current_w OrElse desktop_h <> current_h) Then
            Dim current_time As Double = Timer
            If backend_PendingDisplayWidth <> desktop_w OrElse _
               backend_PendingDisplayHeight <> desktop_h Then
                backend_PendingDisplayWidth = desktop_w
                backend_PendingDisplayHeight = desktop_h
                backend_PendingDisplayAt = current_time
                backend_DisplayResizeFailed = 0
                Return 0
            End If
            Dim elapsed As Double = current_time - backend_PendingDisplayAt
            If elapsed < 0 Then
                backend_PendingDisplayAt = current_time
                Return 0
            End If
            If elapsed < IIf(backend_DisplayResizeFailed <> 0, 1.0, 0.12) Then Return 0
            Dim resizeFlags As UInteger = BACKEND_WINDOW_FULLSCREEN
            If (backend_WindowFlags And BACKEND_WINDOW_FILL) <> 0 Then _
                resizeFlags = BACKEND_WINDOW_FILL Or BACKEND_WINDOW_RESIZABLE
            If backend_SetWindowMode(desktop_w, desktop_h, resizeFlags) = 0 Then
                backend_PendingDisplayAt = current_time
                backend_DisplayResizeFailed = -1
                Return 0
            End If
            backend_PendingDisplayWidth = 0
            backend_PendingDisplayHeight = 0
            backend_DisplayResizeFailed = 0
            current_w = desktop_w
            current_h = desktop_h
            physical_w = desktop_w
            physical_h = desktop_h
        End If
        End If
    End If
#else
    ' Native resizable drivers own their framebuffer changes.
    physical_w = current_w: physical_h = current_h
#endif
#endif
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
    Dim scale_value As Double = 1.0
#ifdef __FB_ANDROID__
    If dpi_value >= 72 AndAlso dpi_value <= 1920 Then scale_value = dpi_value / 160.0
#elseif defined(__FB_LINUX__) And Not defined(__FB_JS__)
    If dpi_value >= 72 AndAlso dpi_value <= 1920 Then
        If backend_DeviceIsHandheld() <> 0 Then
            scale_value = dpi_value / 160.0
            If scale_value < 1.0 Then scale_value = 1.0
        Else
            scale_value = dpi_value / 96.0
        End If
    End If
#elseif Not defined(__FB_JS__)
    If dpi_value >= 72 AndAlso dpi_value <= 1920 Then scale_value = dpi_value / 96.0
#endif
    Dim logical_w As Integer = Int(physical_w / scale_value)
    Dim logical_h As Integer = Int(physical_h / scale_value)
    If logical_w < 2 Then logical_w = 2
    If logical_h < 2 Then logical_h = 2
    Dim changed As Integer = CLng(logical_w <> omagui_nav_logical_w OrElse logical_h <> omagui_nav_logical_h)
    omagui_nav_logical_w = logical_w: omagui_nav_logical_h = logical_h
    Dim layout_height As Integer = 0
    Dim observed_top As Integer = backend_SoftKeyboardOcclusionTop()
    If observed_top >= 0 AndAlso observed_top < logical_h Then
        ' All layout clients share the same usable height. Keep the complete
        ' canvas for drawing/input transforms so reserving space cannot scale
        ' the conversation or move native text-input regions a second time.
        layout_height = observed_top
        If layout_height < 2 Then layout_height = 2
    End If
    If backend_LayoutHeight <> layout_height Then changed = -1
    backend_LayoutHeight = layout_height
    ' Refresh pointer scaling and the unclipped drawing transform together.
    backend_NavigationClip 0, 0, logical_w - 1, logical_h - 1
    Return changed
#else
    Return CLng(physical_w <> current_w OrElse physical_h <> current_h)
#endif
End Function

Function backend_DeviceIsHandheld() As Integer
#if defined(__FB_LINUX__) And Not defined(__FB_JS__)
    Dim As Integer device_class = 0
    ScreenControl BACKEND_GET_DEVICE_CLASS, device_class
    Return IIf(device_class = BACKEND_DEVICE_CLASS_HANDHELD, -1, 0)
#else
    Return 0
#endif
End Function

Sub backend_SetSoftKeyboard(ByVal visible As Integer)
    If backend_HeadlessActive <> BACKEND_DISPLAY_ENABLED Then Exit Sub
    Dim requested As Integer = IIf(visible <> 0, -1, 0)
    backend_KeyboardShowPending = requested
    ScreenControl BACKEND_SET_SOFT_KEYBOARD, requested
End Sub

Function backend_SoftKeyboardPending() As Integer
    If backend_HeadlessActive <> BACKEND_DISPLAY_ENABLED Then Return 0
    Return backend_KeyboardShowPending
End Function

Function backend_SoftKeyboardActive() As Integer
    If backend_HeadlessActive <> BACKEND_DISPLAY_ENABLED Then Return 0
    Dim As Integer visible = 0, available = 0
    ScreenControl BACKEND_GET_SOFT_KEYBOARD, visible, available
    If available = 0 OrElse visible <> 0 Then backend_KeyboardShowPending = 0
    ' Some browsers know that their editor has focus, but cannot prove IME
    ' occlusion. Preserve that focus too, until the application dismisses it.
    Return IIf(available <> 0 AndAlso visible <> 0, -1, 0)
End Function

Function backend_SoftKeyboardMayOverlap() As Integer
    If backend_HeadlessActive <> BACKEND_DISPLAY_ENABLED Then Return 0
    Dim As Integer visible = 0, available = 0
    ScreenControl BACKEND_GET_SOFT_KEYBOARD, visible, available
    If available = 0 OrElse visible = 0 Then Return 0
    If visible <> -2 Then Return -1

    ' A focused Wayland text input can have unknown visibility. On a known
    ' handheld, leave room for the keyboard even if the shell cannot report it.
    ' Do not move a desktop form merely because visibility is unknown.
    Dim device_class As Integer = 0
    ScreenControl BACKEND_GET_DEVICE_CLASS, device_class
    Return IIf(device_class = BACKEND_DEVICE_CLASS_HANDHELD, -1, 0)
End Function

Private Function backend_NormalizeKeyboardOcclusionTop( _
    ByVal visible As Integer, ByVal available As Integer, _
    ByVal top_value As Integer, ByVal height As Integer, _
    ByVal physical_h As Integer, ByVal logical_h As Integer _
) As Integer
    If available = 0 OrElse visible = 0 OrElse height < 0 OrElse top_value < 0 Then Return -1
    If physical_h <= 0 OrElse logical_h <= 0 OrElse top_value > physical_h Then Return -1
    ' An empty overlap at the drawable end confirms a reserved viewport only
    ' with known visibility. Legacy zero outputs and unknown v3 visibility
    ' still require the ordinary conservative fallback.
    If height = 0 AndAlso (visible <> -1 OrElse top_value <> physical_h) Then Return -1
    ' Native IME bounds use drawable pixels; widgets use the logical viewport.
    Return CInt((CLngInt(top_value) * logical_h) \ physical_h)
End Function

Function backend_SoftKeyboardOcclusionTop() As Integer
    If backend_HeadlessActive <> BACKEND_DISPLAY_ENABLED Then Return -1
    Dim As Integer visible = 0, available = 0, top_value = 0, height = 0
    ScreenControl BACKEND_GET_SOFT_KEYBOARD, visible, available, top_value, height
    If available = 0 OrElse visible = 0 OrElse height < 0 OrElse top_value < 0 Then Return -1
    If height = 0 AndAlso visible <> -1 Then Return -1
    Dim As Integer logical_w, logical_h, physical_w, physical_h
    backend_GetCanvasSize logical_w, logical_h
    ScreenInfo physical_w, physical_h
    Return backend_NormalizeKeyboardOcclusionTop(visible, available, top_value, height, physical_h, logical_h)
End Function

Sub backend_ClearTextInputRegions()
#if defined(__FB_JS__) Or defined(__FB_LINUX__)
    ScreenControl BACKEND_CLEAR_SOFT_KEYBOARD_REGIONS
#endif
End Sub

Private Function backend_MapTextInputAxis( _
    ByVal position As Integer, ByVal extent As Integer, _
    ByVal logical_size As Integer, ByVal canvas_size As Integer, _
    ByRef canvas_position As Integer, ByRef canvas_extent As Integer _
) As Integer
    canvas_position = 0
    canvas_extent = 0
    ' Use the navigation viewport's 32767-unit limit before multiplying.
    If logical_size < 2 OrElse logical_size > 32767 OrElse _
       canvas_size < 2 OrElse canvas_size > 32767 Then Return 0
    If position < 0 OrElse position >= logical_size OrElse extent <= 0 Then Return 0
    If extent > logical_size - position Then Return 0

    canvas_position = (CLngInt(position) * canvas_size) \ logical_size
    Dim canvas_end As Integer = _
        ((CLngInt(position) + extent) * canvas_size + logical_size - 1) \ logical_size
    canvas_extent = canvas_end - canvas_position
    Return -1
End Function


Sub backend_TextInputRegion(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer)
#if defined(__FB_JS__) Or defined(__FB_LINUX__)
    Dim As Integer logical_w, logical_h, physical_w, physical_h
    backend_GetCanvasSize logical_w, logical_h
    ScreenInfo physical_w, physical_h
    If logical_w < 2 OrElse logical_h < 2 OrElse physical_w < 2 OrElse physical_h < 2 Then Exit Sub
    If x < 0 OrElse y < 0 OrElse w <= 0 OrElse h <= 0 Then Exit Sub
    If CLngInt(x) + w > logical_w OrElse CLngInt(y) + h > logical_h Then Exit Sub
    Dim As Integer px, py, pw, ph
    If backend_MapTextInputAxis(x, w, logical_w, physical_w, px, pw) = 0 Then Exit Sub
    If backend_MapTextInputAxis(y, h, logical_h, physical_h, py, ph) = 0 Then Exit Sub
    ScreenControl BACKEND_SET_SOFT_KEYBOARD_REGION, px, py, pw, ph
#endif
End Sub

Function backend_MaximizeWindow() As Integer
#if defined(__FB_WIN32__) And Not defined(OMAGUI_PORTABLE_ONLY)
    Dim native_handle As Integer
    ScreenControl FB.GET_WINDOW_HANDLE, native_handle
    If native_handle = 0 Then Return 0
    Const maximize_command As Long = 3 ' SW_MAXIMIZE respects the desktop work area.
    omaGUI_NativeWindows.ShowWindow CPtr(Any Ptr, native_handle), maximize_command
    Return -1
#else
    Return 0
#endif
End Function
' The editor and mobile APIs share the same platform region store.
Sub backend_ClearSoftKeyboardRegions()
    backend_ClearTextInputRegions()
End Sub

Sub backend_SetSoftKeyboardRegion( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal widthValue As Integer, ByVal heightValue As Integer _
)
    backend_TextInputRegion x, y, widthValue, heightValue
End Sub

Function backend_DeviceClass() As Integer
#if defined(__FB_LINUX__)
    Dim As Integer device_class = BACKEND_DEVICE_CLASS_UNKNOWN
    ScreenControl BACKEND_GET_DEVICE_CLASS, device_class
    Return device_class
#else
    Return BACKEND_DEVICE_CLASS_UNKNOWN
#endif
End Function


' end of mobile_display.bas
