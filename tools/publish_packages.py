#!/usr/bin/env python3
"""
Project: OpenSesh
File: tools/publish_packages.py
Purpose: publish a complete native package set after all CI jobs pass.
Responsibilities: enforce target/commit/hash evidence and create checksum assets.
This file does not overwrite an existing published release or accept partial sets.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def publish(directory: Path) -> None:
    tag = os.environ.get("GITHUB_REF_NAME", "")
    commit = os.environ.get("GITHUB_SHA", "")
    if (os.environ.get("GITHUB_ACTIONS") != "true"
            or os.environ.get("GITHUB_REF_TYPE") != "tag"
            or os.environ.get("GITHUB_REPOSITORY") != "fbxl-sj0/OpenMidiSesh"
            or not re.fullmatch(r"v[0-9A-Za-z.+-]+", tag)
            or not re.fullmatch(r"[0-9a-f]{40}", commit)):
        raise ValueError("A trusted version-tag job is required.")
    targets = {"windows", "linux", "freebsd", "netbsd", "openbsd", "haiku"}
    evidence = []
    expected_files = set()
    for target in sorted(targets):
        report_path = directory / (target + "-validation.json")
        report = json.loads(report_path.read_text())
        filename = report["package"]
        if (not re.fullmatch(r"opensesh-[0-9A-Za-z.+-]+-" + target + r"-x86_64\.(zip|tar\.gz)", filename)
                or report["system"] != target or report["architecture"] != "x86_64"
                or report["source_commit"] != commit or report["tests_failed"] != 0
                or report["tests_passed"] != (61 if target == "windows" else 60)
                or report["built_editor"]["status"] != "pass"
                or report["packaged_editor"]["status"] != "pass"):
            raise ValueError("Unqualified native target: " + target)
        package = directory / filename
        if package.is_symlink() or hashlib.sha256(package.read_bytes()).hexdigest() != report["package_sha256"]:
            raise ValueError("Package checksum mismatch: " + target)
        expected_files.update((filename, report_path.name))
        evidence.append(report)
    if {path.name for path in directory.iterdir()} != expected_files:
        raise ValueError("Unexpected or missing package-set files.")
    if len({report["corresponding_source_sha256"] for report in evidence}) != 1:
        raise ValueError("Native packages contain different corresponding source.")
    summary = directory / "CI-SUMMARY.json"
    summary.write_text(json.dumps({"tag": tag, "source_commit": commit, "targets": evidence},
                                 indent=2, sort_keys=True) + "\n")
    assets = sorted(directory.iterdir())
    checksums = directory / "SHA256SUMS.txt"
    checksums.write_text("".join(hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name + "\n"
                                  for path in assets))
    body = directory.parent / "native-release-notes.md"
    body.write_text("Download the archive for your x86_64 operating system and extract it before running OpenSesh.\n\n"
                    "All six packages passed native compilation, deterministic tests, Desktop/Touch editor checks "
                    "and startup checks of the extracted executable. Each includes corresponding source and licenses. "
                    "Exact compiler, OS, source and test evidence is in CI-SUMMARY.json.\n\n"
                    "Windows: 64-bit Windows 10 or newer. Linux: Ubuntu 26.04 or compatible glibc 2.43/X11/ALSA. "
                    "FreeBSD: 15.1 with X11. NetBSD: 11.0 with X11. OpenBSD: 7.8 with X11. Haiku: r1beta6 x86_64.\n\n"
                    "BSD and Haiku external MIDI endpoints are unavailable; editing and software synthesis are supported. "
                    "These unsigned development builds have no physical-device or frame-pacing qualification from hosted CI.\n\n"
                    "This is distribution revision " + tag + "; the application reports " + evidence[0]["application_version"] + ".\n")
    command = ["gh", "release", "create", tag, "--verify-tag", "--title", "OpenSesh " + tag[1:],
               "--notes-file", str(body), "--repo", "fbxl-sj0/OpenMidiSesh"]
    if "dev" in tag:
        command.append("--prerelease")
    subprocess.run(command + [str(path) for path in assets] + [str(checksums)], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    publish(parser.parse_args().directory)

# end of tools/publish_packages.py
