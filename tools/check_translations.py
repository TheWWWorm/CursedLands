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
lore_source = (ROOT / 'game/wiki_lore_data.gd').read_text()
lore_texts = json.loads(lore_source.split('const DATA := ', 1)[1])['texts']
# RemakeText.t also resolves the generated, source-checked lore catalog.
translation_lines = (ROOT / 'ei/remake_text.gd').read_text().splitlines()
translation_lines += [json.dumps(key) + ': ' + json.dumps(value) for key, value in lore_texts.items()]
for line in translation_lines:
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
for table in ('MECHANICS', 'ITEM_TYPES', 'SPELL_NAMES'):
    block = wiki_source.split('const ' + table + ' := {', 1)[1].split('\n}', 1)[0]
    wiki_keys.update(json.loads(m[1]) for m in re.finditer(r':\s*(' + STRING + r')', block))
for match in re.finditer(r'for field: Array in (\[\[.*?\]\]):', wiki_source):
    wiki_keys.update(row[1] for row in json.loads(match[1]))
for key in ('At least 20% of each incoming damage type passes through armor.',
            'Armor can absorb damage completely.'):
    wiki_keys.add(key)
for filename,table in [('game/wiki_knowledge.gd','LABELS'),('ui/wiki_equipment.gd','LABELS')]:
    source=(ROOT / filename).read_text().split('const '+table+' := {',1)[1].split('}',1)[0]
    wiki_keys.update(json.loads(m[1]) for m in re.finditer(r':\s*('+STRING+r')',source))
for filename in ['ui/wiki_planner.gd','ui/wiki_panel.gd','ui/wiki_camp_constructor.gd']:
    source=(ROOT / filename).read_text()
    for match in re.finditer(r'for (?:field|pair|family): Array in (\[\[.*?\]\]):',source):
        wiki_keys.update(row[1] for row in json.loads(match[1]))
home_source=(ROOT / 'ui/wiki_home.gd').read_text()
for match in re.finditer(r'for row: Array in (\[\[.*?\]\]):',home_source):
    for row in json.loads(match[1]):wiki_keys.update(row[1:])
for match in re.finditer(r'_route\(catalog,_routes,\w+,"[^"]+",('+STRING+r'),('+STRING+r')\)',home_source):
    wiki_keys.update(json.loads(s) for s in match.groups())
for match in re.finditer(r'_section\([^,]+,('+STRING+r')\)',(ROOT / 'ui/wiki_planner.gd').read_text()):
    wiki_keys.add(json.loads(match[1]))
library_source=(ROOT / 'game/wiki_library.gd').read_text()
for pattern in (r'"error":\s*('+STRING+r')',r'return\s+('+STRING+r')'):
    wiki_keys.update(json.loads(m[1]) for m in re.finditer(pattern,library_source) if json.loads(m[1]))
library_view=(ROOT / 'ui/wiki_library_view.gd').read_text()
for match in re.finditer(r'for key: String in (\[[^\n]+\]):',library_view):
    wiki_keys.update(json.loads(match[1]))
for match in re.finditer(r'_action\([^,]+,('+STRING+r'),',library_view):
    wiki_keys.add(json.loads(match[1]))
wiki_keys.update(['Item','Spell','Character build'])
for key in sorted(wiki_keys):
    if key not in entries:
        errors.append(f'Wiki dynamic label missing RU/DE key: {key}')
world_source = (ROOT / 'game/wiki_world_text.gd').read_text()
world = json.loads(world_source.split('const TEXTS := ', 1)[1])
reference_source = (ROOT / 'game/wiki_reference_text.gd').read_text()
reference = json.loads(reference_source.split('const TEXTS := ', 1)[1])
native_source = (ROOT / 'game/wiki_quest_text.gd').read_text()
native_quests = json.loads(native_source.split('const TEXTS := ', 1)[1])
for key, record in native_quests.items():
    import hashlib
    for lang in ('en', 'ru', 'de'):
        text = record.get(lang, '')
        if not text or hashlib.sha256(text.encode()).hexdigest() not in record.get('sources', []):
            errors.append(f'Native wiki quest text or source fingerprint missing: {key}/{lang}')
        if lang != 'ru' and re.search('[А-Яа-яЁё]', text):
            errors.append(f'Native wiki quest contains untranslated Russian: {key}/{lang}')
for key, record in reference.items():
    if len(record) != 3 or not re.fullmatch('[a-f0-9]{64}', record[0]):
        errors.append(f'Wiki reference source fingerprint missing: {key}')
    elif any(re.search('[А-Яа-яЁё]', text) for text in record[1:]):
        errors.append(f'Wiki reference text contains untranslated Russian: {key}')
for key, record in world.items():
    if set(record) != {'en', 'ru', 'de'} or not all(record.values()):
        errors.append(f'Wiki world text missing language: {key}')
        continue
    objective_ids = lambda text: re.findall(r'^#subobj\s+(\d+)', text, re.M)
    for lang in ('en', 'de'):
        if re.search('[А-Яа-яЁё]', record[lang]):
            errors.append(f'Wiki world text contains untranslated Russian: {key}/{lang}')
        if objective_ids(record[lang]) != objective_ids(record['ru']):
            errors.append(f'Wiki world objective coverage differs: {key}/{lang}')

print(f'Wiki world text: {len(world)} entries in EN/RU/DE')
print(f'Wiki reference text: {len(reference)} source-checked EN/DE entries; RU uses original archives')
# Expedition content and phase labels also choose their translation keys
# dynamically; prototype identifiers are intentionally excluded.
arena_source = (ROOT / 'game/arena_rules.gd').read_text()
arena_keys = set()
alliance_source = (ROOT / 'game/arena_alliances.gd').read_text()
for match in re.finditer(r'"(?:name|help)":\s*(' + STRING + r')', alliance_source):
    arena_keys.add(json.loads(match[1]))
arena_keys.update(['Next wave in %ds', 'Retry in %ds', 'Camp in %ds'])
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
