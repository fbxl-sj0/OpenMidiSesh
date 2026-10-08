/'
    Project: omaGUI
    File: navigation_viewport.bi
    Purpose: Declare the opt-in logical display and accessibility profile.
    Responsibilities: Keep layout coordinates independent of physical pixels.
    This file does not contain widget policy or window-system input polling.

    The GUI thread owns viewport state. Legacy games select this profile before
    initialization. Applications without that opt-in keep the native pixel path.
'/
#ifndef __OMAGUI_NAVIGATION_VIEWPORT_BI__
#define __OMAGUI_NAVIGATION_VIEWPORT_BI__
Declare Sub backend_SetDisplayOptions(ByVal fullscreen As Integer, ByVal scalePercent As Integer)
Declare Sub backend_SetTextScale(ByVal textScale As Integer)
Declare Function backend_GetTextScale() As Integer
Declare Sub backend_SetHighContrast(ByVal enabled As Integer)
Declare Function backend_PhysicalToLogicalX(ByVal x As Integer) As Integer
Declare Function backend_PhysicalToLogicalY(ByVal y As Integer) As Integer
Declare Sub backend_NavigationCreate(ByRef w As Integer, ByRef h As Integer, ByRef flags As UInteger)
Declare Sub backend_NavigationClip(ByVal x1 As Integer, ByVal y1 As Integer, ByVal x2 As Integer, ByVal y2 As Integer)
Declare Function backend_NavigationColor(ByVal clr As ULong) As ULong
Extern omagui_nav_logical_w As Integer, omagui_nav_logical_h As Integer
Extern omagui_nav_text_scale As Integer
#endif
' end of navigation_viewport.bi
