/'
    Project: OpenSesh
    ---------------------------

    File: pitch_transcriber.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements pitch_transcriber.bi; declarations there define the shared interface.

    Purpose:

        Convert a bounded monophonic PCM WAV recording into timed MIDI pitches.

    Responsibilities:

        - parse uncompressed 8-bit and 16-bit PCM WAV containers safely
        - downmix and downsample voice recordings for bounded analysis
        - reject silence and estimate pitch with normalized autocorrelation
        - stabilize frame estimates into minimum-length monophonic notes

    Ownership:

        Each read owns and closes its file handle. Temporary sample arrays
        belong to the analysis call; retained notes belong to this module.

    This file intentionally does NOT contain:

        - microphone capture or device selection
        - tempo-map conversion or musical-grid quantization
        - polyphonic transcription
        - user-interface code
'/

#lang "fb"

#include once "pitch_transcriber.bi"
#include once "binary_file_internal.bi"

' -------------------------------------------------------------------------
' Analysis limits and retained result state
' -------------------------------------------------------------------------

Const PITCH_FRAME_SAMPLES As Integer = 1024
Const PITCH_HOP_SAMPLES As Integer = 256
Const PITCH_TARGET_SAMPLE_RATE As Integer = 16000
Const PITCH_COARSE_SAMPLE_STEP As Integer = 4
Const PITCH_GAP_BRIDGE_FRAMES As Integer = 2
Const PITCH_DEFAULT_MINIMUM_FREQUENCY As Double = 70.0
Const PITCH_DEFAULT_MAXIMUM_FREQUENCY As Double = 2000.0
Const PITCH_DEFAULT_SILENCE_THRESHOLD As Double = 0.015
Const PITCH_DEFAULT_CORRELATION_THRESHOLD As Double = 0.58
Const PITCH_DEFAULT_MINIMUM_NOTE_MS As ULong = 90
Const PITCH_CONFIG_MINIMUM_FREQUENCY As Double = 20.0
Const PITCH_CONFIG_MAXIMUM_FREQUENCY As Double = 5000.0
Const PITCH_CONFIG_MINIMUM_NOTE_MS As ULong = 20
Const PITCH_CONFIG_MAXIMUM_NOTE_MS As ULong = 5000
Const PITCH_VELOCITY_BASE As Integer = 40
Const PITCH_VELOCITY_RMS_SCALE As Double = 500.0

' PCM fmt chunk layout, measured from the start of its payload:
' 0..1 format, 2..3 channels, 4..7 sample rate, 8..11 byte rate,
' 12..13 block alignment, and 14..15 sample width.
Const PITCH_WAV_FMT_MINIMUM_BYTES As ULongInt = 16
Const PITCH_WAV_FMT_CHANNEL_OFFSET As ULongInt = 2
Const PITCH_WAV_FMT_SAMPLE_RATE_OFFSET As ULongInt = 4
Const PITCH_WAV_FMT_BYTE_RATE_OFFSET As ULongInt = 8
Const PITCH_WAV_FMT_BLOCK_ALIGN_OFFSET As ULongInt = 12
Const PITCH_WAV_FMT_BITS_OFFSET As ULongInt = 14

' fblint: disable-next-line FBL301 REASON: one retained result list mirrors the MIDI model API.
Dim Shared pitchTranscribe_Notes( _
    0 To PITCH_TRANSCRIBE_MAX_NOTES - 1) As PitchTranscribedNote
' fblint: disable-next-line FBL301 REASON: retained count belongs to the bounded result list above.
Dim Shared pitchTranscribe_NoteCount As Integer


' -------------------------------------------------------------------------
' Little-endian WAV helpers
' -------------------------------------------------------------------------

Private Function pitchTranscribe_ReadByte( _
    ByRef binaryData As String, _
    ByVal byteOffset As ULongInt _
) As Integer
    If byteOffset >= CULngInt(Len(binaryData)) Then
        Return -1
    End If
    Return Asc(Mid(binaryData, CInt(byteOffset) + 1, 1))
End Function


Private Function pitchTranscribe_ReadLe16( _
    ByRef binaryData As String, _
    ByVal byteOffset As ULongInt _
) As ULong
    Dim As Integer lowByte = pitchTranscribe_ReadByte(binaryData, byteOffset)
    Dim As Integer highByte = pitchTranscribe_ReadByte(binaryData, byteOffset + 1)
    If lowByte < 0 OrElse highByte < 0 Then
        Return 0
    End If
    Return CULng(lowByte Or (highByte Shl 8))
End Function


Private Function pitchTranscribe_ReadLe32( _
    ByRef binaryData As String, _
    ByVal byteOffset As ULongInt _
) As ULong
    Dim As ULong resultValue
    For byteIndex As Integer = 0 To 3
        Dim As Integer byteValue = pitchTranscribe_ReadByte( _
            binaryData, byteOffset + CULngInt(byteIndex))
        If byteValue < 0 Then
            Return 0
        End If
        resultValue Or= CULng(byteValue) Shl (byteIndex * 8)
    Next
    Return resultValue
End Function


Private Function pitchTranscribe_LoadFile( _
    ByVal filename As String, _
    ByRef binaryData As String, _
    ByRef errorText As String _
) As Integer
    binaryData = ""
    errorText = ""

    Dim As Integer fileNumber = FreeFile()
    If Open(filename For Binary Access Read As #fileNumber) <> 0 Then
        errorText = "The microphone WAV could not be opened."
        Return 0
    End If

    Dim As LongInt fileLength = LOF(fileNumber)
    If fileLength < 44 OrElse _
        CULngInt(fileLength) > PITCH_TRANSCRIBE_MAX_FILE_BYTES Then
        Close #fileNumber
        errorText = "The microphone WAV size is outside the supported range."
        Return 0
    End If

    binaryData = Space(CInt(fileLength))
    If binaryFile_ReadExact(fileNumber, 1, StrPtr(binaryData), _
        Len(binaryData)) = 0 Then
        Close #fileNumber
        binaryData = ""
        errorText = "The microphone WAV could not be read completely."
        Return 0
    End If
    Close #fileNumber
    Return -1
End Function


Private Function pitchTranscribe_PcmSample( _
    ByRef binaryData As String, _
    ByVal dataOffset As ULongInt, _
    ByVal frameIndex As ULongInt, _
    ByVal channelIndex As Integer, _
    ByVal channelCount As Integer, _
    ByVal bitsPerSample As Integer _
) As Double
    Dim As ULongInt bytesPerSample = CULngInt(bitsPerSample \ 8)
    Dim As ULongInt sampleOffset = dataOffset + _
        (frameIndex * CULngInt(channelCount) + CULngInt(channelIndex)) * _
        bytesPerSample

    If bitsPerSample = 8 Then
        Dim As Integer sampleValue = pitchTranscribe_ReadByte( _
            binaryData, sampleOffset)
        If sampleValue < 0 Then
            Return 0.0
        End If
        Return (CDbl(sampleValue) - 128.0) / 128.0
    End If

    Dim As Long sampleValue = CLng(pitchTranscribe_ReadLe16( _
        binaryData, sampleOffset))
    If sampleValue >= 32768 Then
        sampleValue -= 65536
    End If
    Return CDbl(sampleValue) / 32768.0
End Function


Private Function pitchTranscribe_DecodePcm( _
    ByRef binaryData As String, _
    ByVal dataOffset As ULongInt, _
    ByVal dataBytes As ULongInt, _
    ByVal sourceSampleRate As Integer, _
    ByVal channelCount As Integer, _
    ByVal bitsPerSample As Integer, _
    analysisSamples() As Single, _
    ByRef analysisSampleCount As Integer, _
    ByRef analysisSampleRate As Integer _
) As Integer
    Dim As ULongInt bytesPerFrame = CULngInt(channelCount) * _
        CULngInt(bitsPerSample \ 8)
    If bytesPerFrame = 0 Then
        Return 0
    End If
    Dim As ULongInt sourceFrameCount = dataBytes \ bytesPerFrame
    If sourceFrameCount < PITCH_FRAME_SAMPLES Then
        Return 0
    End If

    analysisSampleRate = sourceSampleRate
    If analysisSampleRate > PITCH_TARGET_SAMPLE_RATE Then
        analysisSampleRate = PITCH_TARGET_SAMPLE_RATE
    End If
    Dim As ULongInt targetCount64 = (sourceFrameCount * _
        CULngInt(analysisSampleRate)) \ CULngInt(sourceSampleRate)
    If targetCount64 < PITCH_FRAME_SAMPLES OrElse _
        targetCount64 > CULngInt(&H7FFFFFFF) Then
        Return 0
    End If
    analysisSampleCount = CInt(targetCount64)
    ReDim analysisSamples(0 To analysisSampleCount - 1)

    ' Each target sample averages the complete source interval assigned to it.
    ' This provides a small anti-alias filter when a 44.1/48 kHz microphone is
    ' reduced to the 16 kHz analysis rate.
    For targetIndex As Integer = 0 To analysisSampleCount - 1
        Dim As ULongInt sourceStart = (CULngInt(targetIndex) * _
            CULngInt(sourceSampleRate)) \ CULngInt(analysisSampleRate)
        Dim As ULongInt sourceEnd = (CULngInt(targetIndex + 1) * _
            CULngInt(sourceSampleRate)) \ CULngInt(analysisSampleRate)
        If sourceEnd <= sourceStart Then
            sourceEnd = sourceStart + 1
        End If
        If sourceEnd > sourceFrameCount Then
            sourceEnd = sourceFrameCount
        End If

        Dim As Double sampleTotal
        Dim As ULongInt contributingSamples
        For sourceIndex As ULongInt = sourceStart To sourceEnd - 1
            For channelIndex As Integer = 0 To channelCount - 1
                sampleTotal += pitchTranscribe_PcmSample( _
                    binaryData, dataOffset, sourceIndex, channelIndex, _
                    channelCount, bitsPerSample)
                contributingSamples += 1
            Next
        Next
        If contributingSamples > 0 Then
            analysisSamples(targetIndex) = CSng(sampleTotal / _
                CDbl(contributingSamples))
        End If
    Next
    Return -1
End Function


' -------------------------------------------------------------------------
' Frame pitch estimation
' -------------------------------------------------------------------------

Private Function pitchTranscribe_Correlation( _
    samples() As Single, _
    ByVal frameStart As Integer, _
    ByVal lag As Integer, _
    ByVal sampleStep As Integer, _
    ByVal frameMean As Double _
) As Double
    Dim As Double crossTotal
    Dim As Double firstEnergy
    Dim As Double secondEnergy
    Dim As Integer lastSample = PITCH_FRAME_SAMPLES - lag - 1
    If lastSample < 1 Then
        Return 0.0
    End If

    For sampleIndex As Integer = 0 To lastSample Step sampleStep
        Dim As Double firstValue = CDbl(samples(frameStart + sampleIndex)) - _
            frameMean
        Dim As Double secondValue = _
            CDbl(samples(frameStart + sampleIndex + lag)) - frameMean
        crossTotal += firstValue * secondValue
        firstEnergy += firstValue * firstValue
        secondEnergy += secondValue * secondValue
    Next
    If firstEnergy <= 0.0 OrElse secondEnergy <= 0.0 Then
        Return 0.0
    End If
    Return crossTotal / Sqr(firstEnergy * secondEnergy)
End Function


Private Function pitchTranscribe_FramePitch( _
    samples() As Single, _
    ByVal frameStart As Integer, _
    ByVal sampleRate As Integer, _
    ByRef config As PitchTranscribeConfig, _
    ByRef keyNumber As Integer, _
    ByRef confidence As Single, _
    ByRef frameRms As Single _
) As Integer
    keyNumber = -1
    confidence = 0.0
    frameRms = 0.0

    Dim As Double frameMean
    For sampleIndex As Integer = 0 To PITCH_FRAME_SAMPLES - 1
        frameMean += samples(frameStart + sampleIndex)
    Next
    frameMean /= CDbl(PITCH_FRAME_SAMPLES)

    Dim As Double energyTotal
    For sampleIndex As Integer = 0 To PITCH_FRAME_SAMPLES - 1
        Dim As Double centeredSample = _
            CDbl(samples(frameStart + sampleIndex)) - frameMean
        energyTotal += centeredSample * centeredSample
    Next
    frameRms = CSng(Sqr(energyTotal / CDbl(PITCH_FRAME_SAMPLES)))
    If frameRms < config.silenceThreshold Then
        Return 0
    End If

    ' fblint: disable-next-line FBL404 REASON: Fix and CInt make truncation toward zero explicit.
    Dim As Integer minimumLag = CInt(Fix(CDbl(sampleRate) / _
        config.maximumFrequency))
    ' fblint: disable-next-line FBL404 REASON: adding one half then Fix explicitly rounds the positive lag.
    Dim As Integer maximumLag = CInt(Fix(CDbl(sampleRate) / _
        config.minimumFrequency + 0.5))
    If minimumLag < 2 Then
        minimumLag = 2
    End If
    If maximumLag > PITCH_FRAME_SAMPLES \ 2 Then
        maximumLag = PITCH_FRAME_SAMPLES \ 2
    End If
    If maximumLag <= minimumLag Then
        Return 0
    End If

    Dim As Integer bestLag = -1
    Dim As Double bestScore = -1.0
    For lag As Integer = minimumLag To maximumLag Step 2
        Dim As Double score = pitchTranscribe_Correlation( _
            samples(), frameStart, lag, PITCH_COARSE_SAMPLE_STEP, frameMean)
        If score > bestScore + 0.002 OrElse _
            (Abs(score - bestScore) <= 0.002 AndAlso _
            (bestLag < 0 OrElse lag < bestLag)) Then
            bestScore = score
            bestLag = lag
        End If
    Next
    If bestLag < 0 Then
        Return 0
    End If

    Dim As Integer refineStart = bestLag - 3
    Dim As Integer refineEnd = bestLag + 3
    If refineStart < minimumLag Then
        refineStart = minimumLag
    End If
    If refineEnd > maximumLag Then
        refineEnd = maximumLag
    End If
    For lag As Integer = refineStart To refineEnd
        Dim As Double score = pitchTranscribe_Correlation( _
            samples(), frameStart, lag, 1, frameMean)
        If score > bestScore + 0.002 OrElse _
            (Abs(score - bestScore) <= 0.002 AndAlso lag < bestLag) Then
            bestScore = score
            bestLag = lag
        End If
    Next

    ' Autocorrelation can prefer an exact multiple of the real period. A
    ' shorter divisor is accepted only when it has almost the same normalized
    ' agreement. The check repeats because a clean tone can favor four periods
    ' before it reaches the fundamental period.
    Dim As Integer periodReduced
    Do
        periodReduced = 0
        For divisor As Integer = 3 To 2 Step -1
            ' fblint: disable-next-line FBL404 REASON: adding one half then Fix explicitly rounds the positive lag.
            Dim As Integer dividedLag = CInt(Fix(CDbl(bestLag) / _
                CDbl(divisor) + 0.5))
            If dividedLag < minimumLag OrElse dividedLag >= bestLag Then
                Continue For
            End If
            Dim As Double dividedScore = pitchTranscribe_Correlation( _
                samples(), frameStart, dividedLag, 1, frameMean)
            If dividedScore >= bestScore * 0.94 Then
                bestLag = dividedLag
                bestScore = dividedScore
                periodReduced = -1
                Exit For
            End If
        Next
    Loop While periodReduced <> 0

    If bestScore < config.correlationThreshold Then
        Return 0
    End If
    Dim As Double frequency = CDbl(sampleRate) / CDbl(bestLag)
    If frequency < config.minimumFrequency OrElse _
        frequency > config.maximumFrequency Then
        Return 0
    End If
    Dim As Double midiValue = 69.0 + 12.0 * _
        (Log(frequency / 440.0) / Log(2.0))
    keyNumber = CInt(Fix(midiValue + 0.5))
    If keyNumber < 0 OrElse keyNumber > 127 Then
        keyNumber = -1
        Return 0
    End If
    confidence = CSng(bestScore)
    Return -1
End Function


Private Sub pitchTranscribe_SortFive( _
    values() As Integer, _
    ByVal valueCount As Integer _
)
    For outerIndex As Integer = 1 To valueCount - 1
        Dim As Integer currentValue = values(outerIndex)
        Dim As Integer innerIndex = outerIndex - 1
        While innerIndex >= 0 AndAlso values(innerIndex) > currentValue
            values(innerIndex + 1) = values(innerIndex)
            innerIndex -= 1
        Wend
        values(innerIndex + 1) = currentValue
    Next
End Sub


Private Sub pitchTranscribe_StabilizeFrames( _
    rawKeys() As Integer, _
    ByVal frameCount As Integer, _
    stableKeys() As Integer _
)
    ReDim stableKeys(0 To frameCount - 1)
    For frameIndex As Integer = 0 To frameCount - 1
        Dim As Integer neighborhood(0 To 4)
        Dim As Integer neighborhoodCount
        For neighborIndex As Integer = frameIndex - 2 To frameIndex + 2
            If neighborIndex >= 0 AndAlso neighborIndex < frameCount AndAlso _
                rawKeys(neighborIndex) >= 0 Then
                neighborhood(neighborhoodCount) = rawKeys(neighborIndex)
                neighborhoodCount += 1
            End If
        Next
        If neighborhoodCount >= 3 Then
            pitchTranscribe_SortFive neighborhood(), neighborhoodCount
            stableKeys(frameIndex) = neighborhood(neighborhoodCount \ 2)
        Else
            stableKeys(frameIndex) = rawKeys(frameIndex)
        End If
    Next

    ' Bridge only short silent gaps whose surrounding pitch agrees exactly.
    Dim As Integer gapStart = -1
    For frameIndex As Integer = 0 To frameCount
        Dim As Integer currentKey = -2
        If frameIndex < frameCount Then
            currentKey = stableKeys(frameIndex)
        End If
        If currentKey < 0 AndAlso gapStart < 0 Then
            gapStart = frameIndex
        ElseIf currentKey >= 0 AndAlso gapStart >= 0 Then
            Dim As Integer gapLength = frameIndex - gapStart
            If gapLength <= PITCH_GAP_BRIDGE_FRAMES AndAlso gapStart > 0 AndAlso _
                stableKeys(gapStart - 1) = currentKey Then
                For fillIndex As Integer = gapStart To frameIndex - 1
                    stableKeys(fillIndex) = currentKey
                Next
            End If
            gapStart = -1
        End If
    Next
End Sub


' -------------------------------------------------------------------------
' Public transcription interface
' -------------------------------------------------------------------------

Public Sub pitchTranscribe_DefaultConfig(ByRef config As PitchTranscribeConfig)
    config.minimumFrequency = PITCH_DEFAULT_MINIMUM_FREQUENCY
    config.maximumFrequency = PITCH_DEFAULT_MAXIMUM_FREQUENCY
    config.silenceThreshold = PITCH_DEFAULT_SILENCE_THRESHOLD
    config.correlationThreshold = PITCH_DEFAULT_CORRELATION_THRESHOLD
    config.minimumNoteMilliseconds = PITCH_DEFAULT_MINIMUM_NOTE_MS
End Sub


Public Sub pitchTranscribe_Clear()
    pitchTranscribe_NoteCount = 0
    Dim As PitchTranscribedNote emptyNote
    For noteIndex As Integer = 0 To PITCH_TRANSCRIBE_MAX_NOTES - 1
        pitchTranscribe_Notes(noteIndex) = emptyNote
    Next
End Sub


Public Function pitchTranscribe_GetNoteCount() As Integer
    Return pitchTranscribe_NoteCount
End Function


Public Function pitchTranscribe_GetNote( _
    ByVal noteIndex As Integer, _
    ByRef transcribedNote As PitchTranscribedNote _
) As Integer
    Dim As PitchTranscribedNote emptyNote
    transcribedNote = emptyNote
    If noteIndex < 0 OrElse noteIndex >= pitchTranscribe_NoteCount Then
        Return 0
    End If
    transcribedNote = pitchTranscribe_Notes(noteIndex)
    Return -1
End Function


Public Function pitchTranscribe_AnalyzeWave( _
    ByVal filename As String, _
    ByRef config As PitchTranscribeConfig, _
    ByRef summary As PitchTranscribeSummary _
) As Integer
    Dim As PitchTranscribeSummary emptySummary
    summary = emptySummary
    pitchTranscribe_Clear()

    ' Ordered range comparisons do not reject NaN. Check each floating setting
    ' before it can reach the lag conversion or bypass a confidence threshold.
    If config.minimumFrequency <> config.minimumFrequency OrElse _
        config.maximumFrequency <> config.maximumFrequency OrElse _
        config.silenceThreshold <> config.silenceThreshold OrElse _
        config.correlationThreshold <> config.correlationThreshold OrElse _
        config.minimumFrequency < PITCH_CONFIG_MINIMUM_FREQUENCY OrElse _
        config.maximumFrequency <= config.minimumFrequency OrElse _
        config.maximumFrequency > PITCH_CONFIG_MAXIMUM_FREQUENCY OrElse _
        config.silenceThreshold <= 0.0 OrElse config.silenceThreshold >= 1.0 OrElse _
        config.correlationThreshold <= 0.0 OrElse _
        config.correlationThreshold >= 1.0 OrElse _
        config.minimumNoteMilliseconds < PITCH_CONFIG_MINIMUM_NOTE_MS OrElse _
        config.minimumNoteMilliseconds > PITCH_CONFIG_MAXIMUM_NOTE_MS Then
        summary.errorText = "Pitch-analysis settings are outside their supported ranges."
        Return 0
    End If

    Dim As String binaryData
    If pitchTranscribe_LoadFile(filename, binaryData, summary.errorText) = 0 Then
        Return 0
    End If
    If Left(binaryData, 4) <> "RIFF" OrElse Mid(binaryData, 9, 4) <> "WAVE" Then
        summary.errorText = "The microphone recording is not a RIFF/WAVE file."
        Return 0
    End If

    Dim As Integer audioFormat
    Dim As Integer channelCount
    Dim As Integer sourceSampleRate
    Dim As Integer bitsPerSample
    Dim As Integer formatFound
    Dim As ULong byteRate
    Dim As Integer blockAlign
    Dim As ULongInt dataOffset
    Dim As ULongInt dataBytes
    Dim As ULongInt cursor = 12
    Dim As ULongInt fileLength = CULngInt(Len(binaryData))
    If CULngInt(pitchTranscribe_ReadLe32(binaryData, 4)) + 8 <> fileLength Then
        summary.errorText = "The microphone WAV has an inconsistent RIFF length."
        Return 0
    End If
    While cursor < fileLength
        If fileLength - cursor < 8 Then
            summary.errorText = "The microphone WAV contains a truncated chunk header."
            Return 0
        End If
        Dim As String chunkId = Mid(binaryData, CInt(cursor) + 1, 4)
        Dim As ULongInt chunkLength = pitchTranscribe_ReadLe32( _
            binaryData, cursor + 4)
        Dim As ULongInt payloadOffset = cursor + 8
        If payloadOffset > fileLength OrElse chunkLength > fileLength - payloadOffset Then
            summary.errorText = "The microphone WAV contains a truncated chunk."
            Return 0
        End If

        If chunkId = "fmt " Then
            If formatFound <> 0 OrElse chunkLength < PITCH_WAV_FMT_MINIMUM_BYTES Then
                summary.errorText = "The microphone WAV has an invalid or duplicate format chunk."
                Return 0
            End If
            formatFound = -1
            audioFormat = CInt(pitchTranscribe_ReadLe16(binaryData, payloadOffset))
            channelCount = CInt(pitchTranscribe_ReadLe16(binaryData, _
                payloadOffset + PITCH_WAV_FMT_CHANNEL_OFFSET))
            sourceSampleRate = CInt(pitchTranscribe_ReadLe32(binaryData, _
                payloadOffset + PITCH_WAV_FMT_SAMPLE_RATE_OFFSET))
            byteRate = pitchTranscribe_ReadLe32(binaryData, _
                payloadOffset + PITCH_WAV_FMT_BYTE_RATE_OFFSET)
            blockAlign = CInt(pitchTranscribe_ReadLe16(binaryData, _
                payloadOffset + PITCH_WAV_FMT_BLOCK_ALIGN_OFFSET))
            bitsPerSample = CInt(pitchTranscribe_ReadLe16(binaryData, _
                payloadOffset + PITCH_WAV_FMT_BITS_OFFSET))
        ElseIf chunkId = "data" AndAlso dataBytes = 0 Then
            dataOffset = payloadOffset
            dataBytes = chunkLength
        End If

        Dim As ULongInt paddedLength = chunkLength
        If (paddedLength And &H1) <> 0 Then
            paddedLength += 1
        End If
        If paddedLength > fileLength - payloadOffset Then
            summary.errorText = "The microphone WAV is missing chunk padding."
            Return 0
        End If
        cursor = payloadOffset + paddedLength
    Wend

    If audioFormat <> 1 OrElse channelCount < 1 OrElse channelCount > 2 OrElse _
        sourceSampleRate < 8000 OrElse sourceSampleRate > 192000 OrElse _
        (bitsPerSample <> 8 AndAlso bitsPerSample <> 16) OrElse dataBytes = 0 Then
        summary.errorText = "Pitch transcription requires mono/stereo 8-bit or 16-bit PCM WAV audio."
        Return 0
    End If

    Dim As ULongInt bytesPerFrame = CULngInt(channelCount) * _
        CULngInt(bitsPerSample \ 8)
    ' Reject incomplete frames and contradictory PCM metadata before decoding.
    ' Otherwise a damaged recording can produce plausible but incorrect notes.
    If CULngInt(blockAlign) <> bytesPerFrame OrElse _
        CULngInt(byteRate) <> CULngInt(sourceSampleRate) * bytesPerFrame OrElse _
        (dataBytes Mod bytesPerFrame) <> 0 Then
        summary.errorText = "The microphone WAV has inconsistent PCM frame sizes."
        Return 0
    End If
    Dim As ULongInt sourceFrames = dataBytes \ bytesPerFrame
    Dim As ULongInt durationMilliseconds64 = (sourceFrames * 1000) \ _
        CULngInt(sourceSampleRate)
    If durationMilliseconds64 = 0 OrElse _
        durationMilliseconds64 > PITCH_TRANSCRIBE_MAX_MILLISECONDS Then
        summary.errorText = "Microphone transcription is limited to 120 seconds per take."
        Return 0
    End If

    summary.sourceSampleRate = sourceSampleRate
    summary.channelCount = channelCount
    summary.bitsPerSample = bitsPerSample
    summary.durationMilliseconds = CULng(durationMilliseconds64)

    Dim As Single analysisSamples()
    Dim As Integer analysisSampleCount
    If pitchTranscribe_DecodePcm(binaryData, dataOffset, dataBytes, _
        sourceSampleRate, channelCount, bitsPerSample, analysisSamples(), _
        analysisSampleCount, summary.analysisSampleRate) = 0 Then
        summary.errorText = "The microphone WAV does not contain enough PCM audio."
        Return 0
    End If

    summary.frameCount = ((analysisSampleCount - PITCH_FRAME_SAMPLES) \ _
        PITCH_HOP_SAMPLES) + 1
    If summary.frameCount < 1 Then
        summary.errorText = "The microphone WAV is too short for pitch analysis."
        Return 0
    End If

    Dim As Integer rawKeys()
    Dim As Single frameConfidence()
    Dim As Single frameRms()
    ReDim rawKeys(0 To summary.frameCount - 1)
    ReDim frameConfidence(0 To summary.frameCount - 1)
    ReDim frameRms(0 To summary.frameCount - 1)
    For frameIndex As Integer = 0 To summary.frameCount - 1
        Dim As Integer frameStart = frameIndex * PITCH_HOP_SAMPLES
        If pitchTranscribe_FramePitch(analysisSamples(), frameStart, _
            summary.analysisSampleRate, config, rawKeys(frameIndex), _
            frameConfidence(frameIndex), frameRms(frameIndex)) <> 0 Then
            summary.voicedFrameCount += 1
        End If
    Next

    Dim As Integer stableKeys()
    pitchTranscribe_StabilizeFrames rawKeys(), summary.frameCount, stableKeys()

    Dim As Integer runStart = 0
    While runStart < summary.frameCount
        If stableKeys(runStart) < 0 Then
            runStart += 1
            Continue While
        End If
        Dim As Integer runKey = stableKeys(runStart)
        Dim As Integer runEnd = runStart
        Dim As Double confidenceTotal
        Dim As Double rmsTotal
        Dim As Integer confidenceCount
        While runEnd < summary.frameCount AndAlso stableKeys(runEnd) = runKey
            confidenceTotal += frameConfidence(runEnd)
            rmsTotal += frameRms(runEnd)
            confidenceCount += 1
            runEnd += 1
        Wend

        Dim As ULong runStartMilliseconds = CULng((CULngInt(runStart) * _
            PITCH_HOP_SAMPLES * 1000) \ CULngInt(summary.analysisSampleRate))
        Dim As ULong runEndMilliseconds = CULng((CULngInt(runEnd) * _
            PITCH_HOP_SAMPLES * 1000) \ CULngInt(summary.analysisSampleRate))
        Dim As ULong runDuration = runEndMilliseconds - runStartMilliseconds
        If runDuration >= config.minimumNoteMilliseconds Then
            If pitchTranscribe_NoteCount >= PITCH_TRANSCRIBE_MAX_NOTES Then
                summary.errorText = "The microphone take exceeds the note capacity."
                pitchTranscribe_Clear()
                Return 0
            End If

            Dim As PitchTranscribedNote transcribedNote
            transcribedNote.startMilliseconds = runStartMilliseconds
            transcribedNote.durationMilliseconds = runDuration
            transcribedNote.keyNumber = CUByte(runKey)
            If confidenceCount > 0 Then
                transcribedNote.confidence = CSng(confidenceTotal / _
                    CDbl(confidenceCount))
                ' fblint: disable-next-line FBL404 REASON: Fix and CInt explicitly truncate the positive RMS scale.
                Dim As Integer velocityValue = PITCH_VELOCITY_BASE + _
                    CInt(Fix((rmsTotal / CDbl(confidenceCount)) * _
                    PITCH_VELOCITY_RMS_SCALE))
                If velocityValue < 1 Then
                    velocityValue = 1
                End If
                If velocityValue > 127 Then
                    velocityValue = 127
                End If
                transcribedNote.velocity = CUByte(velocityValue)
            Else
                transcribedNote.velocity = 80
            End If

            ' Merge repeated estimates of the same tone across a short break.
            If pitchTranscribe_NoteCount > 0 Then
                Dim As PitchTranscribedNote Ptr previousNote = _
                    @pitchTranscribe_Notes(pitchTranscribe_NoteCount - 1)
                Dim As ULong previousEnd = previousNote->startMilliseconds + _
                    previousNote->durationMilliseconds
                If previousNote->keyNumber = transcribedNote.keyNumber AndAlso _
                    transcribedNote.startMilliseconds >= previousEnd AndAlso _
                    transcribedNote.startMilliseconds - previousEnd <= 100 Then
                    previousNote->durationMilliseconds = _
                        transcribedNote.startMilliseconds + _
                        transcribedNote.durationMilliseconds - _
                        previousNote->startMilliseconds
                    runStart = runEnd
                    Continue While
                End If
            End If

            pitchTranscribe_Notes(pitchTranscribe_NoteCount) = transcribedNote
            pitchTranscribe_NoteCount += 1
        End If
        runStart = runEnd
    Wend

    summary.noteCount = pitchTranscribe_NoteCount
    Return -1
End Function

/' end of pitch_transcriber.bas '/
