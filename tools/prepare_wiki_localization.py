#!/usr/bin/env python3
"""Build private LiA text overrides from original EN/RU/DE reference exports.

Reuse GOG translations only when the Russian source agrees. Translate expansion
text through the reviewed catalogue, and compose new material names from the
localized recipe and material. Never substitute base-game text by ID alone:
Lost in Astral reuses IDs for different items, spells and characters.
"""
import argparse
import json
from pathlib import Path
import re


def read(path):
    return json.loads(Path(path).read_text(), strict=False)


def clean(text):
    return re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', text).strip()


def parts(text):
    first, _, rest = clean(text).partition('\n')
    return first.strip(), rest.strip()


def normalize(text):
    return re.sub(r'[^\w]+', ' ', text.lower().replace('ё', 'е')).strip()


def prepare(base, astral, translations, output):
    assert astral['campaign'] == 'lost_in_astral' and astral['language'] == 'ru'
    assert all(base[lang]['campaign'] == 'cursed_lands' and base[lang]['language'] == lang for lang in ['en', 'ru', 'de'])
    known = [{}, {}]
    for key, russian in base['ru']['texts'].items():
        targets = [base[lang]['texts'].get(key, '') for lang in ['en', 'de']]
        if not all(targets):
            continue
        for index, source in enumerate(parts(russian)):
            values = [parts(target)[index] for target in targets]
            if normalize(source) and all(normalize(value) for value in values):
                known[index].setdefault(normalize(source), values)
    reviewed = {normalize(source): values for source, values in translations.items()}
    assert all(len(values) == 2 and all(values) for values in reviewed.values())
    missing = {}

    def translate(source, key, part, stack=()):
        source = clean(source)
        if not re.search('[А-Яа-яЁё]', source):
            return [source, source]
        normalized = normalize(source)
        if normalized in reviewed:
            return reviewed[normalized]
        if normalized in known[part]:
            return known[part][normalized]
        fields = key.split(' ')
        if part == 0 and len(fields) == 3 and fields[0] in ['armor', 'weapon']:
            recipe_key = 'instr ' + fields[1]
            material_key = 'material ' + fields[2]
            recipe = parts(astral['texts'].get(recipe_key, ''))[0]
            material = parts(astral['texts'].get(material_key, ''))[0]
            if recipe and material and '_' not in recipe and key not in stack:
                names = translate(recipe, recipe_key, 0, stack + (key,))
                materials = translate(material, material_key, 0, stack + (key,))
                return [name + ' · ' + mat for name, mat in zip(names, materials)]
        missing.setdefault(normalized, {'source': source, 'keys': []})['keys'].append(key)
        return ['', '']

    result = {'en': {}, 'de': {}}
    used = set(astral['used'])
    # The public exporter also reads recipe names for item-family headings,
    # including NPC costumes whose corresponding ordinary recipe is named.
    for entry in astral['entries'].values():
        if entry['kind'] == 'item':
            item_base = entry['value']
            for name in [item_base, item_base.replace(' special ', ' ')]:
                used.add('instr ' + name.replace(' ', '_'))
    for key in sorted(used):
        # Zone and quest texts are not audited; the game localizes them itself.
        # An empty override would hide those maps and quests.
        if key not in astral['texts']:
            continue
        source = astral['texts'][key]
        title, description = parts(source)
        names = translate(title, key, 0)
        descriptions = translate(description, key, 1)
        for index, language in enumerate(result):
            result[language][key] = names[index] + ('\n' + descriptions[index] if descriptions[index] else '')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'missing.json').write_text(json.dumps(sorted(missing.values(), key=lambda row: (row['keys'][0].split()[0], row['source'])), ensure_ascii=False, indent=2) + '\n')
    if missing:
        print(f'{len(missing)} untranslated text segments; see {output / "missing.json"}')
        return False
    for language, text in result.items():
        assert not any(re.search('[А-Яа-яЁё]', value) for value in text.values())
        (output / (language + '.json')).write_text(json.dumps(text, ensure_ascii=False, indent=2) + '\n')
    print(f'Localized {len(result["en"])} LiA text keys in English and German; original Russian retained.')
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for language in ['en', 'ru', 'de']:
        parser.add_argument('--base-' + language, required=True, type=Path)
    parser.add_argument('--astral-ru', required=True, type=Path)
    parser.add_argument('--translations', type=Path, default=Path(__file__).with_name('wiki_lia_translations.json'))
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    ok = prepare({lang: read(getattr(args, 'base_' + lang)) for lang in ['en', 'ru', 'de']},
                 read(args.astral_ru), read(args.translations), args.output)
    raise SystemExit(0 if ok else 1)
