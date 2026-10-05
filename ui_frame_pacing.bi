/'
    Project: OpenSesh
    ---------------------------

    File: ui_frame_pacing.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: uiFramePacing_* measurements/evaluation with OseUi* timing records and acceptance limits.

    Purpose:

        Declare bounded timing statistics and the release acceptance contract
        used by the editor's interactive smoothness benchmark.

    Responsibilities:

        - retain a fixed number of frame, render-work, and input latency samples
        - expose mean, percentile, maximum, and hitch-count statistics
        - normalize elapsed time across the platform Timer midnight boundary
        - evaluate one benchmark run against an explicit 60 Hz UI contract

    This file intentionally does NOT contain:

        - rendering or input injection
        - operating-system performance counters
        - benchmark document construction
        - release-runner process control
'/

#ifndef __OSE_UI_FRAME_PACING_BI__
#define __OSE_UI_FRAME_PACING_BI__

Const OSE_UI_TIMING_SAMPLE_CAPACITY As Integer = 1800
Const OSE_UI_SMOOTHNESS_MINIMUM_SAMPLES As Integer = 240

' A 60 Hz display presents a new frame every 16.67 ms. The 59 FPS floor allows
' 59.94 Hz display clocks and measurement overhead, while the percentile and
' hitch limits reject sustained slow rendering or a visible long-tail pattern.
Const OSE_UI_SMOOTHNESS_MINIMUM_FPS As Double = 59.0
Const OSE_UI_SMOOTHNESS_INTERVAL_P95_MS As Double = 20.0
Const OSE_UI_SMOOTHNESS_INTERVAL_P99_MS As Double = 25.0
Const OSE_UI_SMOOTHNESS_INTERVAL_MAX_MS As Double = 50.0
Const OSE_UI_SMOOTHNESS_WORK_P95_MS As Double = 16.67
Const OSE_UI_SMOOTHNESS_INPUT_P95_MS As Double = 20.0
Const OSE_UI_SMOOTHNESS_HITCH_MS As Double = 33.34
Const OSE_UI_SMOOTHNESS_MAXIMUM_HITCHES As Integer = 2

Type OseUiTimingSeries
    As Integer count
    As Integer rejectedCount
    As Double values(0 To OSE_UI_TIMING_SAMPLE_CAPACITY - 1)
End Type

Type OseUiSmoothnessMetrics
    As OseUiTimingSeries frameIntervals
    As OseUiTimingSeries frameWork
    As OseUiTimingSeries inputLatency
    As OseUiTimingSeries updateWork
    As OseUiTimingSeries applicationRender
    As OseUiTimingSeries widgetRender
    As OseUiTimingSeries presentation
    As OseUiTimingSeries scoreRender
    As OseUiTimingSeries scoreCache
    As OseUiTimingSeries scoreBase
    As OseUiTimingSeries scoreRests
    As OseUiTimingSeries scoreNotes
    As OseUiTimingSeries scoreToolRender
    As OseUiTimingSeries mixerRender
End Type

Type OseUiSmoothnessResult
    As Integer passed
    As Double averageFps
    As Double intervalP50Ms
    As Double intervalP95Ms
    As Double intervalP99Ms
    As Double intervalMaximumMs
    As Double workP95Ms
    As Double inputP95Ms
    As Integer hitchCount
    As Integer longHitchCount
End Type

Declare Sub uiFramePacing_Initialize(ByRef metrics As OseUiSmoothnessMetrics)

Declare Function uiFramePacing_Record( _
    ByRef series As OseUiTimingSeries, _
    ByVal milliseconds As Double _
) As Integer

Declare Function uiFramePacing_Mean( _
    ByRef series As OseUiTimingSeries _
) As Double

Declare Function uiFramePacing_Percentile( _
    ByRef series As OseUiTimingSeries, _
    ByVal percentile As Double _
) As Double

Declare Function uiFramePacing_Maximum( _
    ByRef series As OseUiTimingSeries _
) As Double

Declare Function uiFramePacing_CountAbove( _
    ByRef series As OseUiTimingSeries, _
    ByVal thresholdMilliseconds As Double _
) As Integer

Declare Function uiFramePacing_ElapsedMilliseconds( _
    ByVal startSeconds As Double, _
    ByVal endSeconds As Double _
) As Double

Declare Function uiFramePacing_Evaluate( _
    ByRef metrics As OseUiSmoothnessMetrics, _
    ByVal workloadValid As Integer, _
    ByRef result As OseUiSmoothnessResult _
) As Integer

#endif

/' end of ui_frame_pacing.bi '/
