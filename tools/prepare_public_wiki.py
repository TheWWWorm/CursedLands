#!/usr/bin/env python3
"""Validate and package export_wiki.gd output for a standalone public /wiki."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET
from urllib.parse import unquote, parse_qs, urlencode


def read(path):
    # Original archives can contain non-printing control characters.
    return json.loads(path.read_text(), strict=False)


def prepare_campaign(data, images, target_data, campaign, labels, used_images):
    expected_source = "GOG" if campaign == "cursed_lands" else "Lost in Astral"
    languages = {}
    for lang in labels:
        index = read(data / lang / 'index.json')
        assert index['language'] == lang and index['source'] == expected_source and index['campaign'] == campaign
        entries = {entry['key']: entry for entry in index['entries']}
        assert len(entries) == len(index['entries']) and len(entries) > 900
        pages = {}
        for key, entry in entries.items():
            assert re.fullmatch(r'[a-f0-9]{20}\.json', entry['file'])
            page = read(data / lang / 'pages' / entry['file'])
            assert page['key'] == key and page['versions']
            pages[key] = page
        count = links = normalized = 0
        for key, page in pages.items():
            for group in page.get('relations', []):
                assert group['id'] and group['title'] and group['rows']
                for row in group['rows']:
                    assert row['key'] in entries and row['title'], (campaign, lang, key, 'relationship')
            for version in page['versions']:
                for pin in version.get('pins', []):
                    assert pin['key'] in entries and pin['title'] and pin['kind'] in {'exit','quest','inhabitant'}
                    assert all(isinstance(pin[n], (int,float)) and math.isfinite(pin[n]) and 0 <= pin[n] <= 1 for n in ['x','y'])
                guide = ET.fromstring('<article>' + version.get('guide','') + '</article>')
                assert all(el.tag in {'article','h2','p','br'} and not el.attrib for el in guide.iter())
                if lang != 'ru':
                    assert not re.search('[А-Яа-яЁё]', version.get('guide','')), (campaign, lang, key, 'untranslated guide')
                plan = version.get('plan')
                if plan:
                    assert all(math.isfinite(plan[n]) and plan[n] >= 0 for n in ['weight','price'])
                    if plan.get('material'):assert plan['material']['key'] in entries and plan['material']['title']
            for version in page['versions']:
                assert version['title']
                if lang != 'ru':
                    assert not re.search('[А-Яа-яЁё]', version['title'] + version['html']), (campaign, lang, key, 'untranslated Russian text')
                html = ET.fromstring(re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', version['html']))
                assert html.tag == 'article' and html.find('h1') is not None
                assert not re.search(r'\b\w+_\w*Prototyp\w*', ' '.join(html.itertext()), re.I), (lang, key)
                assert not re.search(r'\b\w+_\w*Prototyp\w*', version['title'], re.I), (lang, key)
                for element in html.iter():
                    assert element.tag in {'article', 'h1', 'h2', 'p', 'br', 'table', 'tr', 'th', 'td', 'a', 'strong'}
                    assert set(element.attrib) <= {'data-columns', 'href'}
                    if element.tag != 'a':
                        continue
                    link = element.attrib['href']
                    assert link.startswith('wiki://')
                    destination, _, query = link[7:].partition('?')
                    if destination.startswith('category/'):
                        assert unquote(destination[9:]) in index['categories']
                    else:
                        assert destination in entries, (lang, key, link)
                        variant = parse_qs(query).get('version', [''])[0]
                        if variant:
                            choices = {v['id'] for v in pages[destination]['versions']}
                            if entries[destination]['kind'] == 'material':
                                # A material already identifies its only page.
                                element.set('href', 'wiki://' + destination)
                                normalized += 1
                            elif variant not in choices:
                                # Creature equipment specifications can carry
                                # an enchantment or authored separator spaces.
                                # Link to the available base material article;
                                # this site does not simulate temporary effects.
                                base = '.'.join(p.strip() for p in variant.split('|')[0].split('.'))
                                if entries[destination].get('fixed'):
                                    # Legacy links may carry synthetic material
                                    # variants of a fixed, non-craftable item.
                                    base = pages[destination]['versions'][0]['id']
                                    element.text = pages[destination]['versions'][0]['title']
                                if base in choices:
                                    element.set('href', 'wiki://' + destination + '?' + urlencode({'version': base}))
                                else:
                                    # Some expansion prototypes retain obsolete
                                    # equipment combinations (e.g. bronze on a
                                    # now-leather shirt). Do not invent a
                                    # craftable material option for that record.
                                    element.set('href', 'wiki://' + destination)
                                    element.text = entries[destination]['title']
                                normalized += 1
                    links += 1
                version['html'] = ET.tostring(html, encoding='unicode')
                image = version['image']
                assert not image or re.fullmatch('[a-f0-9]{24}', image)
                if image and (images / (image + '.webp')).is_file():
                    used_images[image] = images / (image + '.webp')
                else:
                    version['image'] = ''
                count += 1
            target = target_data / lang / 'pages' / entries[key]['file']
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(page, ensure_ascii=False, separators=(',', ':')) + '\n')
        for entry in index["entries"]:
            if entry.get("image") and not (images / (entry["image"] + ".webp")).is_file(): entry.pop("image")
        (target_data / lang / 'index.json').write_text(json.dumps(index, ensure_ascii=False, separators=(',', ':')) + '\n')
        constructors = read(data / lang / 'constructors.json')
        assert set(constructors['planner']['skills']) == {'melee','archery','science','elemental','sense','astral'}
        assert all(len(constructors['planner'][n]) == 5 for n in ['hp','mp'])
        assert constructors['max_runes'] == 8 and constructors['spells'] and constructors['runes']
        for rune in constructors['runes'].values():
            assert rune['title'] and rune.get('image')
            assert (images / (rune['image'] + '.webp')).is_file()
        (target_data / lang / 'constructors.json').write_text(json.dumps(constructors, ensure_ascii=False, separators=(',', ':')) + '\n')
        listed = [entry for entry in entries.values() if entry.get('listed', True)]
        spell_titles = [entry['title'] for entry in listed if entry['kind'] == 'spell']
        assert len(spell_titles) == len(set(spell_titles)), (campaign, lang, 'duplicate base spells')
        assert not set(spell_titles) & {'Spell', 'Заклинание', 'Zauber'}
        assert not any('{' in unquote(entry['key']) for entry in listed if entry['kind'] == 'spell')
        languages[lang] = {'pages': len(entries), 'listed_pages': len(listed),
                                    'listed_spells': sum(entry['kind'] == 'spell' for entry in listed),
                                    'versions': count, 'resolved_links': links, 'normalized_equipment_links': normalized}
    return languages


def prepare(data, images, output, astral_data, astral_images):
    source = Path(__file__).resolve().parents[1] / 'web/wiki'
    labels = json.loads((source / 'i18n.json').read_text())
    assert set(labels) == {'en', 'ru', 'de'}
    assert all(set(v) == set(labels['en']) and all(v.values()) for v in labels.values())
    output.mkdir(parents=True, exist_ok=True)
    for file in source.iterdir():
        shutil.copy2(file, output / file.name)
    version = re.search(r'^config/version="([^"]+)"', (source.parents[1] / 'game/project.godot').read_text(), re.M)[1]
    report = {'version': version, 'languages': {}, 'translation_keys': len(labels['en']),
              'requires_game_files': False, 'requires_game_engine': False, 'requires_account': False}
    used_images = {}
    report['campaigns'] = {}
    for campaign, directory, artwork in [('cursed_lands', data, images), ('lost_in_astral', astral_data, astral_images)]:
        target_data = output / 'data' if campaign == 'cursed_lands' else output / 'data' / campaign
        report['campaigns'][campaign] = {'languages': prepare_campaign(directory, artwork, target_data, campaign, labels, used_images)}
    report['languages'] = report['campaigns']['cursed_lands']['languages']
    (output / 'images').mkdir(exist_ok=True)
    for image, path in sorted(used_images.items()):
        shutil.copy2(path, output / 'images' / (image + '.webp'))
    report['illustrations'] = len(used_images)
    report['files'] = {str(p.relative_to(output)): {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                       for p in sorted(output.rglob('*')) if p.is_file() and p.name != 'BUILD-INFO.json'}
    report['bytes'] = sum(row['bytes'] for row in report['files'].values())
    (output / 'BUILD-INFO.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'files'}, indent=2))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--images', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--astral-data', type=Path, required=True)
    parser.add_argument('--astral-images', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.data, args.images, args.output, args.astral_data, args.astral_images)
