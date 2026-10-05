/'
    Project: fblint regression
    File: fixed_width_safe.bas
    Purpose: distinguish fixed-width FreeBASIC types from native C ABI records.
    Responsibilities: verify target-stable widths and identifier token boundaries.
    This file contains no external ABI declarations or raw record serialization.
'/
#assert SizeOf(Long) = 4
#assert SizeOf(ULong) = 4
#assert SizeOf(LongInt) = 8
#assert SizeOf(ULongInt) = 8
Dim As Long value32 = 1
Dim As ULong unsigned32 = 1
Dim As LongInt value64 = 1
Dim As ULongInt unsigned64 = 1
Dim As Integer selectedEnvironmentMode = 0
Print value32; unsigned32; value64; unsigned64; selectedEnvironmentMode
/' end of fixed_width_safe.bas '/
