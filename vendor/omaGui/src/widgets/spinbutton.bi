/'
    Project: omaGUI
    ---------------

    File: spinbutton.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for spinbutton.

    Purpose:

        Declare a bounded horizontal or vertical spin-button widget.

    Responsibilities:

        - retain a checked integer range, value, increment, and wrap policy
        - expose pointer, keyboard, and programmatic value changes
        - invoke an optional change callback after user activation
        - opt into directional step notifications and held-input repetition

    This file intentionally does NOT contain:

        - spin-button rendering implementation
        - an attached text editor
        - application-specific numeric formatting
'/

#ifndef __SPINBUTTON_BI__
#define __SPINBUTTON_BI__

#include once "src/widgets/widgets.bi"

Const SPINBUTTON_VERTICAL As Integer = 0
Const SPINBUTTON_HORIZONTAL As Integer = 1

Type SpinButtonData
    As Integer minimum_value
    As Integer maximum_value
    As Integer current_value
    As Integer increment_value
    As Integer orientation
    As Integer wrap_enabled
    As Integer pointer_latch
    As Integer pressed_part
    As ULongInt activation_count
    As Any Ptr change_handler
    As Any Ptr step_handler
    As Integer activate_on_press, repeat_direction, automatic_repeat
    As Long repeat_interval_ms
    As Double repeat_elapsed_ms, repeat_clock
    As Integer repeat_clock_initialized
End Type

Declare Function spinbutton_Create( _
    ByVal nm As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal minimumValue As Integer, _
    ByVal maximumValue As Integer, _
    ByVal initialValue As Integer, _
    ByVal orientation As Integer = SPINBUTTON_VERTICAL, _
    ByVal changeHandler As Any Ptr = 0 _
) As Widget Ptr
Declare Sub spinbutton_Render(ByVal w As Widget Ptr)
Declare Sub spinbutton_Update(ByVal w As Widget Ptr)
Declare Sub spinbutton_Activate(ByVal w As Widget Ptr)
Declare Sub spinbutton_Destroy(ByVal w As Widget Ptr)
Declare Function spinbutton_GetValue(ByVal w As Widget Ptr) As Integer
Declare Function spinbutton_SetValue( _
    ByVal w As Widget Ptr, ByVal newValue As Integer _
) As Integer
Declare Function spinbutton_SetRange( _
    ByVal w As Widget Ptr, _
    ByVal minimumValue As Integer, ByVal maximumValue As Integer _
) As Integer
Declare Function spinbutton_SetIncrement( _
    ByVal w As Widget Ptr, ByVal incrementValue As Integer _
) As Integer
Declare Sub spinbutton_SetWrap( _
    ByVal w As Widget Ptr, ByVal wrapEnabled As Integer _
)
Declare Function spinbutton_SetOrientation( _
    ByVal w As Widget Ptr, ByVal orientation As Integer _
) As Integer
' Step handlers receive +1/-1, including wrapping and unchanged singleton ranges.
' Installing one replaces the legacy value-change notification, not widget ownership.
Declare Function spinbutton_SetStepHandler( _
    ByVal w As Widget Ptr, ByVal stepHandler As Any Ptr _
) As Integer
Declare Function spinbutton_Step( _
    ByVal w As Widget Ptr, ByVal directionValue As Integer _
) As Integer
' Opt into press activation and bounded held-button/key repetition. Zero stops repeats.
Declare Function spinbutton_SetRepeat( _
    ByVal w As Widget Ptr, ByVal intervalMs As Long _
) As Integer
Declare Sub spinbutton_SetAutomaticRepeat(ByVal w As Widget Ptr, ByVal enabledState As Integer)
Declare Function spinbutton_AdvanceRepeat( _
    ByVal w As Widget Ptr, ByVal elapsedMs As Double _
) As Integer

#endif

/' end of spinbutton.bi '/
