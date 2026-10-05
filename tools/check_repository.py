#!/usr/bin/env python3
"""
Project: OpenSesh
File: tools/check_repository.py

Purpose:
    Verify the reviewed source boundary before CI or source packaging.
Responsibilities:
    - validate portable paths, dependency hashes and documentation links
    - reject unlisted maintained inputs and generated files in Git
    - work with Python's standard library on Windows and Linux
This file intentionally does not compile code or update any manifest.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


def checked_path(root: Path, name: str) -> Path:
    """Release paths have one portable spelling and resolve inside the tree."""
    parts = name.split("/")
    if (not name or name != name.strip() or "\\" in name or ":" in name
            or any(part in ("", ".", "..") for part in parts)
            or any(ord(character) < 32 or ord(character) > 126 for character in name)):
        raise ValueError(f"Unsafe release path: {name!r}")
    path = root.joinpath(*parts)
    if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root):
        raise ValueError(f"Missing or nonregular release file: {name}")
    return path


def read_manifest(root: Path) -> set[str]:
    names: set[str] = set()
    folded: set[str] = set()
    for line in (root / "release_manifest.txt").read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        checked_path(root, line)
        if line.casefold() in folded:
            raise ValueError(f"Duplicate release path: {line}")
        names.add(line)
        folded.add(line.casefold())
    if not names:
        raise ValueError("The project release manifest is empty.")
    return names


def dependency_files(root: Path) -> set[str]:
    vendor = root / "vendor/omaGui"
    names = {"vendor/omaGui/DEPENDENCY.md", "vendor/omaGui/SNAPSHOT.sha256"}
    for line in (vendor / "SNAPSHOT.sha256").read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([0-9a-f]{64})  ([ -~]+)", line)
        if match is None:
            raise ValueError("Malformed GUI dependency manifest.")
        digest, relative = match.groups()
        path = checked_path(vendor, relative)
        name = "vendor/omaGui/" + relative
        if name in names or "font_arial" in relative or relative.endswith("font_data_impl.bi"):
            raise ValueError(f"Duplicate or excluded GUI payload: {relative}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"Changed GUI dependency bytes: {relative}")
        names.add(name)
    if len(names) <= 2:
        raise ValueError("The GUI release manifest is empty.")
    return names


def maintained_files(root: Path) -> set[str]:
    names = set()
    for path in root.iterdir():
        if path.is_file() and path.suffix in (".ps1", ".sh", ".md", ".json", ".toml"):
            names.add(path.name)
    for directory in ("src", "docs", "tools", ".github"):
        names.update(path.relative_to(root).as_posix()
                     for path in (root / directory).rglob("*")
                     if path.is_file() and "__pycache__" not in path.parts)
    names.update(path.relative_to(root).as_posix() for path in (root / "tests").iterdir()
                 if path.is_file() and path.suffix in (".bas", ".bi", ".ps1", ".sh", ".py", ".sha256"))
    names.update(path.relative_to(root).as_posix()
                 for path in (root / "tests/visual_baselines").glob("*.png"))
    return names


def check_links(root: Path, names: set[str]) -> None:
    # Repository-relative Markdown links must survive the docs/src move. Code
    # fences are examples, not live links, and URL fragments are checked by the
    # document renderer rather than guessed from heading text here.
    for name in sorted(names):
        if not name.endswith(".md"):
            continue
        text = (root / name).read_text(encoding="utf-8")
        text = re.sub(r"```.*?```", "", text, flags=re.DOTALL)
        for destination in re.findall(r"!?\[[^\]]*\]\(([^)]+)\)", text):
            target = destination.split("#", 1)[0]
            if not target or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
                continue
            link = (root / PurePosixPath(name).parent / target).resolve()
            if not link.is_relative_to(root) or not link.exists():
                raise ValueError(f"Broken documentation link in {name}: {destination}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tracked", action="store_true",
                        help="require Git's tracked files to equal the release source boundary")
    options = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    project = read_manifest(root)
    vendor = dependency_files(root)
    missing = maintained_files(root) - project
    if missing:
        raise ValueError("Maintained inputs absent from release manifest: " + ", ".join(sorted(missing)))
    check_links(root, project)
    if options.tracked:
        result = subprocess.run(["git", "ls-files", "-z"], cwd=root, check=True, stdout=subprocess.PIPE)
        tracked = set(result.stdout.decode("utf-8").rstrip("\0").split("\0"))
        expected = project | vendor
        if tracked != expected:
            raise ValueError("Git/release manifest mismatch: missing="
                             + repr(sorted(expected - tracked)) + " extra=" + repr(sorted(tracked - expected)))
    print(f"project_release_files={len(project)}")
    print(f"gui_release_files={len(vendor) - 2}")
    print("repository_integrity=ok")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"repository_integrity=failed: {error}", file=sys.stderr)
        sys.exit(1)

# end of tools/check_repository.py
