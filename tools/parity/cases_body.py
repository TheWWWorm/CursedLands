"""Body-state and effect lifetime inputs, without expected observations."""
import copy
import random

CONTRACTS = {
    "body_health": {
        "entry": ["0x5259b0", "0x525800", "0x525a70"],
        "scope": "Native aggregate HP, healing and HP rescaling versus GameUnit body methods after each operation.",
        "stubs": [],
        "limits": "Six supplied part records; no damage absorption, equipment, visuals, death dispatch or regeneration scheduling.",
        "tolerances": {},
    },
    "effect_lifetime": {
        "entry": ["0x6884f0"],
        "scope": "Native signed-counter decrement/keep result versus authoritative GameUnit._tick_effects membership.",
        "stubs": [],
        "limits": "One feeblemind counter; no application, stacking, client presentation, serialization or other effect modifiers.",
        "tolerances": {},
    },
}


def scenarios(seed=20261020, fuzz=12):
    rows = []
    parts = [{"type": kind, "size": size, "lethal": lethal, "state": 3,
              "cur": 128 * size, "max": 128 * size}
             for kind, size, lethal in [(0, .5, .5), (1, 1, 1), (2, .25, .125),
                                       (2, .25, .125), (3, .5, .25), (3, .5, .25)]]

    def body(name, records, operations):
        rows.append({"id": "body_health/" + name, "kind": "body_health",
                     "inputs": {"max_hp": 128, "parts": records, "operations": operations}})

    body("intact", parts, [{"kind": "query", "value": 0}])
    for state in [0, 1, 2, 3]:
        for hp in [-64, 0, 0.0009, 0.001, 16, 64]:
            records = copy.deepcopy(parts)
            records[0].update(state=state, cur=hp)
            body(f"head_state{state}_hp{hp}", records,
                 [{"kind": "heal", "value": x} for x in [0, 0.0005, 0.001, 0.001001, 1, 32, 128]])
    for i in range(6):
        records = copy.deepcopy(parts)
        records[i].update(state=2, cur=-1)
        body(f"restore_part_{i}", records, [{"kind": "heal", "value": x} for x in [1, 10, 1000]])
    records = copy.deepcopy(parts)
    for p in records: p["cur"] *= .375
    body("multiple_wounds", records, [{"kind": "heal", "value": x} for x in [1, 16, 40, 128]])
    body("rescale_sequence", records, [{"kind": "rescale", "value": x} for x in [64, 192, 80.25, 128]])
    rng = random.Random(seed ^ 0x525800)
    for i in range(fuzz):
        records = copy.deepcopy(parts)
        for p in records:
            p["state"] = rng.choice([1, 2, 3])
            p["cur"] = rng.uniform(-p["max"], p["max"])
        body(f"seeded_{i:03}", records, [{"kind": "heal", "value": rng.uniform(.01, 30)},
                                       {"kind": "rescale", "value": rng.uniform(40, 200)},
                                       {"kind": "heal", "value": 1000}])
    for counter in [-2147483648, -1, 0, 1, 2, 3, 65535, 65536, 65537, 2147483647]:
        for dead in [False, True]:
            rows.append({"id": f"effect_lifetime/counter{counter}_dead{dead}", "kind": "effect_lifetime",
                         "inputs": {"counter": counter, "dead": dead, "ticks": [0, 1, 2, 3, 4]}})
    return rows
