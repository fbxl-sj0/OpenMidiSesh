/'
    Project: OpenSesh
    ---------------------------

    File: src/editor/score_render.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: Private implementation include for opensesh.bas; state.bi owns shared storage.

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Purpose:

        Draw score notation and mixer presentation.

    Responsibilities:

        - render staff, note, ruler and channel state
        - reuse bounded display caches without changing the document

    This file intentionally does NOT contain:

        - an independently linked public module
        - application startup or resource shutdown

    Included once by opensesh.bas in the editor translation unit.
    Shared editor storage and forward declarations live in state.bi.
'/

#ifndef __OSE_EDITOR_SCORE_RENDER_BI__
#define __OSE_EDITOR_SCORE_RENDER_BI__


' -------------------------------------------------------------------------
' Score and mixer rendering
' -------------------------------------------------------------------------

Private Sub session_DrawNoteLedgerLines( _
    ByVal noteX As Integer, _
    ByVal noteY As Integer, _
    ByVal staffY As Integer, _
    ByVal clr As ULong _
)
    Dim As Integer lineSpacing = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight)
    Dim As Integer staffHeight = lineSpacing * 4
    Dim As Integer ledgerHalfWidth = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 8)
    Dim As Integer ledgerTolerance = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 3)
    If noteY < staffY Then
        For ledgerIndex As Integer = 1 To 8
            Dim As Integer ledgerY = staffY - ledgerIndex * lineSpacing
            If ledgerY < noteY - ledgerTolerance Then
                Exit For
            End If
            backend_Line noteX - ledgerHalfWidth, ledgerY, _
                noteX + ledgerHalfWidth, ledgerY, clr
        Next
    ElseIf noteY > staffY + staffHeight Then
        For ledgerIndex As Integer = 1 To 8
            Dim As Integer ledgerY = staffY + staffHeight + _
                ledgerIndex * lineSpacing
            If ledgerY > noteY + ledgerTolerance Then
                Exit For
            End If
            backend_Line noteX - ledgerHalfWidth, ledgerY, _
                noteX + ledgerHalfWidth, ledgerY, clr
        Next
    End If
End Sub


Private Function session_NoteAccidental( _
    ByVal keyNumber As Integer, _
    ByVal sharpsFlats As Integer _
) As String
    If keyNumber < 0 Then
        keyNumber = 0
    End If
    If keyNumber > 127 Then
        keyNumber = 127
    End If
    If sharpsFlats < -7 Then
        sharpsFlats = -7
    End If
    If sharpsFlats > 7 Then
        sharpsFlats = 7
    End If

    Dim As Integer pitchClass = keyNumber Mod 12
    Dim As Integer diatonicIndex = session_MidiDiatonicIndexForKey( _
        keyNumber, sharpsFlats)
    Dim As Integer naturalPitchClass(0 To 6) = {0, 2, 4, 5, 7, 9, 11}
    Dim As Integer letterIndex = diatonicIndex Mod 7
    Dim As Integer naturalClass = naturalPitchClass(letterIndex)
    Dim As Integer defaultAlteration = 0

    If sharpsFlats > 0 Then
        Dim As Integer sharpOrder(0 To 6) = {6, 1, 8, 3, 10, 5, 0}
        For orderIndex As Integer = 0 To sharpsFlats - 1
            Dim As Integer alteredClass = sharpOrder(orderIndex)
            If alteredClass = (naturalClass + 1) Mod 12 Then
                defaultAlteration = 1
                Exit For
            End If
        Next
    ElseIf sharpsFlats < 0 Then
        Dim As Integer flatOrder(0 To 6) = {10, 3, 8, 1, 6, 11, 4}
        For orderIndex As Integer = 0 To (-sharpsFlats) - 1
            Dim As Integer alteredClass = flatOrder(orderIndex)
            If alteredClass = (naturalClass + 11) Mod 12 Then
                defaultAlteration = -1
                Exit For
            End If
        Next
    End If

    Dim As Integer actualAlteration = 0
    If pitchClass = (naturalClass + 1) Mod 12 Then
        actualAlteration = 1
    ElseIf pitchClass = (naturalClass + 11) Mod 12 Then
        actualAlteration = -1
    ElseIf pitchClass <> naturalClass Then
        ' MIDI does not preserve enharmonic spelling. Use the key's preferred
        ' spelling and avoid inventing a symbol for an unrepresentable case.
        Return ""
    End If

    If actualAlteration = defaultAlteration Then
        Return ""
    End If
    If actualAlteration = 0 Then
        Return "n"
    End If
    If actualAlteration > 0 Then
        Return "#"
    End If
    Return "b"
End Function


Private Sub session_DrawAccidental( _
    ByVal accidentalText As String, _
    ByVal accidentalX As Integer, ByVal accidentalY As Integer, _
    ByVal accidentalColor As ULong _
)
    Dim As Integer symbolCode = -1
    Select Case accidentalText
        Case "#"
            symbolCode = MUSIC_SYMBOL_SHARP
        Case "b"
            symbolCode = MUSIC_SYMBOL_FLAT
        Case "n"
            symbolCode = MUSIC_SYMBOL_NATURAL
    End Select

    If symbolCode >= 0 AndAlso musicSymbols_HasGlyph(symbolCode) <> 0 Then
        musicSymbols_DrawCentered symbolCode, accidentalX, accidentalY, _
            accidentalColor
    Else
        backend_Print accidentalX - 4, accidentalY - 6, accidentalColor, _
            accidentalText
    End If
End Sub


Private Sub session_DrawScaledNotationPolygon( _
    ByVal originX As Integer, ByVal originY As Integer, _
    ByVal targetWidth As Integer, ByVal targetHeight As Integer, _
    ByVal designWidth As Integer, ByVal designHeight As Integer, _
    ByVal pointCount As Integer, designX() As Integer, _
    designY() As Integer, ByVal polygonColor As ULong _
)
    /'
        Notation outlines are authored on a large integer grid and reduced to
        their final score size only here. The same guarded path serves clefs,
        noteheads, stems, and flags so those symbols share omaGUI's filled
        polygon rendering behavior.

        omaGUI limits a polygon to GRAPHICSHAPE_MAX_POINTS. Invalid dimensions
        and paths are rejected before scaling to prevent divide-by-zero and
        out-of-range array access in malformed symbol data.
    '/
    If targetWidth < 2 Or targetHeight < 2 Then
        Exit Sub
    End If
    If designWidth < 1 Or designHeight < 1 Then
        Exit Sub
    End If
    If pointCount < 3 Or pointCount > GRAPHICSHAPE_MAX_POINTS Then
        Exit Sub
    End If

    Dim As GraphicShapeRenderOptions options
    Dim As Integer pointX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer pointY(1 To GRAPHICSHAPE_MAX_POINTS)

    For pointIndex As Integer = 1 To pointCount
        Dim As Integer boundedX = designX(pointIndex)
        Dim As Integer boundedY = designY(pointIndex)
        If boundedX < 0 Then
            boundedX = 0
        End If
        If boundedX > designWidth Then
            boundedX = designWidth
        End If
        If boundedY < 0 Then
            boundedY = 0
        End If
        If boundedY > designHeight Then
            boundedY = designHeight
        End If

        pointX(pointIndex) = (boundedX * (targetWidth - 1) + _
            designWidth \ 2) \ designWidth
        pointY(pointIndex) = (boundedY * (targetHeight - 1) + _
            designHeight \ 2) \ designHeight
    Next

    graphicshape_DefaultOptions options, GUI_SHAPE_POLYGON
    options.stroke_clr = polygonColor
    options.fill_clr = polygonColor
    options.filled = -1
    options.line_width = 0
    options.object_alpha = 255
    options.stroke_alpha = 255
    options.fill_alpha = 255
    options.clip_to_bounds = -1

    graphicshape_RenderWithOptions originX, originY, targetWidth, targetHeight, _
        options, "", pointCount, pointX(), pointY()
End Sub


Private Sub session_DrawVectorNoteHead( _
    ByVal centerX As Integer, ByVal centerY As Integer, _
    ByVal headWidth As Integer, ByVal headHeight As Integer, _
    ByVal headFilled As Integer, ByVal noteColor As ULong _
)
    /'
        The slanted 100 by 70 design follows the broad, calligraphic heads in
        the reference score. Hollow heads are two overlapping closed ribbons,
        not an outer shape painted over with a guessed row color. Staff and
        ledger lines therefore remain visible through the center as they did
        through the original monochrome glyph mask.
    '/
    Const DESIGN_WIDTH As Integer = 100
    Const DESIGN_HEIGHT As Integer = 70

    If headWidth < 2 Or headHeight < 2 Then
        Exit Sub
    End If
    Dim As Integer originX = centerX - headWidth \ 2
    Dim As Integer originY = centerY - headHeight \ 2
    Dim As Integer designX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer designY(1 To GRAPHICSHAPE_MAX_POINTS)

    If headFilled <> 0 Then
        designX(1) = 0
        designY(1) = 45
        designX(2) = 6
        designY(2) = 28
        designX(3) = 22
        designY(3) = 14
        designX(4) = 45
        designY(4) = 4
        designX(5) = 70
        designY(5) = 0
        designX(6) = 92
        designY(6) = 12
        designX(7) = 100
        designY(7) = 29
        designX(8) = 93
        designY(8) = 50
        designX(9) = 75
        designY(9) = 63
        designX(10) = 50
        designY(10) = 70
        designX(11) = 25
        designY(11) = 68
        designX(12) = 5
        designY(12) = 58
        session_DrawScaledNotationPolygon originX, originY, headWidth, _
            headHeight, DESIGN_WIDTH, DESIGN_HEIGHT, 12, designX(), _
            designY(), noteColor
        Exit Sub
    End If

    ' Upper ribbon of a whole or half-note head.
    designX(1) = 0
    designY(1) = 45
    designX(2) = 6
    designY(2) = 28
    designX(3) = 22
    designY(3) = 14
    designX(4) = 45
    designY(4) = 4
    designX(5) = 70
    designY(5) = 0
    designX(6) = 92
    designY(6) = 12
    designX(7) = 100
    designY(7) = 29
    designX(8) = 84
    designY(8) = 27
    designX(9) = 67
    designY(9) = 19
    designX(10) = 48
    designY(10) = 17
    designX(11) = 28
    designY(11) = 23
    designX(12) = 15
    designY(12) = 39
    session_DrawScaledNotationPolygon originX, originY, headWidth, headHeight, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 12, designX(), designY(), noteColor

    ' Lower ribbon closes the ends while preserving the hollow center.
    designX(1) = 0
    designY(1) = 42
    designX(2) = 5
    designY(2) = 58
    designX(3) = 25
    designY(3) = 68
    designX(4) = 50
    designY(4) = 70
    designX(5) = 75
    designY(5) = 63
    designX(6) = 93
    designY(6) = 50
    designX(7) = 100
    designY(7) = 30
    designX(8) = 84
    designY(8) = 32
    designX(9) = 74
    designY(9) = 46
    designX(10) = 56
    designY(10) = 53
    designX(11) = 35
    designY(11) = 52
    designX(12) = 16
    designY(12) = 46
    session_DrawScaledNotationPolygon originX, originY, headWidth, headHeight, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 12, designX(), designY(), noteColor
End Sub


Private Sub session_DrawVectorNoteStem( _
    ByVal stemX As Integer, ByVal noteY As Integer, _
    ByVal stemEndY As Integer, ByVal stemWidth As Integer, _
    ByVal noteColor As ULong _
)
    Dim As Integer stemTop = noteY
    If stemEndY < stemTop Then
        stemTop = stemEndY
    End If
    Dim As Integer stemHeight = Abs(stemEndY - noteY) + 1
    If stemHeight < 2 Then
        Exit Sub
    End If

    If stemWidth < 1 Then
        stemWidth = 1
    End If
    ' A stem is one axis-aligned rectangle. Sending one rectangle to
    ' gfxlib preserves the vector silhouette while avoiding one draw command
    ' per scanline for every visible note.
    backend_Rect stemX - stemWidth \ 2, stemTop, stemWidth, _
        stemHeight - 1, noteColor, 1
End Sub


Private Sub session_DrawVectorNoteFlag( _
    ByVal stemX As Integer, ByVal flagAnchorY As Integer, _
    ByVal stemUp As Integer, ByVal flagWidth As Integer, _
    ByVal flagHeight As Integer, ByVal noteColor As ULong _
)
    /'
        One tapered ribbon represents one flag. Mirroring both axes gives the
        standard down-stem form without maintaining a second independent path.
        Repetition at six-pixel intervals produces 8th through 64th notes.
    '/
    If flagWidth < 2 OrElse flagHeight < 2 Then
        Exit Sub
    End If

    Dim As Integer designX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer designY(1 To GRAPHICSHAPE_MAX_POINTS)
    designX(1) = 0
    designY(1) = 0
    designX(2) = 16
    designY(2) = 10
    designX(3) = 38
    designY(3) = 25
    designX(4) = 62
    designY(4) = 43
    designX(5) = 84
    designY(5) = 66
    designX(6) = 96
    designY(6) = 88
    designX(7) = 100
    designY(7) = 100
    designX(8) = 83
    designY(8) = 85
    designX(9) = 65
    designY(9) = 72
    designX(10) = 44
    designY(10) = 59
    designX(11) = 22
    designY(11) = 52
    designX(12) = 0
    designY(12) = 42

    Dim As Integer originX = stemX
    Dim As Integer originY = flagAnchorY
    If stemUp = 0 Then
        For pointIndex As Integer = 1 To 12
            designY(pointIndex) = 100 - designY(pointIndex)
        Next
        originY = flagAnchorY - flagHeight + 1
    End If

    session_DrawScaledNotationPolygon originX, originY, flagWidth, _
        flagHeight, 100, 100, 12, designX(), designY(), noteColor
End Sub


Private Sub session_ClassifyNoteDuration( _
    ByRef editableNote As MidiEditableNote, _
    ByVal quarterTicks As ULongInt, _
    ByRef durationCode As Integer, _
    ByRef headFilled As Integer, _
    ByRef stemRequired As Integer, _
    ByRef flagCount As Integer, _
    ByRef dotted As Integer _
)
    durationCode = 2
    headFilled = 1
    stemRequired = 1
    flagCount = 4
    dotted = 0
    If quarterTicks = 0 Then
        quarterTicks = 1
    End If

    Dim As ULongInt eighthTicks = quarterTicks \ 2
    Dim As ULongInt sixteenthTicks = quarterTicks \ 4
    Dim As ULongInt thirtySecondTicks = quarterTicks \ 8
    Dim As ULongInt sixtyFourthTicks = quarterTicks \ 16
    If eighthTicks = 0 Then
        eighthTicks = 1
    End If
    If sixteenthTicks = 0 Then
        sixteenthTicks = 1
    End If
    If thirtySecondTicks = 0 Then
        thirtySecondTicks = 1
    End If
    If sixtyFourthTicks = 0 Then
        sixtyFourthTicks = 1
    End If

    Dim As ULongInt durationValue(0 To 6) = _
        {quarterTicks * 4, quarterTicks * 2, quarterTicks, _
         eighthTicks, sixteenthTicks, thirtySecondTicks, sixtyFourthTicks}
    Dim As Integer matchedDuration = 0
    For durationIndex As Integer = 0 To 6
        If durationValue(durationIndex) = 0 Then
            Continue For
        End If
        If editableNote.durationTicks = durationValue(durationIndex) Then
            durationCode = durationIndex
            matchedDuration = -1
            Exit For
        End If
        Dim As ULongInt dottedValue = durationValue(durationIndex) + _
            durationValue(durationIndex) \ 2
        If editableNote.durationTicks = dottedValue Then
            durationCode = durationIndex
            dotted = -1
            matchedDuration = -1
            Exit For
        End If
    Next

    If matchedDuration = 0 Then
        If editableNote.durationTicks >= quarterTicks * 4 Then
            durationCode = 0
        ElseIf editableNote.durationTicks >= quarterTicks * 2 Then
            durationCode = 1
        ElseIf editableNote.durationTicks >= quarterTicks Then
            durationCode = 2
        ElseIf editableNote.durationTicks >= eighthTicks Then
            durationCode = 3
        ElseIf editableNote.durationTicks >= sixteenthTicks Then
            durationCode = 4
        ElseIf editableNote.durationTicks >= thirtySecondTicks Then
            durationCode = 5
        Else
            durationCode = 6
        End If
    End If

    Select Case durationCode
        Case 0
            headFilled = 0
            stemRequired = 0
            flagCount = 0
        Case 1
            headFilled = 0
            stemRequired = 1
            flagCount = 0
        Case 2
            headFilled = 1
            stemRequired = 1
            flagCount = 0
        Case 3
            headFilled = 1
            stemRequired = 1
            flagCount = 1
        Case 4
            headFilled = 1
            stemRequired = 1
            flagCount = 2
        Case 5
            headFilled = 1
            stemRequired = 1
            flagCount = 3
        Case Else
            headFilled = 1
            stemRequired = 1
            flagCount = 4
    End Select
End Sub


Private Function session_ScoreBeamBaselineY( _
    ByVal staffY As Integer, ByVal stemUp As Integer _
) As Integer
    /'
        Beamed runs use one shared horizontal baseline one scaled staff-space
        outside the five lines. This keeps every stem attached to one coherent
        beam instead of creating a kink at each change of pitch.
    '/
    Dim As Integer lineSpacing = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight)
    Dim As Integer staffBottomOffset = lineSpacing * 4

    If stemUp <> 0 Then
        Return staffY - lineSpacing
    End If
    Return staffY + staffBottomOffset + lineSpacing
End Function


Private Sub session_DrawScoreNote( _
    ByRef editableNote As MidiEditableNote, _
    ByVal noteX As Integer, _
    ByVal noteY As Integer, _
    ByVal staffY As Integer, _
    ByVal noteColor As ULong, _
    ByVal quarterTicks As ULongInt, _
    ByVal sharpsFlats As Integer, _
    ByVal beamed As Integer, _
    ByVal stemDirection As Integer, _
    ByVal suppressAccidental As Integer _
)
    Dim As Integer lineSpacing = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight)
    Dim As Integer headOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 4)
    Dim As Integer stemLength = lineSpacing * 4
    Dim As Integer stemWidth = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 2)
    Dim As Integer flagWidth = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 11)
    Dim As Integer flagHeight = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 11)
    Dim As Integer durationCode
    Dim As Integer headFilled
    Dim As Integer stemRequired
    Dim As Integer flagCount
    Dim As Integer dotted
    session_ClassifyNoteDuration editableNote, quarterTicks, durationCode, _
        headFilled, stemRequired, flagCount, dotted

    session_DrawNoteLedgerLines noteX, noteY, staffY, noteColor
    If suppressAccidental = 0 Then
        Dim As String accidental = session_NoteAccidental( _
            editableNote.keyNumber, sharpsFlats)
        If accidental <> "" Then
            session_DrawAccidental accidental, noteX - _
                scoreLayout_ScalePixels(session_ScoreTrackRowHeight, 12), _
                noteY, noteColor
        End If
    End If
    Dim As Integer noteHeadWidth = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 10)
    Dim As Integer noteHeadHeight = lineSpacing
    If durationCode = 0 Then
        noteHeadWidth = scoreLayout_ScalePixels( _
            session_ScoreTrackRowHeight, 12)
        noteHeadHeight = scoreLayout_ScalePixels( _
            session_ScoreTrackRowHeight, 8)
    ElseIf durationCode = 1 Then
        noteHeadWidth = scoreLayout_ScalePixels( _
            session_ScoreTrackRowHeight, 11)
    End If
    session_DrawVectorNoteHead noteX, noteY, noteHeadWidth, noteHeadHeight, _
        headFilled, noteColor

    ' Dotted whole notes have no stem, so the dot must be drawn before the
    ' stemless early exit.
    If dotted <> 0 Then
        Dim As Integer dotX = noteX + scoreLayout_ScalePixels( _
            session_ScoreTrackRowHeight, 10)
        If musicSymbols_HasGlyph(MUSIC_SYMBOL_DOT) <> 0 Then
            musicSymbols_DrawCentered MUSIC_SYMBOL_DOT, dotX, noteY, _
                noteColor
        Else
            backend_Circle dotX, noteY, scoreLayout_ScalePixels( _
                session_ScoreTrackRowHeight, 2), noteColor, 1
        End If
    End If

    If stemRequired = 0 Then
        Exit Sub
    End If

    Dim As Integer stemUp = 1
    If noteY < staffY + lineSpacing * 2 Then
        stemUp = 0
    End If
    If stemDirection = 0 Then
        stemUp = 0
    End If
    If stemDirection = 1 Then
        stemUp = 1
    End If

    Dim As Integer stemX = noteX + headOffset
    Dim As Integer stemEndY = noteY - stemLength
    If stemUp = 0 Then
        stemX = noteX - headOffset
        stemEndY = noteY + stemLength
    End If
    If beamed <> 0 Then
        stemEndY = session_ScoreBeamBaselineY(staffY, stemUp)
    End If
    session_DrawVectorNoteStem stemX, noteY, stemEndY, stemWidth, noteColor

    If beamed = 0 Then
        For flagIndex As Integer = 0 To flagCount - 1
            Dim As Integer flagOffset = flagIndex * _
                scoreLayout_ScalePixels(session_ScoreTrackRowHeight, 6)
            If stemUp <> 0 Then
                session_DrawVectorNoteFlag stemX, stemEndY + flagOffset, _
                    stemUp, flagWidth, flagHeight, noteColor
            Else
                session_DrawVectorNoteFlag stemX, stemEndY - flagOffset, _
                    stemUp, flagWidth, flagHeight, noteColor
            End If
        Next
    End If
End Sub


Private Function session_NoteStemDirection( _
    ByVal sourceIndex As Integer, _
    ByRef sourceNote As MidiEditableNote, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
) As Integer
    Dim As Integer sourceCacheIndex = _
        session_ScoreCachePositionForModel(sourceIndex)
    If sourceCacheIndex >= 0 AndAlso _
        session_ScoreStemComputed(sourceCacheIndex) <> 0 Then _
        Return session_ScoreStemDirection(sourceCacheIndex)

    Dim As Integer sourceX
    Dim As Integer sourceY
    session_NoteScreenPosition sourceNote, screenWidth, screenHeight, _
        sourceX, sourceY
    Dim As Integer sourceStaffY = session_ScoreStaffYForTrack( _
        sourceNote.trackIndex, screenHeight)
    Dim As Integer staffMiddleOffset = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight) * 2
    Dim As Integer automaticDirection = 1
    If sourceY < sourceStaffY + staffMiddleOffset Then
        automaticDirection = 0
    End If

    Dim As Integer hasLowerNote = 0
    Dim As Integer hasHigherNote = 0
    Dim As Integer chordNoteCount = 1
    Dim As Long chordYTotal = sourceY
    For candidateCacheIndex As Integer = 0 To _
        session_ScoreVisibleNoteCount - 1
        Dim As Integer candidateIndex = _
            session_ScoreVisibleNoteIndices(candidateCacheIndex)
        If candidateIndex = sourceIndex Then
            Continue For
        End If
        Dim As MidiEditableNote candidateNote
        If midi_GetEditableNote(candidateIndex, candidateNote) = 0 Then
            Continue For
        End If
        If candidateNote.trackIndex <> sourceNote.trackIndex OrElse _
            candidateNote.channel <> sourceNote.channel OrElse _
            candidateNote.startTick <> sourceNote.startTick Then Continue For
        If candidateNote.keyNumber < sourceNote.keyNumber OrElse _
            (candidateNote.keyNumber = sourceNote.keyNumber AndAlso _
             candidateIndex < sourceIndex) Then
            hasLowerNote = -1
        Else
            hasHigherNote = -1
        End If

        Dim As Integer candidateY
        session_NoteScreenPosition candidateNote, screenWidth, screenHeight, _
            sourceX, candidateY
        chordYTotal += candidateY
        chordNoteCount += 1
    Next

    Dim As Integer resolvedDirection = automaticDirection
    If chordNoteCount > 1 Then
        ' A chord is one visual voice in this preview. Average its notehead
        ' positions so every note receives the same stem direction instead of
        ' producing opposing stems for the upper and lower chord members.
        Dim As Integer chordAverageY = CInt(chordYTotal \ chordNoteCount)
        automaticDirection = 1
        If chordAverageY < sourceStaffY + staffMiddleOffset Then _
            automaticDirection = 0
        resolvedDirection = automaticDirection
    ElseIf hasHigherNote <> 0 AndAlso hasLowerNote = 0 Then
        resolvedDirection = 1
    ElseIf hasLowerNote <> 0 AndAlso hasHigherNote = 0 Then
        resolvedDirection = 0
    End If

    If sourceCacheIndex >= 0 Then
        session_ScoreStemDirection(sourceCacheIndex) = resolvedDirection
        session_ScoreStemComputed(sourceCacheIndex) = -1
    End If
    Return resolvedDirection
End Function


Private Function session_FindBeamPartner( _
    ByVal sourceIndex As Integer, _
    ByRef sourceNote As MidiEditableNote, _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal quarterTicks As ULongInt, _
    ByRef partnerIndex As Integer _
) As Integer
    partnerIndex = -1
    Dim As Integer sourceCacheIndex = _
        session_ScoreCachePositionForModel(sourceIndex)
    If sourceCacheIndex >= 0 AndAlso _
        session_ScoreBeamComputed(sourceCacheIndex) <> 0 Then
        partnerIndex = session_ScoreBeamPartner(sourceCacheIndex)
        Return IIf(partnerIndex >= 0, -1, 0)
    End If
    If quarterTicks = 0 Then
        If sourceCacheIndex >= 0 Then _
            session_ScoreBeamComputed(sourceCacheIndex) = -1
        Return 0
    End If

    Dim As Integer sourceStemUp = session_NoteStemDirection(sourceIndex, _
        sourceNote, screenWidth, screenHeight)
    Dim As ULongInt sourceEnd = sourceNote.startTick
    If sourceNote.durationTicks > OSE_MAX_MIDI_TICK - sourceEnd Then
        sourceEnd = OSE_MAX_MIDI_TICK
    Else
        sourceEnd += sourceNote.durationTicks
    End If
    If sourceEnd > session_ScoreNextMeasureBoundary(sourceNote.startTick) Then
        If sourceCacheIndex >= 0 Then _
            session_ScoreBeamComputed(sourceCacheIndex) = -1
        Return 0
    End If

    Dim As Integer sourceDurationCode
    Dim As Integer sourceHeadFilled
    Dim As Integer sourceStemRequired
    Dim As Integer sourceFlagCount
    Dim As Integer sourceDotted
    session_ClassifyNoteDuration sourceNote, quarterTicks, _
        sourceDurationCode, sourceHeadFilled, sourceStemRequired, _
        sourceFlagCount, sourceDotted
    If sourceFlagCount <= 0 Then
        If sourceCacheIndex >= 0 Then _
            session_ScoreBeamComputed(sourceCacheIndex) = -1
        Return 0
    End If

    Dim As ULongInt sourceMeasure = session_ScoreMeasureNumber( _
        sourceNote.startTick)
    Dim As ULongInt nearestForwardGap = CULngInt(-1)
    Dim As Integer nearestForwardIndex = -1
    Dim As ULongInt nearestBackwardGap = CULngInt(-1)
    Dim As Integer nearestBackwardIndex = -1

    For candidateCacheIndex As Integer = 0 To _
        session_ScoreVisibleNoteCount - 1
        Dim As Integer candidateIndex = _
            session_ScoreVisibleNoteIndices(candidateCacheIndex)
        If candidateIndex = sourceIndex Then
            Continue For
        End If
        Dim As MidiEditableNote candidateNote
        If midi_GetEditableNote(candidateIndex, candidateNote) = 0 Then
            Continue For
        End If
        If candidateNote.trackIndex <> sourceNote.trackIndex OrElse _
            candidateNote.channel <> sourceNote.channel Then Continue For
        If session_NoteIsVisible(candidateNote) = 0 Then
            Continue For
        End If
        If candidateNote.startTick = sourceNote.startTick Then
            Continue For
        End If
        Dim As ULongInt candidateEnd = candidateNote.startTick
        If candidateNote.durationTicks > OSE_MAX_MIDI_TICK - candidateEnd Then
            candidateEnd = OSE_MAX_MIDI_TICK
        Else
            candidateEnd += candidateNote.durationTicks
        End If
        If candidateEnd > session_ScoreNextMeasureBoundary( _
            candidateNote.startTick) Then Continue For

        Dim As ULongInt candidateMeasure = session_ScoreMeasureNumber( _
            candidateNote.startTick)
        If candidateMeasure <> sourceMeasure Then
            Continue For
        End If

        Dim As ULongInt noteGap
        If candidateNote.startTick > sourceNote.startTick Then
            noteGap = candidateNote.startTick - sourceNote.startTick
        Else
            noteGap = sourceNote.startTick - candidateNote.startTick
        End If
        If noteGap = 0 OrElse noteGap > quarterTicks Then
            Continue For
        End If

        Dim As Integer candidateStemUp = session_NoteStemDirection( _
            candidateIndex, candidateNote, screenWidth, screenHeight)
        If candidateStemUp <> sourceStemUp Then
            Continue For
        End If

        Dim As Integer candidateDurationCode
        Dim As Integer candidateHeadFilled
        Dim As Integer candidateStemRequired
        Dim As Integer candidateFlagCount
        Dim As Integer candidateDotted
        session_ClassifyNoteDuration candidateNote, quarterTicks, _
            candidateDurationCode, candidateHeadFilled, candidateStemRequired, _
            candidateFlagCount, candidateDotted
        If candidateFlagCount <= 0 Then
            Continue For
        End If

        If candidateNote.startTick > sourceNote.startTick Then
            If noteGap < nearestForwardGap Then
                nearestForwardGap = noteGap
                nearestForwardIndex = candidateIndex
            End If
        ElseIf noteGap < nearestBackwardGap Then
            nearestBackwardGap = noteGap
            nearestBackwardIndex = candidateIndex
        End If
    Next

    ' Prefer a forward neighbor so a run of three or more notes is rendered
    ' as one connected beam chain. A final note still counts as beamed through
    ' its backward neighbor, whose beam was drawn by the preceding note.
    Dim As Integer nearestIndex = nearestForwardIndex
    If nearestIndex < 0 Then
        nearestIndex = nearestBackwardIndex
    End If
    If sourceCacheIndex >= 0 Then
        session_ScoreBeamPartner(sourceCacheIndex) = nearestIndex
        session_ScoreBeamComputed(sourceCacheIndex) = -1
    End If
    If nearestIndex < 0 Then
        Return 0
    End If
    partnerIndex = nearestIndex
    Return -1
End Function


Private Sub session_DrawScoreBeams( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal quarterTicks As ULongInt _
)
    Dim As Integer drawnBeamCount = 0
    Dim As Integer headOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 4)
    Dim As Integer beamSeparation = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 5)
    Dim As Integer beamThickness = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 3)
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer visibleTrackCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer lastTrack = firstTrack + visibleTrackCount - 1
    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote firstNote
        If midi_GetEditableNote(noteIndex, firstNote) = 0 Then
            Continue For
        End If
        If firstNote.trackIndex < firstTrack OrElse _
            firstNote.trackIndex > lastTrack Then Continue For
        If session_NoteIsVisible(firstNote) = 0 Then
            Continue For
        End If

        Dim As Integer secondIndex
        If session_FindBeamPartner(noteIndex, firstNote, screenWidth, _
            screenHeight, quarterTicks, secondIndex) = 0 Then
            Continue For
        End If
        Dim As MidiEditableNote secondNote
        If midi_GetEditableNote(secondIndex, secondNote) = 0 Then
            Continue For
        End If
        If session_NoteIsVisible(secondNote) = 0 Then
            Continue For
        End If
        ' Draw each forward-time connection once. The editable-note array is
        ' not required to be sorted after user edits, so array indices cannot
        ' determine which note is first on the staff.
        If secondNote.startTick <= firstNote.startTick Then
            Continue For
        End If

        Dim As Integer firstX
        Dim As Integer firstY
        Dim As Integer secondX
        Dim As Integer secondY
        session_NoteScreenPosition firstNote, screenWidth, screenHeight, _
            firstX, firstY
        session_NoteScreenPosition secondNote, screenWidth, screenHeight, _
            secondX, secondY
        Dim As Integer stemUp = session_NoteStemDirection(noteIndex, firstNote, _
            screenWidth, screenHeight)

        Dim As Integer firstDurationCode
        Dim As Integer firstHeadFilled
        Dim As Integer firstStemRequired
        Dim As Integer firstFlagCount
        Dim As Integer firstDotted
        session_ClassifyNoteDuration firstNote, quarterTicks, _
            firstDurationCode, firstHeadFilled, firstStemRequired, _
            firstFlagCount, firstDotted
        Dim As Integer secondDurationCode
        Dim As Integer secondHeadFilled
        Dim As Integer secondStemRequired
        Dim As Integer secondFlagCount
        Dim As Integer secondDotted
        session_ClassifyNoteDuration secondNote, quarterTicks, _
            secondDurationCode, secondHeadFilled, secondStemRequired, _
            secondFlagCount, secondDotted
        Dim As Integer beamCount = firstFlagCount
        If secondFlagCount < beamCount Then
            beamCount = secondFlagCount
        End If
        If beamCount <= 0 Then
            Continue For
        End If

        Dim As Integer beamStaffY = session_ScoreStaffYForTrack( _
            firstNote.trackIndex, screenHeight)
        Dim As Integer firstStemEndY = session_ScoreBeamBaselineY( _
            beamStaffY, stemUp)
        Dim As Integer firstStemX = firstX + headOffset
        Dim As Integer secondStemX = secondX + headOffset
        If stemUp = 0 Then
            firstStemX = firstX - headOffset
            secondStemX = secondX - headOffset
        End If

        For beamIndex As Integer = 0 To beamCount - 1
            Dim As Integer beamOffset = beamIndex * beamSeparation
            Dim As Integer beamY1 = firstStemEndY + beamOffset
            If stemUp = 0 Then
                beamY1 = firstStemEndY - beamOffset
            End If
            Dim As Integer beamLeft = firstStemX
            Dim As Integer beamRight = secondStemX
            If beamLeft > beamRight Then
                Swap beamLeft, beamRight
            End If
            backend_Rect beamLeft, beamY1 - beamThickness \ 2, _
                beamRight - beamLeft + 1, beamThickness, _
                session_ThemePalette.textColor, 1
        Next
        drawnBeamCount += 1
        If drawnBeamCount >= 512 Then
            Exit For
        End If
    Next
End Sub


Private Sub session_DrawScorePartialBeams( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal quarterTicks As ULongInt _
)
    Dim As Integer headOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 4)
    Dim As Integer beamSeparation = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 5)
    Dim As Integer partialBeamLength = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 10)
    Dim As Integer beamThickness = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 3)
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer visibleTrackCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer lastTrack = firstTrack + visibleTrackCount - 1
    Dim As Integer drawnPartialCount = 0

    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote sourceNote
        If midi_GetEditableNote(noteIndex, sourceNote) = 0 Then
            Continue For
        End If
        If sourceNote.trackIndex < firstTrack OrElse _
            sourceNote.trackIndex > lastTrack Then Continue For
        If session_NoteIsVisible(sourceNote) = 0 Then
            Continue For
        End If

        Dim As Integer partnerIndex
        If session_FindBeamPartner(noteIndex, sourceNote, screenWidth, _
            screenHeight, quarterTicks, partnerIndex) = 0 Then Continue For
        Dim As MidiEditableNote partnerNote
        If midi_GetEditableNote(partnerIndex, partnerNote) = 0 Then
            Continue For
        End If

        Dim As Integer sourceDurationCode
        Dim As Integer sourceHeadFilled
        Dim As Integer sourceStemRequired
        Dim As Integer sourceFlagCount
        Dim As Integer sourceDotted
        session_ClassifyNoteDuration sourceNote, quarterTicks, _
            sourceDurationCode, sourceHeadFilled, sourceStemRequired, _
            sourceFlagCount, sourceDotted
        If sourceFlagCount <= 0 Then
            Continue For
        End If

        Dim As Integer partnerDurationCode
        Dim As Integer partnerHeadFilled
        Dim As Integer partnerStemRequired
        Dim As Integer partnerFlagCount
        Dim As Integer partnerDotted
        session_ClassifyNoteDuration partnerNote, quarterTicks, _
            partnerDurationCode, partnerHeadFilled, partnerStemRequired, _
            partnerFlagCount, partnerDotted
        Dim As Integer commonBeamCount = sourceFlagCount
        If partnerFlagCount < commonBeamCount Then _
            commonBeamCount = partnerFlagCount
        If sourceFlagCount <= commonBeamCount Then
            Continue For
        End If

        Dim As Integer sourceX
        Dim As Integer sourceY
        session_NoteScreenPosition sourceNote, screenWidth, screenHeight, _
            sourceX, sourceY
        Dim As Integer stemUp = session_NoteStemDirection(noteIndex, _
            sourceNote, screenWidth, screenHeight)
        Dim As Integer stemX = sourceX + headOffset
        Dim As Integer beamStaffY = session_ScoreStaffYForTrack( _
            sourceNote.trackIndex, screenHeight)
        Dim As Integer stemEndY = session_ScoreBeamBaselineY( _
            beamStaffY, stemUp)
        If stemUp = 0 Then
            stemX = sourceX - headOffset
        End If
        Dim As Integer towardRight = 0
        If partnerNote.startTick > sourceNote.startTick Then
            towardRight = -1
        End If
        For beamIndex As Integer = commonBeamCount To sourceFlagCount - 1
            Dim As Integer beamY = stemEndY + beamIndex * beamSeparation
            If stemUp = 0 Then _
                beamY = stemEndY - beamIndex * beamSeparation
            Dim As Integer beamEndX = stemX - partialBeamLength
            If towardRight <> 0 Then
                beamEndX = stemX + partialBeamLength
            End If
            Dim As Integer beamLeft = stemX
            Dim As Integer beamRight = beamEndX
            If beamLeft > beamRight Then
                Swap beamLeft, beamRight
            End If
            backend_Rect beamLeft, beamY - beamThickness \ 2, _
                beamRight - beamLeft + 1, beamThickness, _
                session_ThemePalette.textColor, 1
            drawnPartialCount += 1
            If drawnPartialCount >= 1024 Then
                Exit For
            End If
        Next
        If drawnPartialCount >= 1024 Then
            Exit For
        End If
    Next
End Sub


Private Sub session_DrawScoreTies( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal noteColor As ULong _
)
    Dim As Integer drawnTieCount = 0
    Dim As Integer tieHeadInset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 5)
    Dim As Integer tieMinimumSpan = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 12)
    Dim As Integer tieCurveOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 9)
    Dim As Integer tieControlOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 8)
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer visibleTrackCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer lastTrack = firstTrack + visibleTrackCount - 1
    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote firstNote
        If midi_GetEditableNote(noteIndex, firstNote) = 0 Then
            Continue For
        End If
        If firstNote.trackIndex < firstTrack OrElse _
            firstNote.trackIndex > lastTrack Then Continue For
        If session_NoteIsVisible(firstNote) = 0 Then
            Continue For
        End If

        Dim As ULongInt firstEnd = firstNote.startTick + _
            firstNote.durationTicks
        If firstEnd < firstNote.startTick Then
            Continue For
        End If
        Dim As Integer successorIndex = -1
        For candidateCacheIndex As Integer = 0 To _
            session_ScoreVisibleNoteCount - 1
            Dim As Integer candidateIndex = _
                session_ScoreVisibleNoteIndices(candidateCacheIndex)
            If candidateIndex = noteIndex Then
                Continue For
            End If
            Dim As MidiEditableNote candidateNote
            If midi_GetEditableNote(candidateIndex, candidateNote) = 0 Then
                Continue For
            End If
            If candidateNote.trackIndex <> firstNote.trackIndex OrElse _
                candidateNote.channel <> firstNote.channel OrElse _
                candidateNote.keyNumber <> firstNote.keyNumber Then Continue For
            If candidateNote.startTick <> firstEnd Then
                Continue For
            End If
            successorIndex = candidateIndex
            Exit For
        Next
        If successorIndex < 0 Then
            Continue For
        End If

        Dim As MidiEditableNote secondNote
        If midi_GetEditableNote(successorIndex, secondNote) = 0 Then
            Continue For
        End If
        If session_NoteIsVisible(secondNote) = 0 Then
            Continue For
        End If

        Dim As Integer firstX
        Dim As Integer firstY
        Dim As Integer secondX
        Dim As Integer secondY
        session_NoteScreenPosition firstNote, screenWidth, screenHeight, _
            firstX, firstY
        session_NoteScreenPosition secondNote, screenWidth, screenHeight, _
            secondX, secondY
        If secondX <= firstX + tieMinimumSpan Then
            Continue For
        End If

        Dim As Integer curveY = firstY + tieCurveOffset
        If secondY > curveY Then
            curveY = secondY + tieCurveOffset
        End If
        Dim As Integer controlX = (firstX + secondX) \ 2
        backend_Curve firstX + tieHeadInset, firstY + tieHeadInset, _
            controlX, curveY + tieControlOffset, _
            secondX - tieHeadInset, secondY + tieHeadInset, noteColor
        drawnTieCount += 1
        If drawnTieCount >= 512 Then
            Exit For
        End If
    Next
End Sub


Private Sub session_DrawScoreNotes( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal quarterTicks As ULongInt, _
    ByVal sharpsFlats As Integer _
)
    Dim As Integer tieMinimumSpan = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 4)
    Dim As Integer tieHeadInset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 5)
    Dim As Integer tieCurveOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 9)
    Dim As Integer tieControlOffset = scoreLayout_ScalePixels( _
        session_ScoreTrackRowHeight, 8)
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer visibleTrackCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer lastTrack = firstTrack + visibleTrackCount - 1
    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote editableNote
        If midi_GetEditableNote(noteIndex, editableNote) = 0 Then
            Continue For
        End If
        If editableNote.trackIndex < firstTrack OrElse _
            editableNote.trackIndex > lastTrack Then Continue For
        If session_NoteIsVisible(editableNote) = 0 Then
            Continue For
        End If

        Dim As ULong noteColor = Iif(session_NoteIsSelected(noteIndex) <> 0, _
            session_ThemePalette.warningColor, session_ThemePalette.textColor)

        Dim As Integer noteStaffY = session_ScoreStaffYForTrack( _
            editableNote.trackIndex, screenHeight)
        Dim As Integer beamPartnerIndex
        Dim As Integer isBeamed = session_FindBeamPartner(noteIndex, _
            editableNote, screenWidth, screenHeight, quarterTicks, beamPartnerIndex)
        Dim As Integer stemDirection = session_NoteStemDirection(noteIndex, _
            editableNote, screenWidth, screenHeight)

        Dim As ULongInt noteEnd = editableNote.startTick
        If editableNote.durationTicks > OSE_MAX_MIDI_TICK - noteEnd Then
            noteEnd = OSE_MAX_MIDI_TICK
        Else
            noteEnd += editableNote.durationTicks
        End If
        If noteEnd <= editableNote.startTick Then
            Continue For
        End If

        Dim As Integer splitNote = 0
        If session_ScoreNextMeasureBoundary(editableNote.startTick) < noteEnd Then _
            splitNote = -1
        Dim As ULongInt segmentStart = editableNote.startTick
        Dim As Integer segmentIndex = 0
        Dim As Integer previousX = -1
        Dim As Integer previousY = 0
        While segmentStart < noteEnd
            Dim As ULongInt segmentEnd = noteEnd
            If segmentIndex < SESSION_MAX_SCORE_NOTE_SEGMENTS - 1 Then
                Dim As ULongInt measureBoundary = _
                    session_ScoreNextMeasureBoundary(segmentStart)
                If measureBoundary > segmentStart AndAlso _
                    measureBoundary < segmentEnd Then
                    segmentEnd = measureBoundary
                End If
            End If
            If segmentEnd <= segmentStart Then
                Exit While
            End If

            Dim As MidiEditableNote displayNote = editableNote
            displayNote.startTick = segmentStart
            displayNote.durationTicks = segmentEnd - segmentStart

            Dim As Integer segmentNoteX
            Dim As Integer segmentNoteY
            session_NoteScreenPosition displayNote, screenWidth, screenHeight, _
                segmentNoteX, segmentNoteY

            Dim As Integer segmentSharpsFlats = sharpsFlats
            Dim As Integer segmentKeyIndex = session_KeySignatureIndexForTick( _
                segmentStart)
            If segmentKeyIndex >= 0 AndAlso segmentKeyIndex < _
                session_Summary.keySignatureCount Then
                segmentSharpsFlats = session_Summary.keySignatureMap( _
                    segmentKeyIndex).sharpsFlats
            End If

            Dim As Integer segmentBeamed = isBeamed
            If splitNote <> 0 Then
                segmentBeamed = 0
            End If
            Dim As Integer suppressAccidental = 0
            If segmentIndex > 0 Then
                suppressAccidental = -1
            End If
            session_DrawScoreNote displayNote, segmentNoteX, segmentNoteY, _
                noteStaffY, noteColor, quarterTicks, segmentSharpsFlats, _
                segmentBeamed, stemDirection, suppressAccidental

            If previousX >= 0 AndAlso _
                segmentNoteX > previousX + tieMinimumSpan Then
                Dim As Integer curveY = previousY + tieCurveOffset
                If segmentNoteY > curveY Then _
                    curveY = segmentNoteY + tieCurveOffset
                Dim As Integer controlX = (previousX + segmentNoteX) \ 2
                backend_Curve previousX + tieHeadInset, _
                    previousY + tieHeadInset, controlX, _
                    curveY + tieControlOffset, _
                    segmentNoteX - tieHeadInset, _
                    segmentNoteY + tieHeadInset, noteColor
            End If
            previousX = segmentNoteX
            previousY = segmentNoteY
            segmentIndex += 1
            If segmentEnd >= noteEnd Then
                Exit While
            End If
            segmentStart = segmentEnd
        Wend
    Next

    session_DrawScoreBeams screenWidth, screenHeight, quarterTicks
    session_DrawScorePartialBeams screenWidth, screenHeight, quarterTicks
    session_DrawScoreTies screenWidth, screenHeight, session_ThemePalette.textColor
End Sub


Private Function session_TimeSignatureBeatTicks( _
    ByRef signaturePoint As MidiTimeSignaturePoint _
) As ULongInt
    If session_Summary.division <= 0 Then
        Return 1
    End If

    Dim As ULongInt beatTicks = CULngInt(session_Summary.division) * 4
    For powerIndex As Integer = 1 To signaturePoint.denominatorPower ' fblint: disable-line FBL311 REASON: The counter bounds the power-of-two denominator calculation.
        beatTicks \= 2
    Next
    If beatTicks = 0 Then
        beatTicks = 1
    End If
    Return beatTicks
End Function


Private Function session_TimeSignatureMeasureTicks( _
    ByRef signaturePoint As MidiTimeSignaturePoint _
) As ULongInt
    Dim As ULongInt measureTicks = _
        session_TimeSignatureBeatTicks(signaturePoint) * _
        CULngInt(signaturePoint.numerator)
    If measureTicks = 0 Then
        measureTicks = 1
    End If
    Return measureTicks
End Function


Private Function session_ScoreTickToX( _
    ByVal tick As ULongInt, _
    ByVal scoreLeft As Integer, _
    ByVal scoreRight As Integer, _
    ByVal ticksPerView As ULongInt _
) As Integer
    If tick <= session_ViewStartTick Then
        Return scoreLeft
    End If
    If tick >= session_ViewStartTick + ticksPerView Then
        Return scoreRight
    End If
    Return scoreLeft + CInt((CDbl(scoreRight - scoreLeft) * _
        CDbl(tick - session_ViewStartTick)) / CDbl(ticksPerView))
End Function


Private Sub session_DrawKeySignature( _
    ByVal scoreLeft As Integer, _
    ByVal firstStaffY As Integer, _
    ByVal staffGap As Integer, _
    ByVal staffCount As Integer, _
    ByVal firstTrack As Integer, _
    ByVal sharpsFlats As Integer _
)
    If sharpsFlats < -7 Then
        sharpsFlats = -7
    End If
    If sharpsFlats > 7 Then
        sharpsFlats = 7
    End If
    If sharpsFlats = 0 Then
        Exit Sub
    End If

    Dim As Integer accidentalCount = Abs(sharpsFlats)
    Dim As String accidentalText = "#"
    If sharpsFlats < 0 Then
        accidentalText = "b"
    End If
    Dim As Integer trebleSharpY(0 To 6) = {0, 7, -7, 4, 11, -3, 18}
    Dim As Integer trebleFlatY(0 To 6) = {14, 7, 21, 4, 28, 11, 18}
    Dim As Integer bassSharpY(0 To 6) = {7, 21, 4, 18, 0, 14, 28}
    Dim As Integer bassFlatY(0 To 6) = {0, 14, 7, 21, 4, 18, 11}

    For staffIndex As Integer = 0 To staffCount - 1
        Dim As Integer staffY = firstStaffY + staffIndex * staffGap
        Dim As Integer trackIndex = firstTrack + staffIndex
        Dim As Integer usesBassClef = session_TrackUsesBassClef(trackIndex)
        For accidentalIndex As Integer = 0 To accidentalCount - 1
            Dim As Integer accidentalY
            If usesBassClef = 0 Then
                If sharpsFlats > 0 Then
                    accidentalY = trebleSharpY(accidentalIndex)
                Else
                    accidentalY = trebleFlatY(accidentalIndex)
                End If
            Else
                If sharpsFlats > 0 Then
                    accidentalY = bassSharpY(accidentalIndex)
                Else
                    accidentalY = bassFlatY(accidentalIndex)
                End If
            End If
            accidentalY = scoreLayout_ScalePixels( _
                session_ScoreTrackRowHeight, accidentalY)
            session_DrawAccidental accidentalText, _
                scoreLeft + 15 + accidentalIndex * 7, _
                staffY + accidentalY, session_ThemePalette.textColor
        Next
    Next
End Sub


Private Sub session_DrawStaffTimeSignature( _
    ByVal staffY As Integer, ByVal numerator As Integer, ByVal denominator As Integer _
)
    ' The fixed gutter already reserves space after the clef and up to seven
    ' key accidentals. Stack the two numbers there, before the note timeline.
    Dim As Integer halfHeight = scoreLayout_LineSpacing(session_ScoreTrackRowHeight) * 2
    Dim As Integer fontId = BACKEND_FONT_UI_12_BOLD
    If backend_GetTextHeightFont(fontId) > halfHeight Then
        fontId = BACKEND_FONT_DEFAULT
    End If
    If backend_GetTextHeightFont(BACKEND_FONT_UI_18_BOLD) <= halfHeight Then _
        fontId = BACKEND_FONT_UI_18_BOLD
    backend_PrintAligned SESSION_SCORE_LEFT + 112, staffY, 42, halfHeight, _
        session_ThemePalette.textColor, LTrim(Str(numerator)), fontId, _
        BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
    backend_PrintAligned SESSION_SCORE_LEFT + 112, staffY + halfHeight, 42, halfHeight, _
        session_ThemePalette.textColor, LTrim(Str(denominator)), fontId, _
        BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
End Sub


Private Function session_ScoreIsMeasureStart(ByVal tick As ULongInt) As Integer
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick(tick)
    If signatureIndex < 0 OrElse _
        signatureIndex >= session_Summary.timeSignatureCount Then Return 0
    Dim As MidiTimeSignaturePoint signaturePoint = _
        session_Summary.timeSignatureMap(signatureIndex)
    Dim As ULongInt measureTicks = _
        session_TimeSignatureMeasureTicks(signaturePoint)
    If tick < signaturePoint.tick OrElse measureTicks = 0 Then
        Return 0
    End If
    If (tick - signaturePoint.tick) Mod measureTicks = 0 Then ' fblint: disable-line FBL406 REASON: Range checks keep the dividend nonnegative and the modulus positive before this calculation.
        Return -1
    End If
    Return 0
End Function


Private Function session_ScoreMeasureNumber(ByVal tick As ULongInt) As ULongInt
    If session_Summary.timeSignatureCount <= 0 Then
        Return 1
    End If

    Dim As ULongInt completedMeasures = 0
    For signatureIndex As Integer = 0 To _
        session_Summary.timeSignatureCount - 1
        Dim As MidiTimeSignaturePoint signaturePoint = _
            session_Summary.timeSignatureMap(signatureIndex)
        Dim As ULongInt segmentStart = signaturePoint.tick
        If tick < segmentStart Then
            Exit For
        End If
        Dim As ULongInt segmentEnd = tick
        If signatureIndex + 1 < session_Summary.timeSignatureCount Then
            Dim As ULongInt nextTick = _
                session_Summary.timeSignatureMap(signatureIndex + 1).tick
            If nextTick < segmentEnd Then
                segmentEnd = nextTick
            End If
        End If
        Dim As ULongInt measureTicks = _
            session_TimeSignatureMeasureTicks(signaturePoint)
        If measureTicks > 0 AndAlso segmentEnd >= segmentStart Then
            completedMeasures += (segmentEnd - segmentStart) \ measureTicks
        End If
        If segmentEnd = tick Then
            Exit For
        End If
    Next
    Return completedMeasures + 1
End Function


Private Sub session_MusicalPosition( _
    ByVal tick As ULongInt, _
    ByRef measureNumber As ULongInt, _
    ByRef beatNumber As ULongInt, _
    ByRef subTick As ULongInt _
)
    measureNumber = session_ScoreMeasureNumber(tick)
    beatNumber = 1
    subTick = 0

    Dim As ULongInt segmentStart
    Dim As ULongInt beatTicks = 1
    If session_Summary.division > 0 Then _
        beatTicks = CULngInt(session_Summary.division)
    Dim As ULongInt measureTicks = beatTicks * 4
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick(tick)
    If signatureIndex >= 0 AndAlso _
        signatureIndex < session_Summary.timeSignatureCount Then
        Dim As MidiTimeSignaturePoint signaturePoint = _
            session_Summary.timeSignatureMap(signatureIndex)
        segmentStart = signaturePoint.tick
        beatTicks = session_TimeSignatureBeatTicks(signaturePoint)
        measureTicks = session_TimeSignatureMeasureTicks(signaturePoint)
    End If
    If beatTicks = 0 Then
        beatTicks = 1
    End If
    If measureTicks = 0 Then
        measureTicks = beatTicks
    End If
    If tick < segmentStart Then
        Exit Sub
    End If

    Dim As ULongInt offsetInMeasure = _
        (tick - segmentStart) Mod measureTicks ' fblint: disable-line FBL406 REASON: Range checks keep the dividend nonnegative and the modulus positive before this calculation.
    beatNumber = offsetInMeasure \ beatTicks + 1
    subTick = offsetInMeasure Mod beatTicks
End Sub


Private Function session_MusicalPositionText( _
    ByVal tick As ULongInt _
) As String
    Dim As ULongInt measureNumber
    Dim As ULongInt beatNumber
    Dim As ULongInt subTick
    session_MusicalPosition tick, measureNumber, beatNumber, subTick
    Return LTrim(Str(measureNumber)) + ":" + LTrim(Str(beatNumber)) + _
        ":" + LTrim(Str(subTick))
End Function


Private Function session_ScoreNextMeasureBoundary( _
    ByVal tick As ULongInt _
) As ULongInt
    If tick >= OSE_MAX_MIDI_TICK Then
        Return OSE_MAX_MIDI_TICK
    End If

    Dim As ULongInt segmentStart = 0
    Dim As ULongInt measureTicks = CULngInt(session_Summary.division) * 4
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick(tick)
    If signatureIndex >= 0 AndAlso signatureIndex < _
        session_Summary.timeSignatureCount Then
        Dim As MidiTimeSignaturePoint signaturePoint = _
            session_Summary.timeSignatureMap(signatureIndex)
        segmentStart = signaturePoint.tick
        measureTicks = session_TimeSignatureMeasureTicks(signaturePoint)
    End If
    If measureTicks = 0 Then
        measureTicks = 1
    End If
    If tick < segmentStart Then
        Return segmentStart
    End If

    Dim As ULongInt elapsedTicks = tick - segmentStart
    Dim As ULongInt measureIndex = elapsedTicks \ measureTicks
    Dim As ULongInt measureStep = measureIndex + 1
    Dim As ULongInt nextBoundary = OSE_MAX_MIDI_TICK
    If measureStep <= (OSE_MAX_MIDI_TICK - segmentStart) \ measureTicks Then
        nextBoundary = segmentStart + measureStep * measureTicks
    End If

    If signatureIndex >= 0 AndAlso signatureIndex + 1 < _
        session_Summary.timeSignatureCount Then
        Dim As ULongInt nextSignatureTick = _
            session_Summary.timeSignatureMap(signatureIndex + 1).tick
        If nextSignatureTick < nextBoundary Then
            nextBoundary = nextSignatureTick
        End If
    End If

    If nextBoundary <= tick Then
        nextBoundary = tick + 1
    End If
    If nextBoundary > OSE_MAX_MIDI_TICK Then _
        nextBoundary = OSE_MAX_MIDI_TICK
    Return nextBoundary
End Function


Private Sub session_DrawScoreMeterGuides( _
    ByVal scoreLeft As Integer, _
    ByVal scoreRight As Integer, _
    ByVal firstStaffY As Integer, _
    ByVal staffGap As Integer, _
    ByVal staffCount As Integer, _
    ByVal ticksPerView As ULongInt _
)
    If session_Summary.timeSignatureCount <= 0 Then
        Exit Sub
    End If
    Dim As Integer lineSpacing = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight)
    Dim As Integer staffHeight = lineSpacing * 4
    Dim As Integer guideMargin = (lineSpacing + 1) \ 2

    Dim As ULongInt viewEndTick = session_ViewStartTick + ticksPerView
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick( _
        session_ViewStartTick)
    If signatureIndex < 0 Then
        signatureIndex = 0
    End If
    Dim As ULongInt segmentStart = session_ViewStartTick
    Dim As Integer drawnGuideCount = 0

    While signatureIndex < session_Summary.timeSignatureCount
        Dim As MidiTimeSignaturePoint signaturePoint = _
            session_Summary.timeSignatureMap(signatureIndex)
        Dim As ULongInt segmentEnd = viewEndTick
        If signatureIndex + 1 < session_Summary.timeSignatureCount Then
            Dim As ULongInt nextSignatureTick = _
                session_Summary.timeSignatureMap(signatureIndex + 1).tick
            If nextSignatureTick < segmentEnd Then
                segmentEnd = nextSignatureTick
            End If
        End If

        Dim As ULongInt beatTicks = _
            session_TimeSignatureBeatTicks(signaturePoint)
        Dim As ULongInt measureTicks = _
            session_TimeSignatureMeasureTicks(signaturePoint)
        Dim As ULongInt firstGuideTick = signaturePoint.tick
        If firstGuideTick < segmentStart Then
            Dim As ULongInt elapsedTicks = segmentStart - firstGuideTick
            Dim As ULongInt beatNumber = elapsedTicks \ beatTicks
            If elapsedTicks Mod beatTicks <> 0 Then
                beatNumber += 1
            End If
            firstGuideTick += beatNumber * beatTicks
        End If

        Dim As ULongInt guideTick = firstGuideTick
        While guideTick <= segmentEnd AndAlso guideTick <= viewEndTick
            Dim As Integer beatX = session_ScoreTickToX(guideTick, _
                scoreLeft, scoreRight, ticksPerView)
            Dim As ULong guideColor = session_ThemePalette.scoreGuideColor
            Dim As Integer isMeasureStart = 0
            If (guideTick - signaturePoint.tick) Mod measureTicks = 0 Then ' fblint: disable-line FBL406 REASON: Range checks keep the dividend nonnegative and the modulus positive before this calculation.
                guideColor = session_ThemePalette.scoreStrongGuideColor
                isMeasureStart = -1
            End If
            For staffIndex As Integer = 0 To staffCount - 1
                Dim As Integer staffY = firstStaffY + staffIndex * staffGap
                If isMeasureStart <> 0 Then
                    backend_LineEx beatX, staffY - lineSpacing, beatX, _
                        staffY + staffHeight + lineSpacing, _
                        session_ThemePalette.scoreStrongGuideColor, 2
                Else
                    backend_Line beatX, staffY - guideMargin, beatX, _
                        staffY + staffHeight + guideMargin, _
                        guideColor
                End If
            Next
            If isMeasureStart <> 0 AndAlso staffCount > 1 Then
                ' Join the individual staff segments so a grand visual system
                ' still reads as one measure boundary across every track row.
                backend_LineEx beatX, firstStaffY - lineSpacing, beatX, _
                    firstStaffY + (staffCount - 1) * staffGap + _
                    staffHeight + lineSpacing, _
                    session_ThemePalette.scoreStrongGuideColor, 2
            End If
            drawnGuideCount += 1
            If drawnGuideCount >= 256 Then
                Exit Sub
            End If
            If beatTicks > viewEndTick - guideTick Then
                Exit While
            End If
            guideTick += beatTicks
        Wend

        If signatureIndex + 1 >= session_Summary.timeSignatureCount Then
            Exit While
        End If
        Dim As ULongInt nextTick = _
            session_Summary.timeSignatureMap(signatureIndex + 1).tick
        If nextTick > viewEndTick Then
            Exit While
        End If
        If nextTick <= segmentStart Then
            signatureIndex += 1
            Continue While
        End If
        Dim As MidiTimeSignaturePoint nextSignature = _
            session_Summary.timeSignatureMap(signatureIndex + 1)
        Dim As Integer signatureX = session_ScoreTickToX(nextTick, _
            scoreLeft, scoreRight, ticksPerView)
        backend_Line signatureX, SESSION_SCORE_TOP + 25, signatureX, _
            SESSION_SCORE_TOP + 34, session_ThemePalette.mutedTextColor
        backend_Print signatureX + 2, SESSION_SCORE_TOP + 26, _
            session_ThemePalette.textColor, Str(nextSignature.numerator) + "/" + _
            Str(session_TempoDenominatorValue(nextSignature.denominatorPower))
        segmentStart = nextTick
        signatureIndex += 1
    Wend
End Sub


Private Sub session_DrawWholeRest( _
    ByVal restX As Integer, _
    ByVal staffY As Integer, _
    ByVal restColor As ULong _
)
    ' The small hanging block is a readable whole-rest glyph at this scale.
    backend_Rect restX - 5, staffY + 7, 10, 5, restColor, 1
    backend_Line restX, staffY + 12, restX, staffY + 20, restColor
End Sub


Private Sub session_DrawRestGlyph( _
    ByVal restX As Integer, _
    ByVal staffY As Integer, _
    ByVal durationCode As Integer, _
    ByVal dotted As Integer, _
    ByVal restColor As ULong _
)
    Select Case durationCode
        Case 0
            session_DrawWholeRest restX, staffY, restColor
        Case 1
            backend_Rect restX - 5, staffY + 3, 10, 5, restColor, 1
            backend_Line restX - 5, staffY + 3, restX + 5, staffY + 3, _
                restColor
        Case 2
            If musicSymbols_HasGlyph(MUSIC_SYMBOL_QUARTER_REST) <> 0 Then
                musicSymbols_DrawCentered MUSIC_SYMBOL_QUARTER_REST, restX, _
                    staffY + 12, restColor
            Else
                backend_Line restX - 4, staffY + 5, restX + 3, _
                    staffY + 9, restColor
                backend_Line restX + 3, staffY + 9, restX - 3, _
                    staffY + 14, restColor
                backend_Line restX - 3, staffY + 14, restX + 4, _
                    staffY + 19, restColor
            End If
        Case 3
            If musicSymbols_HasGlyph(MUSIC_SYMBOL_EIGHTH_REST) <> 0 Then
                musicSymbols_DrawCentered MUSIC_SYMBOL_EIGHTH_REST, restX, _
                    staffY + 12, restColor
            Else
                backend_Line restX, staffY + 5, restX, staffY + 20, restColor
                backend_Line restX, staffY + 5, restX + 8, _
                    staffY + 10, restColor
            End If
        Case Else
            Const REST_FLAG_RISE As Integer = 6
            backend_Line restX, staffY + 5, restX, staffY + 20, restColor
            backend_Line restX, staffY + 5, restX + 8, _
                staffY + 5 + REST_FLAG_RISE, restColor
            If durationCode >= 4 Then
                backend_Line restX, staffY + 9, restX + 8, _
                    staffY + 9 + REST_FLAG_RISE, restColor
            End If
            If durationCode >= 5 Then
                backend_Line restX, staffY + 13, restX + 8, _
                    staffY + 13 + REST_FLAG_RISE, restColor
            End If
            If durationCode >= 6 Then
                backend_Line restX, staffY + 17, restX + 8, _
                    staffY + 17 + REST_FLAG_RISE, restColor
            End If
    End Select

    If dotted <> 0 Then
        If musicSymbols_HasGlyph(MUSIC_SYMBOL_DOT) <> 0 Then
            musicSymbols_DrawCentered MUSIC_SYMBOL_DOT, restX + 10, _
                staffY + 14, restColor
        Else
            backend_Circle restX + 11, staffY + 14, 2, restColor, 1
        End If
    End If
End Sub


Private Sub session_DrawRestSpan( _
    ByVal rangeStart As ULongInt, _
    ByVal rangeEnd As ULongInt, _
    ByVal scoreLeft As Integer, _
    ByVal scoreRight As Integer, _
    ByVal firstStaffY As Integer, _
    ByVal staffIndex As Integer, _
    ByVal staffGap As Integer, _
    ByVal ticksPerView As ULongInt, _
    ByVal quarterTicks As ULongInt, _
    ByVal restColor As ULong, _
    ByRef drawnRestCount As Integer _
)
    If rangeEnd <= rangeStart OrElse quarterTicks = 0 Then
        Exit Sub
    End If

    Dim As ULongInt cursorTick = rangeStart
    While cursorTick < rangeEnd
        Dim As ULongInt remainingTicks = rangeEnd - cursorTick
        Dim As ULongInt chosenTicks = 1
        Dim As Integer chosenCode = 6
        Dim As Integer chosenDotted = 0

        For durationCode As Integer = 0 To 6
            Dim As ULongInt baseTicks = quarterTicks
            Select Case durationCode
                Case 0
                    baseTicks = quarterTicks * 4
                Case 1
                    baseTicks = quarterTicks * 2
                Case 2
                    baseTicks = quarterTicks
                Case 3
                    baseTicks = quarterTicks \ 2
                Case 4
                    baseTicks = quarterTicks \ 4
                Case 5
                    baseTicks = quarterTicks \ 8
                Case Else
                    baseTicks = quarterTicks \ 16
            End Select
            If baseTicks = 0 Then
                Continue For
            End If

            If baseTicks <= remainingTicks AndAlso baseTicks > chosenTicks Then
                chosenTicks = baseTicks
                chosenCode = durationCode
                chosenDotted = 0
            End If
            Dim As ULongInt dottedTicks = baseTicks + baseTicks \ 2
            If dottedTicks <= remainingTicks AndAlso dottedTicks > chosenTicks Then
                chosenTicks = dottedTicks
                chosenCode = durationCode
                chosenDotted = -1
            End If
        Next

        ' A non-standard remainder shorter than a 64th is represented once.
        ' Advancing one tick at a time would stack many glyphs on one pixel and
        ' can produce an opaque blot beside a measure line.
        If chosenTicks = 1 AndAlso remainingTicks > 1 Then
            chosenTicks = remainingTicks
            chosenCode = 6
            chosenDotted = 0
        End If
        If chosenTicks > remainingTicks Then
            chosenTicks = remainingTicks
        End If
        If chosenTicks = 0 Then
            Exit While
        End If
        Dim As ULongInt restEnd = cursorTick + chosenTicks
        If restEnd < cursorTick Then
            restEnd = rangeEnd
        End If
        Dim As ULongInt restCenter = cursorTick + _
            (restEnd - cursorTick) \ 2
        If restCenter >= session_ViewStartTick AndAlso _
            restCenter <= session_ViewStartTick + ticksPerView Then
            Dim As Integer restX = session_ScoreTickToX(restCenter, _
                scoreLeft, scoreRight, ticksPerView)
            Dim As Integer staffY = firstStaffY + staffIndex * staffGap
            session_DrawRestGlyph restX, staffY, chosenCode, chosenDotted, _
                restColor
            drawnRestCount += 1
        End If
        If drawnRestCount >= 1024 Then
            Exit Sub
        End If
        cursorTick = restEnd
    Wend
End Sub


Private Sub session_DrawScoreRests( _
    ByVal scoreLeft As Integer, _
    ByVal scoreRight As Integer, _
    ByVal screenHeight As Integer, _
    ByVal firstStaffY As Integer, _
    ByVal staffGap As Integer, _
    ByVal ticksPerView As ULongInt _
)
    If session_Summary.timeSignatureCount <= 0 OrElse _
        session_Summary.trackCount <= 0 Then Exit Sub

    Dim As ULongInt viewEndTick = session_ViewStartTick + ticksPerView
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick( _
        session_ViewStartTick)
    If signatureIndex < 0 Then
        signatureIndex = 0
    End If
    Dim As ULongInt segmentStart = session_ViewStartTick
    Dim As Integer drawnRestCount = 0
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer visibleTrackCount = session_ScoreVisibleTrackCount(screenHeight)
    Dim As Integer lastTrack = firstTrack + visibleTrackCount - 1

    While signatureIndex < session_Summary.timeSignatureCount
        Dim As MidiTimeSignaturePoint signaturePoint = _
            session_Summary.timeSignatureMap(signatureIndex)
        Dim As ULongInt segmentEnd = viewEndTick
        If signatureIndex + 1 < session_Summary.timeSignatureCount Then
            Dim As ULongInt nextSignatureTick = _
                session_Summary.timeSignatureMap(signatureIndex + 1).tick
            If nextSignatureTick < segmentEnd Then
                segmentEnd = nextSignatureTick
            End If
        End If

        Dim As ULongInt measureTicks = _
            session_TimeSignatureMeasureTicks(signaturePoint)
        If measureTicks = 0 Then
            Exit While
        End If
        Dim As ULongInt firstMeasure = signaturePoint.tick
        If firstMeasure < segmentStart Then
            Dim As ULongInt elapsedTicks = segmentStart - firstMeasure
            Dim As ULongInt measureNumber = elapsedTicks \ measureTicks
            If elapsedTicks Mod measureTicks <> 0 Then
                measureNumber += 1
            End If
            firstMeasure += measureNumber * measureTicks
        End If

        Dim As ULongInt measureStart = firstMeasure
        While measureStart < segmentEnd
            Dim As ULongInt measureEnd = measureStart + measureTicks
            If measureEnd < measureStart OrElse measureEnd > segmentEnd Then _
                measureEnd = segmentEnd
            If measureEnd <= measureStart Then
                Exit While
            End If

            For trackIndex As Integer = firstTrack To lastTrack
                Dim As Integer staffIndex = trackIndex - firstTrack
                Dim As ULongInt cursorTick = measureStart
                While cursorTick < measureEnd
                    Dim As ULongInt occupiedUntil = cursorTick
                    Dim As ULongInt nextNoteTick = measureEnd
                    Dim As Integer hasOverlap = 0

                    For cacheIndex As Integer = 0 To _
                        session_ScoreVisibleNoteCount - 1
                        Dim As Integer noteIndex = _
                            session_ScoreVisibleNoteIndices(cacheIndex)
                        Dim As MidiEditableNote editableNote
                        If midi_GetEditableNote(noteIndex, editableNote) = 0 Then _
                            Continue For
                        If editableNote.trackIndex <> trackIndex Then
                            Continue For
                        End If
                        Dim As ULongInt noteEnd = editableNote.startTick + _
                            editableNote.durationTicks
                        If noteEnd < editableNote.startTick Then
                            noteEnd = measureEnd
                        End If
                        If editableNote.startTick <= cursorTick AndAlso _
                            noteEnd > cursorTick Then
                            hasOverlap = -1
                            If noteEnd > occupiedUntil Then
                                occupiedUntil = noteEnd
                            End If
                        ElseIf editableNote.startTick > cursorTick AndAlso _
                            editableNote.startTick < nextNoteTick Then
                            nextNoteTick = editableNote.startTick
                        End If
                    Next

                    If hasOverlap <> 0 Then
                        If occupiedUntil > measureEnd Then
                            occupiedUntil = measureEnd
                        End If
                        If occupiedUntil <= cursorTick Then
                            Exit While
                        End If
                        cursorTick = occupiedUntil
                    Else
                        If nextNoteTick > measureEnd Then
                            nextNoteTick = measureEnd
                        End If
                        If nextNoteTick <= cursorTick Then
                            Exit While
                        End If
                        session_DrawRestSpan cursorTick, nextNoteTick, scoreLeft, _
                            scoreRight, firstStaffY, staffIndex, staffGap, _
                            ticksPerView, CULngInt(session_Summary.division), _
                            session_ThemePalette.textColor, drawnRestCount
                        cursorTick = nextNoteTick
                    End If
                    If drawnRestCount >= 1024 Then
                        Exit Sub
                    End If
                Wend
            Next
            If measureTicks > segmentEnd - measureStart Then
                Exit While
            End If
            measureStart += measureTicks
        Wend

        If signatureIndex + 1 >= session_Summary.timeSignatureCount Then
            Exit While
        End If
        Dim As ULongInt nextTick = _
            session_Summary.timeSignatureMap(signatureIndex + 1).tick
        If nextTick > viewEndTick Then
            Exit While
        End If
        If nextTick <= segmentStart Then
            signatureIndex += 1
            Continue While
        End If
        segmentStart = nextTick
        signatureIndex += 1
    Wend
End Sub


Private Sub session_DrawAudioClips( _
    ByVal scoreLeft As Integer, _
    ByVal scoreRight As Integer, _
    ByVal scoreHeight As Integer, _
    ByVal ticksPerView As ULongInt _
)
    If audio_GetCount() <= 0 OrElse ticksPerView = 0 OrElse _
        scoreRight <= scoreLeft Then Exit Sub
    Dim As Integer laneY = SESSION_SCORE_TOP + scoreHeight - 28
    backend_Print scoreLeft, laneY - 13, _
        session_ThemePalette.audioLabelColor, "Audio"
    backend_Line scoreLeft, laneY + 18, scoreRight, laneY + 18, _
        session_ThemePalette.audioGuideColor

    Dim As ULongInt viewEndTick = session_ViewStartTick + ticksPerView
    If viewEndTick < session_ViewStartTick Then _
        viewEndTick = OSE_MAX_MIDI_TICK
    For clipIndex As Integer = 0 To audio_GetCount() - 1
        Dim As OseAudioClip clip
        If audio_GetClip(clipIndex, clip) = 0 Then
            Continue For
        End If
        Dim As Double clipEndSeconds = midi_TicksToSeconds( _
            session_Summary, clip.startTick) + _
            CDbl(clip.durationMilliseconds) / 1000.0
        Dim As ULongInt clipEndTick = midi_SecondsToTicks( _
            session_Summary, clipEndSeconds)
        If clipEndTick <= clip.startTick Then
            clipEndTick = clip.startTick + 1
        End If
        If clip.startTick > viewEndTick OrElse clipEndTick < session_ViewStartTick Then _
            Continue For

        Dim As ULongInt visibleStart = clip.startTick
        Dim As ULongInt visibleEnd = clipEndTick
        If visibleStart < session_ViewStartTick Then
            visibleStart = session_ViewStartTick
        End If
        If visibleEnd > viewEndTick Then
            visibleEnd = viewEndTick
        End If
        If visibleEnd <= visibleStart Then
            Continue For
        End If
        Dim As Integer clipX = scoreLeft + CInt((CDbl(scoreRight - scoreLeft) * _
            CDbl(visibleStart - session_ViewStartTick)) / CDbl(ticksPerView))
        Dim As Integer clipWidth = CInt((CDbl(scoreRight - scoreLeft) * _
            CDbl(visibleEnd - visibleStart)) / CDbl(ticksPerView))
        If clipWidth < 4 Then
            clipWidth = 4
        End If
        backend_Rect clipX, laneY, clipWidth, 16, _
            session_ThemePalette.audioClipColor, 1
        backend_Print clipX + 3, laneY + 3, _
            session_ThemePalette.audioClipTextColor, Str(clipIndex + 1)
    Next
End Sub


Private Sub session_DrawClefOctagon( _
    ByVal octagonLeft As Integer, ByVal octagonTop As Integer, _
    ByVal octagonWidth As Integer, ByVal octagonHeight As Integer, _
    ByVal polygonColor As ULong _
)
    /'
        A regular octagon remains circular at the sizes used for a bass-clef
        head and dots, while keeping every part of the clef in omaGUI's filled
        polygon path.
    '/
    Dim As Integer designX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer designY(1 To GRAPHICSHAPE_MAX_POINTS)

    designX(1) = 29
    designY(1) = 0
    designX(2) = 71
    designY(2) = 0
    designX(3) = 100
    designY(3) = 29
    designX(4) = 100
    designY(4) = 71
    designX(5) = 71
    designY(5) = 100
    designX(6) = 29
    designY(6) = 100
    designX(7) = 0
    designY(7) = 71
    designX(8) = 0
    designY(8) = 29

    session_DrawScaledNotationPolygon octagonLeft, octagonTop, _
        octagonWidth, octagonHeight, _
        100, 100, 8, designX(), designY(), polygonColor
End Sub


Private Sub session_DrawTrebleClef( _
    ByVal clefX As Integer, ByVal staffY As Integer, ByVal clefColor As ULong _
)
    /'
        The treble clef is a set of overlapping closed ribbons. Its 190 by 430
        design grid is roughly ten times the final raster size, so the upper
        loop, G-line spiral, descending spine, and lower hook can be tuned as
        coherent silhouettes instead of disconnected screen-sized strokes.
    '/
    Const DESIGN_WIDTH As Integer = 190
    Const DESIGN_HEIGHT As Integer = 430
    Const TARGET_WIDTH As Integer = 20
    Const TARGET_HEIGHT As Integer = 44

    Dim As Integer originX = clefX - 10
    Dim As Integer originY = staffY - 11
    Dim As Integer designX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer designY(1 To GRAPHICSHAPE_MAX_POINTS)

    ' Left half of the narrow upper loop.
    designX(1) = 100
    designY(1) = 0
    designX(2) = 70
    designY(2) = 10
    designX(3) = 50
    designY(3) = 40
    designX(4) = 40
    designY(4) = 80
    designX(5) = 50
    designY(5) = 120
    designX(6) = 80
    designY(6) = 150
    designX(7) = 100
    designY(7) = 130
    designX(8) = 80
    designY(8) = 110
    designX(9) = 70
    designY(9) = 80
    designX(10) = 70
    designY(10) = 50
    designX(11) = 90
    designY(11) = 20
    designX(12) = 110
    designY(12) = 10
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 12, designX(), designY(), clefColor

    ' Right half closes the loop while preserving its white center.
    designX(1) = 100
    designY(1) = 0
    designX(2) = 120
    designY(2) = 10
    designX(3) = 130
    designY(3) = 30
    designX(4) = 130
    designY(4) = 60
    designX(5) = 120
    designY(5) = 90
    designX(6) = 100
    designY(6) = 120
    designX(7) = 80
    designY(7) = 150
    designX(8) = 70
    designY(8) = 130
    designX(9) = 90
    designY(9) = 100
    designX(10) = 100
    designY(10) = 70
    designX(11) = 110
    designY(11) = 40
    designX(12) = 110
    designY(12) = 20
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 12, designX(), designY(), clefColor

    ' Upper and right side of the spiral around the G line.
    designX(1) = 0
    designY(1) = 220
    designX(2) = 10
    designY(2) = 190
    designX(3) = 30
    designY(3) = 170
    designX(4) = 60
    designY(4) = 150
    designX(5) = 100
    designY(5) = 150
    designX(6) = 140
    designY(6) = 170
    designX(7) = 170
    designY(7) = 200
    designX(8) = 180
    designY(8) = 230
    designX(9) = 150
    designY(9) = 230
    designX(10) = 140
    designY(10) = 210
    designX(11) = 110
    designY(11) = 190
    designX(12) = 70
    designY(12) = 180
    designX(13) = 40
    designY(13) = 190
    designX(14) = 30
    designY(14) = 220
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 14, designX(), designY(), clefColor

    ' Lower left and lower right ribbons complete the open spiral.
    designX(1) = 0
    designY(1) = 210
    designX(2) = 0
    designY(2) = 250
    designX(3) = 20
    designY(3) = 280
    designX(4) = 60
    designY(4) = 300
    designX(5) = 90
    designY(5) = 300
    designX(6) = 90
    designY(6) = 270
    designX(7) = 60
    designY(7) = 270
    designX(8) = 30
    designY(8) = 260
    designX(9) = 20
    designY(9) = 240
    designX(10) = 30
    designY(10) = 220
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 10, designX(), designY(), clefColor

    designX(1) = 50
    designY(1) = 300
    designX(2) = 100
    designY(2) = 310
    designX(3) = 140
    designY(3) = 290
    designX(4) = 170
    designY(4) = 260
    designX(5) = 180
    designY(5) = 220
    designX(6) = 150
    designY(6) = 210
    designX(7) = 150
    designY(7) = 240
    designX(8) = 130
    designY(8) = 270
    designX(9) = 100
    designY(9) = 280
    designX(10) = 60
    designY(10) = 270
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 10, designX(), designY(), clefColor

    ' The diagonal spine crosses the spiral and descends into the tail.
    designX(1) = 100
    designY(1) = 70
    designX(2) = 120
    designY(2) = 80
    designX(3) = 110
    designY(3) = 120
    designX(4) = 90
    designY(4) = 160
    designX(5) = 80
    designY(5) = 200
    designX(6) = 80
    designY(6) = 240
    designX(7) = 100
    designY(7) = 290
    designX(8) = 120
    designY(8) = 340
    designX(9) = 110
    designY(9) = 400
    designX(10) = 90
    designY(10) = 400
    designX(11) = 100
    designY(11) = 350
    designX(12) = 80
    designY(12) = 300
    designX(13) = 60
    designY(13) = 250
    designX(14) = 60
    designY(14) = 210
    designX(15) = 70
    designY(15) = 160
    designX(16) = 90
    designY(16) = 110
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 16, designX(), designY(), clefColor

    ' Bottom hook, kept broad enough to survive the final 20-pixel reduction.
    designX(1) = 105
    designY(1) = 350
    designX(2) = 125
    designY(2) = 365
    designX(3) = 135
    designY(3) = 390
    designX(4) = 120
    designY(4) = 410
    designX(5) = 90
    designY(5) = 430
    designX(6) = 55
    designY(6) = 420
    designX(7) = 30
    designY(7) = 400
    designX(8) = 25
    designY(8) = 380
    designX(9) = 45
    designY(9) = 375
    designX(10) = 45
    designY(10) = 393
    designX(11) = 60
    designY(11) = 405
    designX(12) = 82
    designY(12) = 410
    designX(13) = 103
    designY(13) = 398
    designX(14) = 110
    designY(14) = 385
    designX(15) = 103
    designY(15) = 370
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 15, designX(), designY(), clefColor
End Sub


Private Sub session_DrawBassClef( _
    ByVal clefX As Integer, ByVal staffY As Integer, ByVal clefColor As ULong _
)
    /'
        The bass clef uses a tapered comma silhouette and three octagons. The
        same normalized polygon path is used for its head and dots, avoiding a
        visual mismatch between a vector body and unrelated circle primitives.
    '/
    Const DESIGN_WIDTH As Integer = 190
    Const DESIGN_HEIGHT As Integer = 290
    Const TARGET_WIDTH As Integer = 20
    Const TARGET_HEIGHT As Integer = 30

    Dim As Integer originX = clefX - 10
    Dim As Integer originY = staffY
    Dim As Integer designX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer designY(1 To GRAPHICSHAPE_MAX_POINTS)

    designX(1) = 20
    designY(1) = 60
    designX(2) = 35
    designY(2) = 20
    designX(3) = 65
    designY(3) = 0
    designX(4) = 95
    designY(4) = 10
    designX(5) = 120
    designY(5) = 40
    designX(6) = 140
    designY(6) = 90
    designX(7) = 125
    designY(7) = 150
    designX(8) = 90
    designY(8) = 210
    designX(9) = 20
    designY(9) = 280
    designX(10) = 55
    designY(10) = 240
    designX(11) = 80
    designY(11) = 200
    designX(12) = 100
    designY(12) = 160
    designX(13) = 105
    designY(13) = 110
    designX(14) = 100
    designY(14) = 70
    designX(15) = 75
    designY(15) = 50
    designX(16) = 45
    designY(16) = 70
    session_DrawScaledNotationPolygon originX, originY, TARGET_WIDTH, TARGET_HEIGHT, _
        DESIGN_WIDTH, DESIGN_HEIGHT, 16, designX(), designY(), clefColor

    session_DrawClefOctagon originX, originY + 2, 8, 9, clefColor
    ' The dots occupy the spaces immediately above and below the F line.
    session_DrawClefOctagon originX + 16, originY + 2, 4, 4, clefColor
    session_DrawClefOctagon originX + 16, originY + 9, 4, 4, clefColor
End Sub


Private Sub session_DrawScoreClef( _
    ByVal trackIndex As Integer, ByVal staffY As Integer, _
    ByVal clefColor As ULong _
)
    Dim As Integer clefCenterX = SESSION_SCORE_LEFT + 17

    If session_TrackUsesBassClef(trackIndex) <> 0 Then
        session_DrawBassClef clefCenterX, staffY, clefColor
    Else
        session_DrawTrebleClef clefCenterX, staffY, clefColor
    End If
End Sub


Private Function session_VisualFingerprintMix( _
    ByVal fingerprint As ULongInt, _
    ByVal value As ULongInt _
) As ULongInt
    Return ((fingerprint Shl 7) Or (fingerprint Shr 57)) Xor value Xor _
        &h9e3779b97f4a7c15ull
End Function


Private Function session_VisualFingerprintText( _
    ByVal fingerprint As ULongInt, _
    ByRef textValue As String _
) As ULongInt
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(Len(textValue)))
    For characterIndex As Integer = 0 To Len(textValue) - 1
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, CULngInt(textValue[characterIndex]))
    Next characterIndex
    Return fingerprint
End Function


Private Function session_ScoreStaticFingerprintValue( _
    ByVal firstTrack As Integer, _
    ByVal staffCount As Integer, _
    ByVal keySharpsFlats As Integer, _
    ByVal keyMinor As Integer _
) As UInteger
    Dim As UInteger fingerprint = &h811c9dc5u

    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(firstTrack + 1)
    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(staffCount + 1)
    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(session_ScoreTrackRowHeight)
    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(session_SelectedTrack + 2)
    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(keySharpsFlats + 8)
    fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
        CUInt(keyMinor And &H1)

    ' Meter changes and scrolling across a signature boundary must invalidate
    ' the cached staff gutter as well as the timeline and small header label.
    Dim As Integer signatureIndex = session_TimeSignatureIndexForTick(session_ViewStartTick)
    If signatureIndex >= 0 Then
        fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
            CUInt(session_Summary.timeSignatureMap(signatureIndex).numerator)
        fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
            CUInt(session_Summary.timeSignatureMap(signatureIndex).denominatorPower)
    End If

    For trackIndex As Integer = firstTrack To firstTrack + staffCount - 1
        Dim As String trackName = midi_TrackDisplayName( _
            session_Summary, trackIndex)
        fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
            CUInt(trackIndex + 1)
        fingerprint = ((fingerprint Shl 5) Or (fingerprint Shr 27)) Xor _
            CUInt(session_TrackUsesBassClef(trackIndex) And &H1)
        For characterIndex As Integer = 0 To Len(trackName) - 1
            fingerprint = ((fingerprint Shl 5) Or _
                (fingerprint Shr 27)) Xor CUInt(trackName[characterIndex])
        Next characterIndex
    Next trackIndex

    Return fingerprint
End Function


Private Function session_ScoreVisualFingerprint( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal ticksPerView As ULongInt, _
    ByVal staticFingerprint As UInteger _
) As ULongInt
    Dim As ULongInt fingerprint = &hcbf29ce484222325ull

    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenWidth))
    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenHeight))
    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(session_ThemeMode))
    fingerprint = session_VisualFingerprintMix(fingerprint, session_ViewStartTick)
    fingerprint = session_VisualFingerprintMix(fingerprint, ticksPerView)
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(staticFingerprint))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Dirty And &H1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_ScoreVisibleNoteOverflowed And &H1))
    fingerprint = session_VisualFingerprintText( _
        fingerprint, session_Summary.documentTitle)
    fingerprint = session_VisualFingerprintText( _
        fingerprint, session_ProjectFilename)
    fingerprint = session_VisualFingerprintText( _
        fingerprint, session_Filename)

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_ScoreVisibleNoteCount))
    For cacheIndex As Integer = 0 To session_ScoreVisibleNoteCount - 1
        Dim As Integer noteIndex = session_ScoreVisibleNoteIndices(cacheIndex)
        Dim As MidiEditableNote editableNote
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, CULngInt(noteIndex + 1))
        If midi_GetEditableNote(noteIndex, editableNote) <> 0 Then
            fingerprint = session_VisualFingerprintMix( _
                fingerprint, editableNote.startTick)
            fingerprint = session_VisualFingerprintMix( _
                fingerprint, editableNote.durationTicks)
            fingerprint = session_VisualFingerprintMix(fingerprint, _
                CULngInt(editableNote.keyNumber) Or _
                (CULngInt(editableNote.channel) Shl 8) Or _
                (CULngInt(editableNote.velocity) Shl 16) Or _
                (CULngInt(editableNote.trackIndex + 1) Shl 24))
        End If
    Next cacheIndex

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_NoteSelection.count))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_NoteSelection.primaryNoteIndex + 1))
    For selectionIndex As Integer = 0 To session_NoteSelection.count - 1
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(session_NoteSelection.noteIndices(selectionIndex) + 1))
    Next selectionIndex

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_ScoreMarqueeActive And &H1))
    If session_ScoreMarqueeActive <> 0 Then
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(session_ScoreMarqueeStartX)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(session_ScoreMarqueeStartY)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(session_ScoreMarqueeCurrentX)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(session_ScoreMarqueeCurrentY)))
    End If

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Summary.timeSignatureCount))
    For signatureIndex As Integer = 0 To _
        session_Summary.timeSignatureCount - 1
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, session_Summary.timeSignatureMap(signatureIndex).tick)
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(session_Summary.timeSignatureMap(signatureIndex).numerator) Or _
            (CULngInt(session_Summary.timeSignatureMap( _
            signatureIndex).denominatorPower) Shl 8))
    Next signatureIndex
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Summary.keySignatureCount))
    For keyIndex As Integer = 0 To session_Summary.keySignatureCount - 1
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, session_Summary.keySignatureMap(keyIndex).tick)
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(session_Summary.keySignatureMap( _
            keyIndex).sharpsFlats)) Or _
            (CULngInt(session_Summary.keySignatureMap(keyIndex).minor) Shl 32))
    Next keyIndex

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(audio_GetCount()))
    For clipIndex As Integer = 0 To audio_GetCount() - 1
        Dim As OseAudioClip clip
        If audio_GetClip(clipIndex, clip) <> 0 Then
            fingerprint = session_VisualFingerprintMix(fingerprint, clip.startTick)
            fingerprint = session_VisualFingerprintMix( _
                fingerprint, clip.durationMilliseconds)
            fingerprint = session_VisualFingerprintMix( _
                fingerprint, CULngInt(clip.gainPermille))
        End If
    Next clipIndex

    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Playing And &H1))
    If session_Playing <> 0 Then
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            midi_SecondsToTicks(session_Summary, session_PlaybackElapsed))
    End If
    Return fingerprint
End Function


Private Sub session_DrawScoreRuler( _
    ByVal ticksPerView As ULongInt, _
    ByVal noteScoreLeft As Integer, _
    ByVal noteScoreRight As Integer _
)
    ' Draw absolute grid positions so changing snap or scrolling between beats
    ' cannot stretch ruler marks away from the notes they describe. Thin dense
    ' grids before drawing, while retaining their actual time coordinates.
    Dim As ULongInt rulerStepTicks = session_ScoreSnapTicks()
    While ticksPerView \ rulerStepTicks > 256
        rulerStepTicks *= 2
    Wend
    Dim As ULongInt firstRulerTick = _
        ((session_ViewStartTick + rulerStepTicks - 1) \ rulerStepTicks) * rulerStepTicks
    Dim As Integer rulerDivisionCount = CInt(ticksPerView \ rulerStepTicks)
    For rulerDivision As Integer = 0 To rulerDivisionCount
        Dim As ULongInt rulerTick = firstRulerTick + _
            CULngInt(rulerDivision) * rulerStepTicks
        If rulerTick > session_ViewStartTick + ticksPerView Then
            Exit For
        End If
        Dim As Integer rulerX = noteScoreLeft + _
            CInt(CDbl(noteScoreRight - noteScoreLeft) * _
            CDbl(rulerTick - session_ViewStartTick) / CDbl(ticksPerView))
        Dim As Integer rulerTickHeight = 4
        If session_Summary.division > 0 AndAlso _
            rulerTick Mod CULngInt(session_Summary.division) = 0 Then _
            rulerTickHeight = 7
        If session_ScoreIsMeasureStart(rulerTick) <> 0 Then _
            rulerTickHeight = 10
        backend_Line rulerX, SESSION_SCORE_TOP + 24, rulerX, _
            SESSION_SCORE_TOP + 24 + rulerTickHeight, _
            session_ThemePalette.dividerColor
        If rulerDivision < rulerDivisionCount Then
            If session_ScoreIsMeasureStart(rulerTick) <> 0 Then
                Dim As ULongInt measureNumber = _
                    session_ScoreMeasureNumber(rulerTick)
                backend_Print rulerX + 3, SESSION_SCORE_TOP + 34, _
                    session_ThemePalette.textColor, Str(measureNumber)
            End If
        End If
    Next

End Sub


' Score drawing branches by notation feature but owns no input or mutation.
' fblint: disable-next-line FBL111 REASON: Score rendering branches by notation feature without mutating document state.
Private Sub session_DrawScore(ByVal screenWidth As Integer, ByVal screenHeight As Integer)
    Dim As Integer scoreWidth = screenWidth - SESSION_SCORE_LEFT - 4
    Dim As Integer scoreHeight = screenHeight - SESSION_TOP_HEIGHT - SESSION_MIXER_HEIGHT - 8
    If scoreWidth < 160 Then
        scoreWidth = 160
    End If
    If scoreHeight < 150 Then
        scoreHeight = 150
    End If

    Dim As Double scoreSectionClock
    If session_SmoothnessProfilingActive <> 0 Then
        scoreSectionClock = Timer
    End If
    session_PrepareScoreNoteCache(screenHeight)
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreCacheMs = uiFramePacing_ElapsedMilliseconds( _
            scoreSectionClock, Timer)
        scoreSectionClock = Timer
    End If

    Dim As Integer firstStaffY = SESSION_SCORE_TOP + _
        scoreLayout_FirstStaffOffset(session_ScoreTrackRowHeight)
    Dim As Integer staffGap = session_ScoreTrackRowHeight
    Dim As Integer lineSpacing = scoreLayout_LineSpacing( _
        session_ScoreTrackRowHeight)
    Dim As Integer rowTopOffset = scoreLayout_RowTopOffset( _
        session_ScoreTrackRowHeight)
    Dim As Integer firstTrack = session_ScoreFirstTrackIndex(screenHeight)
    Dim As Integer staffCount = session_ScoreVisibleTrackCount(screenHeight)

    Dim As Integer scoreLeft = SESSION_SCORE_LEFT + 28
    Dim As Integer scoreRight = SESSION_SCORE_LEFT + scoreWidth - 14
    Dim As Integer noteScoreLeft = SESSION_SCORE_LEFT + SESSION_SCORE_NOTE_LEFT
    Dim As Integer noteScoreRight = SESSION_SCORE_LEFT + scoreWidth - _
        SESSION_SCORE_NOTE_RIGHT
    If noteScoreRight <= noteScoreLeft Then
        Exit Sub
    End If
    If session_Summary.division <= 0 Then
        Exit Sub
    End If

    Dim As Integer activeSignatureIndex = _
        session_TimeSignatureIndexForTick(session_ViewStartTick)
    If activeSignatureIndex < 0 Then
        activeSignatureIndex = 0
    End If
    Dim As MidiTimeSignaturePoint activeSignature
    activeSignature.numerator = 4
    activeSignature.denominatorPower = 2
    If activeSignatureIndex < session_Summary.timeSignatureCount Then
        activeSignature = session_Summary.timeSignatureMap(activeSignatureIndex)
    End If
    Dim As MidiKeySignaturePoint activeKeySignature
    activeKeySignature.sharpsFlats = 0
    activeKeySignature.minor = 0
    Dim As Integer activeKeyIndex = session_KeySignatureIndexForTick( _
        session_ViewStartTick)
    If activeKeyIndex >= 0 AndAlso _
        activeKeyIndex < session_Summary.keySignatureCount Then
        activeKeySignature = session_Summary.keySignatureMap(activeKeyIndex)
    End If
    Dim As ULongInt ticksPerView = session_ViewTicks()

    Dim As Integer workPage = backend_GetWorkPage()
    If workPage < 0 OrElse workPage > 1 Then
        workPage = 0
    End If
    Dim As UInteger staticFingerprint = _
        session_ScoreStaticFingerprintValue(firstTrack, staffCount, _
        activeKeySignature.sharpsFlats, activeKeySignature.minor)
    Dim As ULongInt visualFingerprint = session_ScoreVisualFingerprint( _
        screenWidth, screenHeight, ticksPerView, staticFingerprint)
    If session_ScorePageValid(workPage) <> 0 AndAlso _
        session_ScorePageFingerprint(workPage) = visualFingerprint Then
        session_SmoothnessScoreBaseMs = 0.0
        session_SmoothnessScoreRestsMs = 0.0
        session_SmoothnessScoreNotesMs = 0.0
        Exit Sub
    End If
    Dim As Integer redrawScoreStatic = _
        session_ScoreStaticPageWidth(workPage) <> screenWidth OrElse _
        session_ScoreStaticPageHeight(workPage) <> screenHeight OrElse _
        session_ScoreStaticPageTheme(workPage) <> session_ThemeMode OrElse _
        session_ScoreStaticPageFingerprint(workPage) <> staticFingerprint
    Dim As Integer dynamicScoreLeft = noteScoreLeft - 16
    If dynamicScoreLeft < SESSION_SCORE_LEFT + 1 Then _
        dynamicScoreLeft = SESSION_SCORE_LEFT + 1

    If redrawScoreStatic <> 0 Then
        backend_Rect SESSION_SCORE_LEFT, SESSION_SCORE_TOP, scoreWidth, _
            scoreHeight, session_ThemePalette.scorePaperColor, 1
        backend_Rect SESSION_SCORE_LEFT, SESSION_SCORE_TOP, scoreWidth, _
            scoreHeight, session_ThemePalette.borderColor, 0
        session_ScoreHeaderPageValid(workPage) = 0
    Else
        ' Clear only the changing timeline. The page-local labels and clefs to
        ' its left remain valid and avoid rebuilding identical glyphs.
        backend_Rect dynamicScoreLeft, SESSION_SCORE_TOP + 24, _
            SESSION_SCORE_LEFT + scoreWidth - 1 - dynamicScoreLeft, _
            scoreHeight - 25, session_ThemePalette.scorePaperColor, 1
    End If

    Dim As ULongInt headerFingerprint = &h27d4eb2full
    headerFingerprint = session_VisualFingerprintMix( _
        headerFingerprint, CULngInt(screenWidth))
    headerFingerprint = session_VisualFingerprintMix( _
        headerFingerprint, CULngInt(session_ThemeMode))
    headerFingerprint = session_VisualFingerprintMix(headerFingerprint, _
        CULngInt(activeSignature.numerator) Or _
        (CULngInt(activeSignature.denominatorPower) Shl 8))
    headerFingerprint = session_VisualFingerprintMix(headerFingerprint, _
        CULngInt(CUInt(activeKeySignature.sharpsFlats)) Or _
        (CULngInt(activeKeySignature.minor) Shl 32))
    headerFingerprint = session_VisualFingerprintMix( _
        headerFingerprint, CULngInt(session_Dirty And &H1))
    headerFingerprint = session_VisualFingerprintMix(headerFingerprint, _
        CULngInt(session_ScoreVisibleNoteOverflowed And &H1))
    headerFingerprint = session_VisualFingerprintText( _
        headerFingerprint, session_Summary.documentTitle)
    headerFingerprint = session_VisualFingerprintText( _
        headerFingerprint, session_ProjectFilename)
    headerFingerprint = session_VisualFingerprintText( _
        headerFingerprint, session_Filename)
    If session_ScoreHeaderPageValid(workPage) = 0 OrElse _
        session_ScoreHeaderPageFingerprint(workPage) <> headerFingerprint Then
        ' The title can change after a save or edit without invalidating the body.
        backend_Rect SESSION_SCORE_LEFT + 1, SESSION_SCORE_TOP + 1, _
            scoreWidth - 2, 22, session_ThemePalette.headerColor, 1
        backend_Line SESSION_SCORE_LEFT + 1, SESSION_SCORE_TOP + 23, _
            SESSION_SCORE_LEFT + scoreWidth - 2, SESSION_SCORE_TOP + 23, _
            session_ThemePalette.dividerColor
        Dim As String scoreTitle = session_Summary.documentTitle
        If scoreTitle = "" Then _
            scoreTitle = session_LeafFilename(session_ProjectFilename)
        If scoreTitle = "" Then
            scoreTitle = session_LeafFilename(session_Filename)
        End If
        If scoreTitle = "" Then
            scoreTitle = "Untitled"
        End If
        If session_Dirty <> 0 Then
            scoreTitle += " *"
        End If
        If session_ScoreVisibleNoteOverflowed <> 0 Then _
            scoreTitle += " [dense view clipped]"
        Dim As Integer scoreTitleCharacters = (scoreWidth - 280) \ 8
        If scoreTitleCharacters < 12 Then
            scoreTitleCharacters = 12
        End If
        scoreTitle = session_ClipText(scoreTitle, scoreTitleCharacters)
        backend_PrintAligned SESSION_SCORE_LEFT + 4, SESSION_SCORE_TOP + 5, _
            scoreWidth - 8, 14, session_ThemePalette.textColor, _
            "Score View - " + scoreTitle, _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP

        backend_Print SESSION_SCORE_LEFT + 8, SESSION_SCORE_TOP + 6, _
            session_ThemePalette.mutedTextColor, "Grid " + session_SnapName()

        backend_Print SESSION_SCORE_LEFT + scoreWidth - 70, _
            SESSION_SCORE_TOP + 6, session_ThemePalette.textColor, _
            Str(activeSignature.numerator) + "/" + _
            Str(session_TempoDenominatorValue(activeSignature.denominatorPower))
        backend_Print SESSION_SCORE_LEFT + scoreWidth - 150, _
            SESSION_SCORE_TOP + 6, session_ThemePalette.textColor, _
            "Key " + session_KeySignatureText(activeKeySignature.sharpsFlats, _
            activeKeySignature.minor)
        session_ScoreHeaderPageFingerprint(workPage) = headerFingerprint
        session_ScoreHeaderPageValid(workPage) = -1
    End If

    ' Alternating rows keep dense arrangements readable. The selected row uses
    ' the same accent family as its mixer strip so the two views stay related.
    Dim As Integer rowLeft = IIf( _
        redrawScoreStatic <> 0, SESSION_SCORE_LEFT + 1, dynamicScoreLeft)
    Dim As Integer rowWidth = SESSION_SCORE_LEFT + scoreWidth - 1 - rowLeft
    For rowTrackIndex As Integer = firstTrack To firstTrack + staffCount - 1
        Dim As Integer rowIndex = rowTrackIndex - firstTrack
        Dim As Integer rowY = firstStaffY + rowIndex * staffGap
        Dim As ULong rowColor = session_ThemePalette.scorePaperColor
        If (rowIndex And 1) <> 0 Then _
            rowColor = session_ThemePalette.scoreAlternateColor
        If rowTrackIndex = session_SelectedTrack Then _
            rowColor = session_ThemePalette.scoreSelectedColor
        backend_Rect rowLeft, rowY - rowTopOffset, rowWidth, _
            staffGap - 2, rowColor, 1
        If redrawScoreStatic <> 0 AndAlso _
            rowTrackIndex = session_SelectedTrack Then
            backend_Rect SESSION_SCORE_LEFT + 1, rowY - rowTopOffset, 3, _
                staffGap - 2, session_ThemePalette.accentColor, 1
        End If
    Next

    ' Each time-signature segment owns its own beat and measure alignment.
    session_DrawScoreMeterGuides noteScoreLeft, noteScoreRight, firstStaffY, _
        staffGap, staffCount, ticksPerView

    Dim As Integer staffLineLeft = IIf( _
        redrawScoreStatic <> 0, scoreLeft, dynamicScoreLeft)
    For trackIndex As Integer = firstTrack To firstTrack + staffCount - 1
        Dim As Integer staffIndex = trackIndex - firstTrack
        Dim As Integer staffY = firstStaffY + staffIndex * staffGap
        For lineIndex As Integer = 0 To 4
            backend_Line staffLineLeft, staffY + lineIndex * lineSpacing, _
                scoreRight, staffY + lineIndex * lineSpacing, _
                session_ThemePalette.dividerColor
        Next
        If redrawScoreStatic <> 0 Then
            Dim As String trackLabel = Str(trackIndex + 1) + " " + _
                midi_TrackDisplayName(session_Summary, trackIndex)
            If Len(trackLabel) > SESSION_SCORE_TRACK_LABEL_CHARACTERS Then _
                trackLabel = Left(trackLabel, SESSION_SCORE_TRACK_LABEL_CHARACTERS)
            Dim As ULong trackLabelColor = session_ThemePalette.textColor
            If trackIndex = session_SelectedTrack Then _
                trackLabelColor = session_ThemePalette.accentBrightColor
            backend_Print SESSION_SCORE_LEFT + 5, _
                staffY - rowTopOffset + 3, _
                trackLabelColor, trackLabel
            session_DrawScoreClef trackIndex, staffY, _
                session_ThemePalette.textColor
            session_DrawStaffTimeSignature staffY, activeSignature.numerator, _
                session_TempoDenominatorValue(activeSignature.denominatorPower)
        End If
    Next

    ' The clef and key signature occupy a fixed gutter before the editable timeline.
    If redrawScoreStatic <> 0 Then
        session_DrawKeySignature scoreLeft, firstStaffY, staffGap, staffCount, _
            firstTrack, activeKeySignature.sharpsFlats
        session_ScoreStaticPageWidth(workPage) = screenWidth
        session_ScoreStaticPageHeight(workPage) = screenHeight
        session_ScoreStaticPageTheme(workPage) = session_ThemeMode
        session_ScoreStaticPageFingerprint(workPage) = staticFingerprint
    End If

    session_DrawScoreRuler ticksPerView, noteScoreLeft, noteScoreRight

    If session_Playing <> 0 Then
        Dim As ULongInt playheadTick = midi_SecondsToTicks( _
            session_Summary, session_PlaybackElapsed)
        If playheadTick >= session_ViewStartTick AndAlso _
            playheadTick <= session_ViewStartTick + ticksPerView Then
            Dim As ULongInt viewTick = playheadTick - session_ViewStartTick
            Dim As Integer playheadX = noteScoreLeft + _
                CInt((CDbl(noteScoreRight - noteScoreLeft) * CDbl(viewTick)) / _
                CDbl(ticksPerView))
            backend_Line playheadX, SESSION_SCORE_TOP + 25, playheadX, _
                SESSION_SCORE_TOP + scoreHeight - 8, _
                session_ThemePalette.scorePlayheadColor
        End If
    End If

    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreBaseMs = uiFramePacing_ElapsedMilliseconds( _
            scoreSectionClock, Timer)
        scoreSectionClock = Timer
    End If
    session_DrawScoreRests noteScoreLeft, noteScoreRight, screenHeight, _
        firstStaffY, staffGap, ticksPerView
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreRestsMs = uiFramePacing_ElapsedMilliseconds( _
            scoreSectionClock, Timer)
        scoreSectionClock = Timer
    End If
    session_DrawScoreNotes screenWidth, screenHeight, _
        CULngInt(session_Summary.division), activeKeySignature.sharpsFlats
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreNotesMs = uiFramePacing_ElapsedMilliseconds( _
            scoreSectionClock, Timer)
    End If
    session_DrawAudioClips noteScoreLeft, noteScoreRight, scoreHeight, ticksPerView
    session_DrawScoreMarquee()
    session_ScorePageFingerprint(workPage) = visualFingerprint
    session_ScorePageValid(workPage) = -1
End Sub


Private Sub session_DrawMixerMeter( _
    ByVal meterLeft As Integer, _
    ByVal meterTop As Integer, _
    ByVal meterWidth As Integer, _
    ByVal meterHeight As Integer, _
    ByVal level As Single _
)
    If level < 0.0 Then
        level = 0.0
    End If
    If level > 1.0 Then
        level = 1.0
    End If

    Const segmentCount As Integer = 12
    Dim As Integer segmentHeight = (meterHeight - segmentCount + 1) \ segmentCount
    If segmentHeight < 2 Then
        segmentHeight = 2
    End If
    Dim As Integer activeSegments = CInt(level * segmentCount)
    backend_Rect meterLeft, meterTop, meterWidth, meterHeight, _
        session_ThemePalette.meterWellColor, 1

    For segmentIndex As Integer = 0 To segmentCount - 1
        Dim As Integer segmentY = meterTop + meterHeight - 2 - _
            (segmentIndex + 1) * segmentHeight - segmentIndex
        Dim As ULong segmentColor = session_ThemePalette.meterIdleGreenColor
        If segmentIndex >= 9 Then
            segmentColor = session_ThemePalette.meterIdleRedColor
        ElseIf segmentIndex >= 7 Then
            segmentColor = session_ThemePalette.meterIdleYellowColor
        End If
        If segmentIndex < activeSegments Then
            If segmentIndex >= 9 Then
                segmentColor = session_ThemePalette.meterActiveRedColor
            ElseIf segmentIndex >= 7 Then
                segmentColor = session_ThemePalette.meterActiveYellowColor
            Else
                segmentColor = session_ThemePalette.meterActiveGreenColor
            End If
        End If
        backend_Rect meterLeft + 1, segmentY, meterWidth - 2, _
            segmentHeight, segmentColor, 1
    Next
End Sub


Private Sub session_DrawMixerKnob( _
    ByVal centerX As Integer, _
    ByVal centerY As Integer, _
    ByVal normalizedValue As Single _
)
    If normalizedValue < 0.0 Then
        normalizedValue = 0.0
    End If
    If normalizedValue > 1.0 Then
        normalizedValue = 1.0
    End If
    backend_Circle centerX + 1, centerY + 1, 7, _
        session_ThemePalette.knobOuterColor, 1
    backend_Circle centerX, centerY, 7, _
        session_ThemePalette.knobFaceColor, 1
    backend_Circle centerX, centerY, 7, _
        session_ThemePalette.knobBorderColor, 0
    backend_Circle centerX, centerY, 4, _
        session_ThemePalette.knobInsetColor, 1

    ' The pointer sweeps through 270 degrees, matching small hardware knobs.
    Dim As Double pointerAngle = -2.35 + CDbl(normalizedValue) * 4.70
    Dim As Integer pointerX = centerX + CInt(Sin(pointerAngle) * 5.0)
    Dim As Integer pointerY = centerY - CInt(Cos(pointerAngle) * 5.0)
    backend_Line centerX, centerY, pointerX, pointerY, _
        session_ThemePalette.accentBrightColor
    backend_Circle pointerX, pointerY, 1, _
        session_ThemePalette.highlightColor, 1
End Sub


Private Sub session_DrawMixerPageButton( _
    ByVal buttonLeft As Integer, _
    ByVal buttonTop As Integer, _
    ByVal buttonWidth As Integer, _
    ByVal buttonHeight As Integer, _
    ByVal direction As Integer, _
    ByVal enabledState As Integer _
)
    Dim As ULong faceColor = session_ThemePalette.panelColor
    Dim As ULong borderColor = session_ThemePalette.borderColor
    Dim As ULong iconColor = session_ThemePalette.accentBrightColor
    If enabledState = 0 Then
        faceColor = session_ThemePalette.alternatePanelColor
        borderColor = session_ThemePalette.shadowColor
        iconColor = session_ThemePalette.faintTextColor
    End If

    backend_Rect buttonLeft, buttonTop, buttonWidth, buttonHeight, faceColor, 1
    backend_Rect buttonLeft, buttonTop, buttonWidth, buttonHeight, borderColor, 0
    Dim As Integer centerX = buttonLeft + buttonWidth \ 2
    Dim As Integer centerY = buttonTop + buttonHeight \ 2
    backend_Line centerX - direction * 3, centerY - 4, _
        centerX + direction * 2, centerY, iconColor
    backend_Line centerX + direction * 2, centerY, _
        centerX - direction * 3, centerY + 4, iconColor
End Sub


Private Function session_MixerVisualFingerprint( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer, _
    ByVal includeMeterLevels As Integer _
) As ULongInt
    Dim As ULongInt fingerprint = &h84222325cbf29ce4ull

    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenWidth))
    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenHeight))
    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(session_ThemeMode))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_SelectedTrack + 1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_MixerPageAnchor + 1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Summary.trackCount))
    fingerprint = session_VisualFingerprintText(fingerprint, session_Filename)

    For channelIndex As Integer = 0 To SESSION_CHANNEL_COUNT - 1
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(session_ChannelVolume(channelIndex) * 100000.0)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CUInt(CInt((session_ChannelPan(channelIndex) + 1.0) * _
            100000.0))))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(session_ChannelChorus(channelIndex) * 100000.0)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(session_ChannelReverb(channelIndex) * 100000.0)))
        If includeMeterLevels <> 0 Then
            fingerprint = session_VisualFingerprintMix(fingerprint, _
                CULngInt(CInt(mixerMeter_ChannelLevel( _
                session_MixerMeter, channelIndex) * 100000.0)))
        End If
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(session_Summary.channelProgram(channelIndex)) Or _
            (CULngInt(session_MixerChannels.mute(channelIndex) And 1) Shl 8) Or _
            (CULngInt(session_MixerChannels.solo(channelIndex) And 1) Shl 9) Or _
            (CULngInt(session_MixerChannels.record(channelIndex) And &H1) Shl 10))
        If channelIndex < session_Summary.trackCount Then
            Dim As String trackName = midi_TrackDisplayName( _
                session_Summary, channelIndex)
            fingerprint = session_VisualFingerprintText(fingerprint, trackName)
        End If
    Next channelIndex

    If includeMeterLevels <> 0 Then
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(session_MasterVolume * 100000.0)))
    End If
    fingerprint = session_VisualFingerprintMix(fingerprint, _
        CULngInt(CInt(session_MasterEchoWet * 100000.0)))
    fingerprint = session_VisualFingerprintMix(fingerprint, _
        CULngInt(CInt(session_MasterEchoFeedback * 100000.0)))
    If includeMeterLevels <> 0 Then
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(mixerMeter_MasterLeftLevel( _
            session_MixerMeter) * 100000.0)))
        fingerprint = session_VisualFingerprintMix(fingerprint, _
            CULngInt(CInt(mixerMeter_MasterRightLevel( _
            session_MixerMeter) * 100000.0)))
    End If
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(midiInput_IsOpen() And &H1))
    Return fingerprint
End Function


Private Sub session_DrawMixerMasterBlock( _
    ByRef mixerLayout As OseMixerControlLayout, _
    ByVal screenHeight As Integer _
)
    Dim As Integer mixerTop = mixerLayout.mixerTop
    Dim As Integer masterLeft = mixerLayout.masterLeft
    Dim As Integer faderTop = mixerLayout.faderTop
    Dim As Integer faderBottom = mixerLayout.faderBottom

    ' The master block owns its background so a live fader update erases the
    ' previous handle without forcing all sixteen channel strips to redraw.
    backend_Rect masterLeft, mixerTop + SESSION_MIXER_TITLE_HEIGHT, _
        SESSION_MIXER_MASTER_WIDTH - 4, SESSION_MIXER_HEIGHT - _
        SESSION_MIXER_TITLE_HEIGHT - 3, session_ThemePalette.panelColor, 1
    backend_Rect masterLeft, mixerTop + SESSION_MIXER_TITLE_HEIGHT, _
        SESSION_MIXER_MASTER_WIDTH - 4, SESSION_MIXER_HEIGHT - _
        SESSION_MIXER_TITLE_HEIGHT - 3, session_ThemePalette.borderColor, 0
    backend_PrintAligned masterLeft + 2, mixerTop + 31, _
        SESSION_MIXER_MASTER_WIDTH - 8, 14, session_ThemePalette.textColor, _
        "MASTER", _
        BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP

    Dim As Integer masterFaderX = masterLeft + 31
    Dim As Integer masterFaderY = faderBottom - CInt( _
        session_MasterVolume * CSng(faderBottom - faderTop))
    backend_Line masterFaderX - 1, faderTop, masterFaderX - 1, faderBottom, _
        session_ThemePalette.faderRailShadowColor
    backend_Line masterFaderX, faderTop, masterFaderX, faderBottom, _
        session_ThemePalette.faderRailColor
    backend_Rect masterFaderX - 11, masterFaderY - 5, 22, 10, _
        session_ThemePalette.faderHandleSelectedColor, 1
    backend_Rect masterFaderX - 11, masterFaderY - 5, 22, 10, _
        session_ThemePalette.faderHandleOutlineColor, 0
    backend_Line masterFaderX - 9, masterFaderY, masterFaderX + 9, _
        masterFaderY, session_ThemePalette.faderHandleLineColor

    session_DrawMixerMeter masterLeft + 63, faderTop, 11, _
        faderBottom - faderTop + 1, _
        mixerMeter_MasterLeftLevel(session_MixerMeter)
    session_DrawMixerMeter masterLeft + 80, faderTop, 11, _
        faderBottom - faderTop + 1, _
        mixerMeter_MasterRightLevel(session_MixerMeter)

    If masterEffect_IsAvailable() <> 0 Then
        session_DrawMixerKnob masterLeft + 116, faderTop + 31, _
            session_MasterEchoWet
        session_DrawMixerKnob masterLeft + 141, faderTop + 31, _
            session_MasterEchoFeedback
        backend_Print masterLeft + 104, faderTop + 42, _
            session_ThemePalette.mutedTextColor, "Wet"
        backend_Print masterLeft + 130, faderTop + 42, _
            session_ThemePalette.mutedTextColor, "Fbk"
    Else
        backend_PrintAligned masterLeft + 101, faderTop + 25, 52, 28, _
            session_ThemePalette.mutedTextColor, "Echo N/A", _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_MIDDLE
    End If
    backend_Print masterLeft + 10, screenHeight - 29, _
        session_ThemePalette.mutedTextColor, "MIDI IN"
    backend_Rect masterLeft + 83, screenHeight - 28, 16, 10, _
        session_ThemePalette.borderColor, 0
    backend_Rect masterLeft + 87, screenHeight - 25, 8, 4, _
        Iif(midiInput_IsOpen() <> 0, session_ThemePalette.activityOnColor, _
        session_ThemePalette.activityOffColor), 1
End Sub


Private Sub session_DrawMixer(ByVal screenWidth As Integer, ByVal screenHeight As Integer)
    Dim As OseMixerControlLayout mixerLayout
    Dim As Integer mixerLayoutAnchor = session_SelectedTrack
    If session_MixerPageAnchor >= 0 Then _
        mixerLayoutAnchor = session_MixerPageAnchor
    mixerControls_CalculateLayoutForInteraction mixerLayout, screenWidth, _
        screenHeight, mixerLayoutAnchor, session_InteractionMode
    Dim As Integer mixerTop = mixerLayout.mixerTop
    Dim As Integer mixerLeft = mixerLayout.mixerLeft
    Dim As Integer masterLeft = mixerLayout.masterLeft
    Dim As Integer visibleCount = mixerLayout.visibleCount
    Dim As Integer firstChannel = mixerLayout.firstChannel

    Dim As Integer workPage = backend_GetWorkPage()
    If workPage < 0 OrElse workPage > 1 Then
        workPage = 0
    End If
    Dim As ULongInt staticFingerprint = session_MixerVisualFingerprint( _
        screenWidth, screenHeight, 0)
    Dim As ULongInt visualFingerprint = session_MixerVisualFingerprint( _
        screenWidth, screenHeight, -1)
    If session_MixerPageValid(workPage) <> 0 AndAlso _
        session_MixerPageFingerprint(workPage) = visualFingerprint Then Exit Sub
    If session_MixerPageValid(workPage) <> 0 AndAlso _
        session_MixerStaticPageFingerprint(workPage) = staticFingerprint Then
        For visibleIndex As Integer = 0 To visibleCount - 1
            Dim As Integer channelIndex = firstChannel + visibleIndex
            Dim As Integer stripRight = _
                mixerControls_StripRight(mixerLayout, visibleIndex)
            Const meterWidth As Integer = 9
            session_DrawMixerMeter stripRight - meterWidth - 4, _
                mixerLayout.faderTop, meterWidth, _
                mixerLayout.faderBottom - mixerLayout.faderTop + 1, _
                mixerMeter_ChannelLevel(session_MixerMeter, channelIndex)
        Next visibleIndex
        If Abs(session_MixerPageMasterVolume(workPage) - _
            session_MasterVolume) > 0.000001 Then
            session_DrawMixerMasterBlock mixerLayout, screenHeight
        Else
            session_DrawMixerMeter masterLeft + 63, mixerLayout.faderTop, 11, _
                mixerLayout.faderBottom - mixerLayout.faderTop + 1, _
                mixerMeter_MasterLeftLevel(session_MixerMeter)
            session_DrawMixerMeter masterLeft + 80, mixerLayout.faderTop, 11, _
                mixerLayout.faderBottom - mixerLayout.faderTop + 1, _
                mixerMeter_MasterRightLevel(session_MixerMeter)
        End If
        session_MixerPageMasterVolume(workPage) = session_MasterVolume
        session_MixerPageFingerprint(workPage) = visualFingerprint
        Exit Sub
    End If

    backend_Rect 0, mixerTop, screenWidth, SESSION_MIXER_HEIGHT, _
        session_ThemePalette.windowColor, 1
    backend_Line 0, mixerTop, screenWidth - 1, mixerTop, _
        session_ThemePalette.dividerColor
    backend_Line 0, mixerTop + 1, screenWidth - 1, mixerTop + 1, _
        session_ThemePalette.shadowColor
    backend_Rect mixerLeft, mixerTop + 3, screenWidth - mixerLeft * 2, _
        SESSION_MIXER_TITLE_HEIGHT - 4, session_ThemePalette.headerColor, 1
    backend_Line mixerLeft, mixerTop + SESSION_MIXER_TITLE_HEIGHT - 1, _
        screenWidth - 5, mixerTop + SESSION_MIXER_TITLE_HEIGHT - 1, _
        session_ThemePalette.dividerColor

    Dim As String mixerTitle = "Mixer View"
    If session_Filename <> "" Then _
        mixerTitle += " - " + session_LeafFilename(session_Filename)
    backend_PrintAligned 6, mixerTop + 5, screenWidth - 12, 15, _
        session_ThemePalette.textColor, mixerTitle, BACKEND_FONT_DEFAULT, _
        BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP

    If visibleCount < SESSION_CHANNEL_COUNT Then
        Dim As Integer maximumFirst = SESSION_CHANNEL_COUNT - visibleCount
        session_DrawMixerPageButton mixerLayout.pagePreviousLeft, _
            mixerLayout.pageButtonTop, mixerLayout.pageButtonWidth, _
            mixerLayout.pageButtonHeight, -1, IIf(firstChannel > 0, -1, 0)
        session_DrawMixerPageButton mixerLayout.pageNextLeft, _
            mixerLayout.pageButtonTop, mixerLayout.pageButtonWidth, _
            mixerLayout.pageButtonHeight, 1, _
            IIf(firstChannel < maximumFirst, -1, 0)
        backend_Print mixerLayout.pageNextLeft + _
            mixerLayout.pageButtonWidth + 7, mixerTop + 8, _
            session_ThemePalette.mutedTextColor, _
            "Channels " + Str(firstChannel + 1) + _
            "-" + Str(firstChannel + visibleCount) + " of " + _
            Str(SESSION_CHANNEL_COUNT)
    End If

    Dim As Integer faderTop = mixerLayout.faderTop
    Dim As Integer faderBottom = mixerLayout.faderBottom
    Dim As Integer knobY = mixerLayout.knobCenterY
    Dim As Integer nameBoxTop = mixerLayout.nameBoxTop
    Dim As Integer buttonTop = mixerLayout.buttonTop

    For visibleIndex As Integer = 0 To visibleCount - 1
        Dim As Integer channelIndex = firstChannel + visibleIndex
        Dim As Integer stripLeft = _
            mixerControls_StripLeft(mixerLayout, visibleIndex)
        Dim As Integer stripRight = _
            mixerControls_StripRight(mixerLayout, visibleIndex)
        Dim As ULong stripColor = session_ThemePalette.panelColor
        Dim As ULong channelTextColor = session_ThemePalette.textColor
        If channelIndex >= session_Summary.trackCount Then
            stripColor = session_ThemePalette.alternatePanelColor
            channelTextColor = session_ThemePalette.faintTextColor
        ElseIf channelIndex = session_SelectedTrack Then
            stripColor = session_ThemePalette.selectedPanelColor
        End If
        backend_Rect stripLeft, mixerTop + SESSION_MIXER_TITLE_HEIGHT, _
            stripRight - stripLeft + 1, SESSION_MIXER_HEIGHT - _
            SESSION_MIXER_TITLE_HEIGHT - 3, stripColor, 1
        backend_Rect stripLeft, mixerTop + SESSION_MIXER_TITLE_HEIGHT, _
            stripRight - stripLeft + 1, SESSION_MIXER_HEIGHT - _
            SESSION_MIXER_TITLE_HEIGHT - 3, session_ThemePalette.borderColor, 0
        If channelIndex = session_SelectedTrack AndAlso _
            channelIndex < session_Summary.trackCount Then
            backend_Rect stripLeft + 2, mixerTop + SESSION_MIXER_TITLE_HEIGHT + 2, _
                stripRight - stripLeft - 3, 3, _
                session_ThemePalette.accentBrightColor, 1
        End If

        Dim As String channelName = "Track " + Str(channelIndex + 1)
        If channelIndex < session_Summary.trackCount Then
            channelName = Str(channelIndex + 1) + " - " + _
                midi_TrackDisplayName(session_Summary, channelIndex)
        End If
        Dim As Integer maximumNameCharacters = (stripRight - stripLeft - 4) \ 8
        If maximumNameCharacters < 3 Then
            maximumNameCharacters = 3
        End If
        channelName = session_ClipText(channelName, maximumNameCharacters)
        backend_PrintAligned stripLeft + 2, mixerTop + 30, _
            stripRight - stripLeft - 3, 13, channelTextColor, channelName, _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP

        Dim As Integer meterWidth = 9
        Dim As Integer meterLeft = stripRight - meterWidth - 4
        Dim As Integer faderX = _
            mixerControls_ChannelFaderX(mixerLayout, visibleIndex)
        backend_Line faderX - 1, faderTop, faderX - 1, faderBottom, _
            session_ThemePalette.faderRailShadowColor
        backend_Line faderX, faderTop, faderX, faderBottom, _
            session_ThemePalette.faderRailColor
        For tickIndex As Integer = 0 To 4
            Dim As Integer tickY = faderTop + _
                ((faderBottom - faderTop) * tickIndex) \ 4
            backend_Line faderX - 6, tickY, faderX - 3, tickY, _
                session_ThemePalette.faderTickColor
        Next

        Dim As Integer faderY = faderBottom - CInt( _
            session_ChannelVolume(channelIndex) * CSng(faderBottom - faderTop))
        Dim As ULong faderColor = session_ThemePalette.faderHandleColor
        If channelIndex = session_SelectedTrack Then _
            faderColor = session_ThemePalette.faderHandleSelectedColor
        backend_Rect faderX - 9, faderY - 5, 18, 10, faderColor, 1
        backend_Rect faderX - 9, faderY - 5, 18, 10, _
            session_ThemePalette.faderHandleOutlineColor, 0
        backend_Line faderX - 7, faderY, faderX + 7, faderY, _
            session_ThemePalette.faderHandleLineColor

        Dim As Single meterLevel = mixerMeter_ChannelLevel( _
            session_MixerMeter, channelIndex)
        session_DrawMixerMeter meterLeft, faderTop, meterWidth, _
            faderBottom - faderTop + 1, meterLevel

        backend_Rect stripLeft + 3, nameBoxTop, stripRight - stripLeft - 5, _
            17, session_ThemePalette.insetColor, 1
        backend_Rect stripLeft + 3, nameBoxTop, stripRight - stripLeft - 5, _
            17, session_ThemePalette.borderColor, 0
        Dim As String instrumentName = "Prog " + _
            Str(CInt(session_Summary.channelProgram(channelIndex)) + 1)
        If channelIndex = 9 Then
            instrumentName = "Drums"
        End If
        instrumentName = session_ClipText(instrumentName, maximumNameCharacters)
        backend_PrintAligned stripLeft + 4, nameBoxTop + 3, _
            stripRight - stripLeft - 7, 12, channelTextColor, instrumentName, _
            BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP

        Dim As Integer knobCellWidth = (stripRight - stripLeft + 1) \ 3
        Dim As Single knobValue(0 To 2)
        knobValue(0) = session_ChannelChorus(channelIndex)
        knobValue(1) = session_ChannelReverb(channelIndex)
        knobValue(2) = (session_ChannelPan(channelIndex) + 1.0) * 0.5
        Dim As String knobLabel(0 To 2) = {"Ch", "Rv", "Pn"}
        For knobIndex As Integer = 0 To 2
            Dim As Integer knobCenterX = stripLeft + knobCellWidth * knobIndex + _
                knobCellWidth \ 2
            session_DrawMixerKnob knobCenterX, knobY, knobValue(knobIndex)
            backend_PrintAligned knobCenterX - knobCellWidth \ 2, knobY + 8, _
                knobCellWidth, 9, session_ThemePalette.mutedTextColor, _
                knobLabel(knobIndex), _
                BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP
        Next

        Dim As Integer buttonSpan = stripRight - stripLeft + 1
        For buttonIndex As Integer = 0 To 2
            Dim As Integer buttonLeft = stripLeft + _
                (buttonIndex * buttonSpan) \ 3
            Dim As Integer buttonRight = stripLeft + _
                ((buttonIndex + 1) * buttonSpan) \ 3 - 1
            Dim As Integer buttonState = 0
            Dim As String buttonLabel = "M"
            Select Case buttonIndex
                Case 0
                    buttonState = session_MixerChannels.mute(channelIndex)
                    buttonLabel = "M"
                Case 1
                    buttonState = session_MixerChannels.solo(channelIndex)
                    buttonLabel = "S"
                Case 2
                    buttonState = session_MixerChannels.record(channelIndex)
                    buttonLabel = "R"
            End Select
            Dim As OseUiControlStyle buttonStyle
            uiStyle_MixerButton buttonStyle, session_ThemePalette, _
                buttonIndex, buttonState
            session_DrawRoundedControl buttonLeft, buttonTop, _
                buttonRight - buttonLeft + 1, _
                mixerLayout.buttonHeight, buttonStyle
            backend_PrintAligned buttonLeft, _
                buttonTop + (mixerLayout.buttonHeight - 8) \ 2, _
                buttonRight - buttonLeft + 1, 10, buttonStyle.contentColor, _
                buttonLabel, BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, _
                BACKEND_ALIGN_TOP
        Next
    Next

    ' The right-hand master block is deliberately wider than a channel strip,
    ' matching the Recording Session layout and keeping transport state legible.
    session_DrawMixerMasterBlock mixerLayout, screenHeight
    session_MixerPageFingerprint(workPage) = visualFingerprint
    session_MixerStaticPageFingerprint(workPage) = staticFingerprint
    session_MixerPageMasterVolume(workPage) = session_MasterVolume
    session_MixerPageValid(workPage) = -1
End Sub


Private Sub session_DrawRaisedPanel( _
    ByVal panelLeft As Integer, _
    ByVal panelTop As Integer, _
    ByVal panelWidth As Integer, _
    ByVal panelHeight As Integer, _
    ByVal faceColor As ULong _
)
    If panelWidth <= 1 OrElse panelHeight <= 1 Then
        Exit Sub
    End If
    backend_Rect panelLeft, panelTop, panelWidth, panelHeight, faceColor, 1
    backend_Line panelLeft, panelTop, panelLeft + panelWidth - 1, _
        panelTop, session_ThemePalette.highlightColor
    backend_Line panelLeft, panelTop, panelLeft, panelTop + panelHeight - 1, _
        session_ThemePalette.highlightColor
    backend_Line panelLeft, panelTop + panelHeight - 1, _
        panelLeft + panelWidth - 1, panelTop + panelHeight - 1, _
        session_ThemePalette.shadowColor
    backend_Line panelLeft + panelWidth - 1, panelTop, _
        panelLeft + panelWidth - 1, panelTop + panelHeight - 1, _
        session_ThemePalette.shadowColor
End Sub


Private Sub session_DrawUiIcon( _
    ByVal iconId As Integer, _
    ByVal iconLeft As Integer, _
    ByVal iconTop As Integer, _
    ByVal iconColor As ULong _
)
    If uiIcons_IsValid(iconId) = 0 Then
        Exit Sub
    End If

    /'
        The atlas stores grayscale coverage, not RGB subpixels. Alpha blending
        preserves its hand-hinted edge on BGR, RGB, rotated, and scaled displays
        without baking a monitor-specific color fringe into the application.
    '/
    Dim As UByte iconCoverage(0 To OSE_UI_ICON_SIZE * OSE_UI_ICON_SIZE - 1)
    For pixelY As Integer = 0 To OSE_UI_ICON_SIZE - 1
        Dim As String rowText
        If uiIcons_GetRow(iconId, pixelY, rowText) = 0 Then
            Exit Sub
        End If
        For pixelX As Integer = 0 To OSE_UI_ICON_SIZE - 1
            iconCoverage(pixelY * OSE_UI_ICON_SIZE + pixelX) = _
                uiIcons_DecodeCoverage(rowText[pixelX])
        Next
    Next
    If backend_DrawAlphaMask(iconLeft, iconTop, OSE_UI_ICON_SIZE, _
        OSE_UI_ICON_SIZE, @iconCoverage(0), iconColor) <> 0 Then Exit Sub

    For pixelY As Integer = 0 To OSE_UI_ICON_SIZE - 1
        For pixelX As Integer = 0 To OSE_UI_ICON_SIZE - 1
            Dim As Integer coverage = _
                iconCoverage(pixelY * OSE_UI_ICON_SIZE + pixelX)
            If coverage > 0 Then backend_PSetAlpha iconLeft + pixelX, _
                iconTop + pixelY, iconColor, coverage
        Next pixelX
    Next pixelY
End Sub


Private Sub session_DrawFilledEllipse( _
    ByVal ellipseLeft As Integer, _
    ByVal ellipseTop As Integer, _
    ByVal ellipseWidth As Integer, _
    ByVal ellipseHeight As Integer, _
    ByVal ellipseColor As ULong _
)
    If ellipseWidth <= 0 OrElse ellipseHeight <= 0 Then
        Exit Sub
    End If

    Dim As GraphicShapeRenderOptions options
    Dim As Integer pointX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer pointY(1 To GRAPHICSHAPE_MAX_POINTS)
    graphicshape_DefaultOptions options, GUI_SHAPE_ELLIPSE
    options.stroke_clr = ellipseColor
    options.fill_clr = ellipseColor
    options.filled = -1
    options.line_width = 1
    options.object_alpha = 255
    options.stroke_alpha = 255
    options.fill_alpha = 255
    options.clip_to_bounds = -1
    graphicshape_RenderWithOptions ellipseLeft, ellipseTop, ellipseWidth, _
        ellipseHeight, options, "", 0, pointX(), pointY()
End Sub


Private Sub session_DrawRoundedControl( _
    ByVal controlLeft As Integer, _
    ByVal controlTop As Integer, _
    ByVal controlWidth As Integer, _
    ByVal controlHeight As Integer, _
    ByRef controlStyle As OseUiControlStyle _
)
    If controlWidth <= 0 OrElse controlHeight <= 0 Then
        Exit Sub
    End If

    Dim As GraphicShapeRenderOptions options
    Dim As Integer pointX(1 To GRAPHICSHAPE_MAX_POINTS)
    Dim As Integer pointY(1 To GRAPHICSHAPE_MAX_POINTS)
    graphicshape_DefaultOptions options, GUI_SHAPE_ROUNDED_RECTANGLE
    options.stroke_clr = controlStyle.borderColor
    options.fill_clr = controlStyle.fillColor
    options.filled = -1
    options.line_width = 1
    options.corner_radius = controlStyle.cornerRadius
    options.object_alpha = 255
    options.stroke_alpha = 255
    options.fill_alpha = 255
    options.clip_to_bounds = -1
    graphicshape_RenderWithOptions controlLeft, controlTop, controlWidth, _
        controlHeight, options, "", 0, pointX(), pointY()
End Sub


Private Sub session_DrawScoreToolRail(ByVal screenHeight As Integer)
    Dim As Integer workPage = backend_GetWorkPage()
    If workPage < 0 OrElse workPage > 1 Then
        workPage = 0
    End If
    Dim As ULongInt visualFingerprint = &h519e7a4dull
    visualFingerprint = session_VisualFingerprintMix( _
        visualFingerprint, CULngInt(screenHeight))
    visualFingerprint = session_VisualFingerprintMix( _
        visualFingerprint, CULngInt(session_ThemeMode))
    visualFingerprint = session_VisualFingerprintMix( _
        visualFingerprint, CULngInt(session_ActiveScoreTool + 1))
    visualFingerprint = session_VisualFingerprintMix( _
        visualFingerprint, CULngInt(session_NoteClipboard.count))
    If session_ScoreToolPageValid(workPage) <> 0 AndAlso _
        session_ScoreToolPageFingerprint(workPage) = visualFingerprint Then _
        Exit Sub

    Dim As Integer railBottom = screenHeight - SESSION_MIXER_HEIGHT - 4
    backend_Rect 2, SESSION_SCORE_TOP, SESSION_SCORE_LEFT - 4, _
        railBottom - SESSION_SCORE_TOP, session_ThemePalette.railColor, 1
    For toolIndex As Integer = 0 To SESSION_SCORE_TOOL_COUNT - 1
        Dim As Integer toolTop = session_InteractionMetrics.scoreRailFirstTop + _
            toolIndex * session_InteractionMetrics.scoreRailStep
        Dim As Integer toolEnabled = -1
        If toolIndex = SESSION_SCORE_TOOL_PASTE AndAlso _
            session_NoteClipboard.count <= 0 Then toolEnabled = 0
        Dim As OseUiControlStyle toolStyle
        uiStyle_ScoreTool toolStyle, session_ThemePalette, _
            IIf(toolIndex = session_ActiveScoreTool, -1, 0), toolEnabled
        session_DrawRoundedControl session_InteractionMetrics.scoreRailLeft, _
            toolTop, session_InteractionMetrics.scoreRailWidth, _
            session_InteractionMetrics.scoreRailHeight, _
            toolStyle

        Dim As ULong iconColor = toolStyle.contentColor
        Dim As Integer iconLeft = session_InteractionMetrics.scoreRailLeft + _
            uiIcons_CenteredOffset(32)
        Dim As Integer iconTop = toolTop + uiIcons_CenteredOffset( _
            session_InteractionMetrics.scoreRailHeight)

        Select Case toolIndex
            Case SESSION_SCORE_TOOL_SELECT
                session_DrawUiIcon OSE_UI_ICON_POINTER, iconLeft, iconTop, _
                    iconColor
            Case SESSION_SCORE_TOOL_ADD_NOTE
                session_DrawUiIcon OSE_UI_ICON_NOTE, iconLeft, iconTop, iconColor

            Case SESSION_SCORE_TOOL_DELETE_NOTE
                session_DrawUiIcon OSE_UI_ICON_TRASH, iconLeft, iconTop, _
                    iconColor

            Case SESSION_SCORE_TOOL_CUT
                session_DrawUiIcon OSE_UI_ICON_CUT, iconLeft, iconTop, iconColor

            Case SESSION_SCORE_TOOL_PASTE
                session_DrawUiIcon OSE_UI_ICON_PASTE, iconLeft, iconTop, _
                    iconColor
        End Select

        ' The icon and stable text name form one accessible visual control.
        ' Users never have to infer an editing action from a tiny glyph alone.
        backend_Print session_InteractionMetrics.scoreRailLeft + 32, _
            toolTop + (session_InteractionMetrics.scoreRailHeight - 8) \ 2, _
            iconColor, scoreControls_ToolLabel(toolIndex)
    Next
    session_ScoreToolPageFingerprint(workPage) = visualFingerprint
    session_ScoreToolPageValid(workPage) = -1
End Sub


Private Function session_DrawPaletteButton( _
    ByVal buttonLeft As Integer, ByVal buttonTop As Integer, _
    ByVal selected As Integer _
) As ULong
    Dim As OseUiControlStyle buttonStyle
    uiStyle_ScoreTool buttonStyle, session_ThemePalette, selected, -1
    buttonStyle.cornerRadius = 4
    session_DrawRoundedControl buttonLeft, buttonTop, _
        SESSION_SCORE_PALETTE_FACE_WIDTH, _
        SESSION_SCORE_PALETTE_FACE_HEIGHT, buttonStyle
    Return buttonStyle.contentColor
End Function


Private Sub session_DrawPaletteDurationIcon( _
    ByVal durationIndex As Integer, _
    ByVal buttonLeft As Integer, _
    ByVal buttonTop As Integer, _
    ByVal iconColor As ULong _
)
    Dim As Integer noteX = buttonLeft + 8
    Dim As Integer noteY = buttonTop + 15
    Dim As Integer filledHead = IIf( _
        durationIndex >= OSE_SCORE_DURATION_QUARTER, -1, 0)
    session_DrawVectorNoteHead noteX, noteY, 8, 6, filledHead, iconColor
    If durationIndex = OSE_SCORE_DURATION_WHOLE Then
        Exit Sub
    End If

    Dim As Integer stemX = noteX + 3
    Dim As Integer stemTop = buttonTop + 3
    session_DrawVectorNoteStem stemX, noteY, stemTop, 2, iconColor
    Dim As Integer flagCount = durationIndex - OSE_SCORE_DURATION_QUARTER
    If flagCount < 0 Then
        flagCount = 0
    End If
    For flagIndex As Integer = 0 To flagCount - 1
        session_DrawVectorNoteFlag stemX, stemTop + flagIndex * 3, -1, _
            11, 11, iconColor
    Next
End Sub


Private Sub session_DrawPaletteModifierIcon( _
    ByVal modifierRow As Integer, _
    ByVal buttonLeft As Integer, _
    ByVal buttonTop As Integer, _
    ByVal iconColor As ULong _
)
    Select Case modifierRow
        Case 0
            backend_Line buttonLeft + 7, buttonTop + 3, _
                buttonLeft + 5, buttonTop + 18, iconColor
            backend_Line buttonLeft + 14, buttonTop + 3, _
                buttonLeft + 12, buttonTop + 18, iconColor
            backend_Line buttonLeft + 3, buttonTop + 8, _
                buttonLeft + 17, buttonTop + 6, iconColor
            backend_Line buttonLeft + 3, buttonTop + 14, _
                buttonLeft + 17, buttonTop + 12, iconColor
        Case 1
            backend_Line buttonLeft + 8, buttonTop + 2, _
                buttonLeft + 8, buttonTop + 18, iconColor
            backend_Line buttonLeft + 9, buttonTop + 10, _
                buttonLeft + 15, buttonTop + 8, iconColor
            backend_Line buttonLeft + 15, buttonTop + 8, _
                buttonLeft + 14, buttonTop + 15, iconColor
            backend_Line buttonLeft + 14, buttonTop + 15, _
                buttonLeft + 8, buttonTop + 18, iconColor
        Case 2
            backend_Line buttonLeft + 6, buttonTop + 3, _
                buttonLeft + 6, buttonTop + 17, iconColor
            backend_Line buttonLeft + 14, buttonTop + 2, _
                buttonLeft + 14, buttonTop + 16, iconColor
            backend_Line buttonLeft + 6, buttonTop + 8, _
                buttonLeft + 14, buttonTop + 5, iconColor
            backend_Line buttonLeft + 6, buttonTop + 14, _
                buttonLeft + 14, buttonTop + 11, iconColor
        Case 3
            session_DrawFilledEllipse buttonLeft + 8, buttonTop + 8, 5, 5, _
                iconColor
        Case 4
            backend_Print buttonLeft + 7, buttonTop + 5, iconColor, "3"
        Case 5
            backend_Line buttonLeft + 3, buttonTop + 11, _
                buttonLeft + 7, buttonTop + 15, iconColor
            backend_Line buttonLeft + 7, buttonTop + 15, _
                buttonLeft + 14, buttonTop + 15, iconColor
            backend_Line buttonLeft + 14, buttonTop + 15, _
                buttonLeft + 18, buttonTop + 11, iconColor
            backend_Line buttonLeft + 4, buttonTop + 12, _
                buttonLeft + 17, buttonTop + 12, iconColor
    End Select
End Sub


Private Sub session_DrawAddNotePalette()
    If session_ActiveScoreTool <> SESSION_SCORE_TOOL_ADD_NOTE OrElse _
        session_AddPaletteVisible = 0 Then Exit Sub

    session_DrawRaisedPanel SESSION_SCORE_PALETTE_LEFT, _
        SESSION_SCORE_PALETTE_TOP, SESSION_SCORE_PALETTE_WIDTH, _
        SESSION_SCORE_PALETTE_HEIGHT, session_ThemePalette.paletteColor

    For rowIndex As Integer = 0 To SESSION_SCORE_PALETTE_ROW_COUNT - 1
        Dim As Integer buttonTop = SESSION_SCORE_PALETTE_TOP + 4 + _
            rowIndex * SESSION_SCORE_PALETTE_ROW_HEIGHT
        Dim As Integer durationLeft = SESSION_SCORE_PALETTE_LEFT + 4
        Dim As Integer contentTop = buttonTop + _
            (SESSION_SCORE_PALETTE_FACE_HEIGHT - 25) \ 2
        Dim As Integer durationSelected = IIf( _
            session_AddToolState.durationIndex = rowIndex, -1, 0)
        Dim As ULong durationColor = session_DrawPaletteButton( _
            durationLeft, buttonTop, durationSelected)
        session_DrawPaletteDurationIcon rowIndex, durationLeft, contentTop, _
            durationColor
        backend_Print durationLeft + 28, contentTop + 8, durationColor, _
            scoreControls_DurationLabel(rowIndex)

        If rowIndex < 6 Then
            Dim As Integer modifierLeft = durationLeft + _
                SESSION_SCORE_PALETTE_COLUMN_WIDTH
            Dim As Integer modifierSelected
            Select Case rowIndex
                Case 0
                    modifierSelected = session_AddToolState.accidentalSemitones > 0
                Case 1
                    modifierSelected = session_AddToolState.accidentalSemitones < 0
                Case 2
                    modifierSelected = session_AddToolState.accidentalSemitones = 0
                Case 3
                    modifierSelected = session_AddToolState.dotted
                Case 4
                    modifierSelected = session_AddToolState.triplet
                Case 5
                    modifierSelected = session_AddToolState.tied
            End Select
            Dim As ULong modifierColor = session_DrawPaletteButton( _
                modifierLeft, buttonTop, modifierSelected)
            session_DrawPaletteModifierIcon rowIndex, modifierLeft, _
                contentTop, _
                modifierColor
            backend_Print modifierLeft + 28, contentTop + 8, modifierColor, _
                scoreControls_ModifierLabel(rowIndex)
        End If
    Next
End Sub


Private Sub session_DrawScoreToolCursor( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    If session_IsModalOpen() <> 0 OrElse _
        session_ActiveScoreTool = SESSION_SCORE_TOOL_SELECT Then Exit Sub

    Dim As Integer mouseX = input_MouseX()
    Dim As Integer mouseY = input_MouseY()
    Dim As Integer editLeft
    Dim As Integer editTop
    Dim As Integer editRight
    Dim As Integer editBottom
    session_ScoreEditBounds screenWidth, screenHeight, editLeft, editTop, _
        editRight, editBottom
    If mouseX < editLeft OrElse mouseX > editRight OrElse _
        mouseY < editTop OrElse mouseY > editBottom Then Exit Sub

    Select Case session_ActiveScoreTool
        Case SESSION_SCORE_TOOL_ADD_NOTE
            Dim As ULongInt guideTick = session_TickFromScreenX(mouseX, screenWidth)
            Dim As Integer guideX = session_ScoreTickToX(guideTick, editLeft, _
                editRight, session_ViewTicks())
            backend_Line guideX, SESSION_SCORE_TOP + 25, guideX, editBottom, _
                session_ThemePalette.accentBrightColor
            session_DrawVectorNoteHead guideX - 4, mouseY + 3, 9, 6, -1, _
                session_ThemePalette.accentColor
            session_DrawVectorNoteStem guideX, mouseY + 3, mouseY - 10, _
                2, session_ThemePalette.accentColor
        Case SESSION_SCORE_TOOL_DELETE_NOTE
            session_DrawUiIcon OSE_UI_ICON_TRASH, mouseX - 12, mouseY - 12, _
                session_ThemePalette.textColor
        Case SESSION_SCORE_TOOL_CUT
            session_DrawUiIcon OSE_UI_ICON_CUT, mouseX - 12, mouseY - 12, _
                session_ThemePalette.textColor
        Case SESSION_SCORE_TOOL_PASTE
            session_DrawUiIcon OSE_UI_ICON_PASTE, mouseX - 12, mouseY - 12, _
                session_ThemePalette.textColor
    End Select
End Sub


Private Sub session_DrawApplication(ByVal screenWidth As Integer, ByVal screenHeight As Integer)
    Dim As Integer workPage = backend_GetWorkPage()
    If workPage < 0 OrElse workPage > 1 Then
        workPage = 0
    End If
    Dim As Integer visibleMenu = session_VisibleDesktopMenuIndex()
    Dim As Integer modalState = session_IsModalOpen()
    Dim As Integer chromeStatus = _
        IIf(session_LiveRecording <> 0 OrElse _
        session_MicCaptureActive <> 0, 1, 0) Or _
        IIf(session_MidiOutputOpened <> 0, 2, 0)
    Dim As Integer redrawStaticChrome = _
        session_ChromePageWidth(workPage) <> screenWidth OrElse _
        session_ChromePageHeight(workPage) <> screenHeight OrElse _
        session_ChromePageTheme(workPage) <> session_ThemeMode OrElse _
        session_ChromePageKeyboardAccess(workPage) <> _
            session_MenuKeyboardAccess OrElse _
        session_ChromePageVisibleMenu(workPage) <> visibleMenu OrElse _
        session_ChromePageModalState(workPage) <> modalState OrElse _
        session_ChromePageStatus(workPage) <> chromeStatus

    /'
        Double-buffered static chrome

        Each work page retains pixels from its previous presentation. Menu and
        toolbar chrome therefore needs rebuilding only when page-local state
        changes. Score, mixer, widgets, and live indicators still redraw below.
        Tracking both pages avoids stale pixels when overlays open or close.
    '/
    If redrawStaticChrome <> 0 Then
        backend_Rect 0, 0, screenWidth, screenHeight, _
            session_ThemePalette.windowColor, 1
        session_ScoreStaticPageWidth(workPage) = 0
        session_ScorePageValid(workPage) = 0
        session_ScoreHeaderPageValid(workPage) = 0
        session_MixerPageValid(workPage) = 0
        session_ScoreToolPageValid(workPage) = 0
        session_StatusPageValid(workPage) = 0

        ' The menu and command shelf retain the compact desktop layout while using
        ' a flat neutral surface that lets interactive states carry the hierarchy.
        backend_Rect 0, 0, screenWidth, SESSION_MENU_HEIGHT, _
            session_ThemePalette.menuBarColor, 1
        backend_Line 0, SESSION_MENU_HEIGHT - 1, screenWidth - 1, _
            SESSION_MENU_HEIGHT - 1, session_ThemePalette.dividerColor
        Dim As Integer menuTextY = (SESSION_MENU_HEIGHT - 8) \ 2
        backend_Print 10, menuTextY, session_ThemePalette.textColor, "File"
        backend_Print 50, menuTextY, session_ThemePalette.textColor, "Edit"
        backend_Print 90, menuTextY, session_ThemePalette.textColor, "Options"
        backend_Print 154, menuTextY, session_ThemePalette.textColor, "Setup"
        backend_Print 210, menuTextY, session_ThemePalette.textColor, "View"
        backend_Print 258, menuTextY, session_ThemePalette.textColor, "Track"
        backend_Print 312, menuTextY, session_ThemePalette.textColor, "Music"
        backend_Print screenWidth - 42, menuTextY, _
            session_ThemePalette.textColor, "Help"

        If session_MenuKeyboardAccess <> 0 Then
            ' Underline each mnemonic only while the menu bar is being operated
            ' from the keyboard, matching contemporary desktop focus-cue policy.
            Dim As Integer mnemonicX(0 To SESSION_DESKTOP_MENU_COUNT - 1) = { _
                10, 50, 90, 154, 210, 258, 312, screenWidth - 42 _
            }
            For mnemonicIndex As Integer = 0 To SESSION_DESKTOP_MENU_COUNT - 1
                backend_Line mnemonicX(mnemonicIndex), menuTextY + 9, _
                    mnemonicX(mnemonicIndex) + 6, menuTextY + 9, _
                    session_ThemePalette.textColor
            Next
        End If

        backend_Rect 0, SESSION_TOOLBAR_TOP, screenWidth, _
            SESSION_TOOLBAR_HEIGHT, session_ThemePalette.toolbarColor, 1
        backend_Line 0, SESSION_TOOLBAR_TOP + SESSION_TOOLBAR_HEIGHT - 1, _
            screenWidth - 1, SESSION_TOOLBAR_TOP + SESSION_TOOLBAR_HEIGHT - 1, _
            session_ThemePalette.dividerColor
        Dim As Integer dividerCount = IIf( _
            session_InteractionMode = OSE_UI_INTERACTION_TOUCH, 2, 5)
        For dividerIndex As Integer = 0 To dividerCount - 1
            Dim As Integer dividerX
            If session_InteractionMode = OSE_UI_INTERACTION_TOUCH Then
                dividerX = IIf(dividerIndex = 0, 194, 618)
            Else
                Select Case dividerIndex
                    Case 0
                        dividerX = 160
                    Case 1
                        dividerX = 508
                    Case 2
                        dividerX = 648
                    Case 3
                        dividerX = 846
                    Case Else
                        dividerX = 990
                End Select
            End If
            backend_Line dividerX, SESSION_TOOLBAR_TOP + 4, dividerX, _
                SESSION_TOOLBAR_TOP + SESSION_TOOLBAR_HEIGHT - 5, _
                session_ThemePalette.shadowColor
        Next

        If screenWidth >= 1040 AndAlso _
            session_InteractionMode = OSE_UI_INTERACTION_FINE Then
            backend_Print 654, SESSION_TOOLBAR_TOP + 13, _
                session_ThemePalette.textColor, "Tempo"
        End If

        If screenWidth >= 1040 AndAlso _
            session_InteractionMode = OSE_UI_INTERACTION_FINE Then
            backend_PrintAligned 510, SESSION_TOOLBAR_TOP + 2, 136, 12, _
                session_ThemePalette.textColor, "MEASURE  BEAT  TICK", _
                BACKEND_FONT_DEFAULT, BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP
        End If
        If screenWidth >= 1100 AndAlso _
            session_InteractionMode = OSE_UI_INTERACTION_FINE Then
            Dim As ULong statusColor = session_ThemePalette.activityOffColor
            If (chromeStatus And 1) <> 0 Then _
                statusColor = session_ThemePalette.dangerColor
            backend_Circle screenWidth - 18, SESSION_TOOLBAR_TOP + 13, 5, _
                statusColor, 1
            backend_Print screenWidth - 28, SESSION_TOOLBAR_TOP + 24, _
                session_ThemePalette.mutedTextColor, "In"
            backend_Circle screenWidth - 18, SESSION_TOOLBAR_TOP + 36, 5, _
                IIf((chromeStatus And 2) <> 0, _
                session_ThemePalette.activityOnColor, _
                session_ThemePalette.activityOffColor), 1
            backend_Print screenWidth - 30, SESSION_TOOLBAR_TOP + 44, _
                session_ThemePalette.mutedTextColor, "Out"
        End If

        session_ChromePageWidth(workPage) = screenWidth
        session_ChromePageHeight(workPage) = screenHeight
        session_ChromePageTheme(workPage) = session_ThemeMode
        session_ChromePageKeyboardAccess(workPage) = session_MenuKeyboardAccess
        session_ChromePageVisibleMenu(workPage) = visibleMenu
        session_ChromePageModalState(workPage) = modalState
        session_ChromePageStatus(workPage) = chromeStatus
    End If

    /'
        The status label is transparent and changes independently of the rest
        of the toolbar. Own its small background explicitly so repeated modal
        widget passes cannot accumulate antialiased coverage into bold text.
    '/
    If session_StatusLabel <> 0 AndAlso _
        session_StatusLabel->data <> 0 Then
        Dim As LabelData Ptr statusData = Cast( _
            LabelData Ptr, session_StatusLabel->data)
        Dim As ULongInt statusFingerprint = session_VisualFingerprintText( _
            &h27d4eb2f165667c5ull, statusData->text)
        If session_StatusPageValid(workPage) = 0 OrElse _
            session_StatusPageFingerprint(workPage) <> statusFingerprint Then
            Dim As Integer statusWidth = screenWidth - 54 - _
                session_StatusLabel->x
            If statusWidth > 0 Then
                backend_Rect 0, session_StatusLabel->y - 1, screenWidth, 12, _
                    session_ThemePalette.toolbarColor, 1
                backend_Line 0, session_StatusLabel->y + 10, screenWidth - 1, _
                    session_StatusLabel->y + 10, session_ThemePalette.dividerColor
                backend_Print session_StatusLabel->x, _
                    session_StatusLabel->y, session_ThemePalette.textColor, _
                    statusData->text
            End If
            session_StatusPageFingerprint(workPage) = statusFingerprint
            session_StatusPageValid(workPage) = -1
        End If
    End If

    Dim As ULongInt displayTick = session_ViewStartTick
    If session_Playing <> 0 Then displayTick = midi_SecondsToTicks( _
        session_Summary, session_PlaybackElapsed)
    Dim As ULongInt displayMeasure
    Dim As ULongInt displayBeat
    Dim As ULongInt displaySubTick
    session_MusicalPosition displayTick, displayMeasure, displayBeat, _
        displaySubTick
    If screenWidth >= 1040 AndAlso _
        session_InteractionMode = OSE_UI_INTERACTION_FINE Then
        backend_Rect 510, SESSION_TOOLBAR_TOP + 16, 136, 25, _
            session_ThemePalette.timelineFillColor, 1
        backend_Rect 510, SESSION_TOOLBAR_TOP + 16, 136, 25, _
            session_ThemePalette.timelineBorderColor, 0
        backend_PrintAligned 510, SESSION_TOOLBAR_TOP + 22, 136, 12, _
            session_ThemePalette.timelineTextColor, _
            LTrim(Str(displayMeasure)) + " : " + LTrim(Str(displayBeat)) + _
            " : " + LTrim(Str(displaySubTick)), BACKEND_FONT_DEFAULT, _
            BACKEND_ALIGN_CENTER, BACKEND_ALIGN_TOP
    End If

    Dim As Double smoothnessSectionClock
    If session_SmoothnessProfilingActive <> 0 Then _
        smoothnessSectionClock = Timer
    session_DrawScore screenWidth, screenHeight
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreRenderMs = uiFramePacing_ElapsedMilliseconds( _
            smoothnessSectionClock, Timer)
        smoothnessSectionClock = Timer
    End If
    session_DrawScoreToolRail screenHeight
    session_DrawAddNotePalette()
    session_DrawScoreToolCursor screenWidth, screenHeight
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessScoreToolRenderMs = _
            uiFramePacing_ElapsedMilliseconds(smoothnessSectionClock, Timer)
        smoothnessSectionClock = Timer
    End If
    session_DrawMixer screenWidth, screenHeight
    If session_SmoothnessProfilingActive <> 0 Then
        session_SmoothnessMixerRenderMs = uiFramePacing_ElapsedMilliseconds( _
            smoothnessSectionClock, Timer)
    End If
End Sub


Private Function session_MainWidgetFingerprint( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
) As ULongInt
    Dim As ULongInt fingerprint = &h27d4eb2f165667c5ull

    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenWidth))
    fingerprint = session_VisualFingerprintMix(fingerprint, CULngInt(screenHeight))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_ThemeMode))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Playing And &H1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_Paused And &H1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_LiveRecording And &H1))
    fingerprint = session_VisualFingerprintMix( _
        fingerprint, CULngInt(session_MenuKeyboardAccess And &H1))
    If session_TempoBox <> 0 Then fingerprint = session_VisualFingerprintText( _
        fingerprint, textbox_GetText(session_TempoBox))

    /'
        Pointer movement over the menu or toolbar may change hover and pressed
        faces even when document state is unchanged. Below the toolbar, the
        main widgets are stable except for the two score scrollbars, which the
        cached renderer refreshes separately.
    '/
    If input_MouseY() < SESSION_SCORE_TOP Then
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, CULngInt(CUInt(input_MouseX())))
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, CULngInt(CUInt(input_MouseY())))
        fingerprint = session_VisualFingerprintMix( _
            fingerprint, CULngInt(CUInt(input_MouseButtons())))
    End If
    Return fingerprint
End Function


Private Sub session_RenderTopLevelWidget(ByVal targetWidget As Widget Ptr)
    If targetWidget = 0 OrElse targetWidget->evis = 0 OrElse _
        targetWidget->render = 0 Then Exit Sub
    If targetWidget->w <= 0 OrElse targetWidget->h <= 0 Then
        Exit Sub
    End If

    backend_SetClip targetWidget->ax, targetWidget->ay, _
        targetWidget->w, targetWidget->h
    targetWidget->render(targetWidget)
    backend_ResetClip
End Sub


Private Sub session_RenderWidgets( _
    ByVal screenWidth As Integer, _
    ByVal screenHeight As Integer _
)
    Dim As Integer workPage = backend_GetWorkPage()
    If workPage < 0 OrElse workPage > 1 Then
        workPage = 0
    End If

    /'
        Menus, dialogs, and keyboard focus can alter arbitrary registered
        controls, so those states retain omaGUI's complete ordered render.
        The normal editor desktop keeps identical toolbar pixels on each work
        page and refreshes only the scrollbars layered over the changing score.
    '/
    If session_IsModalOpen() <> 0 OrElse _
        session_VisibleDesktopMenuIndex() >= 0 OrElse _
        gui_GetFocus() <> 0 OrElse _
        gui_IsKeyboardNavigationActive() <> 0 Then
        gui_RenderAll
        session_WidgetPageValid(workPage) = 0
        Exit Sub
    End If

    Dim As ULongInt fingerprint = session_MainWidgetFingerprint( _
        screenWidth, screenHeight)
    If session_WidgetPageValid(workPage) = 0 OrElse _
        session_WidgetPageFingerprint(workPage) <> fingerprint Then
        gui_RenderAll
        session_WidgetPageFingerprint(workPage) = fingerprint
        session_WidgetPageValid(workPage) = -1
        Exit Sub
    End If

    session_RenderTopLevelWidget session_ScoreHorizontalScrollbar
    session_RenderTopLevelWidget session_ScoreVerticalScrollbar
End Sub

#endif

/' end of src/editor/score_render.bi '/
