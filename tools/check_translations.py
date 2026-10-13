#!/usr/bin/env python3
"""Check literal remake translation calls and every RU/DE catalog entry."""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1] / 'game/src'
STRING = r'"(?:[^"\\]|\\.)*"'
entries = {}
errors = []
for line in (ROOT / 'ei/remake_text.gd').read_text().splitlines():
    match = re.match(r'\s*(' + STRING + r'):\s*(\[.*\]),?\s*$', line)
    if not match:
        continue
    key, translations = json.loads(match[1]), json.loads(match[2])
    if key in entries:
        errors.append(f'Duplicate translation key: {key}')
    entries[key] = translations
    placeholders = lambda text: re.findall(r'%(?:[-+0#]*\d*(?:\.\d+)?)?[sdifxXoc]', text.replace('%%', ''))
    if len(translations) != 2 or not all(isinstance(t, str) and t.strip() for t in translations):
        errors.append(f'Missing RU/DE text: {key}')
    elif any(placeholders(t) != placeholders(key) for t in translations):
        errors.append(f'Format placeholders differ: {key}')
for path in ROOT.rglob('*.gd'):
    source = path.read_text()
    for match in re.finditer(r'RemakeText\.t\((' + STRING + r')\)', source):
        key = json.loads(match[1])
        if key and key not in entries:
            line = source[:match.start()].count('\n') + 1
            errors.append(f'{path.relative_to(ROOT)}:{line}: missing RU/DE key: {key}')
print(f'Translations: {len(entries)} entries; {len(errors)} errors')
for error in errors:
    print(error)
sys.exit(bool(errors))
