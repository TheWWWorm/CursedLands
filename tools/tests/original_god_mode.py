"""Capture supported GodMode(0, 0|1) behavior from both shipped executables.

Bounded x86 replay in Unicorn, not a full Windows playthrough. The command
dispatcher, damage-acceptance branch, running gate and stamina arithmetic
execute from the original machine code.
Actor records, the existing player's lookup, load/leg refusal and replicated
notifications are supplied boundaries. No original outcome is computed here.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "parity"))
from native import Original
from native_quests import ADDRESSES, OPS, Expressions
from cases import REFERENCES
from unicorn.x86_const import UC_X86_REG_EBP, UC_X86_REG_EBX, UC_X86_REG_ESI, UC_X86_REG_ESP, UC_X86_REG_EIP

LOCATIONS = {
    "original": {"run": 0x548520, "world": 0x455940, "refusal": 0x5241c0,
                 "placement": 0x5ba5a0, "update": 0x50e9f0, "transform": 0x530570,
                 "drain": 0x548263, "drain_end": 0x548392, "drain_skip": 0x548399,
                 "ack": 0x66d6a0, "damage": 0x554139, "damage_yes": 0x55416d, "damage_no": 0x55437e},
    "lost_in_astral": {"run": 0x4be220, "world": 0x432200, "refusal": 0x4a7bc0,
                       "placement": 0x5086e0, "update": 0x498bd0, "transform": 0x4b0390,
                       "drain": 0x4c4597, "drain_end": 0x4c469f, "drain_skip": 0x4c46a6,
                       "ack": 0x593fb0, "gait": 0x4bc3a0,
                       "damage": 0x4c92be, "damage_yes": 0x4c92f3, "damage_no": 0x4c94d8},
}


def capture(path, campaign):
    data = Path(path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != REFERENCES[campaign]["executable_sha256"]:
        raise ValueError("Executable digest does not match the qualified address map")
    o = Original(data)
    o.campaign = campaign
    loc = LOCATIONS[campaign]
    expr = Expressions(o, [])
    # Obtain the supplied player record through the fixture's lookup boundary.
    player = o.run(ADDRESSES[campaign]["player"], 0, [0])
    expr.opcodes = OPS | {"GodMode": 0x97}
    o.hook(ADDRESSES[campaign]["cleanup"], lambda: o.ret())

    def set_mode(value, owner=0):
        record = expr.compile({"call": "GodMode", "args": [owner, value]})
        vector, thread, killed = o.alloc(20), o.alloc(0xc0), o.alloc(4)
        o.write(vector + 4, record, 1)
        o.write(thread, vector, 0, 0, -1, killed)
        o.run(ADDRESSES[campaign]["program"], thread, [expr.context])
        return o.uc.mem_read(player + 0x108, 1)[0]

    setter = [{"owner": owner, "mode": mode, "stored": set_mode(mode, owner)}
              for owner, mode in [(0, 1), (0, 0), (0, 1), (7, 0), (0, 0)]]
    actor, unit, stats, world = o.alloc(0x300), o.alloc(0x400), o.alloc(0x80), o.alloc(0x400)
    o.write(actor + 0x1c, unit)
    o.write(unit + 0x170, stats)
    o.write(unit + 0x24c, player)
    o.write(unit + 0x278, 1)
    refusal = [0]
    refusal_calls = [0]
    def supplied_refusal():
        refusal_calls[0] += 1
        o.ret(refusal[0], cleanup=4)
    o.hook(loc["world"], lambda: o.ret(world))
    o.hook(loc["refusal"], supplied_refusal)
    o.hook(loc["placement"], lambda: o.ret(1, cleanup=4))
    o.hook(loc["update"], lambda: o.ret(cleanup=4))
    o.hook(loc["transform"], lambda: o.ret())
    o.hook(loc["ack"], lambda: o.ret(cleanup=8))
    if "gait" in loc:
        o.hook(loc["gait"], lambda: o.ret(cleanup=4))
    movement = []
    for mode in [0, 1]:
        set_mode(mode)
        for mana in [0.0, 0.5, 50.0]:
            for blocked in [0, 1, 2]:
                refusal[0] = blocked
                o.write(actor + 0x168, 2, 0, 2)
                o.uc.mem_write(actor + 0x175, b"\1")
                o.floats(stats + 0x34, mana, 150.0)
                before = refusal_calls[0]
                o.run(loc["run"], actor)
                if refusal_calls[0] != before + 1:
                    raise AssertionError("Native running gate did not use the declared refusal boundary")
                allowed = bool(o.uc.mem_read(actor + 0x16d, 1)[0])
                # Observe one already-running tick separately from admission.
                o.write(actor + 0x168, 2, 0, 2)
                o.uc.mem_write(actor + 0x16d, b"\1")
                o.uc.mem_write(actor + 0x175, b"\1")
                o.floats(stats + 0x34, mana, 150.0)
                o.uc.reg_write(UC_X86_REG_ESI, actor)
                o.uc.reg_write(UC_X86_REG_EBP, 0)
                o.uc.reg_write(UC_X86_REG_ESP, 0x91fe000)
                o.slice(loc["drain"], loc["drain_end"], [loc["drain_skip"]])
                movement.append({"mode": mode, "mana": mana, "refusal": blocked,
                                 "can_run": allowed, "after_running_tick": o.number(stats + 0x34)})
    damage = []
    o.hook(loc["damage_no"], o.uc.emu_stop)
    for owned in [False, True]:
        o.write(unit + 0x24c, player if owned else 0)
        for mode in [0, 1]:
            set_mode(mode)
            o.uc.reg_write(UC_X86_REG_ESI, actor)
            o.uc.reg_write(UC_X86_REG_EBP, 0x91fd000)
            o.uc.reg_write(UC_X86_REG_ESP, 0x91fe000)
            o.write(0x91fd000 + 0x10, 0)
            o.write(0x91fe000 + 0x48, 0)
            o.slice(loc["damage"], loc["damage_yes"], [loc["damage_no"]])
            damage.append({"owned": owned, "mode": mode,
                           "accepts_damage": o.uc.reg_read(UC_X86_REG_EIP) == loc["damage_yes"]})
    o.close()
    return {"sha256": digest, "locations": {k: hex(v) for k, v in loc.items()},
            "setter": setter, "movement": movement, "damage": damage}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", required=True)
    parser.add_argument("--astral", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = {"scope": __doc__, "campaigns": {
        "original": capture(args.original, "original"),
        "lost_in_astral": capture(args.astral, "lost_in_astral"),
    }}
    Path(args.output).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"campaigns": list(result["campaigns"]), "observations": 54}))
