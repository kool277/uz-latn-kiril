' =====================================================================================
'  LibreOffice UI (Writer, Calc, Impress, Draw) — appended to the shared engine by tools/make_lo_basic.py
'  Tools → Macros → Run Macro → Standard → UzTranslitLO → UzLO_LatToNew (etc.)
'  Selection if any, otherwise the whole document. Formatting is kept (text-portion level).
' =====================================================================================
Public Sub UzLO_CyrToLat()
    UzLO_Run "cyr", "lat"
End Sub
Public Sub UzLO_CyrToNew()
    UzLO_Run "cyr", "new"
End Sub
Public Sub UzLO_LatToCyr()
    UzLO_Run "lat", "cyr"
End Sub
Public Sub UzLO_NewToCyr()
    UzLO_Run "new", "cyr"
End Sub
Public Sub UzLO_LatToNew()
    UzLO_Run "lat", "new"
End Sub
Public Sub UzLO_NewToLat()
    UzLO_Run "new", "lat"
End Sub
Public Sub UzLO_AutoToNew()
    UzLO_Run "auto", "new"
End Sub
Public Sub UzLO_AutoToLat()
    UzLO_Run "auto", "lat"
End Sub
Public Sub UzLO_AutoToCyr()
    UzLO_Run "auto", "cyr"
End Sub

Private Sub UzLO_Run(ByVal f As String, ByVal t As String)
    Dim doc As Object, cnt As Long
    Set doc = ThisComponent
    If doc.supportsService("com.sun.star.text.TextDocument") Then
        cnt = UzLO_Writer(doc, f, t)
    ElseIf doc.supportsService("com.sun.star.sheet.SpreadsheetDocument") Then
        cnt = UzLO_Calc(doc, f, t)
    ElseIf doc.supportsService("com.sun.star.drawing.DrawingDocument") Or doc.supportsService("com.sun.star.presentation.PresentationDocument") Then
        cnt = UzLO_Draw(doc, f, t)
    Else
        MsgBox "UzTranslit: unsupported document type", 48, "UzTranslit"
        Exit Sub
    End If
    MsgBox "UzTranslit: " & cnt & " fragment(s) converted (" & f & " -> " & t & ")", 64, "UzTranslit"
End Sub

' ---- shared: convert every text portion of an XText (paragraphs, tables inside Writer text) ----
Private Function UzLO_XText(ByVal xt As Object, ByVal f As String, ByVal t As String) As Long
    Dim en As Object, el As Object, cnt As Long
    If IsNull(xt) Then Exit Function
    Set en = xt.createEnumeration()
    Do While en.hasMoreElements()
        Set el = en.nextElement()
        If el.supportsService("com.sun.star.text.TextTable") Then
            cnt = cnt + UzLO_Table(el, f, t)
        ElseIf el.supportsService("com.sun.star.text.Paragraph") Then
            cnt = cnt + UzLO_Paragraph(el, f, t)
        End If
    Loop
    UzLO_XText = cnt
End Function

Private Function UzLO_Table(ByVal tbl As Object, ByVal f As String, ByVal t As String) As Long
    Dim names() As String, i As Long, cnt As Long
    names = tbl.getCellNames()
    For i = LBound(names) To UBound(names)
        cnt = cnt + UzLO_XText(tbl.getCellByName(names(i)), f, t)
    Next
    UzLO_Table = cnt
End Function

Private Function UzLO_Paragraph(ByVal para As Object, ByVal f As String, ByVal t As String) As Long
    Dim pe As Object, por As Object, s As String, conv As String, cnt As Long
    Set pe = para.createEnumeration()
    Do While pe.hasMoreElements()
        Set por = pe.nextElement()
        If por.TextPortionType = "Text" Then
            s = por.getString()
            If Len(s) > 0 Then
                conv = UzConvert(s, f, t)
                If conv <> s Then
                    UzLO_ReplacePortion por, conv
                    cnt = cnt + 1
                End If
            End If
        End If
    Loop
    UzLO_Paragraph = cnt
End Function

' Replace a text portion's string while keeping its character formatting (setString alone inherits
' the neighbouring run's attributes at paragraph start).
Private Sub UzLO_ReplacePortion(ByVal por As Object, ByVal conv As String)
    Dim names As Variant, saved(24) As Variant, i As Long, cur As Object
    names = Array("CharWeight", "CharPosture", "CharUnderline", "CharUnderlineColor", "CharUnderlineHasColor", "CharColor", _
                  "CharHeight", "CharFontName", "CharStrikeout", "CharBackColor", "CharBackTransparent", "CharEscapement", _
                  "CharEscapementHeight", "CharCaseMap", "CharHidden", "CharShadowed", "CharContoured", "CharOverline", _
                  "CharRelief", "CharWeightAsian", "CharPostureAsian", "CharHeightAsian", "CharFontNameAsian", "CharKerning", "CharScaleWidth")
    On Error Resume Next
    For i = 0 To UBound(names)
        saved(i) = por.getPropertyValue(names(i))
    Next
    Set cur = por.getText().createTextCursorByRange(por)
    cur.setString(conv)
    For i = 0 To UBound(names)
        cur.setPropertyValue(names(i), saved(i))
    Next
End Sub

' ---- Writer ----
Private Function UzLO_Writer(ByVal doc As Object, ByVal f As String, ByVal t As String) As Long
    Dim sel As Object, rng As Object, cur As Object, i As Long, cnt As Long, hadSel As Boolean
    Dim frames As Object, notes As Object, styles As Object, ps As Object
    On Error Resume Next
    Set sel = doc.CurrentController.getSelection()
    On Error GoTo 0
    If Not IsNull(sel) Then
        If sel.supportsService("com.sun.star.text.TextRanges") Then
            For i = 0 To sel.getCount() - 1
                Set rng = sel.getByIndex(i)
                If Len(rng.getString()) > 0 Then
                    hadSel = True
                    Set cur = rng.getText().createTextCursorByRange(rng)
                    cnt = cnt + UzLO_XText(cur, f, t)
                End If
            Next
        End If
    End If
    If hadSel Then UzLO_Writer = cnt: Exit Function
    cnt = cnt + UzLO_XText(doc.getText(), f, t)
    On Error Resume Next
    Set frames = doc.getTextFrames()
    For i = 0 To frames.getCount() - 1
        cnt = cnt + UzLO_XText(frames.getByIndex(i), f, t)
    Next
    Set notes = doc.getFootnotes()
    For i = 0 To notes.getCount() - 1
        cnt = cnt + UzLO_XText(notes.getByIndex(i), f, t)
    Next
    Set notes = doc.getEndnotes()
    For i = 0 To notes.getCount() - 1
        cnt = cnt + UzLO_XText(notes.getByIndex(i), f, t)
    Next
    Set styles = doc.getStyleFamilies().getByName("PageStyles")
    For i = 0 To styles.getCount() - 1
        Set ps = styles.getByIndex(i)
        ' (isInUse() is unreliable for unsaved documents, so every page style with a header/footer is processed)
        If ps.HeaderIsOn Then
            cnt = cnt + UzLO_XText(ps.HeaderText, f, t)
            If Not ps.HeaderIsShared Then cnt = cnt + UzLO_XText(ps.HeaderTextLeft, f, t)
            If Not ps.FirstIsShared Then cnt = cnt + UzLO_XText(ps.HeaderTextFirst, f, t)
        End If
        If ps.FooterIsOn Then
            cnt = cnt + UzLO_XText(ps.FooterText, f, t)
            If Not ps.FooterIsShared Then cnt = cnt + UzLO_XText(ps.FooterTextLeft, f, t)
            If Not ps.FirstIsShared Then cnt = cnt + UzLO_XText(ps.FooterTextFirst, f, t)
        End If
    Next
    On Error GoTo 0
    UzLO_Writer = cnt
End Function

' ---- Calc ----
Private Function UzLO_CellRange(ByVal rng As Object, ByVal f As String, ByVal t As String) As Long
    Dim q As Object, en As Object, c As Object, s As String, conv As String, cnt As Long
    Set q = rng.queryContentCells(4)        ' com.sun.star.sheet.CellFlags.STRING
    Set en = q.getCells().createEnumeration()
    Do While en.hasMoreElements()
        Set c = en.nextElement()
        s = c.getString()
        conv = UzConvert(s, f, t)
        If conv <> s Then c.setString(conv): cnt = cnt + 1
    Loop
    UzLO_CellRange = cnt
End Function

Private Function UzLO_Calc(ByVal doc As Object, ByVal f As String, ByVal t As String) As Long
    Dim sel As Object, cur As Object, i As Long, cnt As Long, single As Boolean
    Set sel = doc.CurrentSelection
    If sel.supportsService("com.sun.star.sheet.SheetCellRanges") Then
        For i = 0 To sel.getCount() - 1
            cnt = cnt + UzLO_CellRange(sel.getByIndex(i), f, t)
        Next
    ElseIf sel.supportsService("com.sun.star.sheet.SheetCellRange") Then
        single = (sel.getRows().getCount() = 1 And sel.getColumns().getCount() = 1)
        If single Then
            If MsgBox("Convert the whole sheet? (No = only the selected cell)", 36, "UzTranslit") = 6 Then
                Set cur = doc.CurrentController.getActiveSheet().createCursor()
                cur.gotoStartOfUsedArea(False)
                cur.gotoEndOfUsedArea(True)
                cnt = UzLO_CellRange(cur, f, t)
            Else
                cnt = UzLO_CellRange(sel, f, t)
            End If
        Else
            cnt = UzLO_CellRange(sel, f, t)
        End If
    End If
    UzLO_Calc = cnt
End Function

' ---- Impress / Draw ----
Private Function UzLO_Shapes(ByVal container As Object, ByVal f As String, ByVal t As String) As Long
    Dim i As Long, r As Long, c As Long, shp As Object, model As Object, cnt As Long
    For i = 0 To container.getCount() - 1
        Set shp = container.getByIndex(i)
        If shp.supportsService("com.sun.star.drawing.GroupShape") Then
            cnt = cnt + UzLO_Shapes(shp, f, t)
        ElseIf shp.supportsService("com.sun.star.drawing.TableShape") Then
            Set model = shp.Model
            For r = 0 To model.RowCount - 1
                For c = 0 To model.ColumnCount - 1
                    cnt = cnt + UzLO_XText(model.getCellByPosition(c, r), f, t)
                Next
            Next
        ElseIf shp.supportsService("com.sun.star.drawing.Text") Then
            cnt = cnt + UzLO_XText(shp, f, t)
        End If
    Next
    UzLO_Shapes = cnt
End Function

Private Function UzLO_Draw(ByVal doc As Object, ByVal f As String, ByVal t As String) As Long
    Dim pages As Object, pg As Object, np As Object, i As Long, cnt As Long
    Set pages = doc.getDrawPages()
    For i = 0 To pages.getCount() - 1
        Set pg = pages.getByIndex(i)
        cnt = cnt + UzLO_Shapes(pg, f, t)
        On Error Resume Next
        Set np = pg.getNotesPage()
        If Not IsNull(np) Then cnt = cnt + UzLO_Shapes(np, f, t)
        On Error GoTo 0
    Next
    UzLO_Draw = cnt
End Function
