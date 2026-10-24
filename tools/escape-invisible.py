#!/usr/bin/env python3
"""Rewrites invisible characters (spaces other than U+0020, controls, zero-width marks, separators) in source files
as \\uXXXX escapes, so code never depends on characters a reviewer cannot see.
usage: python3 tools/escape-invisible.py [--check] FILE...
  without --check: rewrites the files (exit 1 if one changed); with --check: only lists them (exit 1 if any)"""
import re
import sys

INVISIBLE = re.compile('[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f\u00a0\u00ad\u1680\ufeff'
                       '\u2000-\u200f\u2028\u2029\u202f\u205f\u3000\ufffc]')
check = '--check' in sys.argv
changed = 0
for path in [a for a in sys.argv[1:] if a != '--check']:
    with open(path, encoding='utf-8') as f:
        src = f.read()
    out = INVISIBLE.sub(lambda m: '\\u%04x' % ord(m.group(0)), src)
    if out != src:
        changed += 1
        if check:
            lines = [i + 1 for i, l in enumerate(src.split('\n')) if INVISIBLE.search(l)]
            print('invisible characters in %s, lines %s' % (path, lines[:10]))
            continue
        with open(path, 'w', encoding='utf-8') as f:
            f.write(out)
        print('escaped invisible characters in', path)
sys.exit(1 if changed else 0)
