#!/usr/bin/env python3
"""
Project: OpenSesh
File: tests/ci_package_safety.py
Purpose: reject corrupted packages and unsafe compiler-download failure cleanup.
Responsibilities: exercise ownership boundaries, integrity checks and link rejection.
This file does not download real compilers or execute target binaries.
"""

import hashlib
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
from fetch_ci_toolchain import fetch
from package_platform import archive_bytes, verify_archive


class PackageSafety(unittest.TestCase):
    def download(self, folder, payload, expected=b"compiler"):
        config = {"base_url": "https://example.invalid", "haiku": {"files": [{
            "name": "compiler.hpkg", "size": len(expected),
            "sha256": hashlib.sha256(expected).hexdigest()}]}}
        with patch("fetch_ci_toolchain.tomllib.loads", return_value=config), \
                patch("fetch_ci_toolchain.urllib.request.urlopen", return_value=io.BytesIO(payload)):
            fetch("haiku", Path(folder))

    def test_existing_download_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "compiler.hpkg"
            path.write_bytes(b"user-owned")
            with self.assertRaises(FileExistsError):
                self.download(folder, b"compiler")
            self.assertEqual(path.read_bytes(), b"user-owned")

    def test_corrupted_download_is_removed(self):
        for payload in (b"corrupt!", b"short", b"compiler-too-large"):
            with self.subTest(payload=payload), tempfile.TemporaryDirectory() as folder:
                with self.assertRaises(ValueError):
                    self.download(folder, payload)
                self.assertEqual(list(Path(folder).iterdir()), [])

    def test_download_accepts_reviewed_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            self.download(folder, b"compiler")
            self.assertEqual((Path(folder) / "compiler.hpkg").read_bytes(), b"compiler")

    def test_archive_detects_corruption_and_extra_files(self):
        files = {"opensesh/opensesh": b"executable", "opensesh/LICENSE": b"license"}
        for windows in (True, False):
            with self.subTest(windows=windows):
                data = archive_bytes(files, "opensesh/opensesh", windows)
                self.assertEqual(verify_archive(data, files, windows), files)
                changed = dict(files, **{"opensesh/LICENSE": b"changed"})
                with self.assertRaises(ValueError):
                    verify_archive(data, changed, windows)
                extra = dict(files, **{"../outside": b"unreviewed"})
                with self.assertRaises(ValueError):
                    verify_archive(archive_bytes(extra, "opensesh/opensesh", windows), files, windows)

    def test_archive_rejects_links(self):
        files = {"opensesh/opensesh": b"target"}
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            entry = zipfile.ZipInfo("opensesh/opensesh")
            entry.create_system = 3
            entry.external_attr = 0o120777 << 16
            archive.writestr(entry, b"target")
        with self.assertRaises(ValueError):
            verify_archive(buffer.getvalue(), files, True)
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
            entry = tarfile.TarInfo("opensesh/opensesh")
            entry.type = tarfile.SYMTYPE
            entry.linkname = "../../outside"
            archive.addfile(entry)
        with self.assertRaises(ValueError):
            verify_archive(buffer.getvalue(), files, False)


if __name__ == "__main__":
    unittest.main()

# end of tests/ci_package_safety.py
