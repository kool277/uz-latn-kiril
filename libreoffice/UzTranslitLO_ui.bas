' =====================================================================================
'  LibreOffice UI (Writer, Calc, Impress, Draw) -- appended to the shared engine by tools/make_lo_basic.py
'  Tools -> Macros -> Run Macro -> Standard -> UzTranslitLO -> UzLO_LatToNew (etc.)
'  Selection if any, otherwise the whole document. Each paragraph is converted as one string, so a word split
'  across differently formatted portions keeps its context (casing, e/ye, digraphs, dictionary), and the result is
'  split back over the portions, which keep their formatting. "Auto" detects the script once per run.
'  Set UZT_QUIET=1 in soffice's environment for unattended runs: no message boxes.
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

' Writer text positions are live: they move with edits (one that sits exactly where text is inserted moves past it),
' and Writer text is rewritten front to back. The text of cells and shapes (EditEngine) is addressed by plain
' indices, which go stale when earlier text changes length: it is rewritten back to front.
Private mWriter As Boolean

Private Function UzLO_Quiet() As Boolean
    UzLO_Quiet = (Environ("UZT_QUIET") = "1")
End Function

Private Sub UzLO_Run(ByVal f As String, ByVal t As String)
    Dim doc As Object, um As Object, cnt As Long, kind As Integer, recWas As Boolean, calcWas As Boolean
    Dim errNo As Long, errMsg As String
    Set doc = ThisComponent
    If doc.supportsService("com.sun.star.text.TextDocument") Then
        kind = 1
    ElseIf doc.supportsService("com.sun.star.sheet.SpreadsheetDocument") Then
        kind = 2
    ElseIf doc.supportsService("com.sun.star.drawing.DrawingDocument") Or doc.supportsService("com.sun.star.presentation.PresentationDocument") Then
        kind = 3
    Else
        If Not UzLO_Quiet() Then MsgBox "UzTranslit: unsupported document type", 48, "UzTranslit"
        Exit Sub
    End If
    mWriter = (kind = 1)
    UzLO_LoadSettings
    ' one undo step for the whole run, and no layout after every change (that alone makes long paragraphs 30x slower);
    ' tracked changes would keep every old word next to its conversion, formulas need not recalculate per cell
    On Error Resume Next
    Set um = doc.getUndoManager()
    um.enterUndoContext("UzTranslit")
    doc.lockControllers()
    If kind = 1 Then recWas = doc.RecordChanges: doc.RecordChanges = False
    If kind = 2 Then calcWas = doc.isAutomaticCalculationEnabled(): doc.enableAutomaticCalculation(False)
    On Error GoTo failed
    Select Case kind
        Case 1: cnt = UzLO_Writer(doc, f, t)
        Case 2: cnt = UzLO_Calc(doc, f, t)
        Case 3: cnt = UzLO_Draw(doc, f, t)
    End Select
cleanup:
    On Error Resume Next
    If kind = 1 Then doc.RecordChanges = recWas
    If kind = 2 Then doc.enableAutomaticCalculation(calcWas)
    doc.unlockControllers()
    um.leaveUndoContext()
    On Error GoTo 0
    If errNo <> 0 Then Err.Raise errNo, "UzTranslit", errMsg
    If Not UzLO_Quiet() Then MsgBox "UzTranslit: " & cnt & " fragment(s) converted (" & f & " -> " & t & ")", 64, "UzTranslit"
    Exit Sub
failed:
    errNo = Err: errMsg = Error$
    Resume cleanup
End Sub

' "auto" becomes the script of the text the run will convert (one decision for the whole run)
Private Function UzLO_Resolve(ByVal f As String, ByVal sample As String) As String
    If f = "auto" Then UzLO_Resolve = UzDetect(Left$(sample, 200000)) Else UzLO_Resolve = f
End Function

' ---- shared: every paragraph of an XText (and the text tables inside Writer text) ----
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

' One paragraph = one string. Portions that are not text stand for a boundary (fields, footnote anchors, frames)
' or for nothing (bookmarks and other invisible marks, which may sit inside a word). UzSplitConvert splits the
' converted paragraph back over the portions.
Private Function UzLO_Paragraph(ByVal para As Object, ByVal f As String, ByVal t As String) As Long
    Dim pe As Object, por As Object, kind As String, n As Long, i As Long, k As Long, cnt As Long
    Dim pors() As Object, texts() As String, isText() As Boolean, outs() As String
    ReDim pors(0 To 15): ReDim texts(0 To 15): ReDim isText(0 To 15)
    Set pe = para.createEnumeration()
    Do While pe.hasMoreElements()
        Set por = pe.nextElement()
        kind = ""
        On Error Resume Next
        kind = por.TextPortionType
        On Error GoTo 0
        If n > UBound(pors) Then
            ReDim Preserve pors(0 To 2 * n): ReDim Preserve texts(0 To 2 * n): ReDim Preserve isText(0 To 2 * n)
        End If
        Set pors(n) = por
        isText(n) = False
        Select Case kind
            Case "Text", ""
                isText(n) = True
                texts(n) = por.getString()
            Case "Bookmark", "ReferenceMark", "DocumentIndexMark", "Redline", "SoftPageBreak", "InContentMetadata", "AnnotationEnd", "ContentControl"
                texts(n) = ""
            Case "Annotation"
                texts(n) = ""
                cnt = cnt + UzLO_Annotation(por, f, t)
            Case Else
                texts(n) = ChrW(&HFFFC&)
        End Select
        n = n + 1
    Loop
    If n > 0 Then
        UzSplitConvert texts, outs, 0, n - 1, f, t
        For k = 0 To n - 1
            If mWriter Then i = k Else i = n - 1 - k
            If isText(i) Then
                If outs(i) <> texts(i) Then
                    UzLO_ReplacePortion pors(i), outs(i)
                    cnt = cnt + 1
                End If
            End If
        Next
    End If
    UzLO_Paragraph = cnt
End Function

' A Writer comment: its text is converted, its author and date are not.
Private Function UzLO_Annotation(ByVal por As Object, ByVal f As String, ByVal t As String) As Long
    Dim fld As Object, s As String, conv As String
    On Error GoTo done
    Set fld = por.TextField
    s = fld.Content
    If Len(s) > 0 Then
        conv = UzConvert(s, f, t)
        If conv <> s Then fld.Content = conv: UzLO_Annotation = 1
    End If
done:
End Function

' The new text goes where it takes the portion's own attributes, then the old text goes: no attribute is copied,
' which keeps every one of them (styles, language, effects) and is 10x faster than saving and restoring them.
' Writer: text added where a portion ends takes the neighbour's attributes, so the new text goes in after the first
' character and the old characters around it are removed; a hyperlink does not grow over text added at its end,
' so a link gets its address back if it lost it. Cells and shapes: text added at the end of a portion takes its
' attributes, and the portion's old range still holds the old text.
Private Sub UzLO_ReplacePortion(ByVal por As Object, ByVal conv As String)
    Dim xt As Object, cur As Object, url As String, target As String, nm As String
    Set xt = por.getText()
    If Not mWriter Then
        xt.insertString(xt.createTextCursorByRange(por.getEnd()), conv, False)
        xt.createTextCursorByRange(por).setString("")
        Exit Sub
    End If
    On Error Resume Next
    url = por.HyperLinkURL: target = por.HyperLinkTarget: nm = por.HyperLinkName
    On Error GoTo 0
    Set cur = xt.createTextCursorByRange(por.getStart())
    cur.goRight(1, False)
    xt.insertString(cur, conv, False)                      ' the cursor moves on past the new text
    cur.gotoRange(por.getEnd(), True)
    cur.setString("")                                      ' the old text after the new
    Set cur = xt.createTextCursorByRange(por.getStart())
    cur.goRight(1, True)
    cur.setString("")                                      ' the old first character
    If url <> "" Then
        Set cur = xt.createTextCursorByRange(por)
        If cur.HyperLinkURL <> url Then
            cur.HyperLinkURL = url: cur.HyperLinkTarget = target: cur.HyperLinkName = nm
        End If
    End If
End Sub

' ---- Writer ----
Private Function UzLO_Writer(ByVal doc As Object, ByRef f As String, ByVal t As String) As Long
    Dim sel As Object, rng As Object, i As Long, cnt As Long, sample As String
    Dim ranges() As Object, nr As Long
    Dim frames As Object, notes As Object, styles As Object, ps As Object
    ReDim ranges(0 To 0)
    On Error Resume Next
    Set sel = doc.CurrentController.getSelection()
    On Error GoTo 0
    If Not IsNull(sel) Then
        If sel.supportsService("com.sun.star.text.TextRanges") Then
            For i = 0 To sel.getCount() - 1
                Set rng = sel.getByIndex(i)
                If Len(rng.getString()) > 0 Then
                    ReDim Preserve ranges(0 To nr)
                    Set ranges(nr) = rng
                    nr = nr + 1
                    sample = sample & rng.getString() & Chr(10)
                End If
            Next
        End If
    End If
    If nr > 0 Then
        f = UzLO_Resolve(f, sample)
        For i = 0 To nr - 1
            cnt = cnt + UzLO_XText(ranges(i).getText().createTextCursorByRange(ranges(i)), f, t)
        Next
        UzLO_Writer = cnt
        Exit Function
    End If
    f = UzLO_Resolve(f, doc.getText().getString())
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
Private Function UzLO_CellText(ByVal rng As Object) As String
    Dim en As Object, s As String
    Set en = rng.queryContentCells(4).getCells().createEnumeration()   ' com.sun.star.sheet.CellFlags.STRING
    Do While en.hasMoreElements() And Len(s) < 200000
        s = s & en.nextElement().getString() & Chr(10)
    Loop
    UzLO_CellText = s
End Function

Private Function UzLO_CellRange(ByVal rng As Object, ByVal f As String, ByVal t As String) As Long
    Dim en As Object, cnt As Long
    Set en = rng.queryContentCells(4).getCells().createEnumeration()
    Do While en.hasMoreElements()
        cnt = cnt + UzLO_XText(en.nextElement(), f, t)   ' paragraph by paragraph: rich text in a cell keeps its formatting
    Loop
    UzLO_CellRange = cnt + UzLO_Comments(rng, f, t)
End Function

' cell comments inside the range (their authors are not touched)
Private Function UzLO_Comments(ByVal rng As Object, ByVal f As String, ByVal t As String) As Long
    Dim anns As Object, a As Object, i As Long, cnt As Long, addr As Object, pos As Object, s As String, conv As String
    On Error GoTo done
    Set addr = rng.getRangeAddress()
    Set anns = rng.getSpreadsheet().getAnnotations()
    For i = 0 To anns.getCount() - 1
        Set a = anns.getByIndex(i)
        Set pos = a.getPosition()
        If pos.Column >= addr.StartColumn And pos.Column <= addr.EndColumn And pos.Row >= addr.StartRow And pos.Row <= addr.EndRow Then
            s = a.getString()
            conv = UzConvert(s, f, t)
            If conv <> s Then a.setString(conv): cnt = cnt + 1
        End If
    Next
done:
    UzLO_Comments = cnt
End Function

Private Function UzLO_Calc(ByVal doc As Object, ByRef f As String, ByVal t As String) As Long
    Dim sel As Object, cur As Object, i As Long, cnt As Long, single As Boolean, sample As String
    Dim targets() As Object, nt As Long
    ReDim targets(0 To 0)
    Set sel = doc.CurrentSelection
    If sel.supportsService("com.sun.star.sheet.SheetCellRanges") Then
        For i = 0 To sel.getCount() - 1
            ReDim Preserve targets(0 To nt)
            Set targets(nt) = sel.getByIndex(i)
            nt = nt + 1
        Next
    ElseIf sel.supportsService("com.sun.star.sheet.SheetCellRange") Then
        single = (sel.getRows().getCount() = 1 And sel.getColumns().getCount() = 1)
        Set targets(0) = sel
        nt = 1
        If single And Not UzLO_Quiet() Then
            If MsgBox("Convert the whole sheet? (No = only the selected cell)", 36, "UzTranslit") = 6 Then
                Set cur = doc.CurrentController.getActiveSheet().createCursor()
                cur.gotoStartOfUsedArea(False)
                cur.gotoEndOfUsedArea(True)
                Set targets(0) = cur
            End If
        End If
    End If
    For i = 0 To nt - 1
        sample = sample & UzLO_CellText(targets(i))
    Next
    f = UzLO_Resolve(f, sample)
    For i = 0 To nt - 1
        cnt = cnt + UzLO_CellRange(targets(i), f, t)
    Next
    UzLO_Calc = cnt
End Function

' ---- Impress / Draw ----
Private Function UzLO_ShapesText(ByVal container As Object) As String
    Dim i As Long, shp As Object, s As String
    For i = 0 To container.getCount() - 1
        Set shp = container.getByIndex(i)
        If shp.supportsService("com.sun.star.drawing.GroupShape") Then
            s = s & UzLO_ShapesText(shp)
        ElseIf shp.supportsService("com.sun.star.drawing.Text") Then
            s = s & shp.getString() & Chr(10)
        End If
    Next
    UzLO_ShapesText = s
End Function

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

Private Function UzLO_Draw(ByVal doc As Object, ByRef f As String, ByVal t As String) As Long
    Dim pages As Object, pg As Object, np As Object, i As Long, cnt As Long, sample As String
    Set pages = doc.getDrawPages()
    For i = 0 To pages.getCount() - 1
        sample = sample & UzLO_ShapesText(pages.getByIndex(i))
    Next
    f = UzLO_Resolve(f, sample)
    For i = 0 To pages.getCount() - 1
        Set pg = pages.getByIndex(i)
        cnt = cnt + UzLO_Shapes(pg, f, t)
        On Error Resume Next
        Set np = Nothing
        Set np = pg.getNotesPage()
        If Not IsNull(np) Then cnt = cnt + UzLO_Shapes(np, f, t)
        On Error GoTo 0
    Next
    UzLO_Draw = cnt
End Function

' ---- settings: /uz.jaybi.UzTranslit/Settings, LibreOffice's configuration (UzTranslit.xcs in the extension) ----
Private Function UzLO_Config(ByVal forUpdate As Boolean) As Object
    Dim cp As Object, arg As New com.sun.star.beans.PropertyValue
    Set cp = createUnoService("com.sun.star.configuration.ConfigurationProvider")
    arg.Name = "nodepath": arg.Value = "/uz.jaybi.UzTranslit/Settings"
    If forUpdate Then
        Set UzLO_Config = cp.createInstanceWithArguments("com.sun.star.configuration.ConfigurationUpdateAccess", Array(arg))
    Else
        Set UzLO_Config = cp.createInstanceWithArguments("com.sun.star.configuration.ConfigurationAccess", Array(arg))
    End If
End Function

' the saved settings become the engine's options (the defaults stay when the module runs without the extension)
Public Sub UzLO_LoadSettings()
    Dim c As Object
    On Error GoTo none
    Set c = UzLO_Config(False)
    UzOptAscii = c.Ascii
    UzOptNoDictionary = Not c.Dictionary
    UzOptKeepHardSignAfterO = c.KeepHardSignAfterO
    UzOptNoTsFinal = Not c.TsFinal
    UzOptNoSkipUrls = Not c.SkipUrls
none:
End Sub

Private Function UzLO_SettingKeys() As Variant
    UzLO_SettingKeys = Array("Ascii", "Dictionary", "KeepHardSignAfterO", "TsFinal", "SkipUrls")
End Function

' "uz", "ru" or "en": LibreOffice's user interface language
Private Function UzLO_Lang() As String
    Dim cp As Object, arg As New com.sun.star.beans.PropertyValue, s As String
    On Error GoTo done
    Set cp = createUnoService("com.sun.star.configuration.ConfigurationProvider")
    arg.Name = "nodepath": arg.Value = "/org.openoffice.Setup/L10N"
    s = LCase(cp.createInstanceWithArguments("com.sun.star.configuration.ConfigurationAccess", Array(arg)).ooLocale)
done:
    If Left(s, 2) = "uz" Then
        UzLO_Lang = "uz"
    ElseIf Left(s, 2) = "ru" Then
        UzLO_Lang = "ru"
    Else
        UzLO_Lang = "en"
    End If
End Function

' the settings dialog with the saved values, not shown yet (tests fill and save it without showing it)
Public Function UzLO_SettingsDialog() As Object
    Dim dm As Object, dlg As Object, c As Object, keys As Variant, i As Integer, cfg As Object, lang As String
    keys = UzLO_SettingKeys()
    lang = UzLO_Lang()
    Set dm = createUnoService("com.sun.star.awt.UnoControlDialogModel")
    dm.Width = 250: dm.Height = 124: dm.Title = UzLO_Text(lang, "title")
    For i = 0 To UBound(keys)
        Set c = dm.createInstance("com.sun.star.awt.UnoControlCheckBoxModel")
        c.PositionX = 8: c.PositionY = 8 + i * 16: c.Width = 234: c.Height = 12
        c.Label = UzLO_Text(lang, keys(i))
        dm.insertByName(keys(i), c)
    Next
    Set c = dm.createInstance("com.sun.star.awt.UnoControlButtonModel")
    c.PositionX = 132: c.PositionY = 102: c.Width = 54: c.Height = 15: c.PushButtonType = 1: c.DefaultButton = True
    c.Label = UzLO_Text(lang, "ok")
    dm.insertByName("OK", c)
    Set c = dm.createInstance("com.sun.star.awt.UnoControlButtonModel")
    c.PositionX = 190: c.PositionY = 102: c.Width = 54: c.Height = 15: c.PushButtonType = 2
    c.Label = UzLO_Text(lang, "cancel")
    dm.insertByName("Cancel", c)
    Set dlg = createUnoService("com.sun.star.awt.UnoControlDialog")
    dlg.setModel(dm)
    On Error Resume Next
    Set cfg = UzLO_Config(False)
    For i = 0 To UBound(keys)
        If cfg.getByName(keys(i)) Then dlg.getControl(keys(i)).State = 1 Else dlg.getControl(keys(i)).State = 0
    Next
    Set UzLO_SettingsDialog = dlg
End Function

Public Sub UzLO_SettingsSave(dlg As Object)
    Dim cfg As Object, keys As Variant, i As Integer
    keys = UzLO_SettingKeys()
    Set cfg = UzLO_Config(True)
    For i = 0 To UBound(keys)
        cfg.replaceByName(keys(i), dlg.getControl(keys(i)).State = 1)
    Next
    cfg.commitChanges()
    UzLO_LoadSettings
End Sub

' Tools > UzTranslit > Settings...
Public Sub UzLO_Settings()
    Dim dlg As Object
    Set dlg = UzLO_SettingsDialog()
    dlg.createPeer(createUnoService("com.sun.star.awt.Toolkit"), Null)
    If dlg.execute() = 1 Then UzLO_SettingsSave dlg
    dlg.dispose()
End Sub

' @UZLO_TEXT@ (the dialog's texts in three languages: generated by tools/make_lo_basic.py)
