# ---------------------------------------------------------------------------------------------
#  LibreOffice UNO glue (appended after the core by tools/build_oxt.py → uztranslit_lo.py)
#  Menu: Tools ▸ UzTranslit ▸ …   (Writer, Calc, Impress, Draw). Selection first, else whole document.
# ---------------------------------------------------------------------------------------------
import uno  # noqa: E402
from com.sun.star.awt.MessageBoxType import INFOBOX, WARNINGBOX, QUERYBOX  # noqa: E402
from com.sun.star.awt.MessageBoxButtons import BUTTONS_OK, BUTTONS_YES_NO  # noqa: E402

CELL_STRING = 4  # com.sun.star.sheet.CellFlags.STRING


def _msg(doc, text, kind=INFOBOX, buttons=BUTTONS_OK):
    try:
        ctx = uno.getComponentContext()
        tk = ctx.ServiceManager.createInstanceWithContext("com.sun.star.awt.Toolkit", ctx)
        win = doc.CurrentController.Frame.ContainerWindow
        box = tk.createMessageBox(win, kind, buttons, "UzTranslit", text)
        return box.execute()
    except Exception:
        return 0


def _xtext(xt, f, t):
    """Convert every text portion of an XText (handles Writer text tables)."""
    cnt = 0
    if xt is None:
        return 0
    en = xt.createEnumeration()
    while en.hasMoreElements():
        el = en.nextElement()
        if el.supportsService("com.sun.star.text.TextTable"):
            for name in el.getCellNames():
                cnt += _xtext(el.getCellByName(name), f, t)
        elif el.supportsService("com.sun.star.text.Paragraph"):
            pe = el.createEnumeration()
            while pe.hasMoreElements():
                por = pe.nextElement()
                if por.TextPortionType == "Text":
                    s = por.getString()
                    if s:
                        c = convert(s, f, t)
                        if c != s:
                            _replace_portion(por, c)
                            cnt += 1
    return cnt


_CHAR_PROPS = ("CharWeight", "CharPosture", "CharUnderline", "CharUnderlineColor", "CharUnderlineHasColor", "CharColor",
               "CharHeight", "CharFontName", "CharStrikeout", "CharBackColor", "CharBackTransparent", "CharEscapement",
               "CharEscapementHeight", "CharCaseMap", "CharHidden", "CharShadowed", "CharContoured", "CharOverline",
               "CharRelief", "CharWeightAsian", "CharPostureAsian", "CharHeightAsian", "CharFontNameAsian", "CharKerning", "CharScaleWidth")


def _replace_portion(por, conv):
    """setString alone makes a run at paragraph start inherit its neighbour's attributes; save & restore them."""
    saved = []
    for n in _CHAR_PROPS:
        try:
            saved.append((n, por.getPropertyValue(n)))
        except Exception:
            pass
    cur = por.getText().createTextCursorByRange(por)
    cur.setString(conv)
    for n, v in saved:
        try:
            cur.setPropertyValue(n, v)
        except Exception:
            pass


def _writer(doc, f, t):
    cnt = 0
    had_sel = False
    try:
        sel = doc.CurrentController.getSelection()
        if sel is not None and sel.supportsService("com.sun.star.text.TextRanges"):
            for i in range(sel.getCount()):
                rng = sel.getByIndex(i)
                if rng.getString():
                    had_sel = True
                    cur = rng.getText().createTextCursorByRange(rng)
                    cnt += _xtext(cur, f, t)
    except Exception:
        pass
    if had_sel:
        return cnt
    cnt += _xtext(doc.getText(), f, t)
    for getter in ("getTextFrames", "getFootnotes", "getEndnotes"):
        try:
            coll = getattr(doc, getter)()
            for i in range(coll.getCount()):
                cnt += _xtext(coll.getByIndex(i), f, t)
        except Exception:
            pass
    try:
        styles = doc.getStyleFamilies().getByName("PageStyles")
        for i in range(styles.getCount()):
            ps = styles.getByIndex(i)
            if ps.HeaderIsOn:
                cnt += _xtext(ps.HeaderText, f, t)
                if not ps.HeaderIsShared:
                    cnt += _xtext(ps.HeaderTextLeft, f, t)
                if not ps.FirstIsShared:
                    cnt += _xtext(ps.HeaderTextFirst, f, t)
            if ps.FooterIsOn:
                cnt += _xtext(ps.FooterText, f, t)
                if not ps.FooterIsShared:
                    cnt += _xtext(ps.FooterTextLeft, f, t)
                if not ps.FirstIsShared:
                    cnt += _xtext(ps.FooterTextFirst, f, t)
    except Exception:
        pass
    return cnt


def _cell_range(rng, f, t):
    cnt = 0
    en = rng.queryContentCells(CELL_STRING).getCells().createEnumeration()
    while en.hasMoreElements():
        c = en.nextElement()
        s = c.getString()
        conv = convert(s, f, t)
        if conv != s:
            c.setString(conv)
            cnt += 1
    return cnt


def _calc(doc, f, t):
    cnt = 0
    sel = doc.CurrentSelection
    if sel.supportsService("com.sun.star.sheet.SheetCellRanges"):
        for i in range(sel.getCount()):
            cnt += _cell_range(sel.getByIndex(i), f, t)
    elif sel.supportsService("com.sun.star.sheet.SheetCellRange"):
        single = sel.getRows().getCount() == 1 and sel.getColumns().getCount() == 1
        if single and _msg(doc, "Convert the whole sheet? (No = only the selected cell)", QUERYBOX, BUTTONS_YES_NO) == 2:
            cur = doc.CurrentController.getActiveSheet().createCursor()
            cur.gotoStartOfUsedArea(False)
            cur.gotoEndOfUsedArea(True)
            cnt += _cell_range(cur, f, t)
        else:
            cnt += _cell_range(sel, f, t)
    return cnt


def _shapes(container, f, t):
    cnt = 0
    for i in range(container.getCount()):
        shp = container.getByIndex(i)
        if shp.supportsService("com.sun.star.drawing.GroupShape"):
            cnt += _shapes(shp, f, t)
        elif shp.supportsService("com.sun.star.drawing.TableShape"):
            model = shp.Model
            for r in range(model.RowCount):
                for c in range(model.ColumnCount):
                    cnt += _xtext(model.getCellByPosition(c, r), f, t)
        elif shp.supportsService("com.sun.star.drawing.Text"):
            cnt += _xtext(shp, f, t)
    return cnt


def _draw(doc, f, t):
    cnt = 0
    pages = doc.getDrawPages()
    for i in range(pages.getCount()):
        pg = pages.getByIndex(i)
        cnt += _shapes(pg, f, t)
        try:
            np = pg.getNotesPage()
            if np is not None:
                cnt += _shapes(np, f, t)
        except Exception:
            pass
    return cnt


def _run(f, t):
    doc = XSCRIPTCONTEXT.getDocument()  # noqa: F821 (provided by the LibreOffice script context)
    if doc is None:
        return
    if doc.supportsService("com.sun.star.text.TextDocument"):
        cnt = _writer(doc, f, t)
    elif doc.supportsService("com.sun.star.sheet.SpreadsheetDocument"):
        cnt = _calc(doc, f, t)
    elif doc.supportsService("com.sun.star.drawing.DrawingDocument") or doc.supportsService("com.sun.star.presentation.PresentationDocument"):
        cnt = _draw(doc, f, t)
    else:
        _msg(doc, "Unsupported document type", WARNINGBOX)
        return
    _msg(doc, "%d fragment(s) converted (%s -> %s)" % (cnt, f, t))


def cyr_to_lat(*a): _run("cyr", "lat")
def cyr_to_new(*a): _run("cyr", "new")
def lat_to_cyr(*a): _run("lat", "cyr")
def new_to_cyr(*a): _run("new", "cyr")
def lat_to_new(*a): _run("lat", "new")
def new_to_lat(*a): _run("new", "lat")
def auto_to_new(*a): _run("auto", "new")
def auto_to_lat(*a): _run("auto", "lat")
def auto_to_cyr(*a): _run("auto", "cyr")


def self_test(*a):
    doc = XSCRIPTCONTEXT.getDocument()  # noqa: F821
    checks = [
        (convert("Toshkent shahri O'zbekiston", "lat", "new"), "Toşkent şahri Özbekiston"),
        (convert("Ўзбекистон Республикаси", "cyr", "lat"), "Oʻzbekiston Respublikasi"),
        (convert("Is'hoq obyekt", "lat", "cyr"), "Исҳоқ объект"),
        (convert("ŞAHAR Ishoq", "new", "lat"), "SHAHAR Isʼhoq"),
    ]
    bad = [w for g, w in checks if g != w]
    _msg(doc, "UzTranslit %s: %d/%d self-checks passed" % (VERSION, len(checks) - len(bad), len(checks)))


g_exportedScripts = (cyr_to_lat, cyr_to_new, lat_to_cyr, new_to_cyr, lat_to_new, new_to_lat,
                     auto_to_new, auto_to_lat, auto_to_cyr, self_test)
