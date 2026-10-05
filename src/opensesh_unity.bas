/'
    Project: OpenSesh
    ---------------------------

    File: opensesh_unity.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; single-source Android ARM/AArch64/x86_64 builds.

    Module API: Single-source build entry point; selects and includes the shared module implementations.

    Purpose:

        Provide a single translation unit for toolchains that package one
        FreeBASIC source entry point.

    Responsibilities:

        - include the complete shared editor implementation exactly once
        - select the native external-MIDI endpoint adapter for each target
        - retain the no-endpoint adapter on targets without a native backend

    This file intentionally does NOT contain:

        - application, rendering, touch, audio, or document implementation
        - target-specific user-interface behavior
        - duplicated source copied from the included modules
'/

#lang "fb"

/'
    The Android packaging wrapper accepts one source entry. Each suppression
    documents an intentional implementation include in this packaging-only
    translation unit; ordinary desktop builds continue compiling modules.

'/
' FBLINT-ALLOW-BAS-INCLUDES: this packaging unit deliberately composes implementations.
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "omagui_runtime.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "midi_model.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "history_timeline.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "document_history.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "project_transaction.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "note_selection.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "selected_note_playback.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "score_tools.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "score_controls.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "numeric_text.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "capture_paths.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "score_scroll.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "score_layout.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "mixer_meter.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "mixer_controls.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "mixer_state.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "keyboard_controls.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "drum_kit.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "drum_phrase.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "playback_mix.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "playback_timing.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "ui_frame_pacing.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "soundfont_bank.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "soundfont_synth.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "software_synth.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "playback_state.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "master_effect.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "sfx_runtime.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "ui_style.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "ui_icons.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "ui_interaction.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "touch_gesture.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "user_preferences.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "music_export.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "wav_export_sfx.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "audio_tracks.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "audio_sample_slots.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "midi_input_protocol.bas"

#If Defined(__FB_WIN32__)
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "midi_input_win.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "midi_output_sfx.bas"
#ElseIf Defined(__FB_LINUX__)
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "midi_alsa.bas"
#Else
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "midi_null.bas"
#EndIf

' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "pitch_transcriber.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "music_symbols.bas"
' fblint: disable-next-line FBL950 REASON: This single-source packaging entry point includes each selected implementation once.
#include once "opensesh.bas"

/' end of opensesh_unity.bas '/
