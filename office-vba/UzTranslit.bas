Attribute VB_Name = "UzTranslit"
Option Explicit
Option Compare Binary
' =====================================================================================
'  UzTranslit v1.0.0 — Oʻzbek alifbo konvertori for Microsoft Office 97 … 2026
'  Word, Excel, PowerPoint (Windows and Mac). One module, no references, pure VBA 5/6/7.
'
'  Scripts:  "cyr"  Кирилл (1940)
'            "lat"  Lotin 1995  (Oʻ Gʻ Sh Ch Ng)
'            "new"  Lotin 2026  (Ö Ğ Ş Ç) — Qonun OʻRQ-1184, 21.10.2026
'            "auto" detect
'
'  INSTALL:  Alt+F11 → File → Import File… → UzTranslit.bas → save the document / Normal.dotm /
'            PERSONAL.XLSB.  Then Alt+F8 and run e.g. UzTranslit_LatToNew, or put the macros on a
'            toolbar / Quick Access Toolbar / ribbon.  Excel formulas: =UzConvert(A1,"lat","new")
'
'  Everything non-ASCII is built with ChrW so the module survives any VBE code page.
'  Conforms to spec/SPEC.md and passes spec/fixtures.json (see tests/vba_selftest below: UzSelfTest).
' =====================================================================================

' ---------- options (defaults = spec defaults; False = default) ----------
Public UzOptAscii As Boolean            ' True: use ' instead of ʻ / ʼ in Latin output
Public UzOptKeepHardSignAfterO As Boolean ' True: мўъжиза → moʻʼjiza (default drops the ъ)
Public UzOptNoTsFinal As Boolean        ' True: never turn word-final "ts" into ц
Public UzOptNoDictionary As Boolean     ' True: skip the loanword dictionary

' ---------- internal tables ----------
Private mInit As Boolean
Private mCyrLower As String, mCyrUpper As String
Private mLatLower As String, mLatUpper As String
Private mApos As String, mCyrVowels As String, mLatVowels As String
Private mDictKey() As String, mDictVal() As String, mDictN As Long

Private Const OKINA As Integer = &H2BB      ' ʻ
Private Const TUTUQ As Integer = &H2BC      ' ʼ

' =====================================================================================
'  PUBLIC API
' =====================================================================================
Public Function UzConvert(ByVal Text As String, ByVal FromScript As String, ByVal ToScript As String) As String
    UzInit
    FromScript = LCase$(FromScript): ToScript = LCase$(ToScript)
    If FromScript = "auto" Then FromScript = UzDetect(Text)
    If FromScript = ToScript Then UzConvert = Text: Exit Function
    If FromScript = "cyr" And (ToScript = "lat" Or ToScript = "new") Then
        UzConvert = CyrToLatin(Text, (ToScript = "new"))
    ElseIf (FromScript = "lat" Or FromScript = "new") And ToScript = "cyr" Then
        UzConvert = LatinToCyr(Text, (FromScript = "new"))
    ElseIf FromScript = "lat" And ToScript = "new" Then
        UzConvert = LatToNew(Text)
    ElseIf FromScript = "new" And ToScript = "lat" Then
        UzConvert = NewToLat(Text)
    Else
        Err.Raise 5, "UzTranslit", "Unknown direction " & FromScript & " -> " & ToScript
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
    Dim i As Long, n As Long, c As Integer, L As Integer, N2 As Integer
    Dim cyr As Long, lat As Long, nw As Long, dig As Long
    UzInit
    n = Len(Text)
    For i = 1 To n
        c = AscW(Mid$(Text, i, 1))
        If IsCyr(c) Then
            cyr = cyr + 1
        ElseIf IsLat(c) Then
            lat = lat + 1
            L = LatLower(c)
            If L = &HF6 Or L = &H11F Or L = &H15F Or L = &HE7 Or L = &H14D Or L = &HF5 Then nw = nw + 1
            N2 = 0: If i < n Then N2 = LatLower(AscW(Mid$(Text, i + 1, 1)))
            If (L = 115 Or L = 99) And N2 = 104 Then dig = dig + 1          ' sh ch
            If (L = 111 Or L = 103) And IsApos(N2) Then dig = dig + 1       ' oʻ gʻ
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

' ---------- Word: paragraph-level when formatting is uniform, run-level otherwise ----------
Private Function UzWord_Run(ByVal app As Object, ByVal f As String, ByVal t As String) As Long
    Dim doc As Object, sel As Object, rng As Object, story As Object
    Dim trackWas As Boolean, cnt As Long
    Set doc = app.ActiveDocument
    Set sel = app.Selection
    On Error Resume Next
    app.ScreenUpdating = False
    trackWas = doc.TrackRevisions
    doc.TrackRevisions = False
    On Error GoTo 0
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
    On Error Resume Next
    doc.TrackRevisions = trackWas
    app.ScreenUpdating = True
    On Error GoTo 0
    UzWord_Run = cnt
End Function

Private Function UzWord_Range(ByVal doc As Object, ByVal rng As Object, ByVal f As String, ByVal t As String) As Long
    Dim para As Object, r As Object, cnt As Long, s As String, conv As String
    Dim pStart As Long, pEnd As Long
    For Each para In rng.Paragraphs
        pStart = para.Range.Start: pEnd = para.Range.End
        If pStart < rng.Start Then pStart = rng.Start
        If pEnd > rng.End Then pEnd = rng.End
        If pEnd > pStart Then
            Set r = para.Range.Duplicate          ' stays inside the paragraph's story (header, footnote, text box…)
            r.End = pEnd: r.Start = pStart
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
                    If conv <> s Then r.Text = conv: cnt = cnt + 1
                Else
                    cnt = cnt + UzWord_Runs(doc, r, f, t)
                End If
            End If
        End If
    Next
    UzWord_Range = cnt
End Function

Private Function UzWord_IsUniform(ByVal r As Object) As Boolean
    Dim ok As Boolean
    On Error GoTo bad
    ok = (r.Fields.Count = 0) And (r.Hyperlinks.Count = 0) And (r.InlineShapes.Count = 0)
    If ok Then ok = (r.Font.Name <> "") And (r.Font.Size <> 9999999) And (r.Font.Bold <> 9999999) _
        And (r.Font.Italic <> 9999999) And (r.Font.Underline <> 9999999) And (r.Font.ColorIndex <> 9999999) _
        And (r.Font.Superscript <> 9999999) And (r.Font.Subscript <> 9999999) And (r.Font.Hidden <> 9999999) _
        And (r.HighlightColorIndex <> 9999999)
    UzWord_IsUniform = ok
    Exit Function
bad:
    UzWord_IsUniform = False
End Function

Private Function UzWord_FontKey(ByVal ch As Object) As String
    On Error Resume Next
    With ch.Font
        UzWord_FontKey = .Name & "|" & .Size & "|" & .Bold & "|" & .Italic & "|" & .Underline & "|" & .ColorIndex & _
            "|" & .Superscript & "|" & .Subscript & "|" & .Hidden & "|" & ch.HighlightColorIndex
    End With
End Function

' mixed formatting: split into runs of identical formatting, convert each run (reverse order keeps positions valid)
Private Function UzWord_Runs(ByVal doc As Object, ByVal r As Object, ByVal f As String, ByVal t As String) As Long
    Dim ch As Object, key As String, prevKey As String
    Dim starts() As Long, ends() As Long, nRuns As Long, i As Long, cnt As Long
    Dim rr As Object, s As String, conv As String
    ReDim starts(0 To 64): ReDim ends(0 To 64)
    nRuns = 0: prevKey = Chr$(0)
    For Each ch In r.Characters
        key = UzWord_FontKey(ch)
        If key <> prevKey Then
            nRuns = nRuns + 1
            If nRuns > UBound(starts) Then ReDim Preserve starts(0 To nRuns * 2): ReDim Preserve ends(0 To nRuns * 2)
            starts(nRuns) = ch.Start
            prevKey = key
        End If
        ends(nRuns) = ch.End
    Next
    For i = nRuns To 1 Step -1
        Set rr = r.Duplicate
        rr.End = ends(i): rr.Start = starts(i)
        If rr.Fields.Count = 0 And rr.Hyperlinks.Count = 0 Then
            s = rr.Text
            conv = UzConvert(s, f, t)
            If conv <> s Then rr.Text = conv: cnt = cnt + 1
        End If
    Next
    UzWord_Runs = cnt
End Function

' ---------- Excel: selected cells (one cell selected → whole used range), constants only ----------
Private Function UzExcel_Run(ByVal app As Object, ByVal f As String, ByVal t As String) As Long
    Dim target As Object, txtCells As Object, c As Object, cnt As Long, v As Variant, s As String, conv As String
    Dim singleCell As Boolean
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
    On Error GoTo 0
    For Each c In txtCells
        v = c.Value
        If VarType(v) = vbString Then
            s = v
            conv = UzConvert(s, f, t)
            If conv <> s Then c.Value = conv: cnt = cnt + 1
        End If
    Next
    On Error Resume Next
    app.ScreenUpdating = True
    On Error GoTo 0
    UzExcel_Run = cnt
End Function

' ---------- PowerPoint: every shape, group, table cell and notes page; run-level (keeps formatting) ----------
Private Function UzPpt_Run(ByVal app As Object, ByVal f As String, ByVal t As String) As Long
    Dim pres As Object, sld As Object, shp As Object, cnt As Long, notes As Object
    Set pres = app.ActivePresentation
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

Private Function UzPpt_TextRange(ByVal tr As Object, ByVal f As String, ByVal t As String) As Long
    Dim i As Long, cnt As Long, run As Object, s As String, conv As String
    For i = 1 To tr.Runs.Count
        Set run = tr.Runs(i)
        s = run.Text
        conv = UzConvert(s, f, t)
        If conv <> s Then run.Text = conv: cnt = cnt + 1
    Next
    UzPpt_TextRange = cnt
End Function

' =====================================================================================
'  ENGINE (mirrors spec/SPEC.md §5)
' =====================================================================================

' ---------- Cyrillic → Latin (toNew=False: 1995, toNew=True: 2026) ----------
Private Function CyrToLatin(ByVal s As String, ByVal toNew As Boolean) As String
    Dim n As Long, i As Long, c As Integer, L As Integer, P As Integer, nx As Integer, NL As Integer
    Dim up As Boolean, r As String, buf As String, pos As Long
    Dim okinaS As String, tutuqS As String
    okinaS = MarkOkina(): tutuqS = MarkTutuq()
    n = Len(s)
    buf = Space$(n * 2 + 16): pos = 0
    For i = 1 To n
        c = AscW(Mid$(s, i, 1))
        If Not IsCyr(c) Then
            Put1 buf, pos, c
        Else
            L = CyrLower(c): up = IsCyrUpper(c)
            P = 0: If i > 1 Then P = AscW(Mid$(s, i - 1, 1))
            nx = 0: If i < n Then nx = AscW(Mid$(s, i + 1, 1))
            NL = CyrLower(nx)
            Select Case L
                Case &H435                                               ' е
                    If (Not IsCyr(P)) Or IsCyrVowel(P) Or CyrLower(P) = &H44A Or CyrLower(P) = &H44C Then r = "ye" Else r = "e"
                Case &H446                                               ' ц
                    If IsCyrVowel(P) Then r = "ts" Else r = "s"
                Case &H44A                                               ' ъ
                    If NL = &H435 Or NL = &H451 Or NL = &H44E Or NL = &H44F Then
                        r = ""
                    ElseIf CyrLower(P) = &H45E And Not UzOptKeepHardSignAfterO Then
                        r = ""
                    Else
                        r = tutuqS
                    End If
                Case &H44C: r = ""                                       ' ь
                Case &H448, &H449                                        ' ш щ
                    If toNew Then r = ChrW(&H15F) Else r = "sh"
                Case &H447                                               ' ч
                    If toNew Then r = ChrW(&HE7) Else r = "ch"
                Case &H45E                                               ' ў
                    If toNew Then r = ChrW(&HF6) Else r = "o" & okinaS
                Case &H493                                               ' ғ
                    If toNew Then r = ChrW(&H11F) Else r = "g" & okinaS
                Case &H441                                               ' с (+ҳ)
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

Private Function C2L(ByVal L As Integer) As String
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

' ---------- Latin → Cyrillic ----------
Private Function L2C(ByVal L As Integer) As Integer
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
        Case &HF6, &H14D, &HF5: L2C = &H45E   ' ö ō õ
        Case &H11F: L2C = &H493 ' ğ
        Case &H15F: L2C = &H448 ' ş
        Case &HE7: L2C = &H447  ' ç
        Case Else: L2C = 0
    End Select
End Function

Private Sub EmitCyr(ByRef buf As String, ByRef pos As Long, ByVal lowerCode As Integer, ByVal up As Boolean)
    If up Then
        Put1 buf, pos, CyrUpper(lowerCode)
    Else
        Put1 buf, pos, lowerCode
    End If
End Sub

Private Function LatinToCyrScan(ByVal s As String, ByVal isNew As Boolean, ByVal prevCtx As Integer) As String
    Dim n As Long, i As Long, c As Integer, L As Integer, nx As Integer, N2 As Integer, NL As Integer, P As Integer
    Dim up As Boolean, prevIsLetter As Boolean, prevIsVA As Boolean, wordEnds As Boolean
    Dim buf As String, pos As Long, rest As String, r As Integer
    n = Len(s)
    buf = Space$(n * 2 + 16): pos = 0
    i = 1
    Do While i <= n
        c = AscW(Mid$(s, i, 1))
        If i > 1 Then P = AscW(Mid$(s, i - 1, 1)) Else P = prevCtx
        nx = 0: If i < n Then nx = AscW(Mid$(s, i + 1, 1))
        N2 = 0: If i + 1 < n Then N2 = AscW(Mid$(s, i + 2, 1))
        If IsApos(c) Then
            If IsLat(P) And IsLat(nx) Then
                EmitCyr buf, pos, &H44A, IsLatUpper(P)                   ' ъ
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
            If L = 111 And IsApos(nx) Then                                ' oʻ
                EmitCyr buf, pos, &H45E, up: i = i + 2
            ElseIf L = 103 And IsApos(nx) Then                            ' gʻ
                EmitCyr buf, pos, &H493, up: i = i + 2
            ElseIf L = 115 And NL = 104 And Not isNew Then               ' sh (1995)
                EmitCyr buf, pos, &H448, up: i = i + 2
            ElseIf L = 115 And IsApos(nx) And LatLower(N2) = 104 Then     ' sʼh
                EmitCyr buf, pos, &H441, up: i = i + 2
            ElseIf L = 99 And NL = 104 Then                              ' ch
                EmitCyr buf, pos, &H447, up: i = i + 2
            ElseIf L = 121 And (NL = 111 Or NL = 117 Or NL = 97 Or NL = 101) Then   ' y + vowel
                If NL = 111 And IsApos(N2) Then
                    EmitCyr buf, pos, &H439, up: i = i + 1               ' yoʻ → йў
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
            ElseIf L = 116 And NL = 115 And TsRule(s, i, n, P) Then      ' ts → ц
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

Private Function TsRule(ByVal s As String, ByVal i As Long, ByVal n As Long, ByVal P As Integer) As Boolean
    Dim rest As String, wordEnds As Boolean
    rest = LCase$(Mid$(s, i + 2, 3))
    If Left$(rest, 3) = "iya" Or Left$(rest, 3) = "ion" Then TsRule = True: Exit Function
    If UzOptNoTsFinal Then Exit Function
    If i + 2 > n Then wordEnds = True Else wordEnds = Not IsLat(AscW(Mid$(s, i + 2, 1)))
    TsRule = wordEnds And IsLatVowel(P)
End Function

Private Function LatinToCyr(ByVal s As String, ByVal isNew As Boolean) As String
    Dim n As Long, i As Long, j As Long, c As Integer, out As String
    If UzOptNoDictionary Then LatinToCyr = LatinToCyrScan(s, isNew, 0): Exit Function
    n = Len(s): i = 1
    Do While i <= n
        c = AscW(Mid$(s, i, 1))
        If Not (IsLat(c) Or IsApos(c)) Then
            out = out & ChrW(c): i = i + 1
        Else
            j = i
            Do While j <= n
                c = AscW(Mid$(s, j, 1))
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
    Dim letters As Long, uppers As Long, firstUpper As Boolean, q As Long, ch As Integer
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
        ch = AscW(Mid$(stemSrc, q, 1))
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
    WordWithDict = cyrStem & LatinToCyrScan(rest, isNew, AscW(Right$(stemSrc, 1)))
End Function

Private Function NormKey(ByVal w As String) As String
    Dim i As Long, c As Integer, o As String
    For i = 1 To Len(w)
        c = LatLower(AscW(Mid$(w, i, 1)))
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

' ---------- Latin 1995 → Latin 2026 ----------
Private Function LatToNew(ByVal s As String) As String
    Dim n As Long, i As Long, c As Integer, L As Integer, nx As Integer, N2 As Integer, NL As Integer, P As Integer
    Dim up As Boolean, buf As String, pos As Long
    n = Len(s): buf = Space$(n + 16): pos = 0: i = 1
    Do While i <= n
        c = AscW(Mid$(s, i, 1)): L = LatLower(c): up = IsLatUpper(c)
        nx = 0: If i < n Then nx = AscW(Mid$(s, i + 1, 1))
        N2 = 0: If i + 1 < n Then N2 = AscW(Mid$(s, i + 2, 1))
        NL = LatLower(nx)
        P = 0: If i > 1 Then P = AscW(Mid$(s, i - 1, 1))
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

' ---------- Latin 2026 → Latin 1995 ----------
Private Function NewToLat(ByVal s As String) As String
    Dim n As Long, i As Long, c As Integer, L As Integer, nx As Integer, NL As Integer, P As Integer
    Dim up As Boolean, buf As String, pos As Long
    n = Len(s): buf = Space$(n * 2 + 16): pos = 0: i = 1
    Do While i <= n
        c = AscW(Mid$(s, i, 1)): L = LatLower(c): up = IsLatUpper(c)
        nx = 0: If i < n Then nx = AscW(Mid$(s, i + 1, 1))
        NL = LatLower(nx)
        P = 0: If i > 1 Then P = AscW(Mid$(s, i - 1, 1))
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
            Put1 buf, pos, c: PutS buf, pos, MarkTutuq()                 ' Ishoq → Isʼhoq
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

Private Sub Put1(ByRef buf As String, ByRef pos As Long, ByVal c As Integer)
    pos = pos + 1
    Mid$(buf, pos, 1) = ChrW(c)
End Sub
Private Sub PutS(ByRef buf As String, ByRef pos As Long, ByVal s As String)
    If Len(s) = 0 Then Exit Sub
    Mid$(buf, pos + 1, Len(s)) = s
    pos = pos + Len(s)
End Sub

Private Function InSet(ByVal setStr As String, ByVal c As Integer) As Boolean
    If c <= 0 Then Exit Function
    InSet = (InStr(1, setStr, ChrW(c), vbBinaryCompare) > 0)
End Function
Private Function IsCyr(ByVal c As Integer) As Boolean
    IsCyr = InSet(mCyrLower, c) Or InSet(mCyrUpper, c)
End Function
Private Function IsCyrUpper(ByVal c As Integer) As Boolean
    IsCyrUpper = InSet(mCyrUpper, c)
End Function
Private Function CyrLower(ByVal c As Integer) As Integer
    Dim p As Long
    CyrLower = c
    If c <= 0 Then Exit Function
    p = InStr(1, mCyrUpper, ChrW(c), vbBinaryCompare)
    If p > 0 Then CyrLower = AscW(Mid$(mCyrLower, p, 1))
End Function
Private Function CyrUpper(ByVal c As Integer) As Integer
    Dim p As Long
    CyrUpper = c
    If c <= 0 Then Exit Function
    p = InStr(1, mCyrLower, ChrW(c), vbBinaryCompare)
    If p > 0 Then CyrUpper = AscW(Mid$(mCyrUpper, p, 1))
End Function
Private Function IsCyrVowel(ByVal c As Integer) As Boolean
    IsCyrVowel = InSet(mCyrVowels, CyrLower(c))
End Function
Private Function IsLat(ByVal c As Integer) As Boolean
    IsLat = InSet(mLatLower, c) Or InSet(mLatUpper, c)
End Function
Private Function IsLatUpper(ByVal c As Integer) As Boolean
    IsLatUpper = InSet(mLatUpper, c)
End Function
Private Function LatLower(ByVal c As Integer) As Integer
    Dim p As Long
    LatLower = c
    If c <= 0 Then Exit Function
    p = InStr(1, mLatUpper, ChrW(c), vbBinaryCompare)
    If p > 0 Then LatLower = AscW(Mid$(mLatLower, p, 1))
End Function
Private Function LatUpper(ByVal c As Integer) As Integer
    Dim p As Long
    LatUpper = c
    If c <= 0 Then Exit Function
    p = InStr(1, mLatLower, ChrW(c), vbBinaryCompare)
    If p > 0 Then LatUpper = AscW(Mid$(mLatUpper, p, 1))
End Function
Private Function IsLatVowel(ByVal c As Integer) As Boolean
    IsLatVowel = InSet(mLatVowels, LatLower(c))
End Function
Private Function IsApos(ByVal c As Integer) As Boolean
    IsApos = InSet(mApos, c)
End Function
Private Function IsLetter(ByVal c As Integer) As Boolean
    IsLetter = IsCyr(c) Or IsLat(c)
End Function
Private Function IsUpperLetter(ByVal c As Integer) As Boolean
    IsUpperLetter = IsCyrUpper(c) Or IsLatUpper(c)
End Function

Private Function UpperStr(ByVal s As String) As String
    Dim i As Long, o As String
    For i = 1 To Len(s)
        o = o & ChrW(LatUpper(CyrUpper(AscW(Mid$(s, i, 1)))))
    Next
    UpperStr = o
End Function
Private Function UpperFirst(ByVal s As String) As String
    If Len(s) = 0 Then Exit Function
    UpperFirst = ChrW(LatUpper(CyrUpper(AscW(Left$(s, 1))))) & Mid$(s, 2)
End Function

' SPEC §4: next letter (skipping one apostrophe) uppercase → ALL CAPS; else previous letter if no next letter
Private Function NextLetterIsUpper(ByVal s As String, ByVal i As Long) As Boolean
    Dim j As Long, k As Long, c As Integer, n As Long
    n = Len(s)
    j = i + 1
    If j <= n Then If IsApos(AscW(Mid$(s, j, 1))) Then j = j + 1
    If j <= n Then
        c = AscW(Mid$(s, j, 1))
        If IsLetter(c) Then NextLetterIsUpper = IsUpperLetter(c): Exit Function
    End If
    k = i - 1
    If k >= 1 Then If IsApos(AscW(Mid$(s, k, 1))) Then k = k - 1
    If k >= 1 Then
        c = AscW(Mid$(s, k, 1))
        If IsLetter(c) Then NextLetterIsUpper = IsUpperLetter(c): Exit Function
    End If
    NextLetterIsUpper = False
End Function

Private Function CaseOut(ByVal s As String, ByVal i As Long, ByVal srcUpper As Boolean, ByVal r As String) As String
    If (Not srcUpper) Or Len(r) = 0 Then CaseOut = r: Exit Function
    If Len(r) = 1 Then CaseOut = UpperStr(r): Exit Function
    If NextLetterIsUpper(s, i) Then CaseOut = UpperStr(r) Else CaseOut = UpperFirst(r)
End Function

' "043E 0431" -> "об"
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
    ' --- dictionary, longest keys first (generated from spec/SPEC.md §6) ---
    AddD "konsentratsiya", U("043A 043E 043D 0446 0435 043D 0442 0440 0430 0446 0438 044F")
    AddD "sivilizatsiya", U("0446 0438 0432 0438 043B 0438 0437 0430 0446 0438 044F")
    AddD "konstruksiya", U("043A 043E 043D 0441 0442 0440 0443 043A 0446 0438 044F")
    AddD "konferensiya", U("043A 043E 043D 0444 0435 0440 0435 043D 0446 0438 044F")
    AddD "differensial", U("0434 0438 0444 0444 0435 0440 0435 043D 0446 0438 0430 043B")
    AddD "sotsiologiya", U("0441 043E 0446 0438 043E 043B 043E 0433 0438 044F")
    AddD "konyunktura", U("043A 043E 043D 044A 044E 043D 043A 0442 0443 0440 0430")
    AddD "shampinyon", U("0448 0430 043C 043F 0438 043D 044C 043E 043D")
    AddD "sellyuloza", U("0446 0435 043B 043B 044E 043B 043E 0437 0430")
    AddD "seremoniya", U("0446 0435 0440 0435 043C 043E 043D 0438 044F")
    AddD "produksiya", U("043F 0440 043E 0434 0443 043A 0446 0438 044F")
    AddD "kolleksiya", U("043A 043E 043B 043B 0435 043A 0446 0438 044F")
    AddD "proporsiya", U("043F 0440 043E 043F 043E 0440 0446 0438 044F")
    AddD "litsenziya", U("043B 0438 0446 0435 043D 0437 0438 044F")
    AddD "protsedura", U("043F 0440 043E 0446 0435 0434 0443 0440 0430")
    AddD "konsepsiya", U("043A 043E 043D 0446 0435 043F 0446 0438 044F")
    AddD "inyeksiya", U("0438 043D 044A 0435 043A 0446 0438 044F")
    AddD "kompyuter", U("043A 043E 043C 043F 044C 044E 0442 0435 0440")
    AddD "redaksiya", U("0440 0435 0434 0430 043A 0446 0438 044F")
    AddD "infeksiya", U("0438 043D 0444 0435 043A 0446 0438 044F")
    AddD "potensial", U("043F 043E 0442 0435 043D 0446 0438 0430 043B")
    AddD "spetsifik", U("0441 043F 0435 0446 0438 0444 0438 043A")
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
    AddD "subyekt", U("0441 0443 0431 044A 0435 043A 0442")
    AddD "tatyana", U("0442 0430 0442 044C 044F 043D 0430")
    AddD "senzura", U("0446 0435 043D 0437 0443 0440 0430")
    AddD "sentner", U("0446 0435 043D 0442 043D 0435 0440")
    AddD "silindr", U("0446 0438 043B 0438 043D 0434 0440")
    AddD "sitadel", U("0446 0438 0442 0430 0434 0435 043B 044C")
    AddD "leksiya", U("043B 0435 043A 0446 0438 044F")
    AddD "seksiya", U("0441 0435 043A 0446 0438 044F")
    AddD "porsiya", U("043F 043E 0440 0446 0438 044F")
    AddD "ofitser", U("043E 0444 0438 0446 0435 0440")
    AddD "konsert", U("043A 043E 043D 0446 0435 0440 0442")
    AddD "konsern", U("043A 043E 043D 0446 0435 0440 043D")
    AddD "sotsial", U("0441 043E 0446 0438 0430 043B")
    AddD "shprits", U("0448 043F 0440 0438 0446")
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
    AddD "sentr", U("0446 0435 043D 0442 0440")
    AddD "sokol", U("0446 043E 043A 043E 043B 044C")
    AddD "plats", U("043F 043B 0430 0446")
    AddD "blits", U("0431 043B 0438 0446")
    AddD "ilya", U("0438 043B 044C 044F")
    AddD "yoga", U("0439 043E 0433 0430")
    AddD "york", U("0439 043E 0440 043A")
    AddD "yota", U("0439 043E 0442 0430")
    AddD "sirk", U("0446 0438 0440 043A")
    AddD "sikl", U("0446 0438 043A 043B")
    AddD "sink", U("0446 0438 043D 043A")
    AddD "yod", U("0439 043E 0434")
    AddD "sex", U("0446 0435 0445")
End Sub

' =====================================================================================
'  SELF-TEST (Alt+F8 → UzSelfTest). Mirrors a sample of spec/fixtures.json.
' =====================================================================================
Public Sub UzSelfTest()
    Dim ok As Long, bad As Long, msg As String
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
    MsgBox "UzTranslit self-test: " & ok & " passed, " & bad & " failed" & IIf(bad > 0, vbCrLf & vbCrLf & msg, ""), IIf(bad > 0, vbExclamation, vbInformation), "UzTranslit"
End Sub

Private Sub T(ByRef ok As Long, ByRef bad As Long, ByRef msg As String, ByVal got As String, ByVal want As String)
    If got = want Then
        ok = ok + 1
    Else
        bad = bad + 1
        If Len(msg) < 1500 Then msg = msg & "want: " & want & vbCrLf & "got:  " & got & vbCrLf
    End If
End Sub
