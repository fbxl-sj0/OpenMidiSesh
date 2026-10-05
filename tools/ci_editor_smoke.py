#!/usr/bin/env python3
"""
Project: OpenSesh
File: tools/ci_editor_smoke.py
Purpose: launch the real editor on its native graphics backend in CI.
Responsibilities: exercise Desktop/Touch contracts and verify framebuffer output.
This file does not certify physical MIDI/audio devices or frame-pacing limits.
"""

import argparse
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import wave


def check_editor(executable: Path, output: Path) -> None:
    executable = executable.resolve(strict=True)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="opensesh-ci-window-") as directory:
        work = Path(directory)
        midi = work / "example.mid"
        # The selected-phrase audit requires two real notes, at different ticks.
        track = bytes.fromhex("00ff510307a12000903c648360803c0000904064"
                              "836080400000ff2f00")
        midi.write_bytes(b"MThd" + struct.pack(">IHHH", 6, 0, 1, 480)
                         + b"MTrk" + struct.pack(">I", len(track)) + track)
        audio = work / "example.wav"
        with wave.open(str(audio), "wb") as stream:
            stream.setparams((1, 2, 44100, 0, "NONE", "not compressed"))
            samples = (int(6000 * math.sin(index * 2 * math.pi * 440 / 44100))
                       for index in range(8192))
            stream.writeframes(b"".join(struct.pack("<h", sample) for sample in samples))
        base_environment = os.environ.copy()
        base_environment.update(SFXLIB_DRIVER="null", OSE_TEST_HIDE_WINDOW="1",
                                OSE_TEST_AUDIO_FIXTURE=str(audio))
        for mode in ("Desktop", "Touch"):
            environment = base_environment.copy()
            report = output / (mode.lower() + "-controls.txt")
            preferences = work / (mode + ".conf")
            interaction = "fine" if mode == "Desktop" else "touch"
            preferences.write_text("format=OpenSeshPreferences\nversion=1\n"
                                   + "theme=dark\ninteraction=" + interaction + "\n")
            environment.update(OSE_TEST_CONTROL_REPORT=str(report.resolve()),
                               OSE_TEST_PREFERENCES_FILE=str(preferences))
            log = output / (mode.lower() + "-window.log")
            with log.open("xb") as stream:
                subprocess.run([str(executable), str(midi)], cwd=work, env=environment,
                               stdout=stream, stderr=subprocess.STDOUT,
                               timeout=60, check=True)
            lines = set(report.read_text().splitlines())
            required = {"status=ok", "total_controls=324", "behavior_checks=508",
                        "startup_interaction=" + mode, "persisted_interaction=" + mode}
            if not required <= lines:
                raise ValueError("Native " + mode + " editor audit failed: " + str(report))
        environment = base_environment.copy()
        snapshot = output / "native-frame.bmp"
        environment.update(OSE_TEST_SNAPSHOT=str(snapshot.resolve()),
                           OSE_TEST_SNAPSHOT_FRAME="12", OSE_TEST_WIDTH="800",
                           OSE_TEST_HEIGHT="600", OSE_TEST_PREFERENCES_FILE=str(work / "snapshot.conf"))
        with (output / "snapshot-window.log").open("xb") as stream:
            subprocess.run([str(executable), str(midi)], cwd=work, env=environment,
                           stdout=stream, stderr=subprocess.STDOUT, timeout=60, check=True)
        image = snapshot.read_bytes()
        if (len(image) < 54 or image[:2] != b"BM"
                or struct.unpack_from("<ii", image, 18) != (800, 600)
                or struct.unpack_from("<H", image, 28)[0] != 24):
            raise ValueError("Native framebuffer capture is not an 800x600 24-bit BMP.")
        (output / "editor-smoke.json").write_text(json.dumps({
            "status": "pass", "native_editor_launches": 3,
            "control_contracts": 648, "behavior_checks": 1016,
            "framebuffer": "800x600x24", "frame_pacing_qualification": "not_run"
        }, indent=2) + "\n")
    print("native_editor_smoke=pass controls=648 behaviors=1016 launches=3", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    check_editor(arguments.executable, arguments.output)

# end of tools/ci_editor_smoke.py
