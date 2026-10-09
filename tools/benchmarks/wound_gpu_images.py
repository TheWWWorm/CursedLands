#!/usr/bin/env python3
"""Recompute P1 acceptance from complete decoded RGB PNGs, independent of Godot.

Usage: wound_gpu_images.py RUN [--probe PRE_INTEGRATION_PROBE] [--output JSON]
Requires Pillow. A probe is the accepted raw-UNORM candidate, not old baked pixels.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops


def difference(a, b):
    with Image.open(a) as ia, Image.open(b) as ib:
        assert ia.size == ib.size, (a, b, ia.size, ib.size)
        delta = ImageChops.difference(ia.convert('RGB'), ib.convert('RGB'))
    channels = delta.split()
    maximum = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
    histogram = maximum.histogram()
    return dict(peak=maximum.getextrema()[1], changed=sum(histogram[1:]), over2=sum(histogram[3:]),
                rgb_absolute_sum=sum(i * n for c in channels for i, n in enumerate(c.histogram())))


def audit(run, probe=None):
    report = json.loads((run / 'wound-gpu-contract.json').read_text())
    assert report['failures'] == 0 and report['production_changed']
    rows = []

    def compare(name, a, b, peak, recorded=None):
        result = difference(a, b)
        assert result['peak'] <= peak, (name, result)
        if recorded is not None:
            assert all(result[k] == recorded[k] for k in result), (name, result, recorded)
        rows.append(dict(name=name, **result))

    for row in report['rows']:
        tag = 'wound-contract-' + row['label']
        if row['kind'] == 'independent_cpu_oracle':
            compare(tag, run / (tag + '.png'), run / (tag + '-oracle-display.png'), 2, row)
        elif row['kind'] == 'production_material_alpha':
            compare(tag, run / (tag + '-actual.png'), run / (tag + '-reference.png'), 2, row)
        elif row['kind'] == 'production_wound_signal':
            compare(tag + '-healed', run / (tag + '-healthy.png'), run / (tag + '-healed.png'), 0)
            if row['label'].startswith('unmowi-'):
                compare(tag + '-no-wound', run / (tag + '-healthy.png'), run / (tag + '-candidate.png'), 0)
            if probe:
                for suffix in ['healthy', 'candidate', 'healed']:
                    name = tag + '-' + suffix + '.png'
                    compare('pre-integration-' + name, run / name, probe / name, 2)
    return dict(run=str(run), probe=str(probe) if probe else None, comparisons=len(rows),
                failures=0, rows=rows)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('--probe', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = audit(args.run, args.probe)
    text = json.dumps(result, indent=2) + '\n'
    if args.output:
        args.output.write_text(text)
    print(json.dumps({k: v for k, v in result.items() if k != 'rows'}))
