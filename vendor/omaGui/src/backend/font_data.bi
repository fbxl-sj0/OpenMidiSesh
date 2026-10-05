/'
    Project: omaGUI
    ---------------

    File: font_data.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for font_data.

    Purpose:

        Declare the default embedded glyph table used by the text backend.

    Responsibilities:

        - expose printable ASCII glyph pointers
        - expose the bundled heading font pointers
        - expose pointer initialization after glyph data is linked

    This file intentionally does NOT contain:

        - generated glyph bytes
        - text layout or rasterization
'/

#ifndef __FONT_DATA_BI__
#define __FONT_DATA_BI__

#ifndef font_chars_defined
Extern font_chars(32 To 126) As UByte Ptr
#define font_chars_defined
#endif

#ifdef OMAGUI_REDISTRIBUTABLE_FONTS
#ifndef font_omagui_sans_18_bold_defined
Extern font_omagui_sans_18_bold_chars(32 To 126) As UByte Ptr
#define font_omagui_sans_18_bold_defined
#endif
#ifndef font_omagui_serif_18_regular_defined
Extern font_omagui_serif_18_regular_chars(32 To 126) As UByte Ptr
#define font_omagui_serif_18_regular_defined
#endif
#else
#ifndef font_liberation_sans_18_bold_defined
Extern font_liberation_sans_18_bold_chars(32 To 126) As UByte Ptr
#define font_liberation_sans_18_bold_defined
#endif

#ifndef font_liberation_serif_18_regular_defined
Extern font_liberation_serif_18_regular_chars(32 To 126) As UByte Ptr
#define font_liberation_serif_18_regular_defined
#endif
#endif

Declare Sub font_init_pointers()

#endif

/' end of font_data.bi '/
