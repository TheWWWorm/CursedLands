"""Execute the original full-save loader's zone-type branch in both games.

The input is a supplied zone record returned by the preceding zone lookup.
Execution stops at either mission.sav opening or common zone-entry setup.
No file I/O, world deserialization, script restoration or whole-scene replay
is claimed by this bounded branch capture.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'parity'))
from native import Original
from cases import REFERENCES
from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EBP, UC_X86_REG_EIP

LOCATIONS = {
    'original': dict(start=0x57b1a7, mission=0x57b1ca, entry=0x57b1b5),
    'lost_in_astral': dict(start=0x4e3820, mission=0x4e3844, entry=0x4e382e),
}


def capture(path, campaign):
    data = Path(path).read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    assert sha == REFERENCES[campaign]['executable_sha256']
    o = Original(data)
    loc = LOCATIONS[campaign]
    zone = o.alloc(0x60)
    # Stop before either downstream operation. The comparison and conditional
    # jumps themselves run unchanged from the supplied executable.
    o.hook(loc['entry'], o.uc.emu_stop)
    rows = []
    for kind, label in [(0, 'field'), (1, 'global_map'), (2, 'town')]:
        o.write(zone + 0x28, kind)
        o.uc.reg_write(UC_X86_REG_EAX, zone)
        o.uc.reg_write(UC_X86_REG_EBP, 0)  # base loader's zero register
        o.slice(loc['start'], loc['mission'], alternatives=(loc['entry'],))
        end = o.uc.reg_read(UC_X86_REG_EIP)
        rows.append(dict(zone_type=kind, label=label, endpoint=hex(end),
                         route='mission' if end == loc['mission'] else 'zone_entry'))
    o.close()
    return dict(sha256=sha, locations={k: hex(v) for k, v in loc.items()}, cases=rows)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--original', required=True)
    p.add_argument('--astral', required=True)
    p.add_argument('--output', required=True)
    a = p.parse_args()
    result = dict(scope=__doc__, campaigns={
        'original': capture(a.original, 'original'),
        'lost_in_astral': capture(a.astral, 'lost_in_astral')})
    Path(a.output).write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v['cases'] for k, v in result['campaigns'].items()}))
