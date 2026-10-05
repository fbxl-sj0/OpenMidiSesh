OpenSesh
===================

File: PORTABLE_README.txt

Purpose:

    Explain the supported use and contents of the portable Windows package.

This development package runs on 64-bit Windows 10 and later. It does not
install system services, request administrator privileges, or write files into
the application directory during normal use.

To start the editor, extract the complete ZIP archive and run
OpenSesh.exe. Preferences are stored for the current user in:

    %LOCALAPPDATA%\OpenSesh\settings.conf

The package contains the exact corresponding source archive used by the build,
the GPL license, linked-library notices, and SHA-256 checksums. Keep those files
together when redistributing the program.

This 0.9.0-dev package is intentionally unsigned and is not a public 1.0
release. A public Windows release must be signed and timestamped by the release
owner and must pass the remaining hardware and accessibility checks documented
in the source-tree RELEASE_CHECKLIST.md.

End of PORTABLE_README.txt
