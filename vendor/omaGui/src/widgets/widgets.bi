/'
    Project: omaGUI
    ---------------
    File: widgets.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for widgets.

    Purpose:

        Central widget registry and base structure definitions.

    Responsibilities:

        - define the base Widget structure
        - declare the global GUI manager API
        - define widget lifecycle callbacks
        - expose anchor constraints for reactive window layouts
        - expose the widget which owned the latest pointer update
        - expose portable access-key caption parsing
        - render access-key underlines with the active classic palette
        - route noninteractive access keys to safe focus targets
        - let container widgets suspend descendant input without hiding chrome

    This file intentionally does NOT contain:

        - individual widget implementation logic
        - graphics backend code
'/

#ifndef __WIDGETS_BI__
#define __WIDGETS_BI__

Const GUI_MODAL_ROOT_MAXIMUM_DEPTH As Integer = 64

#include "src/backend/backend.bi"
#include "src/backend/input.bi"

' -------------------------------------------------------------------------
' Type Definitions
' -------------------------------------------------------------------------

Type Widget_Struct_ ' fblint: disable-line FBL910 REASON: This record is process-local state, never a raw serialized or external ABI layout.
    As String name
    As Integer x, y, w, h
    As Integer ax, ay
    As Integer visible
    As Integer enabled
    As Integer evis
    As Integer een
    As Integer updated_this_frame
    As Integer accepts_focus
    As Integer captures_tab
    As Integer captures_return
    As Integer captures_escape
    As Integer has_focus
    As Integer tab_order_known
    As Integer tab_order
    As Integer mnemonic_key
    ' Weak registry reference. Removal clears every inbound target before the
    ' Widget allocation is released.
    As Widget_Struct_ Ptr mnemonic_target
    As Integer is_default_action
    As Integer is_cancel_action
    As Integer is_window
    As Integer pointer_global
    ' A global popup may decline a hit inside its owner's region.
    As Function(ByVal As Widget_Struct_ Ptr, ByVal As Integer, ByVal As Integer) As Integer pointer_test
    /'
        A process-wide keyboard widget is offered the active form's keyboard
        frame even while another child owns focus. The manager chooses one
        eligible widget in the focused or foreground window, so independent
        forms cannot dispatch the same accelerator twice.
    '/
    As Integer keyboard_global
    As Integer clip_children
    ' Popup descendants may extend beyond their owner's client rectangle.
    As Integer escape_parent_clip
    ' A collapsed container remains interactive while its child tree is not.
    ' Effective enabled state inherits this flag during layout resolution.
    As Integer suspend_children
    As Integer child_clip_x, child_clip_y
    As Integer child_clip_right, child_clip_bottom
    As Any Ptr data
    ' Borrowed palette. Its owner keeps it alive through widget destruction.
    As GUI_Theme Ptr appearance
    ' Copied overrides own their palette and take precedence at this node.
    As Integer theme_override_enabled
    As GUI_Theme theme_override

    /'
        The manager assigns a new identity whenever a widget enters the
        registry. Update callbacks may remove their own tree and an allocator
        may immediately reuse the same address, so pointer equality alone
        cannot prove that a callback returned to the same live widget.
    '/
    As ULongInt registry_id

    /'
        Reactive layout is opt-in. The saved rectangle and container size are
        the stable reference used when a window or parent changes dimensions.
        Widgets without layout_initialized retain the original absolute or
        parent-relative behavior.
    '/
    As UInteger anchor_flags
    As Integer layout_initialized
    As Integer layout_base_x, layout_base_y
    As Integer layout_base_w, layout_base_h
    As Integer layout_container_w, layout_container_h
    As UInteger layout_generation

    ' Callbacks
    As Sub(ByVal As Widget_Struct_ Ptr) render
    As Sub(ByVal As Widget_Struct_ Ptr) update
    As Sub(ByVal As Widget_Struct_ Ptr) activate
    As Sub(ByVal As Widget_Struct_ Ptr) destroy

    ' Called on the GUI thread instead of update while hidden, disabled, or
    ' outside the modal tree. Reset private input state only; do not dispatch
    ' application callbacks or change the registry from this notification.
    As Sub(ByVal As Widget_Struct_ Ptr) cancel_input

    As Widget_Struct_ Ptr parent
    As Widget_Struct_ Ptr next_widget
    ' Opt-out applies only to Tab traversal; pointer and explicit focus remain
    ' available. Zero preserves keyboard traversal for existing constructors.
    As Integer skip_tab_stop
    ' Optional GUI-thread observation for retained drawing. The key must cover
    ' every visual dependency, including application-owned callback state.
    ' No observation preserves conservative repainting of the complete scene.
    As Function(ByVal As Widget_Struct_ Ptr) As String render_observation
    ' An optional exact matcher can compare borrowed retained bytes without
    ' allocating the observation again. Bind it through the setter below;
    ' replacing the observer automatically disables its old matcher.
    As Function(ByVal As Widget_Struct_ Ptr, ByRef As Const String, _
        ByVal As Integer) As Integer render_observation_match
    As Function(ByVal As Widget_Struct_ Ptr) As String render_match_owner
    ' Optional GUI-thread footprint for painters with known decoration bounds.
    ' Return nonzero only when the drawable-clipped rectangle contains every
    ' painted pixel, including owned popups. Bind through the setter so a
    ' replacement painter cannot inherit that contract. Zero keeps full redraw.
    As Function(ByVal As Widget_Struct_ Ptr, ByRef As Integer, ByRef As Integer, _
        ByRef As Integer, ByRef As Integer) As Integer render_bounds
    As Sub(ByVal As Widget_Struct_ Ptr) render_bounds_owner
    ' A top-level window may report a rectangle it paints completely opaque.
    ' This read-only GUI-thread contract can omit covered earlier painters.
    ' It describes filled pixels, not the bounding box of a popup branch.
    As Function(ByVal As Widget_Struct_ Ptr, ByRef As Integer, ByRef As Integer, _
        ByRef As Integer, ByRef As Integer) As Integer render_opaque_bounds
    As Sub(ByVal As Widget_Struct_ Ptr) render_opaque_owner
    ' Optional narrower damage for an observation change such as caret blink.
    ' Return zero to repaint both complete widget rectangles.
    As Function(ByVal As Widget_Struct_ Ptr, ByRef As Const String, _
        ByRef As Const String, ByRef As Integer, ByRef As Integer, _
        ByRef As Integer, ByRef As Integer) As Integer render_damage
    As String retained_key
    As Integer retained_observation_offset
    As Integer retained_valid, retained_visible
    As Integer retained_x, retained_y, retained_w, retained_h
    As Integer retained_bounds_valid
    As Integer retained_paint_x, retained_paint_y, retained_paint_w, retained_paint_h
End Type

Type Widget As Widget_Struct_

' First half-second is visible. Keep epoch-based Timer values in Double;
' multiplying them before an Integer conversion overflows on 32-bit targets.
Declare Function gui_CaretBlinkVisible(ByVal secondsValue As Double) As Integer

Declare Sub gui_SetTabStop(ByVal w As Widget Ptr, ByVal enabled As Integer)
Declare Function gui_GetTabStop(ByVal w As Widget Ptr) As Integer

' -------------------------------------------------------------------------
' GUI Manager API
' -------------------------------------------------------------------------

' The returned unregistered base belongs to the caller until gui_AddWidget.
Declare Function gui_CreateWidgetBase() As Widget Ptr
Declare Function gui_GetPointerWidgetNameAt(ByVal x As Integer, ByVal y As Integer) As String
Declare Function gui_GetPointerCaptureName() As String

Const GUI_ANCHOR_NONE As UInteger = 0
Const GUI_ANCHOR_LEFT As UInteger = 1
Const GUI_ANCHOR_TOP As UInteger = 2
Const GUI_ANCHOR_RIGHT As UInteger = 4
Const GUI_ANCHOR_BOTTOM As UInteger = 8
Const GUI_ANCHOR_ALL As UInteger = _
    GUI_ANCHOR_LEFT Or GUI_ANCHOR_TOP Or _
    GUI_ANCHOR_RIGHT Or GUI_ANCHOR_BOTTOM

/'
    Anchor behavior follows desktop GUI conventions. Anchoring both opposing
    edges stretches that axis, anchoring only the far edge moves the widget,
    anchoring only the near edge preserves its local rectangle, and selecting
    neither edge keeps the widget centered as its container changes size.
'/

Declare Sub gui_Init()
Declare Sub gui_ResetForTest()
Declare Sub gui_AddWidget(ByVal w As Widget Ptr)
Declare Sub gui_AddGeneratedWidget(ByVal w As Widget Ptr)
' Remove one exact registered widget tree. The pointer is borrowed and becomes
' invalid when this function succeeds; zero or an unregistered pointer is safe.
Declare Function gui_RemoveWidgetPtr(ByVal target As Widget Ptr) As Integer
Declare Sub gui_RemoveWidget(ByVal nm As String)
Declare Function gui_FindWidget(ByVal nm As String) As Widget Ptr
Declare Sub gui_SetParent(ByVal child As Widget Ptr, ByVal parent As Widget Ptr)
Declare Sub gui_SetWidgetTheme(ByVal w As Widget Ptr, ByRef themeValue As GUI_Theme)
Declare Sub gui_ClearWidgetTheme(ByVal w As Widget Ptr)
Declare Function gui_GetEffectiveWidgetTheme( _
    ByVal w As Widget Ptr, ByRef themeValue As GUI_Theme _
) As Integer
Declare Sub gui_BringToFront(ByVal w As Widget Ptr)
Declare Function gui_IsWidgetRegistered(ByVal w As Widget Ptr) As Integer
Declare Sub gui_SetTextTransformHandler(ByVal handler As Any Ptr)
Declare Function gui_TransformText(ByVal text As String) As String
Declare Sub gui_SetFocus(ByVal w As Widget Ptr)
Declare Function gui_GetFocus() As Widget Ptr
Declare Function gui_IsPointerTarget(ByVal w As Widget Ptr) As Integer
Declare Sub gui_MoveFocus(ByVal reverseDirection As Integer = 0)
Declare Function gui_SetTabOrder( _
    ByVal w As Widget Ptr, ByVal tabOrder As Integer _
) As Integer
Declare Function gui_GetTabOrder( _
    ByVal w As Widget Ptr, ByRef tabOrder As Integer _
) As Integer
Declare Function gui_SetDefaultAction( _
    ByVal w As Widget Ptr, ByVal enabledState As Integer _
) As Integer
Declare Function gui_GetDefaultAction(ByVal w As Widget Ptr) As Integer
Declare Function gui_SetCancelAction( _
    ByVal w As Widget Ptr, ByVal enabledState As Integer _
) As Integer
Declare Function gui_GetCancelAction(ByVal w As Widget Ptr) As Integer
Declare Function gui_MnemonicScanCode( _
    ByVal characterCode As Integer _
) As Integer
Declare Function gui_ParseMnemonicCaption( _
    ByRef sourceText As Const String, ByRef displayText As String, _
    ByRef scanCode As Integer, ByRef displayIndex As Integer _
) As Integer
Declare Sub gui_RenderMnemonicUnderline( _
    ByVal w As Widget Ptr, ByRef display_text As Const String, _
    ByVal text_left As Integer, ByVal text_top As Integer, _
    ByVal text_height As Integer _
)
Declare Sub gui_SetMnemonic(ByVal w As Widget Ptr, ByVal keyCode As Integer)
Declare Function gui_SetMnemonicTarget( _
    ByVal sourceWidget As Widget Ptr, ByVal targetWidget As Widget Ptr _
) As Integer
Declare Function gui_GetMnemonicTarget( _
    ByVal sourceWidget As Widget Ptr _
) As Widget Ptr
Declare Function gui_IsKeyboardNavigationActive() As Integer
' Setting a registered root activates it above the current modal root.
' Repeating a root already in the stack does not displace a newer modal child.
' Closing a nested root restores the prior registered root. The checked form
' returns zero for an unregistered root or a full stack without changing state.
Declare Function gui_TrySetModalRoot(ByVal root As Widget Ptr) As Integer
Declare Sub gui_SetModalRoot(ByVal root As Widget Ptr)
Declare Sub gui_CancelInput(ByVal root As Widget Ptr)
Declare Sub gui_ClearModalRoot(ByVal root As Widget Ptr = 0)
Declare Function gui_IsModalOpen() As Integer
' Visibility changes cancel a hidden tree's private input and clear stale
' focus/modal ownership. Callers must not write Widget_Struct.visible directly.
Declare Function gui_SetVisible( _
    ByVal w As Widget Ptr, ByVal visibleState As Integer _
) As Integer
Declare Function gui_GetVisible(ByVal w As Widget Ptr) As Integer
Declare Sub gui_SetViewportSize(ByVal w As Integer, ByVal h As Integer)
Declare Sub gui_GetViewportSize(ByRef w As Integer, ByRef h As Integer)
' Set one positive-size logical rectangle and rebase active anchors against
' the current parent or viewport. This keeps application layout code out of
' Widget_Struct internals while preserving normal reactive resize behavior.
Declare Function gui_SetBounds( _
    ByVal w As Widget Ptr, ByVal x As Integer, ByVal y As Integer, _
    ByVal widthValue As Integer, ByVal heightValue As Integer _
) As Integer
Declare Sub gui_SetAnchors(ByVal w As Widget Ptr, ByVal anchorFlags As UInteger)
Declare Sub gui_ResetAnchors(ByVal w As Widget Ptr)
Declare Sub gui_SynchronizeLayout()
Declare Sub gui_RefreshLayout()
Declare Sub gui_RenderDesktop()
Declare Sub gui_RenderWindows()

Declare Sub gui_UpdateAll()
Declare Sub gui_RenderAll()

' Retained drawing keeps the visible framebuffer between updates. Regions
' include old bounds on movement/removal and are repainted in normal z order.
' Call Prepare once, then paint each returned region before the next update.
Declare Sub gui_InvalidateAll()
Declare Sub gui_InvalidateRect(ByVal x As Integer, ByVal y As Integer, _
    ByVal widthValue As Integer, ByVal heightValue As Integer)
Declare Function gui_PrepareRetainedFrame() As Integer
Declare Sub gui_SetRenderBoundsHandler(ByVal w As Widget Ptr, _
    ByVal boundsHandler As Function(ByVal As Widget Ptr, ByRef As Integer, _
        ByRef As Integer, ByRef As Integer, ByRef As Integer) As Integer)
Declare Sub gui_SetOpaqueRenderBoundsHandler(ByVal w As Widget Ptr, _
    ByVal boundsHandler As Function(ByVal As Widget Ptr, ByRef As Integer, _
        ByRef As Integer, ByRef As Integer, ByRef As Integer) As Integer)
Declare Sub gui_SetRenderObservationMatcher(ByVal w As Widget Ptr, _
    ByVal matchHandler As Function(ByVal As Widget Ptr, ByRef As Const String, _
        ByVal As Integer) As Integer)
Declare Sub gui_GetDamageRect(ByVal index As Integer, ByRef x As Integer, _
    ByRef y As Integer, ByRef widthValue As Integer, ByRef heightValue As Integer)

Declare Sub gui_DrawLine( _
    ByVal x1 As Integer, ByVal y1 As Integer, _
    ByVal x2 As Integer, ByVal y2 As Integer, _
    ByVal clr As ULong _
)
Declare Sub gui_DrawRect( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer, _
    ByVal clr As ULong, ByVal filled As Integer _
)
Declare Sub gui_DrawCircle( _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal radius As Integer, ByVal clr As ULong, _
    ByVal filled As Integer _
)
Declare Sub gui_DrawCurve( _
    ByVal x1 As Integer, ByVal y1 As Integer, _
    ByVal x2 As Integer, ByVal y2 As Integer, _
    ByVal x3 As Integer, ByVal y3 As Integer, _
    ByVal clr As ULong _
)

Declare Function gui_ButtonPressed(ByVal nm As String) As Integer
Declare Sub gui_DeselectRadioGroup(ByVal group_id As Integer, ByVal caller As Widget Ptr)

#endif

/' end of widgets.bi '/
