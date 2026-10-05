/'
    Project: omaGUI CHM Reader
    -------------------------

    File: chmarchive.bi

    Purpose:

        Declare a read-only, on-demand reader for Microsoft Compiled HTML
        Help archives.

    Responsibilities:

        - retain a bounded CHM directory and reset table
        - read stored or LZX-compressed members on demand
        - cache at most one decompressed LZX reset interval

    This file intentionally does NOT contain:

        - HTML parsing or widget rendering
        - extraction of the archive to the filesystem
        - operating-system CHM services or external archive libraries

    The archive and LZX implementation are based on the LGPL-2.1-or-later
    libmspack implementation. See LICENSES/LGPL-2.1.txt.
'/ 

#ifndef __OMAGUI_CHMARCHIVE_BI__
#define __OMAGUI_CHMARCHIVE_BI__

#include once "src/archive/chm_lzx.bi"

Const CHMARCHIVE_MAX_ENTRIES As Integer = 16384
Const CHMARCHIVE_MAX_RESET_ENTRIES As Integer = 65536
Const CHMARCHIVE_MAX_ENTRY_NAME_BYTES As Integer = 1024
Const CHMARCHIVE_MAX_MEMBER_BYTES As LongInt = 67108864
Const CHMARCHIVE_MAX_FILE_BYTES As LongInt = 1073741824
Const CHMARCHIVE_MAX_DIRECTORY_CHUNK_BYTES As Integer = 8192

Type ChmArchiveEntry
    As String nameText
    As Integer sectionIndex
    As LongInt offset
    As LongInt length
End Type

Type ChmArchive
    As String filePath
    As LongInt fileLength
    As LongInt section0Offset
    As LongInt contentOffset
    As LongInt contentLength
    As LongInt compressedDataLength
    As LongInt uncompressedLength
    As Integer chunkSize
    As Integer numberOfChunks
    As Integer firstPmglChunk
    As Integer lastPmglChunk
    As Integer entryCount
    As ChmArchiveEntry entries(0 To CHMARCHIVE_MAX_ENTRIES - 1)
    As Integer windowBits
    As Integer resetIntervalBytes
    As Integer resetFrameCount
    As Integer resetEntryCount
    As Integer resetEntrySize
    As LongInt resetOffsets(0 To CHMARCHIVE_MAX_RESET_ENTRIES - 1)
    As String cachedResetData
    As Integer cachedResetFrame = -1
End Type

Declare Function chmarchive_Open( _
    ByRef filePath As Const String, ByRef errorText As String _
) As ChmArchive Ptr
Declare Sub chmarchive_Close(ByRef archive As ChmArchive Ptr)
Declare Function chmarchive_ReadFile( _
    ByVal archive As ChmArchive Ptr, _
    ByRef memberName As Const String, _
    ByRef memberText As String, _
    ByRef errorText As String, _
    ByVal maximumMemberBytes As LongInt = CHMARCHIVE_MAX_MEMBER_BYTES _
) As Integer
Declare Function chmarchive_Contains( _
    ByVal archive As ChmArchive Ptr, _
    ByRef memberName As Const String _
) As Integer
Declare Function chmarchive_MemberCount( _
    ByVal archive As ChmArchive Ptr _
) As Integer
Declare Function chmarchive_GetMemberInfo( _
    ByVal archive As ChmArchive Ptr, ByVal memberIndex As Integer, _
    ByRef memberName As String, ByRef sectionIndex As Integer _
) As Integer

#endif

/' end of chmarchive.bi '/
