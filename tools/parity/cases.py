"""Authored inputs shared by the two independent capture processes.

No expected results or copies of game formulas belong here. Adding an input
does not approve a behavioral difference. All floating inputs are finite.
"""
import random
from cases_extended import CONTRACTS as EXTRA_CONTRACTS, scenarios as extra_scenarios
from cases_quests import ASTRAL_REFERENCE, contracts as quest_contracts, scenarios as quest_scenarios
from cases_body import CONTRACTS as BODY_CONTRACTS, scenarios as body_scenarios

SCHEMA = 1
REFERENCE = {
    "id": "evil-islands-gog-en-d0fc0bb2",
    "campaign": "original",
    "executable_sha256": "d0fc0bb2acf45f0e59fae89e55c16a59848ffa89fb68feee9f298a680b660ad8",
    "patches": [],
    "description": "Locally verified GOG base-game game.exe. Addresses are valid only for this digest.",
}

# These are comparison contracts, not blanket approximate-equality rules.
# Exact integer/boolean/list comparisons apply everywhere else.
CONTRACTS = {
    "clock": {
        "entry": ["0x4571c1", "0x457405"],
        "scope": "Original raw timestamp loop versus GameWorld._sample_frame; simulation bodies are counters.",
        "stubs": ["OS timestamp", "application active flag", "server/client dispatch bodies", "render dispatch"],
        "limits": "No world simulation, input handling, rendering or worker debt retention is covered.",
        "tolerances": {"remainder_ms": {"abs": 0.00002}, "draw_fraction": {"abs": 0.00000012}},
    },
    "cast_rank": {
        "entry": ["0x58eaab", "0x58eb7e", "0x58ec8c"],
        "scope": "Original candidate-selection loop versus Spells._cast_pick, including dead-node removal.",
        "stubs": ["dead predicate", "removed-list-node cleanup", "candidate list and ground heights"],
        "limits": "Does not cover target acquisition, line of sight, spell application or damage. This terrain fixture requires one ground height per XY coordinate.",
        "tolerances": {},
    },
    "script_random": {
        "entry": ["0x4b41e0", "0x4667f0"],
        "scope": "Original Random opcode with supplied uint32 words versus ScriptVM.random_value.",
        "stubs": ["one-word native RNG queue"],
        "limits": "Tests the mapping, not the RNG generator or whole-game random draw order.",
        "tolerances": {},
    },
    "sight_factor": {
        "entry": ["0x5536b0", "0x553742"],
        "scope": "Original observer sight multiplier versus GameUnit.sight_factor.",
        "stubs": ["world lookup", "darkness/weather/night-sight/posture inputs"],
        "limits": "Does not establish complete stealth, terrain occlusion or AI behavior.",
        "tolerances": {},
    },
    "interaction_reach": {
        "entry": ["0x54c070"],
        "scope": "Original type-6 interaction distance versus ScriptVM._interact_reach.",
        "stubs": ["figure/use radii", "target type accessor"],
        "limits": "Does not cover route planning, inventory transfer or actual lever use.",
        "tolerances": {},
    },
    "attack": {
        "entry": ["0x553df0", "0x555bd0"],
        "scope": "Original hit decision with zero random spread versus Combat.attack_hits.",
        "stubs": ["attack/defence record accessors", "target special-case predicate (false)", "target use radius"],
        "limits": "Synthetic no-spread boundary cases. Does not cover damage, armour, backstab or RNG equivalence.",
        "tolerances": {},
    },
    "attack_chance": {
        "entry": ["0x553df0", "0x555bd0"],
        "scope": "Enumerate all supplied native roll residues versus Combat.hit_chance.",
        "stubs": ["attack/defence record accessors", "target special-case predicate (false)", "target use radius", "one-word native RNG queue"],
        "limits": "Compares the combat probability query for unaimed attacks. Does not test the remake RNG stream.",
        "tolerances": {"probability": {"abs": 1e-12}},
    },
}
CONTRACTS.update(EXTRA_CONTRACTS)
CONTRACTS.update(quest_contracts())
CONTRACTS.update(BODY_CONTRACTS)
REFERENCES = {"original": REFERENCE, "lost_in_astral": ASTRAL_REFERENCE}


def contracts_for(campaign):
    if campaign == "original":
        return CONTRACTS
    if campaign != "lost_in_astral":
        raise ValueError("Unsupported campaign reference")
    result = quest_contracts(astral=True)
    result["script_random"] = dict(CONTRACTS["script_random"], entry=["0x46cca0", "0x43ac30", "0x45e440"])
    return result


def scenarios(seed=20261020, fuzz=12):
    rng = random.Random(seed)
    rows = []

    def add(kind, name, inputs):
        rows.append({"id": f"{kind}/{name}", "kind": kind, "inputs": inputs})

    clocks = [
        ("slow_frames", 55, [[100000, True], [100016, True], [100220, True], [100490, True], [101490, True], [101491, True], [101545, True]]),
        ("inactive_resume", 55, [[100000, True], [100020, True], [100520, False], [100920, False], [100940, True], [100955, True], [101010, True]]),
        ("fast27", 27, [[200000, True], [200013, True], [200027, True], [200120, True], [200420, True], [200440, True]]),
        ("wrap_backward", 55, [[0xfffffff0, True], [0x27, True], [0x20, True], [0x57, True]]),
        ("tick_edges", 55, [[1000, True], [1054, True], [1055, True], [1109, True], [1110, True], [1111, True]]),
    ]
    for name, interval, frames in clocks:
        add("clock", name, {"interval_ms": interval, "frames": frames})
    for i in range(fuzz):
        stamp = 1000
        frames = [[stamp, True]]
        for _ in range(25):
            stamp += rng.choice([0, 1, 16, 27, 54, 55, 56, 275, 1000])
            frames.append([stamp, rng.randrange(8) != 0])
        add("clock", f"seeded_{i:03}", {"interval_ms": rng.choice([27, 55]), "frames": frames})

    rank_rows = [
        ("height_matters", [[1, 0, 20], [4, 0, 0], [3, 0, 2]], [0, 1, 2], [], -1),
        ("equal_distance_stable", [[0, 0, 5], [3, 4, 0], [-5, 0, 0]], [2, 0, 1], [], -1),
        ("explicit_target_first", [[20, 0, 3], [1, 0, 0], [3, 0, 8]], [1, 2, 0], [], 0),
        ("dead_nodes", [[0, 0, 0], [8, 0, 0], [2, 0, 0], [1, 0, 0]], [0, 1, 2, 3], [0, 3], -1),
        ("dead_target", [[0, 0, 0], [4, 0, 0], [8, 0, 20]], [0, 1, 2], [0], 0),
        ("all_dead", [[0, 0, 0], [1, 0, 0]], [0, 1], [0, 1], -1),
        ("finite_cutoff", [[1e20, 0, 0], [-1e20, 0, 0]], [0, 1], [], -1),
        ("empty", [], [], [], -1),
    ]
    for name, points, pool, dead, target in rank_rows:
        add("cast_rank", name, {"point": [0, 0, 0], "units": [{"pos": p, "dead": i in dead} for i, p in enumerate(points)], "pool": pool, "target": target})
    for i in range(fuzz):
        units, used_xy = [], set()
        while len(units) < 8:
            point = [rng.randint(-32, 32) / 4 for _ in range(3)]
            if tuple(point[:2]) in used_xy:
                continue
            used_xy.add(tuple(point[:2]))
            units.append({"pos": point, "dead": rng.randrange(5) == 0})
        pool = list(range(8))
        rng.shuffle(pool)
        add("cast_rank", f"seeded_{i:03}", {"point": [1.25, -2.5, 0.75], "units": units, "pool": pool, "target": -1})

    for maximum in [0, 1, 2, 30, -2, 0.125, 999, 1.234567, 0.0003]:
        add("script_random", f"maximum_{maximum}", {"maximum": maximum, "words": [0, 1, 0x12345678, 0x3fffffff, 0x7fffffff, 0x80000000, 0xbfffffff, 0xffffff00, 0xffffffff]})
    for i in range(fuzz):
        add("script_random", f"seeded_{i:03}", {"maximum": rng.uniform(-1000, 1000), "words": [rng.getrandbits(32) for _ in range(12)]})

    for dark in [0, 0.5, 1]:
        for night in [0, 50, 100]:
            add("sight_factor", f"dark_{dark}_night_{night}", {"dark": dark, "night": night, "weather": 0.75, "postures": [0, 1, 2, 3]})
    for i in range(fuzz):
        add("sight_factor", f"seeded_{i:03}", {"dark": rng.random(), "night": rng.uniform(0, 100), "weather": rng.uniform(0.1, 1), "postures": [0, 1, 2, 3]})

    for kind in ["loot", "steal", "lever"]:
        for own, target in [(0.01, 0.01), (0.45, 0.6624259352684), (0.45, 1.39), (2.5, 3.0)]:
            add("interaction_reach", f"{kind}_{own}_{target}", {"kind": kind, "own_figure": own, "target_figure": target, "target_use": target})

    for attack, defence in [(0, 0), (10, 10), (11, 10), (35, 10), (20, 10)]:
        for aim in [-1, 0, 1, 2]:
            add("attack", f"a{attack}_d{defence}_aim{aim}", {"attack": attack, "defence": defence, "spread": 0, "aim": aim, "distance": 1.0, "radius": 0.5, "attack_actions": 15.0, "defence_actions": 15.0})
    for distance in [0, 0.25, 1, 5, 10]:
        for attack, defence in [(40, 40), (41, 40), (20, 10)]:
            add("attack_chance", f"a{attack}_d{defence}_distance{distance}", {"attack": attack, "defence": defence, "spread": 40, "aim": -1, "distance": distance, "radius": 0.5, "attack_actions": 15.0, "defence_actions": 15.0})
    # Independent geometry/action-rate inputs, including deterministic
    # zero-spread equality. These enter both processes without expectations.
    hit_rng = random.Random(seed ^ 0x555BD0)
    for i in range(144):
        values = {"attack": hit_rng.choice([0, 1, 10, 20, 40, 41, 80]),
                  "defence": hit_rng.choice([0, 1, 10, 20, 40, 41, 80]),
                  "spread": hit_rng.choice([0, 1, 5, 40, 80]), "aim": -1,
                  "distance": hit_rng.choice([0.25, 1, 5, 10, 50]),
                  "height": hit_rng.choice([0, 0.5, 4, -4]),
                  "radius": hit_rng.choice([0.1, 0.5, 2.0]),
                  "attack_actions": hit_rng.choice([1.0, 5.0, 15.0, 50.0]),
                  "defence_actions": hit_rng.choice([1.0, 5.0, 15.0, 50.0])}
        add("attack_chance", f"geometry_actions_{i:03}", values)
    for distance in [0, 0.25, 1, 5, 10]:
        for aim in [-1, 0, 1, 2]:
            add("attack", f"zero_spread_equality_d{distance}_aim{aim}",
                {"attack": 40, "defence": 40 - (25 if aim == 0 else 10 if aim == 2 else 0),
                 "spread": 0, "aim": aim, "distance": distance, "radius": 0.5,
                 "attack_actions": 15.0, "defence_actions": 15.0})
    return rows + extra_scenarios(seed, fuzz) + quest_scenarios(seed, fuzz) + body_scenarios(seed, fuzz)


def make_inputs(seed=20261020, fuzz=12, pattern=None, campaign="original"):
    contracts = contracts_for(campaign)
    rows = scenarios(seed, fuzz)
    rows = [r for r in rows if r["kind"] in contracts]
    if pattern:
        rows = [r for r in rows if pattern in r["id"]]
    if not rows:
        raise ValueError("No scenarios selected")
    return {"schema": SCHEMA, "reference": REFERENCES[campaign], "seed": seed, "fuzz_per_family": fuzz,
            "contracts": {r["kind"]: contracts[r["kind"]] for r in rows}, "scenarios": rows}
