"""Audit the shipped Haburu references without altering original game assets.

Usage: python3 tools/tests/lia_haburu_source_audit.py LIA_GAME_DIRECTORY OUTPUT_JSON
Reads each MOB's top-level script directly and the pinned LiA native command
table. This is static source evidence, not an original-executable playthrough.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import struct

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('game', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def script(data):
    # The native reader consumes the OBJECTDBFILE root. Trailing editor data
    # is not a second executable script or an implicit function library.
    root, end = struct.unpack_from('<II', data)
    assert root == 0xA000 and 8 <= end <= len(data)
    at = 8
    result = b''
    while at + 8 <= end:
        kind, size = struct.unpack_from('<II', data, at)
        assert size >= 8 and at + size <= end
        body = data[at + 8:at + size]
        if kind == 0xACCEECCA:
            assert not result
            result = body
        elif kind == 0xACCEECCB:
            assert not result and len(body) >= 4
            key = struct.unpack_from('<I', body)[0]
            decoded = bytearray()
            for value in body[4:]:
                key = (key * 214013 + 2531011) & 0xFFFFFFFF
                decoded.append(value ^ ((key >> 16) & 255))
            result = bytes(decoded)
        at += size
    assert at == end
    return result


def native_table(data):
    # These addresses belong only to this independently inspected executable.
    assert sha(data) == 'f04a305b77c84ea29c18ad2996d23072ccef1c0c46876c9b93bae4ce9351d1ff'
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    count, opt_size = struct.unpack_from('<H12xH', data, pe + 6)
    opt = pe + 24
    base = struct.unpack_from('<I', data, opt + 28)[0]
    sections = [struct.unpack_from('<4I', data, opt + opt_size + 40 * i + 8) for i in range(count)]

    def read(address, size):
        for _, rva, raw_size, raw in sections:
            if base + rva <= address and address + size <= base + rva + raw_size:
                start = raw + address - base - rva
                return data[start:start + size]
        raise ValueError(hex(address))

    rows = []
    for i in range(1000):
        address = 0x66C078 + 16 * i
        name, opcode, query, statement = struct.unpack('<4I', read(address, 16))
        if not name:
            return rows
        rows.append({'address': hex(address), 'name': read(name, 256).split(b'\0', 1)[0].decode('ascii'),
                     'opcode': hex(opcode), 'query': bool(query), 'statement': bool(statement)})
    raise AssertionError('unterminated native command table')


checks = 0


def check(ok):
    global checks
    checks += 1
    assert ok


names = [f'BuyHaburuMain#2#{i}#0' for i in range(1, 6)]
maps = []
definitions = {}
references = {name: [] for name in names}
target = ''
for path in sorted((args.game / 'maps').glob('*.mob')):
    data = path.read_bytes()
    raw = script(data)
    text = raw.decode('cp1251')
    found = re.findall(r'^\s*(DeclareScript|Script)\s+([^\s(]+)', text, re.M)
    for kind, name in found:
        definitions.setdefault(name.lower(), []).append({'map': path.name, 'kind': kind})
    for line, value in enumerate(text.splitlines(), 1):
        for name in names:
            if name.lower() in value.lower():
                references[name].append({'map': path.name, 'line': line, 'source': value.strip()})
    maps.append({'name': path.name, 'sha256': sha(data), 'script_bytes': len(raw),
                 'script_ascii_sha256': sha(bytes(v if v < 128 else 63 for v in raw)),
                 'declarations': sum(k == 'DeclareScript' for k, _ in found),
                 'definitions': sum(k == 'Script' for k, _ in found)})
    if path.name.lower() == 'bz23k.mob':
        target = text

check(bool(target))
world = target.split('WorldScript', 1)[1]
check('Sleep( 2 )' in world and 'Start( NULL )' in world)
check(world.index('Start( NULL )') < world.index(names[0]))
table = native_table((args.game / 'game.exe').read_bytes())
check(len(table) == 227)
for name in names:
    check(name.lower() not in definitions)
    check(len(references[name]) == 1 and references[name][0]['map'].lower() == 'bz23k.mob')
    check(references[name][0]['source'] == name + ' ( NULL )')
    check(not any(name.lower().startswith(row['name'].lower()) for row in table))

report = {'checks': checks, 'failures': 0, 'game': str(args.game), 'maps': maps,
          'script_count': sum(row['script_bytes'] > 0 for row in maps), 'references': references,
          'missing_declarations_and_definitions': names,
          'native': {'executable': str(args.game / 'game.exe'), 'sha256': sha((args.game / 'game.exe').read_bytes()),
                     'table_address': '0x66c078', 'commands': len(table),
                     'matching_command_prefixes': [], 'resolver': '0x477e30'},
          'scope': 'All supplied map script bodies plus the pinned native command table; no synthesized quest behavior or native scene playback.',
          'audit_sha256': sha(Path(__file__).read_bytes())}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'checks': checks, 'maps': len(maps), 'scripts': report['script_count'], 'output': str(args.output)}))
