"""Replay the original spell-dispatch provocation branch from shipped x86 code.

This captures dispatch-side AI notifications and hostility writes, not spell
damage/effects or a complete encounter. Spell index, target kind, caster and
friendship are supplied inputs. The AI notification and replication transport
are observed boundaries. Hostility selection and writes execute natively.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "parity"))
from native import Original
from cases import REFERENCES
from unicorn.x86_const import UC_X86_REG_EBP, UC_X86_REG_EBX, UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_ESP, UC_X86_REG_ECX

LOCATIONS = {
    "original": {"begin": 0x58e7a7, "end": 0x58e813, "hit": 0x5d7e90,
                 "replicate": 0x50e9f0, "world_diplomacy": 0x12c64, "spell_stack": 0x30},
    "lost_in_astral": {"begin": 0x4e7db7, "end": 0x4e7e1a, "hit": 0x51bee0,
                       "replicate": 0x498bd0, "world_diplomacy": 0x12c64, "spell_stack": 0x2c},
}


def capture(path, campaign):
    data = Path(path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != REFERENCES[campaign]["executable_sha256"]:
        raise ValueError("Executable differs from the qualified address map")
    o = Original(data)
    loc = LOCATIONS[campaign]
    world, spell, caster, target, controller, vtable = [o.alloc(n) for n in [0x14000, 0x80, 0x400, 0x400, 0xc00, 0x100]]
    o.write(target, vtable)
    o.write(target + 0x240, controller)
    o.write(target + 0x250, 1)
    o.write(caster + 0x250, 0)
    o.write(vtable + 0x30, 0x1800)
    kind = [0x50]
    o.hook(0x1800, lambda: o.ret(kind[0]))
    notices = []
    def notified():
        notices.append({"target": o.uc.reg_read(UC_X86_REG_ECX) == controller + 0x980,
                        "caster": o.args(1)[0] == caster})
        o.ret(cleanup=4)
    o.hook(loc["hit"], notified)
    o.hook(loc["replicate"], lambda: o.ret(cleanup=4))
    rows = []
    for index in range(40):
        for situation in ["enemy", "neutral", "friend", "no_caster", "point", "object"]:
            notices.clear()
            kind[0] = 0x3f if situation == "object" else 0x50
            o.write(world + loc["world_diplomacy"] + 4, 3 if situation == "friend" else 2)
            o.write(target + 0x244, 0)
            o.write(target + 8, 0)
            o.write(caster + 8, 0)
            o.write(spell + 0x18, index << 16)
            stack = 0x91fe000
            o.write(stack + loc["spell_stack"], spell)
            o.uc.reg_write(UC_X86_REG_ESP, stack)
            regs = [UC_X86_REG_EBP, UC_X86_REG_EBX, UC_X86_REG_EDI] if campaign == "original" else [UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP]
            for reg, value in zip(regs, [0 if situation == "point" else target, 0 if situation == "no_caster" else caster, world]):
                o.uc.reg_write(reg, value)
            o.slice(loc["begin"], loc["end"])
            rows.append({"index": index, "situation": situation, "notifications": list(notices),
                         "hates_caster": bool(o.ints(target + 0x244)[0] & 1)})
    o.close()
    return {"sha256": digest, "locations": {k: hex(v) for k, v in loc.items()}, "rows": rows}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", required=True)
    parser.add_argument("--astral", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = {"scope": __doc__, "campaigns": {"original": capture(args.original, "original"),
              "lost_in_astral": capture(args.astral, "lost_in_astral")}}
    Path(args.output).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"observations": sum(len(c["rows"]) for c in result["campaigns"].values())}))
