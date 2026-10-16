/'
    Project: omaGUI
    ---------------

    File: filesystem.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for filesystem.

    Purpose:

        Expose the small filesystem operations needed by portable widgets and
        applications without exposing platform-specific directory APIs.

    Responsibilities:

        - enumerate directory entries through a caller-owned callback
        - identify directories while keeping platform calls inside omaGUI

    This file intentionally does NOT contain:

        - file content loading or saving policy
        - file dialog layout or application search behavior
        - graphics, input, or window management
'/

#ifndef __SYSTEM_FILESYSTEM_BI__
#define __SYSTEM_FILESYSTEM_BI__

Const SYSTEM_DIRECTORY_FILES As Integer = 1
Const SYSTEM_DIRECTORY_FOLDERS As Integer = 2
Const SYSTEM_FILE_ATTRIBUTE_DIRECTORY As UInteger = &h10
Const SYSTEM_FILE_ATTRIBUTE_REPARSE_POINT As UInteger = &h400

Type SystemDirectoryEntryHandler As Function( _
    ByRef entryName As Const String, _
    ByVal attributes As UInteger, _
    ByVal context As Any Ptr _
) As Integer

Declare Function system_EnumerateDirectory( _
    ByRef directoryPath As Const String, _
    ByVal entryKinds As Integer, _
    ByVal handler As SystemDirectoryEntryHandler, _
    ByVal context As Any Ptr _
) As Integer

Declare Function system_IsDirectory(ByRef directoryPath As Const String) As Integer

' Attribute-only queries must not open streams, which can block on devices or
' FIFOs. Size is -1 where the host bridge has no safe size query; dates are
' FreeBASIC date serials, or zero when unavailable. GUI-thread use only.
Declare Function system_PathExists(ByRef pathValue As Const String) As Integer
Declare Sub system_GetFileDetails(ByRef pathValue As Const String, ByRef sizeValue As LongInt, ByRef modifiedValue As Double)

#endif

' end of filesystem.bi
