"""Execute GetFutureX/Y in both qualified original x86 interpreters.

The only hook supplies the object's virtual future-position result at vtable
+0xd0. The original dispatcher evaluates the command, converts now + delay to
an absolute tick, invokes that method and returns the selected float32 axis.
This captures the script dispatch contract, not the original path predictor,
collision response or a complete running game.
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
from unicorn.x86_const import UC_X86_REG_ECX

LOCATIONS = {'original': (0x4b41e0, 0x7affb4), 'lost_in_astral': (0x46cca0, 0x6a343c)}


def inputs():
    for now in [0, 1, 2, 9, 10, 1000000, 16777215, 16777216]:
        for delay in [-2.5, -1, 0, .25, .5, .50000006, 1.5, 2.5, 3, 30, 60, 500]:
            for axis in range(2):
                yield dict(now=now, delay=f32(delay), axis=axis, present=True, point=[123.25, -72.5, 8])
    for axis in range(2):
        yield dict(now=101, delay=3, axis=axis, present=False, point=[123.25, -72.5, 8])


def capture(path, campaign):
    data = Path(path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != REFERENCES[campaign]['executable_sha256']:
        raise ValueError('Unqualified executable')
    o = Original(data)
    command, args, slots, slot, unit, vt, out, context, instance = [
        o.alloc(n) for n in [0x100, 32, 16, 16, 0x600, 0x200, 32, 0x220, 0xc0]]
    o.write(command+8, args); o.write(command+0x30, slots)
    o.write(slots, slot); o.write(unit, vt); o.write(vt+0xd0, 0x1800)
    calls, point = [], []

    def prediction():
        vector, target = o.args(2)
        target = struct.unpack('<i', struct.pack('<I', target))[0]
        calls.append(dict(absolute_tick=target, correct_object=o.uc.reg_read(UC_X86_REG_ECX)==unit))
        o.floats(vector, *point)
        o.ret(vector, cleanup=8)

    o.hook(0x1800, prediction)
    entry, clock = LOCATIONS[campaign]
    results = []
    for row in inputs():
        calls.clear(); point[:] = row['point']
        o.write(clock, row['now']); o.write(command, 0xbf+row['axis'])
        o.floats(args, row['delay']); o.write(slot, unit if row['present'] else 0)
        o.floats(out, -999)
        o.run(entry, command, [context, instance, out])
        results.append(dict(input=row, calls=calls.copy(), value=o.number(out), value_bits=o.ints(out)[0]))
    o.close()
    return dict(sha256=digest, entry=hex(entry), clock=hex(clock), rows=results)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--original', required=True); p.add_argument('--astral', required=True)
    p.add_argument('--output', required=True)
    a = p.parse_args()
    report = dict(scope=__doc__, campaigns={k:capture(v,k) for k,v in [('original',a.original),('lost_in_astral',a.astral)]})
    Path(a.output).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:len(v['rows']) for k,v in report['campaigns'].items()}))
