/'
    Project: omaGUI qualification. File: textbox_short_press_smoke.bas.
    Purpose: Retain editing and navigation presses released between GUI polls.
    Responsibilities: Check edits, one-frame consumption and callback precedence.
    This file does not inject operating-system input or modify user documents.
    All GUI and mock input calls run on the fixture's main thread.
'/
#lang "fb"
#define OMAGUI_IMPLEMENTATION
#define OMAGUI_PORTABLE_ONLY
#include once "omaGUI.bi"

Dim Shared As Integer checks, failures
Dim Shared As String diagnostics
Private Sub require(ByVal condition As Integer, ByRef description As Const String)
    checks += 1
    If condition Then Exit Sub
    failures += 1
    diagnostics &= "FAIL: " & description & Chr(10)
End Sub
Private Sub pressAndRelease(ByVal scanCode As Integer)
    require input_MockKeyEvent(INPUT_KEY_EVENT_PRESS, scanCode), "queue press"
    require input_MockKeyEvent(INPUT_KEY_EVENT_RELEASE, scanCode), "queue release"
    gui_UpdateAll
End Sub
Private Sub consumeBackspace(ByVal target As Widget Ptr, ByRef characterCode As Integer)
    If characterCode = 8 Then characterCode = 0
End Sub

ScreenControl FB.SET_DRIVER_NAME, "null"
backend_Init 400, 240, BACKEND_DISPLAY_ENABLED
gui_Init
Dim As Widget Ptr editor = textbox_Create("editor", "abc", 10, 10, 220, 90, -1, 0)
gui_AddWidget editor
gui_SynchronizeLayout
gui_SetFocus editor
textbox_SetCursorPosition editor, 3
pressAndRelease KEY_BACKSPACE
require textbox_GetText(editor) = "ab", "released Backspace edits once"
gui_UpdateAll
require textbox_GetText(editor) = "ab", "old Backspace is not replayed"
textbox_SetCursorPosition editor, 0
pressAndRelease KEY_DELETE
require textbox_GetText(editor) = "b", "released Delete edits once"
textbox_SetCursorPosition editor, 1
pressAndRelease KEY_RETURN
require textbox_GetText(editor) = "b" & Chr(10), "released Return inserts one newline"
pressAndRelease KEY_LEFT
require textbox_GetCursorPosition(editor) = 1, "released Left moves the caret"
gui_UpdateAll
require textbox_GetCursorPosition(editor) = 1, "old Left is not replayed"

textbox_SetText editor, "xy", -1
textbox_SetCursorPosition editor, 2
Dim As TextBoxData Ptr editorData = editor->data
editorData->key_press_handler = @consumeBackspace
pressAndRelease KEY_BACKSPACE
require textbox_GetText(editor) = "xy", "callback consumption still prevents deletion"
editorData->key_press_handler = 0
pressAndRelease KEY_BACKSPACE
require textbox_GetText(editor) = "x", "later released Backspace remains available"

gui_ResetForTest
backend_Exit
Print diagnostics;
Print "SHORT_PRESS_CHECKS;"; checks; ";"; failures
If failures <> 0 Then End 1
Print "TEXTBOX_SHORT_PRESS_PASS"
End 0
' end of textbox_short_press_smoke.bas
