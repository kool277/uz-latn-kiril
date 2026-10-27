Attribute VB_Name = "UzTranslit"
Option Explicit
Option Compare Binary
' =====================================================================================
'  UzTranslit v1.1.0 -- O'zbek alifbo konvertori for Microsoft Office 97 ... 2026
'  Word, Excel, PowerPoint (Windows and Mac). One module, no references, pure VBA 5/6/7.
'
'  Scripts:  "cyr"  Kirill / Cyrillic (1940)
'            "lat"  Lotin 1995  (O' G' Sh Ch Ng)
'            "new"  Lotin 2026  (O-umlaut, G-breve, S-cedilla, C-cedilla) -- Qonun O'RQ-1184, 21.10.2026
'            "auto" detect
'
'  INSTALL:  Alt+F11 -> File -> Import File... -> UzTranslit.bas -> save the document / Normal.dotm /
'            PERSONAL.XLSB.  Then Alt+F8 and run e.g. UzTranslit_LatToNew, or put the macros on a
'            toolbar / Quick Access Toolbar / ribbon.  Excel formulas: =UzConvert(A1,"lat","new")
'
'  Everything non-ASCII is built with ChrW so the module survives any VBE code page.
'  Conforms to spec/SPEC.md and passes spec/fixtures.json (see tests/vba_selftest below: UzSelfTest).
' =====================================================================================

' ---------- options (defaults = spec defaults; False = default) ----------
Public UzOptAscii As Boolean            ' True: use ' instead of U+02BB / U+02BC in Latin output
Public UzOptKeepHardSignAfterO As Boolean ' True: Cyrillic hard sign after short u stays (mu'jiza keeps the tutuq); default drops it
Public UzOptNoTsFinal As Boolean        ' True: never turn word-final "ts" into Cyrillic tse
Public UzOptNoDictionary As Boolean     ' True: skip the loanword dictionary
Public UzOptNoSkipUrls As Boolean       ' True: also convert URLs, e-mail addresses and @handles (default keeps them)

' ---------- internal tables ----------
Private mInit As Boolean
Private mCyrLower As String, mCyrUpper As String
Private mLatLower As String, mLatUpper As String
Private mApos As String, mCyrVowels As String, mLatVowels As String
Private mDictKey() As String, mDictVal() As String, mDictN As Long

Private Const OKINA As Long = &H2BB      ' U+02BB okina
Private Const TUTUQ As Long = &H2BC      ' U+02BC tutuq

' =====================================================================================
'  PUBLIC API
' =====================================================================================
' A UTF-16 code unit as 0..65535. VBA's AscW returns -32768..-1 for U+8000..U+FFFF (emoji halves, CJK, BOM),
' LibreOffice Basic returns 32768..65535; both end up here as the same positive Long.
Private Function CodeAt(ByVal s As String, ByVal i As Long) As Long
    CodeAt = AscW(Mid$(s, i, 1))
    If CodeAt < 0 Then CodeAt = CodeAt + 65536
End Function

Public Function UzConvert(ByVal Text As String, ByVal FromScript As String, ByVal ToScript As String) As String
    UzInit
    FromScript = LCase$(FromScript): ToScript = LCase$(ToScript)
    If FromScript = "auto" Then FromScript = UzDetect(Text)
    If FromScript = ToScript Then UzConvert = Text: Exit Function
    If Not ((FromScript = "cyr" And (ToScript = "lat" Or ToScript = "new")) _
        Or ((FromScript = "lat" Or FromScript = "new") And ToScript = "cyr") _
        Or (FromScript = "lat" And ToScript = "new") Or (FromScript = "new" And ToScript = "lat")) Then
        Err.Raise 5, "UzTranslit", "Unknown direction " & FromScript & " -> " & ToScript
    End If
    If UzOptNoSkipUrls Then
        UzConvert = ConvertSlice(Text, FromScript, ToScript)
    Else
        UzConvert = WithSkips(Text, FromScript, ToScript)
    End If
End Function

Public Function UzCyrToLat(ByVal Text As String) As String
    UzCyrToLat = UzConvert(Text, "cyr", "lat")
End Function
Public Function UzCyrToNew(ByVal Text As String) As String
    UzCyrToNew = UzConvert(Text, "cyr", "new")
End Function
Public Function UzLatToCyr(ByVal Text As String) As String
    UzLatToCyr = UzConvert(Text, "lat", "cyr")
End Function
Public Function UzNewToCyr(ByVal Text As String) As String
    UzNewToCyr = UzConvert(Text, "new", "cyr")
End Function
Public Function UzLatToNew(ByVal Text As String) As String
    UzLatToNew = UzConvert(Text, "lat", "new")
End Function
Public Function UzNewToLat(ByVal Text As String) As String
    UzNewToLat = UzConvert(Text, "new", "lat")
End Function

Public Function UzDetect(ByVal Text As String) As String
    Dim i As Long, n As Long, c As Long, L As Long, N2 As Long
    Dim cyr As Long, lat As Long, nw As Long, dig As Long
    UzInit
    n = Len(Text)
    For i = 1 To n
        c = CodeAt(Text, i)
        If IsCyr(c) Then
            cyr = cyr + 1
        ElseIf IsLat(c) Then
            lat = lat + 1
            L = LatLower(c)
            If L = &HF6 Or L = &H11F Or L = &H15F Or L = &HE7 Or L = &H14D Or L = &HF5 Then nw = nw + 1
            N2 = 0: If i < n Then N2 = LatLower(CodeAt(Text, i + 1))
            If (L = 115 Or L = 99) And N2 = 104 Then dig = dig + 1          ' sh ch
            If (L = 111 Or L = 103) And IsApos(N2) Then dig = dig + 1       ' o' g'
        End If
    Next
    If cyr > lat Then
        UzDetect = "cyr"
    ElseIf nw > 0 And nw >= dig Then
        UzDetect = "new"
    Else
        UzDetect = "lat"
    End If
End Function

' Converts the joined pieces(lo..hi) as one string and splits the result back over the pieces into outs(lo..hi), for
' text that formatting cuts into runs: a word half bold, half plain still converts as one word, and the joined outs
' are always exactly UzConvert of the joined pieces. A cut lands where the conversion of the text before it ends. No
' rule looks across whitespace, so only the part of the word up to the cut is converted again, and a paragraph of
' thousands of runs stays linear. Where a rule looks across a cut inside a word, a letter may move to the next piece.
Public Sub UzSplitConvert(pieces() As String, outs() As String, ByVal lo As Long, ByVal hi As Long, ByVal f As String, ByVal t As String)
    Dim P As String, Q As String, i As Long, b As Long, w As Long, safe As Long, safeLen As Long, sPrev As Long, sCur As Long
    If hi < lo Then Exit Sub
    ReDim outs(lo To hi)
    For i = lo To hi
        P = P & pieces(i)
    Next
    If LCase$(f) = "auto" Then f = UzDetect(P)
    Q = UzConvert(P, f, t)
    If Q = P Then
        For i = lo To hi
            outs(i) = pieces(i)
        Next
        Exit Sub
    End If
    For i = lo To hi
        b = b + Len(pieces(i))
        If i = hi Then
            sCur = Len(Q)
        Else
            w = b                                          ' last whitespace before the cut, if after the last one known
            Do While w > safe
                If IsJsSpace(CodeAt(P, w)) Then Exit Do
                w = w - 1
            Loop
            If w > safe Then
                safeLen = safeLen + Len(UzConvert(Mid$(P, safe + 1, w - safe), f, t))
                safe = w
            End If
            sCur = safeLen
            If b > safe Then sCur = sCur + Len(UzConvert(Mid$(P, safe + 1, b - safe), f, t))
            If sCur > Len(Q) Then sCur = Len(Q)
        End If
        If sCur < sPrev Then sCur = sPrev
        outs(i) = Mid$(Q, sPrev + 1, sCur - sPrev)
        sPrev = sCur
    Next
End Sub

' =====================================================================================
'  DOCUMENT MACROS (Alt+F8). Selection if any, otherwise the whole document / sheet / deck.
' =====================================================================================
Public Sub UzTranslit_CyrToLat()
    UzDoc_Run "cyr", "lat"
End Sub
Public Sub UzTranslit_CyrToNew()
    UzDoc_Run "cyr", "new"
End Sub
Public Sub UzTranslit_LatToCyr()
    UzDoc_Run "lat", "cyr"
End Sub
Public Sub UzTranslit_NewToCyr()
    UzDoc_Run "new", "cyr"
End Sub
Public Sub UzTranslit_LatToNew()
    UzDoc_Run "lat", "new"
End Sub
Public Sub UzTranslit_NewToLat()
    UzDoc_Run "new", "lat"
End Sub
Public Sub UzTranslit_AutoToNew()
    UzDoc_Run "auto", "new"
End Sub
Public Sub UzTranslit_AutoToLat()
    UzDoc_Run "auto", "lat"
End Sub
Public Sub UzTranslit_AutoToCyr()
    UzDoc_Run "auto", "cyr"
End Sub

Private Sub UzDoc_Run(ByVal f As String, ByVal t As String)
    Dim app As Object, host As String, cnt As Long
    Set app = Application
    host = app.Name
    If InStr(1, host, "Word", vbTextCompare) > 0 Then
        cnt = UzWord_Run(app, f, t)
    ElseIf InStr(1, host, "Excel", vbTextCompare) > 0 Then
        cnt = UzExcel_Run(app, f, t)
    ElseIf InStr(1, host, "PowerPoint", vbTextCompare) > 0 Then
        cnt = UzPpt_Run(app, f, t)
    Else
        MsgBox "UzTranslit: this host (" & host & ") is not supported. Use the UzConvert() function instead.", vbExclamation, "UzTranslit"
        Exit Sub
    End If
    MsgBox "UzTranslit: " & cnt & " fragment(s) converted  (" & f & " -> " & t & ")", vbInformation, "UzTranslit"
End Sub

' ---------- Word: every story (body, headers, footers, footnotes, text boxes...), formatting kept ----------
Private Function UzWord_Run(ByVal app As Object, ByVal f As String, ByVal t As String) As Long
    Dim doc As Object, sel As Object, rng As Object, story As Object, undoRec As Object
    Dim trackWas As Boolean, hiddenWas As Boolean, cnt As Long, errNo As Long, errDesc As String
    Set doc = app.ActiveDocument
    Set sel = app.Selection
    On Error Resume Next
    Set undoRec = app.UndoRecord                           ' Word 2010 and later: the whole run is one undo step
    undoRec.StartCustomRecord "UzTranslit"
    app.ScreenUpdating = False
    trackWas = doc.TrackRevisions
    doc.TrackRevisions = False
    hiddenWas = doc.Bookmarks.ShowHidden
    doc.Bookmarks.ShowHidden = True                        ' hidden bookmarks (_Toc..., _Ref...) are kept too
    On Error GoTo failed
    If f = "auto" Then                                     ' one decision for the whole run
        If sel.Type = 2 Then f = UzDetect(Left$(sel.Range.Text, 200000)) Else f = UzDetect(Left$(doc.Content.Text, 200000))
    End If
    If sel.Type = 2 Then                                   ' wdSelectionNormal = text selected
        cnt = UzWord_Range(doc, sel.Range, f, t)
    Else
        For Each story In doc.StoryRanges
            Set rng = story
            Do
                cnt = cnt + UzWord_Range(doc, rng, f, t)
                Set rng = rng.NextStoryRange
            Loop Until rng Is Nothing
        Next
    End If
cleanup:
    On Error Resume Next
    doc.Bookmarks.ShowHidden = hiddenWas
    doc.TrackRevisions = trackWas
    app.ScreenUpdating = True
    undoRec.EndCustomRecord
    On Error GoTo 0
    If errNo <> 0 Then Err.Raise errNo, "UzTranslit", errDesc
    UzWord_Run = cnt
    Exit Function
failed:
    errNo = Err.Number: errDesc = Err.Description
    Resume cleanup
End Function

' paragraph by paragraph: one formatting -> rewritten at once, mixed formatting -> run by run
Private Function UzWord_Range(ByVal doc As Object, ByVal rng As Object, ByVal f As String, ByVal t As String) As Long
    Dim para As Object, r As Object, cnt As Long, s As String, conv As String
    Dim pStart As Long, pEnd As Long
    For Each para In rng.Paragraphs
        pStart = para.Range.Start: pEnd = para.Range.End
        If pStart < rng.Start Then pStart = rng.Start
        If pEnd > rng.End Then pEnd = rng.End
        If pEnd > pStart Then
            Set r = para.Range.Duplicate          ' stays inside the paragraph's story (header, footnote, text box...)
            r.SetRange pStart, pEnd
            ' drop the paragraph / cell end marks from the range
            Do While r.End > r.Start
                s = r.Text
                If Len(s) = 0 Then Exit Do
                If Right$(s, 1) = Chr$(13) Or Right$(s, 1) = Chr$(7) Then r.End = r.End - 1 Else Exit Do
            Loop
            If r.End > r.Start Then
                If UzWord_IsUniform(r) Then
                    s = r.Text
                    conv = UzConvert(s, f, t)
                    If conv <> s Then UzWord_SetText doc, r, s, conv, f, t: cnt = cnt + 1
                Else
                    cnt = cnt + UzWord_Runs(doc, r, f, t)
                End If
            End If
        End If
    Next
    UzWord_Range = cnt
End Function

' one formatting, and nothing that rewriting the text would destroy
Private Function UzWord_IsUniform(ByVal r As Object) As Boolean
    Dim ok As Boolean
    On Error GoTo bad
    ok = (r.Fields.Count = 0) And (r.Hyperlinks.Count = 0) And (r.InlineShapes.Count = 0) And (UzWord_CCCount(r) = 0)
    If ok Then ok = UzWord_Plain(r.Text)
    If ok Then ok = (r.Font.Name <> "") And (r.Font.Size <> 9999999) And (r.Font.Bold <> 9999999) _
        And (r.Font.Italic <> 9999999) And (r.Font.Underline <> 9999999) And (r.Font.ColorIndex <> 9999999) _
        And (r.Font.Superscript <> 9999999) And (r.Font.Subscript <> 9999999) And (r.Font.Hidden <> 9999999) _
        And (r.HighlightColorIndex <> 9999999)
    UzWord_IsUniform = ok
    Exit Function
bad:
    UzWord_IsUniform = False
End Function

Private Function UzWord_CCCount(ByVal r As Object) As Long
    On Error Resume Next
    UzWord_CCCount = r.ContentControls.Count               ' Word 2007 and later; none before
End Function

' False when the text holds one of Word's special characters (picture, footnote or comment mark, field brace...)
Private Function UzWord_Plain(ByVal s As String) As Boolean
    Dim i As Long, c As Long
    For i = 1 To Len(s)
        c = CodeAt(s, i)
        If c < 32 And c <> 9 And c <> 11 Then Exit Function
    Next
    UzWord_Plain = True
End Function

Private Function UzWord_FontKey(ByVal ch As Object) As String
    On Error Resume Next
    With ch.Font
        UzWord_FontKey = .Name & "|" & .Size & "|" & .Bold & "|" & .Italic & "|" & .Underline & "|" & .ColorIndex & _
            "|" & .Superscript & "|" & .Subscript & "|" & .Hidden & "|" & ch.HighlightColorIndex
    End With
End Function

' mixed formatting: the paragraph is converted as one string (a word split across bold/plain runs keeps its context)
' and split back over its runs of identical formatting, rewritten back to front so positions stay valid. Fields,
' hyperlinks, pictures, content controls and special characters are never rewritten: they are runs of their own,
' which stand for a word boundary (an optional hyphen inside a word does not). Hyperlink texts are converted on
' their own afterwards, so the links keep their addresses.
Private Function UzWord_Runs(ByVal doc As Object, ByVal r As Object, ByVal f As String, ByVal t As String) As Long
    Dim ch As Object, hl As Object, rr As Object, key As String, prevKey As String, s As String, conv As String
    Dim cs As Long, code As Long, k As Long, prot As Boolean, soft As Boolean
    Dim starts() As Long, ends() As Long, isText() As Boolean, allSoft() As Boolean, texts() As String, outs() As String
    Dim spanS() As Long, spanE() As Long, nSpan As Long, nRuns As Long, i As Long, cnt As Long
    UzWord_Spans r, spanS, spanE, nSpan
    ReDim starts(0 To 64): ReDim ends(0 To 64): ReDim isText(0 To 64): ReDim allSoft(0 To 64)
    prevKey = vbNullChar & "none"
    For Each ch In r.Characters
        cs = ch.Start
        s = ch.Text
        prot = False: soft = False
        If Len(s) > 0 Then
            code = CodeAt(s, 1)
            If code < 32 And code <> 9 And code <> 11 Then prot = True: soft = (code = 31)
        End If
        If Not prot Then
            For k = 1 To nSpan
                If cs >= spanS(k) And cs < spanE(k) Then prot = True: Exit For
            Next
        End If
        If prot Then key = vbNullChar Else key = UzWord_FontKey(ch)
        If key <> prevKey Then
            nRuns = nRuns + 1
            If nRuns > UBound(starts) Then
                ReDim Preserve starts(0 To 2 * nRuns): ReDim Preserve ends(0 To 2 * nRuns)
                ReDim Preserve isText(0 To 2 * nRuns): ReDim Preserve allSoft(0 To 2 * nRuns)
            End If
            starts(nRuns) = cs
            isText(nRuns) = Not prot
            allSoft(nRuns) = True
            prevKey = key
        End If
        If Not soft Then allSoft(nRuns) = False
        ends(nRuns) = ch.End
    Next
    If nRuns = 0 Then Exit Function
    ReDim texts(1 To nRuns)
    For i = 1 To nRuns
        If isText(i) Then
            Set rr = r.Duplicate
            rr.SetRange starts(i), ends(i)
            texts(i) = rr.Text
        ElseIf allSoft(i) Then
            texts(i) = ""                                  ' optional hyphens: invisible, the word goes on
        Else
            texts(i) = ChrW(&HFFFC&)
        End If
    Next
    UzSplitConvert texts, outs, 1, nRuns, f, t
    For i = nRuns To 1 Step -1
        If isText(i) And outs(i) <> texts(i) Then
            Set rr = r.Duplicate
            rr.SetRange starts(i), ends(i)
            UzWord_SetText doc, rr, texts(i), outs(i), f, t
            cnt = cnt + 1
        End If
    Next
    On Error Resume Next
    For Each hl In r.Hyperlinks
        s = "": s = hl.TextToDisplay
        If Len(s) > 0 Then
            conv = UzConvert(s, f, t)
            If conv <> s Then hl.TextToDisplay = conv: cnt = cnt + 1
        End If
    Next
    On Error GoTo 0
    UzWord_Runs = cnt
End Function

' the character ranges that are never rewritten: fields (code and result), hyperlinks, pictures, content controls
Private Sub UzWord_Spans(ByVal r As Object, spanS() As Long, spanE() As Long, nSpan As Long)
    Dim kind As Long
    ReDim spanS(0 To 8): ReDim spanE(0 To 8)
    nSpan = 0
    For kind = 1 To 4
        UzWord_AddSpans r, kind, spanS, spanE, nSpan
    Next
End Sub

Private Sub UzWord_AddSpans(ByVal r As Object, ByVal kind As Long, spanS() As Long, spanE() As Long, nSpan As Long)
    Dim col As Object, i As Long
    On Error GoTo done
    Select Case kind
        Case 1: Set col = r.Fields
        Case 2: Set col = r.Hyperlinks
        Case 3: Set col = r.InlineShapes
        Case Else: Set col = r.ContentControls             ' Word 2007 and later
    End Select
    For i = 1 To col.Count
        UzWord_AddSpan spanS, spanE, nSpan, col(i), kind
    Next
done:
End Sub

Private Sub UzWord_AddSpan(spanS() As Long, spanE() As Long, nSpan As Long, ByVal o As Object, ByVal kind As Long)
    Dim a As Long, b As Long, e As Long
    a = -1: b = -1
    On Error Resume Next
    If kind = 1 Then                                       ' a field: begin mark, code, result, end mark
        a = o.Code.Start - 1: b = o.Code.End + 1
        e = o.Result.End + 1
        If e > b Then b = e
    ElseIf kind = 4 Then                                   ' a content control with its two marks
        a = o.Range.Start - 1: b = o.Range.End + 1
    Else
        a = o.Range.Start: b = o.Range.End
    End If
    On Error GoTo 0
    If a < 0 Or b <= a Then Exit Sub
    nSpan = nSpan + 1
    If nSpan > UBound(spanS) Then ReDim Preserve spanS(0 To 2 * nSpan): ReDim Preserve spanE(0 To 2 * nSpan)
    spanS(nSpan) = a: spanE(nSpan) = b
End Sub

' Range.Text = ... deletes the bookmarks inside the range (a table of contents points at hidden _Toc bookmarks on the
' headings): they are put back over the new text, their ends moved by how the text before them converted
Private Sub UzWord_SetText(ByVal doc As Object, ByVal rr As Object, ByVal oldText As String, ByVal newText As String, ByVal f As String, ByVal t As String)
    Dim bm As Object, br As Object, bmName() As String, bs() As Long, be() As Long, n As Long, i As Long, st As Long
    st = rr.Start
    ReDim bmName(0 To 4): ReDim bs(0 To 4): ReDim be(0 To 4)
    On Error Resume Next
    For Each bm In rr.Bookmarks
        n = n + 1
        If n > UBound(bmName) Then ReDim Preserve bmName(0 To 2 * n): ReDim Preserve bs(0 To 2 * n): ReDim Preserve be(0 To 2 * n)
        bmName(n) = bm.Name: bs(n) = bm.Start - st: be(n) = bm.End - st
    Next
    On Error GoTo 0
    rr.Text = newText
    On Error Resume Next
    For i = 1 To n
        If Not doc.Bookmarks.Exists(bmName(i)) Then
            Set br = rr.Duplicate
            br.SetRange st + UzWord_MapPos(oldText, newText, bs(i), f, t), st + UzWord_MapPos(oldText, newText, be(i), f, t)
            doc.Bookmarks.Add bmName(i), br
        End If
    Next
    On Error GoTo 0
End Sub

' where offset o of oldText ends up in newText
Private Function UzWord_MapPos(ByVal oldText As String, ByVal newText As String, ByVal o As Long, ByVal f As String, ByVal t As String) As Long
    Dim m As Long
    If o <= 0 Then
        m = o
    ElseIf o >= Len(oldText) Then
        m = o + Len(newText) - Len(oldText)
    Else
        m = Len(UzConvert(Left$(oldText, o), f, t))
        If m > Len(newText) Then m = Len(newText)
    End If
    UzWord_MapPos = m
End Function

' ---------- Excel: selected cells (one cell selected -> whole used range), text constants only, rich text kept ----------
Private Function UzExcel_Run(ByVal app As Object, ByVal f As String, ByVal t As String) As Long
    Dim target As Object, txtCells As Object, c As Object, cnt As Long, v As Variant, s As String
    Dim singleCell As Boolean, errNo As Long, errDesc As String
    On Error Resume Next
    Set target = app.Selection
    If TypeName(target) <> "Range" Then Set target = app.ActiveSheet.UsedRange
    If target.Cells.Count = 1 Then
        If MsgBox("Convert the whole sheet? (No = only the selected cell)", vbYesNo + vbQuestion, "UzTranslit") = vbYes Then
            Set target = app.ActiveSheet.UsedRange
        Else
            singleCell = True
        End If
    End If
    Set txtCells = Nothing
    If singleCell Then
        Set txtCells = target                   ' SpecialCells on one cell would expand to the whole sheet
    Else
        Set txtCells = target.SpecialCells(2, 2) ' xlCellTypeConstants, xlTextValues
    End If
    On Error GoTo 0
    If txtCells Is Nothing Then Exit Function
    On Error Resume Next
    app.ScreenUpdating = False
    On Error GoTo failed
    If f = "auto" Then                                     ' one decision for the whole run
        For Each c In txtCells
            v = c.Value
            If VarType(v) = vbString Then s = s & v & vbLf
            If Len(s) > 200000 Then Exit For
        Next
        f = UzDetect(s)
    End If
    For Each c In txtCells
        v = c.Value
        If VarType(v) = vbString Then
            If Not c.HasFormula Then cnt = cnt + UzExcel_Cell(c, CStr(v), f, t)   ' a lone selected cell may hold a formula
        End If
    Next
cleanup:
    On Error Resume Next
    app.ScreenUpdating = True
    On Error GoTo 0
    If errNo <> 0 Then Err.Raise errNo, "UzTranslit", errDesc
    UzExcel_Run = cnt
    Exit Function
failed:
    errNo = Err.Number: errDesc = Err.Description
    Resume cleanup
End Function

Private Function UzExcel_Cell(ByVal c As Object, ByVal s As String, ByVal f As String, ByVal t As String) As Long
    Dim conv As String
    conv = UzConvert(s, f, t)
    If conv = s Then Exit Function
    If UzExcel_IsRich(c, Len(s)) Then
        UzExcel_RichReplace c, s, f, t
    Else
        UzExcel_SetText c, conv
    End If
    UzExcel_Cell = 1
End Function

' the cell held text and keeps holding text: Excel would read a value like "=A1", "Mar 5" or "1e5" as a formula,
' date or number, so such a value gets the apostrophe prefix (which is not part of the text)
Private Sub UzExcel_SetText(ByVal c As Object, ByVal s As String)
    Dim k As String
    k = Left$(s, 1)
    If k = "=" Or k = "+" Or k = "-" Or k = "@" Then
        c.Value = "'" & s
    Else
        c.Value = s
        If Len(s) > 0 Then
            If c.HasFormula Or VarType(c.Value) <> vbString Then c.Value = "'" & s
        End If
    End If
End Sub

' Excel reports Null for a font property that differs inside the cell
Private Function UzExcel_IsRich(ByVal c As Object, ByVal n As Long) As Boolean
    On Error Resume Next
    If n < 2 Then Exit Function
    With c.Font
        UzExcel_IsRich = IsNull(.Bold) Or IsNull(.Italic) Or IsNull(.Underline) Or IsNull(.Color) Or IsNull(.Size) _
            Or IsNull(.Name) Or IsNull(.Strikethrough) Or IsNull(.Superscript) Or IsNull(.Subscript)
    End With
End Function

Private Function UzExcel_FontKey(ByVal fnt As Object) As String
    On Error Resume Next
    UzExcel_FontKey = fnt.Name & "|" & fnt.Size & "|" & fnt.Bold & "|" & fnt.Italic & "|" & fnt.Underline & "|" & fnt.Color & _
        "|" & fnt.Strikethrough & "|" & fnt.Superscript & "|" & fnt.Subscript
End Function

' rich text: each run's font is remembered, the converted text written, and every run's share gets its font back
Private Sub UzExcel_RichReplace(ByVal c As Object, ByVal s As String, ByVal f As String, ByVal t As String)
    Dim n As Long, k As Long, nRuns As Long, key As String, prevKey As String, conv As String
    Dim starts() As Long, lens() As Long, texts() As String, outs() As String, fonts() As Variant
    Dim pos As Long, i As Long, fnt As Object
    n = Len(s)
    ReDim starts(1 To n): ReDim lens(1 To n): ReDim fonts(1 To n)
    prevKey = vbNullChar
    For k = 1 To n
        Set fnt = c.Characters(k, 1).Font
        key = UzExcel_FontKey(fnt)
        If key <> prevKey Then
            nRuns = nRuns + 1
            starts(nRuns) = k
            fonts(nRuns) = Array(fnt.Name, fnt.Size, fnt.Bold, fnt.Italic, fnt.Underline, fnt.Color, fnt.Strikethrough, fnt.Superscript, fnt.Subscript)
            prevKey = key
        End If
        lens(nRuns) = lens(nRuns) + 1
    Next
    ReDim texts(1 To nRuns)
    For i = 1 To nRuns
        texts(i) = Mid$(s, starts(i), lens(i))
    Next
    UzSplitConvert texts, outs, 1, nRuns, f, t
    For i = 1 To nRuns
        conv = conv & outs(i)
    Next
    UzExcel_SetText c, conv
    pos = 1
    For i = 1 To nRuns
        If Len(outs(i)) > 0 Then
            With c.Characters(pos, Len(outs(i))).Font
                .Name = fonts(i)(0): .Size = fonts(i)(1): .Bold = fonts(i)(2): .Italic = fonts(i)(3)
                .Underline = fonts(i)(4): .Color = fonts(i)(5): .Strikethrough = fonts(i)(6)
                .Superscript = fonts(i)(7): .Subscript = fonts(i)(8)
            End With
        End If
        pos = pos + Len(outs(i))
    Next
End Sub

' ---------- PowerPoint: every shape, group, table cell and notes page, formatting kept ----------
Private Function UzPpt_Run(ByVal app As Object, ByVal f As String, ByVal t As String) As Long
    Dim pres As Object, sld As Object, shp As Object, cnt As Long, notes As Object
    Set pres = app.ActivePresentation
    If f = "auto" Then f = UzDetect(Left$(UzPpt_Sample(pres), 200000))   ' one decision for the whole run
    For Each sld In pres.Slides
        For Each shp In sld.Shapes
            cnt = cnt + UzPpt_Shape(shp, f, t)
        Next
        Set notes = Nothing
        On Error Resume Next
        Set notes = sld.NotesPage
        On Error GoTo 0
        If Not notes Is Nothing Then
            For Each shp In notes.Shapes
                cnt = cnt + UzPpt_Shape(shp, f, t)
            Next
        End If
    Next
    UzPpt_Run = cnt
End Function

Private Function PptHasTable(ByVal shp As Object) As Boolean
    On Error Resume Next
    PptHasTable = shp.HasTable
End Function
Private Function PptHasText(ByVal shp As Object) As Boolean
    On Error Resume Next
    If shp.HasTextFrame Then PptHasText = shp.TextFrame.HasText
End Function

Private Function UzPpt_Shape(ByVal shp As Object, ByVal f As String, ByVal t As String) As Long
    Dim i As Long, j As Long, cnt As Long
    If shp.Type = 6 Then                                   ' msoGroup
        For i = 1 To shp.GroupItems.Count
            cnt = cnt + UzPpt_Shape(shp.GroupItems(i), f, t)
        Next
    ElseIf PptHasTable(shp) Then
        For i = 1 To shp.Table.Rows.Count
            For j = 1 To shp.Table.Columns.Count
                cnt = cnt + UzPpt_TextRange(shp.Table.Cell(i, j).Shape.TextFrame.TextRange, f, t)
            Next
        Next
    ElseIf PptHasText(shp) Then
        cnt = cnt + UzPpt_TextRange(shp.TextFrame.TextRange, f, t)
    End If
    UzPpt_Shape = cnt
End Function

' each paragraph is converted as one string and split back over its runs, rewritten back to front
Private Function UzPpt_TextRange(ByVal tr As Object, ByVal f As String, ByVal t As String) As Long
    Dim p As Long, i As Long, n As Long, cnt As Long, para As Object, texts() As String, outs() As String
    For p = tr.Paragraphs.Count To 1 Step -1
        Set para = tr.Paragraphs(p)
        n = para.Runs.Count
        If n > 0 Then
            ReDim texts(1 To n)
            For i = 1 To n
                texts(i) = para.Runs(i).Text
            Next
            UzSplitConvert texts, outs, 1, n, f, t
            For i = n To 1 Step -1
                If outs(i) <> texts(i) Then para.Runs(i).Text = outs(i): cnt = cnt + 1
            Next
        End If
    Next
    UzPpt_TextRange = cnt
End Function

Private Function UzPpt_Sample(ByVal pres As Object) As String
    Dim sld As Object, shp As Object, s As String
    On Error Resume Next
    For Each sld In pres.Slides
        For Each shp In sld.Shapes
            If PptHasText(shp) Then s = s & shp.TextFrame.TextRange.Text & vbLf
            If Len(s) > 200000 Then Exit For
        Next
    Next
    UzPpt_Sample = s
End Function

' =====================================================================================
'  ENGINE (mirrors spec/SPEC.md section 5)
' =====================================================================================

Private Function ConvertSlice(ByVal s As String, ByVal f As String, ByVal t As String) As String
    If Len(s) = 0 Then Exit Function
    If f = "cyr" Then
        ConvertSlice = CyrToLatin(s, (t = "new"))
    ElseIf t = "cyr" Then
        ConvertSlice = LatinToCyr(s, (f = "new"))
    ElseIf f = "lat" Then
        ConvertSlice = LatToNew(s)
    Else
        ConvertSlice = NewToLat(s)
    End If
End Function

' ---------- URL / e-mail protection (SPEC section 5.6) ----------
' Tokens of the JavaScript expression (https?://|www\.)\S+|\S+@\S+\.\S+|@\w+ with JavaScript's \s and \w stay as
' they are; the text between them is converted slice by slice. A scanner, so every host matches the reference.
Private Function WithSkips(ByVal s As String, ByVal f As String, ByVal t As String) As String
    Dim n As Long, p As Long, last As Long, runEnd As Long, runAt As Long, k As Long, dotPos As Long
    Dim mEnd As Long, pre As Long, c As Long, out As String
    n = Len(s): p = 1: last = 1: runEnd = 0
    Do While p <= n
        c = CodeAt(s, p)
        If IsJsSpace(c) Then
            p = p + 1
        Else
            If p >= runEnd Then
                ' a new run of non-space characters; \S+@\S+\.\S+ matches from p to its end iff an "@" at k >= p + 1
                ' is followed by a "." at d >= k + 2 with at least one character after it
                runEnd = p
                Do While runEnd <= n
                    If IsJsSpace(CodeAt(s, runEnd)) Then Exit Do
                    runEnd = runEnd + 1
                Loop
                dotPos = 0
                For k = runEnd - 2 To p Step -1
                    If CodeAt(s, k) = 46 Then dotPos = k: Exit For
                Next
                runAt = 0
                If dotPos > 0 Then
                    For k = dotPos - 2 To p Step -1
                        If CodeAt(s, k) = 64 Then runAt = k: Exit For
                    Next
                End If
            End If
            mEnd = 0
            pre = UrlPrefix(s, p, n)
            If pre > 0 And p + pre < runEnd Then
                mEnd = runEnd
            ElseIf runAt >= p + 1 Then
                mEnd = runEnd
            ElseIf c = 64 And p < n Then
                If IsWordChar(CodeAt(s, p + 1)) Then
                    mEnd = p + 2
                    Do While mEnd <= n
                        If Not IsWordChar(CodeAt(s, mEnd)) Then Exit Do
                        mEnd = mEnd + 1
                    Loop
                End If
            End If
            If mEnd = 0 Then
                p = p + 1
            Else
                out = out & ConvertSlice(Mid$(s, last, p - last), f, t) & Mid$(s, p, mEnd - p)
                last = mEnd: p = mEnd
            End If
        End If
    Loop
    WithSkips = out & ConvertSlice(Mid$(s, last), f, t)
End Function

' "www." -> 4, "http://" -> 7, "https://" -> 8 (case-sensitive, like the reference), else 0
Private Function UrlPrefix(ByVal s As String, ByVal p As Long, ByVal n As Long) As Long
    If p + 3 <= n Then
        If Mid$(s, p, 4) = "www." Then UrlPrefix = 4: Exit Function
    End If
    If p + 6 <= n Then
        If Mid$(s, p, 7) = "http://" Then UrlPrefix = 7: Exit Function
    End If
    If p + 7 <= n Then
        If Mid$(s, p, 8) = "https://" Then UrlPrefix = 8: Exit Function
    End If
End Function

' JavaScript's \s
Private Function IsJsSpace(ByVal c As Long) As Boolean
    Select Case c
        Case 9 To 13, 32, &HA0&, &H1680&, &H2000& To &H200A&, &H2028&, &H2029&, &H202F&, &H205F&, &H3000&, &HFEFF&
            IsJsSpace = True
    End Select
End Function

' JavaScript's \w (ASCII only)
Private Function IsWordChar(ByVal c As Long) As Boolean
    IsWordChar = (c >= 48 And c <= 57) Or (c >= 65 And c <= 90) Or (c >= 97 And c <= 122) Or c = 95
End Function

' ---------- Cyrillic -> Latin (toNew=False: 1995, toNew=True: 2026) ----------
Private Function CyrToLatin(ByVal s As String, ByVal toNew As Boolean) As String
    Dim n As Long, i As Long, c As Long, L As Long, P As Long, nx As Long, NL As Long
    Dim up As Boolean, r As String, buf As String, pos As Long
    Dim okinaS As String, tutuqS As String
    okinaS = MarkOkina(): tutuqS = MarkTutuq()
    n = Len(s)
    buf = Space$(n * 2 + 16): pos = 0
    For i = 1 To n
        c = CodeAt(s, i)
        If Not IsCyr(c) Then
            Put1 buf, pos, c
        Else
            L = CyrLower(c): up = IsCyrUpper(c)
            P = 0: If i > 1 Then P = CodeAt(s, i - 1)
            nx = 0: If i < n Then nx = CodeAt(s, i + 1)
            NL = CyrLower(nx)
            Select Case L
                Case &H435                                               ' cyr ye
                    If (Not IsCyr(P)) Or IsCyrVowel(P) Or CyrLower(P) = &H44A Or CyrLower(P) = &H44C Then r = "ye" Else r = "e"
                Case &H446                                               ' cyr tse
                    If IsCyrVowel(P) Then r = "ts" Else r = "s"
                Case &H44A                                               ' cyr hard sign
                    If NL = &H435 Or NL = &H451 Or NL = &H44E Or NL = &H44F Then
                        r = ""
                    ElseIf CyrLower(P) = &H45E And Not UzOptKeepHardSignAfterO Then
                        r = ""
                    Else
                        r = tutuqS
                    End If
                Case &H44C                                               ' cyr soft sign (+ o: batalyon)
                    If NL = &H43E Then r = "y" Else r = ""
                Case &H44F                                               ' cyr ya (sentabr, oktabr)
                    If MonthTa(s, i, n) Then r = "a" Else r = "ya"
                Case &H448, &H449                                        ' cyr sha, shcha
                    If toNew Then r = ChrW(&H15F) Else r = "sh"
                Case &H447                                               ' cyr che
                    If toNew Then r = ChrW(&HE7) Else r = "ch"
                Case &H45E                                               ' cyr short u
                    If toNew Then r = ChrW(&HF6) Else r = "o" & okinaS
                Case &H493                                               ' cyr ghe with stroke
                    If toNew Then r = ChrW(&H11F) Else r = "g" & okinaS
                Case &H441                                               ' cyr es (+ ha with descender)
                    If (Not toNew) And NL = &H4B3 Then r = "s" & tutuqS Else r = "s"
                Case Else
                    r = C2L(L)
                    If r = "" Then r = ChrW(c)
            End Select
            PutS buf, pos, CaseOut(s, i, up, r)
        End If
    Next
    CyrToLatin = Left$(buf, pos)
End Function

' The cyr ya of the months sentyabr / oktyabr: their Latin spelling is sentabr, oktabr.
Private Function MonthTa(ByVal s As String, ByVal i As Long, ByVal n As Long) As Boolean
    Dim st As Long, stem As String, k As Long
    st = i
    Do While st > 1
        If Not IsLetter(CodeAt(s, st - 1)) Then Exit Do
        st = st - 1
    Loop
    If i - st = 4 Then
        stem = U("0441 0435 043D 0442 044F 0431 0440")
    ElseIf i - st = 3 Then
        stem = U("043E 043A 0442 044F 0431 0440")
    Else
        Exit Function
    End If
    If st + Len(stem) - 1 > n Then Exit Function
    For k = 1 To Len(stem)
        If CyrLower(CodeAt(s, st + k - 1)) <> CodeAt(stem, k) Then Exit Function
    Next
    MonthTa = True
End Function

Private Function C2L(ByVal L As Long) As String
    Select Case L
        Case &H430: C2L = "a"
        Case &H431: C2L = "b"
        Case &H432: C2L = "v"
        Case &H433: C2L = "g"
        Case &H434: C2L = "d"
        Case &H436: C2L = "j"
        Case &H437: C2L = "z"
        Case &H438: C2L = "i"
        Case &H439: C2L = "y"
        Case &H43A: C2L = "k"
        Case &H43B: C2L = "l"
        Case &H43C: C2L = "m"
        Case &H43D: C2L = "n"
        Case &H43E: C2L = "o"
        Case &H43F: C2L = "p"
        Case &H440: C2L = "r"
        Case &H442: C2L = "t"
        Case &H443: C2L = "u"
        Case &H444: C2L = "f"
        Case &H445: C2L = "x"
        Case &H49B: C2L = "q"
        Case &H4B3: C2L = "h"
        Case &H44D: C2L = "e"
        Case &H44B: C2L = "i"
        Case &H451: C2L = "yo"
        Case &H44E: C2L = "yu"
        Case &H44F: C2L = "ya"
        Case Else: C2L = ""
    End Select
End Function

' ---------- Latin -> Cyrillic ----------
Private Function L2C(ByVal L As Long) As Long
    Select Case L
        Case 97: L2C = &H430    ' a
        Case 98: L2C = &H431    ' b
        Case 100: L2C = &H434   ' d
        Case 102: L2C = &H444   ' f
        Case 103: L2C = &H433   ' g
        Case 104: L2C = &H4B3   ' h
        Case 105: L2C = &H438   ' i
        Case 106: L2C = &H436   ' j
        Case 107: L2C = &H43A   ' k
        Case 108: L2C = &H43B   ' l
        Case 109: L2C = &H43C   ' m
        Case 110: L2C = &H43D   ' n
        Case 111: L2C = &H43E   ' o
        Case 112: L2C = &H43F   ' p
        Case 113: L2C = &H49B   ' q
        Case 114: L2C = &H440   ' r
        Case 115: L2C = &H441   ' s
        Case 116: L2C = &H442   ' t
        Case 117: L2C = &H443   ' u
        Case 118: L2C = &H432   ' v
        Case 120: L2C = &H445   ' x
        Case 121: L2C = &H439   ' y
        Case 122: L2C = &H437   ' z
        Case 99: L2C = &H446    ' c
        Case 119: L2C = &H432   ' w
        Case &HF6, &H14D, &HF5: L2C = &H45E   ' o-umlaut, o-macron, o-tilde
        Case &H11F: L2C = &H493 ' g-breve
        Case &H15F: L2C = &H448 ' s-cedilla
        Case &HE7: L2C = &H447  ' c-cedilla
        Case Else: L2C = 0
    End Select
End Function

Private Sub EmitCyr(ByRef buf As String, ByRef pos As Long, ByVal lowerCode As Long, ByVal up As Boolean)
    If up Then
        Put1 buf, pos, CyrUpper(lowerCode)
    Else
        Put1 buf, pos, lowerCode
    End If
End Sub

Private Function LatinToCyrScan(ByVal s As String, ByVal isNew As Boolean, ByVal prevCtx As Long) As String
    Dim n As Long, i As Long, c As Long, L As Long, nx As Long, N2 As Long, NL As Long, P As Long
    Dim up As Boolean, prevIsLetter As Boolean, prevIsVA As Boolean, wordEnds As Boolean
    Dim buf As String, pos As Long, rest As String, r As Long
    n = Len(s)
    buf = Space$(n * 2 + 16): pos = 0
    i = 1
    Do While i <= n
        c = CodeAt(s, i)
        If i > 1 Then P = CodeAt(s, i - 1) Else P = prevCtx
        nx = 0: If i < n Then nx = CodeAt(s, i + 1)
        N2 = 0: If i + 1 < n Then N2 = CodeAt(s, i + 2)
        If IsApos(c) Then
            If IsLat(P) And IsLat(nx) Then
                EmitCyr buf, pos, &H44A, IsLatUpper(P)                   ' cyr hard sign
            ElseIf IsLat(P) And c = TUTUQ Then
                EmitCyr buf, pos, &H44A, IsLatUpper(P)
            Else
                Put1 buf, pos, c
            End If
            i = i + 1
        ElseIf Not IsLat(c) Then
            Put1 buf, pos, c
            i = i + 1
        Else
            L = LatLower(c): up = IsLatUpper(c): NL = LatLower(nx)
            prevIsLetter = IsLat(P)
            prevIsVA = IsLatVowel(P) Or IsApos(P)
            If L = 111 And IsApos(nx) Then                                ' o'
                EmitCyr buf, pos, &H45E, up: i = i + 2
            ElseIf L = 103 And IsApos(nx) Then                            ' g'
                EmitCyr buf, pos, &H493, up: i = i + 2
            ElseIf L = 115 And NL = 104 And Not isNew Then               ' sh (1995)
                EmitCyr buf, pos, &H448, up: i = i + 2
            ElseIf L = 115 And IsApos(nx) And LatLower(N2) = 104 Then     ' s'h
                EmitCyr buf, pos, &H441, up: i = i + 2
            ElseIf L = 99 And NL = 104 Then                              ' ch
                EmitCyr buf, pos, &H447, up: i = i + 2
            ElseIf L = 121 And (NL = 111 Or NL = 117 Or NL = 97 Or NL = 101) Then   ' y + vowel
                If NL = 111 And IsApos(N2) Then
                    EmitCyr buf, pos, &H439, up: i = i + 1               ' yo' -> cyr y + short u
                Else
                    If NL = 101 Then
                        If (Not prevIsLetter) Or prevIsVA Then
                            EmitCyr buf, pos, &H435, up
                        Else
                            EmitCyr buf, pos, &H44C, up: EmitCyr buf, pos, &H435, up
                        End If
                    ElseIf NL = 111 Then
                        EmitCyr buf, pos, &H451, up
                    ElseIf NL = 117 Then
                        EmitCyr buf, pos, &H44E, up
                    Else
                        EmitCyr buf, pos, &H44F, up
                    End If
                    i = i + 2
                End If
            ElseIf L = 101 Then                                          ' e
                If (Not prevIsLetter) Or prevIsVA Then
                    EmitCyr buf, pos, &H44D, up
                Else
                    EmitCyr buf, pos, &H435, up
                End If
                i = i + 1
            ElseIf L = 116 And NL = 115 And TsRule(s, i, n, P) Then      ' ts -> cyr tse
                EmitCyr buf, pos, &H446, up: i = i + 2
            Else
                r = L2C(L)
                If r = 0 Then
                    Put1 buf, pos, c
                Else
                    EmitCyr buf, pos, r, up
                End If
                i = i + 1
            End If
        End If
    Loop
    LatinToCyrScan = Left$(buf, pos)
End Function

Private Function TsRule(ByVal s As String, ByVal i As Long, ByVal n As Long, ByVal P As Long) As Boolean
    Dim rest As String, wordEnds As Boolean
    If Not IsLat(P) Then                                         ' word-initial ts: tsirk (not o'tsa)
        If i = 1 Or Not IsApos(P) Then TsRule = True: Exit Function
    End If
    rest = LCase$(Mid$(s, i + 2, 3))
    If Left$(rest, 3) = "iya" Or Left$(rest, 3) = "ion" Then TsRule = True: Exit Function
    If UzOptNoTsFinal Then Exit Function
    If i + 2 > n Then wordEnds = True Else wordEnds = Not IsLat(CodeAt(s, i + 2))
    TsRule = wordEnds And IsLatVowel(P)
End Function

Private Function LatinToCyr(ByVal s As String, ByVal isNew As Boolean) As String
    Dim n As Long, i As Long, j As Long, c As Long, out As String
    If UzOptNoDictionary Then LatinToCyr = LatinToCyrScan(s, isNew, 0): Exit Function
    n = Len(s): i = 1
    Do While i <= n
        c = CodeAt(s, i)
        If Not (IsLat(c) Or IsApos(c)) Then
            out = out & ChrW(c): i = i + 1
        Else
            j = i
            Do While j <= n
                c = CodeAt(s, j)
                If IsLat(c) Or IsApos(c) Then j = j + 1 Else Exit Do
            Loop
            out = out & WordWithDict(Mid$(s, i, j - i), isNew)
            i = j
        End If
    Loop
    LatinToCyr = out
End Function

Private Function WordWithDict(ByVal w As String, ByVal isNew As Boolean) As String
    Dim key As String, k As Long, hit As Long, consumed As Long, built As String
    Dim stemSrc As String, rest As String, value As String, cyrStem As String
    Dim letters As Long, uppers As Long, firstUpper As Boolean, q As Long, ch As Long
    key = NormKey(w): hit = 0
    For k = 1 To mDictN
        If Len(key) >= Len(mDictKey(k)) Then
            If Left$(key, Len(mDictKey(k))) = mDictKey(k) Then hit = k: Exit For
        End If
    Next
    If hit = 0 Then WordWithDict = LatinToCyrScan(w, isNew, 0): Exit Function
    consumed = 0: built = ""
    Do While Len(built) < Len(mDictKey(hit)) And consumed < Len(w)
        consumed = consumed + 1
        built = built & NormKey(Mid$(w, consumed, 1))
    Loop
    stemSrc = Left$(w, consumed): rest = Mid$(w, consumed + 1)
    value = mDictVal(hit)
    For q = 1 To Len(stemSrc)
        ch = CodeAt(stemSrc, q)
        If IsLat(ch) Then
            letters = letters + 1
            If IsLatUpper(ch) Then
                uppers = uppers + 1
                If letters = 1 Then firstUpper = True
            End If
        End If
    Next
    If letters >= 2 And uppers = letters Then
        cyrStem = UpperStr(value)
    ElseIf firstUpper Then
        cyrStem = UpperFirst(value)
    Else
        cyrStem = value
    End If
    ' a final soft sign goes when a suffix follows (iyul, iyuldagi)
    If Len(rest) > 0 Then
        If IsLat(CodeAt(rest, 1)) And CyrLower(CodeAt(cyrStem, Len(cyrStem))) = &H44C Then cyrStem = Left$(cyrStem, Len(cyrStem) - 1)
    End If
    WordWithDict = cyrStem & LatinToCyrScan(rest, isNew, CodeAt(stemSrc, Len(stemSrc)))
End Function

Private Function NormKey(ByVal w As String) As String
    Dim i As Long, c As Long, o As String
    For i = 1 To Len(w)
        c = LatLower(CodeAt(w, i))
        If IsApos(c) Then
            o = o & "'"
        ElseIf c = &HF6 Or c = &H14D Or c = &HF5 Then
            o = o & "o'"
        ElseIf c = &H11F Then
            o = o & "g'"
        ElseIf c = &H15F Then
            o = o & "sh"
        ElseIf c = &HE7 Then
            o = o & "ch"
        Else
            o = o & ChrW(c)
        End If
    Next
    NormKey = o
End Function

' ---------- Latin 1995 -> Latin 2026 ----------
Private Function LatToNew(ByVal s As String) As String
    Dim n As Long, i As Long, c As Long, L As Long, nx As Long, N2 As Long, NL As Long, P As Long
    Dim up As Boolean, buf As String, pos As Long
    n = Len(s): buf = Space$(n + 16): pos = 0: i = 1
    Do While i <= n
        c = CodeAt(s, i): L = LatLower(c): up = IsLatUpper(c)
        nx = 0: If i < n Then nx = CodeAt(s, i + 1)
        N2 = 0: If i + 1 < n Then N2 = CodeAt(s, i + 2)
        NL = LatLower(nx)
        P = 0: If i > 1 Then P = CodeAt(s, i - 1)
        If IsApos(c) Then
            If IsLat(P) And IsLat(nx) Then
                PutS buf, pos, MarkTutuq()
            Else
                Put1 buf, pos, c
            End If
            i = i + 1
        ElseIf Not IsLat(c) Then
            Put1 buf, pos, c: i = i + 1
        ElseIf L = 111 And IsApos(nx) Then
            If up Then
                Put1 buf, pos, &HD6
            Else
                Put1 buf, pos, &HF6
            End If
            i = i + 2
        ElseIf L = 103 And IsApos(nx) Then
            If up Then
                Put1 buf, pos, &H11E
            Else
                Put1 buf, pos, &H11F
            End If
            i = i + 2
        ElseIf L = 115 And NL = 104 Then
            If up Then
                Put1 buf, pos, &H15E
            Else
                Put1 buf, pos, &H15F
            End If
            i = i + 2
        ElseIf L = 115 And IsApos(nx) And LatLower(N2) = 104 Then
            Put1 buf, pos, c: i = i + 2
        ElseIf L = 99 And NL = 104 Then
            If up Then
                Put1 buf, pos, &HC7
            Else
                Put1 buf, pos, &HE7
            End If
            i = i + 2
        ElseIf L = &H14D Or L = &HF5 Then
            If up Then
                Put1 buf, pos, &HD6
            Else
                Put1 buf, pos, &HF6
            End If
            i = i + 1
        Else
            Put1 buf, pos, c: i = i + 1
        End If
    Loop
    LatToNew = Left$(buf, pos)
End Function

' ---------- Latin 2026 -> Latin 1995 ----------
Private Function NewToLat(ByVal s As String) As String
    Dim n As Long, i As Long, c As Long, L As Long, nx As Long, NL As Long, P As Long
    Dim up As Boolean, buf As String, pos As Long
    n = Len(s): buf = Space$(n * 2 + 16): pos = 0: i = 1
    Do While i <= n
        c = CodeAt(s, i): L = LatLower(c): up = IsLatUpper(c)
        nx = 0: If i < n Then nx = CodeAt(s, i + 1)
        NL = LatLower(nx)
        P = 0: If i > 1 Then P = CodeAt(s, i - 1)
        If IsApos(c) Then
            If IsLat(P) And IsLat(nx) Then
                PutS buf, pos, MarkTutuq()
            Else
                Put1 buf, pos, c
            End If
        ElseIf Not IsLat(c) Then
            Put1 buf, pos, c
        ElseIf L = &HF6 Or L = &H14D Or L = &HF5 Then
            If up Then
                PutS buf, pos, "O" & MarkOkina()
            Else
                PutS buf, pos, "o" & MarkOkina()
            End If
        ElseIf L = &H11F Then
            If up Then
                PutS buf, pos, "G" & MarkOkina()
            Else
                PutS buf, pos, "g" & MarkOkina()
            End If
        ElseIf L = &H15F Then
            PutS buf, pos, CaseOut(s, i, up, "sh")
        ElseIf L = &HE7 Then
            PutS buf, pos, CaseOut(s, i, up, "ch")
        ElseIf L = 115 And NL = 104 Then
            Put1 buf, pos, c: PutS buf, pos, MarkTutuq()                 ' Ishoq -> Is'hoq
        Else
            Put1 buf, pos, c
        End If
        i = i + 1
    Loop
    NewToLat = Left$(buf, pos)
End Function

' =====================================================================================
'  HELPERS
' =====================================================================================
Private Function MarkOkina() As String
    If UzOptAscii Then MarkOkina = "'" Else MarkOkina = ChrW(OKINA)
End Function
Private Function MarkTutuq() As String
    If UzOptAscii Then MarkTutuq = "'" Else MarkTutuq = ChrW(TUTUQ)
End Function

Private Sub Put1(ByRef buf As String, ByRef pos As Long, ByVal c As Long)
    pos = pos + 1
    Mid$(buf, pos, 1) = ChrW(c)
End Sub
Private Sub PutS(ByRef buf As String, ByRef pos As Long, ByVal s As String)
    If Len(s) = 0 Then Exit Sub
    Mid$(buf, pos + 1, Len(s)) = s
    pos = pos + Len(s)
End Sub

Private Function InSet(ByVal setStr As String, ByVal c As Long) As Boolean
    If c <= 0 Then Exit Function
    InSet = (InStr(1, setStr, ChrW(c), vbBinaryCompare) > 0)
End Function
Private Function IsCyr(ByVal c As Long) As Boolean
    IsCyr = InSet(mCyrLower, c) Or InSet(mCyrUpper, c)
End Function
Private Function IsCyrUpper(ByVal c As Long) As Boolean
    IsCyrUpper = InSet(mCyrUpper, c)
End Function
Private Function CyrLower(ByVal c As Long) As Long
    Dim p As Long
    CyrLower = c
    If c <= 0 Then Exit Function
    p = InStr(1, mCyrUpper, ChrW(c), vbBinaryCompare)
    If p > 0 Then CyrLower = CodeAt(mCyrLower, p)
End Function
Private Function CyrUpper(ByVal c As Long) As Long
    Dim p As Long
    CyrUpper = c
    If c <= 0 Then Exit Function
    p = InStr(1, mCyrLower, ChrW(c), vbBinaryCompare)
    If p > 0 Then CyrUpper = CodeAt(mCyrUpper, p)
End Function
Private Function IsCyrVowel(ByVal c As Long) As Boolean
    IsCyrVowel = InSet(mCyrVowels, CyrLower(c))
End Function
Private Function IsLat(ByVal c As Long) As Boolean
    IsLat = InSet(mLatLower, c) Or InSet(mLatUpper, c)
End Function
Private Function IsLatUpper(ByVal c As Long) As Boolean
    IsLatUpper = InSet(mLatUpper, c)
End Function
Private Function LatLower(ByVal c As Long) As Long
    Dim p As Long
    LatLower = c
    If c <= 0 Then Exit Function
    p = InStr(1, mLatUpper, ChrW(c), vbBinaryCompare)
    If p > 0 Then LatLower = CodeAt(mLatLower, p)
End Function
Private Function LatUpper(ByVal c As Long) As Long
    Dim p As Long
    LatUpper = c
    If c <= 0 Then Exit Function
    p = InStr(1, mLatLower, ChrW(c), vbBinaryCompare)
    If p > 0 Then LatUpper = CodeAt(mLatUpper, p)
End Function
Private Function IsLatVowel(ByVal c As Long) As Boolean
    IsLatVowel = InSet(mLatVowels, LatLower(c))
End Function
Private Function IsApos(ByVal c As Long) As Boolean
    IsApos = InSet(mApos, c)
End Function
Private Function IsLetter(ByVal c As Long) As Boolean
    IsLetter = IsCyr(c) Or IsLat(c)
End Function
Private Function IsUpperLetter(ByVal c As Long) As Boolean
    IsUpperLetter = IsCyrUpper(c) Or IsLatUpper(c)
End Function

Private Function UpperStr(ByVal s As String) As String
    Dim i As Long, o As String
    For i = 1 To Len(s)
        o = o & ChrW(LatUpper(CyrUpper(CodeAt(s, i))))
    Next
    UpperStr = o
End Function
Private Function UpperFirst(ByVal s As String) As String
    If Len(s) = 0 Then Exit Function
    UpperFirst = ChrW(LatUpper(CyrUpper(CodeAt(s, 1)))) & Mid$(s, 2)
End Function

' SPEC section 4: next letter (skipping one apostrophe) uppercase -> ALL CAPS; else previous letter if no next letter
Private Function NextLetterIsUpper(ByVal s As String, ByVal i As Long) As Boolean
    Dim j As Long, k As Long, c As Long, n As Long
    n = Len(s)
    j = i + 1
    If j <= n Then If IsApos(CodeAt(s, j)) Then j = j + 1
    If j <= n Then
        c = CodeAt(s, j)
        If IsLetter(c) Then NextLetterIsUpper = IsUpperLetter(c): Exit Function
    End If
    k = i - 1
    If k >= 1 Then If IsApos(CodeAt(s, k)) Then k = k - 1
    If k >= 1 Then
        c = CodeAt(s, k)
        If IsLetter(c) Then NextLetterIsUpper = IsUpperLetter(c): Exit Function
    End If
    NextLetterIsUpper = False
End Function

Private Function CaseOut(ByVal s As String, ByVal i As Long, ByVal srcUpper As Boolean, ByVal r As String) As String
    If (Not srcUpper) Or Len(r) = 0 Then CaseOut = r: Exit Function
    If Len(r) = 1 Then CaseOut = UpperStr(r): Exit Function
    If NextLetterIsUpper(s, i) Then CaseOut = UpperStr(r) Else CaseOut = UpperFirst(r)
End Function

' "043E 0431" -> cyr "ob"
Private Function U(ByVal hexCodes As String) As String
    Dim i As Long, o As String, tok As String
    hexCodes = Trim$(hexCodes) & " "
    tok = ""
    For i = 1 To Len(hexCodes)
        If Mid$(hexCodes, i, 1) = " " Then
            If Len(tok) > 0 Then o = o & ChrW(CLng("&H" & tok)): tok = ""
        Else
            tok = tok & Mid$(hexCodes, i, 1)
        End If
    Next
    U = o
End Function

Private Sub AddD(ByVal k As String, ByVal v As String)
    mDictN = mDictN + 1
    If mDictN > UBound(mDictKey) Then
        ReDim Preserve mDictKey(1 To mDictN + 32)
        ReDim Preserve mDictVal(1 To mDictN + 32)
    End If
    mDictKey(mDictN) = k: mDictVal(mDictN) = v
End Sub

' Add your own stems at runtime: UzAddDictionary "fizika", ChrW(&H444) & ...   (keys: lowercase Latin 1995, ASCII ')
Public Sub UzAddDictionary(ByVal latinStem As String, ByVal cyrillicStem As String)
    Dim i As Long, j As Long, tk As String, tv As String
    UzInit
    AddD NormKey(latinStem), cyrillicStem
    ' keep longest-first order (insertion sort of the last element)
    For i = mDictN To 2 Step -1
        If Len(mDictKey(i)) > Len(mDictKey(i - 1)) Then
            tk = mDictKey(i): tv = mDictVal(i)
            mDictKey(i) = mDictKey(i - 1): mDictVal(i) = mDictVal(i - 1)
            mDictKey(i - 1) = tk: mDictVal(i - 1) = tv
        Else
            Exit For
        End If
    Next
End Sub

Private Sub UzInit()
    If mInit Then Exit Sub
    mInit = True
    mCyrLower = U("0430 0431 0432 0433 0434 0435 0451 0436 0437 0438 0439 043A 043B 043C 043D 043E 043F 0440 0441 0442 0443 0444 0445 0446 0447 0448 0449 044A 044B 044C 044D 044E 044F 045E 049B 0493 04B3")
    mCyrUpper = U("0410 0411 0412 0413 0414 0415 0401 0416 0417 0418 0419 041A 041B 041C 041D 041E 041F 0420 0421 0422 0423 0424 0425 0426 0427 0428 0429 042A 042B 042C 042D 042E 042F 040E 049A 0492 04B2")
    mLatLower = U("0061 0062 0063 0064 0065 0066 0067 0068 0069 006A 006B 006C 006D 006E 006F 0070 0071 0072 0073 0074 0075 0076 0077 0078 0079 007A 00F6 011F 015F 00E7 014D 00F5")
    mLatUpper = U("0041 0042 0043 0044 0045 0046 0047 0048 0049 004A 004B 004C 004D 004E 004F 0050 0051 0052 0053 0054 0055 0056 0057 0058 0059 005A 00D6 011E 015E 00C7 014C 00D5")
    mApos = U("0027 02BB 02BC 2018 2019 0060 00B4")
    mCyrVowels = U("0430 0435 0451 0438 043E 0443 044D 044E 044F 045E 044B")
    mLatVowels = U("0061 0065 0069 006F 0075 00F6 014D 00F5")
    ReDim mDictKey(1 To 128): ReDim mDictVal(1 To 128): mDictN = 0
    ' --- dictionary, longest keys first (generated from spec/SPEC.md section 6) ---
    AddD "konsentratsiya", U("043A 043E 043D 0446 0435 043D 0442 0440 0430 0446 0438 044F")
    AddD "rekonstruksiya", U("0440 0435 043A 043E 043D 0441 0442 0440 0443 043A 0446 0438 044F")
    AddD "sivilizatsiya", U("0446 0438 0432 0438 043B 0438 0437 0430 0446 0438 044F")
    AddD "kalkulyatsiya", U("043A 0430 043B 044C 043A 0443 043B 044F 0446 0438 044F")
    AddD "konstruksiya", U("043A 043E 043D 0441 0442 0440 0443 043A 0446 0438 044F")
    AddD "konferensiya", U("043A 043E 043D 0444 0435 0440 0435 043D 0446 0438 044F")
    AddD "differensial", U("0434 0438 0444 0444 0435 0440 0435 043D 0446 0438 0430 043B")
    AddD "sotsiologiya", U("0441 043E 0446 0438 043E 043B 043E 0433 0438 044F")
    AddD "shveytsariya", U("0448 0432 0435 0439 0446 0430 0440 0438 044F")
    AddD "konyunktura", U("043A 043E 043D 044A 044E 043D 043A 0442 0443 0440 0430")
    AddD "instruksiya", U("0438 043D 0441 0442 0440 0443 043A 0446 0438 044F")
    AddD "tranzaksiya", U("0442 0440 0430 043D 0437 0430 043A 0446 0438 044F")
    AddD "kalkulyator", U("043A 0430 043B 044C 043A 0443 043B 044F 0442 043E 0440")
    AddD "shampinyon", U("0448 0430 043C 043F 0438 043D 044C 043E 043D")
    AddD "sellyuloza", U("0446 0435 043B 043B 044E 043B 043E 0437 0430")
    AddD "seremoniya", U("0446 0435 0440 0435 043C 043E 043D 0438 044F")
    AddD "produksiya", U("043F 0440 043E 0434 0443 043A 0446 0438 044F")
    AddD "kolleksiya", U("043A 043E 043B 043B 0435 043A 0446 0438 044F")
    AddD "proporsiya", U("043F 0440 043E 043F 043E 0440 0446 0438 044F")
    AddD "litsenziya", U("043B 0438 0446 0435 043D 0437 0438 044F")
    AddD "protsedura", U("043F 0440 043E 0446 0435 0434 0443 0440 0430")
    AddD "konsepsiya", U("043A 043E 043D 0446 0435 043F 0446 0438 044F")
    AddD "instansiya", U("0438 043D 0441 0442 0430 043D 0446 0438 044F")
    AddD "distansiya", U("0434 0438 0441 0442 0430 043D 0446 0438 044F")
    AddD "kvitansiya", U("043A 0432 0438 0442 0430 043D 0446 0438 044F")
    AddD "korrupsiya", U("043A 043E 0440 0440 0443 043F 0446 0438 044F")
    AddD "inspeksiya", U("0438 043D 0441 043F 0435 043A 0446 0438 044F")
    AddD "korreksiya", U("043A 043E 0440 0440 0435 043A 0446 0438 044F")
    AddD "funksional", U("0444 0443 043D 043A 0446 0438 043E 043D 0430 043B")
    AddD "gorizontal", U("0433 043E 0440 0438 0437 043E 043D 0442 0430 043B 044C")
    AddD "fakultativ", U("0444 0430 043A 0443 043B 044C 0442 0430 0442 0438 0432")
    AddD "pochtalyon", U("043F 043E 0447 0442 0430 043B 044C 043E 043D")
    AddD "inyeksiya", U("0438 043D 044A 0435 043A 0446 0438 044F")
    AddD "kompyuter", U("043A 043E 043C 043F 044C 044E 0442 0435 0440")
    AddD "redaksiya", U("0440 0435 0434 0430 043A 0446 0438 044F")
    AddD "infeksiya", U("0438 043D 0444 0435 043A 0446 0438 044F")
    AddD "potensial", U("043F 043E 0442 0435 043D 0446 0438 0430 043B")
    AddD "spetsifik", U("0441 043F 0435 0446 0438 0444 0438 043A")
    AddD "sinklinal", U("0441 0438 043D 043A 043B 0438 043D 0430 043B")
    AddD "direksiya", U("0434 0438 0440 0435 043A 0446 0438 044F")
    AddD "induksiya", U("0438 043D 0434 0443 043A 0446 0438 044F")
    AddD "avtomobil", U("0430 0432 0442 043E 043C 043E 0431 0438 043B 044C")
    AddD "magistral", U("043C 0430 0433 0438 0441 0442 0440 0430 043B 044C")
    AddD "kompanyon", U("043A 043E 043C 043F 0430 043D 044C 043E 043D")
    AddD "adyutant", U("0430 0434 044A 044E 0442 0430 043D 0442")
    AddD "intervyu", U("0438 043D 0442 0435 0440 0432 044C 044E")
    AddD "premyera", U("043F 0440 0435 043C 044C 0435 0440 0430")
    AddD "batalyon", U("0431 0430 0442 0430 043B 044C 043E 043D")
    AddD "medalyon", U("043C 0435 0434 0430 043B 044C 043E 043D")
    AddD "sisterna", U("0446 0438 0441 0442 0435 0440 043D 0430")
    AddD "sellofan", U("0446 0435 043B 043B 043E 0444 0430 043D")
    AddD "funksiya", U("0444 0443 043D 043A 0446 0438 044F")
    AddD "fraksiya", U("0444 0440 0430 043A 0446 0438 044F")
    AddD "reaksiya", U("0440 0435 0430 043A 0446 0438 044F")
    AddD "sanksiya", U("0441 0430 043D 043A 0446 0438 044F")
    AddD "protsent", U("043F 0440 043E 0446 0435 043D 0442")
    AddD "protsess", U("043F 0440 043E 0446 0435 0441 0441")
    AddD "spetsial", U("0441 043F 0435 0446 0438 0430 043B")
    AddD "stansiya", U("0441 0442 0430 043D 0446 0438 044F")
    AddD "fransiya", U("0444 0440 0430 043D 0446 0438 044F")
    AddD "sentyabr", U("0441 0435 043D 0442 044F 0431 0440 044C")
    AddD "spektakl", U("0441 043F 0435 043A 0442 0430 043A 043B 044C")
    AddD "kalendar", U("043A 0430 043B 0435 043D 0434 0430 0440 044C")
    AddD "sekretar", U("0441 0435 043A 0440 0435 0442 0430 0440 044C")
    AddD "parallel", U("043F 0430 0440 0430 043B 043B 0435 043B 044C")
    AddD "festival", U("0444 0435 0441 0442 0438 0432 0430 043B 044C")
    AddD "shtempel", U("0448 0442 0435 043C 043F 0435 043B 044C")
    AddD "vertikal", U("0432 0435 0440 0442 0438 043A 0430 043B 044C")
    AddD "diagonal", U("0434 0438 0430 0433 043E 043D 0430 043B 044C")
    AddD "gospital", U("0433 043E 0441 043F 0438 0442 0430 043B 044C")
    AddD "dvigatel", U("0434 0432 0438 0433 0430 0442 0435 043B 044C")
    AddD "alpinist", U("0430 043B 044C 043F 0438 043D 0438 0441 0442")
    AddD "alpinizm", U("0430 043B 044C 043F 0438 043D 0438 0437 043C")
    AddD "rezultat", U("0440 0435 0437 0443 043B 044C 0442 0430 0442")
    AddD "fakultet", U("0444 0430 043A 0443 043B 044C 0442 0435 0442")
    AddD "pavilyon", U("043F 0430 0432 0438 043B 044C 043E 043D")
    AddD "mo'tabar", U("043C 045E 044A 0442 0430 0431 0430 0440")
    AddD "mo'tadil", U("043C 045E 044A 0442 0430 0434 0438 043B")
    AddD "subyekt", U("0441 0443 0431 044A 0435 043A 0442")
    AddD "tatyana", U("0442 0430 0442 044C 044F 043D 0430")
    AddD "senzura", U("0446 0435 043D 0437 0443 0440 0430")
    AddD "sentner", U("0446 0435 043D 0442 043D 0435 0440")
    AddD "silindr", U("0446 0438 043B 0438 043D 0434 0440")
    AddD "sitadel", U("0446 0438 0442 0430 0434 0435 043B 044C")
    AddD "sinkret", U("0441 0438 043D 043A 0440 0435 0442")
    AddD "leksiya", U("043B 0435 043A 0446 0438 044F")
    AddD "seksiya", U("0441 0435 043A 0446 0438 044F")
    AddD "porsiya", U("043F 043E 0440 0446 0438 044F")
    AddD "ofitser", U("043E 0444 0438 0446 0435 0440")
    AddD "konsert", U("043A 043E 043D 0446 0435 0440 0442")
    AddD "konsern", U("043A 043E 043D 0446 0435 0440 043D")
    AddD "sotsial", U("0441 043E 0446 0438 0430 043B")
    AddD "shprits", U("0448 043F 0440 0438 0446")
    AddD "auksion", U("0430 0443 043A 0446 0438 043E 043D")
    AddD "fransuz", U("0444 0440 0430 043D 0446 0443 0437")
    AddD "sentabr", U("0441 0435 043D 0442 044F 0431 0440 044C")
    AddD "oktyabr", U("043E 043A 0442 044F 0431 0440 044C")
    AddD "portfel", U("043F 043E 0440 0442 0444 0435 043B 044C")
    AddD "tekstil", U("0442 0435 043A 0441 0442 0438 043B 044C")
    AddD "ansambl", U("0430 043D 0441 0430 043C 0431 043B 044C")
    AddD "tyulpan", U("0442 044E 043B 044C 043F 0430 043D")
    AddD "shampun", U("0448 0430 043C 043F 0443 043D 044C")
    AddD "konsult", U("043A 043E 043D 0441 0443 043B 044C 0442")
    AddD "mayonez", U("043C 0430 0439 043E 043D 0435 0437")
    AddD "mo'jiza", U("043C 045E 044A 0436 0438 0437 0430")
    AddD "sinkop", U("0441 0438 043D 043A 043E 043F")
    AddD "obyekt", U("043E 0431 044A 0435 043A 0442")
    AddD "bulyon", U("0431 0443 043B 044C 043E 043D")
    AddD "kanyon", U("043A 0430 043D 044C 043E 043D")
    AddD "senyor", U("0441 0435 043D 044C 043E 0440")
    AddD "nyuton", U("043D 044C 044E 0442 043E 043D")
    AddD "yogurt", U("0439 043E 0433 0443 0440 0442")
    AddD "sement", U("0446 0435 043C 0435 043D 0442")
    AddD "sitata", U("0446 0438 0442 0430 0442 0430")
    AddD "sitrus", U("0446 0438 0442 0440 0443 0441")
    AddD "selsiy", U("0446 0435 043B 044C 0441 0438 0439")
    AddD "sianid", U("0446 0438 0430 043D 0438 0434")
    AddD "sirkul", U("0446 0438 0440 043A 0443 043B 044C")
    AddD "sunami", U("0446 0443 043D 0430 043C 0438")
    AddD "aksiya", U("0430 043A 0446 0438 044F")
    AddD "litsey", U("043B 0438 0446 0435 0439")
    AddD "kvarts", U("043A 0432 0430 0440 0446")
    AddD "aksent", U("0430 043A 0446 0435 043D 0442")
    AddD "yanvar", U("044F 043D 0432 0430 0440 044C")
    AddD "fevral", U("0444 0435 0432 0440 0430 043B 044C")
    AddD "oktabr", U("043E 043A 0442 044F 0431 0440 044C")
    AddD "noyabr", U("043D 043E 044F 0431 0440 044C")
    AddD "dekabr", U("0434 0435 043A 0430 0431 0440 044C")
    AddD "slovar", U("0441 043B 043E 0432 0430 0440 044C")
    AddD "bukvar", U("0431 0443 043A 0432 0430 0440 044C")
    AddD "shinel", U("0448 0438 043D 0435 043B 044C")
    AddD "spiral", U("0441 043F 0438 0440 0430 043B 044C")
    AddD "asfalt", U("0430 0441 0444 0430 043B 044C 0442")
    AddD "mo'jaz", U("043C 045E 044A 0436 0430 0437")
    AddD "sirka", U("0441 0438 0440 043A 0430")
    AddD "sentr", U("0446 0435 043D 0442 0440")
    AddD "sokol", U("0446 043E 043A 043E 043B 044C")
    AddD "plats", U("043F 043B 0430 0446")
    AddD "blits", U("0431 043B 0438 0446")
    AddD "aksiz", U("0430 043A 0446 0438 0437")
    AddD "aprel", U("0430 043F 0440 0435 043B 044C")
    AddD "albom", U("0430 043B 044C 0431 043E 043C")
    AddD "palto", U("043F 0430 043B 044C 0442 043E")
    AddD "medal", U("043C 0435 0434 0430 043B 044C")
    AddD "model", U("043C 043E 0434 0435 043B 044C")
    AddD "mebel", U("043C 0435 0431 0435 043B 044C")
    AddD "dizel", U("0434 0438 0437 0435 043B 044C")
    AddD "pedal", U("043F 0435 0434 0430 043B 044C")
    AddD "detal", U("0434 0435 0442 0430 043B 044C")
    AddD "panel", U("043F 0430 043D 0435 043B 044C")
    AddD "kabel", U("043A 0430 0431 0435 043B 044C")
    AddD "motel", U("043C 043E 0442 0435 043B 044C")
    AddD "kafel", U("043A 0430 0444 0435 043B 044C")
    AddD "tabel", U("0442 0430 0431 0435 043B 044C")
    AddD "kreml", U("043A 0440 0435 043C 043B 044C")
    AddD "rayon", U("0440 0430 0439 043E 043D")
    AddD "mayor", U("043C 0430 0439 043E 0440")
    AddD "ilya", U("0438 043B 044C 044F")
    AddD "yoga", U("0439 043E 0433 0430")
    AddD "york", U("0439 043E 0440 043A")
    AddD "sirk", U("0446 0438 0440 043A")
    AddD "sikl", U("0446 0438 043A 043B")
    AddD "sink", U("0446 0438 043D 043A")
    AddD "iyun", U("0438 044E 043D 044C")
    AddD "iyul", U("0438 044E 043B 044C")
    AddD "film", U("0444 0438 043B 044C 043C")
    AddD "stil", U("0441 0442 0438 043B 044C")
    AddD "rubl", U("0440 0443 0431 043B 044C")
    AddD "otel", U("043E 0442 0435 043B 044C")
    AddD "vals", U("0432 0430 043B 044C 0441")
    AddD "volt", U("0432 043E 043B 044C 0442")
    AddD "pult", U("043F 0443 043B 044C 0442")
    AddD "kult", U("043A 0443 043B 044C 0442")
    AddD "sex", U("0446 0435 0445")
    AddD "rol", U("0440 043E 043B 044C")
End Sub

' =====================================================================================
'  SELF-TEST (Alt+F8 -> UzSelfTest). Mirrors a sample of spec/fixtures.json.
' =====================================================================================
Public Sub UzSelfTest()
    Dim r As String
    r = UzSelfTestResult()
    MsgBox "UzTranslit self-test: " & r, IIf(InStr(r, ", 0 failed") > 0, vbInformation, vbExclamation), "UzTranslit"
End Sub

' "N passed, M failed" and the failures, one per line (CI runs this in LibreOffice's VBA mode)
Public Function UzSelfTestResult() As String
    Dim ok As Long, bad As Long, msg As String, pieces() As String, outs() As String
    UzInit
    T ok, bad, msg, UzConvert(U("040E 0437 0431 0435 043A 0438 0441 0442 043E 043D"), "cyr", "lat"), "O" & ChrW(&H2BB) & "zbekiston"
    T ok, bad, msg, UzConvert(U("040E 0437 0431 0435 043A 0438 0441 0442 043E 043D"), "cyr", "new"), U("00D6 007A 0062 0065 006B 0069 0073 0074 006F 006E")
    T ok, bad, msg, UzConvert(U("0422 043E 0448 043A 0435 043D 0442 0020 0448 0430 04B3 0440 0438"), "cyr", "new"), U("0054 006F 015F 006B 0065 006E 0074 0020 015F 0061 0068 0072 0069")
    T ok, bad, msg, UzConvert(U("0428 0410 04B2 0410 0420"), "cyr", "lat"), "SHAHAR"
    T ok, bad, msg, UzConvert(U("0418 0441 04B3 043E 049B"), "cyr", "lat"), "Is" & ChrW(&H2BC) & "hoq"
    T ok, bad, msg, UzConvert(U("0418 0441 04B3 043E 049B"), "cyr", "new"), "Ishoq"
    T ok, bad, msg, UzConvert(U("043A 043E 043D 0441 0442 0438 0442 0443 0446 0438 044F"), "cyr", "lat"), "konstitutsiya"
    T ok, bad, msg, UzConvert(U("0446 0438 0440 043A"), "cyr", "lat"), "sirk"
    T ok, bad, msg, UzConvert(U("043E 0431 044A 0435 043A 0442"), "cyr", "lat"), "obyekt"
    T ok, bad, msg, UzConvert("O'zbekiston Respublikasi", "lat", "cyr"), U("040E 0437 0431 0435 043A 0438 0441 0442 043E 043D 0020 0420 0435 0441 043F 0443 0431 043B 0438 043A 0430 0441 0438")
    T ok, bad, msg, UzConvert("Toshkent shahri", "lat", "cyr"), U("0422 043E 0448 043A 0435 043D 0442 0020 0448 0430 04B3 0440 0438")
    T ok, bad, msg, UzConvert("Yer", "lat", "cyr"), U("0415 0440")
    T ok, bad, msg, UzConvert("yo'l", "lat", "cyr"), U("0439 045E 043B")
    T ok, bad, msg, UzConvert("Is'hoq", "lat", "cyr"), U("0418 0441 04B3 043E 049B")
    T ok, bad, msg, UzConvert("Ekologiya", "lat", "cyr"), U("042D 043A 043E 043B 043E 0433 0438 044F")
    T ok, bad, msg, UzConvert("poema", "lat", "cyr"), U("043F 043E 044D 043C 0430")
    T ok, bad, msg, UzConvert("obyekt", "lat", "cyr"), U("043E 0431 044A 0435 043A 0442")
    T ok, bad, msg, UzConvert("kompyuterlar", "lat", "cyr"), U("043A 043E 043C 043F 044C 044E 0442 0435 0440 043B 0430 0440")
    T ok, bad, msg, UzConvert("militsiya", "lat", "cyr"), U("043C 0438 043B 0438 0446 0438 044F")
    T ok, bad, msg, UzConvert("ketsa", "lat", "cyr"), U("043A 0435 0442 0441 0430")
    T ok, bad, msg, UzConvert("MA'NO", "lat", "cyr"), U("041C 0410 042A 041D 041E")
    T ok, bad, msg, UzConvert("O'zbekiston Respublikasi", "lat", "new"), U("00D6 007A 0062 0065 006B 0069 0073 0074 006F 006E 0020 0052 0065 0073 0070 0075 0062 006C 0069 006B 0061 0073 0069")
    T ok, bad, msg, UzConvert("SHAHAR chiroyli Is'hoq ma'no", "lat", "new"), U("015E 0041 0048 0041 0052 0020 00E7 0069 0072 006F 0079 006C 0069 0020 0049 0073 0068 006F 0071 0020 006D 0061 02BC 006E 006F")
    T ok, bad, msg, UzConvert(U("015E 0041 0048 0041 0052 0020 0049 0073 0068 006F 0071 0020 0071 00F6 006E 011F 0069 0072 006F 0071"), "new", "lat"), "SHAHAR Is" & ChrW(&H2BC) & "hoq qo" & ChrW(&H2BB) & "ng" & ChrW(&H2BB) & "iroq"
    T ok, bad, msg, UzConvert(U("0049 0073 0068 006F 0071"), "new", "cyr"), U("0418 0441 04B3 043E 049B")
    T ok, bad, msg, UzDetect(U("00D6 007A 0062 0065 006B 0069 0073 0074 006F 006E")), "new"
    T ok, bad, msg, UzDetect("O'zbekiston"), "lat"
    T ok, bad, msg, UzDetect(U("0421 0430 043B 043E 043C")), "cyr"
    ReDim pieces(1 To 2)                                   ' a word cut by formatting: bold "Sh" + plain "ahar"
    pieces(1) = U("0428"): pieces(2) = U("0410 04B2 0410 0420")
    UzSplitConvert pieces, outs, 1, 2, "cyr", "lat"
    T ok, bad, msg, outs(1) & "|" & outs(2), "SH|AHAR"
    UzSelfTestResult = ok & " passed, " & bad & " failed" & IIf(bad > 0, vbCrLf & vbCrLf & msg, "")
End Function

Private Sub T(ByRef ok As Long, ByRef bad As Long, ByRef msg As String, ByVal got As String, ByVal want As String)
    If got = want Then
        ok = ok + 1
    Else
        bad = bad + 1
        If Len(msg) < 1500 Then msg = msg & "want: " & want & vbCrLf & "got:  " & got & vbCrLf
    End If
End Sub
