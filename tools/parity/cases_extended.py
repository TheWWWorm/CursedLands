"""Additional authored inputs. No expected outputs or game-formula substitutes."""
import math
import random

CONTRACTS = {
    "village_gate": {
        "entry": ["0x603e79", "0x603ea3", "0x60410d"],
        "scope": "Original village-talk eligibility branch versus GameUnit.village_talk_ready.",
        "stubs": ["present unit controller", "current and posted command records", "branch endpoints"],
        "limits": "Tests eligibility for all command-code pairs, not command dispatch or dialogue content.",
        "tolerances": {},
    },
    "darkness": {
        "entry": ["0x55fc50"],
        "scope": "Original simulation darkness versus GameWorld.darkness at clock boundaries.",
        "stubs": ["world hour", "zero elapsed world-clock ticks"],
        "limits": "Does not test rendered daylight, weather changes or the clock's progression.",
        "tolerances": {},
    },
    "eye_height": {
        "entry": ["0x5303a0"],
        "scope": "Original normal-figure eye position versus GameUnit.eye_z.",
        "stubs": ["ground-height getter", "dead predicate", "figure half-height", "posture"],
        "limits": "Normal grounded figures only; no flying eye approximation or occlusion query.",
        "tolerances": {},
    },
    "faction_relation": {
        "entry": ["0x4554e0"],
        "scope": "Original directional faction-bit updates versus GameWorld.set_relation.",
        "stubs": ["initial self-friend relation matrix", "no unit-notification recipient"],
        "limits": "Matrix updates only; individual hate, taming and notification side effects are separate regressions.",
        "tolerances": {},
    },
    "path_refine": {
        "entry": ["0x5c42b0", "0x5c46c0"],
        "scope": "Original turn-template builder and local path-refinement pass versus NavTurn.refine.",
        "stubs": ["CRT allocation/free", "supplied navigation costs, slopes and occupancy", "unit move-class/threshold accessors"],
        "limits": "Refines supplied routes; does not establish whole-route search or collision/spline equivalence. Heading is a supplied direction code.",
        "tolerances": {},
    },
}


def scenarios(seed, fuzz):
    rows = []
    def add(kind, name, inputs):
        rows.append({"id":kind + "/" + name, "kind":kind, "inputs":inputs})
    for current in range(12):
        for posted in range(12):
            add("village_gate", f"current_{current}_posted_{posted}", {"current":current, "posted":posted})
    for hour in [0, 1, 7.999, 8, 8.001, 12, 19.999, 20, 20.001, 21, 22, 23, 23.999, 24, 24.001, 25, 31.999, 32, 44, 48]:
        add("darkness", f"hour_{hour}", {"hour":hour})
    for half in [0.1, 0.9, 1.37, 3.0]:
        for posture in [0, 1, 2]:
            for dead in [False, True]:
                for ground in [-1.5, 2.25]:
                    add("eye_height", f"half_{half}_posture_{posture}_dead_{int(dead)}_ground_{ground}",
                        {"half":half, "posture":posture, "dead":dead, "ground":ground})
    for a, b in [(0,1),(2,3),(3,2),(0,31),(31,0),(31,31),(2,2),(15,16)]:
        for values in [[0,2,1],[2,0,2]]:
            add("faction_relation", f"sides_{a}_{b}_sequence_{''.join(map(str, values))}",
                {"actor":a, "target":b, "values":values})
    directions = [(0,0),(0,-1),(-1,-1),(-1,0),(-1,1),(0,1),(1,1),(1,0),(1,-1)]
    for first in range(1,9):
        for second in range(1,9):
            x, y = 15, 15
            points = [(x,y)]
            for direction in [first,second]:
                x += directions[direction][0]; y += directions[direction][1]
                points.append((x,y))
            facing = (first + second) % 8
            add("path_refine", f"directions_{first}_{second}", {
                "size":[32,32], "values":[14]*1024, "heights":[0]*1024, "stamps":[0]*1024,
                "slope":[1024]*2049, "cls":3, "threshold":24, "flat":False,
                "cells":[y*32+x for x,y in points], "facing":facing*math.pi/4,
                "heading":[7,6,5,4,3,2,1,8][facing], "end":[x*.5+.25,y*.5+.25]})
    rng = random.Random(seed ^ 0x91ab)
    for trial in range(fuzz):
        x, y = 8, 8
        points = [(x,y)]
        for _ in range(12):
            dx, dy = directions[rng.choice([5,6,7])]
            x += dx; y += dy; points.append((x,y))
        values = [rng.choice([3,9,12,14]) for _ in range(1024)]
        stamps = [rng.choice([0,0,0,25,50]) for _ in range(1024)]
        for x1,y1 in points: stamps[y1*32+x1] = 0
        facing = trial % 8
        add("path_refine", f"seeded_{trial:03}", {
            "size":[32,32], "values":values, "heights":[0]*1024, "stamps":stamps,
            "slope":[1024]*2049, "cls":3, "threshold":24, "flat":trial % 2 == 0,
            "cells":[y1*32+x1 for x1,y1 in points], "facing":facing*math.pi/4,
            "heading":[7,6,5,4,3,2,1,8][facing], "end":[x*.5+.125,y*.5+.25]})
    return rows
