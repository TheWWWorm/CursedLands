#!/usr/bin/env python3
"""Audit full RGB PNG data independently of Godot image storage formats."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--native', type=Path, action='append', default=[])
parser.add_argument('--volume', type=Path, action='append', default=[])
parser.add_argument('--exact-pair', type=Path, nargs=2, action='append', default=[])
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
rows = []

def compare(a, b, label, limit=2, minimum=None):
    with Image.open(a) as raw_a, Image.open(b) as raw_b:
        aa, bb = raw_a.convert('RGB'), raw_b.convert('RGB')
        if aa.size != bb.size:
            raise AssertionError(f'{a}: mismatched dimensions')
        differences = [max(abs(x-y) for x, y in zip(p, q))
                       for p, q in zip(aa.getdata(), bb.getdata())]
    peak = max(differences)
    over = sum(d > 2 for d in differences)
    passed = over > minimum if minimum is not None else peak <= limit
    rows.append({'case': label, 'a': str(a), 'b': str(b),
                 'sha256': [hashlib.sha256(p.read_bytes()).hexdigest() for p in [a,b]],
                 'changed_pixels': sum(d > 0 for d in differences),
                 'pixels_over_2': over, 'peak_delta': peak, 'passed': passed})

for folder in args.native:
    for alpha in ['0.0','0.25','0.625','1.0']:
        for quality in ['half','quarter']:
            for prefix in ['', 'radiance-']:
                compare(folder / f'sky-alpha-{prefix}reference-{alpha}.png',
                        folder / f'sky-alpha-{prefix}{quality}-{alpha}.png',
                        f'{folder.name}: {prefix}{quality} alpha {alpha}')
    for quality in ['half','quarter']:
        for prefix in ['', 'radiance-']:
            compare(folder / f'sky-alpha-{prefix}rgb-reference.png',
                    folder / f'sky-alpha-{prefix}rgb-{quality}.png',
                    f'{folder.name}: {prefix}{quality} RGB')

for folder in args.volume:
    def pair(a,b,**kw):
        compare(folder/f'volume-{a}.png',folder/f'volume-{b}.png',f'{folder.name}: {a}/{b}',**kw)
    for q in [1,2,3]:
        pair(f'quality{q}',f'quality{q}-held',limit=0)
        pair('off',f'quality{q}',minimum=1000)
        if (folder/f'volume-quality{q}-empty.png').exists():
            pair('off',f'quality{q}-empty')
    for name in ['cave-cleared','restored','storm-empty']:
        if (folder/f'volume-{name}.png').exists(): pair('off',name)
    pair('fair','moved',minimum=500)
    pair('moved','rain' if (folder/'volume-rain.png').exists() else 'snow',minimum=1000)
    if (folder/'volume-night.png').exists(): pair('night','night-held',limit=0)
    if (folder/'volume-reflection-on.png').exists(): pair('reflection-off','reflection-on',minimum=20)

for before, after in args.exact_pair:
    names = ['volume-off.png','volume-quality1.png','volume-quality1-held.png',
             'volume-restored.png','volume-cave-cleared.png']
    names += [p.name for p in before.glob('sky-alpha-*.png')
              if 'reference-' in p.name or 'rgb-' in p.name]
    for name in names:
        if (before/name).exists() and (after/name).exists():
            compare(before/name, after/name, f'{before.name}/{after.name}: unchanged {name}',limit=0)

result = {'checks': len(rows), 'failures': sum(not r['passed'] for r in rows), 'rows': rows}
args.output.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['checks','failures']}))
raise SystemExit(bool(result['failures']))
