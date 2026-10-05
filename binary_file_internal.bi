/'
    Project: OpenSesh
    File: binary_file_internal.bi

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Internal binaryFile_* bounded file reads; no separately linked API.
    Purpose: Require complete binary reads at persistence boundaries.
    Responsibilities: Validate the requested span and check both runtime status
        and the number of bytes actually transferred into caller-owned storage.
    This file intentionally does NOT contain:

        - buffer allocation or file ownership
        - format serialization or document state changes
'/

#ifndef __OSE_BINARY_FILE_INTERNAL_BI__
#define __OSE_BINARY_FILE_INTERNAL_BI__

' FreeBASIC's large file positions are signed 64-bit offsets.
Const BINARY_FILE_MAX_POSITION As LongInt = &H7FFFFFFFFFFFFFFFLL

Private Function binaryFile_ReadExact( _
    ByVal fileNumber As Integer, _
    ByVal filePosition As LongInt, _
    ByVal destination As Any Ptr, _
    ByVal byteCount As Integer _
) As Integer
    /'
        GET can return success at EOF after reading fewer bytes than requested.
        Its fifth argument reports the actual byte count as a native-sized
        integer. Read through a byte pointer so this count has the same units
        for strings, arrays, and fixed-width file fields. Positions are the
        one-based offsets used by FreeBASIC's binary file API.

        The caller supplies a buffer of at least byteCount bytes and discards
        any partial contents on failure. No other thread may mutate this
        buffer or reposition the same file handle during the call.
    '/
    Dim As UInteger bytesRead = 0
    If fileNumber < 1 OrElse filePosition < 1 OrElse destination = 0 OrElse _
        byteCount < 1 Then Return 0
    If filePosition - 1 > BINARY_FILE_MAX_POSITION - byteCount Then Return 0
    If Get(#fileNumber, filePosition, *Cast(UByte Ptr, destination), _
        byteCount, bytesRead) <> 0 Then Return 0
    Return IIf(bytesRead = CUInt(byteCount), -1, 0)
End Function

#endif

/' end of binary_file_internal.bi '/
