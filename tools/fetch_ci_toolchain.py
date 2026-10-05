#!/usr/bin/env python3
"""
Project: OpenSesh
File: tools/fetch_ci_toolchain.py
Purpose: download the exact public compiler files reviewed for native CI.
Responsibilities: enforce names, lengths, SHA-256 and exclusive file creation.
This file does not install or execute the downloaded compiler.
"""

import argparse
import hashlib
from pathlib import Path
import re
import tomllib
import urllib.request


def fetch(target: str, destination: Path) -> None:
    config = tomllib.loads(Path(__file__).with_name("ci_toolchains.toml").read_text())
    destination.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        raise ValueError("The compiler download directory must not be a link.")
    for item in config[target]["files"]:
        name, size, expected = item["name"], item["size"], item["sha256"]
        if (not re.fullmatch(r"[A-Za-z0-9._-]+", name)
                or not re.fullmatch(r"[0-9a-f]{64}", expected)
                or not 1 <= size <= 1024 * 1024 * 1024):
            raise ValueError("Invalid compiler download identity.")
        path = destination / name
        digest = hashlib.sha256()
        count = 0
        created = False
        # The pinned publisher's bytes are checked before a package manager or
        # compiler executes anything. Partial downloads cannot look installed.
        try:
            with urllib.request.urlopen(config["base_url"] + "/" + name, timeout=60) as response:
                with path.open("xb") as output:
                    created = True
                    while chunk := response.read(1024 * 1024):
                        count += len(chunk)
                        if count > size:
                            raise ValueError("Compiler download exceeded its reviewed length.")
                        digest.update(chunk)
                        output.write(chunk)
            if count != size or digest.hexdigest() != expected:
                raise ValueError("Compiler download identity mismatch: " + name)
        except BaseException:
            if created and path.exists():
                path.unlink()
            raise
        print("verified_compiler_package=" + name, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=("windows", "linux", "freebsd", "netbsd", "openbsd", "haiku"))
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    fetch(arguments.target, arguments.destination)

# end of tools/fetch_ci_toolchain.py
