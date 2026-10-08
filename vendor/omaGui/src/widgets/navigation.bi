/'
    Project: omaGUI
    File: navigation.bi
    Purpose: Declare opt-in scope and directional navigation.
    Responsibilities: Preserve controller-friendly focus and explicit neighbor APIs.
    This file does not contain application commands or a second event queue.

    The navigation profile is opt-in through OMAGUI_NAVIGATION_EXTENSIONS.
    All state belongs to the GUI thread, like the core registry and input frame.
'/

#ifndef __OMAGUI_NAVIGATION_BI__
#define __OMAGUI_NAVIGATION_BI__
Declare Sub listbox_NavigationCancelInput(ByVal w As Widget Ptr)
Declare Sub gui_NavigationReset()
Declare Sub gui_NavigationAttach(ByVal w As Widget Ptr)
Declare Sub gui_NavigationPrepare()
Declare Sub gui_NavigationDispatch()
Declare Sub gui_Shutdown()
Declare Sub gui_SetActiveScope(ByVal root As Widget Ptr)
Declare Function gui_GetActiveScope() As Widget Ptr
Declare Function gui_WidgetIsInActiveScope(ByVal w As Widget Ptr) As Integer
Declare Function gui_BeginInputScope(ByVal nm As String, ByVal x As Integer, _
    ByVal y As Integer, ByVal w As Integer, ByVal h As Integer) As Widget Ptr
Declare Sub gui_EndInputScopeBuild()
Declare Sub gui_SetFocusable(ByVal w As Widget Ptr, ByVal focusOrder As Integer)
Declare Function gui_IsFocused(ByVal w As Widget Ptr) As Integer
Declare Function gui_ShouldShowFocus(ByVal w As Widget Ptr) As Integer
Declare Function gui_WidgetHasNavigation(ByVal w As Widget Ptr) As Integer
Declare Function gui_FocusFirst() As Integer
Declare Function gui_FocusNext(ByVal direction As Integer = 1) As Integer
Declare Sub gui_SetDirectionalFocus(ByVal enabled As Integer)
Declare Sub gui_SetFocusNeighbor(ByVal w As Widget Ptr, ByVal action As Integer, ByVal neighbor As Widget Ptr)
Declare Sub gui_SetDefaultButton(ByVal w As Widget Ptr)
Declare Sub gui_SetCancelButton(ByVal w As Widget Ptr)
Declare Function gui_ActivateWidget(ByVal w As Widget Ptr) As Integer
Declare Function gui_WidgetHasPointer(ByVal w As Widget Ptr) As Integer
Declare Function gui_GetPointerCapture() As Widget Ptr
Declare Sub button_SetKeyboardFocusOrder(ByVal w As Widget Ptr, ByVal focusOrder As Integer)
Declare Sub button_SetKeyboardSelected(ByVal w As Widget Ptr, ByVal selected As Integer)
Declare Sub button_SetKeyboardShortcut(ByVal w As Widget Ptr, ByVal shortcutText As String)
Declare Sub gui_SetPreferredSize(ByVal w As Widget Ptr, ByVal preferredWidth As Integer, ByVal preferredHeight As Integer)
Declare Sub gui_SetMinimumSize(ByVal w As Widget Ptr, ByVal minimumWidth As Integer, ByVal minimumHeight As Integer)
Declare Sub gui_SetLayoutWeight(ByVal w As Widget Ptr, ByVal weight As Integer)
Declare Sub gui_SetGridCell(ByVal w As Widget Ptr, ByVal row As Integer, ByVal column As Integer, ByVal rowSpan As Integer = 1, ByVal columnSpan As Integer = 1)
#endif
' end of navigation.bi
