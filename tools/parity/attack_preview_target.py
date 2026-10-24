"""Replay the original attack preview up to its fresh pathfinder call.

Requires the user's unmodified English GOG 1.06 game.exe and Unicorn.
Object records and allocation/path-container boundaries are supplied. Target
position selection, its living-unit getter and the pathfinder argument assembly
execute original x86 bytes. This is not an entire world or moving-AI replay.
"""
import argparse
import hashlib
import json
from pathlib import Path

from native import Original

SHA256 = "d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8"


def replay(data, position):
    o = Original(data)
    controller, actor, owner, target, command, world = [o.alloc(0x600) for _ in range(6)]
    o.write(controller + 0x1c, actor)
    o.write(actor + 0x24c, owner)
    o.write(target, 0x73ea8c)
    o.floats(target + 0x1c, *position)
    o.write(target + 0x274, 0)  # Living target: original getter copies current pos.
    o.write(command, 3, 0, target)  # ATTACK, target object present.
    o.floats(command + 0xc, 999, 777, -1)  # Distinct fallback coordinates.
    o.write(command + 0x18, 0)  # Build a fresh preview route.
    # Empty path-container setup; no path data is consumed before the stop.
    for address in [0x545750, 0x54eac0, 0x557230, 0x5b23a0]:
        o.hook(address, lambda: o.ret())
    o.hook(0x556d10, lambda: o.ret(cleanup=4))
    o.hook(0x5c1010, lambda: o.ret(cleanup=4))  # Temporary occupancy removal.
    o.hook(0x54c800, lambda: o.ret(0, cleanup=4))  # Outside immediate reach.
    o.hook(0x455940, lambda: o.ret(world))
    o.hook(0x455950, lambda: o.ret(world))
    o.run(0x54e600, controller, (command, 0), end=0x5bb350)
    args = o.args(5)
    actual = [o.number(args[1] + n * 4) for n in range(3)]
    result = {"target": position, "command_fallback": [999, 777, -1],
              "pathfinder_target": actual, "actor_matches": args[0] == actor,
              "passed": actual == position and args[0] == actor}
    o.close()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    args = parser.parse_args()
    data = args.executable.read_bytes()
    if hashlib.sha256(data).hexdigest() != SHA256:
        parser.error("Unsupported executable hash; original bytes are required")
    rows = [replay(data, p) for p in [[20.25, 30.5, 1.0], [400.0, 88.75, 5.5], [1.5, 2.25, -0.5]]]
    print(json.dumps({"sha256": SHA256, "entry": "0x54e600", "stop": "0x5bb350",
                      "target_getter": "0x52fdf0", "rows": rows,
                      "scope": __doc__}, indent=2))
    raise SystemExit(0 if all(row["passed"] for row in rows) else 1)


if __name__ == "__main__":
    main()
