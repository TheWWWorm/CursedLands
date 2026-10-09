"""Recheck every RGB channel in saved waterfall/cliff render captures.

Usage: python3 tools/tests/renderer_png_controls.py waterfalls|cliffs QA_ROOT RUN...
Requires Pillow. It does not run the game or change prior captures/manifests.
Vulkan viewport readbacks may be RGB8 while Compatibility returns RGBA8;
normalising decoded PNGs gives an independent check on fixture pixel strides.
"""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('kind', choices=['waterfalls', 'cliffs'])
parser.add_argument('root', type=Path)
parser.add_argument('runs', nargs='+')
args = parser.parse_args()
prefix = 'waterfalls' if args.kind == 'waterfalls' else 'terrain-cliffs'
checks = failures = 0
records = []
hashes = {}


def compare(folder, map_name, first, second):
    images = []
    for state in (first, second):
        path = folder / f'{prefix}-{map_name}-{state}.png'
        hashes[str(path.relative_to(args.root))] = hashlib.sha256(path.read_bytes()).hexdigest()
        with Image.open(path) as source:
            images.append(source.convert('RGB'))
    assert images[0].size == images[1].size
    channels = ImageChops.difference(*images).split()
    maximum = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
    histogram = maximum.histogram()
    return {'changed_pixels': sum(histogram[1:]),
            'peak_byte_delta': max(i for i, n in enumerate(histogram) if n),
            'sum': sum(i * n for i, n in enumerate(histogram))}


for run in args.runs:
    folder = args.root / run
    source = json.loads((folder / f'{prefix}-render.json').read_text())
    rows = []
    for row in source['rows']:
        map_name = row['map']
        pairs = [('off', 'on', 'visible' if row['positive'] else 'exact')]
        if args.kind == 'waterfalls':
            if row['positive']:
                pairs += [('on', 'clock-held', 'exact'), ('on', 'flowing', 'animated')]
            pairs += [('hidden-control', 'disabled', 'exact')]
        else:
            if row['positive']:
                pairs += [('off', 'unclassified', 'exact'), ('on', 'restored', 'exact')]
            pairs += [('off', 'disabled', 'exact')]
        pairs += [('original', 'dependency', 'exact')]
        results = []
        for first, second, policy in pairs:
            delta = compare(folder, map_name, first, second)
            ok = (delta['changed_pixels'] == 0 if policy == 'exact' else
                  delta['changed_pixels'] > 10 if policy == 'animated' else
                  delta['changed_pixels'] > 40 and delta['peak_byte_delta'] > 8)
            checks += 1
            failures += not ok
            results.append({'first': first, 'second': second, 'policy': policy, 'passed': ok, 'difference': delta})
        rows.append({'map': map_name, 'positive': row['positive'], 'comparisons': results})
    records.append({'run': run, 'rows': rows})

record = {'method': 'Pillow RGB decode; per-pixel maximum of all three channel deltas',
          'checks': checks, 'failures': failures, 'runs': records, 'capture_sha256': hashes,
          'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
output = args.root / f'{args.kind}-image-audit.json'
output.write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps({'checks': checks, 'failures': failures, 'output': str(output)}))
raise SystemExit(1 if failures else 0)
