/'
    Project: omaGUI backend
    File: backend_idle.bi
    Purpose: Release foreground GUI idle time to the selected platform.
    Responsibilities: Bound polling waits and support the DOSBox-X idle API.
    This file intentionally does NOT contain:
        draw widgets, dispatch input or schedule worker threads.

    Calls belong to the GUI thread, after drawing and application locks are
    released. Native targets use SLEEP. DOSBox-X builds can explicitly select
    OMAGUI_DOSBOX_X_IDLE; ordinary DOS builds retain their existing wait path.
    INT 2Fh/AX=1680h is reached through DJGPP's __dpmi_yield. One request lets
    DOSBox-X release host CPU time; SLEEP retains the runtime's wait path and
    optional RTC preemption. Do not poll TIMER or uclock around host yields:
    DOS graphics owns the PIT, and its clock readings can be coarse or move
    backward. Repeating the host request against those readings can stall
    input dispatch even when the requested polling interval is very short.
    This path is not enabled for an unqualified physical DOS or DPMI host.

    OMAGUI_DOSBOX_X_TIMER_IDLE selects the timed helper in the newer DOS
    gfxlib. It requires that library at link time. Its IRQ0 counter measures
    PIT input cycles independently of BIOS ticks and consumed display ticks.
    DOS_GFX_LOW_POWER=YesPlease can lower the library's timer wake rate when
    paired with this wait. A single yield alone can accelerate GUI polling.

    Targets: FreeBASIC fb dialect with the native omaGUI backend.
    Module API boundary: Bounded backend_Idle waits on the GUI thread.
'/

#pragma once

#If Defined(__FB_DOS__) And Defined(OMAGUI_DOSBOX_X_IDLE)
Extern "C"
    Declare Sub backend_DosHostYield Alias "__dpmi_yield"()
End Extern
#EndIf

#If Defined(__FB_DOS__) And Defined(OMAGUI_DOSBOX_X_TIMER_IDLE)
Extern "C"
    Declare Sub backend_DosTimedIdle Alias "fb_GfxDosIdle"(ByVal milliseconds As Long)
End Extern
#EndIf

Sub backend_Idle(ByVal milliseconds As Integer)
    If milliseconds <= 0 Then Exit Sub
    ' This is a GUI polling wait, not a general-purpose long sleep.
    If milliseconds > 1000 Then milliseconds = 1000
#If Defined(__FB_DOS__) And Defined(OMAGUI_DOSBOX_X_TIMER_IDLE)
    backend_DosTimedIdle CLng(milliseconds)
#Else
#If Defined(__FB_DOS__) And Defined(OMAGUI_DOSBOX_X_IDLE)
    backend_DosHostYield()
#EndIf
    Sleep milliseconds, 1
#EndIf
End Sub

' end of backend_idle.bi
