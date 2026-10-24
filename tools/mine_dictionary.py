#!/usr/bin/env python3
"""Proposes dictionary stems for spec/SPEC.md section 6 from a parallel Cyrillic / Latin 1995 corpus.

The rules are lossy for Russian loans (ц, ъ, ь, йо ...): a Latin word whose rule-based Cyrillic differs from the
Cyrillic attested in the corpus needs a dictionary stem. For every such word this finds the stem that fixes it (the
Latin prefix whose Cyrillic replaces the rule-based one, the rest converting by the rules), widens it to the longest
prefix that all forms of the word share (kompyuter, kompyuterlar, kompyuterda -> kompyuter), and checks it against
the whole corpus: a key that would also catch words the rules already get right (never `sent`, which would hit
`sentabr`) is reported with the words it would break.

usage:
  python3 tools/mine_dictionary.py --cyr kitob.cyr.txt --lat kitob.lat.txt     two files, line i of one = line i of the other
  python3 tools/mine_dictionary.py --tsv pairs.tsv                              Cyrillic <TAB> Latin per line
  options: --min N (occurrences, default 2)  --json (machine-readable)  --fixtures (fixtures.json cases for the proposals)

Lines whose word counts differ are skipped (and counted). Nothing is changed: SPEC first, fixtures second, ports third.
"""
import argparse
import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "core", "python"))
import uztranslit as U  # noqa: E402


def words(line):
    """Runs of letters, with apostrophes that sit between letters."""
    out, cur = [], ""
    for i, ch in enumerate(line):
        if U.is_letter(ch) or (U.is_apos(ch) and cur and i + 1 < len(line) and U.is_letter(line[i + 1])):
            cur += ch
        else:
            if cur:
                out.append(cur)
            cur = ""
    if cur:
        out.append(cur)
    return out


def lower(s):
    return "".join(U.lat_lower(U.cyr_lower(c)) for c in s)


def with_entry(lat, key, cyr_stem):
    """Latin -> Cyrillic of one lowercase word as if the dictionary had key -> cyr_stem (SPEC section 6 matching)."""
    o = U._opts(None)
    norm = U.norm_key(lat)
    if not norm.startswith(key) or any(len(k) > len(key) and norm.startswith(k) for k in U.DICT):
        return U.convert(lat, "lat", "cyr")              # not caught, or a longer key of the dictionary wins
    consumed, built = 0, ""
    while len(built) < len(key) and consumed < len(lat):
        built += U.norm_key(lat[consumed])
        consumed += 1
    rest = lat[consumed:]
    return cyr_stem + U._latin_to_cyr_scan(rest, "lat", o, lat[consumed - 1] if consumed else "")


def minimal_stem(lat, cyr):
    """The shortest Latin prefix and its Cyrillic that make lat convert to cyr, or None."""
    o = U._opts(None)
    for k in range(1, len(lat) + 1):
        rest = U._latin_to_cyr_scan(lat[k:], "lat", o, lat[k - 1])
        if cyr.endswith(rest) and len(cyr) > len(rest):
            stem = cyr[:len(cyr) - len(rest)] if rest else cyr
            key = U.norm_key(lat[:k])
            if with_entry(lat, key, stem) == cyr:
                return key, stem
    return None


# Uzbek endings on (loan) nouns, longest first: kompyuterlarda, kompyuterning -> kompyuter
SUFFIXES = sorted("""larimizning larining laridagi larimiz laringiz larning lardan larda larga larni lari lar
ning dagi dan da ga ka qa ni imiz ingiz im ing si""".split(), key=len, reverse=True)


def lemma(word):
    """The word without its Uzbek endings (at least 3 letters stay)."""
    changed = True
    while changed:
        changed = False
        for suf in SUFFIXES:
            if word.endswith(suf) and len(word) - len(suf) >= 3:
                word = word[:-len(suf)]
                changed = True
                break
    return word


def pairs_from(cyr_lines, lat_lines):
    return list(zip(cyr_lines, lat_lines))


def mine(pairs, min_count=2):
    """pairs: [(cyrillic line, latin line)]. Returns {stats, proposals: [...]}"""
    stats = Counter()
    attested = defaultdict(Counter)          # latin word (lowercase) -> Counter of attested Cyrillic forms
    for cyr_line, lat_line in pairs:
        cw, lw = words(cyr_line), words(lat_line)
        if len(cw) != len(lw):
            stats["lines skipped (word counts differ)"] += 1
            continue
        stats["lines used"] += 1
        for c, l in zip(cw, lw):
            if not any(U.is_cyr(ch) for ch in c) or not any(U.is_lat(ch) for ch in l):
                continue
            attested[lower(l)][lower(c)] += 1
            stats["word pairs"] += 1
    wrong = {}                                # latin word -> (attested cyrillic, count)
    for lat, forms in attested.items():
        cyr, n = forms.most_common(1)[0]
        if U.convert(lat, "lat", "cyr") != cyr:
            wrong[lat] = (cyr, n)
    stats["distinct words"] = len(attested)
    stats["distinct words the rules get wrong"] = len(wrong)
    groups = defaultdict(list)                # lemma -> [(latin, cyrillic, count)]
    unexplained = []
    for lat, (cyr, n) in wrong.items():
        if minimal_stem(lat, cyr) is None:    # no prefix stem explains it
            unexplained.append((lat, cyr, n))
        else:
            groups[lemma(lat)].append((lat, cyr, n))
    candidates = []
    for lem, forms in groups.items():
        # the lemma as the key, if one Cyrillic stem fixes every form; otherwise each form on its own
        w = minimal_wide(forms[0][0], forms[0][1], U.norm_key(lem))
        if w and all(with_entry(l, w[0], w[1]) == c for l, c, _ in forms):
            candidates.append((w, forms))
        else:
            for f in forms:
                candidates.append(((U.norm_key(f[0]), f[1]), [f]))
    proposals = []
    for (k, s), forms in candidates:
        count = sum(n for _, _, n in forms)
        if count < min_count:
            continue
        breaks = []
        for lat, forms_c in attested.items():
            if lat in wrong or not U.norm_key(lat).startswith(k):
                continue
            cyr = forms_c.most_common(1)[0][0]
            if with_entry(lat, k, s) != cyr:
                breaks.append((lat, cyr, with_entry(lat, k, s)))
        known = U.DICT.get(k)
        proposals.append({
            "key": k, "cyrillic": s, "occurrences": count,
            "forms": sorted(((l, c) for l, c, _ in forms), key=lambda x: x[0]),
            "breaks": breaks, "already_in_dictionary": known,
        })
    proposals.sort(key=lambda p: (-p["occurrences"], p["key"]))
    unexplained.sort(key=lambda x: -x[2])
    return {"stats": dict(stats), "proposals": proposals, "unexplained": unexplained}


def minimal_wide(lat, cyr, wide_key):
    """The Cyrillic for a given (wider) Latin key, so that lat still converts to cyr."""
    o = U._opts(None)
    consumed, built = 0, ""
    while len(built) < len(wide_key) and consumed < len(lat):
        built += U.norm_key(lat[consumed])
        consumed += 1
    rest = U._latin_to_cyr_scan(lat[consumed:], "lat", o, lat[consumed - 1] if consumed else "")
    if not cyr.endswith(rest) or len(cyr) <= len(rest):
        return None
    return wide_key, cyr[:len(cyr) - len(rest)] if rest else cyr


def report(result):
    out = ["# Dictionary candidates (spec/SPEC.md section 6)", ""]
    for k, v in result["stats"].items():
        out.append("* %s: %d" % (k, v))
    out += ["", "| key | Cyrillic | seen | forms | would break |", "|---|---|---|---|---|"]
    for p in result["proposals"]:
        forms = ", ".join("%s → %s" % f for f in p["forms"][:4]) + (" …" if len(p["forms"]) > 4 else "")
        br = ", ".join("%s (%s, not %s)" % (b[0], b[2], b[1]) for b in p["breaks"][:3]) or "—"
        mark = " (already: %s)" % p["already_in_dictionary"] if p["already_in_dictionary"] else ""
        out.append("| `%s` | %s%s | %d | %s | %s |" % (p["key"], p["cyrillic"], mark, p["occurrences"], forms, br))
    if result["unexplained"]:
        out += ["", "Words no prefix stem explains (other spelling, typo or alignment):", ""]
        out += ["* %s → %s (%d×), rules: %s" % (l, c, n, U.convert(l, "lat", "cyr")) for l, c, n in result["unexplained"][:30]]
    return "\n".join(out)


def fixtures(result):
    """fixtures.json cases for the proposals without breaks: one example form each."""
    cases = []
    for p in result["proposals"]:
        if p["breaks"] or p["already_in_dictionary"]:
            continue
        lat, cyr = p["forms"][0]
        cases.append({"id": "dict/%s" % p["key"].replace("'", ""), "from": "lat", "to": "cyr", "in": lat, "out": cyr,
                      "note": "dictionary: %s %s" % (p["key"], p["cyrillic"])})
    return cases


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--cyr")
    ap.add_argument("--lat")
    ap.add_argument("--tsv")
    ap.add_argument("--min", type=int, default=2)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--fixtures", action="store_true")
    a = ap.parse_args(argv)
    if a.tsv:
        pairs = [tuple(line.rstrip("\n").split("\t", 1)) for line in open(a.tsv, encoding="utf-8") if "\t" in line]
    elif a.cyr and a.lat:
        pairs = pairs_from(open(a.cyr, encoding="utf-8").read().splitlines(), open(a.lat, encoding="utf-8").read().splitlines())
    else:
        ap.error("give --tsv, or --cyr and --lat")
    result = mine(pairs, a.min)
    if a.fixtures:
        print(json.dumps(fixtures(result), ensure_ascii=False, indent=2))
    elif a.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(report(result))


if __name__ == "__main__":
    main()
