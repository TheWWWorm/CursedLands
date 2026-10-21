"""Replay native effect registration for Enlarge/Shrink and adjacent effects.

The real switch, target guard, effect-record copy and presentation-strength
calculation execute from each shipped EXE. A supplied prototype record replaces
the database lookup; the target's AddEffect virtual call is an observed boundary.
The captured records establish registration/type/duration, not a full render.
"""
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "parity"))
from native import Original
from cases import REFERENCES
from unicorn.x86_const import UC_X86_REG_EBP, UC_X86_REG_EBX, UC_X86_REG_ESI, UC_X86_REG_ESP, UC_X86_REG_ECX

LOCATIONS = {
    "original": {"begin": 0x67f8ba, "end": 0x681411, "prototype": 0x68b9e0},
    "lost_in_astral": {"begin": 0x5a2839, "end": 0x5a3a7f, "prototype": 0x5a7cc0},
}


def capture(path, campaign):
    data = Path(path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != REFERENCES[campaign]["executable_sha256"]:
        raise ValueError("Executable differs from the qualified address map")
    o = Original(data)
    loc = LOCATIONS[campaign]
    effect, prototype, target, vtable = [o.alloc(n) for n in [0x200, 0x100, 0x100, 0x100]]
    o.write(target, vtable)
    o.write(vtable + 0xb4, 0x1800)
    o.floats(prototype + 0x2c, 15.0)
    o.hook(loc["prototype"], lambda: o.ret(prototype))
    records = []

    def added():
        raw = bytes(o.uc.mem_read(o.args(1)[0], 20))
        records.append({"target_matches": o.uc.reg_read(UC_X86_REG_ECX) == target,
                        "type": raw[0], "visual_strength": raw[1],
                        "ticks": struct.unpack_from("<i", raw, 4)[0],
                        "power": struct.unpack_from("<f", raw, 8)[0],
                        "raw": raw.hex()})
        o.ret(cleanup=4)

    o.hook(0x1800, added)
    rows = []
    for index, spell in [(29, "strength"), (30, "weak"), (37, "enlarge"), (38, "shrink")]:
        for ticks in [0, 1, 5, 120]:
            for has_target in [True, False]:
                records.clear()
                o.uc.mem_write(effect, bytes(0x200))
                o.write(effect + 0x1c, target if has_target else 0)
                o.write(effect + 0x50, index, ticks)
                o.floats(effect + 0x58, 15.0)
                stack, frame = 0x91fd000, 0x91fe000
                o.uc.mem_write(stack, bytes(0x2000))
                o.uc.reg_write(UC_X86_REG_ESP, stack)
                o.uc.reg_write(UC_X86_REG_EBX, effect)
                o.uc.reg_write(UC_X86_REG_EBP, frame if campaign == "original" else index)
                o.uc.reg_write(UC_X86_REG_ESI, index)
                o.slice(loc["begin"], loc["end"])
                rows.append({"spell": spell, "index": index, "ticks": ticks,
                             "has_target": has_target, "records": list(records)})
    o.close()
    return {"sha256": digest, "locations": {k: hex(v) for k, v in loc.items()}, "rows": rows}


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--original", required=True)
    p.add_argument("--astral", required=True)
    p.add_argument("--output", required=True)
    a = p.parse_args()
    result = {"scope": __doc__, "campaigns": {"original": capture(a.original, "original"),
              "lost_in_astral": capture(a.astral, "lost_in_astral")}}
    Path(a.output).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"observations": sum(len(c["rows"]) for c in result["campaigns"].values())}))
