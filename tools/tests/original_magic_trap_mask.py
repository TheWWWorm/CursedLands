"""Execute the original map-loader mask loop, not a Python mask formula.

The full original was also observed under Wine; this bounded replay makes the
previously missed load-time conversion repeatable without a graphics runtime.
"""
import hashlib
import json
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "parity"))
from native import Original
from cases import REFERENCE
from unicorn.x86_const import UC_X86_REG_EBX, UC_X86_REG_ESI, UC_X86_REG_ESP

binary, game, output = map(Path, sys.argv[1:4])
data = binary.read_bytes()
assert hashlib.sha256(data).hexdigest() == REFERENCE["executable_sha256"]
mob = (game / "maps/zone3obr.mob").read_bytes()
at = mob.index(struct.pack("<I", 0xDDDDDDD2))
assert struct.unpack_from("<I", mob, at + 4)[0] == 4104
authored = list(struct.unpack_from("<1024I", mob, at + 8))
cases = [("gz3g shrine", 2, 0xFFFFFFFF, authored, 1)]
for owner in [0, 7, 31]:
    matrix = [1] * 1024
    for target in [0, 3, 31]:
        matrix[owner * 32 + target] = 2
    cases.append(("owner %d, sparse enemies" % owner, owner, 0, matrix, 0x80000009))
cases.append(("no enemies", 4, 0xFFFFFFFF, [0] * 1024, 0))
rows = []
for name, owner, raw, matrix, expected in cases:
    o = Original(data)
    record = o.alloc(0x100)
    o.write(record + 0x48, 7)
    o.write(record + 0x8C, raw)
    o.uc.mem_write(record + 0x6E, bytes([owner]))
    o.floats(record + 0x20, 194.918, 72.4484, -1)
    stack = 0x91F0000
    o.write(stack + 0xBC, *matrix)
    o.uc.reg_write(UC_X86_REG_ESP, stack)
    o.uc.reg_write(UC_X86_REG_ESI, record)
    o.uc.reg_write(UC_X86_REG_EBX, 0)
    o.slice(0x481C31, 0x481C80)
    mask = o.ints(record + 0x8C)[0]
    assert mask == expected, (name, mask, expected)
    assert bytes(o.uc.mem_read(record + 0x94, 12)) == bytes(o.uc.mem_read(record + 0x20, 12))
    rows.append({"case": name, "owner": owner, "raw_mask": raw, "effective_mask": mask})
    o.close()
dead_rows = []
for dead in [0, 1]:
    o = Original(data)
    unit = o.alloc(0x300)
    o.write(unit + 0x274, dead)
    value = o.run(0x446880, this=unit)
    assert value == dead
    dead_rows.append({"dead": dead, "virtual_dc_result": value})
    o.close()
report = {"executable_sha256": REFERENCE["executable_sha256"],
          "mask_slice": ["0x481c31", "0x481c80"], "dead_getter": "0x446880",
          "scope": "Actual x86 loader mask conversion and unit dead getter; supplied records/stack, no full-world replay claim.",
          "masks": rows, "dead_getter_cases": dead_rows}
output.write_text(json.dumps(report, indent=2) + "\n")
print("ORIGINAL_MAGIC_TRAP_MASK 7 cases passed")
