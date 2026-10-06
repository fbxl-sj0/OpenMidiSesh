/'
    Project: omaGUI CHM Reader
    -------------------------

    File: chmarchive.bas

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Implements chmarchive.bi; declarations there define the interface.
    Ownership:

        The archive object owns its member index, reset table and cached
        decoded interval. Open failure resets that storage; returned member
        strings belong to the caller. File handles are closed before return.

    Purpose:

        Read individual files from a Compiled HTML Help archive on demand.

    Responsibilities:

        - validate ITSF, ITSP, PMGL, ControlData, and ResetTable records
        - retain a bounded member index and the LZX reset offsets
        - return stored members or only the reset intervals needed for one
          compressed member
        - keep no more than one decompressed reset interval cached

    This file intentionally does NOT contain:

        - HTML parsing or viewer state
        - whole-archive extraction
        - operating-system CHM APIs or external decompression libraries

    The CHM/LZX handling follows the LGPL-2.1-or-later libmspack format
    implementation. See LICENSES/LGPL-2.1.txt.
'/

' -------------------------------------------------------------------------
' Implementation
' -------------------------------------------------------------------------


#include once "src/archive/chmarchive.bi"

' -------------------------------------------------------------------------
' CHM archive data and bounded reader state
' -------------------------------------------------------------------------

Private Const CHMARCHIVE_ITSF_HEADER_BYTES As Integer = 96
Private Const CHMARCHIVE_ITSP_HEADER_BYTES As Integer = 84
Private Const CHMARCHIVE_PMGL_HEADER_BYTES As Integer = 20
Private Const CHMARCHIVE_RESET_HEADER_BYTES As Integer = 40
Private Const CHMARCHIVE_LZX_FRAME_BYTES As Integer = 32768
Private Const CHMARCHIVE_RESET_BYTES As Integer = 4
Private Const CHMARCHIVE_RESET_TABLE_NAME As String = _
    "::DataSpace/Storage/MSCompressed/Transform/" & _
    "{7FC28940-9D31-11D0-9B27-00A0C91E9C7C}/InstanceData/ResetTable"


Private Function chmarchive_ReadU16( _
    ByRef sourceText As Const String, ByVal byteOffset As Integer _
) As UInteger

    Return CUInt(Asc(Mid(sourceText, byteOffset + 1, 1))) Or _
        (CUInt(Asc(Mid(sourceText, byteOffset + 2, 1))) Shl 8)

End Function


Private Function chmarchive_ReadU32( _
    ByRef sourceText As Const String, ByVal byteOffset As Integer _
) As ULong

    Return CULng(Asc(Mid(sourceText, byteOffset + 1, 1))) Or _
        (CULng(Asc(Mid(sourceText, byteOffset + 2, 1))) Shl 8) Or _
        (CULng(Asc(Mid(sourceText, byteOffset + 3, 1))) Shl 16) Or _
        (CULng(Asc(Mid(sourceText, byteOffset + 4, 1))) Shl 24)

End Function


Private Function chmarchive_ReadU64( _
    ByRef sourceText As Const String, ByVal byteOffset As Integer, _
    ByRef value As LongInt _
) As Integer

    Dim As ULongInt lowPart
    Dim As ULongInt highPart
    Dim As ULongInt fullValue

    value = 0
    If byteOffset < 0 OrElse byteOffset + 8 > Len(sourceText) Then Return 0
    lowPart = chmarchive_ReadU32(sourceText, byteOffset)
    highPart = chmarchive_ReadU32(sourceText, byteOffset + 4)
    fullValue = lowPart Or (highPart Shl 32)
    If fullValue > CULngInt(CHMARCHIVE_MAX_FILE_BYTES) Then Return 0
    value = CLngInt(fullValue)
    Return -1

End Function


Private Function chmarchive_ReadAt( _
    ByVal fileNumber As Integer, ByVal fileLength As LongInt, _
    ByVal fileOffset As LongInt, ByVal byteCount As Integer, _
    ByRef resultText As String, ByRef errorText As String _
) As Integer

    resultText = ""
    If fileNumber <= 0 OrElse byteCount < 0 OrElse _
       fileOffset < 0 OrElse fileOffset > fileLength OrElse _
       byteCount > fileLength - fileOffset Then
        errorText = "CHM read is outside the archive file"
        Return 0
    End If
    If byteCount = 0 Then Return -1

    resultText = String(byteCount, Chr(0))
    If Get(fileNumber, fileOffset + 1, resultText) <> 0 Then
        resultText = ""
        errorText = "Could not read the CHM archive"
        Return 0
    End If
    Return -1

End Function


Private Function chmarchive_ReadEncInt( _
    ByRef sourceText As Const String, ByRef byteOffset As Integer, _
    ByVal endOffset As Integer, ByRef value As LongInt _
) As Integer

    Dim As Integer byteValue
    Dim As Integer byteCount
    Dim As ULongInt decodedValue

    value = 0
    decodedValue = 0
    byteCount = 0
    While byteCount < 9
        If byteOffset < 0 OrElse byteOffset >= endOffset OrElse _
           byteOffset >= Len(sourceText) Then Return 0
        byteValue = Asc(Mid(sourceText, byteOffset + 1, 1))
        byteOffset += 1
        byteCount += 1
        If decodedValue > _
           (CULngInt(CHMARCHIVE_MAX_FILE_BYTES) Shr 7) Then Return 0
        decodedValue = (decodedValue Shl 7) Or CULngInt(byteValue And &h7F)
        If decodedValue > CULngInt(CHMARCHIVE_MAX_FILE_BYTES) Then Return 0
        If (byteValue And &h80) = 0 Then
            value = CLngInt(decodedValue)
            Return -1
        End If
    Wend

    Return 0

End Function


Private Function chmarchive_NormalizeMemberName( _
    ByRef sourceName As Const String, ByRef normalizedName As String _
) As Integer

    Dim As String pathPart
    Dim As String currentPart
    Dim As Integer nextSeparator
    Dim As Integer characterValue
    Dim As Integer componentStart

    pathPart = LCase(Trim(sourceName))
    For charPosition As Integer = 1 To Len(pathPart)
        If Mid(pathPart, charPosition, 1) = Chr(92) Then _
            Mid(pathPart, charPosition, 1) = "/"
    Next charPosition
    While Len(pathPart) > 0 AndAlso Left(pathPart, 1) = "/"
        pathPart = Mid(pathPart, 2)
    Wend
    If pathPart = "" OrElse Len(pathPart) > CHMARCHIVE_MAX_ENTRY_NAME_BYTES Then _
        Return 0

    componentStart = 1
    While componentStart <= Len(pathPart)
        nextSeparator = InStr(componentStart, pathPart, "/")
        If nextSeparator = 0 Then nextSeparator = Len(pathPart) + 1
        currentPart = Mid(pathPart, componentStart, nextSeparator - componentStart)
        If currentPart = ".." Then Return 0
        componentStart = nextSeparator + 1
    Wend

    For charPosition As Integer = 1 To Len(pathPart)
        characterValue = Asc(Mid(pathPart, charPosition, 1))
        If characterValue = 0 OrElse characterValue < 32 Then Return 0
    Next charPosition

    normalizedName = pathPart
    Return -1

End Function


Private Function chmarchive_FindEntry( _
    ByVal archive As ChmArchive Ptr, ByRef memberName As Const String _
) As Integer

    Dim As String normalizedName

    If archive = 0 OrElse _
       chmarchive_NormalizeMemberName(memberName, normalizedName) = 0 Then _
        Return -1

    For entryIndex As Integer = 0 To archive->entryCount - 1
        If archive->entries(entryIndex).nameText = normalizedName Then _
            Return entryIndex
    Next entryIndex
    Return -1

End Function


Private Function chmarchive_FindRawSystemEntry( _
    ByVal archive As ChmArchive Ptr, ByRef memberName As Const String _
) As Integer

    If archive = 0 Then Return -1
    For entryIndex As Integer = 0 To archive->entryCount - 1
        If archive->entries(entryIndex).nameText = LCase(memberName) AndAlso _
           archive->entries(entryIndex).sectionIndex = 0 Then _
            Return entryIndex
    Next entryIndex
    Return -1

End Function


Private Function chmarchive_ReadStoredEntry( _
    ByVal archive As ChmArchive Ptr, ByVal fileNumber As Integer, _
    ByVal entryIndex As Integer, ByRef memberText As String, _
    ByRef errorText As String _
) As Integer

    Dim As ChmArchiveEntry Ptr entry

    memberText = ""
    If archive = 0 OrElse entryIndex < 0 OrElse _
       entryIndex >= archive->entryCount Then Return 0
    entry = @archive->entries(entryIndex)
    If entry->sectionIndex <> 0 OrElse _
       entry->length > CHMARCHIVE_MAX_MEMBER_BYTES OrElse _
       entry->offset > archive->fileLength - archive->section0Offset OrElse _
       entry->length > _
          archive->fileLength - archive->section0Offset - entry->offset Then
        errorText = "Stored CHM member exceeds the supported bounds"
        Return 0
    End If

    If entry->length = 0 Then Return -1
    Return chmarchive_ReadAt( _
        fileNumber, archive->fileLength, _
        archive->section0Offset + entry->offset, CInt(entry->length), _
        memberText, errorText _
    )

End Function


Private Function chmarchive_LoadResetTable( _
    ByVal archive As ChmArchive Ptr, ByVal fileNumber As Integer, _
    ByRef errorText As String _
) As Integer

    Dim As Integer contentEntryIndex
    Dim As Integer controlEntryIndex
    Dim As Integer resetEntryIndex
    Dim As Integer spanEntryIndex
    Dim As Integer fileVersion
    Dim As Integer entryPosition
    Dim As Integer resetIndex
    Dim As Integer byteOffset
    Dim As LongInt resetInterval
    Dim As LongInt windowSize
    Dim As LongInt tableOffset
    Dim As LongInt tableLength
    Dim As LongInt compressedLength
    Dim As LongInt declaredUncompressedLength
    Dim As LongInt tableEntryOffset
    Dim As String systemText
    Dim As String controlName = _
        "::DataSpace/Storage/MSCompressed/ControlData"
    Dim As String resetTableName = CHMARCHIVE_RESET_TABLE_NAME
    Dim As String spanInfoName = _
        "::DataSpace/Storage/MSCompressed/SpanInfo"
    Dim As String contentName = _
        "::DataSpace/Storage/MSCompressed/Content"

    contentEntryIndex = chmarchive_FindRawSystemEntry(archive, contentName)
    If contentEntryIndex < 0 Then
        errorText = "CHM has no LZX compressed content stream"
        Return 0
    End If
    If archive->entries(contentEntryIndex).length < 1 Then
        errorText = "CHM LZX compressed content stream is empty"
        Return 0
    End If
    archive->contentOffset = _
        archive->section0Offset + archive->entries(contentEntryIndex).offset
    archive->contentLength = archive->entries(contentEntryIndex).length

    controlEntryIndex = chmarchive_FindRawSystemEntry(archive, controlName)
    If controlEntryIndex < 0 OrElse _
       archive->entries(controlEntryIndex).length <> 28 Then
        errorText = "CHM LZX ControlData is missing or has the wrong size"
        Return 0
    End If
    If chmarchive_ReadStoredEntry( _
        archive, fileNumber, controlEntryIndex, systemText, errorText _
    ) = 0 Then Return 0
    If Len(systemText) <> 28 OrElse _
       Mid(systemText, 5, 4) <> "LZXC" Then
        errorText = "CHM LZX ControlData has an invalid signature"
        Return 0
    End If
    fileVersion = CInt(chmarchive_ReadU32(systemText, 8))
    resetInterval = chmarchive_ReadU32(systemText, 12)
    windowSize = chmarchive_ReadU32(systemText, 16)
    If fileVersion = 2 Then
        resetInterval *= CHMARCHIVE_LZX_FRAME_BYTES
        windowSize *= CHMARCHIVE_LZX_FRAME_BYTES
    Elseif fileVersion <> 1 Then
        errorText = "CHM LZX ControlData version is unsupported"
        Return 0
    End If
    If resetInterval < CHMARCHIVE_LZX_FRAME_BYTES OrElse _
       resetInterval Mod CHMARCHIVE_LZX_FRAME_BYTES <> 0 OrElse _
       resetInterval > CHM_LZX_MAX_RESET_BYTES Then
        errorText = "CHM LZX reset interval exceeds the supported bounds"
        Return 0
    End If
    Select Case windowSize
    Case 32768: archive->windowBits = 15
    Case 65536: archive->windowBits = 16
    Case 131072: archive->windowBits = 17
    Case 262144: archive->windowBits = 18
    Case 524288: archive->windowBits = 19
    Case 1048576: archive->windowBits = 20
    Case 2097152: archive->windowBits = 21
    Case Else
        errorText = "CHM LZX window size is outside the supported range"
        Return 0
    End Select
    archive->resetIntervalBytes = CInt(resetInterval)
    archive->resetFrameCount = CInt( _
        resetInterval \ CHMARCHIVE_LZX_FRAME_BYTES _
    )
    systemText = ""

    ' fblint: disable-next-line FBL310 REASON: resetTableName is a named CHM stream constant declared in this module.
    resetEntryIndex = chmarchive_FindRawSystemEntry(archive, resetTableName)
    If resetEntryIndex >= 0 Then
        tableLength = archive->entries(resetEntryIndex).length
        If tableLength < CHMARCHIVE_RESET_HEADER_BYTES OrElse _
           tableLength > 1000000 OrElse _
           tableLength > CHMARCHIVE_MAX_MEMBER_BYTES Then
            errorText = "CHM LZX ResetTable has an invalid size"
            Return 0
        End If
        If chmarchive_ReadStoredEntry( _
            archive, fileNumber, resetEntryIndex, systemText, errorText _
        ) = 0 Then Return 0
        If CInt(chmarchive_ReadU32(systemText, 32)) <> _
           CHMARCHIVE_LZX_FRAME_BYTES Then
            errorText = "CHM LZX ResetTable uses an unsupported frame size"
            Return 0
        End If
        archive->resetEntryCount = CInt(chmarchive_ReadU32(systemText, 4))
        archive->resetEntrySize = CInt(chmarchive_ReadU32(systemText, 8))
        tableOffset = chmarchive_ReadU32(systemText, 12)
        If chmarchive_ReadU64( _
            systemText, 16, declaredUncompressedLength _
        ) = 0 OrElse chmarchive_ReadU64( _
            systemText, 24, compressedLength _
        ) = 0 Then
            errorText = "CHM LZX ResetTable contains an oversized length"
            Return 0
        End If
        If archive->resetEntryCount < 1 OrElse _
           archive->resetEntryCount > CHMARCHIVE_MAX_RESET_ENTRIES OrElse _
           (archive->resetEntrySize <> 4 AndAlso _
            archive->resetEntrySize <> 8) OrElse tableOffset < 0 OrElse _
           tableOffset > Len(systemText) OrElse _
           archive->resetEntryCount > _
             (Len(systemText) - tableOffset) \ archive->resetEntrySize Then
            errorText = "CHM LZX ResetTable directory is outside its member"
            Return 0
        End If
        If declaredUncompressedLength < 1 OrElse _
           compressedLength < 1 OrElse _
           compressedLength > archive->contentLength Then
            errorText = "CHM LZX ResetTable lengths are inconsistent"
            Return 0
        End If
        If declaredUncompressedLength > CHMARCHIVE_MAX_FILE_BYTES Then
            errorText = "CHM uncompressed content exceeds the 1 GiB limit"
            Return 0
        End If

        archive->uncompressedLength = declaredUncompressedLength
        archive->compressedDataLength = compressedLength
        tableEntryOffset = tableOffset
        For resetIndex = 0 To archive->resetEntryCount - 1
            byteOffset = CInt(tableEntryOffset)
            If archive->resetEntrySize = 4 Then
                archive->resetOffsets(resetIndex) = _
                    chmarchive_ReadU32(systemText, byteOffset)
            Elseif chmarchive_ReadU64( _
                systemText, byteOffset, _
                archive->resetOffsets(resetIndex) _
            ) = 0 Then
                errorText = "CHM LZX ResetTable offset is too large"
                Return 0
            End If
            If archive->resetOffsets(resetIndex) < 0 OrElse _
               archive->resetOffsets(resetIndex) >= compressedLength OrElse _
               (resetIndex > 0 AndAlso _
                archive->resetOffsets(resetIndex) <= _
                archive->resetOffsets(resetIndex - 1)) Then
                errorText = "CHM LZX ResetTable offsets are not increasing"
                Return 0
            End If
            tableEntryOffset += archive->resetEntrySize
        Next resetIndex
        Return -1
    End If

    spanEntryIndex = chmarchive_FindRawSystemEntry(archive, spanInfoName)
    If spanEntryIndex < 0 OrElse _
       archive->entries(spanEntryIndex).length <> 8 Then
        errorText = "CHM has no usable LZX ResetTable or SpanInfo"
        Return 0
    End If
    If chmarchive_ReadStoredEntry( _
        archive, fileNumber, spanEntryIndex, systemText, errorText _
    ) = 0 Then Return 0
    If chmarchive_ReadU64(systemText, 0, declaredUncompressedLength) = 0 OrElse _
       declaredUncompressedLength < 1 Then
        errorText = "CHM SpanInfo contains an invalid length"
        Return 0
    End If
    errorText = "CHM random access requires an LZX ResetTable"
    Return 0

End Function


Private Function chmarchive_ReadCompressedMember( _
    ByVal archive As ChmArchive Ptr, ByVal fileNumber As Integer, _
    ByVal entry As ChmArchiveEntry Ptr, ByRef memberText As String, _
    ByRef errorText As String _
) As Integer

    Dim As LongInt memberEnd
    Dim As LongInt groupStart
    Dim As LongInt groupEnd
    Dim As LongInt compressedStart
    Dim As LongInt compressedEnd
    Dim As LongInt copyStart
    Dim As LongInt copyEnd
    Dim As LongInt copyLength
    Dim As LongInt tableIndex
    Dim As LongInt nextTableIndex
    Dim As Integer frameCount
    Dim As String compressedText
    Dim As String resetText
    Dim As String decodeError

    memberText = ""
    If entry = 0 OrElse entry->sectionIndex <> 1 OrElse _
       entry->length < 0 OrElse entry->length > CHMARCHIVE_MAX_MEMBER_BYTES OrElse _
       entry->offset < 0 OrElse _
       entry->offset > archive->uncompressedLength OrElse _
       entry->length > archive->uncompressedLength - entry->offset Then
        errorText = "Compressed CHM member exceeds the supported bounds"
        Return 0
    End If
    If entry->length = 0 Then Return -1
    If archive->resetEntryCount < 1 Then
        errorText = "CHM archive has no random-access LZX reset table"
        Return 0
    End If

    memberText = String(CInt(entry->length), Chr(0))
    memberEnd = entry->offset + entry->length
    groupStart = (entry->offset \ archive->resetIntervalBytes) * _
        archive->resetIntervalBytes
    While groupStart < memberEnd
        tableIndex = (groupStart \ archive->resetIntervalBytes) * _
            archive->resetFrameCount
        If tableIndex < 0 OrElse tableIndex >= archive->resetEntryCount Then
            errorText = "CHM LZX ResetTable does not cover this member"
            memberText = ""
            Return 0
        End If
        If archive->cachedResetFrame <> tableIndex Then
            compressedStart = archive->resetOffsets(tableIndex)
            nextTableIndex = tableIndex + archive->resetFrameCount
            If nextTableIndex < archive->resetEntryCount Then
                compressedEnd = archive->resetOffsets(nextTableIndex)
            Else
                compressedEnd = archive->compressedDataLength
            End If
            If compressedEnd <= compressedStart OrElse _
               compressedEnd - compressedStart > CHMARCHIVE_MAX_MEMBER_BYTES Then
                errorText = "CHM LZX compressed reset interval is invalid"
                memberText = ""
                Return 0
            End If
            If chmarchive_ReadAt( _
                fileNumber, archive->fileLength, _
                archive->contentOffset + compressedStart, _
                CInt(compressedEnd - compressedStart), compressedText, errorText _
            ) = 0 Then
                memberText = ""
                Return 0
            End If

            groupEnd = groupStart + archive->resetIntervalBytes
            If groupEnd > archive->uncompressedLength Then _
                groupEnd = archive->uncompressedLength
            frameCount = CInt((groupEnd - groupStart + _
                CHMARCHIVE_LZX_FRAME_BYTES - 1) \ _
                CHMARCHIVE_LZX_FRAME_BYTES)
            If chmlzx_DecompressReset( _
                compressedText, CInt(groupEnd - groupStart), _
                archive->windowBits, frameCount, resetText, decodeError _
            ) = 0 Then
                errorText = "Could not decode CHM LZX reset interval: " & _
                    decodeError
                memberText = ""
                Return 0
            End If
            compressedText = ""
            archive->cachedResetData = resetText
            archive->cachedResetFrame = CInt(tableIndex)
        End If

        groupEnd = groupStart + archive->resetIntervalBytes
        If groupEnd > archive->uncompressedLength Then _
            groupEnd = archive->uncompressedLength
        copyStart = entry->offset
        If copyStart < groupStart Then copyStart = groupStart
        copyEnd = memberEnd
        If copyEnd > groupEnd Then copyEnd = groupEnd
        copyLength = copyEnd - copyStart
        If copyLength < 0 OrElse _
           copyEnd - groupStart > Len(archive->cachedResetData) Then
            errorText = "CHM LZX reset interval did not produce member bytes"
            memberText = ""
            Return 0
        End If
        If copyLength > 0 Then
            Mid(memberText, CInt(copyStart - entry->offset) + 1, _
                CInt(copyLength)) = Mid( _
                    archive->cachedResetData, CInt(copyStart - groupStart) + 1, _
                    CInt(copyLength) _
                )
        End If
        groupStart = groupEnd
    Wend

    Return -1

End Function


' fblint: disable-next-line FBL111 REASON: Container records are checked in stream order and share one rollback path.
Function chmarchive_Open( _
    ByRef filePath As Const String, ByRef errorText As String _
) As ChmArchive Ptr

    Dim As ChmArchive Ptr archive
    Dim As Integer fileNumber
    Dim As Integer ioResult
    Dim As Integer openSucceeded = 0
    Dim As Integer chmVersion
    Dim As Integer entryCount
    Dim As Integer chunkIndex
    Dim As Integer chunkFirst
    Dim As Integer chunkLast
    Dim As Integer numberOfEntries
    Dim As Integer nameLength
    Dim As Integer sectionIndex
    Dim As Integer entryIndex
    Dim As Integer nameOffset
    Dim As Integer encintPosition
    Dim As Integer entryEnd
    Dim As UInteger quickRefBytes
    Dim As ULong chunkSize
    Dim As ULong numChunks
    Dim As ULong itspHeaderLength
    Dim As LongInt hs0Offset
    Dim As LongInt hs0Length
    Dim As LongInt hs1Offset
    Dim As LongInt hs1Length
    Dim As LongInt cs0Offset
    Dim As LongInt directoryOffset
    Dim As LongInt chunksOffset
    Dim As LongInt chunkOffset
    Dim As LongInt encodedValue
    Dim As LongInt memberOffset
    Dim As LongInt contentEnd
    Dim As LongInt rawSectionEnd
    Dim As String fileText
    Dim As String itspText
    Dim As String chunkText
    Dim As String entryName
    Dim As String normalizedName

    errorText = ""
    If Len(filePath) = 0 Then
        errorText = "CHM archive path is empty"
        Return 0
    End If
    fileNumber = FreeFile
    ioResult = Open(filePath For Binary Access Read As #fileNumber)
    If ioResult <> 0 Then
        errorText = "Could not open CHM archive: " & filePath
        Return 0
    End If

    archive = New ChmArchive
    If archive = 0 Then
        Close #fileNumber
        errorText = "Could not allocate CHM archive state"
        Return 0
    End If
    archive->filePath = filePath
    archive->fileLength = LOF(fileNumber)
    archive->cachedResetFrame = -1
    Do
        If archive->fileLength < CHMARCHIVE_ITSF_HEADER_BYTES OrElse _
           archive->fileLength > CHMARCHIVE_MAX_FILE_BYTES Then
            errorText = "CHM archive length is outside the supported bounds"
            Exit Do
        End If

        If chmarchive_ReadAt( _
            fileNumber, archive->fileLength, 0, _
            CHMARCHIVE_ITSF_HEADER_BYTES, fileText, errorText _
        ) = 0 Then Exit Do
        If Left(fileText, 4) <> "ITSF" Then
            errorText = "File does not have an ITSF CHM signature"
            Exit Do
        End If
        chmVersion = CInt(chmarchive_ReadU32(fileText, 4))
        If chmVersion <> 3 Then
            errorText = "Only version 3 CHM archives are supported"
            Exit Do
        End If
        If CInt(chmarchive_ReadU32(fileText, 8)) < _
           CHMARCHIVE_ITSF_HEADER_BYTES OrElse _
           chmarchive_ReadU64(fileText, 56, hs0Offset) = 0 OrElse _
           chmarchive_ReadU64(fileText, 64, hs0Length) = 0 OrElse _
           chmarchive_ReadU64(fileText, 72, hs1Offset) = 0 OrElse _
           chmarchive_ReadU64(fileText, 80, hs1Length) = 0 OrElse _
           chmarchive_ReadU64(fileText, 88, cs0Offset) = 0 Then
            errorText = "CHM ITSF header fields are invalid"
            Exit Do
        End If
        If hs0Offset > archive->fileLength OrElse _
           hs0Length > archive->fileLength - hs0Offset OrElse _
           hs1Offset > archive->fileLength OrElse _
           hs1Length > archive->fileLength - hs1Offset Then
            errorText = "CHM ITSF sections exceed the archive file"
            Exit Do
        End If
        directoryOffset = hs1Offset
        If hs1Length < CHMARCHIVE_ITSP_HEADER_BYTES OrElse _
           directoryOffset > archive->fileLength OrElse _
           hs1Length > archive->fileLength - directoryOffset OrElse _
           CHMARCHIVE_ITSP_HEADER_BYTES > archive->fileLength - directoryOffset Then
            errorText = "CHM ITSP directory header exceeds the archive file"
            Exit Do
        End If
        archive->section0Offset = cs0Offset
        If chmarchive_ReadAt( _
            fileNumber, archive->fileLength, directoryOffset, _
            CHMARCHIVE_ITSP_HEADER_BYTES, itspText, errorText _
        ) = 0 Then Exit Do
        If Left(itspText, 4) <> "ITSP" Then
            errorText = "CHM directory has no ITSP signature"
            Exit Do
        End If
        itspHeaderLength = chmarchive_ReadU32(itspText, 8)
        chunkSize = chmarchive_ReadU32(itspText, 16)
        chunkFirst = CInt(chmarchive_ReadU32(itspText, 32))
        chunkLast = CInt(chmarchive_ReadU32(itspText, 36))
        numChunks = chmarchive_ReadU32(itspText, 44)
        If itspHeaderLength < CHMARCHIVE_ITSP_HEADER_BYTES OrElse _
           itspHeaderLength > 4096 OrElse chunkSize < _
           CHMARCHIVE_PMGL_HEADER_BYTES + 2 OrElse _
           chunkSize > CHMARCHIVE_MAX_DIRECTORY_CHUNK_BYTES OrElse _
           numChunks < 1 OrElse numChunks > 100000 OrElse _
           chunkFirst < 0 OrElse chunkLast < chunkFirst OrElse _
           CULng(chunkLast) >= numChunks Then
            errorText = "CHM ITSP directory bounds are invalid"
            Exit Do
        End If
        If itspHeaderLength > hs1Length Then
            errorText = "CHM ITSP header exceeds header section one"
            Exit Do
        End If
        chunksOffset = directoryOffset + itspHeaderLength
        If chunksOffset > archive->fileLength OrElse _
           CULngInt(numChunks) * CULngInt(chunkSize) > _
           CULngInt(archive->fileLength - chunksOffset) Then
            errorText = "CHM directory chunks exceed the archive file"
            Exit Do
        End If
        archive->chunkSize = CInt(chunkSize)
        archive->numberOfChunks = CInt(numChunks)
        archive->firstPmglChunk = chunkFirst
        archive->lastPmglChunk = chunkLast

        For chunkIndex = chunkFirst To chunkLast
            chunkOffset = chunksOffset + CULngInt(chunkIndex) * chunkSize
            If chmarchive_ReadAt( _
                fileNumber, archive->fileLength, chunkOffset, _
                CInt(chunkSize), chunkText, errorText _
            ) = 0 Then Exit Do
            If Left(chunkText, 4) <> "PMGL" Then Continue For

            quickRefBytes = chmarchive_ReadU32(chunkText, 4)
            If quickRefBytes > chunkSize - CHMARCHIVE_PMGL_HEADER_BYTES Then
                errorText = "CHM PMGL quick-reference area is invalid"
                Exit Do
            End If
            numberOfEntries = CInt(chmarchive_ReadU16( _
                chunkText, CInt(chunkSize) - 2 _
            ))
            If numberOfEntries > chunkSize \ 4 Then
                errorText = "CHM PMGL entry count exceeds the chunk size"
                Exit Do
            End If

            encintPosition = CHMARCHIVE_PMGL_HEADER_BYTES
            entryEnd = CInt(chunkSize) - 2
        ' fblint: disable-next-line FBL311 REASON: The loop counter bounds repeated work; the cursor or stream state supplies each value.
            For localEntry As Integer = 0 To numberOfEntries - 1
                If chmarchive_ReadEncInt( _
                    chunkText, encintPosition, entryEnd, encodedValue _
                ) = 0 Then
                    errorText = "CHM PMGL filename length is invalid"
                    Exit Do
                End If
                nameLength = CInt(encodedValue)
                If nameLength < 1 OrElse _
                   nameLength > CHMARCHIVE_MAX_ENTRY_NAME_BYTES OrElse _
                   encintPosition > entryEnd - nameLength Then
                    errorText = "CHM PMGL filename exceeds its entry bounds"
                    Exit Do
                End If
                nameOffset = encintPosition
                entryName = Mid(chunkText, nameOffset + 1, nameLength)
                encintPosition += nameLength
                If chmarchive_ReadEncInt( _
                    chunkText, encintPosition, entryEnd, encodedValue _
                ) = 0 Then
                    errorText = "CHM PMGL member metadata is invalid"
                    Exit Do
                End If
                sectionIndex = CInt(encodedValue)
                If chmarchive_ReadEncInt( _
                    chunkText, encintPosition, entryEnd, encodedValue _
                ) = 0 Then
                    errorText = "CHM PMGL member metadata is invalid"
                    Exit Do
                End If
                ' Section-one offsets address the uncompressed LZX stream, which
                ' can be larger than the physical CHM. Validate stored entries
                ' against the file and compressed entries against logical length
                ' after the section metadata has been loaded below.
                memberOffset = encodedValue
                If chmarchive_ReadEncInt( _
                    chunkText, encintPosition, entryEnd, encodedValue _
                ) = 0 Then
                    errorText = "CHM PMGL member metadata is invalid"
                    Exit Do
                End If
                If sectionIndex < 0 OrElse sectionIndex > 1 OrElse _
                   encodedValue > CHMARCHIVE_MAX_FILE_BYTES Then
                    errorText = "CHM PMGL member metadata is invalid"
                    Exit Do
                End If
                If memberOffset = 0 AndAlso encodedValue = 0 AndAlso _
                   Right(entryName, 1) = "/" Then Continue For
                If archive->entryCount >= CHMARCHIVE_MAX_ENTRIES Then
                    errorText = "CHM directory exceeds the 16,384 member limit"
                    Exit Do
                End If
                If chmarchive_NormalizeMemberName( _
                    entryName, normalizedName _
                ) = 0 Then Continue For
                entryIndex = archive->entryCount
                archive->entries(entryIndex).nameText = normalizedName
                archive->entries(entryIndex).sectionIndex = sectionIndex
                archive->entries(entryIndex).offset = memberOffset
                archive->entries(entryIndex).length = encodedValue
                archive->entryCount += 1
                Continue For

            Next localEntry
        Next chunkIndex

        If archive->entryCount < 1 Then
            errorText = "CHM directory contains no readable members"
            Exit Do
        End If
        rawSectionEnd = archive->fileLength - archive->section0Offset
        For entryIndex = 0 To archive->entryCount - 1
            If archive->entries(entryIndex).sectionIndex = 0 Then
                If archive->entries(entryIndex).offset > rawSectionEnd OrElse _
                   archive->entries(entryIndex).length > _
                     rawSectionEnd - archive->entries(entryIndex).offset Then
                    errorText = "CHM stored member exceeds section zero"
                    Exit Do
                End If
            End If
        Next entryIndex

        If chmarchive_LoadResetTable(archive, fileNumber, errorText) = 0 Then Exit Do
        For entryIndex = 0 To archive->entryCount - 1
            If archive->entries(entryIndex).sectionIndex = 1 Then
                If archive->entries(entryIndex).offset > archive->uncompressedLength OrElse _
                   archive->entries(entryIndex).length > archive->uncompressedLength - archive->entries(entryIndex).offset Then
                    errorText = "CHM compressed member exceeds the logical section"
                    Exit Do
                End If
            End If
        Next entryIndex
        contentEnd = archive->contentOffset + archive->compressedDataLength
        If archive->contentOffset < archive->section0Offset OrElse _
           contentEnd > archive->fileLength Then
            errorText = "CHM compressed content exceeds the archive file"
            Exit Do
        End If

        openSucceeded = -1
        Exit Do
    Loop

    Close #fileNumber
    If openSucceeded = 0 Then
        Delete archive
        Return 0
    End If
    Return archive

End Function


Sub chmarchive_Close(ByRef archive As ChmArchive Ptr)

    If archive = 0 Then Exit Sub
    Delete archive
    archive = 0

End Sub


Function chmarchive_ReadFile( _
    ByVal archive As ChmArchive Ptr, ByRef memberName As Const String, _
    ByRef memberText As String, ByRef errorText As String, _
    ByVal maximumMemberBytes As LongInt _
) As Integer

    Dim As Integer fileNumber
    Dim As Integer entryIndex
    Dim As Integer ioResult

    memberText = ""
    errorText = ""
    If archive = 0 Then
        errorText = "CHM archive is not open"
        Return 0
    End If
    If maximumMemberBytes < 0 OrElse _
       maximumMemberBytes > CHMARCHIVE_MAX_MEMBER_BYTES Then
        errorText = "CHM member read limit is outside the supported bounds"
        Return 0
    End If
    entryIndex = chmarchive_FindEntry(archive, memberName)
    If entryIndex < 0 Then
        errorText = "CHM member was not found: " & memberName
        Return 0
    End If
    If archive->entries(entryIndex).length < 0 OrElse _
       archive->entries(entryIndex).length > maximumMemberBytes Then
        errorText = "CHM member exceeds the requested read limit"
        Return 0
    End If
    fileNumber = FreeFile
    ioResult = Open(archive->filePath For Binary Access Read As #fileNumber)
    If ioResult <> 0 Then
        errorText = "Could not reopen CHM archive: " & archive->filePath
        Return 0
    End If

    If archive->entries(entryIndex).sectionIndex = 0 Then
        ioResult = chmarchive_ReadStoredEntry( _
            archive, fileNumber, entryIndex, memberText, errorText _
        )
    Else
        ioResult = chmarchive_ReadCompressedMember( _
            archive, fileNumber, @archive->entries(entryIndex), _
            memberText, errorText _
        )
    End If
    Close #fileNumber
    If ioResult = 0 Then memberText = ""
    Return ioResult

End Function


Function chmarchive_Contains( _
    ByVal archive As ChmArchive Ptr, ByRef memberName As Const String _
) As Integer

    If chmarchive_FindEntry(archive, memberName) >= 0 Then Return -1
    Return 0

End Function


Function chmarchive_MemberCount(ByVal archive As ChmArchive Ptr) As Integer

    If archive = 0 Then Return 0
    Return archive->entryCount

End Function


Function chmarchive_GetMemberInfo( _
    ByVal archive As ChmArchive Ptr, ByVal memberIndex As Integer, _
    ByRef memberName As String, ByRef sectionIndex As Integer _
) As Integer

    memberName = ""
    sectionIndex = -1
    If archive = 0 OrElse memberIndex < 0 OrElse _
       memberIndex >= archive->entryCount Then Return 0
    memberName = archive->entries(memberIndex).nameText
    sectionIndex = archive->entries(memberIndex).sectionIndex
    Return -1

End Function

/' end of chmarchive.bas '/
