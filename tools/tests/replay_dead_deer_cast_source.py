#!/usr/bin/env python3
"""Execute original LiA geometry union and unarmed cast fallback on authored poses.

Only graphics-mode discovery and the absent legacy socket lookup are hooked.
This is bounded native replay, not a full Windows-game visual test. No executable
bytes are redistributed. Inputs come from dead_deer_cast_source.gd.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'parity'))
from native import Original

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('binary', type=Path)
parser.add_argument('poses', type=Path)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
data = args.binary.read_bytes()
sha = hashlib.sha256(data).hexdigest()
assert sha == 'f04a305b77c84ea29c18ad2996d23072ccef1c0c46876c9b93bae4ce9351d1ff'
results = []
for case in json.loads(args.poses.read_text())['cases']:
    o = Original(data)
    unit, out, mode, vtable, mode_fn = [o.alloc(n) for n in [0x1000, 12, 16, 0x100, 16]]
    o.write(mode, vtable); o.write(vtable+0x68, mode_fn)
    o.hook(0x432200, lambda: o.ret(mode))
    o.hook(mode_fn, lambda: o.ret(0))
    o.hook(0x4b5fd0, lambda: o.ret(0, 4))
    o.write(unit+0x10, 0x34)
    o.floats(unit+0x1c, *case['position'])
    parts = o.alloc(4*len(case['parts']))
    o.write(unit+0xd0, parts, len(case['parts']))
    for i, part in enumerate(case['parts']):
        p = o.alloc(0x200); o.write(parts+i*4, p)
        o.floats(p+0x1c, *part['position'])
        for offset, key in [(0x18c,'centre'),(0x19c,'min'),(0x1a8,'max')]:
            o.floats(p+offset, *part[key])
    o.run(0x49f3f0, unit)
    centre = [o.number(unit+0x128+i*4) for i in range(3)]
    o.run(0x4aeac0, unit, [out])
    actual = [o.number(out+i*4) for i in range(3)]
    error = max(abs(a-b) for a,b in zip(actual, case['actual']))
    geometry_error = max(abs(a-b) for a,b in zip(centre, case['centre']))
    results.append({'id':case['id'],'facing':case['facing'],'frame':case['frame'],
                    'native':actual,'remake':case['actual'],'error':error,'geometry_error':geometry_error})
    o.close()
report = {'source_sha256':sha,'checks':len(results)*2,
          'failures':sum(x['error']>1e-4 for x in results)+sum(x['geometry_error']>1e-4 for x in results),
          'functions':['0x49f3f0','0x4aeac0'],
          'boundary':'Engine graphics mode and absent baserh3 lookup supplied; real authored pose origins/FIG bounds and original x87 union/source instructions executed.',
          'results':results}
args.output.write_text(json.dumps(report, indent=2)+'\n')
print('DEAD_DEER_NATIVE', json.dumps({k:report[k] for k in ['checks','failures']}))
sys.exit(bool(report['failures']))
