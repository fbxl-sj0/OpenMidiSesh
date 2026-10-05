/'
    Project: omaGUI Portable Raster Images
    --------------------------------------

    File: raster_image.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for raster_image.

    Purpose:

        Declare a small content-sniffing raster image loader for omaGUI.

    Responsibilities:

        - expose checked local-file and in-memory image loading
        - retain decoded gfxlib image buffers and their dimensions
        - expose one matching destruction routine

    This file intentionally does NOT contain:

        - HTML layout or widget behavior
        - networking, URL handling, or platform image APIs
        - animation playback or general-purpose image editing
'/

#ifndef __RASTER_IMAGE_BI__
#define __RASTER_IMAGE_BI__

#include once "src/backend/backend.bi"

Const RASTERIMAGE_MAX_FILE_BYTES As LongInt = 33554432
Const RASTERIMAGE_MAX_DIMENSION As Long = 4096
Const RASTERIMAGE_MAX_PIXELS As ULongInt = 16777216ULL

Const RASTERIMAGE_FORMAT_UNKNOWN As Integer = 0
Const RASTERIMAGE_FORMAT_BMP As Integer = 1
Const RASTERIMAGE_FORMAT_PNG As Integer = 2
Const RASTERIMAGE_FORMAT_GIF As Integer = 3
Const RASTERIMAGE_FORMAT_JPEG As Integer = 4
Const RASTERIMAGE_FORMAT_ICO As Integer = 5

Type RasterImage
    As Any Ptr pixels
    As Long width
    As Long height
    As Integer formatKind
    As Integer hasAlpha
End Type

Declare Function rasterimage_LoadFile( _
    ByVal filePath As String, _
    ByRef loadedImage As RasterImage Ptr, _
    ByRef errorMessage As String _
) As Integer

Declare Function rasterimage_LoadMemory( _
    bytes() As UByte, _
    ByVal byteCount As LongInt, _
    ByRef loadedImage As RasterImage Ptr, _
    ByRef errorMessage As String _
) As Integer

Declare Function rasterimage_DetectFormat( _
    bytes() As UByte, ByVal byteCount As LongInt _
) As Integer

Declare Function rasterimage_ScaleToFit( _
    ByVal loadedImage As RasterImage Ptr, _
    ByVal maximumWidth As Long, ByVal maximumHeight As Long, _
    ByRef errorMessage As String, ByVal allowEnlarge As Integer = 0, _
    ByVal smooth As Integer = 0 _
) As Integer

Declare Sub rasterimage_Destroy(ByVal loadedImage As RasterImage Ptr)

#endif

/' end of raster_image.bi '/
