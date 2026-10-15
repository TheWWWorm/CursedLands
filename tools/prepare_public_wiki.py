#!/usr/bin/env python3
"""Validate and package export_wiki.gd output for a standalone public /wiki."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET
from urllib.parse import unquote, parse_qs, urlencode


def prepare(data, images, output):
    source = Path(__file__).resolve().parents[1] / 'web/wiki'
    labels = json.loads((source / 'i18n.json').read_text())
    assert set(labels) == {'en', 'ru', 'de'}
    assert all(set(v) == set(labels['en']) and all(v.values()) for v in labels.values())
    output.mkdir(parents=True, exist_ok=True)
    for file in source.iterdir():
        shutil.copy2(file, output / file.name)
    report = {'version': '1.6.0', 'languages': {}, 'translation_keys': len(labels['en']),
              'requires_game_files': False, 'requires_game_engine': False, 'requires_account': False}
    used_images = set()
    for lang in labels:
        index = json.loads((data / lang / 'index.json').read_text())
        assert index['language'] == lang and index['source'] == 'GOG'
        entries = {entry['key']: entry for entry in index['entries']}
        assert len(entries) == len(index['entries']) and len(entries) > 900
        pages = {}
        for key, entry in entries.items():
            assert re.fullmatch(r'[a-f0-9]{20}\.json', entry['file'])
            page = json.loads((data / lang / 'pages' / entry['file']).read_text())
            assert page['key'] == key and page['versions']
            pages[key] = page
        count = links = normalized = 0
        for key, page in pages.items():
            for version in page['versions']:
                assert version['title']
                html = ET.fromstring(version['html'])
                assert html.tag == 'article' and html.find('h1') is not None
                assert not re.search(r'\b\w+_\w*Prototyp\w*', ' '.join(html.itertext()), re.I), (lang, key)
                assert not re.search(r'\b\w+_\w*Prototyp\w*', version['title'], re.I), (lang, key)
                for element in html.iter():
                    assert element.tag in {'article', 'h1', 'h2', 'p', 'br', 'table', 'tr', 'th', 'td', 'a'}
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
                                assert base in choices, (key, link)
                                element.set('href', 'wiki://' + destination + '?' + urlencode({'version': base}))
                                normalized += 1
                    links += 1
                version['html'] = ET.tostring(html, encoding='unicode')
                image = version['image']
                assert not image or re.fullmatch('[a-f0-9]{24}', image)
                if image and (images / (image + '.webp')).is_file():
                    used_images.add(image)
                else:
                    version['image'] = ''
                count += 1
            target = output / 'data' / lang / 'pages' / entries[key]['file']
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(page, ensure_ascii=False, separators=(',', ':')) + '\n')
        (output / 'data' / lang / 'index.json').write_text(json.dumps(index, ensure_ascii=False, separators=(',', ':')) + '\n')
        listed = [entry for entry in entries.values() if entry.get('listed', True)]
        report['languages'][lang] = {'pages': len(entries), 'listed_pages': len(listed),
                                    'listed_spells': sum(entry['kind'] == 'spell' for entry in listed),
                                    'versions': count, 'resolved_links': links, 'normalized_equipment_links': normalized}
    (output / 'images').mkdir(exist_ok=True)
    for image in sorted(used_images):
        shutil.copy2(images / (image + '.webp'), output / 'images' / (image + '.webp'))
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
    args = parser.parse_args()
    prepare(args.data, args.images, args.output)
