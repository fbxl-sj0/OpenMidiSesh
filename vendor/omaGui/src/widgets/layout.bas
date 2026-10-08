/'
    Project: omaGUI
    ---------------

    File: layout.bas

    Purpose:

        Arrange direct child widgets without embedding fixed screen
        coordinates in every application.

    Responsibilities:

        - lay out visible children in rows, columns, or equal-cell grids
        - respect preferred and minimum child sizes
        - divide remaining row or column space by child weight
        - detect impossible minimum-size combinations

    This file intentionally does NOT contain:

        - widget rendering
        - recursive screen construction
        - automatic scrolling for an overflowing layout
'/

#lang "fb"
#include once "src/widgets/layout.bi"

' The core registry owns membership. Walk direct registered children instead
' of maintaining a second sibling list that callbacks could leave dangling.
Private Function layout_NextChild(ByVal parentWidget As Widget Ptr, ByVal afterWidget As Widget Ptr) As Widget Ptr
    Dim As Widget Ptr current = widget_list_head
    If afterWidget <> 0 Then current = afterWidget->next_widget
    While current <> 0
        If current->parent = parentWidget Then Return current
        current = current->next_widget
    Wend
    Return 0
End Function

Private Function layout_FirstChild(ByVal parentWidget As Widget Ptr) As Widget Ptr
    Return layout_NextChild(parentWidget, 0)
End Function

Private Function layout_Validate(ByVal w As Widget Ptr) As Integer
    If w->w < 0 OrElse w->w > 32767 OrElse w->h < 0 OrElse w->h > 32767 Then Return 0
    Dim As LayoutData Ptr d = w->data
    If d->padding < 0 OrElse d->padding > 32767 OrElse d->gap < 0 OrElse d->gap > 32767 Then Return 0
    If d->columns < 1 OrElse d->columns > 4096 Then Return 0
    Dim As Integer childCount
    Dim As Widget Ptr child = layout_FirstChild(w)
    While child <> 0
        childCount += 1
        If childCount > 4096 Then Return 0
        If child->preferred_w < 0 OrElse child->preferred_w > 32767 OrElse child->preferred_h < 0 OrElse child->preferred_h > 32767 Then Return 0
        If child->minimum_w < 0 OrElse child->minimum_w > 32767 OrElse child->minimum_h < 0 OrElse child->minimum_h > 32767 Then Return 0
        If child->layout_weight < 0 OrElse child->layout_weight > 65535 Then Return 0
        If child->layout_row < -1 OrElse child->layout_row > 4095 OrElse child->layout_column < -1 OrElse child->layout_column > 4095 Then Return 0
        If child->layout_row_span < 0 OrElse child->layout_row_span > 4096 OrElse child->layout_column_span < 0 OrElse child->layout_column_span > 4096 Then Return 0
        If child->layout_row >= 0 AndAlso child->layout_row + child->layout_row_span > 4096 Then Return 0
        child = layout_NextChild(w, child)
    Wend
    ' 4096 children and bounded dimensions/weights keep all intermediate
    ' sums and products below signed 32-bit limits, including on DOS targets.
    Return -1
End Function

Private Function layout_VisibleChildCount(ByVal w As Widget Ptr) As Integer
    Dim As Integer childCount
    Dim As Widget Ptr child

    If w = 0 Then Return 0
    child = layout_FirstChild(w)
    While child <> 0
        If child->visible <> 0 Then childCount += 1
        child = layout_NextChild(w, child)
    Wend
    Return childCount
End Function

Private Function layout_PreferredWidth(ByVal child As Widget Ptr) As Integer
    Dim As Integer result = child->preferred_w
    If result < child->minimum_w Then result = child->minimum_w
    If result < 0 Then result = 0
    Return result
End Function

Private Function layout_PreferredHeight(ByVal child As Widget Ptr) As Integer
    Dim As Integer result = child->preferred_h
    If result < child->minimum_h Then result = child->minimum_h
    If result < 0 Then result = 0
    Return result
End Function

Private Sub layout_ApplyLinear( _
    ByVal w As Widget Ptr, _
    ByVal horizontal As Integer)

    Dim As LayoutData Ptr d = Cast(LayoutData Ptr, w->data)
    Dim As Widget Ptr child
    Dim As Integer childCount
    Dim As Integer fixedSize
    Dim As Integer innerPrimary
    Dim As Integer innerCross
    Dim As Integer minimumSize
    Dim As Integer remaining
    Dim As Integer share
    Dim As Integer totalWeight
    Dim As Integer cursor
    Dim As Integer childPrimary
    Dim As Integer childCross

    childCount = layout_VisibleChildCount(w)
    If childCount <= 0 Then Exit Sub

    If horizontal <> 0 Then
        innerPrimary = w->w - d->padding * 2 - d->gap * (childCount - 1)
        innerCross = w->h - d->padding * 2
    Else
        innerPrimary = w->h - d->padding * 2 - d->gap * (childCount - 1)
        innerCross = w->w - d->padding * 2
    End If
    If innerPrimary < 0 Then innerPrimary = 0
    If innerCross < 0 Then innerCross = 0

    child = layout_FirstChild(w)
    While child <> 0
        If child->visible <> 0 Then
            If child->layout_weight > 0 Then
                totalWeight += child->layout_weight
                If horizontal <> 0 Then
                    fixedSize += child->minimum_w
                Else
                    fixedSize += child->minimum_h
                End If
            ElseIf horizontal <> 0 Then
                fixedSize += layout_PreferredWidth(child)
            Else
                fixedSize += layout_PreferredHeight(child)
            End If
        End If
        child = layout_NextChild(w, child)
    Wend

    remaining = innerPrimary - fixedSize
    If remaining < 0 Then
        d->overflowed = -1
        remaining = 0
    End If

    cursor = d->padding
    child = layout_FirstChild(w)
    While child <> 0
        If child->visible <> 0 Then
            If horizontal <> 0 Then
                minimumSize = child->minimum_w
                childPrimary = layout_PreferredWidth(child)
                childCross = layout_PreferredHeight(child)
            Else
                minimumSize = child->minimum_h
                childPrimary = layout_PreferredHeight(child)
                childCross = layout_PreferredWidth(child)
            End If

            If child->layout_weight > 0 Then
                share = 0
                If totalWeight > 0 Then _
                    share = (remaining * child->layout_weight) \ totalWeight
                childPrimary = minimumSize + share
            End If
            If d->stretch_cross_axis <> 0 Then childCross = innerCross
            If childCross > innerCross Then d->overflowed = -1

            If horizontal <> 0 Then
                child->x = cursor
                child->y = d->padding
                child->w = childPrimary
                child->h = childCross
            Else
                child->x = d->padding
                child->y = cursor
                child->w = childCross
                child->h = childPrimary
            End If
            cursor += childPrimary + d->gap
        End If
        child = layout_NextChild(w, child)
    Wend
End Sub

Private Sub layout_ApplyGrid(ByVal w As Widget Ptr)
    Dim As LayoutData Ptr d = Cast(LayoutData Ptr, w->data)
    Dim As Widget Ptr child
    Dim As Integer childCount
    Dim As Integer columns
    Dim As Integer rows
    Dim As Integer automaticIndex
    Dim As Integer row
    Dim As Integer column
    Dim As Integer rowSpan
    Dim As Integer columnSpan
    Dim As Integer innerWidth
    Dim As Integer innerHeight
    Dim As Integer cellWidth
    Dim As Integer cellHeight

    childCount = layout_VisibleChildCount(w)
    If childCount <= 0 Then Exit Sub
    columns = d->columns
    If columns < 1 Then columns = 1
    rows = (childCount + columns - 1) \ columns

    child = layout_FirstChild(w)
    While child <> 0
        If child->visible <> 0 AndAlso child->layout_row >= 0 Then
            rowSpan = IIf(child->layout_row_span > 0, child->layout_row_span, 1)
            If child->layout_row + rowSpan > rows Then _
                rows = child->layout_row + rowSpan
        End If
        child = layout_NextChild(w, child)
    Wend
    If rows < 1 Then rows = 1

    innerWidth = w->w - d->padding * 2 - d->gap * (columns - 1)
    innerHeight = w->h - d->padding * 2 - d->gap * (rows - 1)
    If innerWidth < 0 Then innerWidth = 0 : d->overflowed = -1
    If innerHeight < 0 Then innerHeight = 0 : d->overflowed = -1
    cellWidth = innerWidth \ columns
    cellHeight = innerHeight \ rows

    child = layout_FirstChild(w)
    While child <> 0
        If child->visible <> 0 Then
            If child->layout_row >= 0 AndAlso child->layout_column >= 0 Then
                row = child->layout_row
                column = child->layout_column
            Else
                row = automaticIndex \ columns
                column = automaticIndex Mod columns
            End If
            rowSpan = IIf(child->layout_row_span > 0, child->layout_row_span, 1)
            columnSpan = IIf(child->layout_column_span > 0, _
                child->layout_column_span, 1)
            If column >= columns Then column = columns - 1 : d->overflowed = -1
            If row >= rows Then row = rows - 1 : d->overflowed = -1
            If column + columnSpan > columns Then _
                columnSpan = columns - column : d->overflowed = -1
            If row + rowSpan > rows Then _
                rowSpan = rows - row : d->overflowed = -1

            child->x = d->padding + column * (cellWidth + d->gap)
            child->y = d->padding + row * (cellHeight + d->gap)
            child->w = cellWidth * columnSpan + d->gap * (columnSpan - 1)
            child->h = cellHeight * rowSpan + d->gap * (rowSpan - 1)
            If child->w < child->minimum_w Then _
                child->w = child->minimum_w : d->overflowed = -1
            If child->h < child->minimum_h Then _
                child->h = child->minimum_h : d->overflowed = -1
            automaticIndex += 1
        End If
        child = layout_NextChild(w, child)
    Wend
End Sub

Sub layout_Apply(ByVal w As Widget Ptr)
    Dim As LayoutData Ptr d

    If w = 0 OrElse w->destroy <> @layout_Destroy OrElse w->data = 0 Then _
        Exit Sub
    d = Cast(LayoutData Ptr, w->data)
    d->overflowed = 0
    If layout_Validate(w) = 0 Then d->overflowed = -1: Exit Sub
    Select Case d->mode
        Case GUI_LAYOUT_ROW
            layout_ApplyLinear w, -1
        Case GUI_LAYOUT_COLUMN
            layout_ApplyLinear w, 0
        Case GUI_LAYOUT_GRID
            layout_ApplyGrid w
        Case Else
            d->overflowed = -1
    End Select
End Sub

Function layout_Create( _
    ByVal nm As String, _
    ByVal x As Integer, _
    ByVal y As Integer, _
    ByVal w As Integer, _
    ByVal h As Integer, _
    ByVal mode As Integer, _
    ByVal padding As Integer, _
    ByVal gap As Integer, _
    ByVal columns As Integer) As Widget Ptr

    If w < 0 OrElse w > 32767 OrElse h < 0 OrElse h > 32767 Then Return 0
    If padding < 0 OrElse padding > 32767 OrElse gap < 0 OrElse gap > 32767 Then Return 0
    If columns < 1 OrElse columns > 4096 Then Return 0
    Dim As Widget Ptr result = gui_CreateWidgetBase()
    If result = 0 Then Return 0
    Dim As LayoutData Ptr d = New LayoutData
    If d = 0 Then Delete result: Return 0
    result->name = nm
    result->x = x
    result->y = y
    result->w = IIf(w >= 0, w, 0)
    result->h = IIf(h >= 0, h, 0)
    result->destroy = @layout_Destroy
    result->data = d

    Select Case mode
        Case GUI_LAYOUT_ROW, GUI_LAYOUT_COLUMN, GUI_LAYOUT_GRID
            d->mode = mode
        Case Else
            d->mode = GUI_LAYOUT_COLUMN
    End Select
    d->padding = IIf(padding >= 0, padding, 0)
    d->gap = IIf(gap >= 0, gap, 0)
    d->columns = IIf(columns > 0, columns, 1)
    d->stretch_cross_axis = -1
    d->overflowed = 0
    Return result
End Function

Sub layout_SetStretchCrossAxis( _
    ByVal w As Widget Ptr, _
    ByVal enabled As Integer)

    If w = 0 OrElse w->destroy <> @layout_Destroy OrElse w->data = 0 Then _
        Exit Sub
    Cast(LayoutData Ptr, w->data)->stretch_cross_axis = _
        IIf(enabled <> 0, -1, 0)
End Sub

Function layout_HasOverflow(ByVal w As Widget Ptr) As Integer
    If w = 0 OrElse w->destroy <> @layout_Destroy OrElse w->data = 0 Then _
        Return 0
    Return Cast(LayoutData Ptr, w->data)->overflowed
End Function

Sub layout_Destroy(ByVal w As Widget Ptr)
    If w <> 0 AndAlso w->data <> 0 Then Delete Cast(LayoutData Ptr, w->data)
End Sub

/' end of layout.bas '/
