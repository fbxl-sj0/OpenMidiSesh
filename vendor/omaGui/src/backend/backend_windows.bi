/'
    Project: omaGUI
    File: backend_windows.bi
    Purpose: Declare the small Windows ABI used by native GUI bridges.
    Responsibilities: Keep handle types, imports and constants out of the
        application's global namespace; retain 32-bit Windows scalar widths.
    This file intentionally does NOT contain: drawing, input or widget policy.

    HWND/HGLOBAL/HANDLE are borrowed opaque pointers. SIZE_T is pointer-sized,
    while BOOL, UINT and MMRESULT remain 32-bit on both Windows architectures.
    These declarations match winuser.bi, winbase.bi and mmsystem.bi. Clipboard
    allocations transfer to Windows only after SetClipboardData succeeds.
'/
#ifndef __OMAGUI_BACKEND_WINDOWS_BI__
#define __OMAGUI_BACKEND_WINDOWS_BI__
#if defined(__FB_WIN32__)
#inclib "user32"
#inclib "kernel32"
Namespace omaGUI_NativeWindows
    Const RestoreWindow As Long = 9 ' SW_RESTORE preserves the normal window size.
    Const TextFormat As ULong = 1 ' CF_TEXT is the current single-byte clipboard ABI.
    Const MovableMemory As ULong = &h2 ' GMEM_MOVEABLE is required by the clipboard.
    Const ZeroedMemory As ULong = &h40 ' GMEM_ZEROINIT includes the terminator.
    /'
        WIN32_FIND_DATAA is a 320-byte, four-byte-aligned Windows record:
        attributes; three FILETIME pairs; size high/low; two reserved DWORDs;
        a 260-byte filename and a 14-byte alternate filename, then padding.
        Keep the timestamps as DWORD pairs to retain the SDK's alignment.
    '/
    Type FindData
        As ULong dwFileAttributes
        As ULong creationLow, creationHigh, accessLow, accessHigh, writeLow, writeHigh
        As ULong fileSizeHigh, fileSizeLow, reserved0, reserved1
        As ZString * 260 cFileName
        As ZString * 14 alternateName
    End Type
    #if sizeof(FindData) <> 320
        #error omaGUI Windows directory record does not match the native ABI
    #endif
    Extern "Windows"
        Declare Function IsIconic Alias "IsIconic" (ByVal windowHandle As Any Ptr) As Long
        Declare Function ShowWindow Alias "ShowWindow" (ByVal windowHandle As Any Ptr, ByVal command As Long) As Long
        Declare Function SetForegroundWindow Alias "SetForegroundWindow" (ByVal windowHandle As Any Ptr) As Long
        Declare Function OpenClipboard Alias "OpenClipboard" (ByVal windowHandle As Any Ptr) As Long
        Declare Function CloseClipboard Alias "CloseClipboard" () As Long
        Declare Function EmptyClipboard Alias "EmptyClipboard" () As Long
        Declare Function IsClipboardFormatAvailable Alias "IsClipboardFormatAvailable" (ByVal formatValue As ULong) As Long
        Declare Function GetClipboardData Alias "GetClipboardData" (ByVal formatValue As ULong) As Any Ptr
        ' fblint: disable-next-line FBL971 REASON: SetClipboardData transfers a mutable HGLOBAL handle to the clipboard owner.
        Declare Function SetClipboardData Alias "SetClipboardData" (ByVal formatValue As ULong, ByVal memoryHandle As Any Ptr) As Any Ptr
        Declare Function GlobalAlloc Alias "GlobalAlloc" (ByVal flags As ULong, ByVal byteCount As UInteger) As Any Ptr
        Declare Function GlobalFree Alias "GlobalFree" (ByVal memoryHandle As Any Ptr) As Any Ptr
        Declare Function GlobalLock Alias "GlobalLock" (ByVal memoryHandle As Any Ptr) As Any Ptr
        Declare Function GlobalUnlock Alias "GlobalUnlock" (ByVal memoryHandle As Any Ptr) As Long
        Declare Function GlobalSize Alias "GlobalSize" (ByVal memoryHandle As Any Ptr) As UInteger
        Declare Function FindFirstFileA Alias "FindFirstFileA" (ByVal pathText As Const ZString Ptr, ByVal dataValue As FindData Ptr) As Any Ptr
        ' fblint: disable-next-line FBL971 REASON: FindNextFileA writes the caller's native directory record; its output pointer is mutable.
        Declare Function FindNextFileA Alias "FindNextFileA" (ByVal searchHandle As Any Ptr, ByVal dataValue As FindData Ptr) As Long
        Declare Function FindClose Alias "FindClose" (ByVal searchHandle As Any Ptr) As Long
        Declare Function GetFileAttributesA Alias "GetFileAttributesA" (ByVal pathText As Const ZString Ptr) As ULong
#if not defined(__FB_GFXLIB3__)
        #inclib "winmm"
        Declare Function timeBeginPeriod Alias "timeBeginPeriod" (ByVal milliseconds As ULong) As ULong
        Declare Function timeEndPeriod Alias "timeEndPeriod" (ByVal milliseconds As ULong) As ULong
#endif
    End Extern
End Namespace
#endif
#endif
' end of backend_windows.bi
