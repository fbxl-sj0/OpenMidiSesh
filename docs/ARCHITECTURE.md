<!--
    Project: OpenSesh
    File: docs/ARCHITECTURE.md
    Purpose: Explain how the editor's main components work together.
    Responsibilities: describe module boundaries, data flow and platform adapters.
    This file does not serve as a line-by-line source reference.
-->

# Architecture

OpenSesh is a single MIDI editor with a shared document model, score and mixer
interface, playback engine, and file workflows. The desktop build compiles
separate modules. Android packages the same editor sources through a unity
translation unit and selects the Touch profile on first launch.

~~~mermaid
flowchart TD
    User[User input] --> UI[Editor UI and omaGUI]
    UI --> App[Application commands and session state]
    App --> MIDI[MIDI document model]
    App --> Audio[Audio clip model]
    App --> History[Chronological edit history]
    History --> MIDI
    History --> Audio
    App --> Timing[Playback timing and transport]
    MIDI --> Timing
    Audio --> Mix[Playback routing]
    Timing --> Mix
    Mix --> Synth[Built-in or SoundFont synth]
    Synth --> Runtime[sfxlib audio runtime]
    Mix --> Runtime
    Runtime --> Output[Host audio output]
    Timing --> NativeMIDI[Platform MIDI output]
    MIDI --> Save[MIDI save and export]
    Audio --> Project[OpenSesh project files]
    MIDI --> Project
~~~

## Components

| Component | Main source | Responsibility |
| --- | --- | --- |
| Application and UI | <code>src/opensesh.bas</code>, <code>src/omagui_runtime.bas</code>, <code>vendor/omaGui/</code> | Build the windows and controls, route user commands, manage the editor session and shut down owned resources. |
| MIDI document | <code>src/midi_model.bas</code>, <code>src/note_selection.bas</code>, <code>src/score_tools.bas</code> | Read and write Standard MIDI Files, expose editable tracks, notes and events, and apply score operations. |
| Score and mixer | <code>src/score_layout.bas</code>, <code>src/score_controls.bas</code>, <code>src/mixer_controls.bas</code>, <code>src/mixer_state.bas</code> | Map document state to score and mixer views and convert pointer input into edits. |
| History and projects | <code>src/document_history.bas</code>, <code>src/history_timeline.bas</code>, <code>src/project_transaction.bas</code> | Keep MIDI and clip edits in one undo/redo order and save project data consistently. |
| Audio clips | <code>src/audio_tracks.bas</code>, <code>src/audio_sample_slots.bas</code> | Track external WAV clips, load samples for playback, and retain clip edits. |
| Playback and synthesis | <code>src/playback_state.bas</code>, <code>src/playback_timing.bas</code>, <code>src/playback_mix.bas</code>, <code>src/software_synth.bas</code>, <code>src/soundfont_synth.bas</code> | Schedule notes, apply channel state, render voices, and send the final software mix to sfxlib. |
| MIDI devices | <code>src/midi_input_win.bas</code>, <code>src/midi_alsa.bas</code>, <code>src/midi_output_sfx.bas</code>, <code>src/midi_null.bas</code> | Keep operating-system endpoint handling separate from the document and interface. |
| Export | <code>src/music_export.bas</code>, <code>src/wav_export_sfx.bas</code> | Write ProTracker MOD files and capture a PCM WAV mix. |

Names without extensions refer to a matching <code>.bas</code> implementation
and <code>.bi</code> interface where the pair exists.

## Data flow and ownership

The UI sends commands to application modules. The MIDI model owns the editable
song state; audio clips are represented separately and refer to WAV files on
disk. The shared history records MIDI and clip changes in the order the user
made them.

Playback reads the document timeline and mixer state, then routes sound through
the software synth and audio runtime. MIDI device input is validated at the
platform boundary before it can become a document edit. Device output is a
separate path from the software mix.

A Standard MIDI File contains the song's MIDI data. An OpenSesh project keeps a
MIDI file with references to external WAV clips and project-specific data.
Project saves stage the related files before replacing them, so a failed write
does not leave a partially updated project.

The application owns its top-level widgets and coordinates shutdown. Audio
rendering has a worker thread; the UI thread owns document edits. Platform
callbacks and polling code pass bounded MIDI events back to the application
before changing the song.

## Platform boundaries

| Target | MIDI input | MIDI output | Shared editor features |
| --- | --- | --- | --- |
| Windows | WinMM | sfxlib | Score, mixer, playback, SoundFonts and file export |
| Linux | ALSA Sequencer | ALSA Sequencer | Score, mixer, playback, SoundFonts and file export |
| FreeBSD, NetBSD, OpenBSD, Haiku | Unavailable | Unavailable | Score, mixer, built-in sound and file export |
| Android | Unavailable | Unavailable | Shared editor, Touch profile and built-in sound |

<!-- end of docs/ARCHITECTURE.md -->