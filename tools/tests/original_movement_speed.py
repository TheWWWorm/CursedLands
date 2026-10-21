"""Capture original movement-speed bytes, including authored race values.

Execute each original stats-packing prefix without hooks, ending immediately
after the four gait bytes and the movement-factor byte are written. The LiA
rounding helper runs as original machine code too. The supplied stats include
the already-computed movement/wound factor. This does not replay injury
calculation, terrain, route planning, animation or whole-game movement.
"""
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'parity'))
from native import Original, f32
from cases import REFERENCES

LOCATIONS = {'original': (0x522ce0, 0x522e1d), 'lost_in_astral': (0x4a7620, 0x4a7733)}


def around(value):
    bits = struct.unpack('<I', struct.pack('<f', value))[0]
    return [struct.unpack('<f', struct.pack('<I', bits+d))[0] for d in [-1, 0, 1]]


def inputs(censuses):
    rows = []
    for campaign, path in censuses.items():
        census = json.loads(Path(path).read_text())
        for race in census['races']:
            speeds = race['speeds']
            if len(speeds) >= 4:
                rows.append(dict(id=f"authored/{campaign}/{race['name']}", speeds=speeds[:4], factor=1.0))
    for number in range(255):
        for side, value in enumerate(around((number+0.5)/127.5)):
            rows.append(dict(id=f'gait-boundary/{number}/{side}', speeds=[value]*4, factor=1.0))
        for side, value in enumerate(around((number+0.5)/25.5)):
            rows.append(dict(id=f'factor-boundary/{number}/{side}', speeds=[f32(x) for x in [.4,.16,.1,.05]], factor=value))
    for value in [0, .1, .2, .3, .5, .6, 1, 1.2, 2, 10, 12]:
        rows.append(dict(id=f'limits/{value}', speeds=[f32(value)]*4, factor=f32(value)))
    return rows


def capture(path, campaign, rows):
    data = Path(path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != REFERENCES[campaign]['executable_sha256']:
        raise ValueError('Unqualified executable')
    o = Original(data)
    stats, packed = o.alloc(0x710), o.alloc(0x110)
    entry, stop = LOCATIONS[campaign]
    results = []
    for row in rows:
        o.floats(stats+0x34, *row['speeds'])
        o.floats(stats+0x28, row['factor'])
        o.run(entry, stats, [0, packed], end=stop)
        results.append(dict(input=row, bytes=list(o.uc.mem_read(packed+0x10,5))))
    o.close()
    return dict(sha256=digest, entry=hex(entry), stop=hex(stop), rows=results)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--original', required=True); p.add_argument('--astral', required=True)
    p.add_argument('--base-census', required=True); p.add_argument('--astral-census', required=True)
    p.add_argument('--output', required=True)
    a = p.parse_args()
    censuses = {'original':a.base_census,'lost_in_astral':a.astral_census}
    rows = inputs(censuses)
    report = dict(scope=__doc__, census_sha256={k:hashlib.sha256(Path(v).read_bytes()).hexdigest() for k,v in censuses.items()},
                  campaigns={k:capture(v,k,rows) for k,v in [('original',a.original),('lost_in_astral',a.astral)]})
    Path(a.output).write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({k:len(v['rows']) for k,v in report['campaigns'].items()}))
