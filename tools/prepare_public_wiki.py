#!/usr/bin/env python3
"""Validate and package export_wiki.gd output for a standalone public /wiki."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET
from urllib.parse import unquote, parse_qs


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
        count = links = 0
        for key, page in pages.items():
            for version in page['versions']:
                assert version['title']
                html = ET.fromstring(version['html'])
                assert html.tag == 'article' and html.find('h1') is not None
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
                            assert variant in {v['id'] for v in pages[destination]['versions']}, (key, link)
                    links += 1
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
        report['languages'][lang] = {'pages': len(entries), 'versions': count, 'resolved_links': links}
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
