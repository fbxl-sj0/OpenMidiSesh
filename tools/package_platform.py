#!/usr/bin/env python3
"""
Project: OpenSesh
File: tools/package_platform.py
Purpose: create and exercise a portable package on the actual target OS.
Responsibilities: include corresponding source, verify bytes, test extracted startup.
This file does not cross-compile or certify physical audio/MIDI hardware.
"""

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import stat
import subprocess
import tarfile
import tempfile
import tomllib
import zipfile

from check_repository import read_manifest, dependency_files
from check_source_archive import check_archive
from ci_editor_smoke import check_editor


SYSTEMS = {"Windows": "windows", "Linux": "linux", "FreeBSD": "freebsd",
           "NetBSD": "netbsd", "OpenBSD": "openbsd", "Haiku": "haiku"}
EPOCH = 946684800  # Fixed 2000-01-01 UTC, independent of the build clock.

# These requirements were checked against DT_NEEDED in the qualified native
# executables. Review them when changing the pinned compiler or target OS.
RUNTIME_NOTES = {
    "windows": "Requires 64-bit Windows 10 or newer; only system DLLs are used.\n",
    "linux": (
        "Requires Ubuntu 26.04 or compatible glibc 2.43 and an X11 desktop.\n"
        "ALSA, PulseAudio client and terminfo libraries must be installed.\n"
        "On Ubuntu 26.04, install the runtime packages with:\n"
        "  sudo apt install libasound2t64 libpulse0 libtinfo6 libx11-6 libxext6 "
        "libxpm4 libxrandr2 libxrender1\n"
    ),
    "freebsd": (
        "Requires FreeBSD 15.1 and an X11 desktop with libX11, libXext, libXpm,\n"
        "libXrandr and libXrender. The base ncursesw/terminfo libraries are used.\n"
        "If these X11 libraries are missing, install them as root with:\n"
        "  pkg install libX11 libXext libXpm libXrandr libXrender\n"
    ),
    "netbsd": (
        "Requires NetBSD 11.0 with the base X11 sets and pkgsrc ncurses.\n"
        "The executable needs libncurses.so.6 in addition to base system libraries.\n"
        "Install ncurses as root with:\n"
        "  pkgin install ncurses\n"
    ),
    "openbsd": (
        "Requires OpenBSD 7.8 with its X11 sets installed.\n"
        "Audio, curses and threading libraries are supplied by the base system.\n"
    ),
    "haiku": (
        "Requires Haiku r1beta6 x86_64, its native desktop and ncurses6.\n"
        "Install the ncurses runtime with:\n"
        "  pkgman install ncurses6\n"
        "The editor uses a fixed window on this pinned runtime.\n"
    ),
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_bytes(root: Path) -> bytes:
    names = read_manifest(root) | dependency_files(root)
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
        for name in sorted(names):
            entry = zipfile.ZipInfo("opensesh/" + name, (2000, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, (root / name).read_bytes())
    return buffer.getvalue()


def archive_bytes(files: dict[str, bytes], executable: str, windows: bool) -> bytes:
    buffer = io.BytesIO()
    if windows:
        with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=9) as archive:
            for name, data in sorted(files.items()):
                entry = zipfile.ZipInfo(name, (2000, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = (0o100755 if name == executable else 0o100644) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, data)
    else:
        with gzip.GzipFile(fileobj=buffer, mode="wb", filename="", mtime=EPOCH) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT) as archive:
                for name, data in sorted(files.items()):
                    entry = tarfile.TarInfo(name)
                    entry.size = len(data)
                    entry.mode = 0o755 if name == executable else 0o644
                    entry.mtime = EPOCH
                    archive.addfile(entry, io.BytesIO(data))
    return buffer.getvalue()


def verify_archive(data: bytes, files: dict[str, bytes], windows: bool) -> dict[str, bytes]:
    """Require exactly the reviewed regular files before any extraction."""
    contents = {}
    if windows:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            entries = archive.infolist()
            if len(entries) != len(files) or {entry.filename for entry in entries} != set(files):
                raise ValueError("Package ZIP inventory mismatch.")
            for entry in entries:
                if (entry.flag_bits & 1 or entry.is_dir()
                        or stat.S_IFMT(entry.external_attr >> 16) != stat.S_IFREG
                        or archive.read(entry) != files[entry.filename]):
                    raise ValueError("Package ZIP content mismatch.")
                contents[entry.filename] = archive.read(entry)
    else:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            entries = archive.getmembers()
            if len(entries) != len(files) or {entry.name for entry in entries} != set(files):
                raise ValueError("Package TAR inventory mismatch.")
            for entry in entries:
                if not entry.isfile() or archive.extractfile(entry).read() != files[entry.name]:
                    raise ValueError("Package TAR content mismatch.")
                contents[entry.name] = archive.extractfile(entry).read()
    return contents


def package(executable: Path, tests: Path, destination: Path) -> None:
    root = Path(__file__).resolve().parent.parent
    system = SYSTEMS.get(platform.system())
    if system is None or platform.machine().lower() not in ("amd64", "x86_64"):
        raise ValueError("A supported native x86_64 host is required.")
    test_text = tests.read_text()
    passed = re.findall(r"^tests_passed=(\d+)\s*$", test_text, re.MULTILINE)
    failed = re.findall(r"^tests_failed=(\d+)\s*$", test_text, re.MULTILINE)
    expected_tests = 61 if system == "windows" else 60
    if len(passed) != 1 or int(passed[0]) != expected_tests or failed != ["0"]:
        raise ValueError("A complete passing native test report is required.")
    built_smoke = json.loads((root / "build/ci/editor/editor-smoke.json").read_text())
    if built_smoke.get("status") != "pass":
        raise ValueError("Native editor launch checks are required.")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"],
                               cwd=root, text=True).strip():
        raise ValueError("Do not package modified tracked source.")
    compiler = os.environ.get("FREEBASIC_PATH", "fbc")
    banner = subprocess.check_output([compiler, "-version"], text=True).splitlines()[0]
    version_text = (root / "src/version.bi").read_text()
    version = re.search(r'OSE_VERSION_TEXT As String = "([0-9A-Za-z.+-]+)"', version_text)[1]
    native_name = "opensesh.exe" if system == "windows" else "opensesh"
    prefix = "opensesh-" + version + "-" + system + "-x86_64/"
    source = source_bytes(root)
    locks = tomllib.loads((root / "tools/ci_toolchains.toml").read_text())
    evidence = {
        "schema_version": 1, "product": "OpenSesh", "application_version": version,
        "source_commit": commit, "system": system, "architecture": "x86_64",
        "native_os_release": platform.release(), "compiler": banner,
        "compiler_downloads": locks[system]["files"],
        "runtime_requirements": RUNTIME_NOTES[system],
        "tests_passed": int(passed[0]), "tests_failed": 0,
        "built_editor": built_smoke,
        "external_midi": system in ("windows", "linux"),
        "executable_sha256": digest(executable.read_bytes()),
        "corresponding_source_sha256": digest(source),
        "physical_device_qualification": "not_run",
    }
    files = {prefix + native_name: executable.read_bytes(),
             prefix + "opensesh-source.zip": source,
             prefix + "BUILD-INFO.json": (json.dumps(evidence, indent=2, sort_keys=True) + "\n").encode()}
    for name in ("COPYING", "COPYING.LESSER", "LICENSE", "THIRD_PARTY_NOTICES.md"):
        files[prefix + name] = (root / name).read_bytes()
    files[prefix + "README.txt"] = (
        "OpenSesh " + version + " for " + system + " x86_64\n\n"
        "Extract this entire archive, then run " + native_name + ".\n"
        "Source, build instructions and user documentation are in opensesh-source.zip.\n"
        + RUNTIME_NOTES[system] + "\n"
        "BSD and Haiku have editing and software synthesis; external MIDI endpoints\n"
        "are currently unavailable. SoundFonts are supplied by the user.\n"
        "See BUILD-INFO.json for the exact native OS, compiler, source and checks.\n"
        "These development packages are unsigned and physical devices are unqualified.\n"
    ).encode()
    data = archive_bytes(files, prefix + native_name, system == "windows")
    if data != archive_bytes(files, prefix + native_name, system == "windows"):
        raise ValueError("Package creation is not deterministic.")
    verified_contents = verify_archive(data, files, system == "windows")
    destination.mkdir(parents=True, exist_ok=True)
    filename = prefix.rstrip("/") + (".zip" if system == "windows" else ".tar.gz")
    # Only create files. Never replace a previous download or release artifact.
    with tempfile.TemporaryDirectory(prefix="opensesh-package-check-") as directory:
        extracted = Path(directory)
        # The verified inventory was assembled locally from explicit portable
        # names. Write those verified bytes, without general archive extraction.
        for name, content in verified_contents.items():
            path = extracted / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        extracted_executable = extracted / prefix / native_name
        extracted_executable.chmod(0o755)
        check_archive(extracted / prefix / "opensesh-source.zip", len(read_manifest(root) | dependency_files(root)))
        check_editor(extracted_executable, root / "build/ci/packaged-editor")
    evidence["packaged_editor"] = json.loads((root / "build/ci/packaged-editor/editor-smoke.json").read_text())
    evidence["package"] = filename
    evidence["package_sha256"] = digest(data)
    with (destination / filename).open("xb") as stream:
        stream.write(data)
    with (destination / (system + "-validation.json")).open("x", encoding="utf-8") as stream:
        json.dump(evidence, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print("native_package=pass " + filename + " sha256=" + digest(data))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("tests", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    package(arguments.executable, arguments.tests, arguments.destination)

# end of tools/package_platform.py
