/'
    Project: OpenSesh
    ---------------------------

    File: tests/ui_frame_pacing_smoke.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; Windows/Linux host test runners.

    Purpose:

        Prove the timing statistics and fail-closed 60 Hz UI acceptance rules
        used by the native smoothness benchmark.

    Responsibilities:

        - verify bounded sample storage and invalid-value rejection
        - verify mean, nearest-rank percentile, maximum, and hitch counting
        - verify ordinary and midnight-wrapped elapsed time
        - exercise every smoothness contract boundary and failure category

    This file intentionally does NOT contain:

        - a graphical window
        - editor input simulation
        - platform-specific process automation
'/

#lang "fb"

#include once "../ui_frame_pacing.bi"

Private Sub test_Fail(ByVal messageText As String)
    Print "FAIL: "; messageText
    End 1
End Sub


Private Function test_Close( _
    ByVal actualValue As Double, _
    ByVal expectedValue As Double _
) As Integer
    Return IIf(Abs(actualValue - expectedValue) <= 0.000001, -1, 0)
End Function


Private Sub test_FillPassingMetrics(ByRef metrics As OseUiSmoothnessMetrics)
    uiFramePacing_Initialize metrics
    For sampleIndex As Integer = 0 To OSE_UI_SMOOTHNESS_MINIMUM_SAMPLES - 1
        If Not uiFramePacing_Record(metrics.frameIntervals, 16.0) OrElse _
            Not uiFramePacing_Record(metrics.frameWork, 8.0) OrElse _
            Not uiFramePacing_Record(metrics.inputLatency, 9.0) Then _
            test_Fail "a valid contract sample was rejected"
    Next
End Sub


Dim As OseUiSmoothnessMetrics metrics
uiFramePacing_Initialize metrics
If metrics.frameIntervals.count <> 0 OrElse _
    metrics.frameWork.rejectedCount <> 0 Then _
    test_Fail "initialization did not clear counters"

Dim As Double values(0 To 4) = {5.0, 1.0, 4.0, 2.0, 3.0}
For sampleIndex As Integer = 0 To 4
    If Not uiFramePacing_Record( _
        metrics.frameIntervals, values(sampleIndex)) Then _
        test_Fail "a valid statistic sample was rejected"
Next
If Not test_Close(uiFramePacing_Mean(metrics.frameIntervals), 3.0) Then _
    test_Fail "mean calculation was wrong"
If Not test_Close(uiFramePacing_Percentile(metrics.frameIntervals, 0.0), 1.0) OrElse _
    Not test_Close(uiFramePacing_Percentile(metrics.frameIntervals, 50.0), 3.0) OrElse _
    Not test_Close(uiFramePacing_Percentile(metrics.frameIntervals, 95.0), 5.0) OrElse _
    Not test_Close(uiFramePacing_Percentile(metrics.frameIntervals, 100.0), 5.0) Then _
    test_Fail "nearest-rank percentile calculation was wrong"
If Not test_Close(uiFramePacing_Maximum(metrics.frameIntervals), 5.0) Then _
    test_Fail "maximum calculation was wrong"
If uiFramePacing_CountAbove(metrics.frameIntervals, 3.0) <> 2 Then _
    test_Fail "strict hitch counting was wrong"

If uiFramePacing_Record(metrics.frameIntervals, -1.0) <> 0 OrElse _
    uiFramePacing_Record(metrics.frameIntervals, 60001.0) <> 0 OrElse _
    metrics.frameIntervals.rejectedCount <> 2 Then _
    test_Fail "invalid timing values were not rejected"

Dim As OseUiTimingSeries fullSeries
For sampleIndex As Integer = 0 To OSE_UI_TIMING_SAMPLE_CAPACITY - 1
    If Not uiFramePacing_Record(fullSeries, 1.0) Then _
        test_Fail "capacity rejected an in-range sample"
Next
If uiFramePacing_Record(fullSeries, 1.0) <> 0 OrElse _
    fullSeries.count <> OSE_UI_TIMING_SAMPLE_CAPACITY OrElse _
    fullSeries.rejectedCount <> 1 Then _
    test_Fail "capacity guard did not fail closed"

If Not test_Close(uiFramePacing_ElapsedMilliseconds(1.0, 1.125), 125.0) OrElse _
    Not test_Close(uiFramePacing_ElapsedMilliseconds(86399.9, 0.1), 200.0) OrElse _
    uiFramePacing_ElapsedMilliseconds(100.0, 50.0) >= 0.0 Then _
    test_Fail "elapsed-time normalization was wrong"

Dim As OseUiSmoothnessResult result
test_FillPassingMetrics metrics
If uiFramePacing_Evaluate(metrics, -1, result) = 0 OrElse _
    result.passed = 0 OrElse Not test_Close(result.averageFps, 62.5) Then _
    test_Fail "a passing 60 Hz run was rejected"

test_FillPassingMetrics metrics
metrics.frameIntervals.values(0) = 51.0
If uiFramePacing_Evaluate(metrics, -1, result) <> 0 OrElse _
    result.longHitchCount <> 1 Then _
    test_Fail "a long frame hitch passed"

test_FillPassingMetrics metrics
metrics.frameWork.values(0) = 25.0
For sampleIndex As Integer = 1 To 20
    metrics.frameWork.values(sampleIndex) = 17.0
Next
If uiFramePacing_Evaluate(metrics, -1, result) <> 0 Then _
    test_Fail "excessive render work passed"

test_FillPassingMetrics metrics
metrics.inputLatency.values(0) = 30.0
For sampleIndex As Integer = 1 To 20
    metrics.inputLatency.values(sampleIndex) = 21.0
Next
If uiFramePacing_Evaluate(metrics, -1, result) <> 0 Then _
    test_Fail "excessive input latency passed"

test_FillPassingMetrics metrics
If uiFramePacing_Evaluate(metrics, 0, result) <> 0 Then _
    test_Fail "an unverified workload passed"

test_FillPassingMetrics metrics
metrics.frameIntervals.count = OSE_UI_SMOOTHNESS_MINIMUM_SAMPLES - 1
metrics.frameWork.count = metrics.frameIntervals.count
metrics.inputLatency.count = metrics.frameIntervals.count
If uiFramePacing_Evaluate(metrics, -1, result) <> 0 Then _
    test_Fail "an undersampled run passed"

Print "ui_frame_pacing=ok"
Print "statistics_cases=10 contract_failure_cases=5"
End 0

/' end of tests/ui_frame_pacing_smoke.bas '/
