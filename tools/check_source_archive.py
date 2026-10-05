#!/usr/bin/env python3
"""
Project: OpenSesh
File: tools/check_source_archive.py

Purpose:
    Check ZIP metadata before the Linux verifier extracts source files.
Responsibilities:
    - require portable, unique paths beneath the opensesh directory
    - reject links, special files, encryption and excessive expanded content
This file intentionally does not extract, execute or authenticate an archive.
"""

import argparse
from pathlib import Path
import stat
import sys
import zipfile


# The release source is currently under 32 MiB expanded. A 1 GiB ceiling leaves
# room for future font/test data while preventing unbounded extraction to /tmp.
MAX_SOURCE_BYTES = 1024 * 1024 * 1024
MAX_SOURCE_FILES = 100000


def check_archive(path: Path, expected_count: int) -> int:
    if not 1 <= expected_count <= MAX_SOURCE_FILES:
        raise ValueError("Source file count must be between 1 and 100000.")
    names: set[str] = set()
    expanded_bytes = 0
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if len(entries) != expected_count:
            raise ValueError("Source archive entry count mismatch.")
        for entry in entries:
            name = entry.orig_filename
            parts = name.split("/")
            if (name != entry.filename or len(parts) < 2 or parts[0] != "opensesh"
                    or any(part in ("", ".", "..") for part in parts)
                    or "\\" in name or ":" in name
                    or any(ord(character) < 32 or ord(character) > 126 for character in name)):
                raise ValueError(f"Unsafe source archive path: {name!r}")
            if name.casefold() in names:
                raise ValueError(f"Duplicate source archive path: {name}")
            names.add(name.casefold())
            # Unix creators put the file type in the upper attributes. A zero
            # type is normal for Windows ZIP writers; explicit special types
            # and the DOS directory bit must never reach the extractor.
            file_type = stat.S_IFMT(entry.external_attr >> 16)
            if file_type not in (0, stat.S_IFREG) or entry.external_attr & 0x10:
                raise ValueError(f"Nonregular source archive entry: {name}")
            if entry.flag_bits & 1:
                raise ValueError(f"Encrypted source archive entry: {name}")
            if entry.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                raise ValueError(f"Unsupported source archive compression: {name}")
            expanded_bytes += entry.file_size
            if expanded_bytes > MAX_SOURCE_BYTES:
                raise ValueError("Expanded source archive exceeds the 1 GiB limit.")
    return len(names)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("expected_count", type=int)
    options = parser.parse_args()
    count = check_archive(options.archive, options.expected_count)
    print(f"source_archive_structure=ok files={count}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"source_archive_structure=failed: {error}", file=sys.stderr)
        sys.exit(1)

# end of tools/check_source_archive.py
