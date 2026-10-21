"""Replay native lever eligibility, use consumption, state reset and re-enable.

Both original x86 executables run in Unicorn. The permission query executes
without hooks; the use handler consumes a supplied skill verdict. SetState's
integer transition executes with a supplied zero duration and an offline world
that omits navigation/render updates. Replication notifications are stubbed.
This observes logical state and permission, not animation, collision or UI.
"""
import argparse
import hashlib
import itertools
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "parity"))
from native import Original
from cases import REFERENCES
from unicorn.x86_const import UC_X86_REG_ESP

LOCATIONS = {
    "original": dict(eligible=0x52bb00, use=0x52bb50, skill=0x522a80,
                     state=0x52b7a0, enable=0x52bad0, world=0x455950, notify=0x50e9f0),
    "lost_in_astral": dict(eligible=0x4ab3b0, use=0x4ad5e0, skill=0x4a68b0,
                           state=0x4ad2e0, enable=0x4ab370, world=0x432210, notify=0x498bd0),
}


def capture(path, campaign):
    data = Path(path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != REFERENCES[campaign]["executable_sha256"]:
        raise ValueError("Unqualified executable")
    o = Original(data)
    loc = LOCATIONS[campaign]
    obj, world, vt = o.alloc(0x300), o.alloc(0x300), o.alloc(0x100)
    o.write(world, vt); o.write(vt + 0x68, 0x1800)
    o.hook(0x1800, lambda: o.ret(0))
    o.hook(loc['world'], lambda: o.ret(world))
    o.hook(loc['notify'], lambda: o.ret(cleanup=4))
    verdict = [True]
    o.hook(loc['skill'], lambda: o.ret(int(verdict[0]), cleanup=4))
    # Supply immediate motion; all state/clamping and permission writes run.
    o.hook(loc['state'], lambda: o.floats(o.uc.reg_read(UC_X86_REG_ESP) + 8, 0))

    def setup(states, state, cycled, mask, enabled):
        o.write(obj + 8, 0 if enabled else 0x80000)
        o.write(obj + 0x238, state, states, cycled, mask, 0, 0)

    def observe():
        return dict(state=o.ints(obj + 0x238)[0], enabled=not bool(o.ints(obj + 8)[0] & 0x80000),
                    usable=bool(o.run(loc['eligible'], obj)))

    eligibility = []
    for states, last, cycled, mask, enabled in itertools.product([1, 2, 3, 4], [False, True], [0, 1], [0, 1, 5, 8, 15], [False, True]):
        state = states - 1 if last else 0
        setup(states, state, cycled, mask, enabled)
        eligibility.append(dict(input=dict(states=states, state=state, cycled=cycled, science=[mask, 0, 0], enabled=enabled), expected=observe()))
    sequences = []
    for states, cycled, success in itertools.product([2, 3], [0, 1], [False, True]):
        setup(states, 0, cycled, 1, True); verdict[0] = success
        steps = [dict(action='initial', expected=observe())]
        result = o.run(loc['use'], obj, [0, 0]) & 0xff
        steps.append(dict(action='use', expected=observe(), success=bool(result)))
        o.run(loc['state'], obj, [0, 0])
        steps.append(dict(action='reset', expected=observe()))
        o.run(loc['enable'], obj, [1])
        o.run(loc['state'], obj, [states-1, 0])
        steps.append(dict(action='enable_at_end', expected=observe()))
        o.run(loc['enable'], obj, [0])
        steps.append(dict(action='disable', expected=observe()))
        sequences.append(dict(states=states, cycled=cycled, success=success, steps=steps))
    o.close()
    return dict(sha256=digest, locations={k:hex(v) for k,v in loc.items()}, eligibility=eligibility, sequences=sequences)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--original', required=True); p.add_argument('--astral', required=True); p.add_argument('--output', required=True)
    a = p.parse_args()
    result = dict(scope=__doc__, campaigns={c:capture(path,c) for c,path in [('original',a.original),('lost_in_astral',a.astral)]})
    Path(a.output).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({c:dict(eligibility=len(d['eligibility']),sequences=len(d['sequences'])) for c,d in result['campaigns'].items()}))
