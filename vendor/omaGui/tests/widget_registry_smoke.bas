/'
    Project: omaGUI qualification. File: widget_registry_smoke.bas.
    Purpose: Preserve callback lifetimes while avoiding idle registry scans.
    Responsibilities: Check self-replacement, sibling removal and new registrations;
        count real lifetime lookups in a bounded hidden-widget idle workload.
    This file does not operate system input, draw a user window or save documents.
    The fixture and all registry callbacks belong to the same GUI thread.
'/
#lang "fb"
#define OMAGUI_IMPLEMENTATION
#define OMAGUI_PORTABLE_ONLY
#define OMAGUI_PROFILE_REGISTRY
#include once "omaGUI.bi"
Private Dim Shared As Integer checks, failures, replacementUpdates, siblingUpdates
Private Dim Shared As Widget Ptr sibling
Private Dim Shared As String diagnostics
Private Sub require(ByVal condition As Integer, ByRef description As Const String)
    checks += 1
    If condition <> 0 Then Exit Sub
    failures += 1
    diagnostics &= "FAIL: " & description & Chr(10)
End Sub
Private Sub updateReplacement(ByVal w As Widget Ptr)
    replacementUpdates += 1
End Sub
Private Sub updateSibling(ByVal w As Widget Ptr)
    siblingUpdates += 1
End Sub
Private Function createNode(ByRef nodeName As Const String) As Widget Ptr
    Dim As Widget Ptr result = gui_CreateWidgetBase()
    If result = 0 Then End 90
    result->name = nodeName
    result->w = 10
    result->h = 10
    Return result
End Function
Private Sub replaceSelf(ByVal w As Widget Ptr)
    gui_RemoveWidgetPtr w
    Dim As Widget Ptr replacement = createNode("replacement")
    replacement->update = @updateReplacement
    gui_AddWidget replacement
End Sub
Private Sub removeSibling(ByVal w As Widget Ptr)
    If sibling = 0 Then Exit Sub
    gui_RemoveWidgetPtr sibling
    sibling = 0
End Sub
Private Sub appendSibling(ByVal w As Widget Ptr)
    w->update = 0
    Dim As Widget Ptr added = createNode("added")
    added->update = @updateReplacement
    gui_AddWidget added
End Sub

ScreenControl FB.SET_DRIVER_NAME, "null"
backend_Init 400, 240, BACKEND_DISPLAY_ENABLED
gui_Init
input_ResetForTest
Dim As Widget Ptr current = createNode("self")
current->update = @replaceSelf
gui_AddWidget current
gui_UpdateAll
require replacementUpdates = 1, "replacement updates once after the restart"
require gui_FindWidget("self") = 0, "self is removed"
require gui_FindWidget("replacement") <> 0, "replacement remains registered"
gui_ResetForTest
current = createNode("first")
current->update = @removeSibling
gui_AddWidget current
sibling = createNode("sibling")
sibling->update = @updateSibling
gui_AddWidget sibling
gui_UpdateAll
require siblingUpdates = 0, "deleted sibling receives no update"
require gui_FindWidget("sibling") = 0, "deleted sibling is absent"
gui_ResetForTest
replacementUpdates = 0
current = createNode("append")
current->update = @appendSibling
gui_AddWidget current
gui_UpdateAll
require replacementUpdates = 0, "new sibling waits for its first layout"
require gui_FindWidget("added") <> 0, "appended sibling is registered"
gui_UpdateAll
require replacementUpdates = 1, "new sibling updates on the following frame"
gui_ResetForTest
For index As Integer = 1 To 256
    current = createNode("idle_" & Str(index))
    current->visible = 0
    gui_AddWidget current
Next index
gui_ProfileRegistryLookups = 0
Dim As Double started = Timer
For frame As Integer = 1 To 100
    gui_UpdateAll
Next frame
Dim As Double elapsed = Timer - started
If elapsed < -43200 Then elapsed += 86400
Dim As ULongInt lookups = gui_ProfileRegistryLookups
#Ifdef REGISTRY_REFERENCE
require lookups >= 25600, "original idle path scans every widget"
#Else
require lookups = 0, "unchanged idle registry needs no lifetime scan"
#EndIf
gui_ResetForTest
backend_Exit
Print diagnostics;
Print "REGISTRY_EPOCH_CHECKS;"; checks; ";"; failures
Print "REGISTRY_EPOCH_LOOKUPS;"; lookups
Print "REGISTRY_EPOCH_SECONDS;"; elapsed
If failures <> 0 Then End 1
Print "REGISTRY_EPOCH_PASS"
End 0
' end of widget_registry_smoke.bas
