/'
    Project: omaGUI
    File: byte_span.bi
    Purpose: Compare borrowed byte spans without allocating temporary strings.
    Responsibilities: Preserve exact equality, accept unaligned spans on DOS,
        and keep every read within the supplied byte count.
    Targets: FreeBASIC fb dialect; DOS uses packed, unaligned word loads.
    Module API: oma_BytesEqual compares caller-owned readable byte spans.
    This file intentionally does NOT contain:
        - text decoding
        - hashing
        - GUI state

    Callers keep both spans alive and unchanged until the call returns. A zero
    count needs no storage. Other calls require two readable spans of that size.
'/
#ifndef __OMAGUI_BYTE_SPAN_BI__
#define __OMAGUI_BYTE_SPAN_BI__

Declare Function oma_BytesEqual(ByVal firstBytes As Const Any Ptr, _
    ByVal secondBytes As Const Any Ptr, ByVal byteCount As Integer) As Integer

#ifdef OMAGUI_IMPLEMENTATION
#include once "crt/string.bi"

#If Defined(__FB_DOS__) Or Defined(OMAGUI_TEST_BYTE_SPAN_WORDS)
' FIELD=1 permits unaligned word loads in both the assembly and C generators.
' ULONG is exactly four bytes; this packed view borrows the caller's storage.
' The C generator disables strict aliasing for FreeBASIC pointer views.
Private Type OMA_ByteSpanWord Field = 1
    As ULong value
End Type
#assert SizeOf(OMA_ByteSpanWord) = 4
#EndIf

Function oma_BytesEqual(ByVal firstBytes As Const Any Ptr, _
    ByVal secondBytes As Const Any Ptr, ByVal byteCount As Integer) As Integer
    If byteCount < 0 Then Return 0
    If byteCount = 0 Then Return -1
    If firstBytes = 0 OrElse secondBytes = 0 Then Return 0
#If Defined(__FB_DOS__) Or (Defined(OMAGUI_TEST_BYTE_SPAN_X86) And Defined(__FB_X86__))
    ' DPMI supplies flat data and extra segments, and the x86 ABI enters with
    ' a clear direction flag. REP compares complete words without a BASIC
    ' loop per word. The final zero to three bytes stay inside the span.
    ' The compiler preserves the callee-saved registers used by this block.
    ' Numeric assembler labels remain local when GCC inlines the block.
    Dim As Integer equalResult = -1
    Asm
        mov esi, [firstBytes]
        mov edi, [secondBytes]
        mov ecx, [byteCount]
        shr ecx, 2
        jz 1f
        repe
        cmpsd
        jne 2f
    1:
        mov ecx, [byteCount]
        and ecx, 3
        jz 3f
        repe
        cmpsb
        je 3f
    2:
        mov dword ptr [equalResult], 0
    3:
    End Asm
    Return equalResult
#ElseIf Defined(OMAGUI_TEST_BYTE_SPAN_WORDS)
    ' DJGPP's memcmp visits one byte per loop. Equal words can be skipped
    ' together because this API observes equality only, including NUL bytes.
    ' Compare complete words first; the tail must never read a partial word.
    Dim As Const OMA_ByteSpanWord Ptr firstWords = Cast(Const OMA_ByteSpanWord Ptr, firstBytes)
    Dim As Const OMA_ByteSpanWord Ptr secondWords = Cast(Const OMA_ByteSpanWord Ptr, secondBytes)
    Dim As Integer wordCount = byteCount \ SizeOf(ULong)
    For wordIndex As Integer = 0 To wordCount - 1
        If firstWords[wordIndex].value <> secondWords[wordIndex].value Then Return 0
    Next wordIndex
    Dim As Const UByte Ptr firstTail = Cast(Const UByte Ptr, firstBytes)
    Dim As Const UByte Ptr secondTail = Cast(Const UByte Ptr, secondBytes)
    For byteIndex As Integer = wordCount * SizeOf(ULong) To byteCount - 1
        If firstTail[byteIndex] <> secondTail[byteIndex] Then Return 0
    Next byteIndex
    Return -1
#Else
    Return IIf(memcmp(firstBytes, secondBytes, byteCount) = 0, -1, 0)
#EndIf
End Function
#endif
#endif
' end of byte_span.bi
