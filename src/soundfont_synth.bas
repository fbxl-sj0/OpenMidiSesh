/'
    Project: OpenSesh
    ---------------------------

    File: soundfont_synth.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Implements soundfont_synth.bi; declarations there define the shared interface.

    Purpose:

        Mix SoundFont sample voices in FreeBASIC and deliver the completed mix.

    Responsibilities:

        - own a bounded realtime voice pool and its synchronization
        - interpolate SF2 sample voices at the device rate
        - apply loop, pitch-bend, envelope, attenuation, and pan parameters
        - clock the ordinary sfxlib mixer before adding SoundFont voices
        - submit one combined caller-clocked stream on every supported target

    This file intentionally does NOT contain:

        - platform audio APIs
        - SF2 file parsing
        - transport clocks or MIDI document access

    Threading and resource ownership:

        This module owns one worker thread, one mutex, and a bounded voice
        array. Every worker state flag, channel setting, and voice is accessed
        while holding the mutex. The bank remains immutable while the worker
        runs; load, unload, and shutdown join the worker before changing bank
        storage. The output lifecycle owns the raw audio stream. Shutdown sets
        the stop flag, closes the queue under sfxlib's runtime lock, joins the
        worker, and closes once more after no writer can reopen the queue.
'/

#lang "fb"

#inclib "sfx" ' fblint: disable-line FBL930 REASON: The supported FreeBASIC toolchain supplies sfx on Windows and Linux.
#include once "sfxlib_raw.bi"
#include once "soundfont_synth.bi"
#include once "soundfont_bank.bi"

Const SOUNDFONT_SYNTH_CHANNEL_COUNT As Integer = 16
Const SOUNDFONT_SYNTH_VOICE_COUNT As Integer = 128
Const SOUNDFONT_SYNTH_BLOCK_FRAMES As Integer = 256
Const SOUNDFONT_SYNTH_START_TIMEOUT_SECONDS As Double = 3.0
Const SOUNDFONT_SYNTH_MAX_DURATION_SECONDS As Single = 3600.0

Const SOUNDFONT_ENVELOPE_ATTACK As Integer = 0
Const SOUNDFONT_ENVELOPE_HOLD As Integer = 1
Const SOUNDFONT_ENVELOPE_DECAY As Integer = 2
Const SOUNDFONT_ENVELOPE_SUSTAIN As Integer = 3
Const SOUNDFONT_ENVELOPE_RELEASE As Integer = 4

/'
    Shared mixer bridge

    Raw output is exclusive by design. While a SoundFont is selected, this
    worker becomes the one output clock. It asks sfxlib to render its ordinary
    tones, WAV clips, MIDI fallback, and effects into the existing mix buffer,
    then adds FreeBASIC sample voices before writing the completed block. The
    runtime lock is the same lock used by sfxlib commands on the UI thread.
'/
Declare Sub fb_sfxRuntimeLock CDecl Alias "fb_sfxRuntimeLock" ()
Declare Sub fb_sfxRuntimeUnlock CDecl Alias "fb_sfxRuntimeUnlock" ()
Declare Sub fb_sfxMixerProcess CDecl Alias "fb_sfxMixerProcess" ( _
    ByVal frames As Integer _
)
Declare Function fb_sfxMixBufferRead CDecl Alias "fb_sfxMixBufferRead" ( _
    ByVal samples As Single Ptr, _
    ByVal frames As Integer _
) As Integer
Declare Function fb_sfxBufferFrames CDecl Alias "fb_sfxBufferFrames" () As Integer

' fblint: disable-next-line FBL911,FBL014 REASON: This is an in-memory record; its fields are not a raw on-disk UDT layout.
Type SoundFontSynthVoice
    As Integer active
    As Integer channelIndex
    As Integer keyNumber
    As Integer exclusiveClass
    As OseSoundFontVoiceRegion region
    As Double samplePosition
    As Double sampleIncrement
    As ULongInt noteFramesRemaining
    As Integer envelopeStage
    As ULongInt envelopeFrame
    As ULongInt attackFrames
    As ULongInt holdFrames
    As ULongInt decayFrames
    As ULongInt releaseFrames
    As Single envelopeLevel
    As Single releaseStartLevel
    As Single velocityGain
    As ULongInt serialNumber
End Type

' fblint: disable-next-line FBL301 REASON: the synth mutex protects all following realtime state.
Dim Shared soundfontSynth_Mutex As Any Ptr
' fblint: disable-next-line FBL301 REASON: the worker handle is owned by this module's output lifecycle.
Dim Shared soundfontSynth_Thread As Any Ptr
' fblint: disable-next-line FBL301 REASON: the worker state is read only while holding the synth mutex.
Dim Shared soundfontSynth_WorkerState As Integer
' fblint: disable-next-line FBL301 REASON: the stop flag is read only while holding the synth mutex.
Dim Shared soundfontSynth_StopRequested As Integer
' fblint: disable-next-line FBL301 REASON: the pause flag belongs to the process-wide SoundFont engine.
Dim Shared soundfontSynth_Paused As Integer
' fblint: disable-next-line FBL301 REASON: the negotiated sample rate belongs to the current raw stream.
Dim Shared soundfontSynth_SampleRate As Integer
' fblint: disable-next-line FBL301 REASON: this bounded array is the module-owned realtime voice pool.
Dim Shared soundfontSynth_Voices( _
    0 To SOUNDFONT_SYNTH_VOICE_COUNT - 1 _
) As SoundFontSynthVoice
' fblint: disable-next-line FBL301 REASON: channel automation is shared with active voices under the mutex.
Dim Shared soundfontSynth_ChannelGain( _
    0 To SOUNDFONT_SYNTH_CHANNEL_COUNT - 1 _
) As Single
' fblint: disable-next-line FBL301 REASON: channel pan follows the same protected automation state.
Dim Shared soundfontSynth_ChannelPan( _
    0 To SOUNDFONT_SYNTH_CHANNEL_COUNT - 1 _
) As Single
' fblint: disable-next-line FBL301 REASON: serials provide deterministic oldest-voice stealing.
Dim Shared soundfontSynth_NextSerial As ULongInt = 1

' Thread synchronization: the synth mutex locks every shared field above.

' -------------------------------------------------------------------------
' Synchronization and numeric helpers
' -------------------------------------------------------------------------

Private Function soundfontSynth_EnsureMutex() As Integer
    If soundfontSynth_Mutex <> 0 Then
        Return -1
    End If
    soundfontSynth_Mutex = MutexCreate()
    If soundfontSynth_Mutex = 0 Then
        Return 0
    End If
    For channelIndex As Integer = 0 To SOUNDFONT_SYNTH_CHANNEL_COUNT - 1
        soundfontSynth_ChannelGain(channelIndex) = 1.0
        soundfontSynth_ChannelPan(channelIndex) = 0.0
    Next
    Return -1
End Function


Private Function soundfontSynth_ClampSample(ByVal sampleValue As Single) As Single
    If sampleValue < -1.0 Then
        Return -1.0
    End If
    If sampleValue > 1.0 Then
        Return 1.0
    End If
    Return sampleValue
End Function


Private Function soundfontSynth_BoundedFrames( _
    ByVal durationSeconds As Single, _
    ByVal sampleRate As Integer _
) As ULongInt
    If durationSeconds <= 0.0 OrElse sampleRate <= 0 Then
        Return 0
    End If
    Dim As Double exactFrames = CDbl(durationSeconds) * CDbl(sampleRate)
    If exactFrames < 1.0 Then
        Return 1
    End If
    If exactFrames > 4294967295.0 Then
        Return 4294967295
    End If
    Return CULngInt(Int(exactFrames + 0.5))
End Function


Private Function soundfontSynth_ElapsedSeconds( _
    ByVal startClock As Double _
) As Double
' Timer wraps at midnight; the following branch repairs that one-day wrap.
    Dim As Double elapsedSeconds = Timer - startClock
    If elapsedSeconds < 0.0 Then
        elapsedSeconds += 86400.0
    End If
    Return elapsedSeconds
End Function

' -------------------------------------------------------------------------
' Voice lifecycle
' -------------------------------------------------------------------------

Private Sub soundfontSynth_ClearVoice(ByRef voiceState As SoundFontSynthVoice)
    Dim As SoundFontSynthVoice emptyVoice
    voiceState = emptyVoice
End Sub


Private Sub soundfontSynth_BeginRelease(ByRef voiceState As SoundFontSynthVoice)
    If voiceState.active = 0 OrElse _
        voiceState.envelopeStage = SOUNDFONT_ENVELOPE_RELEASE Then
        Exit Sub
    End If
    voiceState.envelopeStage = SOUNDFONT_ENVELOPE_RELEASE
    voiceState.envelopeFrame = 0
    voiceState.releaseStartLevel = voiceState.envelopeLevel
    If voiceState.releaseFrames = 0 Then
        soundfontSynth_ClearVoice voiceState
    End If
End Sub


Private Function soundfontSynth_AllocateVoice() As Integer
    For voiceIndex As Integer = 0 To SOUNDFONT_SYNTH_VOICE_COUNT - 1
        If soundfontSynth_Voices(voiceIndex).active = 0 Then
            Return voiceIndex
        End If
    Next
    Dim As Integer oldestIndex
    Dim As ULongInt oldestSerial = soundfontSynth_Voices(0).serialNumber
    For voiceIndex As Integer = 1 To SOUNDFONT_SYNTH_VOICE_COUNT - 1
        If soundfontSynth_Voices(voiceIndex).serialNumber < oldestSerial Then
            oldestIndex = voiceIndex
            oldestSerial = soundfontSynth_Voices(voiceIndex).serialNumber
        End If
    Next
    Return oldestIndex
End Function


Private Sub soundfontSynth_AdvanceEnvelope(ByRef voiceState As SoundFontSynthVoice)
    Select Case voiceState.envelopeStage
        Case SOUNDFONT_ENVELOPE_ATTACK
            If voiceState.attackFrames = 0 Then
                voiceState.envelopeLevel = 1.0
                voiceState.envelopeStage = SOUNDFONT_ENVELOPE_HOLD
                voiceState.envelopeFrame = 0
            Else
                voiceState.envelopeLevel = CSng(voiceState.envelopeFrame + 1) / _
                    CSng(voiceState.attackFrames)
                voiceState.envelopeFrame += 1
                If voiceState.envelopeFrame >= voiceState.attackFrames Then
                    voiceState.envelopeLevel = 1.0
                    voiceState.envelopeStage = SOUNDFONT_ENVELOPE_HOLD
                    voiceState.envelopeFrame = 0
                End If
            End If
        Case SOUNDFONT_ENVELOPE_HOLD
            voiceState.envelopeLevel = 1.0
            voiceState.envelopeFrame += 1
            If voiceState.envelopeFrame >= voiceState.holdFrames Then
                voiceState.envelopeStage = SOUNDFONT_ENVELOPE_DECAY
                voiceState.envelopeFrame = 0
            End If
        Case SOUNDFONT_ENVELOPE_DECAY
            If voiceState.decayFrames = 0 Then
                voiceState.envelopeLevel = voiceState.region.sustainLevel
                voiceState.envelopeStage = SOUNDFONT_ENVELOPE_SUSTAIN
                voiceState.envelopeFrame = 0
            Else
                Dim As Single decayRatio = CSng(voiceState.envelopeFrame + 1) / _
                    CSng(voiceState.decayFrames)
                voiceState.envelopeLevel = 1.0 - _
                    (1.0 - voiceState.region.sustainLevel) * decayRatio
                voiceState.envelopeFrame += 1
                If voiceState.envelopeFrame >= voiceState.decayFrames Then
                    voiceState.envelopeLevel = voiceState.region.sustainLevel
                    voiceState.envelopeStage = SOUNDFONT_ENVELOPE_SUSTAIN
                    voiceState.envelopeFrame = 0
                End If
            End If
        Case SOUNDFONT_ENVELOPE_SUSTAIN
            voiceState.envelopeLevel = voiceState.region.sustainLevel
        Case SOUNDFONT_ENVELOPE_RELEASE
            If voiceState.releaseFrames = 0 OrElse _
                voiceState.envelopeFrame >= voiceState.releaseFrames Then
                soundfontSynth_ClearVoice voiceState
            Else
                voiceState.envelopeLevel = voiceState.releaseStartLevel * _
                    (1.0 - CSng(voiceState.envelopeFrame + 1) / _
                    CSng(voiceState.releaseFrames))
                voiceState.envelopeFrame += 1
                If voiceState.envelopeFrame >= voiceState.releaseFrames OrElse _
                    voiceState.envelopeLevel <= 0.00001 Then
                    soundfontSynth_ClearVoice voiceState
                End If
            End If
        Case Else
            ' A corrupted stage must silence the voice rather than read on forever.
            soundfontSynth_ClearVoice voiceState
    End Select
End Sub


Private Function soundfontSynth_ReadInterpolated( _
    ByVal sampleData As Short Ptr, _
    ByVal sampleStart As ULongInt, _
    ByVal sampleEnd As ULongInt, _
    ByVal samplePosition As Double _
) As Single
    If sampleData = 0 OrElse sampleStart >= sampleEnd OrElse _
        samplePosition < 0.0 Then
        Return 0.0
    End If
    Dim As ULongInt wholePosition = CULngInt(Int(samplePosition))
    Dim As ULongInt firstIndex = sampleStart + wholePosition
    If firstIndex >= sampleEnd Then
        Return 0.0
    End If
    Dim As ULongInt secondIndex = firstIndex + 1
    If secondIndex >= sampleEnd Then
        secondIndex = firstIndex
    End If
    Dim As Double fraction = samplePosition - CDbl(wholePosition)
    Dim As Double firstSample = CDbl(sampleData[firstIndex]) / 32768.0
    Dim As Double secondSample = CDbl(sampleData[secondIndex]) / 32768.0
    Return CSng(firstSample + (secondSample - firstSample) * fraction)
End Function


Private Function soundfontSynth_PrepareSamplePosition( _
    ByRef voiceState As SoundFontSynthVoice _
) As Integer
    Dim As Double sampleLength = CDbl(voiceState.region.leftEnd - _
        voiceState.region.leftStart)
    Dim As Double loopStart = CDbl(voiceState.region.leftLoopStart - _
        voiceState.region.leftStart)
    Dim As Double loopEnd = CDbl(voiceState.region.leftLoopEnd - _
        voiceState.region.leftStart)
    Dim As Integer loopActive = voiceState.region.sampleModes = 1 OrElse _
        (voiceState.region.sampleModes = 3 AndAlso _
        voiceState.envelopeStage <> SOUNDFONT_ENVELOPE_RELEASE)
    If loopActive <> 0 AndAlso loopEnd > loopStart Then
        While voiceState.samplePosition >= loopEnd
            voiceState.samplePosition -= loopEnd - loopStart
        Wend
    End If
    If voiceState.samplePosition < 0.0 OrElse _
        voiceState.samplePosition >= sampleLength Then
        soundfontSynth_ClearVoice voiceState
        Return 0
    End If
    Return -1
End Function


Private Sub soundfontSynth_RenderVoices( _
    ByVal samples As Single Ptr, _
    ByVal frameCount As Integer _
)
    If samples = 0 OrElse frameCount <= 0 OrElse soundfontSynth_Paused <> 0 Then
        Exit Sub
    End If
    Dim As Short Ptr sampleData = soundfontBank_GetSampleData()
    If sampleData = 0 Then
        Exit Sub
    End If
    For frameIndex As Integer = 0 To frameCount - 1
        Dim As Single soundfontLeft
        Dim As Single soundfontRight
        For voiceIndex As Integer = 0 To SOUNDFONT_SYNTH_VOICE_COUNT - 1
            Dim As SoundFontSynthVoice Ptr voiceState = _
                @soundfontSynth_Voices(voiceIndex)
            If voiceState->active = 0 Then
                Continue For
            End If
            If voiceState->noteFramesRemaining > 0 Then
                voiceState->noteFramesRemaining -= 1
                If voiceState->noteFramesRemaining = 0 Then
                    soundfontSynth_BeginRelease *voiceState
                End If
            End If
            If voiceState->active = 0 OrElse _
                soundfontSynth_PrepareSamplePosition(*voiceState) = 0 Then
                Continue For
            End If

            Dim As Single leftSample = soundfontSynth_ReadInterpolated( _
                sampleData, voiceState->region.leftStart, _
                voiceState->region.leftEnd, voiceState->samplePosition)
            Dim As Single rightSample = soundfontSynth_ReadInterpolated( _
                sampleData, voiceState->region.rightStart, _
                voiceState->region.rightEnd, voiceState->samplePosition)
            Dim As Single channelGain = _
                soundfontSynth_ChannelGain(voiceState->channelIndex)
            Dim As Single combinedPan = voiceState->region.pan + _
                soundfontSynth_ChannelPan(voiceState->channelIndex)
            If combinedPan < -1.0 Then
                combinedPan = -1.0
            End If
            If combinedPan > 1.0 Then
                combinedPan = 1.0
            End If
            Dim As Single voiceGain = voiceState->velocityGain * channelGain * _
                voiceState->region.attenuationGain * voiceState->envelopeLevel
            soundfontLeft += leftSample * voiceGain * (1.0 - combinedPan) * 0.5
            soundfontRight += rightSample * voiceGain * (1.0 + combinedPan) * 0.5
            voiceState->samplePosition += voiceState->sampleIncrement
            soundfontSynth_AdvanceEnvelope *voiceState
        Next
        samples[frameIndex * 2] = soundfontSynth_ClampSample( _
            samples[frameIndex * 2] + soundfontLeft)
        samples[frameIndex * 2 + 1] = soundfontSynth_ClampSample( _
            samples[frameIndex * 2 + 1] + soundfontRight)
    Next
End Sub

' -------------------------------------------------------------------------
' Combined output worker
' -------------------------------------------------------------------------

Private Sub soundfontSynth_SetWorkerState(ByVal workerState As Integer)
    If soundfontSynth_Mutex = 0 Then
        Exit Sub
    End If
    MutexLock soundfontSynth_Mutex
    soundfontSynth_WorkerState = workerState
    MutexUnlock soundfontSynth_Mutex
End Sub


Private Function soundfontSynth_ShouldStop() As Integer
    If soundfontSynth_Mutex = 0 Then
        Return -1
    End If
    MutexLock soundfontSynth_Mutex
    Dim As Integer shouldStop = soundfontSynth_StopRequested
    MutexUnlock soundfontSynth_Mutex
    Return shouldStop
End Function


' ThreadCreate requires this callback parameter.
Private Sub soundfontSynth_OutputWorker(ByVal unusedParameter As Any Ptr)
    Dim As Integer sampleRate = sfxlib.RawOpen()
    If sampleRate <= 0 Then
        soundfontSynth_SetWorkerState -1
        Exit Sub
    End If
    MutexLock soundfontSynth_Mutex
    soundfontSynth_SampleRate = sampleRate
    soundfontSynth_WorkerState = 2
    MutexUnlock soundfontSynth_Mutex

    Dim As Single outputSamples( _
        0 To SOUNDFONT_SYNTH_BLOCK_FRAMES * 2 - 1 _
    )
    Do
        If soundfontSynth_ShouldStop() <> 0 Then
            Exit Do
        End If
        Dim As Integer currentBlockFrames = fb_sfxBufferFrames()
        If currentBlockFrames <= 0 OrElse _
            currentBlockFrames > SOUNDFONT_SYNTH_BLOCK_FRAMES Then
            currentBlockFrames = SOUNDFONT_SYNTH_BLOCK_FRAMES
        End If
        fb_sfxRuntimeLock()
        fb_sfxMixerProcess currentBlockFrames
        Dim As Integer copiedFrames = fb_sfxMixBufferRead( _
            @outputSamples(0), currentBlockFrames)
        fb_sfxRuntimeUnlock()
        If copiedFrames <> currentBlockFrames Then
            For sampleIndex As Integer = 0 To currentBlockFrames * 2 - 1
                outputSamples(sampleIndex) = 0.0
            Next
        End If

        MutexLock soundfontSynth_Mutex
        soundfontSynth_RenderVoices @outputSamples(0), _
            currentBlockFrames
        MutexUnlock soundfontSynth_Mutex

        Dim As Integer writtenFrames
        While writtenFrames < currentBlockFrames
            If soundfontSynth_ShouldStop() <> 0 Then
                Exit While
            End If
            Dim As Integer writeResult = sfxlib.RawWrite( _
                @outputSamples(writtenFrames * 2), _
                currentBlockFrames - writtenFrames, 2)
            If writeResult < 0 Then
                ' fblint: disable-next-line FBL310 REASON: sfxlib_raw.bi declares the SfxLib namespace used by this call.
                sfxlib.RawClose()
                soundfontSynth_SetWorkerState -1
                Exit Sub
            ElseIf writeResult = 0 Then
                Sleep 1, 1
            Else
                writtenFrames += writeResult
            End If
        Wend
        /'
            Some platform queues can accept blocks faster than their device
            clock drains them. Yield once per block so the UI thread can take
            the synth mutex promptly for stop, pause, and note commands.
        '/
        Sleep 1, 1
    Loop
    soundfontSynth_SetWorkerState 0
End Sub


Private Function soundfontSynth_StartOutput( _
    ByRef errorText As String _
) As Integer
    errorText = ""
    If soundfontBank_IsLoaded() = 0 Then
        errorText = "No SoundFont bank is loaded."
        Return 0
    End If
    If soundfontSynth_EnsureMutex() = 0 Then
        errorText = "The SoundFont synchronization lock could not be created."
        Return 0
    End If
    MutexLock soundfontSynth_Mutex
    If soundfontSynth_WorkerState = 2 Then
        MutexUnlock soundfontSynth_Mutex
        Return -1
    End If
    MutexUnlock soundfontSynth_Mutex
    ' A stream can fail after startup. Join its old worker and release the raw
    ' queue before replacing the thread handle during a later resume attempt.
    soundfontSynth_SuspendOutput()
    MutexLock soundfontSynth_Mutex
    soundfontSynth_StopRequested = 0
    soundfontSynth_WorkerState = 1
    soundfontSynth_SampleRate = 0
    MutexUnlock soundfontSynth_Mutex

    soundfontSynth_Thread = ThreadCreate(@soundfontSynth_OutputWorker, 0)
    If soundfontSynth_Thread = 0 Then
        soundfontSynth_SetWorkerState -1
        errorText = "The SoundFont audio worker could not be created."
        Return 0
    End If

    Dim As Double startClock = Timer
    Do
        MutexLock soundfontSynth_Mutex
        Dim As Integer workerState = soundfontSynth_WorkerState
        MutexUnlock soundfontSynth_Mutex
        If workerState = 2 Then
            Return -1
        End If
        If workerState < 0 Then
            Exit Do
        End If
        If soundfontSynth_ElapsedSeconds(startClock) >= _
            SOUNDFONT_SYNTH_START_TIMEOUT_SECONDS Then
            Exit Do
        End If
        Sleep 1, 1
    Loop
    soundfontSynth_SuspendOutput()
    errorText = "The SoundFont audio stream could not be started."
    Return 0
End Function


Public Sub soundfontSynth_SuspendOutput()
    If soundfontSynth_Thread = 0 OrElse soundfontSynth_Mutex = 0 Then
        Exit Sub
    End If
    MutexLock soundfontSynth_Mutex
    soundfontSynth_StopRequested = -1
    MutexUnlock soundfontSynth_Mutex
    /'
        Closing the queue also releases a writer stalled behind a platform
        callback. RawClose uses sfxlib's runtime lock, so any in-flight write
        finishes before the queue is reset. A worker which already passed its
        stop check can still start one final RawWrite and reopen the queue.
    '/
    ' fblint: disable-next-line FBL310 REASON: RawClose is declared by the public sfxlib_raw.bi namespace.
    sfxlib.RawClose()
    ThreadWait soundfontSynth_Thread
    soundfontSynth_Thread = 0
    ' The worker has exited, so this final close also covers a write which
    ' raced the first close. Ordinary mixer output can now resume reliably.
    ' fblint: disable-next-line FBL310 REASON: sfxlib_raw.bi declares the SfxLib namespace used by this call.
    sfxlib.RawClose()
    MutexLock soundfontSynth_Mutex
    soundfontSynth_StopRequested = 0
    soundfontSynth_WorkerState = 0
    soundfontSynth_SampleRate = 0
    MutexUnlock soundfontSynth_Mutex
End Sub


Public Function soundfontSynth_ResumeOutput( _
    ByRef errorText As String _
) As Integer
    If soundfontBank_IsLoaded() = 0 Then
        errorText = ""
        Return -1
    End If
    Return soundfontSynth_StartOutput(errorText)
End Function

' -------------------------------------------------------------------------
' Public bank and note operations
' -------------------------------------------------------------------------

Public Function soundfontSynth_Load( _
    ByVal filename As String, _
    ByRef errorText As String _
) As Integer
    Dim As Integer hadBank = soundfontBank_IsLoaded()
    soundfontSynth_SuspendOutput()
    If soundfontBank_Load(filename, errorText) = 0 Then
        If hadBank <> 0 Then
            Dim As String restartError
            soundfontSynth_StartOutput restartError
        End If
        Return 0
    End If
    soundfontSynth_StopAll()
    If soundfontSynth_StartOutput(errorText) = 0 Then
        soundfontBank_Clear()
        Return 0
    End If
    Return -1
End Function


Public Sub soundfontSynth_Unload()
    soundfontSynth_SuspendOutput()
    soundfontSynth_StopAll()
    soundfontBank_Clear()
End Sub


Public Sub soundfontSynth_Shutdown()
    soundfontSynth_Unload()
    If soundfontSynth_Mutex <> 0 Then
        MutexDestroy soundfontSynth_Mutex
        soundfontSynth_Mutex = 0
    End If
End Sub


Public Function soundfontSynth_IsActive() As Integer
    If soundfontSynth_Mutex = 0 OrElse soundfontBank_IsLoaded() = 0 Then
        Return 0
    End If
    MutexLock soundfontSynth_Mutex
    Dim As Integer activeResult = IIf(soundfontSynth_WorkerState = 2, -1, 0)
    MutexUnlock soundfontSynth_Mutex
    Return activeResult
End Function


Public Function soundfontSynth_GetName() As String
    Return soundfontBank_GetName()
End Function


Public Function soundfontSynth_GetFilename() As String
    Return soundfontBank_GetFilename()
End Function


Public Function soundfontSynth_PlayMidiNote( _
    ByVal channelIndex As Integer, _
    ByVal keyNumber As Integer, _
    ByVal bankNumber As Integer, _
    ByVal programNumber As Integer, _
    ByVal pitchBend As Integer, _
    ByVal durationSeconds As Single, _
    ByRef mixValues As OsePlaybackMixValues _
) As Integer
    If soundfontSynth_IsActive() = 0 OrElse channelIndex < 0 OrElse _
        channelIndex >= SOUNDFONT_SYNTH_CHANNEL_COUNT OrElse keyNumber < 0 OrElse _
        keyNumber > 127 OrElse bankNumber < 0 OrElse bankNumber > 16383 OrElse _
        programNumber < 0 OrElse programNumber > 127 OrElse pitchBend < 0 OrElse _
        pitchBend > 16383 OrElse durationSeconds <= 0.0 OrElse _
        durationSeconds > SOUNDFONT_SYNTH_MAX_DURATION_SECONDS OrElse _
        mixValues.channelGain <= 0.0 OrElse mixValues.voiceGain <= 0.0 Then
        Return 0
    End If

    Dim As OseSoundFontVoiceRegion regions( _
        0 To OSE_SOUNDFONT_MAX_REGIONS_PER_NOTE - 1 _
    )
    Dim As Double velocityRatio = CDbl(mixValues.voiceGain) / _
        CDbl(OSE_PLAYBACK_VOICE_HEADROOM)
    ' CInt already rounds. Adding half before it shifts odd MIDI velocities
    ' into the next sample zone; Int supplies the intended half-up conversion.
    If velocityRatio > 1.0 Then
        velocityRatio = 1.0
    End If
    Dim As Integer velocity = CInt(Int(velocityRatio * 127.0 + 0.5))
    If velocity < 1 Then
        velocity = 1
    End If
    If velocity > 127 Then
        velocity = 127
    End If
    Dim As Integer resolvedCount = soundfontBank_Resolve( _
        bankNumber, programNumber, keyNumber, velocity, regions())
    If resolvedCount <= 0 Then
        Return 0
    End If

    MutexLock soundfontSynth_Mutex
    Dim As Integer sampleRate = soundfontSynth_SampleRate
    If sampleRate <= 0 Then
        MutexUnlock soundfontSynth_Mutex
        Return 0
    End If
    soundfontSynth_ChannelGain(channelIndex) = mixValues.channelGain
    soundfontSynth_ChannelPan(channelIndex) = mixValues.pan
    Dim As Integer startedVoices
    ' Choke older note-ons before allocating any layers of this note. Doing
    ' this inside the allocation loop makes stereo hi-hats silence themselves.
    For regionIndex As Integer = 0 To resolvedCount - 1
        Dim As OseSoundFontVoiceRegion Ptr region = @regions(regionIndex)
        If region->exclusiveClass > 0 Then
            For voiceIndex As Integer = 0 To SOUNDFONT_SYNTH_VOICE_COUNT - 1
                If soundfontSynth_Voices(voiceIndex).active <> 0 AndAlso _
                    soundfontSynth_Voices(voiceIndex).channelIndex = channelIndex AndAlso _
                    soundfontSynth_Voices(voiceIndex).exclusiveClass = _
                    region->exclusiveClass Then
                    soundfontSynth_ClearVoice soundfontSynth_Voices(voiceIndex)
                End If
            Next
        End If
    Next
    For regionIndex As Integer = 0 To resolvedCount - 1
        Dim As OseSoundFontVoiceRegion Ptr region = @regions(regionIndex)
        Dim As Integer voiceIndex = soundfontSynth_AllocateVoice()
        Dim As SoundFontSynthVoice Ptr voiceState = _
            @soundfontSynth_Voices(voiceIndex)
        soundfontSynth_ClearVoice *voiceState
        voiceState->active = -1
        voiceState->channelIndex = channelIndex
        voiceState->keyNumber = keyNumber
        voiceState->exclusiveClass = region->exclusiveClass
        voiceState->region = *region
        Dim As Integer effectiveKey = keyNumber
        If region->keyOverride >= 0 Then
            effectiveKey = region->keyOverride
        End If
        Dim As Double bendSemitones = _
            ((CDbl(pitchBend) - 8192.0) / 8192.0) * 2.0
        Dim As Double semitones = _
            CDbl(effectiveKey - region->rootKey) * _
            (CDbl(region->scaleTuning) / 100.0) + _
            CDbl(region->tuneCents) / 100.0 + bendSemitones
        voiceState->sampleIncrement = (CDbl(region->sampleRate) / _
            CDbl(sampleRate)) * (2.0 ^ (semitones / 12.0))
        If voiceState->sampleIncrement <= 0.0 OrElse _
            voiceState->sampleIncrement > 256.0 Then
            soundfontSynth_ClearVoice *voiceState
            Continue For
        End If
        voiceState->noteFramesRemaining = soundfontSynth_BoundedFrames( _
            durationSeconds, sampleRate)
        voiceState->attackFrames = soundfontSynth_BoundedFrames( _
            region->attackSeconds, sampleRate)
        voiceState->holdFrames = soundfontSynth_BoundedFrames( _
            region->holdSeconds, sampleRate)
        voiceState->decayFrames = soundfontSynth_BoundedFrames( _
            region->decaySeconds, sampleRate)
        voiceState->releaseFrames = soundfontSynth_BoundedFrames( _
            region->releaseSeconds, sampleRate)
        voiceState->envelopeStage = SOUNDFONT_ENVELOPE_ATTACK
        voiceState->envelopeLevel = IIf( _
            voiceState->attackFrames = 0, 1.0, 0.0)
        voiceState->velocityGain = mixValues.voiceGain
        If region->velocityOverride >= 0 Then
            voiceState->velocityGain = OSE_PLAYBACK_VOICE_HEADROOM * _
                CSng(region->velocityOverride) / 127.0
        End If
        voiceState->serialNumber = soundfontSynth_NextSerial
        soundfontSynth_NextSerial += 1
        If soundfontSynth_NextSerial = 0 Then
            soundfontSynth_NextSerial = 1
        End If
        startedVoices += 1
    Next
    MutexUnlock soundfontSynth_Mutex
    Return IIf(startedVoices > 0, -1, 0)
End Function


Public Function soundfontSynth_RenderPreview( _
    ByVal channelIndex As Integer, _
    ByVal keyNumber As Integer, _
    ByVal bankNumber As Integer, _
    ByVal programNumber As Integer, _
    ByVal pitchBend As Integer, _
    ByVal durationSeconds As Single, _
    ByRef mixValues As OsePlaybackMixValues, _
    ByVal outputSampleRate As Integer, _
    ByVal outputSamples As Single Ptr, _
    ByVal frameCount As Integer _
) As Integer
    If soundfontSynth_Thread <> 0 OrElse soundfontBank_IsLoaded() = 0 OrElse _
        outputSampleRate < 4000 OrElse outputSampleRate > 384000 OrElse _
        outputSamples = 0 OrElse frameCount <= 0 OrElse _
        frameCount > outputSampleRate * 60 Then
        Return 0
    End If
    If soundfontSynth_EnsureMutex() = 0 Then
        Return 0
    End If
    For sampleIndex As Integer = 0 To frameCount * 2 - 1
        outputSamples[sampleIndex] = 0.0
    Next

    MutexLock soundfontSynth_Mutex
    soundfontSynth_WorkerState = 2
    soundfontSynth_SampleRate = outputSampleRate
    MutexUnlock soundfontSynth_Mutex
    Dim As Integer playResult = soundfontSynth_PlayMidiNote( _
        channelIndex, keyNumber, bankNumber, programNumber, pitchBend, _
        durationSeconds, mixValues)
    If playResult <> 0 Then
        MutexLock soundfontSynth_Mutex
        soundfontSynth_RenderVoices outputSamples, frameCount
        MutexUnlock soundfontSynth_Mutex
    End If
    soundfontSynth_StopAll()
    MutexLock soundfontSynth_Mutex
    soundfontSynth_WorkerState = 0
    soundfontSynth_SampleRate = 0
    MutexUnlock soundfontSynth_Mutex
    Return playResult
End Function


Public Sub soundfontSynth_SetChannelMix( _
    ByVal channelIndex As Integer, _
    ByVal channelGain As Single, _
    ByVal channelPan As Single _
)
    If soundfontSynth_Mutex = 0 OrElse channelIndex < 0 OrElse _
        channelIndex >= SOUNDFONT_SYNTH_CHANNEL_COUNT Then
        Exit Sub
    End If
    If channelGain < 0.0 Then
        channelGain = 0.0
    End If
    If channelGain > 1.0 Then
        channelGain = 1.0
    End If
    If channelPan < -1.0 Then
        channelPan = -1.0
    End If
    If channelPan > 1.0 Then
        channelPan = 1.0
    End If
    MutexLock soundfontSynth_Mutex
    soundfontSynth_ChannelGain(channelIndex) = channelGain
    soundfontSynth_ChannelPan(channelIndex) = channelPan
    MutexUnlock soundfontSynth_Mutex
End Sub


Public Sub soundfontSynth_SetPaused(ByVal paused As Integer)
    If soundfontSynth_Mutex = 0 Then
        Exit Sub
    End If
    MutexLock soundfontSynth_Mutex
    soundfontSynth_Paused = IIf(paused <> 0, -1, 0)
    MutexUnlock soundfontSynth_Mutex
End Sub


Public Sub soundfontSynth_StopChannel(ByVal channelIndex As Integer)
    If soundfontSynth_Mutex = 0 OrElse channelIndex < 0 OrElse _
        channelIndex >= SOUNDFONT_SYNTH_CHANNEL_COUNT Then
        Exit Sub
    End If
    MutexLock soundfontSynth_Mutex
    For voiceIndex As Integer = 0 To SOUNDFONT_SYNTH_VOICE_COUNT - 1
        If soundfontSynth_Voices(voiceIndex).active <> 0 AndAlso _
            soundfontSynth_Voices(voiceIndex).channelIndex = channelIndex Then
            soundfontSynth_BeginRelease soundfontSynth_Voices(voiceIndex)
        End If
    Next
    MutexUnlock soundfontSynth_Mutex
End Sub


Public Sub soundfontSynth_StopAll()
    If soundfontSynth_Mutex = 0 Then
        Exit Sub
    End If
    MutexLock soundfontSynth_Mutex
    For voiceIndex As Integer = 0 To SOUNDFONT_SYNTH_VOICE_COUNT - 1
        soundfontSynth_ClearVoice soundfontSynth_Voices(voiceIndex)
    Next
    soundfontSynth_Paused = 0
    MutexUnlock soundfontSynth_Mutex
End Sub

/' end of soundfont_synth.bas '/
