/'
    Project: OpenMidiSesh
    ---------------------------

    File: sfx_runtime.bi

    Copyright (C) 2026 OpenMidiSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: sfxRuntime_* initialization, generation, restart, and shutdown.

    Purpose:

        Declare explicit ownership of the process-wide sfxlib runtime.

    Responsibilities:

        - initialize the process-wide sound runtime on demand
        - restart the sound runtime after an output-device interruption
        - identify runtime generations for retained audio configuration
        - expose an idempotent sound-runtime shutdown operation
        - give applications and tests one documented teardown boundary
        - share the channel limit used by sfxlib mixer operations

    This file intentionally does NOT contain:

        - synthesis, capture, or MIDI commands
        - effect parameter mapping
        - application lifecycle decisions
'/

#ifndef __OSE_SFX_RUNTIME_BI__
#define __OSE_SFX_RUNTIME_BI__

' sfxlib exposes sixteen mixer channels, including the dedicated sample lane.
Const OSE_SFX_MIXER_CHANNEL_COUNT As Integer = 16

Declare Function sfxRuntime_EnsureReady() As Integer
Declare Function sfxRuntime_Restart() As Integer
Declare Function sfxRuntime_GetGeneration() As Integer
Declare Sub sfxRuntime_Shutdown()

#endif

/' end of sfx_runtime.bi '/
