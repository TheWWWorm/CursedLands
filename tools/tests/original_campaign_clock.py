"""Native GS clock writes/deletion and the zone-entry daylight handoff.

The original interpreter, GS hash lookup/update/erase, clock query and the
zone-entry modulo/setter instructions execute in Unicorn. Supplied boundaries
are retained temporary strings, player lookup, locale storage, node release,
and outgoing network/render notifications. Base-game hash capacity is supplied.
Map file loading is not executed.
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
from unicorn.x86_const import UC_X86_REG_ECX, UC_X86_REG_ESP

LOCATIONS = {
    'original': dict(world=0x7aff50, scale=0x79be4c,
        hour=0x58eea0, rate=0x58eee0, read=0x460af0, release=0x461710,
        zone_start=0x57c5df, zone_end=0x57c606, local_table=0x78,
        notify=0x58b6d0, render=0x58ccd0, first=0x404920, next=0x404960,
        set=0x66edd0, set_max=0x66ee40),
    'lost_in_astral': dict(world=0x6a33d8, scale=0x676a4c,
        hour=0x4f0aa0, rate=0x4f0ae0, read=0x431d80, release=0x5d8df0,
        zone_start=0x4e1d2a, zone_end=0x4e1d51, local_table=0x78,
        notify=0x4e6910, render=0x4f01f0, first=0x402250, next=0x402290,
        set=0x5943e0, set_max=0x594450),
}


def capture(path, campaign):
    data = Path(path).read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    assert sha == REFERENCES[campaign]['executable_sha256']
    o = Original(data); o.campaign = campaign
    a, loc = ADDRESSES[campaign], LOCATIONS[campaign]
    world = loc['world']
    player, bucket, node, sink = [o.alloc(n) for n in (0x200, 4, 12, 16)]
    vt, ctx, instance, output, cmd, numeric, strings, vector, thread, killed = [
        o.alloc(n) for n in (0x100, 0x220, 0xc0, 4, 0x94, 8, 4, 20, 0xc0, 4)]
    raw = b'gtime\0'; name = o.alloc(16+len(raw))+16
    o.write(name-4, 100000); o.uc.mem_write(name, raw)
    o.write(world, vt); o.write(vt+0x7c, loc['hour'])
    o.write(vt+0x50, 0x1810)
    o.hook(0x1810, lambda: o.ret(player))
    o.hook(loc['first'], lambda: o.ret(player, cleanup=4))
    o.hook(loc['next'], lambda: o.ret())
    o.write(world+0x12d64, 1); o.write(loc['scale'], 60)
    o.write(player+0x1c, player); o.write(player+0x20, player)
    o.write(player+0x48, sink); o.write(sink+8, 0x1800)
    o.hook(0x1800, lambda: o.ret(cleanup=8))
    o.hook(a['player'], lambda: o.ret(player, cleanup=4))
    o.hook(a['network'], lambda: o.ret())
    def temporary_string():
        o.write(o.uc.reg_read(UC_X86_REG_ECX), o.args(1)[0]); o.ret(cleanup=4)
    o.hook(a['string'], temporary_string)
    if campaign == 'original':
        o.hook(0x700930, lambda: o.ret())
        # Retain the supplied string and table capacity. Native hash lookup,
        # value replacement and bucket unlink still execute normally.
        def copy_string():
            o.write(o.uc.reg_read(UC_X86_REG_ECX), o.ints(o.args(1)[0])[0])
            o.ret(cleanup=4)
        o.hook(0x7006a5, copy_string)
        o.hook(0x461750, lambda: o.ret(cleanup=4))
    else:
        tls, locale = o.alloc(0x100), o.alloc(0x200)
        o.write(tls+0x60, locale); o.write(0x6bda2c, locale)
        o.hook(0x5f25dd, lambda: o.ret(tls))
    o.hook(loc['release'], lambda: o.ret())
    o.hook(loc['notify'], lambda: o.ret(cleanup=4))
    o.hook(loc['render'], lambda: o.ret())
    o.hook(a['cleanup'], lambda: o.ret())
    reached = []
    # Observe entry without replacing the native functions. This catches an
    # incorrect dispatcher opcode instead of accepting its default no-op.
    o.hook(loc['set'], lambda: reached.append('GSSetVar'))
    o.hook(loc['set_max'], lambda: reached.append('GSSetVarMax'))
    o.write(cmd+8, numeric); o.write(cmd+0x1c, strings)
    o.write(strings, name); o.write(vector+4, cmd, 1)

    def table(at):
        o.write(at+4, bucket, bucket+4); o.write(at+0x10, 1)

    def sample():
        o.write(cmd, 0xb5)
        o.run(a['eval'], cmd, [ctx, instance, output]); hour = o.number(output)
        o.write(cmd, 0x80); o.floats(numeric, 0)
        o.run(a['eval'], cmd, [ctx, instance, output])
        return dict(hour=hour, gtime=o.number(output), fixed=o.number(world+0x20)==0,
                    present=bool(o.ints(bucket)[0]))

    rows = []
    for now in [0, 12345]:
        for initial in [6.0, 35.75, 99.95]:
            for fixed in [False, True]:
                for op, value in [('GSSetVar', -1.25), ('GSSetVar', 0),
                                  ('GSSetVar', 19), ('GSSetVar', 50.5), ('GSDelVar', 0),
                                  ('GSSetVarMax', -4), ('GSSetVarMax', 0), ('GSSetVarMax', 45)]:
                    o.write(bucket, node); o.write(node, 0, name); o.floats(node+8, initial)
                    table(player+0xc4); o.write(world+0x64, now)
                    o.write(player+0x110, now)
                    o.run(loc['rate'], world, [float_bits(0 if fixed else 60)])
                    o.run(loc['hour'], world, [float_bits(.3 if fixed else 11.75)])
                    states = [dict(action='initial', state=sample())]
                    o.write(cmd, {'GSSetVar':0x7f,'GSSetVarMax':0x98,'GSDelVar':0x82}[op])
                    o.floats(numeric, 0, value)
                    o.write(thread, vector, 0, 0, -1, killed)
                    reached.clear(); o.run(a['program'], thread, [ctx])
                    assert o.ints(thread+4)[0] == 1
                    if op != 'GSDelVar': assert reached and reached[0] == op and reached.count(op)==1, (op,reached)
                    states.append(dict(action=op, state=sample()))
                    # Exact native zone-entry slice, after map/party loading:
                    # read copied GS store, native fmod(24), call scene setter.
                    table(0x91ff000+loc['local_table'])
                    o.run(loc['zone_start'], 0, [], end=loc['zone_end'])
                    states.append(dict(action='zone_hour', state=sample()))
                    rows.append(dict(now=now, initial=f32(initial), fixed=fixed, op=op,
                                     value=f32(value), rows=states))
    o.close()
    return dict(sha256=sha, locations={k:hex(v) for k,v in loc.items()}, cases=rows)


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--original'); p.add_argument('--astral',required=True); p.add_argument('--output',required=True)
    a=p.parse_args(); paths=[('lost_in_astral',a.astral)]
    if a.original: paths.insert(0,('original',a.original))
    d=dict(scope=__doc__,campaigns={k:capture(v,k) for k,v in paths})
    Path(a.output).write_text(json.dumps(d,indent=2)+'\n')
    print(json.dumps({k:len(v['cases'])*3 for k,v in d['campaigns'].items()}))
