' ===== Generated from office-vba/UzTranslit.bas by tools/make_lo_basic.py -- do not edit the engine here =====
Option Explicit
Option VBASupport 1
' =====================================================================================
'  UzTranslit v1.0.0 -- O'zbek alifbo konvertori for Microsoft Office 97 ... 2026
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
                Case &H44C: r = ""                                       ' cyr soft sign
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

' the dialog's texts in three languages (generated by tools/make_lo_basic.py)
Private Function UzLO_Text(ByVal lang As String, ByVal key As String) As String
    Dim s As String
    UzInit
    Select Case lang & "|" & key
        Case "en|title": s = "UzTranslit settings"
        Case "uz|title": s = "UzTranslit sozlamalari"
        Case "ru|title": s = U("041D 0430 0441 0442 0440 043E 0439 043A 0438") & " UzTranslit"
        Case "en|Ascii": s = "Plain apostrophe (') instead of " & U("02BB") & " and " & U("02BC")
        Case "uz|Ascii": s = "Oddiy apostrof (') " & U("2014") & " " & U("02BB") & " va " & U("02BC") & " o" & U("02BB") & "rniga"
        Case "ru|Ascii": s = U("041F 0440 043E 0441 0442 043E 0439") & " " & U("0430 043F 043E 0441 0442 0440 043E 0444") & " (') " & U("0432 043C 0435 0441 0442 043E") & " " & U("02BB") & " " & U("0438") & " " & U("02BC")
        Case "en|Dictionary": s = "Loanword dictionary (obyekt " & U("2192") & " " & U("043E 0431 044A 0435 043A 0442") & ", kompyuter " & U("2192") & " " & U("043A 043E 043C 043F 044C 044E 0442 0435 0440") & ")"
        Case "uz|Dictionary": s = "O" & U("02BB") & "zlashma so" & U("02BB") & "zlar lug" & U("02BB") & "ati (obyekt " & U("2192") & " " & U("043E 0431 044A 0435 043A 0442") & ", kompyuter " & U("2192") & " " & U("043A 043E 043C 043F 044C 044E 0442 0435 0440") & ")"
        Case "ru|Dictionary": s = U("0421 043B 043E 0432 0430 0440 044C") & " " & U("0437 0430 0438 043C 0441 0442 0432 043E 0432 0430 043D 0438 0439") & " (obyekt " & U("2192") & " " & U("043E 0431 044A 0435 043A 0442") & ", kompyuter " & U("2192") & " " & U("043A 043E 043C 043F 044C 044E 0442 0435 0440") & ")"
        Case "en|KeepHardSignAfterO": s = "Keep " & U("044A") & " after " & U("045E") & " as " & U("02BC") & " (" & U("043C 045E 044A 0436 0438 0437 0430") & " " & U("2192") & " mo" & U("02BB 02BC") & "jiza)"
        Case "uz|KeepHardSignAfterO": s = U("045E") & " dan keyingi " & U("044A") & " " & U("02BC") & " bo" & U("02BB") & "lib qolsin (" & U("043C 045E 044A 0436 0438 0437 0430") & " " & U("2192") & " mo" & U("02BB 02BC") & "jiza)"
        Case "ru|KeepHardSignAfterO": s = U("0421 043E 0445 0440 0430 043D 044F 0442 044C") & " " & U("044A") & " " & U("043F 043E 0441 043B 0435") & " " & U("045E") & " " & U("043A 0430 043A") & " " & U("02BC") & " (" & U("043C 045E 044A 0436 0438 0437 0430") & " " & U("2192") & " mo" & U("02BB 02BC") & "jiza)"
        Case "en|TsFinal": s = "Word-final ts becomes " & U("0446") & " (Latin to Cyrillic)"
        Case "uz|TsFinal": s = "So" & U("02BB") & "z oxiridagi ts " & U("2192") & " " & U("0446") & " (lotindan kirillga)"
        Case "ru|TsFinal": s = "ts " & U("0432") & " " & U("043A 043E 043D 0446 0435") & " " & U("0441 043B 043E 0432 0430") & " " & U("2192") & " " & U("0446") & " (" & U("0438 0437") & " " & U("043B 0430 0442 0438 043D 0438 0446 044B") & " " & U("0432") & " " & U("043A 0438 0440 0438 043B 043B 0438 0446 0443") & ")"
        Case "en|SkipUrls": s = "Leave web addresses and e-mail addresses as they are"
        Case "uz|SkipUrls": s = "Sayt va e-pochta manzillari o" & U("02BB") & "zgarmasin"
        Case "ru|SkipUrls": s = U("041D 0435") & " " & U("043C 0435 043D 044F 0442 044C") & " " & U("0430 0434 0440 0435 0441 0430") & " " & U("0441 0430 0439 0442 043E 0432") & " " & U("0438") & " " & U("044D 043B 0435 043A 0442 0440 043E 043D 043D 043E 0439") & " " & U("043F 043E 0447 0442 044B")
        Case "en|ok": s = "OK"
        Case "uz|ok": s = "OK"
        Case "ru|ok": s = "OK"
        Case "en|cancel": s = "Cancel"
        Case "uz|cancel": s = "Bekor qilish"
        Case "ru|cancel": s = U("041E 0442 043C 0435 043D 0430")
    End Select
    If s = "" And lang <> "en" Then s = UzLO_Text("en", key)
    UzLO_Text = s
End Function
