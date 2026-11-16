/'
    Project: omaGUI Generated Bitmap Font
    ------------------------------------

    File: font_omagui_sans_10_regular.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Embedded bitmap font tables selected by omaGUI; no runtime entry point.

    Purpose:

        Store one generated bitmap font for the omaGUI renderer.

    Responsibilities:

        - embed printable-ASCII glyph dimensions and alpha-mask data
        - initialize the glyph-pointer table used by the renderer

    Source font:

        Liberation Sans Regular (SIL Open Font License 1.1), point size 10

    This file intentionally does NOT contain:

        - runtime font selection
        - text layout logic
        - the source TrueType font
'/

#ifndef __FONT_OMAGUI_SANS_10_REGULAR_BI__
#define __FONT_OMAGUI_SANS_10_REGULAR_BI__

' Format: Width, Height, AlphaData...
' This module owns the pointer table and initializes it before text rendering.
' fblint: disable-next-line FBL301
Dim Shared As UByte Ptr font_omagui_sans_10_regular_chars(32 To 126)

' Font data for character 32 (' ')
Static Shared As UByte font_omagui_sans_10_regular_char_32_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0 , _
0 }

' Font data for character 33 ('!')
Static Shared As UByte font_omagui_sans_10_regular_char_33_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  21,220,0, _
  15,214,0, _
  8,207,0, _
  1,200,0, _
  0,190,0, _
  0,0,0, _
  24,216,0, _
  0,0,0, _
  0,0,0 , _
0 }

' Font data for character 34 ('"')
Static Shared As UByte font_omagui_sans_10_regular_char_34_data(...) = { _
  4, 12, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  142,76,191,24, _
  127,62,178,10, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0 , _
0 }

' Font data for character 35 ('#')
Static Shared As UByte font_omagui_sans_10_regular_char_35_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,14,124,0,136,0, _
  0,68,71,1,134,0, _
  180,255,255,255,255,132, _
  0,138,1,92,47,0, _
  244,255,255,255,255,68, _
  20,116,0,139,0,0, _
  73,65,3,132,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 36 ('$')
Static Shared As UByte font_omagui_sans_10_regular_char_36_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,120,36,0,0, _
  29,180,213,195,162,4, _
  133,89,120,36,59,11, _
  95,173,147,36,0,0, _
  0,86,205,215,120,1, _
  0,0,120,42,173,73, _
  101,17,120,36,147,80, _
  69,191,217,194,151,3, _
  0,0,120,36,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 37 ('%')
Static Shared As UByte font_omagui_sans_10_regular_char_37_data(...) = { _
  9, 12, _
  0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0, _
  55,163,168,24,0,21,173,1,0, _
  149,32,80,101,0,158,37,0,0, _
  148,32,82,99,75,119,0,0,0, _
  51,165,169,35,178,46,169,169,35, _
  0,0,0,145,50,129,52,61,120, _
  0,0,59,136,0,129,52,61,120, _
  0,6,179,9,0,40,166,165,31, _
  0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0 , _
0 }

' Font data for character 38 ('&')
Static Shared As UByte font_omagui_sans_10_regular_char_38_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,21,182,165,138,0,0, _
  0,86,112,0,199,0,0, _
  0,43,179,163,96,0,0, _
  13,168,220,63,0,174,0, _
  129,91,36,196,78,135,0, _
  144,72,0,100,249,27,0, _
  31,181,165,175,124,195,87, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 39 (''')
Static Shared As UByte font_omagui_sans_10_regular_char_39_data(...) = { _
  2, 12, _
  0,0, _
  0,0, _
  0,0, _
  118,96, _
  103,82, _
  0,0, _
  0,0, _
  0,0, _
  0,0, _
  0,0, _
  0,0, _
  0,0 , _
0 }

' Font data for character 40 ('(')
Static Shared As UByte font_omagui_sans_10_regular_char_40_data(...) = { _
  4, 12, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  0,23,185,11, _
  0,166,58,0, _
  19,204,0,0, _
  73,150,0,0, _
  91,133,0,0, _
  73,150,0,0, _
  19,204,0,0, _
  0,165,57,0, _
  0,23,184,11 , _
0 }

' Font data for character 41 (')')
Static Shared As UByte font_omagui_sans_10_regular_char_41_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  140,79,0, _
  6,205,13, _
  0,126,99, _
  0,68,157, _
  0,49,174, _
  0,66,157, _
  0,122,101, _
  5,203,14, _
  138,81,0 , _
0 }

' Font data for character 42 ('*')
Static Shared As UByte font_omagui_sans_10_regular_char_42_data(...) = { _
  4, 12, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  0,92,70,0, _
  141,169,166,122, _
  0,173,154,0, _
  43,112,133,20, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0 , _
0 }

' Font data for character 43 ('+')
Static Shared As UByte font_omagui_sans_10_regular_char_43_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,8,5,0,0, _
  0,0,112,72,0,0, _
  0,0,112,72,0,0, _
  94,184,215,204,184,63, _
  0,0,112,72,0,0, _
  0,0,91,58,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 44 (',')
Static Shared As UByte font_omagui_sans_10_regular_char_44_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  20,222,0, _
  1,133,0, _
  0,0,0 , _
0 }

' Font data for character 45 ('-')
Static Shared As UByte font_omagui_sans_10_regular_char_45_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  112,200,178, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0 , _
0 }

' Font data for character 46 ('.')
Static Shared As UByte font_omagui_sans_10_regular_char_46_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  24,220,0, _
  0,0,0, _
  0,0,0 , _
0 }

' Font data for character 47 ('/')
Static Shared As UByte font_omagui_sans_10_regular_char_47_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,33,162, _
  0,107,90, _
  0,178,20, _
  8,191,0, _
  72,129,0, _
  146,56,0, _
  200,2,0, _
  0,0,0, _
  0,0,0 , _
0 }

' Font data for character 48 ('0')
Static Shared As UByte font_omagui_sans_10_regular_char_48_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  1,144,187,193,57,0, _
  71,161,0,24,207,0, _
  132,90,0,0,203,19, _
  150,76,0,0,188,37, _
  131,92,0,0,204,18, _
  67,167,0,28,203,0, _
  1,140,188,191,52,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 49 ('1')
Static Shared As UByte font_omagui_sans_10_regular_char_49_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,57,218,104,0,0, _
  6,149,132,104,0,0, _
  0,0,124,104,0,0, _
  0,0,124,104,0,0, _
  0,0,124,104,0,0, _
  0,0,124,104,0,0, _
  45,192,223,218,192,15, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 50 ('2')
Static Shared As UByte font_omagui_sans_10_regular_char_50_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  4,159,188,199,83,0, _
  71,136,0,20,222,0, _
  0,0,0,35,201,0, _
  0,0,22,193,53,0, _
  0,39,197,49,0,0, _
  16,202,32,0,0,0, _
  117,227,192,192,192,12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 51 ('3')
Static Shared As UByte font_omagui_sans_10_regular_char_51_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  8,165,185,199,85,0, _
  80,117,0,20,222,0, _
  0,0,3,77,182,0, _
  0,0,193,216,65,0, _
  0,0,0,14,221,11, _
  112,114,0,9,229,10, _
  17,179,190,201,103,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 52 ('4')
Static Shared As UByte font_omagui_sans_10_regular_char_52_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,13,227,76,0, _
  0,0,146,188,76,0, _
  0,55,152,136,76,0, _
  5,191,19,136,76,0, _
  122,97,0,136,76,0, _
  134,176,176,218,199,46, _
  0,0,0,136,76,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 53 ('5')
Static Shared As UByte font_omagui_sans_10_regular_char_53_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  54,231,192,192,141,0, _
  72,145,0,0,0,0, _
  91,214,180,204,78,0, _
  22,34,0,21,225,4, _
  0,0,0,0,205,25, _
  55,61,0,24,220,1, _
  32,190,191,195,66,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 54 ('6')
Static Shared As UByte font_omagui_sans_10_regular_char_54_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,94,186,200,110,0, _
  24,175,1,5,54,0, _
  93,172,162,198,87,0, _
  116,166,0,13,224,3, _
  101,129,0,0,204,22, _
  41,198,2,15,219,1, _
  0,117,189,195,75,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 55 ('7')
Static Shared As UByte font_omagui_sans_10_regular_char_55_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  93,192,192,192,245,12, _
  0,0,0,67,147,0, _
  0,0,4,198,15,0, _
  0,0,92,127,0,0, _
  0,0,195,36,0,0, _
  0,12,221,0,0,0, _
  0,43,194,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 56 ('8')
Static Shared As UByte font_omagui_sans_10_regular_char_56_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  8,167,170,183,83,0, _
  88,148,0,11,224,0, _
  50,184,14,58,189,0, _
  9,177,181,205,86,0, _
  116,118,0,4,216,11, _
  119,121,0,3,224,11, _
  15,174,170,183,103,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 57 ('9')
Static Shared As UByte font_omagui_sans_10_regular_char_57_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  2,155,187,195,48,0, _
  87,153,0,50,197,0, _
  127,99,0,0,232,3, _
  90,150,0,30,253,16, _
  5,168,184,161,217,0, _
  28,65,0,41,170,0, _
  14,184,186,178,29,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 58 (':')
Static Shared As UByte font_omagui_sans_10_regular_char_58_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  24,220,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  24,220,0, _
  0,0,0, _
  0,0,0 , _
0 }

' Font data for character 59 (';')
Static Shared As UByte font_omagui_sans_10_regular_char_59_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  20,224,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  20,222,0, _
  1,132,0, _
  0,0,0 , _
0 }

' Font data for character 60 ('<')
Static Shared As UByte font_omagui_sans_10_regular_char_60_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,59,161,69, _
  13,105,188,134,30,0, _
  128,180,13,0,0,0, _
  15,109,190,133,30,0, _
  0,0,0,62,163,69, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 61 ('=')
Static Shared As UByte font_omagui_sans_10_regular_char_61_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  94,184,184,184,184,63, _
  0,0,0,0,0,0, _
  94,184,184,184,184,63, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 62 ('>')
Static Shared As UByte font_omagui_sans_10_regular_char_62_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  96,149,44,0,0,0, _
  0,43,150,182,90,6, _
  0,0,0,27,205,92, _
  0,43,149,186,94,8, _
  96,151,47,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 63 ('?')
Static Shared As UByte font_omagui_sans_10_regular_char_63_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  8,166,203,207,117,0, _
  113,138,0,5,213,27, _
  3,4,0,7,212,18, _
  0,0,30,187,77,0, _
  0,0,180,60,0,0, _
  0,0,0,0,0,0, _
  0,0,220,24,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 64 ('@')
Static Shared As UByte font_omagui_sans_10_regular_char_64_data(...) = { _
  10, 12, _
  0,0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0,0, _
  0,0,23,143,158,155,160,142,17,0, _
  0,33,173,28,0,0,0,42,175,0, _
  0,169,19,84,181,160,135,95,127,46, _
  21,156,38,188,2,0,187,37,111,63, _
  48,127,82,135,0,36,211,0,171,15, _
  19,163,19,194,165,106,170,160,90,0, _
  0,149,78,0,0,0,8,54,0,0, _
  0,5,123,166,159,158,160,71,0,0, _
  0,0,0,0,0,0,0,0,0,0 , _
0 }

' Font data for character 65 ('A')
Static Shared As UByte font_omagui_sans_10_regular_char_65_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,96,244,26,0,0, _
  0,0,192,115,123,0,0, _
  0,45,170,10,206,1,0, _
  0,148,67,0,144,69,0, _
  10,222,188,188,191,170,0, _
  98,131,0,0,0,205,21, _
  200,41,0,0,0,121,117, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 66 ('B')
Static Shared As UByte font_omagui_sans_10_regular_char_66_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  44,240,192,191,200,57,0, _
  44,192,0,0,75,177,0, _
  44,192,0,6,123,131,0, _
  44,239,188,191,207,63,0, _
  44,192,0,0,11,221,12, _
  44,192,0,0,10,230,13, _
  44,240,192,192,200,96,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 67 ('C')
Static Shared As UByte font_omagui_sans_10_regular_char_67_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,41,181,197,205,159,15, _
  13,220,55,0,0,121,128, _
  86,156,0,0,0,0,0, _
  116,124,0,0,0,0,0, _
  90,162,0,0,0,0,0, _
  15,226,64,0,0,93,141, _
  0,45,187,204,200,155,15, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 68 ('D')
Static Shared As UByte font_omagui_sans_10_regular_char_68_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  44,240,192,193,190,70,0, _
  44,192,0,0,29,210,54, _
  44,192,0,0,0,89,153, _
  44,192,0,0,0,55,183, _
  44,192,0,0,0,92,153, _
  44,192,0,0,24,212,52, _
  44,240,192,194,199,78,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 69 ('E')
Static Shared As UByte font_omagui_sans_10_regular_char_69_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  44,241,196,196,196,196,9, _
  44,192,0,0,0,0,0, _
  44,192,0,0,0,0,0, _
  44,240,192,192,192,144,0, _
  44,192,0,0,0,0,0, _
  44,192,0,0,0,0,0, _
  44,241,196,196,196,196,45, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 70 ('F')
Static Shared As UByte font_omagui_sans_10_regular_char_70_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  44,241,196,196,196,137, _
  44,192,0,0,0,0, _
  44,192,0,0,0,0, _
  44,241,196,196,196,116, _
  44,192,0,0,0,0, _
  44,192,0,0,0,0, _
  44,192,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 71 ('G')
Static Shared As UByte font_omagui_sans_10_regular_char_71_data(...) = { _
  8, 12, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  0,44,182,197,203,173,23,0, _
  16,222,54,0,0,100,151,0, _
  91,155,0,0,0,0,0,0, _
  120,124,0,0,178,200,246,8, _
  93,161,0,0,0,0,212,8, _
  15,225,62,0,0,56,228,5, _
  0,42,182,200,205,178,47,0, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0 , _
0 }

' Font data for character 72 ('H')
Static Shared As UByte font_omagui_sans_10_regular_char_72_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  44,192,0,0,0,136,104, _
  44,192,0,0,0,136,104, _
  44,192,0,0,0,136,104, _
  44,242,200,200,200,229,104, _
  44,192,0,0,0,136,104, _
  44,192,0,0,0,136,104, _
  44,192,0,0,0,136,104, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 73 ('I')
Static Shared As UByte font_omagui_sans_10_regular_char_73_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  20,220,0, _
  20,220,0, _
  20,220,0, _
  20,220,0, _
  20,220,0, _
  20,220,0, _
  20,220,0, _
  0,0,0, _
  0,0,0 , _
0 }

' Font data for character 74 ('J')
Static Shared As UByte font_omagui_sans_10_regular_char_74_data(...) = { _
  5, 12, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,196,236,68, _
  0,0,0,172,68, _
  0,0,0,172,68, _
  0,0,0,172,68, _
  0,0,0,172,67, _
  169,61,0,206,38, _
  52,203,200,135,0, _
  0,0,0,0,0, _
  0,0,0,0,0 , _
0 }

' Font data for character 75 ('K')
Static Shared As UByte font_omagui_sans_10_regular_char_75_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  44,192,0,0,105,172,3, _
  44,192,0,93,178,5,0, _
  44,192,81,183,7,0,0, _
  44,232,210,157,0,0,0, _
  44,206,2,162,116,0,0, _
  44,192,0,8,199,78,0, _
  44,192,0,0,26,218,48, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 76 ('L')
Static Shared As UByte font_omagui_sans_10_regular_char_76_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  44,192,0,0,0,0, _
  44,192,0,0,0,0, _
  44,192,0,0,0,0, _
  44,192,0,0,0,0, _
  44,192,0,0,0,0, _
  44,192,0,0,0,0, _
  44,241,196,196,196,45, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 77 ('M')
Static Shared As UByte font_omagui_sans_10_regular_char_77_data(...) = { _
  8, 12, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  44,254,59,0,0,1,221,132, _
  44,204,155,0,0,62,210,132, _
  44,167,197,9,0,156,127,132, _
  44,168,116,91,9,190,84,132, _
  44,168,24,183,88,111,84,132, _
  44,168,0,176,188,22,84,132, _
  44,168,0,84,179,0,84,132, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0 , _
0 }

' Font data for character 78 ('N')
Static Shared As UByte font_omagui_sans_10_regular_char_78_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  44,254,56,0,0,112,104, _
  44,193,199,4,0,112,104, _
  44,167,123,115,0,112,104, _
  44,168,6,203,29,112,104, _
  44,168,0,65,175,111,104, _
  44,168,0,0,164,181,104, _
  44,168,0,0,23,239,104, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 79 ('O')
Static Shared As UByte font_omagui_sans_10_regular_char_79_data(...) = { _
  8, 12, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  0,44,182,197,205,163,22,0, _
  17,222,51,0,0,100,198,0, _
  97,148,0,0,0,0,209,42, _
  128,116,0,0,0,0,177,68, _
  101,152,0,0,0,0,210,38, _
  20,226,53,0,0,96,190,0, _
  0,49,187,199,201,161,18,0, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0 , _
0 }

' Font data for character 80 ('P')
Static Shared As UByte font_omagui_sans_10_regular_char_80_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  44,240,192,193,204,81,0, _
  44,192,0,0,20,230,5, _
  44,192,0,0,0,213,24, _
  44,192,0,2,66,210,0, _
  44,239,188,186,153,33,0, _
  44,192,0,0,0,0,0, _
  44,192,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 81 ('Q')
Static Shared As UByte font_omagui_sans_10_regular_char_81_data(...) = { _
  8, 12, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  0,44,182,197,206,163,22,0, _
  17,222,51,0,0,103,198,0, _
  97,149,0,0,0,0,210,42, _
  128,116,0,0,0,0,177,67, _
  103,151,0,0,0,0,209,37, _
  22,228,50,0,0,92,189,0, _
  0,53,190,199,201,160,16,0, _
  0,0,0,61,194,0,0,0, _
  0,0,0,0,151,197,73,0 , _
0 }

' Font data for character 82 ('R')
Static Shared As UByte font_omagui_sans_10_regular_char_82_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  44,240,192,192,197,171,11, _
  44,192,0,0,0,148,104, _
  44,192,0,0,19,186,77, _
  44,239,188,190,246,92,0, _
  44,192,0,0,176,81,0, _
  44,192,0,0,39,217,7, _
  44,192,0,0,0,150,121, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 83 ('S')
Static Shared As UByte font_omagui_sans_10_regular_char_83_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,118,187,179,198,84,0, _
  36,202,0,0,20,157,0, _
  19,227,85,13,0,0,0, _
  0,42,151,212,199,85,0, _
  0,0,0,0,40,229,28, _
  80,143,0,0,8,217,28, _
  6,146,198,187,195,97,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 84 ('T')
Static Shared As UByte font_omagui_sans_10_regular_char_84_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  153,196,220,226,196,171, _
  0,0,104,132,0,0, _
  0,0,104,132,0,0, _
  0,0,104,132,0,0, _
  0,0,104,132,0,0, _
  0,0,104,132,0,0, _
  0,0,104,132,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 85 ('U')
Static Shared As UByte font_omagui_sans_10_regular_char_85_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  60,180,0,0,0,124,116, _
  60,180,0,0,0,124,116, _
  60,180,0,0,0,124,116, _
  60,180,0,0,0,124,116, _
  54,188,0,0,0,134,108, _
  13,227,28,0,13,210,48, _
  0,67,198,195,204,97,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 86 ('V')
Static Shared As UByte font_omagui_sans_10_regular_char_86_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  193,56,0,0,0,142,108, _
  90,155,0,0,5,223,15, _
  7,222,11,0,82,158,0, _
  0,140,97,0,180,55,0, _
  0,38,195,25,204,0,0, _
  0,0,189,143,105,0,0, _
  0,0,87,242,14,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 87 ('W')
Static Shared As UByte font_omagui_sans_10_regular_char_87_data(...) = { _
  10, 12, _
  0,0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0,0, _
  207,38,0,0,220,78,0,0,180,66, _
  133,109,0,34,203,149,0,6,230,5, _
  59,180,0,106,101,200,0,64,174,0, _
  3,225,6,175,32,170,34,135,99,0, _
  0,166,68,205,0,103,103,204,26,0, _
  0,92,177,151,0,35,179,204,0,0, _
  0,20,251,82,0,0,220,133,0,0, _
  0,0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0,0 , _
0 }

' Font data for character 88 ('X')
Static Shared As UByte font_omagui_sans_10_regular_char_88_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  59,197,4,0,37,210,12, _
  0,127,127,2,193,56,0, _
  0,3,191,161,126,0,0, _
  0,0,90,252,28,0,0, _
  0,20,204,86,181,0,0, _
  0,177,73,0,149,105,0, _
  108,152,0,0,11,209,37, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 89 ('Y')
Static Shared As UByte font_omagui_sans_10_regular_char_89_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  118,143,0,0,8,211,40, _
  3,201,51,0,131,122,0, _
  0,47,200,43,201,4,0, _
  0,0,134,233,50,0,0, _
  0,0,36,204,0,0,0, _
  0,0,36,204,0,0,0, _
  0,0,36,204,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0 , _
0 }

' Font data for character 90 ('Z')
Static Shared As UByte font_omagui_sans_10_regular_char_90_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  64,196,196,196,231,134, _
  0,0,0,31,207,17, _
  0,0,6,196,55,0, _
  0,0,146,112,0,0, _
  0,84,173,0,0,0, _
  36,207,15,0,0,0, _
  167,223,196,196,196,156, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 91 ('[')
Static Shared As UByte font_omagui_sans_10_regular_char_91_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  72,214,112, _
  72,144,0, _
  72,144,0, _
  72,144,0, _
  72,144,0, _
  72,144,0, _
  72,144,0, _
  72,144,0, _
  72,214,112 , _
0 }

' Font data for character 92 ('\')
Static Shared As UByte font_omagui_sans_10_regular_char_92_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  195,1,0, _
  147,50,0, _
  75,124,0, _
  10,189,0, _
  0,182,18, _
  0,113,89, _
  0,40,163, _
  0,0,0, _
  0,0,0 , _
0 }

' Font data for character 93 (']')
Static Shared As UByte font_omagui_sans_10_regular_char_93_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  147,235,16, _
  0,200,16, _
  0,200,16, _
  0,200,16, _
  0,200,16, _
  0,200,16, _
  0,200,16, _
  0,200,16, _
  147,235,16 , _
0 }

' Font data for character 94 ('^')
Static Shared As UByte font_omagui_sans_10_regular_char_94_data(...) = { _
  5, 12, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,98,227,23,0, _
  0,186,72,131,0, _
  72,125,0,189,10, _
  179,22,0,96,106, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0 , _
0 }

' Font data for character 95 ('_')
Static Shared As UByte font_omagui_sans_10_regular_char_95_data(...) = { _
  7, 12, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0, _
  25,164,164,164,164,164,110 , _
0 }

' Font data for character 96 ('`')
Static Shared As UByte font_omagui_sans_10_regular_char_96_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  57,197,2, _
  0,84,94, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0 , _
0 }

' Font data for character 97 ('a')
Static Shared As UByte font_omagui_sans_10_regular_char_97_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  27,185,170,193,78,0, _
  0,0,0,42,190,0, _
  38,181,157,166,200,0, _
  135,107,0,84,202,0, _
  62,207,161,107,214,84, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 98 ('b')
Static Shared As UByte font_omagui_sans_10_regular_char_98_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  84,140,0,0,0,0, _
  84,140,0,0,0,0, _
  84,181,161,195,116,0, _
  84,190,0,5,228,8, _
  84,146,0,0,206,28, _
  84,184,0,5,226,7, _
  86,178,156,192,111,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 99 ('c')
Static Shared As UByte font_omagui_sans_10_regular_char_99_data(...) = { _
  5, 12, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  9,168,176,188,80, _
  103,131,0,0,0, _
  139,94,0,0,0, _
  103,137,0,0,0, _
  9,169,177,188,89, _
  0,0,0,0,0, _
  0,0,0,0,0 , _
0 }

' Font data for character 100 ('d')
Static Shared As UByte font_omagui_sans_10_regular_char_100_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,224,0, _
  0,0,0,0,224,0, _
  17,187,166,130,224,0, _
  111,128,0,42,228,0, _
  141,93,0,3,227,0, _
  114,128,0,47,228,0, _
  21,192,170,133,219,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 101 ('e')
Static Shared As UByte font_omagui_sans_10_regular_char_101_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  7,162,169,184,83,0, _
  102,130,0,9,218,2, _
  139,202,172,172,172,15, _
  101,136,0,0,0,0, _
  7,163,171,173,127,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 102 ('f')
Static Shared As UByte font_omagui_sans_10_regular_char_102_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  3,198,144, _
  25,199,0, _
  151,234,130, _
  28,196,0, _
  28,196,0, _
  28,196,0, _
  28,196,0, _
  0,0,0, _
  0,0,0 , _
0 }

' Font data for character 103 ('g')
Static Shared As UByte font_omagui_sans_10_regular_char_103_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  18,186,168,130,219,0, _
  112,124,0,64,228,0, _
  141,89,0,8,227,0, _
  117,121,0,63,228,0, _
  24,195,166,121,224,0, _
  25,70,0,29,201,0, _
  13,178,180,190,66,0 , _
0 }

' Font data for character 104 ('h')
Static Shared As UByte font_omagui_sans_10_regular_char_104_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  80,148,0,0,0,0, _
  80,147,0,0,0,0, _
  80,181,154,200,120,0, _
  80,190,0,9,220,0, _
  80,148,0,0,224,0, _
  80,148,0,0,224,0, _
  80,148,0,0,224,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 105 ('i')
Static Shared As UByte font_omagui_sans_10_regular_char_105_data(...) = { _
  2, 12, _
  0,0, _
  0,0, _
  0,0, _
  70,118, _
  0,0, _
  84,140, _
  84,140, _
  84,140, _
  84,140, _
  84,140, _
  0,0, _
  0,0 , _
0 }

' Font data for character 106 ('j')
Static Shared As UByte font_omagui_sans_10_regular_char_106_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,70,118, _
  0,0,0, _
  0,84,140, _
  0,84,140, _
  0,84,140, _
  0,84,140, _
  0,84,140, _
  0,87,138, _
  42,211,77 , _
0 }

' Font data for character 107 ('k')
Static Shared As UByte font_omagui_sans_10_regular_char_107_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  84,140,0,0,0,0, _
  84,140,0,0,0,0, _
  84,140,0,153,105,0, _
  84,140,144,107,0,0, _
  84,231,222,30,0,0, _
  84,147,54,196,8,0, _
  84,140,0,104,158,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 108 ('l')
Static Shared As UByte font_omagui_sans_10_regular_char_108_data(...) = { _
  2, 12, _
  0,0, _
  0,0, _
  0,0, _
  84,140, _
  84,140, _
  84,140, _
  84,140, _
  84,140, _
  84,140, _
  84,140, _
  0,0, _
  0,0 , _
0 }

' Font data for character 109 ('m')
Static Shared As UByte font_omagui_sans_10_regular_char_109_data(...) = { _
  8, 12, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0, _
  81,175,157,200,111,155,207,75, _
  80,182,0,78,195,0,66,163, _
  80,144,0,64,160,0,52,172, _
  80,144,0,64,160,0,52,172, _
  80,144,0,64,160,0,52,172, _
  0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0 , _
0 }

' Font data for character 110 ('n')
Static Shared As UByte font_omagui_sans_10_regular_char_110_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  81,174,156,200,120,0, _
  80,189,0,12,221,0, _
  80,148,0,0,224,0, _
  80,148,0,0,224,0, _
  80,148,0,0,224,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 111 ('o')
Static Shared As UByte font_omagui_sans_10_regular_char_111_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  9,168,171,186,92,0, _
  105,136,0,7,226,5, _
  139,94,0,0,206,27, _
  103,134,0,8,225,4, _
  8,165,170,186,86,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 112 ('p')
Static Shared As UByte font_omagui_sans_10_regular_char_112_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  87,175,161,195,116,0, _
  84,196,0,5,228,8, _
  84,147,0,0,206,28, _
  84,184,0,5,227,7, _
  84,184,156,192,111,0, _
  84,140,0,0,0,0, _
  84,140,0,0,0,0 , _
0 }

' Font data for character 113 ('q')
Static Shared As UByte font_omagui_sans_10_regular_char_113_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  17,187,166,139,223,0, _
  111,128,0,42,228,0, _
  141,93,0,3,227,0, _
  114,128,0,48,228,0, _
  21,192,171,142,222,0, _
  0,0,0,0,224,0, _
  0,0,0,0,224,0 , _
0 }

' Font data for character 114 ('r')
Static Shared As UByte font_omagui_sans_10_regular_char_114_data(...) = { _
  4, 12, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  83,168,194,35, _
  80,195,1,0, _
  80,150,0,0, _
  80,148,0,0, _
  80,148,0,0, _
  0,0,0,0, _
  0,0,0,0 , _
0 }

' Font data for character 115 ('s')
Static Shared As UByte font_omagui_sans_10_regular_char_115_data(...) = { _
  5, 12, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  45,188,175,193,39, _
  113,135,3,39,41, _
  9,127,188,172,33, _
  67,29,0,93,148, _
  63,190,171,185,58, _
  0,0,0,0,0, _
  0,0,0,0,0 , _
0 }

' Font data for character 116 ('t')
Static Shared As UByte font_omagui_sans_10_regular_char_116_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  19,162,0, _
  159,222,102, _
  60,164,0, _
  60,164,0, _
  59,167,0, _
  25,222,118, _
  0,0,0, _
  0,0,0 , _
0 }

' Font data for character 117 ('u')
Static Shared As UByte font_omagui_sans_10_regular_char_117_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  88,136,0,4,224,0, _
  88,136,0,4,224,0, _
  88,136,0,4,224,0, _
  79,152,0,47,224,0, _
  17,201,168,123,213,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

' Font data for character 118 ('v')
Static Shared As UByte font_omagui_sans_10_regular_char_118_data(...) = { _
  5, 12, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  199,37,0,40,196, _
  101,129,0,135,96, _
  13,209,3,212,10, _
  0,160,121,150,0, _
  0,61,248,50,0, _
  0,0,0,0,0, _
  0,0,0,0,0 , _
0 }

' Font data for character 119 ('w')
Static Shared As UByte font_omagui_sans_10_regular_char_119_data(...) = { _
  9, 12, _
  0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0, _
  0,212,7,9,242,58,0,190,26, _
  0,147,65,73,161,128,12,196,0, _
  0,71,133,145,43,181,77,125,0, _
  0,6,187,188,0,171,160,48,0, _
  0,0,170,157,0,106,221,0,0, _
  0,0,0,0,0,0,0,0,0, _
  0,0,0,0,0,0,0,0,0 , _
0 }

' Font data for character 120 ('x')
Static Shared As UByte font_omagui_sans_10_regular_char_120_data(...) = { _
  5, 12, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  110,129,0,139,105, _
  0,171,107,169,0, _
  0,48,255,44,0, _
  4,185,80,186,3, _
  134,104,0,113,132, _
  0,0,0,0,0, _
  0,0,0,0,0 , _
0 }

' Font data for character 121 ('y')
Static Shared As UByte font_omagui_sans_10_regular_char_121_data(...) = { _
  5, 12, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  194,43,0,36,198, _
  87,147,0,130,95, _
  4,214,11,205,9, _
  0,127,155,143,0, _
  0,24,249,40,0, _
  0,41,181,0,0, _
  117,194,37,0,0 , _
0 }

' Font data for character 122 ('z')
Static Shared As UByte font_omagui_sans_10_regular_char_122_data(...) = { _
  5, 12, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  0,0,0,0,0, _
  72,172,172,236,92, _
  0,0,80,183,3, _
  0,43,206,16,0, _
  17,205,42,0,0, _
  141,219,172,172,86, _
  0,0,0,0,0, _
  0,0,0,0,0 , _
0 }

' Font data for character 123 ('{')
Static Shared As UByte font_omagui_sans_10_regular_char_123_data(...) = { _
  4, 12, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  0,122,188,27, _
  0,198,19,0, _
  0,200,8,0, _
  21,212,2,0, _
  158,129,0,0, _
  0,206,3,0, _
  0,200,8,0, _
  0,196,16,0, _
  0,115,188,27 , _
0 }

' Font data for character 124 ('|')
Static Shared As UByte font_omagui_sans_10_regular_char_124_data(...) = { _
  3, 12, _
  0,0,0, _
  0,0,0, _
  0,0,0, _
  28,180,0, _
  28,180,0, _
  28,180,0, _
  28,180,0, _
  28,180,0, _
  28,180,0, _
  28,180,0, _
  28,180,0, _
  28,180,0 , _
0 }

' Font data for character 125 ('}')
Static Shared As UByte font_omagui_sans_10_regular_char_125_data(...) = { _
  4, 12, _
  0,0,0,0, _
  0,0,0,0, _
  0,0,0,0, _
  146,192,1,0, _
  0,192,22,0, _
  0,180,24,0, _
  0,149,76,0, _
  0,55,206,25, _
  0,167,38,0, _
  0,180,24,0, _
  0,188,20,0, _
  140,184,0,0 , _
0 }

' Font data for character 126 ('~')
Static Shared As UByte font_omagui_sans_10_regular_char_126_data(...) = { _
  6, 12, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  72,177,164,23,6,61, _
  68,0,28,169,182,48, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0, _
  0,0,0,0,0,0 , _
0 }

Sub font_omagui_sans_10_regular_init_pointers()
    /'
        The drawing backend indexes printable ASCII characters
        directly by character code. Each pointer references one
        generated width, height, alpha-data block.
    '/
    font_omagui_sans_10_regular_chars(32) = @font_omagui_sans_10_regular_char_32_data(0)
    font_omagui_sans_10_regular_chars(33) = @font_omagui_sans_10_regular_char_33_data(0)
    font_omagui_sans_10_regular_chars(34) = @font_omagui_sans_10_regular_char_34_data(0)
    font_omagui_sans_10_regular_chars(35) = @font_omagui_sans_10_regular_char_35_data(0)
    font_omagui_sans_10_regular_chars(36) = @font_omagui_sans_10_regular_char_36_data(0)
    font_omagui_sans_10_regular_chars(37) = @font_omagui_sans_10_regular_char_37_data(0)
    font_omagui_sans_10_regular_chars(38) = @font_omagui_sans_10_regular_char_38_data(0)
    font_omagui_sans_10_regular_chars(39) = @font_omagui_sans_10_regular_char_39_data(0)
    font_omagui_sans_10_regular_chars(40) = @font_omagui_sans_10_regular_char_40_data(0)
    font_omagui_sans_10_regular_chars(41) = @font_omagui_sans_10_regular_char_41_data(0)
    font_omagui_sans_10_regular_chars(42) = @font_omagui_sans_10_regular_char_42_data(0)
    font_omagui_sans_10_regular_chars(43) = @font_omagui_sans_10_regular_char_43_data(0)
    font_omagui_sans_10_regular_chars(44) = @font_omagui_sans_10_regular_char_44_data(0)
    font_omagui_sans_10_regular_chars(45) = @font_omagui_sans_10_regular_char_45_data(0)
    font_omagui_sans_10_regular_chars(46) = @font_omagui_sans_10_regular_char_46_data(0)
    font_omagui_sans_10_regular_chars(47) = @font_omagui_sans_10_regular_char_47_data(0)
    font_omagui_sans_10_regular_chars(48) = @font_omagui_sans_10_regular_char_48_data(0)
    font_omagui_sans_10_regular_chars(49) = @font_omagui_sans_10_regular_char_49_data(0)
    font_omagui_sans_10_regular_chars(50) = @font_omagui_sans_10_regular_char_50_data(0)
    font_omagui_sans_10_regular_chars(51) = @font_omagui_sans_10_regular_char_51_data(0)
    font_omagui_sans_10_regular_chars(52) = @font_omagui_sans_10_regular_char_52_data(0)
    font_omagui_sans_10_regular_chars(53) = @font_omagui_sans_10_regular_char_53_data(0)
    font_omagui_sans_10_regular_chars(54) = @font_omagui_sans_10_regular_char_54_data(0)
    font_omagui_sans_10_regular_chars(55) = @font_omagui_sans_10_regular_char_55_data(0)
    font_omagui_sans_10_regular_chars(56) = @font_omagui_sans_10_regular_char_56_data(0)
    font_omagui_sans_10_regular_chars(57) = @font_omagui_sans_10_regular_char_57_data(0)
    font_omagui_sans_10_regular_chars(58) = @font_omagui_sans_10_regular_char_58_data(0)
    font_omagui_sans_10_regular_chars(59) = @font_omagui_sans_10_regular_char_59_data(0)
    font_omagui_sans_10_regular_chars(60) = @font_omagui_sans_10_regular_char_60_data(0)
    font_omagui_sans_10_regular_chars(61) = @font_omagui_sans_10_regular_char_61_data(0)
    font_omagui_sans_10_regular_chars(62) = @font_omagui_sans_10_regular_char_62_data(0)
    font_omagui_sans_10_regular_chars(63) = @font_omagui_sans_10_regular_char_63_data(0)
    font_omagui_sans_10_regular_chars(64) = @font_omagui_sans_10_regular_char_64_data(0)
    font_omagui_sans_10_regular_chars(65) = @font_omagui_sans_10_regular_char_65_data(0)
    font_omagui_sans_10_regular_chars(66) = @font_omagui_sans_10_regular_char_66_data(0)
    font_omagui_sans_10_regular_chars(67) = @font_omagui_sans_10_regular_char_67_data(0)
    font_omagui_sans_10_regular_chars(68) = @font_omagui_sans_10_regular_char_68_data(0)
    font_omagui_sans_10_regular_chars(69) = @font_omagui_sans_10_regular_char_69_data(0)
    font_omagui_sans_10_regular_chars(70) = @font_omagui_sans_10_regular_char_70_data(0)
    font_omagui_sans_10_regular_chars(71) = @font_omagui_sans_10_regular_char_71_data(0)
    font_omagui_sans_10_regular_chars(72) = @font_omagui_sans_10_regular_char_72_data(0)
    font_omagui_sans_10_regular_chars(73) = @font_omagui_sans_10_regular_char_73_data(0)
    font_omagui_sans_10_regular_chars(74) = @font_omagui_sans_10_regular_char_74_data(0)
    font_omagui_sans_10_regular_chars(75) = @font_omagui_sans_10_regular_char_75_data(0)
    font_omagui_sans_10_regular_chars(76) = @font_omagui_sans_10_regular_char_76_data(0)
    font_omagui_sans_10_regular_chars(77) = @font_omagui_sans_10_regular_char_77_data(0)
    font_omagui_sans_10_regular_chars(78) = @font_omagui_sans_10_regular_char_78_data(0)
    font_omagui_sans_10_regular_chars(79) = @font_omagui_sans_10_regular_char_79_data(0)
    font_omagui_sans_10_regular_chars(80) = @font_omagui_sans_10_regular_char_80_data(0)
    font_omagui_sans_10_regular_chars(81) = @font_omagui_sans_10_regular_char_81_data(0)
    font_omagui_sans_10_regular_chars(82) = @font_omagui_sans_10_regular_char_82_data(0)
    font_omagui_sans_10_regular_chars(83) = @font_omagui_sans_10_regular_char_83_data(0)
    font_omagui_sans_10_regular_chars(84) = @font_omagui_sans_10_regular_char_84_data(0)
    font_omagui_sans_10_regular_chars(85) = @font_omagui_sans_10_regular_char_85_data(0)
    font_omagui_sans_10_regular_chars(86) = @font_omagui_sans_10_regular_char_86_data(0)
    font_omagui_sans_10_regular_chars(87) = @font_omagui_sans_10_regular_char_87_data(0)
    font_omagui_sans_10_regular_chars(88) = @font_omagui_sans_10_regular_char_88_data(0)
    font_omagui_sans_10_regular_chars(89) = @font_omagui_sans_10_regular_char_89_data(0)
    font_omagui_sans_10_regular_chars(90) = @font_omagui_sans_10_regular_char_90_data(0)
    font_omagui_sans_10_regular_chars(91) = @font_omagui_sans_10_regular_char_91_data(0)
    font_omagui_sans_10_regular_chars(92) = @font_omagui_sans_10_regular_char_92_data(0)
    font_omagui_sans_10_regular_chars(93) = @font_omagui_sans_10_regular_char_93_data(0)
    font_omagui_sans_10_regular_chars(94) = @font_omagui_sans_10_regular_char_94_data(0)
    font_omagui_sans_10_regular_chars(95) = @font_omagui_sans_10_regular_char_95_data(0)
    font_omagui_sans_10_regular_chars(96) = @font_omagui_sans_10_regular_char_96_data(0)
    font_omagui_sans_10_regular_chars(97) = @font_omagui_sans_10_regular_char_97_data(0)
    font_omagui_sans_10_regular_chars(98) = @font_omagui_sans_10_regular_char_98_data(0)
    font_omagui_sans_10_regular_chars(99) = @font_omagui_sans_10_regular_char_99_data(0)
    font_omagui_sans_10_regular_chars(100) = @font_omagui_sans_10_regular_char_100_data(0)
    font_omagui_sans_10_regular_chars(101) = @font_omagui_sans_10_regular_char_101_data(0)
    font_omagui_sans_10_regular_chars(102) = @font_omagui_sans_10_regular_char_102_data(0)
    font_omagui_sans_10_regular_chars(103) = @font_omagui_sans_10_regular_char_103_data(0)
    font_omagui_sans_10_regular_chars(104) = @font_omagui_sans_10_regular_char_104_data(0)
    font_omagui_sans_10_regular_chars(105) = @font_omagui_sans_10_regular_char_105_data(0)
    font_omagui_sans_10_regular_chars(106) = @font_omagui_sans_10_regular_char_106_data(0)
    font_omagui_sans_10_regular_chars(107) = @font_omagui_sans_10_regular_char_107_data(0)
    font_omagui_sans_10_regular_chars(108) = @font_omagui_sans_10_regular_char_108_data(0)
    font_omagui_sans_10_regular_chars(109) = @font_omagui_sans_10_regular_char_109_data(0)
    font_omagui_sans_10_regular_chars(110) = @font_omagui_sans_10_regular_char_110_data(0)
    font_omagui_sans_10_regular_chars(111) = @font_omagui_sans_10_regular_char_111_data(0)
    font_omagui_sans_10_regular_chars(112) = @font_omagui_sans_10_regular_char_112_data(0)
    font_omagui_sans_10_regular_chars(113) = @font_omagui_sans_10_regular_char_113_data(0)
    font_omagui_sans_10_regular_chars(114) = @font_omagui_sans_10_regular_char_114_data(0)
    font_omagui_sans_10_regular_chars(115) = @font_omagui_sans_10_regular_char_115_data(0)
    font_omagui_sans_10_regular_chars(116) = @font_omagui_sans_10_regular_char_116_data(0)
    font_omagui_sans_10_regular_chars(117) = @font_omagui_sans_10_regular_char_117_data(0)
    font_omagui_sans_10_regular_chars(118) = @font_omagui_sans_10_regular_char_118_data(0)
    font_omagui_sans_10_regular_chars(119) = @font_omagui_sans_10_regular_char_119_data(0)
    font_omagui_sans_10_regular_chars(120) = @font_omagui_sans_10_regular_char_120_data(0)
    font_omagui_sans_10_regular_chars(121) = @font_omagui_sans_10_regular_char_121_data(0)
    font_omagui_sans_10_regular_chars(122) = @font_omagui_sans_10_regular_char_122_data(0)
    font_omagui_sans_10_regular_chars(123) = @font_omagui_sans_10_regular_char_123_data(0)
    font_omagui_sans_10_regular_chars(124) = @font_omagui_sans_10_regular_char_124_data(0)
    font_omagui_sans_10_regular_chars(125) = @font_omagui_sans_10_regular_char_125_data(0)
    font_omagui_sans_10_regular_chars(126) = @font_omagui_sans_10_regular_char_126_data(0)
End Sub

#endif

/' end of font_omagui_sans_10_regular.bi '/
