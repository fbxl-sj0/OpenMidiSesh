/'
    Project: omaGUI
    File: control_keyevents.bi
    Purpose: Deliver portable control Down/Up notifications from one input frame.
    Responsibilities: Preserve raw key identity and validate callback ownership.
    This file intentionally does NOT choose virtual keys or implement widget actions.
    Private implementation include. All calls and borrowed handler fields belong
    to the GUI thread. Each widget family supplies its own reentry depth.
'/
#ifndef __CONTROL_KEYEVENTS_BI__
#define __CONTROL_KEYEVENTS_BI__

Private Function control_KeyTargetIsCurrent( _
    ByVal w As Widget Ptr, ByVal data_value As Any Ptr, ByVal registry_id As ULongInt, _
    ByVal frame_serial As ULongInt _
) As Integer
    If input_FrameSerial() <> frame_serial Then Return 0
    If gui_IsWidgetRegistered(w) = 0 Then Return 0
    If w->registry_id <> registry_id OrElse w->data <> data_value Then Return 0
    gui_SynchronizeLayout
    Return gui_GetFocus() = w AndAlso w->evis <> 0 AndAlso w->een <> 0
End Function

Private Function control_KeyNotifications( _
    ByVal w As Widget Ptr, ByVal data_value As Any Ptr, ByRef handler As Any Ptr, _
    ByVal release_events As Integer, ByRef callback_depth As Integer _
) As Integer
    If callback_depth <> 0 Then Return 0
    If handler = 0 Then Return -1
    Dim As ULongInt registry_id = w->registry_id
    Dim As ULongInt frame_serial = input_FrameSerial()
    Dim As Long event_count = input_KeyEventCount()
    For event_index As Long = 0 To event_count - 1
        Dim As InputKeyEvent ordered_event
        If input_ReadKeyEvent(event_index, ordered_event) = 0 Then Continue For
        If release_events Then
            If ordered_event.event_kind <> INPUT_KEY_EVENT_RELEASE Then Continue For
        Else
            If ordered_event.event_kind <> INPUT_KEY_EVENT_PRESS AndAlso _
                ordered_event.event_kind <> INPUT_KEY_EVENT_REPEAT Then Continue For
        End If
        If handler = 0 Then Exit For
        Dim As Integer scan_code = ordered_event.scan_code, modifiers = ordered_event.modifiers
        callback_depth += 1
        Cast(Sub(ByVal As Widget Ptr, ByRef As Integer, ByRef As Integer), handler)(w, scan_code, modifiers)
        callback_depth -= 1
        ' The handler field is borrowed from widget data. Do not read it again
        ' until registration, allocation identity and the frame still match.
        If control_KeyTargetIsCurrent(w, data_value, registry_id, frame_serial) = 0 Then Return 0
        If release_events = 0 Then
            If input_SetKeyEventMapping(ordered_event.scan_code, scan_code) = 0 Then Return 0
        End If
    Next event_index
    Return -1
End Function

Private Sub control_UpdateWithKeyNotifications( _
    ByVal w As Widget Ptr, ByVal data_value As Any Ptr, _
    ByRef down_handler As Any Ptr, ByRef up_handler As Any Ptr, _
    ByRef callback_depth As Integer, ByVal update_body As Sub(ByVal As Widget Ptr) _
)
    ' The depth belongs to the widget family, outside its allocation. A handler
    ' can withdraw itself or destroy the owner before recursively updating GUI.
    If callback_depth <> 0 Then Exit Sub
    If (down_handler = 0 AndAlso up_handler = 0) OrElse gui_GetFocus() <> w Then
        update_body(w)
        Exit Sub
    End If
    Dim As ULongInt registry_id = w->registry_id
    Dim As ULongInt frame_serial = input_FrameSerial()
    If control_KeyTargetIsCurrent(w, data_value, registry_id, frame_serial) = 0 Then Exit Sub
    If control_KeyNotifications(w, data_value, down_handler, 0, callback_depth) = 0 Then Exit Sub
    update_body(w)
    ' Both handler references borrow fields in data_value. The body can call
    ' application code, so validate ownership before reading the Up field.
    If control_KeyTargetIsCurrent(w, data_value, registry_id, frame_serial) = 0 Then Exit Sub
    control_KeyNotifications w, data_value, up_handler, -1, callback_depth
End Sub

#endif
/' end of control_keyevents.bi '/
