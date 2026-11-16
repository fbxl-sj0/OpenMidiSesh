/'
    Project: omaGUI
    File: mobile_display.bi
    Purpose: Declare responsive display and software-keyboard backend operations.
    Responsibilities: Keep platform controls behind the GUI backend boundary.
    This file does not contain widgets or application layout policy.
'/
#ifndef __OMAGUI_MOBILE_DISPLAY_BI__
#define __OMAGUI_MOBILE_DISPLAY_BI__
' Numeric ScreenControl IDs keep these extensions available with older fbgfx headers.
Const BACKEND_DEVICE_CLASS_UNKNOWN As Integer = 0
Const BACKEND_DEVICE_CLASS_DESKTOP As Integer = 1
Const BACKEND_DEVICE_CLASS_HANDHELD As Integer = 2
Declare Function backend_DeviceClass() As Integer
Declare Sub backend_SetResponsiveDisplay(ByVal enabled As Integer)
Declare Function backend_PollResponsiveDisplay() As Integer
Declare Function backend_DeviceIsHandheld() As Integer
Declare Sub backend_SetSoftKeyboard(ByVal visible As Integer)
' Pending expresses an unacknowledged show request, not observed visibility.
Declare Function backend_SoftKeyboardPending() As Integer
Declare Function backend_SoftKeyboardActive() As Integer
Declare Function backend_SoftKeyboardMayOverlap() As Integer
Declare Function backend_SoftKeyboardOcclusionTop() As Integer
Declare Sub backend_ClearTextInputRegions()
Declare Sub backend_TextInputRegion(ByVal x As Integer, ByVal y As Integer, ByVal w As Integer, ByVal h As Integer)
Declare Function backend_MaximizeWindow() As Integer
Declare Sub backend_ClearSoftKeyboardRegions()
Declare Sub backend_SetSoftKeyboardRegion(ByVal x As Integer, ByVal y As Integer, ByVal widthValue As Integer, ByVal heightValue As Integer)
#endif
' end of mobile_display.bi
