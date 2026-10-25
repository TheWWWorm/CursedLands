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
# Console descriptions, button labels and typed argument hints are dynamic.
console_catalog = (ROOT / 'ui/console_catalog.gd').read_text()
console_keys = {'unit', 'text', 'number', 'Read an original script expression.', 'On', 'Off', 'Yes', 'No'}
for match in re.finditer(r'^\s*(\[".*\]),$', console_catalog, re.M):
    console_keys.add(json.loads(match[1])[1])
console_ui = (ROOT / 'ui/game_console.gd').read_text()
for match in re.finditer(r'_button\(header,(' + STRING + r'),(' + STRING + r')', console_ui):
    console_keys.update(json.loads(s) for s in match.groups())
for key in console_keys:
    if key not in entries: errors.append(f'Console dynamic text missing RU/DE key: {key}')
# Download cards and availability messages are selected dynamically.
catalog_source = (ROOT / 'game/mod_catalog.gd').read_text()
for pattern in (r'^const ANDROID_INSTALL_NOTE := (' + STRING + r')',
                r'"(?:title|description|notes)":\s*(' + STRING + r')',
                r'return\s+(' + STRING + r')'):
    for match in re.finditer(pattern, catalog_source, re.M):
        key = json.loads(match[1])
        if key and key not in entries:
            errors.append(f'Mod download text missing RU/DE key: {key}')
# Renderer labels and recovery help are chosen dynamically by platform.
renderer_source = (ROOT / 'platform/renderer_choice.gd').read_text()
for match in re.finditer(r'^const WINDOWS_[A-Z_]+ := (.+)$', renderer_source, re.M):
    value = json.loads(match[1])
    for key in value if isinstance(value, list) else [value]:
        if key not in entries: errors.append(f'Windows renderer text missing RU/DE key: {key}')
detector_source = (ROOT / 'platform/renderer_detector.gd').read_text()
for match in re.finditer(r'^const (?:STATUS|DETAIL) := (".*")$', detector_source, re.M):
    key = json.loads(match[1])
    if key not in entries: errors.append(f'Renderer detector text missing RU/DE key: {key}')
# Scene RT availability is selected dynamically from the hardware capability.
rt_source = (ROOT / 'game/fx/scene_raytrace.gd').read_text()
for match in re.finditer(r'^const REASON := (' + STRING + r')$', rt_source, re.M):
    key = json.loads(match[1])
    if key not in entries: errors.append(f'Scene RT availability missing RU/DE key: {key}')
# Online errors cross the wire as English keys and translate on each client.
online_source = (ROOT / 'game/arena_online_session.gd').read_text()
for key in json.loads(re.search(r'^const ERRORS := (\[.*\])$', online_source, re.M)[1]):
    if key not in entries: errors.append(f'Online error missing RU/DE key: {key}')
for key in ('Ready', 'Not ready', 'First place', 'Eliminated'):
    if key not in entries: errors.append(f'Online state missing RU/DE key: {key}')
# Rich Presence chooses mode and phase labels dynamically.
for key in ('Main menu', 'Multiplayer', 'Co-op campaign', 'Campaign', 'Paused',
            'Trials of the Allods', 'Battle', 'Preparation', 'Victory', 'Defeat', 'Round %d'):
    if key not in entries: errors.append(f'Discord activity missing RU/DE key: {key}')
# Recruit family names/roles are chosen dynamically by the shop and guide.
arena_rules = (ROOT / 'game/arena_rules.gd').read_text().split('const FAMILIES := [', 1)[1].split('\n]', 1)[0]
for match in re.finditer(r'"(?:name|role)":\s*(' + STRING + r')', arena_rules):
    key = json.loads(match[1])
    if key not in entries:
        errors.append(f'Arena recruit label missing RU/DE key: {key}')
# Options are selected dynamically, so literal RemakeText.t calls alone
# cannot catch a missing label, help paragraph or translated choice.
options_source = (ROOT / 'ei/game_data.gd').read_text()
neutral_choices = {'SMAA', 'MSAA 4×', 'MSAA 4× + SMAA', 'TAA', 'FSR 2'}
for table in ('REMAKE_OPTIONS', 'DISPLAY_CHOICES'):
    block = options_source.split('const ' + table + ' := {', 1)[1].split('\n}', 1)[0]
    for match in re.finditer(r'^\s*(' + STRING + r'):\s*(\[.*?\]),', block, re.M):
        name = json.loads(match[1])
        for key in (json.loads(s) for s in re.findall(STRING, match[2])):
            if table == 'DISPLAY_CHOICES' and (key in neutral_choices or not any(c.isalpha() for c in key)):
                continue  # numeric quantities and unchanged graphics acronyms
            if key not in entries:
                errors.append(f'{table}[{name}]: missing RU/DE key: {key}')
# FSR option choices, help and capability errors are selected dynamically.
fsr_source = (ROOT / 'platform/fsr_graphics.gd').read_text()
for match in re.finditer(r'^const (?:SECTION|SR_HELP|QUALITY_HELP|FG_HELP|VERSIONS|QUALITIES|UNAVAILABLE|NEED_RESTART|NEED_API|NEED_SR|NEED_FG|ENABLE_SR) := (.+)$', fsr_source, re.M):
    value = json.loads(match[1])
    for key in value if isinstance(value, list) else [value]:
        if key not in entries: errors.append(f'FSR experiment text missing RU/DE key: {key}')
# NVIDIA/combined selectors and package-aware credits choose strings dynamically.
for filename in ('platform/rtx_graphics.gd', 'platform/temporal_graphics.gd', 'ui/graphics_attribution.gd'):
    source = (ROOT / filename).read_text()
    for match in re.finditer(r'^const (?:SECTION|SR_HELP|FG_HELP|QUALITY_HELP|CHOICES|FG_CHOICES|UNAVAILABLE|NEED_RESTART|NEED_API|NEED_SR|NEED_FG|ENABLE_SR|NVIDIA_CREDIT|NVIDIA_SOURCE|NVIDIA_MARKS|NRD_CREDIT|SHARC_CREDIT|AMD_CREDIT|AMD_MARKS|LICENSES) := (.+)$', source, re.M):
        value = json.loads(match[1])
        for key in value if isinstance(value, list) else [value]:
            if key not in entries: errors.append(f'{filename}: missing RU/DE key: {key}')
    for match in re.finditer(r'return ("(?:[^"\\]|\\.)*")', source):
        key = json.loads(match[1])
        if key and key not in entries: errors.append(f'{filename}: dynamic reason missing RU/DE key: {key}')
# The wiki translates categories, damage types, mechanics titles and stat
# labels dynamically. Check their source tables as well as literal calls.
permissions_source = (ROOT / 'game/coop_permissions.gd').read_text()
for match in re.finditer(r'^const (?:CLOCK_CHOICES|SAVE_CHOICES) := (\[.*\])$', permissions_source, re.M):
    for key in json.loads(match[1]):
        if key not in entries: errors.append(f'Co-op permission choice missing RU/DE key: {key}')
players_source = (ROOT / 'ui/players_panel.gd').read_text()
for table in ('PERMISSION_LABELS', 'PERMISSION_HELP'):
    block = players_source.split('const ' + table + ' := {', 1)[1].split('}', 1)[0]
    for match in re.finditer(r':\s*(' + STRING + r')', block):
        key = json.loads(match[1])
        if key not in entries: errors.append(f'Player permission text missing RU/DE key: {key}')
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
cut_source=(ROOT / 'game/wiki_cut.gd').read_text()
for table in ('ENGINE_FIGURES','FIGURES','PALETTES','SPECIES'):
    block=cut_source.split('const '+table+' := {',1)[1].split('\n}' if table=='FIGURES' else '}\n',1)[0]
    wiki_keys.update(json.loads(m[1]) for m in re.finditer(r'(?:"(?:title|text)"|"[A-Za-z0-9]+")\s*:\s*('+STRING+r')',block) if not json.loads(m[1]).startswith(('bird','un')))
for match in re.finditer(r'sections\.append\(\[('+STRING+r'), ('+STRING+r')',cut_source):
    wiki_keys.update([json.loads(match[1]),json.loads(match[2])])
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
arena_keys.update(['Next wave in %ds', 'Retry in %ds', 'Camp in %ds', 'Next round in %ds', 'First place', 'Eliminated', '1×', '2×'])
for match in re.finditer(r'"(?:name|role|help|hook)":\s*(' + STRING + r')', arena_source):
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
for match in re.finditer(r'topics\[\d+\] = (\[[^\n]+\])', arena_ui):
    if 'RemakeText.t(' not in match[1]: arena_keys.update(json.loads(match[1]))
for match in re.finditer(r'var words := (\[[^\n]+\])', arena_ui):
    arena_keys.update(json.loads(match[1]))
arena_keys.update(['Return to battle', 'Continue', 'Draw', 'Defeat', 'Gipath', 'Ingos', 'Suslanger'])
for key in sorted(arena_keys):
    if key not in entries:
        errors.append(f'Arena dynamic label missing RU/DE key: {key}')
print(f'Translations: {len(entries)} entries; {len(wiki_keys)} dynamic wiki keys; {len(arena_keys)} dynamic arena keys; {len(errors)} errors')
for error in errors:
    print(error)
sys.exit(bool(errors))
