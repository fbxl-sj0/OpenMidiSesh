/'
    Project: OpenSesh
    ---------------------------

    File: ui_frame_pacing.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements ui_frame_pacing.bi; declarations there define the shared interface.

    Purpose:

        Calculate deterministic, bounded UI timing statistics for native
        Windows and Linux release benchmarks.

    Responsibilities:

        - reject invalid or excessive timing samples without writing past arrays
        - calculate descriptive statistics without heap allocation
        - handle the FreeBASIC Timer midnight wrap
        - apply the documented interactive 60 Hz release limits

    This file intentionally does NOT contain:

        - editor globals or widget knowledge
        - drawing and page presentation
        - test-report file access
        - arbitrary-size statistical storage
'/

#lang "fb"

#include once "ui_frame_pacing.bi"

' -------------------------------------------------------------------------
' Series storage
' -------------------------------------------------------------------------

Public Sub uiFramePacing_Initialize(ByRef metrics As OseUiSmoothnessMetrics)
    metrics.frameIntervals.count = 0
    metrics.frameIntervals.rejectedCount = 0
    metrics.frameWork.count = 0
    metrics.frameWork.rejectedCount = 0
    metrics.inputLatency.count = 0
    metrics.inputLatency.rejectedCount = 0
    metrics.updateWork.count = 0
    metrics.updateWork.rejectedCount = 0
    metrics.applicationRender.count = 0
    metrics.applicationRender.rejectedCount = 0
    metrics.widgetRender.count = 0
    metrics.widgetRender.rejectedCount = 0
    metrics.presentation.count = 0
    metrics.presentation.rejectedCount = 0
    metrics.scoreRender.count = 0
    metrics.scoreRender.rejectedCount = 0
    metrics.scoreCache.count = 0
    metrics.scoreCache.rejectedCount = 0
    metrics.scoreBase.count = 0
    metrics.scoreBase.rejectedCount = 0
    metrics.scoreRests.count = 0
    metrics.scoreRests.rejectedCount = 0
    metrics.scoreNotes.count = 0
    metrics.scoreNotes.rejectedCount = 0
    metrics.scoreToolRender.count = 0
    metrics.scoreToolRender.rejectedCount = 0
    metrics.mixerRender.count = 0
    metrics.mixerRender.rejectedCount = 0
End Sub


Public Function uiFramePacing_Record( _
    ByRef series As OseUiTimingSeries, _
    ByVal milliseconds As Double _
) As Integer
    ' The comparison against itself is a portable NaN check. Timing values
    ' above one minute indicate a broken benchmark clock and are not useful UI
    ' samples, so they are rejected along with negative values.
    If milliseconds <> milliseconds OrElse milliseconds < 0.0 OrElse _
        milliseconds > 60000.0 OrElse _
        series.count < 0 OrElse _
        series.count >= OSE_UI_TIMING_SAMPLE_CAPACITY Then
        If series.rejectedCount < &h7fffffff Then
            series.rejectedCount += 1
        End If
        Return 0
    End If

    series.values(series.count) = milliseconds
    series.count += 1
    Return -1
End Function

' -------------------------------------------------------------------------
' Descriptive statistics
' -------------------------------------------------------------------------

Public Function uiFramePacing_Mean( _
    ByRef series As OseUiTimingSeries _
) As Double
    If series.count <= 0 OrElse _
        series.count > OSE_UI_TIMING_SAMPLE_CAPACITY Then
        Return 0.0
    End If

    Dim As Double total
    For sampleIndex As Integer = 0 To series.count - 1
        total += series.values(sampleIndex)
    Next
    Return total / CDbl(series.count)
End Function


Public Function uiFramePacing_Percentile( _
    ByRef series As OseUiTimingSeries, _
    ByVal percentile As Double _
) As Double
    If series.count <= 0 OrElse _
        series.count > OSE_UI_TIMING_SAMPLE_CAPACITY Then
        Return 0.0
    End If

    If percentile < 0.0 Then
        percentile = 0.0
    End If
    If percentile > 100.0 Then
        percentile = 100.0
    End If

    Dim As Double sortedValues(0 To OSE_UI_TIMING_SAMPLE_CAPACITY - 1)
    For sampleIndex As Integer = 0 To series.count - 1
        sortedValues(sampleIndex) = series.values(sampleIndex)
    Next

    ' Shell sort avoids heap allocation and is comfortably bounded at 1,800
    ' samples. Percentiles are calculated only once when a run ends.
    Dim As Integer gap = series.count \ 2
    While gap > 0
        For sampleIndex As Integer = gap To series.count - 1
            Dim As Double pendingValue = sortedValues(sampleIndex)
            Dim As Integer insertionIndex = sampleIndex
            While insertionIndex >= gap AndAlso _
                sortedValues(insertionIndex - gap) > pendingValue
                sortedValues(insertionIndex) = _
                    sortedValues(insertionIndex - gap)
                insertionIndex -= gap
            Wend
            sortedValues(insertionIndex) = pendingValue
        Next
        gap \= 2
    Wend

    ' Nearest-rank percentiles select ceil(P * N), with a zero-based array.
    Dim As Integer rankIndex
    If percentile > 0.0 Then
        rankIndex = CInt(Int((percentile * CDbl(series.count) + 99.999999999) / _
            100.0)) - 1
    End If
    If rankIndex < 0 Then
        rankIndex = 0
    End If
    If rankIndex >= series.count Then
        rankIndex = series.count - 1
    End If
    Return sortedValues(rankIndex)
End Function


Public Function uiFramePacing_Maximum( _
    ByRef series As OseUiTimingSeries _
) As Double
    If series.count <= 0 OrElse _
        series.count > OSE_UI_TIMING_SAMPLE_CAPACITY Then
        Return 0.0
    End If

    Dim As Double maximumValue = series.values(0)
    For sampleIndex As Integer = 1 To series.count - 1
        If series.values(sampleIndex) > maximumValue Then
            maximumValue = series.values(sampleIndex)
        End If
    Next
    Return maximumValue
End Function


Public Function uiFramePacing_CountAbove( _
    ByRef series As OseUiTimingSeries, _
    ByVal thresholdMilliseconds As Double _
) As Integer
    If series.count <= 0 OrElse _
        series.count > OSE_UI_TIMING_SAMPLE_CAPACITY Then
        Return 0
    End If

    Dim As Integer matchingCount
    For sampleIndex As Integer = 0 To series.count - 1
        If series.values(sampleIndex) > thresholdMilliseconds Then
            matchingCount += 1
        End If
    Next
    Return matchingCount
End Function

' -------------------------------------------------------------------------
' Clock and release contract
' -------------------------------------------------------------------------

Public Function uiFramePacing_ElapsedMilliseconds( _
    ByVal startSeconds As Double, _
    ByVal endSeconds As Double _
) As Double
    Dim As Double elapsedSeconds = endSeconds - startSeconds
    If elapsedSeconds < 0.0 Then
        elapsedSeconds += 86400.0
    End If
    If elapsedSeconds < 0.0 OrElse elapsedSeconds > 60.0 Then
        Return -1.0
    End If
    Return elapsedSeconds * 1000.0
End Function


Public Function uiFramePacing_Evaluate( _
    ByRef metrics As OseUiSmoothnessMetrics, _
    ByVal workloadValid As Integer, _
    ByRef result As OseUiSmoothnessResult _
) As Integer
    result.passed = 0
    result.averageFps = 0.0
    result.intervalP50Ms = uiFramePacing_Percentile( _
        metrics.frameIntervals, 50.0)
    result.intervalP95Ms = uiFramePacing_Percentile( _
        metrics.frameIntervals, 95.0)
    result.intervalP99Ms = uiFramePacing_Percentile( _
        metrics.frameIntervals, 99.0)
    result.intervalMaximumMs = uiFramePacing_Maximum(metrics.frameIntervals)
    result.workP95Ms = uiFramePacing_Percentile(metrics.frameWork, 95.0)
    result.inputP95Ms = uiFramePacing_Percentile(metrics.inputLatency, 95.0)
    result.hitchCount = uiFramePacing_CountAbove( _
        metrics.frameIntervals, OSE_UI_SMOOTHNESS_HITCH_MS)
    result.longHitchCount = uiFramePacing_CountAbove( _
        metrics.frameIntervals, OSE_UI_SMOOTHNESS_INTERVAL_MAX_MS)

    Dim As Double meanInterval = uiFramePacing_Mean(metrics.frameIntervals)
    If meanInterval > 0.0 Then
        result.averageFps = 1000.0 / meanInterval
    End If

    If workloadValid = 0 OrElse _
        metrics.frameIntervals.count < OSE_UI_SMOOTHNESS_MINIMUM_SAMPLES OrElse _
        metrics.frameWork.count <> metrics.frameIntervals.count OrElse _
        metrics.inputLatency.count <> metrics.frameIntervals.count OrElse _
        metrics.frameIntervals.rejectedCount <> 0 OrElse _
        metrics.frameWork.rejectedCount <> 0 OrElse _
        metrics.inputLatency.rejectedCount <> 0 Then
        Return 0
    End If

    If result.averageFps < OSE_UI_SMOOTHNESS_MINIMUM_FPS OrElse _
        result.intervalP95Ms > OSE_UI_SMOOTHNESS_INTERVAL_P95_MS OrElse _
        result.intervalP99Ms > OSE_UI_SMOOTHNESS_INTERVAL_P99_MS OrElse _
        result.intervalMaximumMs > OSE_UI_SMOOTHNESS_INTERVAL_MAX_MS OrElse _
        result.workP95Ms > OSE_UI_SMOOTHNESS_WORK_P95_MS OrElse _
        result.inputP95Ms > OSE_UI_SMOOTHNESS_INPUT_P95_MS OrElse _
        result.hitchCount > OSE_UI_SMOOTHNESS_MAXIMUM_HITCHES OrElse _
        result.longHitchCount <> 0 Then
        Return 0
    End If

    result.passed = -1
    Return -1
End Function

/' end of ui_frame_pacing.bas '/
