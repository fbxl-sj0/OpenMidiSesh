<!--
    Project: OpenSesh
    ---------------------------

    File: README.md

    Purpose:

        Explain how to build and run the native FreeBASIC editor shell.

    Responsibilities:

        - document the compiler and include-path requirements
        - identify the sample and command-line loading behavior
        - state the current implementation boundary

    This file intentionally does NOT contain:

        - generated decompiler output
        - private Midisoft implementation details
        - platform-specific setup outside the local toolchain
-->

# OpenSesh

This is an independent GPL MIDI editor implementation informed by the
reference application's observable layout. It loads and saves Standard MIDI
Files, exports ProTracker MOD and PCM WAV files, displays their track and note
summary, draws a compact multi-track
score preview and
sixteen-channel mixer, exposes sfxlib transport controls, and supports bounded
track and note editing. The initial tempo, channel volume/pan, chorus, and
reverb values can also be edited and saved without flattening later automation.
The mixer includes independent Mute, Solo, and Record-arm controls. Record-arm
provides PC-key step entry, while the Keys window provides a playable two-octave
piano with mouse input, PC-key input, octave shifting, and real-duration live
recording. Native MIDI input uses WinMM on Windows and ALSA Sequencer on Linux.
Both backends remain outside the model and UI code. The optional `Out` command
opens a chooser for the native MIDI output endpoints. It mirrors playback to
the selected hardware or virtual device while the software synth remains
available. Windows output uses sfxlib; Linux output uses ALSA Sequencer.

The main window keeps the reference program's observable hierarchy while the
command shelf and score tools use flat, state-aware controls with consistent
normal, hover, pressed, active, and disabled appearances. It has a full-width
Score View, narrow score tool rail, pane scrollbars, and a tall Mixer View with
channel strips and a wider master section. The File, Edit, Options, Setup, View, Track,
Music, and Help popups use omaGui menu objects. The score uses omaGui
horizontal and vertical scrollbar objects. Their shared mapping contract tests
all 1001 horizontal positions, exact 64-bit endpoints, and track-count resize
clamping. Options also provides Light, Dark, and Black themes. Each selection
applies a complete semantic palette to the editor, mixer, score, menus,
generated dialogs, performance keyboard, and every interaction state for the
current session and stores that selection for the next launch. Preferences use
`%LOCALAPPDATA%\OpenSesh\settings.conf` on Windows and
`$XDG_CONFIG_HOME/opensesh/settings.conf`, or the conventional
`$HOME/.config` fallback, on Linux. Malformed preferences fall back to Light,
and replacements are written atomically. Black uses true-black primary surfaces
with high-contrast controls; it is not a darker name for the charcoal Dark
theme. A semantic contrast gate calculates sRGB relative luminance for 102
foreground/background pairings across the three themes. Normal labels and
control glyphs must reach 4.5:1; deliberately subdued disabled labels must
still reach 3:1. This is a color-readability check, not a claim of complete
screen-reader or high-DPI qualification. At widths below
1040 pixels, tempo
and MIDI setup widgets are hidden as a group rather than clipped; their menu
commands remain available.

Options > Load SoundFont opens a shared `.sf2` chooser. The selected bank is
remembered with the other preferences and is used for Play, selected-note
playback, the performance keyboard, live MIDI monitoring, and WAV export.
Options > Use Built-in Synth releases the bank and restores the small
oscillator synth. The SF2 RIFF/Hydra reader, GM/GS bank resolver, interpolation,
independently panned stereo zones, looping, envelopes, pitch bend, voice allocation, and
realtime mixer are written in FreeBASIC. There is no FluidSynth, C/C++ synth,
or platform-specific SoundFont implementation. Invalid or unavailable banks
leave the built-in synth usable.

SoundFonts are user-supplied and are not copied into release packages.
[Timbres of Heaven](https://midkar.com/SoundFonts/TOH.html) is compatible with
the loader, but its publisher says it may not be redistributed on another
site without written permission. Download it from MidKar, extract the `.sf2`
to a permanent folder, then select that file in Options.

Options also switches between Desktop and Touch interaction profiles. Touch is
the first-run default on Android and remains selectable on every platform; the
choice is stored with the theme. The touch profile enlarges menus, toolbar
buttons, scrollbars, score tools, note-palette faces, and mixer strips. A
single finger taps, drags notes and controls, or pans the score. Two fingers
pan around their center while their horizontal separation changes time density
and their vertical separation changes staff and track density. The two axes
are independent, so a horizontal, vertical, or diagonal pinch behaves as the
gesture indicates instead of assuming every finger motion is one-dimensional.

## Build

From this directory, using the FreeBASIC compiler selected by the build script:

```powershell
& '.\build_editor.ps1'
```

The script defaults to the reviewed source snapshot under `vendor\omaGui`.
Use `-FreeBasicPath`, `-OmaGuiPath`, or `-OutputPath` when the local toolchain,
an intentionally substituted omaGui tree, or the output location differs.
`tests\verify_dependency_snapshot.ps1` checks every default omaGui payload
file against its SHA-256 manifest and rejects extra files. The release source
therefore does not depend on an unversioned sibling checkout.

Audited Windows release builds also verify 14 release-critical compiler,
binutils, header, runtime, gfxlib, and sfxlib files against
`windows_toolchain_lock.json`. See `DEPENDENCIES.md` before changing the
compiler distribution or refreshing that lock.
Windows builds also embed `opensesh.manifest`. It declares
`asInvoker`, no privileged UI access, Windows 10-or-later compatibility, and
system-DPI awareness. System awareness matches the current fixed-pixel gfxlib
backend; per-monitor DPI awareness remains a future layout capability rather
than an unsupported manifest claim.

Linux builds use the matching shell wrapper:

```bash
bash ./build_editor.sh
```

Set `FREEBASIC_PATH`, `OMAGUI_PATH`, or `OUTPUT_PATH` to make a deliberate
toolchain, dependency, or output override. Linux builds link the system ALSA
Sequencer library (`libasound`) for native MIDI input and output.

Android uses the same editor, model, rendering, gesture, and software-synth
sources through a single packaging translation unit:

```powershell
& '.\build_editor_android.ps1'
```

The default output is `build\android\opensesh-debug.apk` for 64-bit ARM at API
24. Pass `-RunOnDevice` to install and launch it on an attached device, or use
`-Target`, `-ApiLevel`, and `-OutputPath` for another supported build. Android
has no native external-MIDI endpoint adapter yet, so MIDI In and Out report
unavailable there; software-synth playback and audio metering remain active.
This is the only intentional platform capability substitution in the Android
build, rather than a separate Android user interface.

The APK display version comes from `version.bi`. Pass `-VersionCode` with an
increasing positive integer for each Android upgrade; its development default
is `1`. The script stages a copy of the installed package template (or the
caller's `FBANDROID_TEMPLATE`) and leaves the original template unchanged.
Run `tests\android_package_metadata_smoke.ps1` to check this staging, metadata,
and failure cleanup with a fake wrapper, without compiling or using a device.

## Drum machine and independent meters

Click **Drum machine** beside Music on the main screen. **Music > Drum Machine /
Phrases** and **Beat phrases** in the playable Drum Kit open the same editor.
The grid provides 16 named phrase slots and twelve General
MIDI drum sounds. Click a cell to add or remove a hit. The Soft / Medium / Hard
button selects the velocity for new hits; click a drum name to audition it.
Use Copy to start a variation in an unused slot. More drums and the step-page
buttons expose the rest of the grid on smaller screens and in Touch mode.
**New beat** creates a straight 4/4 kick, snare, and hi-hat pattern in an unused
slot. It keeps existing phrases. **At view** places the insertion point at the
left edge of the score; **At end** uses the song end. The phrase header also
shows that position as a bar, beat, and tick. Clear asks for a second click
before erasing hits. Store phrase saves the draft into the current song;
the main Save command writes the song to disk.

Each phrase has its own meter: 1-16 beats, denominator 1-32, and 1-4 steps per
beat, up to 64 steps. Apply meter updates the grid. For example, use 3/4 drums
against a 4/4 song, or 4/3 for four beats each lasting a third of a whole note.
Phrase timing follows the song tempo map; it does not change the melodic
meter. The score displays the active time signature as stacked numbers beside
each clef. Click **Time 4/4...** (or the current meter) beside Drum machine to
choose a song signature. Choose **Song start** or **Current view**, select a
preset or enter the numerator and denominator, then click **Apply & show**.
The score moves to that position and redraws its signature and bar lines; the
change is undoable and leaves note timing and tempo unchanged. Later signature
changes remain in the song. The drum editor shows both meters at the insertion
tick. Its **Song meter** button opens
the existing Tempo / Meter Map editor, where the song's notation and bar lines
can be changed. Standard MIDI song signatures use power-of-two denominators;
the drum phrase grid also accepts other denominators and rounds absolute MIDI
tick boundaries to avoid cumulative drift across repeats.

**Loop phrase** previews the grid. Set **Start tick** and **Repeats**, then use
**Insert into song** to write ordinary channel 10 notes on the Drum phrases
track. Start tick advances by the full phrase length, including trailing rests,
so a different phrase can be placed immediately after it. Placement markers
record the phrase name and meter. Each placement is one undoable edit. Existing
placements are independent note copies; editing a phrase affects subsequent
placements. Notes remain editable through the score and note properties.

Store phrase, switching slots, and closing the window store the draft in the
song. Save the MIDI file to keep the phrase bank on disk. Phrase names, meters,
velocities, and hidden steps are preserved in versioned MIDI text events and
participate in document undo/redo. Other MIDI players can play the inserted
notes without understanding this metadata. Empty phrases and placements beyond
the song's note, track, tick, or timing-resolution limits are rejected.

## Everyday note editing

Click **Note tools...** beside the time signature, or use Edit > Note Tools.
Select notes on the score first, or use **Select track notes** in the panel.
The panel shows the selected-note count and active snap grid. Unavailable
actions are dimmed. Changes apply immediately and can be undone or redone.

- **Duplicate** (`Ctrl+D`) repeats the selection immediately after its span,
  rounded up to the snap grid. The new copy stays selected, so another press
  repeats it again. Relative timing, instruments, and note lengths are kept.
  The Cut/Copy clipboard is left available for other phrases.
- **Quantize** (`Ctrl+Q`) aligns selected note starts to the chosen grid and
  keeps their lengths. Choose quarter, eighth, sixteenth, thirty-second, or
  eighth-note triplet spacing. This also sets score placement and drag snap;
  sixteenths remain the default. Grid selection lasts for the current session.
- **Pitch / Octave** moves melodic notes by semitones or octaves. Channel 10
  drum sounds retain their assignments. Edits beyond MIDI's pitch limits are
  rejected as a whole.
- **Softer / Louder** adjusts velocities by ten within the playable MIDI range.
  **Listen to selection** auditions the result; click again to stop.

**Loop selection** repeats the selected phrase for practice or comparison.
Its length rounds up to the current grid, matching Duplicate. It follows tempo
changes, retains timing across loop boundaries, and works with the built-in
synth, SoundFonts and optional MIDI output. Pause holds its position. Stop loop,
Done, or a note edit stops it. Looping does not write notes or change the song.
Undo and Redo keep the selection after pitch, velocity and timing edits so you
can listen to the before/after result without selecting the phrase again.

**Help > Quick start / shortcuts** explains writing notes, making beats,
arranging phrases and the essential keyboard commands inside the editor.

Each command is one undo step. `Ctrl+Shift+Z` is also accepted for Redo alongside
`Ctrl+Y`. Status messages remain visible below the transport in both Desktop
and Touch modes, including small windows.

## Run

With any Standard MIDI File:

```powershell
.\opensesh.exe `
    'C:\path\to\song.mid'
```

If no argument is supplied, the editor starts with an empty document. Open
shows an omaGui file dialog. Save opens a Standard MIDI Save As dialog for a
standalone document. When a project is open, Save updates its sibling MIDI
file and project container. A second command-line argument still supplies an
unattended output path.

File > Export ProTracker MOD writes the editable MIDI notes as a conventional
31-sample `M.K.` module. The converter uses four rows per quarter note, carries
tempo changes in ProTracker `Fxx` commands, and generates sixteen small looping
waveforms so the module has no external sample dependency. ProTracker has only
four playback channels, a 128-pattern order table, and a practical four-octave
period range. The exporter therefore keeps the strongest four attacks on one
row, steals the voice that ends soonest when later polyphony overlaps, folds
out-of-range pitches by octaves, and reports those reductions in the status
line. MOD export contains MIDI notes only; placed WAV clips remain part of the
OpenSesh project and the WAV mix.

File > Export WAV Mix records the complete editor playback through sfxlib's
final-output capture path. The result is a 16-bit PCM WAV containing the same
software synth, channel automation, current mixer mute/solo/master state, and
placed audio clips heard during Play. External MIDI output is deliberately not
sent during a file render. Export proceeds from the beginning in real time,
shows percentage progress, and can be cancelled with Stop before a file is
written. Because sfxlib retains floating-point capture frames until saving,
one WAV render is bounded to ten minutes.
Saving first writes a temporary file beside the destination, so a failed
write or replacement preserves the previous export. Sustained MIDI notes keep
their scored duration during playback and export, up to one hour per voice.

`Ctrl+N` clears the current document and creates a fresh one-track document;
when edits are unsaved, both New and Open ask for confirmation first.
File > Exit, Escape, and the native window close button use that same discard
confirmation path, so none of the three can silently discard a dirty session.
The desktop menus are fully keyboard operable: Alt+F, Alt+E, Alt+O, Alt+S,
Alt+V, Alt+T, Alt+M, and Alt+H open File through Help; the arrow keys move
within and between menus, Enter activates a command, and Escape dismisses the
menu without closing the editor. Tab and Shift+Tab traverse eligible toolbar
and dialog controls, with Enter or Space activating the focused command.
Ctrl+S saves the current Standard MIDI output, and Space toggles Play/Pause
when no modal editor is open. Music > Play Selected Notes or Ctrl+Space plays
only the current note selection. One selected note starts immediately. A
multi-note selection follows its original score-time order, tempo changes,
simultaneous attacks, durations, and current playback-speed multiplier. The
command snapshots the phrase before playback, so later editing cannot retime
notes already being heard. It uses the same software synth, mixer automation,
VU meters, pause/stop handling, and optional native MIDI output as Play, while
leaving unrelated audio clips silent. The documented transport keys are also active:
F2 Stop, F3 Rewind, F4 Fast Forward, F5 Play, F6 Record, F7 Pause, F8 Step
Record, and F9 Step Play. Right-clicking Rewind returns directly to the song
beginning. While stopped, Fast Forward selects normal or 4x playback speed;
Play and Play Selected Notes retain that selection. Full-song playback with
WAV clips requires 1x speed; selected-note audition can still use 4x. Press Stop
before changing speed or tempo, including tempo-map edits. Playback, pause, recording, and drum
loops retain their starting timing settings. Use the score scroll controls to
navigate without changing speed. Stop releases generated SOUND and NOISE voices
as well as sample, SoundFont, and external MIDI notes.
Play uses the selected SoundFont or the built-in sfxlib software synth and does
not require a MIDI output device.
Tone uses the same synth for a generated A4 sound and does not require a MIDI
file.

The score keeps a selection-first editing workflow. Selecting one note reports
its pitch, musical start and end, and tick span. Selecting a phrase reports the
same precise range for the complete group. View > Zoom Selection (`Ctrl+E`)
frames that range with a small amount of musical context. View also provides
Zoom In (`Ctrl+1`), Zoom Normal (`Ctrl+2`), Zoom Out (`Ctrl+3`), Fit Project
(`Ctrl+F`), and Fit Tracks (`Ctrl+Shift+F`). These are navigation commands, so
they do not change the MIDI document or create undo entries. Space remains the
single Play/Pause toggle and `Ctrl+Space` remains the direct way to listen to
the current selection.

MIDI Out opens the native MIDI output chooser, or closes an active output. When
available, playback sends the initial channel setup, editable channel events,
and note ranges to the selected device in addition to the software-synth path.
Stop and Pause send all-notes-off so a hardware synth is not left sounding
indefinitely. The separate `MIDI In` command opens a named WinMM input device
on Windows or an ALSA Sequencer source port on Linux.
Playback applies channel automation in global tick order even when imported
events originate in different MIDI tracks. Application shutdown explicitly
stops sfxlib driver and capture workers before graphics and language-runtime
teardown; effect and capture tests exercise that idempotent boundary directly.

Track > Add Track creates a new track and Track > Remove Track removes the
selected track. The Score View rail follows the five-tool Recording Session
layout: Select, Add Note, Delete Note, Cut, and Paste. Every rail icon retains
a persistent text name. The five score tools and seven transport commands use
embedded 24 x 24 grayscale coverage masks. Their eight-times-supersampled
edges are alpha blended without RGB subpixel assumptions, so the same reviewed
pixels render on Windows and Linux. Add Note expands a two-column palette containing whole
through sixty-fourth values plus sharp, flat, natural, dot, triplet, and tie
choices; every compact notation glyph is paired with its name. Its thirteen visible choices and
the five score-rail tools share exact drawing and input bounds; frame padding,
button gaps, and the blank lower-right cell are verified as background. The
ruler and note placement use the grid chosen in Note tools, initially
sixteenth-note divisions, and a vertical guide follows the snapped insertion
point. Clicking the sharp or flat choice again selects its double accidental.
Tie extends an adjacent note of the same pitch so the score renderer can show
the sustained phrase across boundaries.

A normal click selects one note, Shift-click toggles individual notes, and
dragging empty score space selects every intersecting notehead with a marquee.
Dragging any selected note moves the complete selection on the chosen snap
grid while preserving intervals and track ownership. Alt-drag resizes a single
note. Ctrl+C copies the selection, while Ctrl+X cuts it and automatically arms
the clipboard Paste tool. Ctrl+V or Edit > Paste arms the same tool without
guessing a destination. Clicking a staff then pastes at that exact snapped time
and track; relative timing and multi-track spacing are preserved. Repeated
pastes remain available until another Cut or Copy replaces the bounded
8,192-note clipboard. The original Shift+Delete, Ctrl+Insert, and Shift+Insert
shortcuts are accepted as Cut, Copy, and Paste alternatives. Delete removes the
complete selection as one undoable edit. The
mouse wheel navigates the score timeline in four-beat steps. Shift+mouse-wheel
moves the selected track through the visible score rows. Ctrl+mouse-wheel zooms
the time axis around the pointer, while Ctrl+Shift+mouse-wheel changes staff and
note size around the pointer. Clicking a staff or mixer strip selects its track
in every view. The
score's horizontal scrollbar moves directly through a long session, while its
vertical scrollbar moves through track rows.
The BPM field edits the initial tempo. Mixer faders, pan, chorus, and reverb
controls edit the initial channel mix and effects; the score view shows the
transport playhead while playback is active. The master fader scales sfxlib
playback without rewriting per-channel MIDI CC7 values. The master Wet and Fbk
knobs control a real bounded stereo echo on the completed sfxlib mix. Channel
and master VU meters remain at zero while idle, attack when a note or sample is
started, follow channel gain, expression, pan, mute, solo, and master volume,
then release after the sound ends. sfxlib does not expose a live post-mix peak
callback, so the meters follow sound actions accepted by the library rather
than inspecting its private output buffer. Automated output capture separately
requires those same generated and MIDI-driven actions to produce non-silent
PCM. Mute and Solo affect the software synth.
The mixer draw and input paths share one responsive control map. The automated
suite probes all 112 channel controls and the three master controls so a visible
fader, knob, or M/S/R button cannot retain a dead or mismatched hit area.
Separate state tests exercise all 48 Mute, Solo, and Record button behaviors,
including multiple Solo channels, Mute-over-Solo, and exclusive record arming.
Arm a mixer R or press Step
button for step entry, then use `Z S X D C V G B H N J M` and
`Q 2 W 3 E R 5 T 6 Y 7 U` for two chromatic keyboard octaves. Each accepted
key adds one eighth-note-sized MIDI note at the current step position. Options
> Performance Keyboard opens the full performance keyboard. The same PC keys
and the on-screen piano
can be played without recording, or Record / Stop can append wall-clock-timed
notes to the selected track. Octave - and Octave + shift both rows together.
All fourteen white and ten black key faces share one tested pitch map, including
black-key priority in the overlapping upper area and all twenty-four PC labels.
Map opens the imported tempo, meter, and key-signature map editor, and Events opens a
bounded MIDI event editor where CC automation, program changes, pressure,
pitch-bend, and supported system-common messages can be enumerated, moved,
added, or deleted.
Note opens a bounded note
property editor for start tick, duration, track, channel, pitch, and velocity.
Track Properties also quantizes the selected track's note starts to a bounded
tick grid without changing their durations.
Ctrl+Z and Ctrl+Y undo or redo one edit. A group move, paste, or multi-note
delete occupies one history step. The editor keeps the most recent sixteen
MIDI and audio edits in their exact chronological order. Alternating score and
clip changes therefore undo and redo in user order without exposing either
model's private snapshot representation. Starting a new edit after undo clears
the abandoned redo branch in both domains. History is cleared when a new
document is created or another MIDI file is loaded.
In opens the native MIDI input chooser. The selected device remains the
preferred device for later recordings, and Rec can auto-open it when needed.
Rec starts recording at the current MIDI end tick. When MIDI input is open, short channel-voice messages
are captured on the selected track. Notes retain their incoming channel and
velocity; controller, program, pressure, and pitch-bend messages are retained
as ordinary editable channel events. Mapped PC keyboard keys remain available
at the same time. Key-down and key-up timing is converted
through the active tempo map, so held keys produce variable-length notes. MIDI
hardware messages use the native backend's monotonic millisecond timestamp
instead of the GUI polling time, while PC-keyboard timing uses the local wall
clock. WinMM callback work is restricted to a bounded queue, and ALSA events
are polled into the same validated queue; model and UI changes happen on the
main thread. If the optional `Out` device is open while recording, complete incoming
channel-voice messages are also sent through as MIDI Thru without creating a
second model event. Complete SysEx messages up to 4 KiB, including their F0/F7 framing
bytes, are recorded. A larger or unterminated SysEx message is discarded;
F1, F2, F3, and F6 system-common messages are retained with their payload
bytes. Realtime and undefined status messages are intentionally ignored. CC64
sustain is honored during live recording: Note Off closes immediately with the pedal
up, or is deferred until the pedal is released, while the CC64 event remains
editable in the document.

Options > Hum / Whistle Input opens the monophonic transcription window. It records from
sfxlib's default microphone or line input for up to 120 seconds, retains the
source take as `session-mic-take*.wav` beside the open project or MIDI file. An
unsaved document uses `OpenSesh Captures` in the user's Music or
home directory, so an installed read-only program directory is never required.
The transcriber estimates one stable pitch at a time with normalized
autocorrelation. Starts and ends are
converted through the active tempo map and quantized to a selectable 1/4,
1/8, 1/16, or 1/32-note grid. The minimum stable-note field rejects brief pitch
wobbles; 90 ms is the default. This is intentionally a single-note melody
transcriber. Chords, accompaniment, speech, and noisy polyphonic recordings are
outside its supported input model.

The score preview walks the imported time-signature map, uses each active meter
for beat and measure guides, reserves a clef/key-signature gutter, applies
key-signature context to accidentals, and draws visible tracks as compact
labeled staff rows. Each row chooses a compact treble or bass clef once from
the document's imported pitch range, and the key-signature glyphs follow that
choice. Later note insertion and editing cannot silently flip that clef and
move the existing score vertically. The
selected track is kept in view when the document has more rows than fit
vertically. Basic note durations, flags, rests, and
bounded tie marks are drawn; sustained notes are visually split at measure
boundaries. The editable timeline begins after that gutter so score editing,
rests, audio clips, and the playhead share the same horizontal scale. It
remains a compact preview rather than a full engraving engine. Rendering scans
the complete editable note set for the visible rows and time window, with a
bounded dense-view limit reported in the score header.

Audio opens a separate clip editor. Add PCM WAV references, place them at MIDI
ticks, and adjust their gain from 0 to 1000. The score shows each clip as an
independent timeline block. Project saves write an original `OSEPROJECT 1`
text container and a sibling Standard MIDI File. Both serialized images are
committed through a recoverable pair transaction with byte-exact backups and a
same-directory journal. A failure before either commit restores both prior
files, while a later Open or Save recovers an interrupted prepared or completed
transaction before touching the project. Open recognizes `.ose`
projects and reloads their external WAV references. WAV files remain external
user-owned files and are never copied into the project archive. sfxlib provides
the audition path through its sample commands; because this backend exposes a
shared sixteen-channel control space, sample playback uses channel 16 and is
intended as a bounded audition path rather than a full multitrack audio engine.
The Audio dialog can also start and stop sfxlib `CAPTURE` from the default
microphone or line input; a captured WAV is validated and inserted as a new
clip at the current project end. Capture is
optional and reports an unavailable-device status when the active backend does
not provide an input device. Capture filenames use the native platform path
separator, avoid occupied files and directories, and share the same project or
user-owned capture location as microphone transcription takes.
Setup > Restart Audio Engine provides a bounded recovery path after an output
device change or backend failure. It recreates sfxlib, rebuilds all retained
synthesizer definitions, reloads project audio clips, restores the master
effect, and reapplies mixer state. Active input capture and WAV export must be
stopped first so recovery cannot discard an unfinished recording.
The transport timeline includes audio clip tails when deciding playback length
and score scrolling limits, so a clip is not truncated merely because the MIDI
event stream ends earlier.

## Automated tests

The current development release is `0.9.0-dev`. The same version appears in
the title bar, About window, source constants, and Windows executable metadata.

The Windows runner compiles every test from current source, executes the
hardware-independent suite, builds the complete application, and audits the
actual omaGUI widget tree. The control audit currently verifies the exact
handlers of 78 buttons and meaningful menu items, pointer focus and typed input
for all 29 text fields, pointer focus and row activation for all five lists,
two behavior-tested score scrollbars, and 159 code-drawn controls. Every score tool, note-palette face,
mixer-strip face, master control, mixer page control, and performance key is
driven through the application's real pointer path. The audit also checks
score-label separation and executes 508 semantic outcomes through every menu,
transport, chronological edit, generated keyboard, MIDI device chooser, note
editor, tempo/meter/key map, channel and system-event editor, audio editor,
track properties, quantizer, and the dirty, clean, and confirmed exit paths.
Pointer note insertion must append exactly one note without moving existing
music or changing either score view anchor, and must undo cleanly.
The application audit also requires Audition A4 to drive its channel and both
master meters and requires all three displays to return to zero after the sound
stops. A reviewed active-audition framebuffer independently requires bright
meter segments in those exact three wells.
It also completes accepted and cancelled native file selections through MIDI,
project, MOD, WAV, audio-clip, and Open routes using temporary artifacts.
When the capture backend is available, the same audit records real one-second
microphone takes, validates the saved RIFF/WAVE files, inserts and undoes the
audio clip, and runs the transcription completion path.
The application audit injects retained keyboard events to prove forward and
reverse focus traversal, focused-button activation, Alt menu access, arrow
navigation, menu activation, Escape dismissal, and modal shortcut isolation.
The style test separately rejects any theme or interactive control state whose
semantic foreground/background contrast falls below its reviewed threshold.
At narrow window widths, tested Previous and Next controls page the mixer so
all sixteen channel strips remain reachable rather than disappearing behind
the fixed master section.

The model suite also constructs malformed files covering invalid headers,
track topology, lengths, running status, fixed-length meta events, SysEx,
system events, and overflowing tick deltas. Each case must fail with a useful
bounded error before a valid control file is loaded.
A deterministic mutation corpus then exercises 1,916 additional MIDI files,
including exhaustive seed truncations and byte substitutions plus 1,536 mixed
block mutations. Rejected loads must preserve the active notes and exact
undo/redo counts; mutations which remain valid must satisfy model bounds and
serialize back to a complete Standard MIDI File.
The optional notation-mask loader is tested with generated public-domain test
patterns for required glyph discovery, bounds, drawing coordinates, staged
replacement, malformed input, and cache cleanup; no private font data is used.
The audio-format matrix covers RIFF sizes and chunk padding, PCM field
consistency, complete sample frames, project field bounds, staged project
loading, and trailing-data rejection.
Dedicated history tests exceed the sixteen-step MIDI, audio, and shared
timeline bounds, verify oldest-step eviction, check every intermediate state
while alternating real model edits, and prove that a branch clears both redo
stacks. Prepared-edit tests also force failed and cancelled mutations at full
capacity, require exact model restoration, and prove that a no-op Apply keeps
the existing redo branch.

The document endurance test goes beyond one bounded-history traversal. Its
deterministic state machine performs 8,192 mixed MIDI, audio, undo, redo, and
cancel operations, repeatedly wraps the shared history rings, creates new
branches, and resets seven complete document lifecycles. An independent oracle
serializes both domains after every operation and requires every restored state
and history count to match exactly.
Persistence tests replace longer files with verified shorter binary images,
exercise occupied temporary names, and require same-directory atomic
replacement without leftover temporary files. Rejected MIDI loads retain the
active document and its undo/redo history; project loading retains one audio
rollback snapshot until the separately referenced MIDI document commits.
The project-pair suite injects failures before both destination commits and
simulates interruption after the first commit, after the second commit, and
after the durable completion marker. It requires exact rollback or restart
recovery and rejects untrusted transaction journals without following their
paths.

```powershell
& '.\tests\run_tests.ps1'
```

Release-script regressions use disposable mock toolchains and Android templates.
They do not compile the editor or change installed tools, templates, or keys:

```powershell
& '.\tests\windows_toolchain_selection_smoke.ps1'
& '.\tests\android_package_metadata_smoke.ps1'
```

Each test process has a 60-second default timeout and receives a unique
temporary build directory, preventing one hung or concurrent run from blocking
the complete report. Use `-TestTimeoutSeconds` and `-BuildDirectory` to select
other bounded values. On Linux the corresponding settings are
`TEST_TIMEOUT_SECONDS` and `BUILD_DIRECTORY`.

The Windows suite also reads the process manifest directly from the built
executable and rejects missing or changed privilege, Windows-generation, and
DPI declarations. Its native smoothness gate measures 480 settled frames in
each of eight cases: idle Light, Dark, and Black at 1280 x 720, score
scrolling plus master-fader dragging in Desktop and Touch profiles, playback
with changing channel and master VU levels in both profiles, and Dark idle at
1920 x 1080. The Touch interaction workload also drives independent horizontal
and vertical pinch paths. The gate requires a 59 FPS floor for
59.94/60 Hz displays, 20 ms p95, 25 ms p99, no frame above 50 ms, bounded input
latency and rendering work, and no more than two 33.34 ms hitches. Reports with
missing samples, unchanged workloads, rejected timing values, or altered
thresholds fail closed. The suite also launches the built editor sixty
consecutive times on the null audio backend, alternating 800 x 600 and
1280 x 720. One launch supplies
malformed numeric dimensions and must retain the documented defaults instead
of accepting a numeric prefix. Every process must write a correctly sized
framebuffer and exit cleanly within ten seconds. A
separate twenty-five-process stress test initializes the default Windows audio
backend, checks the master-effect contract, and requires explicit sfxlib
shutdown to finish within the same bound. This keeps display and sound-driver
lifecycle failures independently attributable.

The Linux runner uses sfxlib's null audio driver and exercises the same core
suite without requiring a desktop or audio device:

```bash
bash ./tests/run_tests.sh
```

The shell commands invoke `bash` explicitly because ZIP extraction does not
portably preserve Unix execute bits.

On a Linux host with GCC's address and undefined-behavior sanitizer runtimes
and an authenticated X11 display, the dynamic-analysis gate rebuilds the 58
hardware-independent tests and the complete editor with FreeBASIC runtime checks, ASan, UBSan, and
leak detection. Generated C that GCC cannot prove is initialized is rejected
at compile time instead of being buried among sanitizer output. The gate then
runs the same 324-control and 508-behavior audit,
including audio add, apply, delete, undo, slot resynchronization, and explicit
sample teardown:

```bash
LINUX_UI_DISPLAY=:0 \
LINUX_UI_XAUTHORITY=/path/to/.Xauthority \
bash ./tests/run_linux_sanitizers.sh
```

The commercial Midcom gate also sets `REQUIRE_LINUX_MIDI_LOOPBACK=1`. When no
indices are supplied, the runner selects the ALSA `Midi Through` input and
output automatically, runs a fifty-ninth test, and requires seven ordered MIDI
channel-message families to return through the native backend.

Any initialization warning, leak, or sanitizer finding is a failing gate. Set
`KEEP_SANITIZER_BUILD=1` only when retaining the isolated temporary binaries
for diagnosis.

The remaining examples show how to run individual tests during development.

```powershell
& 'C:\FreeBASIC\fbc.exe' '-i' '.\vendor\omaGui' `
    'tests\midi_model_smoke.bas' 'midi_model.bas' `
    '-x' 'tests\midi_model_smoke.exe'
& '.\tests\midi_model_smoke.exe' `
    'C:\path\to\song.mid'
```

The score-selection state and bulk note-editing paths have a deterministic
test that does not open the GUI:

```powershell
& 'C:\FreeBASIC\fbc.exe' 'tests\note_selection_smoke.bas' `
    'note_selection.bas' 'midi_model.bas' `
    '-x' 'tests\note_selection_smoke.exe'
& '.\tests\note_selection_smoke.exe'
```

The Add Note palette timing and accidental rules have a separate deterministic
test:

```powershell
& 'C:\FreeBASIC\fbc.exe' 'tests\score_tools_smoke.bas' `
    'score_tools.bas' '-x' 'tests\score_tools_smoke.exe'
& '.\tests\score_tools_smoke.exe'
```

Stable staff layout has a regression test for the former behavior where
inserting one note could change the track's average pitch, flip its automatic
clef, and move every existing note vertically:

```powershell
& 'C:\FreeBASIC\fbc.exe' 'tests\score_layout_smoke.bas' `
    'score_layout.bas' '-x' 'tests\score_layout_smoke.exe'
& '.\tests\score_layout_smoke.exe'
```

Visual regression runs can ask the gfxlib backend to save its own framebuffer
as a deterministic 24-bit BMP after a bounded number of settled frames. Set
`OSE_TEST_SNAPSHOT` to the output filename, optionally set
`OSE_TEST_SNAPSHOT_FRAME`, and set `OSE_TEST_WIDTH` and `OSE_TEST_HEIGHT` for a
specific bounded client size. `OSE_TEST_OPEN_ADD_PALETTE=1` expands the note
palette. `OSE_TEST_MODAL` accepts `about`, `audio`, `automation`, `confirm`,
`file_open`, `keyboard`, `microphone`, `midi_input`, `midi_output`,
`midi_save`, `mod_export`, `note`, `project_save`, `tempo`, `track`, or
`wav_export`; `options_menu` opens the Options popup for theme inspection.
Tests may also set `OSE_TEST_MOUSE_X` and `OSE_TEST_MOUSE_Y` to
place the mocked pointer over the score without moving the desktop cursor.
`OSE_TEST_VISUAL_DEVICES=1` supplies stable representative MIDI device rows
only while a snapshot is active. These environment variables are ignored
during ordinary launches.

`tests/run_visual_regression.ps1` builds or accepts a current editor, captures
49 reviewed views, and compares decoded pixels against compressed PNG files in
`tests/visual_baselines`. It covers both mixer pages at the supported 800 x 600
minimum, Light, Dark, and Black main windows, Options popups, and representative
dialogs at 1280 x 720, plus Desktop and Touch layouts, an independently
vertical-zoomed Touch score, the expanded note palette, and every generated
modal route.
The runner rejects a capture whose real dimensions differ from
the requested dimensions, preventing desktop clamping from creating a falsely
labeled baseline. Use
`-UpdateBaselines` only after inspecting every changed image; ordinary test
runs never rewrite the reviewed evidence.

`OSE_TEST_CONTROL_REPORT` is the bounded application-level contract hook used
by the Windows runner. It opens each persistent dialog in turn and rejects any
visible action button or menu item whose callback is missing or is not the
handler assigned to that command. It also dispatches real pointer and text
input to every application-owned textbox and real pointer selection to every
application-owned list, then restores the exact fixture state.

The audio/project layer has a standalone smoke test:

```powershell
& 'C:\FreeBASIC\fbc.exe' 'tests\audio_tracks_smoke.bas' `
    'audio_tracks.bas' '-x' 'tests\audio_tracks_smoke.exe'
& '.\tests\audio_tracks_smoke.exe' '.\tests\audio-test.ose'
```

Sample playback has a separate PCM integration test. It fills all 64 sfxlib
sample slots, renders the final slot, deletes the first of two distinct tone
clips, and proves from captured zero crossings that the following waveform
moved into slot zero. It also rejects stale mappings and invalid channel,
index, and pitch bounds. When one backing WAV becomes damaged, the test proves
that only its slot goes offline, a neighboring valid clip still renders, and a
repaired file reloads its current PCM. The Audio list marks unavailable clips
as `[offline]`. The same test runs under leak detection on Linux.

The native MIDI-input boundary also has a no-device-safe smoke test. It does not
open a real device, so it is safe to run on a machine without MIDI hardware:

```powershell
& 'C:\FreeBASIC\fbc.exe' 'tests\midi_input_smoke.bas' `
    'midi_input_win.bas' 'midi_input_protocol.bas' `
    '-x' 'tests\midi_input_smoke.exe'
& '.\tests\midi_input_smoke.exe'
```

The input protocol also has a deterministic harness. It validates
short-message filtering, split SysEx assembly, reset behavior, FIFO order, and
queue-drop accounting without opening a device:

```powershell
& 'C:\FreeBASIC\fbc.exe' 'tests\midi_input_protocol_smoke.bas' `
    'midi_input_protocol.bas' `
    '-x' 'tests\midi_input_protocol_smoke.exe'
& '.\tests\midi_input_protocol_smoke.exe'
```

For an end-to-end test with a physical or virtual loopback port, build the
loopback smoke program and run it once without arguments to list the separate
input and output indices. Then pass the matching input and output indices:

```powershell
& 'C:\FreeBASIC\fbc.exe' '-i' '.\vendor\omaGui' `
    'tests\midi_loopback_smoke.bas' 'midi_input_win.bas' `
    'midi_input_protocol.bas' 'midi_output_sfx.bas' `
    '-x' 'tests\midi_loopback_smoke.exe'
& '.\tests\midi_loopback_smoke.exe'
& '.\tests\midi_loopback_smoke.exe' <input-index> <output-index>
```

The final invocation sends Note On, Poly Pressure, Controller, Program Change,
Channel Pressure, Pitch Bend, and Note Off through the native output and
requires the ordered sequence to return through native input within two
seconds. The indices are intentionally separate because operating systems can
number a virtual port differently in their input and output lists. On Linux,
compile with `midi_alsa.bas`, link `midi_input_protocol.bas`, and pass `auto
auto` to select the standard ALSA `Midi Through` endpoint.

The native MIDI-output boundary has a no-device-safe smoke test:

```powershell
& 'C:\FreeBASIC\fbc.exe' 'tests\midi_output_smoke.bas' `
    'midi_output_sfx.bas' '-x' 'tests\midi_output_smoke.exe'
& '.\tests\midi_output_smoke.exe'
```

Software playback also has a MIDI-to-PCM integration test. It loads a real
Standard MIDI File, schedules every editable note through the production
software-synth adapter, advances sfxlib deterministically, and rejects a valid
WAV whose PCM peak is silent:

```powershell
& 'C:\FreeBASIC\fbc.exe' -mt 'tests\midi_playback_audio_smoke.bas' `
    'midi_model.bas' 'audio_tracks.bas' 'wav_export_sfx.bas' `
    'playback_mix.bas' 'soundfont_bank.bas' 'soundfont_synth.bas' `
    'software_synth.bas' 'sfx_runtime.bas' `
    '-x' 'tests\midi_playback_audio_smoke.exe'
& '.\tests\midi_playback_audio_smoke.exe' `
    '.\tests\midi-playback-audio-smoke.mid' `
    '.\tests\midi-playback-audio-smoke.wav'
```

The SoundFont smoke test creates its own tiny, unencumbered SF2 fixture. It
checks malformed-bank rejection, transactional replacement, GM bank/program
fallback, sample and loop bounds, deterministic non-silent PCM rendering, and
the null-driver worker lifecycle. No downloaded SoundFont is committed to the
test suite.

An optional full-bank gate checks a user-supplied GM SoundFont without adding
it to the repository. It requires all 128 melodic programs and bank 128
percussion, resolves 388 representative note mappings, and renders six
instrument families plus a drum voice. This is the command used for Timbres
of Heaven 4.00(G):

```powershell
& 'C:\FreeBASIC\fbc.exe' -mt 'tests\soundfont_compatibility.bas' `
    'soundfont_bank.bas' 'soundfont_synth.bas' 'playback_mix.bas' `
    'sfx_runtime.bas' '-x' 'tests\soundfont_compatibility.exe'
& '.\tests\soundfont_compatibility.exe' 'C:\SoundFonts\your-bank.sf2'
```

The playback endurance test accelerates 30 seconds of production synthesis
through the hardware-independent null-driver foreground feed while scheduling
more than ten thousand varied notes. It requires exact PCM frame accounting,
zero underruns, useful signal in the first and final seconds, and enough
headroom to avoid full-scale clipping.

The two export paths have deterministic binary tests. The MOD test verifies
the `M.K.` header, 31-sample table, pattern image, generated sample length, and
four-channel reduction report. The WAV test advances sfxlib's null driver in a
foreground feed and validates the captured file through the project WAV
parser:

```powershell
& 'C:\FreeBASIC\fbc.exe' 'tests\music_export_smoke.bas' `
    'midi_model.bas' 'music_export.bas' `
    '-x' 'tests\music_export_smoke.exe'
& '.\tests\music_export_smoke.exe' '.\tests\music-export-smoke.mod'

& 'C:\FreeBASIC\fbc.exe' 'tests\wav_export_smoke.bas' `
    'audio_tracks.bas' 'wav_export_sfx.bas' `
    '-x' 'tests\wav_export_smoke.exe'
$env:SFXLIB_DRIVER = 'null'
& '.\tests\wav_export_smoke.exe' '.\tests\wav-export-smoke.wav'
```

The pitch detector has a deterministic hardware-independent smoke test. It
generates a mono PCM WAV containing A4 and C5, verifies their MIDI pitches and
durations, and rejects malformed input:

```powershell
& 'C:\FreeBASIC\fbc.exe' 'tests\pitch_transcriber_smoke.bas' `
    'pitch_transcriber.bas' '-x' 'tests\pitch_transcriber_smoke.exe'
& '.\tests\pitch_transcriber_smoke.exe' `
    '.\tests\pitch-transcriber-smoke.wav'
```

The notation-duration fixture verifies whole through 64th-note round trips,
keeps all four isolated flag counts visible, and includes both up-stem and
down-stem beam runs. Its 64th-note row also exercises bounded short-rest
decomposition at a measure boundary:

```powershell
& 'C:\FreeBASIC\fbc.exe' '-i' '.\vendor\omaGui' `
    'tests\notation_duration_smoke.bas' 'midi_model.bas' `
    '-x' 'tests\notation_duration_smoke.exe'
& '.\tests\notation_duration_smoke.exe' `
    '.\tests\notation-duration-smoke.mid'
```

The parser rejects files outside its explicit size and chunk bounds. Playback
uses the tempo-aware sfxlib software-synth path; the current implementation
supports General MIDI program families, temporal program/volume/expression/pan
and pitch-bend state, percussion on channel 10, imported tempo maps, and
bounded note scheduling. Later tempo and controller automation is preserved on
save while the initial tempo, mix, and effect values remain editable in the
UI. Windows input uses the public WinMM API because FreeBASIC's sfxlib MIDI
commands are output-only. Linux input and output use the public ALSA Sequencer
API. See `CLEAN_ROOM.md` before creating a release archive.

When an independently supplied `music-screen-glyphs.mask` is available beside
the editor or in its working directory, the generic mask loader can use it for
accidentals, quarter and eighth rests, and the augmentation dot. Whole through
64th notes use independent filled omaGUI polygon outlines for their hollow or
solid heads, stems, and one through four flags. No private font, generated mask,
original program, or reverse-engineering workspace is retained by the project.
The editor uses independent drawing fallbacks when the optional mask is absent.

## Source archive

`prepare_source_release.ps1` creates an explicit source-only ZIP containing
the reviewed project files and tests. It refuses to overwrite an existing
archive and does not copy generated executables, edited MIDI files, recovered
payloads, screenshots, or decompiler output. ZIP entry paths always use
forward slashes so Linux extraction does not reinterpret Windows separators:

```powershell
& '.\prepare_source_release.ps1' `
    -OutputArchive 'E:\Midisoft\OpenSesh-source.zip'
```

For a fail-closed Windows evidence bundle, choose a directory that does not
already exist and is outside the source tree:

```powershell
& '.\verify_windows_release.ps1' `
    -EvidenceDirectory 'E:\Midisoft\OpenSesh-release-evidence'
```

The verifier runs the complete Windows suite, checks maintained FreeBASIC files
with the strict Windows lint profile, separately records the byte-pinned omaGui
lint boundary, compares every project Linux-target warning group to the
reviewed portability baseline, verifies the locked Windows toolchain, builds
and version-checks the editor, and compares every archived byte with the
current source tree. It also requires two byte-identical stripped executable
builds, parses the final PE image for x64 architecture, reviewed system DLLs,
ASLR and NX flags, zero build timestamp, no debug sections, no overlay, and no
local path leakage. Eight deliberately unsafe PE mutations must fail closed.

The same run creates two byte-identical portable ZIPs and independently
verifies the retained copy. The nine-file customer bundle contains the exact
executable, readme, GPL and linked-library notices, an internal SHA-256
manifest, build identity, and the exact corresponding source ZIP. Seven
corrupt, incomplete, traversal, duplicate, changed-timestamp, and modified
package variants must be rejected. It retains the logs, executable, source
ZIP, portable ZIP, SHA-256 hashes, archive manifest, and a
`release-evidence.json` summary. The JSON deliberately keeps
`commercial_release_ready` false because Linux graphical runtime, hardware,
accessibility, signing, licensing, and release-owner gates remain separate.

The package is intentionally unsigned while the product version remains
`0.9.0-dev`. It can also be created explicitly after building the executable
and source archive:

```powershell
& '.\prepare_windows_portable_package.ps1' `
    -ExecutablePath '.\OpenSesh-0.9.0-dev-windows.exe' `
    -SourceArchivePath '.\OpenSesh-source-0.9.0-dev.zip' `
    -OutputPackage '.\OpenSesh-0.9.0-dev-windows-portable.zip'
```

The exact source ZIP can be exercised independently on Linux after its hash and
entry count have been taken from `release-evidence.json`:

```bash
bash ./verify_linux_release_archive.sh \
    /path/to/OpenSesh-source-0.9.0-dev.zip \
    EXPECTED_SHA256 EXPECTED_ENTRY_COUNT
```

That verifier rejects an unexpected archive root or traversal path, runs all
58 hardware-independent Linux tests, and builds the complete editor using only
the extracted source and the host FreeBASIC toolchain. On Midcom, require the
fifty-ninth native ALSA loopback test and the graphical runtime contract:

```bash
REQUIRE_LINUX_UI_RUNTIME=1 \
REQUIRE_LINUX_MIDI_LOOPBACK=1 \
LINUX_UI_DISPLAY=:0 \
LINUX_UI_XAUTHORITY=/path/to/the/display.xauthority \
bash ./verify_linux_release_archive.sh \
    /path/to/OpenSesh-source-0.9.0-dev.zip \
    EXPECTED_SHA256 EXPECTED_ENTRY_COUNT
```

The Linux MIDI contract selects `Midi Through` automatically unless explicit
`OSE_MIDI_INPUT_INDEX` and `OSE_MIDI_OUTPUT_INDEX` values are supplied. The
Linux UI contract launches the extracted editor thirty-one times across
twenty-one framebuffer captures, two control audits, and eight smoothness
scenarios. It repeats the 324-control and 508-behavior application audit in
both Desktop and Touch profiles, and requires one passing 480-frame
measurement in each smoothness scenario. Use `-CaseNames` with
`tests/run_ui_smoothness.ps1` to investigate named scenarios with the same
acceptance thresholds; release verification uses all eight cases.
Sixteen 800 x 600 cases cover all three themes for main, Options, About, drums,
and active-meter views, plus one View menu. Five 1920 x 1080 cases cover every
main theme, the Dark Options theme menu, the full 16-channel mixer, and an
active meter. It uses internal
mocked input and moves test windows off-screen; it does not replace physical
MIDI, microphone, speaker, high-DPI, or accessibility approval.

The archive includes and byte-verifies the exact omaGui runtime source. It
still expects the FreeBASIC toolchain and its sfxlib archive to be supplied
under their own licensing terms. `THIRD_PARTY_NOTICES.md` preserves the
notices for components present in audited binaries, while
`RELEASE_CHECKLIST.md` records the automated gates and the remaining manual
requirements for a signed 1.0 binary release.

Saving rebuilds note events from the editable model while retaining unrelated
channel, meta, sysex, and system events. The current editor edits the initial
tempo, channel mix, and channel effects and exposes bounded non-note channel
event editing. The Map dialog can add or remove later tempo, meter, and
key-signature points. The score includes basic duration, accidental, and rest
rendering, but full engraved notation is not yet exposed. The Events editor exposes non-note
channel messages and supported system-common messages through their standard
MIDI status types.
The Info window edits the selected track name and the first document title,
copyright, lyric, and marker text events.
Same-key overlapping notes are matched in bounded
FIFO order during import so regenerated note durations remain stable.

The model smoke test also exercises adding a track before saving. The separate
`tests\empty_document_smoke.bas` test covers creating a two-track document,
removing the second track, compacting its note and event indices, and saving
the remaining document.

The `.ose` project container is intentionally small and independent of the
reference application:

```text
OSEPROJECT 1
MIDI <character-count>
<MIDI path>
CLIPS <count>
CLIP <start-tick> <duration-ms> <gain-permille> <path-character-count>
<WAV path>
```

The loader bounds the file, clip count, path lengths, tick values, gains, and
duration values before committing the temporary clip list.

## Software-synth smoke test

```powershell
& 'C:\FreeBASIC\fbc.exe' 'tests\sfxlib_smoke.bas' '-x' 'tests\sfxlib_smoke.exe'
$env:SFXLIB_DRIVER = 'null'
& '.\tests\sfxlib_smoke.exe'
```

<!-- end of README.md -->
