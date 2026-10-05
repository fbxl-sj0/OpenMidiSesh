#!/usr/bin/env python3
"""
Project: OpenSesh
File: tests/source_archive_safety.py

Purpose:
    Exercise source ZIP extraction boundaries with small synthetic archives.
Responsibilities:
    - prove regular files are accepted and dangerous metadata is rejected
    - remove every temporary fixture after the test run
This file intentionally does not compile or run archived application code.
"""

from __future__ import annotations

from pathlib import Path
import stat
import sys
import tempfile
import unittest
import warnings
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import check_source_archive


class ArchiveSafety(unittest.TestCase):
    def setUp(self) -> None:
        self.work = tempfile.TemporaryDirectory(prefix="opensesh-zip-test-")
        self.addCleanup(self.work.cleanup)
        self.archive = Path(self.work.name) / "source.zip"

    def write_entries(self, entries: list[str | zipfile.ZipInfo]) -> None:
        # Duplicate names are intentional corrupt inputs in this fixture.
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.archive, "w") as archive:
                for entry in entries:
                    archive.writestr(entry, b"source\n")

    def test_regular_windows_and_unix_files(self) -> None:
        unix_file = zipfile.ZipInfo("opensesh/src/editor.bi")
        unix_file.external_attr = (stat.S_IFREG | 0o644) << 16
        self.write_entries(["opensesh/README.md", unix_file])
        self.assertEqual(check_source_archive.check_archive(self.archive, 2), 2)

    def test_unsafe_paths(self) -> None:
        for name in ("/opensesh/a", "other/a", "opensesh/../a", "opensesh/./a",
                     "opensesh//a", "opensesh/C:a",
                     "opensesh/a\nb", "opensesh/a/"):
            with self.subTest(name=name):
                self.write_entries([name])
                with self.assertRaises(ValueError):
                    check_source_archive.check_archive(self.archive, 1)

    def test_unportable_zip_metadata(self) -> None:
        # Normal ZIP writers truncate NULs and may normalize backslashes on
        # Windows. Mutate both metadata records to preserve the corrupt input.
        for name in (b"opensesh/a\x00b", b"opensesh/a\\b"):
            with self.subTest(name=name):
                self.write_entries(["opensesh/aZb"])
                self.archive.write_bytes(self.archive.read_bytes().replace(b"opensesh/aZb", name))
                with self.assertRaises(ValueError):
                    check_source_archive.check_archive(self.archive, 1)

    def test_duplicate_paths(self) -> None:
        for second in ("opensesh/README.md", "opensesh/readme.md"):
            with self.subTest(second=second):
                self.write_entries(["opensesh/README.md", second])
                with self.assertRaises(ValueError):
                    check_source_archive.check_archive(self.archive, 2)

    def test_nonregular_files(self) -> None:
        for kind in (stat.S_IFLNK, stat.S_IFIFO, stat.S_IFDIR, stat.S_IFCHR):
            with self.subTest(kind=kind):
                entry = zipfile.ZipInfo("opensesh/source")
                entry.create_system = 3
                entry.external_attr = (kind | 0o644) << 16
                self.write_entries([entry])
                with self.assertRaises(ValueError):
                    check_source_archive.check_archive(self.archive, 1)

    def test_encryption_and_compression_metadata(self) -> None:
        for encrypted in (True, False):
            with self.subTest(encrypted=encrypted):
                self.write_entries(["opensesh/README.md"])
                data = bytearray(self.archive.read_bytes())
                central = data.index(b"PK\x01\x02")
                if encrypted:
                    data[6] |= 1
                    data[central + 8] |= 1
                else:
                    data[8] = 255
                    data[central + 10] = 255
                self.archive.write_bytes(data)
                with self.assertRaises(ValueError):
                    check_source_archive.check_archive(self.archive, 1)

    def test_count_and_size_limits(self) -> None:
        self.write_entries(["opensesh/README.md"])
        for count in (0, 2, 100001):
            with self.subTest(count=count), self.assertRaises(ValueError):
                check_source_archive.check_archive(self.archive, count)
        original_limit = check_source_archive.MAX_SOURCE_BYTES
        try:
            check_source_archive.MAX_SOURCE_BYTES = 1
            with self.assertRaises(ValueError):
                check_source_archive.check_archive(self.archive, 1)
        finally:
            check_source_archive.MAX_SOURCE_BYTES = original_limit


if __name__ == "__main__":
    unittest.main()

# end of tests/source_archive_safety.py
