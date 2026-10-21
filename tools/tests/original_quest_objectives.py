"""Capture QFinish's generated objective chains from the original x86 EXE.

The real generator chooses conditions, links, journal updates and completion.
Hooks replace only CString allocation/format/concatenation and observe the
script compiler input. The compiler and whole game do not execute here. Inputs
come from an installed-map census, plus empty/max-length boundary chains.
"""
import argparse
import hashlib
import json
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "parity"))
from native import Original
from cases import REFERENCES
from unicorn.x86_const import UC_X86_REG_ECX, UC_X86_REG_ESP

KINDS = {"QObjArea":0xd7,"QObjSeeObject":0xd8,"QObjSeeUnit":0xd9,
         "QObjKillUnit":0xda,"QObjKillGroup":0xdb,"QObjUse":0xdc,"QObjGetItem":0xdd}


def objectives(calls):
    rows = []
    for line in calls:
        match = re.fullmatch(r'(QObj\w+)\s*\(\s*(?:"([^"]*)"|([\d.\-]+))\s*(?:,\s*([\d.\-]+)\s*)?\)', line)
        if not match:
            if "QObj" in line: raise ValueError(line)
            continue
        kind, string, number, second = match.groups()
        rows.append([kind, string if string is not None else float(number), float(second or 0)])
    return rows


def capture(data, name, rows):
    o = Original(data)
    formats, compiled = [], []

    def cstring(at):
        raw = bytearray()
        while at and len(raw) < 65536:
            b = bytes(o.uc.mem_read(at, 1))
            if b == b'\0': return raw.decode('ascii')
            raw.extend(b); at += 1
        raise ValueError('invalid native string')

    def put(slot, text):
        raw = text.encode('ascii') + b'\0'
        p = o.alloc(len(raw)); o.uc.mem_write(p, raw); o.write(slot, p)

    def read(slot): return cstring(o.ints(slot)[0])

    def fmt():
        out, template = o.args(2)
        template = cstring(template)
        at = o.uc.reg_read(UC_X86_REG_ESP) + 12
        values = []
        for token in re.findall(r'%[ifs]', template):
            if token == '%f':
                values.append(struct.unpack('<d', o.uc.mem_read(at, 8))[0]); at += 8
            else:
                value = o.ints(at)[0]; at += 4
                values.append(cstring(value) if token == '%s' else value)
        text = template % tuple(values)
        formats.append(dict(template=template, args=values, text=text))
        put(out, text); o.ret(out)

    def append_object():
        target = o.uc.reg_read(UC_X86_REG_ECX)
        put(target, read(target) + read(o.args(1)[0])); o.ret(target, 4)

    def assign_raw():
        target = o.uc.reg_read(UC_X86_REG_ECX)
        put(target, cstring(o.args(1)[0])); o.ret(target, 4)

    def append_raw():
        target = o.uc.reg_read(UC_X86_REG_ECX)
        put(target, read(target) + cstring(o.args(1)[0])); o.ret(target, 4)

    def concat():
        target, left, right = o.args(3)
        put(target, read(left) + read(right)); o.ret(target, 12)

    def compile_source():
        source, mode = o.args(2)
        compiled.append(dict(source=read(source), mode=mode)); o.ret(1, 8)

    o.hook(0x6fdf1f, fmt)
    o.hook(0x700930, lambda: o.ret())
    o.hook(0x700d48, append_object)
    o.hook(0x700ab9, assign_raw)
    o.hook(0x700d0c, append_raw)
    o.hook(0x700b5f, concat)
    o.hook(0x4d23a0, compile_source)
    put(0x796e38, '')
    put(0x7aa60c, name)
    records = o.alloc(max(1,len(rows)) * 12)
    o.write(0x7aa5fc, records, len(rows))
    for i, (kind, arg, number) in enumerate(rows):
        slot = records + i * 12
        o.write(slot, KINDS[kind], 0, 0)
        if isinstance(arg, str): put(slot+4, arg)
        else: number = arg
        o.floats(slot+8, number)
    o.run(0x4baab0)
    if len(compiled) != 1 or compiled[0]['mode'] != 1:
        raise AssertionError(compiled)
    o.close()
    return dict(id=name, objectives=rows, source=compiled[0]['source'], formats=formats)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--original', required=True)
    p.add_argument('--census', required=True)
    p.add_argument('--output', required=True)
    a = p.parse_args()
    data = Path(a.original).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != REFERENCES['original']['executable_sha256']: raise ValueError('Unqualified executable')
    census_data = Path(a.census).read_bytes()
    census = json.loads(census_data)
    inputs = [(q['id'], objectives(q['calls'])) for q in census['quests'] if q['calls']]
    inputs.extend([('empty', []), ('sixteen', [['QObjUse','GetObject(100)',1]] * 16)])
    result = dict(scope=__doc__, executable_sha256=digest, generator='0x4baab0',
                  census_sha256=hashlib.sha256(census_data).hexdigest(),
                  rows=[capture(data, name, rows) for name, rows in inputs])
    Path(a.output).write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(dict(chains=len(result['rows']), objectives=sum(len(r['objectives']) for r in result['rows']))))
