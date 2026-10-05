/'
    Project: OpenSesh
    ---------------------------

    File: generated_voice_stop_internal.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; native desktop and Android sfxlib runtimes.

    Module API: Internal generatedVoiceStop_Channel plus verified sfxlib C stop/lock bindings.

    Purpose:

        Stop generated SOUND and NOISE voices at a transport boundary.

    Responsibilities:

        - share the production stop operation with the null-renderer regression
        - retain channel isolation when releasing generated voices
        - bind the runtime's C int parameters as FreeBASIC Long on every target

    API and ownership:

        These are exported sfxlib C entrypoints, not documented BASIC STOP
        keywords. Native CI must link and execute generated_voice_stop_smoke
        against each platform's runtime before packaging. These exports are a
        release dependency to recheck on toolchain upgrades.
        This helper keeps no voice pointers and runs only on the application's
        UI/transport owner. Both stop calls share the runtime's recursive lock
        with its mixer and the application's SoundFont rendering worker. The
        exported lock lazily initializes itself before runtime initialization.

    This file intentionally does NOT contain:

        - private runtime structure layouts or voice allocation
        - sample/SoundFont stop operations or external MIDI access
        - duration retiming, audio-device selection, or worker ownership
'/

#ifndef __OSE_GENERATED_VOICE_STOP_INTERNAL_BI__
#define __OSE_GENERATED_VOICE_STOP_INTERNAL_BI__

#If Not Defined(__FB_WIN32__) And Not Defined(__FB_LINUX__) And Not Defined(__FB_ANDROID__) And _
    Not Defined(__FB_FREEBSD__) And Not Defined(__FB_NETBSD__) And _
    Not Defined(__FB_OPENBSD__) And Not Defined(__FB_HAIKU__)
    #Error OpenSesh generated-voice stopping requires a supported native sfxlib runtime
#EndIf

' Modern FB on both 32- and 64-bit targets: the C ABI uses a 32-bit int.
Declare Sub fb_sfxSoundStopChannel CDecl Alias "fb_sfxSoundStopChannel" ( _
    ByVal channelIndex As Long _
)
Declare Sub fb_sfxNoiseStop CDecl Alias "fb_sfxNoiseStop" ( _
    ByVal channelIndex As Long _
)
Declare Sub generatedVoiceStop_RuntimeLock CDecl Alias "fb_sfxRuntimeLock" ()
Declare Sub generatedVoiceStop_RuntimeUnlock CDecl Alias "fb_sfxRuntimeUnlock" ()

Private Sub generatedVoiceStop_Channel(ByVal channelIndex As Integer)
    If channelIndex < 0 OrElse channelIndex > 15 Then Exit Sub
    generatedVoiceStop_RuntimeLock()
    fb_sfxSoundStopChannel CLng(channelIndex)
    fb_sfxNoiseStop CLng(channelIndex)
    generatedVoiceStop_RuntimeUnlock()
End Sub

#endif

/' end of generated_voice_stop_internal.bi '/
