#!/usr/bin/env python3
"""Checks that every localizable string literal in Sources/ has an Uzbek and a Russian translation in
Resources/Strings/Localizable.xcstrings with the same format placeholders, that the catalog has no unused keys,
and that the .strings files (Services menu, extension names) exist for en, uz and ru.
usage: python3 platforms/ios/scripts/check-localizations.py   (exit code 1 on any problem)"""
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
IOS = os.path.dirname(HERE)
LANGS = ('uz', 'ru')

# literal arguments that SwiftUI / String(localized:) look up in the catalog
CALL = re.compile(r'\b(?:Text|Button|Label|Toggle|Picker|Section|ProgressView|LabeledContent|flash)\(\s*"((?:[^"\\]|\\.)*)"')
LOCALIZED = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"')
RETURNED = re.compile(r'\breturn\s+"((?:[^"\\]|\\.)*)"')  # LocalizedStringKey properties (labels, error messages)
# interpolated values and the format specifier SwiftUI uses for them
INTERPOLATION = {'characters': '%lld', 'words': '%lld', 'ExtensionModel.previewLimit': '%lld',
                 'r.from.localizedName': '%@'}
SPEC = re.compile(r'%(?:\d+\$)?(?:lld|@)')


def key_of(literal, where):
    def repl(m):
        expr = m.group(1)
        if expr not in INTERPOLATION:
            sys.exit('%s: add the format specifier of \\(%s) to INTERPOLATION' % (where, expr))
        return INTERPOLATION[expr]
    return re.sub(r'\\\((.*?)\)', repl, literal).replace("\\'", "'").replace('\\"', '"')


def kinds(s):
    return sorted(re.sub(r'\d+\$', '', m) for m in SPEC.findall(s))


problems = []
used = {}
for path in sorted(glob.glob(os.path.join(IOS, 'Sources', '**', '*.swift'), recursive=True)):
    rel = os.path.relpath(path, IOS)
    with open(path, encoding='utf-8') as f:
        src = f.read()
    returned = RETURNED.findall(src) if ('LocalizedStringKey' in src) else []
    for literal in CALL.findall(src) + LOCALIZED.findall(src) + returned:
        used.setdefault(key_of(literal, rel), rel)

with open(os.path.join(IOS, 'Resources', 'Strings', 'Localizable.xcstrings'), encoding='utf-8') as f:
    catalog = json.load(f)
strings = catalog['strings']
if catalog.get('sourceLanguage') != 'en':
    problems.append('sourceLanguage must be en')

for key, where in sorted(used.items()):
    entry = strings.get(key)
    if entry is None:
        problems.append('%s: %r is not in Localizable.xcstrings' % (where, key))
        continue
    for lang in LANGS:
        unit = entry.get('localizations', {}).get(lang, {}).get('stringUnit', {})
        value = unit.get('value')
        if not value or unit.get('state') != 'translated':
            problems.append('%r has no translated %s value' % (key, lang))
        elif kinds(value) != kinds(key):
            problems.append('%r: %s placeholders %s differ from %s' % (key, lang, kinds(value), kinds(key)))
for key in sorted(set(strings) - set(used)):
    problems.append('unused catalog key %r' % key)

for pattern in ('Resources/MacApp/%s.lproj/ServicesMenu.strings', 'Resources/ActionExtension/%s.lproj/InfoPlist.strings'):
    for lang in ('en',) + LANGS:
        if not os.path.isfile(os.path.join(IOS, pattern % lang)):
            problems.append('missing ' + pattern % lang)

for p in problems:
    print(p)
print('%d localizable strings, %s: %s' % (len(used), '/'.join(('en',) + LANGS), 'OK' if not problems else '%d problems' % len(problems)))
sys.exit(1 if problems else 0)
