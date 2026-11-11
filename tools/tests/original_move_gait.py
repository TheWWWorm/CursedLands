"""Capture the gait of a script MoveToPoint against a player's move order in
the original base game (bounded x86 replay in Unicorn, not a playthrough).

Executed from the original machine code, in the order of a unit's tick:
the script dispatcher's MoveToPoint (builtin 0x2, 0x4b6760), a player move
(CUnitServer::OrderMove 0x554740 with the double-click flag) or a queued
attack (order type 3, its target record left out), then
CUnitServer::TakeQueuedOrder (0x54a6e0, with SyncMoveModes 0x54a620) and the
running gate (0x548520), which stores the gait the unit moves at in unit+0x264
(3 run, 2 walk). Supplied boundaries: the actor records, an offline world
(no path planning), no load / leg refusal, a placement that fits, and stubbed
replication notifications. No outcome is computed here.

Output: tools/tests/fixtures/original_move_gait.json (script_move_gait.gd).
"""
import argparse
import hashlib
import itertools
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "parity"))
from native import Original
from native_quests import ADDRESSES, OPS, Expressions
from cases import REFERENCES

LOC = {"order_move": 0x554740, "take_order": 0x54a6e0, "run_gate": 0x548520,
       "world": 0x455940, "notify": 0x50e9f0, "set_target": 0x52a8f0,
       "refusal": 0x5241c0, "placement": 0x5ba5a0, "transform": 0x530570, "ack": 0x66d6a0}


def capture(path):
    data = Path(path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != REFERENCES["original"]["executable_sha256"]:
        raise ValueError("Executable digest does not match the qualified address map")
    o = Original(data)
    o.campaign = "original"
    world, player = o.alloc(0x100), o.alloc(0x200)
    o.write(world + 0x6c, 0)          # offline: OrderMove plans no path
    o.hook(LOC["world"], lambda: o.ret(world))
    o.hook(LOC["notify"], lambda: o.ret(cleanup=4))
    o.hook(LOC["set_target"], lambda: o.ret(cleanup=4))
    o.hook(LOC["refusal"], lambda: o.ret(0, cleanup=4))
    o.hook(LOC["placement"], lambda: o.ret(1, cleanup=4))
    o.hook(LOC["transform"], lambda: o.ret())
    o.hook(LOC["ack"], lambda: o.ret(cleanup=8))
    o.hook(ADDRESSES["original"]["cleanup"], lambda: o.ret())
    expr = Expressions(o, [{"pos": [10.0, 20.0], "hp": 10.0, "max_hp": 10.0, "dead": False}])
    expr.opcodes = OPS | {"MoveToPoint": 0x2}
    unit = expr.units[0]
    server, stats = o.alloc(0xa00), o.alloc(0x80)
    o.write(unit + 0x240, server)
    o.write(server + 0x1c, unit)
    o.write(server + 0x980, server)   # the AI brain's server back-pointer
    o.write(unit + 0x170, stats)
    o.floats(stats + 0x34, 50.0)      # mana: no hero is out of stamina

    def setup(party, gait, combat):
        o.uc.mem_write(server + 0x160, bytes(0x80))
        o.write(server + 0x168, 2, 0, 2)              # move mode 2 (standing), target 2
        o.uc.mem_write(server + 0x174, bytes([combat]))
        o.write(server + 0x190, 9)                    # no current order
        o.write(server + 0x1b4, 9)
        o.write(unit + 0x24c, player if party else 0)
        o.write(unit + 0x264, gait, gait)             # gait and requested gait

    def script_move():
        record = expr.compile({"call": "MoveToPoint", "args": [{"unit": 0}, 12.5, 30.25]})
        vector, thread, killed = o.alloc(20), o.alloc(0xc0), o.alloc(4)
        o.write(vector + 4, record, 1)
        o.write(thread, vector, 0, 0, -1, killed)
        o.run(ADDRESSES["original"]["program"], thread, [expr.context])

    def player_move(double_click):
        point = o.alloc(12)
        o.floats(point, 12.5, 30.25, 0.0)
        o.run(LOC["order_move"], server, [point, int(double_click), 0, 0x49742400])

    def attack(double_click):
        o.write(server + 0x1b4, 3)
        o.uc.mem_write(server + 0x1d4, bytes([int(double_click)]))

    rows = []
    for source, party, gait, combat in itertools.product(
            ["script", "player_click", "player_double_click", "attack", "attack_double_click"],
            [True, False], [2, 3], [0, 1]):
        setup(party, gait, combat)
        if source == "script":
            script_move()
        elif source.startswith("attack"):
            attack(source.endswith("double_click"))
        else:
            player_move(source == "player_double_click")
        order = o.ints(server + 0x1b4)[0]
        double = o.uc.mem_read(server + 0x1d4, 1)[0]
        o.run(LOC["take_order"], server)
        request = o.uc.mem_read(server + 0x175, 1)[0]
        o.run(LOC["run_gate"], server)
        rows.append({"source": source, "party": party, "gait": gait, "combat_flag": combat,
                     "queued_order": order, "double_click": double, "run_request_bits": request,
                     "moves_at_gait": o.ints(unit + 0x264)[0]})
    o.close()
    return {"sha256": digest, "locations": {k: hex(v) for k, v in LOC.items()}, "cases": rows}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = {"scope": __doc__.split("\n\n")[0], "original": capture(args.original)}
    Path(args.output).write_text(json.dumps(result, indent=1) + "\n")
    print(json.dumps({"cases": len(result["original"]["cases"])}))
