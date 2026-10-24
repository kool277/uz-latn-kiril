#!/usr/bin/env python3
"""Tests tools/mine_dictionary.py on a synthetic parallel corpus: the Latin side is the rules' conversion of the
Cyrillic side, and the miner's dictionary lacks four entries it must find again.
usage: python3 tools/test_mine_dictionary.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mine_dictionary as M  # noqa: E402

U = M.U
failures = []


def check(name, got, want):
    if got == want:
        print("  ok   " + name)
    else:
        failures.append(name)
        print("  FAIL %s\n       want %r\n       got  %r" % (name, want, got))


REMOVED = ("sement", "kompyuter", "aksiya", "sink")
saved = dict(U.DICT)
for k in REMOVED:
    del U.DICT[k]
U.DICT_KEYS[:] = sorted(U.DICT, key=len, reverse=True)
try:
    cyr = [
        "Тошкент шаҳрида катта цемент заводи бор.",
        "Цементни олиб келинг, компьютерлар ишламаяпти.",
        "Бу компьютерда янги акция бошланди, компьютер ҳам бор.",
        "Акциялар ва цемент нархи.",
        "Цинк ва синкара ҳақида, цинкни қаердан олдингиз?",
        "Объект ва субъект луғатда бор.",
        "Бу қатор бошқача ёзилган",
    ]
    lat = [U.convert(line, "cyr", "lat") for line in cyr]
    lat[-1] = "Bu qator boshqacha yozilgan ekan"         # one more word: the line is skipped
    result = M.mine(list(zip(cyr, lat)), min_count=2)
    by_key = {p["key"]: p for p in result["proposals"]}
    check("lines used / skipped", (result["stats"]["lines used"], result["stats"]["lines skipped (word counts differ)"]), (6, 1))
    check("the four missing stems are found, nothing else", sorted(by_key), sorted(REMOVED))
    check("sement -> цемент", by_key["sement"]["cyrillic"], "цемент")
    check("forms of one word give one stem: kompyuter -> компьютер", (by_key["kompyuter"]["cyrillic"], len(by_key["kompyuter"]["forms"])), ("компьютер", 3))
    check("aksiya -> акция", by_key["aksiya"]["cyrillic"], "акция")
    check("a key that would break a correct word says so", [b[0] for b in by_key["sink"]["breaks"]], ["sinkara"])
    check("no unexplained words", result["unexplained"], [])
    fx = M.fixtures(result)
    check("fixtures for the safe stems only", sorted(c["id"] for c in fx), ["dict/aksiya", "dict/kompyuter", "dict/sement"])
    check("a fixture converts as attested once the stem is in the dictionary", [(c["in"], c["out"]) for c in fx if c["id"] == "dict/sement"],
          [("sement", "цемент")])
    check("--min drops rarer words (sement and kompyuter are seen 3 times)", sorted(p["key"] for p in M.mine(list(zip(cyr, lat)), min_count=3)["proposals"]), ["kompyuter", "sement"])
    check("words(): apostrophes inside words only", M.words("'O'zbekiston' va ma'no, 2026"), ["O'zbekiston", "va", "ma'no"])
    check("lemma()", [M.lemma(w) for w in ("kompyuterlarda", "sementni", "aksiyalari", "sex")], ["kompyuter", "sement", "aksiya", "sex"])
finally:
    U.DICT.clear()
    U.DICT.update(saved)
    U.DICT_KEYS[:] = sorted(U.DICT, key=len, reverse=True)

# with the real dictionary only the word that its sink key catches is left: it needs a key of its own (SPEC 6)
left = M.mine(list(zip(cyr, lat)), 1)["proposals"]
check("full dictionary: an own key for the word sink catches", [(p["key"], p["cyrillic"]) for p in left], [("sinkara", "синкара")])
print("%d failed" % len(failures) if failures else "mine_dictionary: all checks passed")
sys.exit(1 if failures else 0)
