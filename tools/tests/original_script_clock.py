"""Execute the original scene-clock commands, query and campaign-time updater.

The command interpreter, rate/offset setters, modulo-hour query and elapsed
campaign-time arithmetic execute original x86 instructions. Hooks supply one
player and its gtime storage, and omit rendering/network notifications. Tick
advancement is an explicit fixture input, not a full Windows game simulation.
"""
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'parity'))
from native import Original, f32, float_bits
from native_quests import ADDRESSES
from cases import REFERENCES
from unicorn.x86_const import UC_X86_REG_EIP

LOCATIONS = {
    'original': dict(world=0x7aff50, scale=0x79be4c, set_hour=0x58eea0,
        update=0x58d280, notify=0x58b6d0, render=0x58ccd0,
        first=0x404920, next=0x404960, read=0x460af0, write=0x66edd0),
    'lost_in_astral': dict(world=0x6a33d8, scale=0x676a4c, set_hour=0x4f0aa0,
        update=0x4e69a0, notify=0x4e6910, render=0x4f01f0,
        first=0x402250, next=0x402290, read=0x431d80, write=0x5943e0),
}


def capture(path, campaign):
    data = Path(path).read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    if sha != REFERENCES[campaign]['executable_sha256']:
        raise ValueError('Unqualified executable')
    o = Original(data)
    loc = LOCATIONS[campaign]
    world = loc['world']
    vt, player, gtime, context, instance, output, command, args, vector, thread, killed = [
        o.alloc(n) for n in [0x100, 0x200, 4, 0x220, 0xc0, 4, 0x94, 4, 20, 0xc0, 4]]
    o.write(world, vt); o.write(vt+0x50, 0x1800); o.write(vt+0x7c, loc['set_hour'])
    o.write(world+0x12d64, 1); o.write(player+0x20, player)
    o.write(loc['scale'], 60)
    o.hook(0x1800, lambda: o.ret(player))
    o.hook(loc['first'], lambda: o.ret(player, 4))
    o.hook(loc['next'], lambda: o.ret())
    # Supplied GS storage returns float via the x87 stack, preserving native
    # updater arithmetic rather than replacing it with a Python calculation.
    o.uc.mem_write(0x1810, b'\xd9\x05'+struct.pack('<I', gtime)+b'\xc2\x04\x00')
    o.hook(loc['read'], lambda: o.uc.reg_write(UC_X86_REG_EIP, 0x1810))
    def write():
        _, value = o.args(2)
        o.write(gtime, value); o.ret(cleanup=8)
    o.hook(loc['write'], write)
    o.hook(loc['notify'], lambda: o.ret(cleanup=4))
    o.hook(loc['render'], lambda: o.ret())
    o.hook(ADDRESSES[campaign]['cleanup'], lambda: o.ret())
    o.write(command+8, args); o.write(vector+4, command, 1)

    def sample():
        o.write(command, 0xb5)
        o.run(ADDRESSES[campaign]['eval'], command, [context, instance, output])
        return dict(hour=o.number(output), gtime=o.number(gtime), rate=o.number(world+0x20),
                    offset=o.number(world+0x1c), tick=o.ints(world+0x64)[0])

    def action(op, hour):
        o.write(command, 0xb7 if op=='FixWorldTime' else 0xb6); o.floats(args,hour)
        o.write(thread, vector, 0, 0, -1, killed)
        o.run(ADDRESSES[campaign]['program'], thread, [context])
        if o.ints(thread+4)[0] != 1: raise AssertionError('Command did not finish')

    cases = []
    for now in [0, 12345]:
        for initial in [6.0, 35.75, 99.95]:
            for hour in [-.3, 0, .3, 23.0, 24.0, 25.5]:
                rate = f32(f32(1/60)/15)
                o.write(world+0x64, now); o.write(player+0x110, now)
                o.floats(world+0x20,rate); o.floats(gtime,initial)
                o.run(loc['set_hour'],world,[float_bits(initial % 24)])
                rows = [dict(action={'op':'initial'}, state=sample())]
                actions = [dict(op='advance',ticks=7), dict(op='FixWorldTime',hour=hour),
                    dict(op='advance',ticks=13), dict(op='FixWorldTime',hour=.3),
                    dict(op='advance',ticks=900), dict(op='RunWorldTime',hour=19),
                    dict(op='advance',ticks=7), dict(op='advance',ticks=900),
                    dict(op='RunWorldTime',hour=hour), dict(op='advance',ticks=1)]
                for step in actions:
                    if step['op']=='advance':
                        o.write(world+0x64,o.ints(world+0x64)[0]+step['ticks'])
                        o.run(loc['update'],world,[0])
                    else: action(step['op'],step['hour'])
                    rows.append(dict(action=step,state=sample()))
                cases.append(dict(now=now,initial_gtime=f32(initial),rows=rows))
    o.close()
    return dict(sha256=sha,locations={k:hex(v) for k,v in loc.items()},cases=cases)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--original');p.add_argument('--astral',required=True);p.add_argument('--output',required=True)
    a=p.parse_args()
    paths=[('lost_in_astral',a.astral)]
    if a.original:paths.insert(0,('original',a.original))
    report=dict(scope=__doc__,campaigns={k:capture(v,k) for k,v in paths})
    Path(a.output).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:sum(len(c['rows']) for c in v['cases']) for k,v in report['campaigns'].items()}))
