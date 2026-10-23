#!/usr/bin/env python3
"""Build small, fingerprinted LiA 1.02 corrections from owned patch inputs.

The AST export is produced by tools/tests/astral_patch_sources.gd. This emits
only changed values/statements and continuation maps, never whole MOB/RES files.
"""
import argparse
import base64
import difflib
import hashlib
import json
from pathlib import Path
import struct


def digest(data):
    return hashlib.sha256(data).hexdigest()


def token(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':'))


def edits(a, b, path=()):
    if a == b:
        return []
    if isinstance(a, dict) and isinstance(b, dict):
        out = []
        for key in sorted(a.keys() | b.keys()):
            if key not in b:
                out.append(['erase', list(path + (key,))])
            elif key not in a:
                out.append(['set', list(path + (key,)), b[key]])
            else:
                out += edits(a[key], b[key], path + (key,))
        return out
    if isinstance(a, list) and isinstance(b, list):
        if len(a) == len(b):
            return [op for i, (x, y) in enumerate(zip(a, b)) for op in edits(x, y, path + (i,))]
        out = []
        matcher = difflib.SequenceMatcher(None, list(map(token, a)), list(map(token, b)), autojunk=False)
        for tag, i, end, j, stop in reversed(matcher.get_opcodes()):
            if tag != 'equal':
                out.append(['splice', list(path), i, end-i, b[j:stop]])
        return out
    return [['set', list(path), b]]


def positions(a, b):
    """Map the next old instruction to its new position; include new inserts."""
    pos = [None] * (len(a) + 1)
    matcher = difflib.SequenceMatcher(None, list(map(token, a)), list(map(token, b)), autojunk=False)
    for tag, i, end, j, stop in matcher.get_opcodes():
        for offset in range(end-i+1):
            new = j + min(offset, stop-j) if tag in ('equal', 'replace') else j
            at = i + offset
            pos[at] = min(pos[at], new) if pos[at] is not None else new
    out = {'ip': pos, 'loops': {}}
    for i, statement in enumerate(a):
        if statement[0] != 5:
            continue
        candidates = [j for j, other in enumerate(b) if other[:3] == statement[:3]]
        if len(candidates) == 1:
            j = candidates[0]
            out['loops'][str(i)] = {'target': j, 'body': positions(statement[3], b[j][3])}
    return out


def continuations(a, b):
    out = {}
    for name, old in a['scripts'].items():
        new = b['scripts'].get(name)
        if old == new:
            continue
        blocks = {}
        for i, block in enumerate(old['blocks']):
            found = [j for j, target in enumerate(new['blocks']) if block['conds'] == target['conds']] if new else []
            if not found and new and len(old['blocks']) == len(new['blocks']) == 1:
                found = [0]
            if len(found) != 1:
                blocks[str(i)] = {'target': -1}
            else:
                j = found[0]
                blocks[str(i)] = {'target': j, 'body': positions(block['body'], new['blocks'][j]['body'])}
        out[name] = blocks
    if a['world'] != b['world']:
        out['WorldScript'] = {'0': {'target': 0, 'body': positions(a['world'], b['world'])}}
    return out


def archive(path):
    data = path.read_bytes()
    magic, count, table, _ = struct.unpack_from('<4I', data)
    assert magic == 0x019CE23C
    result = {}
    for i in range(count):
        at = table + i * 22
        size, offset = struct.unpack_from('<II', data, at+4)
        name_len, name_offset = struct.unpack_from('<HI', data, at+16)
        name_at = table + count*22 + name_offset
        name = data[name_at:name_at+name_len].decode('ascii').lower()
        result[name] = data[offset:offset+size]
    return result


def byte_patch(a, b):
    if len(a) == len(b):
        spans = []
        for i, (x, y) in enumerate(zip(a, b)):
            if x == y:
                continue
            if spans and i-spans[-1][1] <= 8:
                spans[-1][1] = i+1
            else:
                spans.append([i, i+1])
        ops = [[start, end-start, base64.b64encode(b[start:end]).decode()] for start, end in spans]
    else:
        # Map25 adds one object. Anchor the large unchanged prefix/suffix,
        # then find matches only inside the small changed middle.
        prefix = 0
        while prefix < min(len(a), len(b)) and a[prefix] == b[prefix]:
            prefix += 1
        suffix = 0
        while suffix < min(len(a), len(b))-prefix and a[-suffix-1] == b[-suffix-1]:
            suffix += 1
        matcher = difflib.SequenceMatcher(None, a[prefix:len(a)-suffix], b[prefix:len(b)-suffix], autojunk=True)
        ops = [[prefix+i, end-i, base64.b64encode(b[prefix+j:prefix+stop]).decode()]
               for tag, i, end, j, stop in matcher.get_opcodes() if tag != 'equal']
    rebuilt = bytearray(a)
    for offset, count, data in reversed(ops):
        rebuilt[offset:offset+count] = base64.b64decode(data)
    assert rebuilt == b
    return {'before': digest(a), 'after': digest(b), 'size': len(b), 'edits': ops}


def build(args):
    exported = json.loads(args.ast.read_text())
    zones = {'zone11dun2':'gz11d2', 'zone1dun2':'gz1d2', 'zone21':'gz21k', 'zone23':'gz23k',
             'zone25':'gz25k', 'zone31':'gz31j', 'zone32':'gz32j'}
    data = {'revision': 1, 'scripts': {}, 'database': {}, 'files': {}, 'texts': {}}
    for file, target in exported['102'].items():
        if file == 'zone25':
            continue
        zone = zones.get(file, file if file.startswith('b') else 'g'+file.replace('zone', 'z')+'g')
        row = {'map': file, 'canonical': target['hash'], 'variants': {}}
        for edition in ('cd', '101'):
            original = exported[edition][file]
            if original['hash'] == target['hash'] or original['hash'] in row['variants']:
                continue
            row['variants'][original['hash']] = {'edition': edition,
                'edits': edits(original['ast'], target['ast']),
                'continuations': continuations(original['ast'], target['ast'])}
        data['scripts'][zone] = row
    old, new = archive(args.cd/'res/database.res'), archive(args.patched/'res/database.res')
    for entry in old:
        if old[entry] != new[entry]:
            data['database'][entry] = byte_patch(old[entry], new[entry])
    key = 'maps/zone25.mob'
    data['files'][key] = byte_patch((args.cd/key).read_bytes(), (args.patched/key).read_bytes())
    texts = [archive(root/'res/texts.res') for root in [args.cd,args.patch101,args.patched]]
    for key in sorted(texts[0].keys() | texts[2].keys()):
        target = texts[2].get(key,b'').decode('cp1251').replace('\r','')
        variants = {}
        for table in texts[:2]:
            original = table.get(key,b'').decode('cp1251').replace('\r','')
            if original == target:continue
            matcher = difflib.SequenceMatcher(None,original,target,autojunk=False)
            variants[digest(original.encode())] = [[i,end-i,target[j:stop]]
                for tag,i,end,j,stop in matcher.get_opcodes() if tag!='equal']
        if variants:data['texts'][key]={'canonical':digest(target.encode()),'variants':variants}
    header = '# Generated by tools/build_astral_patch_data.py from the official LiA 1.01/1.02 changes.\n'
    header += '# Contains corrections and save-position mappings; original game files are still required.\n'
    args.output.write_text(header+'extends RefCounted\nconst DATA := '+json.dumps(data, ensure_ascii=False, indent='\t')+'\n')
    print(f'{args.output}: {args.output.stat().st_size} bytes, {len(data["scripts"])} script maps, {len(data["database"])} database entries')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ast', type=Path, required=True)
    p.add_argument('--cd', type=Path, required=True)
    p.add_argument('--patched', type=Path, required=True)
    p.add_argument('--patch101', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    build(p.parse_args())
