#!/usr/bin/env python3
"""Static checks for VBA modules that LibreOffice's VBA mode lets through. Real VBA compiles the whole module on the
first call, so a single undeclared name in a Word-only macro would break every macro, UzConvert() included.

usage: python3 tools/vba_lint.py FILE.bas...      (exit 1 on any finding; modules given together share a file)

  * every identifier is declared (module level, parameters, Dim / Const / Static), names a procedure or label of the
    module, or is a VBA keyword, function or constant listed below; members after a dot are the host's business
  * Exit Sub only in a Sub, Exit Function only in a Function
  * ASCII only, CRLF line ends, Attribute VB_Name first: what the VBA editor's File > Import needs
"""
import re
import sys

VBA_WORDS = """
and or not xor eqv imp mod is like new nothing null empty true false me
if then else elseif end select case for to step next each in do loop while wend until exit sub function property get
let set dim redim preserve static const private public global friend byval byref optional paramarray as call goto
gosub return on error resume option explicit compare binary text base attribute with open close output input append
print line write put lock unlock shared access read random typeof type enum declare lib alias ptrsafe erase stop
long integer string boolean variant object double single byte date currency decimal longlong longptr any
len mid mid$ left left$ right right$ lcase lcase$ ucase ucase$ trim trim$ ltrim ltrim$ rtrim rtrim$ instr instrrev
replace split join chr chr$ chrw chrw$ asc ascw cstr clng cint cdbl cbool cvar cdate val str str$ isnumeric isnull
isempty isarray isobject isdate ismissing typename vartype ubound lbound array msgbox inputbox err error error$ erl
freefile dir dir$ eof space space$ string$ format format$ now timer doevents application environ environ$ strcomp
strconv abs int fix sgn hex hex$ iif createobject getobject
vbstring vblf vbcr vbcrlf vbnullchar vbnullstring vbtab vbyesno vbyes vbno vbquestion vbinformation vbexclamation
vbcritical vbokonly vbtextcompare vbbinarycompare vbobject vbempty vbnull vbinteger vblong vbdouble vbboolean
vbvariant vbarray vbdate vberror vbnewline
""".split()

PROC = re.compile(r"^(?:(?:Public|Private|Friend)\s+)?(?:Static\s+)?(Sub|Function|Property\s+(?:Get|Let|Set))\s+(\w+)\s*\(", re.I)
END_PROC = re.compile(r"^End\s+(Sub|Function|Property)\b", re.I)
DECL = re.compile(r"^(?:(?:Public|Private)\s+Const|Dim|Static|ReDim(?:\s+Preserve)?|Public|Private|Global|Const)\s+(.*)$", re.I)
IDENT = re.compile(r"(?<![\w.])([A-Za-z][A-Za-z0-9_]*[$%&!#@]?)")


def logical_lines(src):
    """(first line number, code) with strings blanked, comments dropped and ' _' continuations joined."""
    out, buf, start = [], "", None
    for no, raw in enumerate(src.split("\n"), 1):
        line = raw.rstrip("\r")
        code, i, in_str = [], 0, False
        while i < len(line):
            ch = line[i]
            if in_str:
                if ch == '"':
                    if line[i + 1:i + 2] == '"':
                        i += 2
                        continue
                    in_str = False
                    code.append('"')
                i += 1
                continue
            if ch == '"':
                in_str = True
                code.append('"')
            elif ch == "'":
                break
            else:
                code.append(ch)
            i += 1
        code = "".join(code)
        if re.match(r"\s*Rem\b", code, re.I):
            code = ""
        if start is None:
            start = no
        if code.rstrip().endswith(" _"):
            buf += code.rstrip()[:-2] + " "
            continue
        out.append((start, (buf + code).strip()))
        buf, start = "", None
    return out


def params_of(code, open_at):
    """The text between the parenthesis at open_at and its partner."""
    depth = 0
    for i in range(open_at, len(code)):
        if code[i] == "(":
            depth += 1
        elif code[i] == ")":
            depth -= 1
            if depth == 0:
                return code[open_at + 1:i]
    return code[open_at + 1:]


def split_top(s, sep=","):
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return parts


def declared_names(decl_list):
    names = []
    for part in split_top(decl_list):
        part = re.sub(r"^\s*(Optional|ByVal|ByRef|ParamArray|WithEvents)\s+", "", part.strip(), flags=re.I)
        part = re.sub(r"^\s*(ByVal|ByRef)\s+", "", part, flags=re.I)
        m = re.match(r"([A-Za-z]\w*[$%&!#@]?)", part)
        if m:
            names.append(m.group(1).rstrip("$%&!#@").lower())
    return names


def statements(code):
    """Splits a logical line at ':' statement separators (not ':=')."""
    return [s.strip() for s in re.split(r":(?!=)", code) if s.strip()]


def public_procs(path):
    """Public procedures of a module, which the other modules of the same file may call."""
    names = set()
    for _, code in logical_lines(open(path, "rb").read().decode("ascii", "replace")):
        m = PROC.match(code)
        if m and not code.lower().startswith(("private", "friend")):
            names.add(m.group(2).lower())
    return names


def lint(path, others=frozenset()):
    raw = open(path, "rb").read()
    problems = []
    try:
        src = raw.decode("ascii")
    except UnicodeDecodeError as e:
        return ["%s: not ASCII (byte %d): the VBA editor reads modules in the system code page" % (path, e.start)]
    if b"\n" in raw.replace(b"\r\n", b""):
        problems.append("%s: LF line ends: the VBA editor's Import needs CRLF" % path)
    if not src.startswith("Attribute VB_Name"):
        problems.append("%s: does not start with Attribute VB_Name" % path)
    lines = logical_lines(src)
    module, procs, current = set(), {}, None
    for no, code in lines:
        m = PROC.match(code)
        if m:
            current = m.group(2).lower()
            procs[current] = (m.group(1).split()[0].lower(), no, params_of(code, m.end() - 1), [])
            continue
        if END_PROC.match(code):
            current = None
            continue
        if current:
            procs[current][3].append((no, code))
        else:
            for st in statements(code):
                d = DECL.match(st)
                if d and not st.lower().startswith(("option", "attribute")):
                    module.update(declared_names(re.sub(r"=.*$", "", d.group(1))))
    known = set(VBA_WORDS) | module | set(procs) | set(others)
    for name, (kind, start, params, body) in procs.items():
        local = set(declared_names(params)) | {name}
        labels = set()
        for no, code in body:
            lm = re.match(r"^([A-Za-z]\w*):(?!=)", code)
            if lm and lm.group(1).lower() not in ("else",):
                labels.add(lm.group(1).lower())
            for st in statements(code):
                d = DECL.match(st)
                if d and not re.match(r"ReDim", st, re.I):
                    local.update(declared_names(re.sub(r"\s=\s.*$", "", d.group(1))))
                if kind == "sub" and re.search(r"\bExit\s+Function\b", st, re.I):
                    problems.append("%s:%d: Exit Function in Sub %s" % (path, no, name))
                if kind == "function" and re.search(r"\bExit\s+Sub\b", st, re.I):
                    problems.append("%s:%d: Exit Sub in Function %s" % (path, no, name))
        for no, code in body:
            # literals and type names are not identifiers to check
            c = re.sub(r'"[^"]*"', '""', code)
            c = re.sub(r"&[HO][0-9A-Fa-f]+&?", "0", c)
            c = re.sub(r"\b\d+(\.\d+)?([eE][+-]?\d+)?[#!&%@]?", "0", c)
            c = re.sub(r"\bAs\s+(New\s+)?[A-Za-z_][\w.]*", "", c, flags=re.I)
            c = re.sub(r"\b[A-Za-z]\w*\s*:=", "", c)
            c = re.sub(r"^[A-Za-z]\w*:(?!=)", "", c)
            for m in IDENT.finditer(c):
                word = m.group(1)
                key = word.lower()
                if key in known or key.rstrip("$%&!#@") in local or key in local or key.rstrip("$%&!#@") in known or key in labels:
                    continue
                problems.append("%s:%d: '%s' is not declared (in %s)" % (path, no, word, name))
    return problems


def main():
    problems, paths = [], sys.argv[1:]
    for p in paths:  # the modules given together go into one file: each may call the others' public procedures
        others = set().union(*[public_procs(q) for q in paths if q != p]) if len(paths) > 1 else set()
        problems += lint(p, others)
    for p in problems:
        print(p)
    print("%d problem(s)" % len(problems) if problems else "vba lint: clean")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
