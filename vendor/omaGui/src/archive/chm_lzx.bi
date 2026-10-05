/'
    Project: omaGUI CHM Reader
    -------------------------

    File: chm_lzx.bi

    Purpose:

        Declare the bounded LZX decompressor used by CHM archive reads.

    Responsibilities:

        - expose one reset-interval decompression operation
        - keep codec state private to the archive implementation

    This file intentionally does NOT contain:

        - CHM directory or file lookup
        - temporary-file or platform codec APIs
        - a public end-user compression API

    The decoder follows the LZX format and the FreeBASIC port is based on
    the LGPL-2.1-or-later libmspack implementation. See LICENSES/LGPL-2.1.txt.
'/ 

#ifndef __OMAGUI_CHM_LZX_BI__
#define __OMAGUI_CHM_LZX_BI__

Const CHM_LZX_FRAME_BYTES As Integer = 32768
Const CHM_LZX_MAX_WINDOW_BITS As Integer = 21
Const CHM_LZX_MAX_WINDOW_BYTES As Integer = 2097152
Const CHM_LZX_MAX_RESET_BYTES As Integer = 4194304

Declare Function chmlzx_DecompressReset( _
    ByRef compressedText As Const String, _
    ByVal outputLength As Integer, _
    ByVal windowBits As Integer, _
    ByVal resetFrameCount As Integer, _
    ByRef outputText As String, _
    ByRef errorText As String _
) As Integer

#endif

/' end of chm_lzx.bi '/
