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
# Options are selected dynamically, so literal RemakeText.t calls alone
# cannot catch a missing label, help paragraph or translated choice.
options_source = (ROOT / 'ei/game_data.gd').read_text()
neutral_choices = {'SMAA', 'MSAA 4×', 'MSAA 4× + SMAA', 'TAA', 'FSR 2'}
for table in ('REMAKE_OPTIONS', 'DISPLAY_CHOICES'):
    block = options_source.split('const ' + table + ' := {', 1)[1].split('\n}', 1)[0]
    for match in re.finditer(r'^\s*(' + STRING + r'):\s*(\[.*?\]),', block, re.M):
        name = json.loads(match[1])
        for key in json.loads(match[2]):
            if table == 'DISPLAY_CHOICES' and (key in neutral_choices or not any(c.isalpha() for c in key)):
                continue  # numeric quantities and unchanged graphics acronyms
            if key not in entries:
                errors.append(f'{table}[{name}]: missing RU/DE key: {key}')
# The wiki translates categories, damage types, mechanics titles and stat
# labels dynamically. Check their source tables as well as literal calls.
wiki_source = (ROOT / 'game/wiki_catalog.gd').read_text()
wiki_keys = set()
for table in ('CATEGORIES', 'DAMAGE_TYPES'):
    block = re.search(r'const ' + table + r' := (\[[^\n]+\])', wiki_source)[1]
    wiki_keys.update(json.loads(block))
block = wiki_source.split('const MECHANICS := {', 1)[1].split('\n}', 1)[0]
wiki_keys.update(json.loads(m[1]) for m in re.finditer(r':\s*(' + STRING + r')', block))
for match in re.finditer(r'for field: Array in (\[\[.*?\]\]):', wiki_source):
    wiki_keys.update(row[1] for row in json.loads(match[1]))
for key in ('At least 20% of each incoming damage type passes through armor.',
            'Armor can absorb damage completely.'):
    wiki_keys.add(key)
for key in sorted(wiki_keys):
    if key not in entries:
        errors.append(f'Wiki dynamic label missing RU/DE key: {key}')
# Expedition content and phase labels also choose their translation keys
# dynamically; prototype identifiers are intentionally excluded.
arena_source = (ROOT / 'game/arena_rules.gd').read_text()
arena_keys = set()
for match in re.finditer(r'"(?:name|role|help)":\s*(' + STRING + r')', arena_source):
    arena_keys.add(json.loads(match[1]))
block = arena_source.split('const WAVES := [', 1)[1].split('\n]', 1)[0]
for match in re.finditer(r'^\s*\[(' + STRING + r')', block, re.M):
    arena_keys.add(json.loads(match[1]))
block = arena_source.split('const BOONS := {', 1)[1].split('\n}', 1)[0]
for match in re.finditer(r':\s*(\[[^\n]+\])', block):
    arena_keys.update(json.loads(match[1]))
arena_keys.update(['Standard expedition', 'Veteran expedition', 'Champion expedition',
    'On bench', 'Deployed', 'Bench', 'Expedition complete', 'The expedition ends',
    'Victory', 'Regroup and try again', 'Choose reward', 'Next wave', 'Prepare again',
    'Visit camp', 'Choose your pact', 'A moment at camp', 'Choose pact', 'Ready', 'Not contributing',
    'Your pact needs a two-star recruit from this family.', 'This family belongs to your pact.',
    'On field', 'In reserves', 'Needs 2 stars', 'Not recruited'])
arena_ui = (ROOT / 'ui/arena_pve_screen.gd').read_text()
for block_name in ('topics',):
    block = arena_ui.split('var ' + block_name + ' := [', 1)[1].split(']\n', 1)[0]
    arena_keys.update(json.loads(m[0]) for m in re.finditer(STRING, block))
for match in re.finditer(r'var words := (\[[^\n]+\])', arena_ui):
    arena_keys.update(json.loads(match[1]))
arena_keys.update(['Return to battle', 'Continue', 'Defeat', 'Gipath', 'Ingos', 'Suslanger'])
for key in sorted(arena_keys):
    if key not in entries:
        errors.append(f'Arena dynamic label missing RU/DE key: {key}')
print(f'Translations: {len(entries)} entries; {len(wiki_keys)} dynamic wiki keys; {len(arena_keys)} dynamic arena keys; {len(errors)} errors')
for error in errors:
    print(error)
sys.exit(bool(errors))
