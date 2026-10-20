"""Quest-condition inputs, shared without expected answers or formula ports."""
import random

ASTRAL_REFERENCE = {
    "id": "lost-in-astral-f04a305b",
    "campaign": "lost_in_astral",
    "executable_sha256": "f04a305b77c84ea29c18ad2996d23072ccef1c0c46876c9b93bae4ce9351d1ff",
    "patches": [],
    "description": "Locally inspected Lost in Astral game.exe; separately qualified native addresses.",
}


def contracts(astral=False):
    evaluator, gate, nested = (["0x46cca0", "0x473b50", "0x46ee90"] if astral
                               else ["0x4b41e0", "0x4bb520", "0x4b4030"])
    return {
        "quest_predicate": {
            "entry": [evaluator, nested, "0x431d80" if astral else "0x460af0",
                      * (["0x4663e0", "0x466440", "0x464390", "0x46bc30"] if astral
                         else ["0x4b1ed0", "0x4b2070", "0x4bce10"])],
            "scope": "Native numeric quest expressions, nested calls, group quantifiers and constructed areas versus ScriptVM._eval.",
            "stubs": ["supplied unit position/HP/identity/lever records", "unit dead-state/type accessors",
                      "player-zero lookup", "single-player mode", "temporary string allocation/destruction",
                      "CRT thread-local single-byte locale", "supplied group membership", "fixture actor reference release",
                      "preallocated area containers, including empty missing IDs"],
            "limits": "Bounded expressions and ASCII keys/strings only; no quest rewards, inventory, script scheduler or campaign completion.",
            "tolerances": {},
        },
        "quest_trigger": {
            "entry": [gate, evaluator, nested,
                      * (["0x4663e0", "0x466440", "0x464390", "0x46bc30"] if astral
                         else ["0x4b1ed0", "0x4b2070", "0x4bce10"])],
            "scope": "Native ordered condition-list gate versus ScriptVM._run at supplied polls, recording body dispatch.",
            "stubs": ["supplied unit position/HP/identity/lever records", "unit dead-state/type accessors",
                      "player-zero lookup", "single-player mode", "temporary string allocation/destruction",
                      "CRT thread-local single-byte locale",
                      "supplied group membership", "fixture actor reference release",
                      "preallocated area containers, including empty missing IDs",
                      "native temporary-expression cleanup", "trigger body dispatch recorded as an event"],
            "limits": "Repeated independent condition polls; no sleep scheduling, one-shot disposal, quest rewards or full campaign playthrough.",
            "tolerances": {},
        },
    }


def call(name, *args):
    return {"call": name, "args": list(args)}


def scenarios(seed=20261020, fuzz=12):
    rows = []
    hero, other, absent = {"unit": 0}, {"unit": 1}, {"unit": -1}
    unit = {"pos": [0, 0], "hp": 10, "max_hp": 20, "dead": False, "uid": 1}

    def add(name, expression, units=None):
        rows.append({"id": "quest_predicate/" + name, "kind": "quest_predicate",
                     "inputs": {"expression": expression, "units": [unit.copy()] if units is None else units}})

    for name in ["IsEqual", "IsLess", "IsGreater"]:
        for i, (a, b) in enumerate([(0, 0), (-1, 0), (2, 1), (1, 1.000001),
                                    (0.5, 0.50000006), (1000.25, 1000.2505),
                                    (16777216, 16777217), (-0.0, 0.0)]):
            add(f"{name}_{i}", call(name, a, b))
    for value in [0, -0.0, 1, -1, 0.000001]:
        add("Not_" + str(value), call("Not", value))
    for op in ["Add", "Sub", "Mul", "Div"]:
        for i, (a, b) in enumerate([(0.1, 0.2), (1.234567, 3.25), (-10, 4), (16777216, 1)]):
            add(f"{op}_{i}", call(op, a, b))
    add("nested_rounded_sum", call("IsEqual", call("Add", 16777216, 1), 16777216))
    add("nested_fraction_sum", call("IsEqual", call("Add", 0.1, 0.2), 0.3))
    add("nested_division", call("IsLess", call("Div", 1, 3), 0.33333334))
    add("nested_zero", call("Not", call("Sub", 1, 1)))
    for i, (left, right) in enumerate([("", ""), ("quest", "quest"), ("Quest", "quest"),
                                     ("q.gz1h.q1h", "q.gz1h.q1h.1"), ("Gate", "GATE")]):
        add(f"string_{i}", call("IsEqualString", {"string": left}, {"string": right}))
    for key in ["q.gz1h.q1h", "q.gz1h.q1h.1", "missing", "Q.GZ1H.Q1H", ""]:
        add("flag_" + (key or "empty"), call("GSGetVar", 0, {"string": key}), [])
        rows[-1]["inputs"]["variables"] = {"q.gz1h.q1h": 2, "q.gz1h.q1h.1": 1, "unrelated": -3}
    for state in [-1, 0, 1, 2, 10]:
        add("lever_" + str(state), call("GetLeverState", hero), [dict(unit, lever=state)])
    add("lever_null", call("GetLeverState", absent), [])
    for x, y in [(-1, 5), (0, 0), (10, 10), (10, 5), (5, 10), (0, 5),
                 (5, 0), (5, 5), (10.000001, 5), (9.999999, 5)]:
        add(f"rectangle_{x}_{y}", call("UnitInSquare", hero, 0, 0, 10, 10),
            [dict(unit, pos=[x, y])])
    add("rectangle_reversed", call("UnitInSquare", hero, 10, 10, 0, 0), [dict(unit, pos=[5, 5])])
    add("rectangle_degenerate", call("UnitInSquare", hero, 0, 0, 0, 0))
    add("rectangle_null", call("UnitInSquare", absent, 0, 0, 10, 10), [])
    for name in ["HP", "MaxHP", "GetX", "GetY", "GetObjectID", "IsAlive", "IsDead"]:
        for present, dead in [(True, False), (True, True), (False, False)]:
            add(f"{name}_{present}_{dead}", call(name, hero if present else absent),
                [dict(unit, dead=dead, hp=0 if dead else 10, pos=[1.25, -2.5])] if present else [])
    for point in [[3, 4], [0.1, 0.2], [1000.25, -512.75]]:
        add("distance_point_" + str(point), call("DistanceUnitPoint", hero, *point))
        add("distance_units_" + str(point), call("DistanceUnitUnit", hero, other),
            [unit.copy(), dict(unit, pos=point, uid=2)])
    add("distance_missing_unit", call("DistanceUnitUnit", hero, absent))
    add("distance_missing_point", call("DistanceUnitPoint", absent, 0, 0), [])
    add("missing_distance_large_threshold", call("IsLess", call("DistanceUnitPoint", absent, 0, 0), 100000), [])

    rng = random.Random(seed ^ 0x4BB520)
    for i in range(fuzz):
        a, b, c = [rng.uniform(-100, 100) for _ in range(3)]
        add(f"nested_seeded_{i:03}", call("IsGreater", call("Sub", call("Mul", a, b), c), 0))

    def trigger(name, conditions, snapshots):
        rows.append({"id": "quest_trigger/" + name, "kind": "quest_trigger",
                     "inputs": {"conditions": conditions, "snapshots": snapshots}})

    positions = [[-1, 5], [0, 5], [5, 5], [10, 5], [11, 5], [5, 10], [5, 5]]
    trigger("enter_leave_reenter_rectangle", [call("UnitInSquare", hero, 0, 0, 10, 10)],
            [{"units": [dict(unit, pos=p)]} for p in positions])
    trigger("distance_and_alive", [call("IsAlive", hero), call("IsLess", call("DistanceUnitPoint", hero, 0, 0), 5)],
            [{"units": [dict(unit, pos=p, dead=dead, hp=0 if dead else 10)]}
             for p, dead in [([3, 4], False), ([2.99, 4], False), ([0, 0], True), ([0, 0], False), ([6, 0], False)]])
    trigger("death_then_missing_actor", [call("IsDead", hero)],
            [{"units": [dict(unit, dead=d, hp=0 if d else 10)]} for d in [False, True, True]] + [{"units": [None]}])
    trigger("hp_threshold", [call("IsLess", call("HP", hero), call("Div", call("MaxHP", hero), 2))],
            [{"units": [dict(unit, hp=hp)]} for hp in [20, 10.000001, 10, 9.999999, 1, 15]])
    trigger("nested_equality", [call("IsEqual", call("Add", call("HP", hero), 0.000001), 10)],
            [{"units": [dict(unit, hp=hp)]} for hp in [9, 10, 10.000001, 0, 10]])
    trigger("empty_conditions", [], [{"units": []}, {"units": []}])
    trigger("short_circuit_false", [call("IsLess", 2, 1), call("IsEqual", 1, 1)],
            [{"units": []}, {"units": []}])
    trigger("all_conditions_true", [call("Not", 0), call("IsGreater", 2, 1), call("IsEqual", 1, 1)],
            [{"units": []}, {"units": []}])
    trigger("quest_flag_progression", [call("IsEqual", call("GSGetVar", 0, {"string": "q.test"}), 2)],
            [{"units": [], "variables": v} for v in [{}, {"q.test": 1}, {"q.test": 2},
                                                    {"q.test": 2}, {"q.test": 0}]])
    trigger("lever_and_flag", [call("IsEqual", call("GetLeverState", hero), 1),
                              call("IsEqual", call("GSGetVar", 0, {"string": "q.test"}), 2)],
            [{"units": [dict(unit, lever=lever)], "variables": {"q.test": flag}}
             for lever, flag in [(0, 0), (1, 0), (1, 2), (0, 2), (1, 2)]])
    group, iterator = {"group": "guards"}, {"iterator": "guard"}
    members = [dict(unit, uid=i + 10, hp=10 + i, pos=[i * 3, i * 4], dead=i == 1) for i in range(3)]
    for indices in [[], [0], [1], [0, 1], [1, 0], [2, 1, 0]]:
        suffix = "_".join(map(str, indices)) or "empty"
        expressions = [
            ("size", call("GroupSize", group)),
            ("has_first", call("GroupHas", group, hero)),
            ("has_null", call("GroupHas", group, absent)),
        ]
        for quantifier in ["Any", "Every"]:
            for name, predicate in [
                ("alive", call("IsAlive", iterator)), ("dead", call("IsDead", iterator)),
                ("low_hp", call("IsLess", call("HP", iterator), 11)),
                ("in_rect", call("UnitInSquare", iterator, 0, 0, 3, 4)),
                ("near", call("IsLess", call("DistanceUnitPoint", iterator, 0, 0), 5)),
                ("constant_zero", 0), ("constant_one", 1), ("constant_two", 2),
            ]:
                expressions.append((quantifier + "_" + name, call(quantifier, iterator, group, predicate)))
        for name, expression in expressions:
            add(f"group_{suffix}_{name}", expression, members)
            rows[-1]["inputs"]["groups"] = {"guards": indices}
    group_polls = [
        {"units": members, "groups": {"guards": []}},
        {"units": members, "groups": {"guards": [0, 1, 2]}},
        {"units": [dict(u, dead=True, hp=0) for u in members], "groups": {"guards": [0, 1, 2]}},
        {"units": members, "groups": {"guards": [1]}},
        {"units": members, "groups": {"guards": [0]}},
    ]
    trigger("group_all_dead", [call("Not", call("Any", iterator, group, call("IsAlive", iterator)))], group_polls)
    trigger("group_nonempty_all_dead", [call("IsGreater", call("GroupSize", group), 0),
                                      call("Every", iterator, group, call("IsDead", iterator))], group_polls)
    trigger("group_iterator_after_short_circuit", [call("Any", iterator, group, call("IsDead", iterator)),
                                                call("IsEqual", call("GetObjectID", iterator), 11)], group_polls)
    for i in range(fuzz * 4):
        # Raw arithmetic observations and cancellation expose rounding that
        # sign-only random predicates can miss.
        a, b, c = [rng.uniform(-1000, 1000) for _ in range(3)]
        add(f"arithmetic_chain_{i:03}", call("Sub", call("Add", call("Mul", a, b), c), call("Mul", a, b)))
        point = [rng.uniform(-10000, 10000) for _ in range(2)]
        add(f"distance_translated_{i:03}", call("DistanceUnitPoint", hero, *point),
            [dict(unit, pos=[rng.uniform(-10000, 10000), rng.uniform(-10000, 10000)])])
        add(f"distance_translated_units_{i:03}", call("DistanceUnitUnit", hero, other),
            [rows[-1]["inputs"]["units"][0], dict(unit, pos=point, uid=2)])
    shapes = [
        ("rectangle", [{"rect": [0, 0, 10, 10]}]),
        ("reversed_x", [{"rect": [10, 0, 0, 10]}]),
        ("reversed_y", [{"rect": [0, 10, 10, 0]}]),
        ("point", [{"rect": [0, 0, 0, 0]}]),
        ("circle", [{"circle": [0, 0, 5]}]),
        ("negative_circle", [{"circle": [0, 0, -5]}]),
        ("zero_circle", [{"circle": [0, 0, 0]}]),
        ("union", [{"rect": [20, 20, 30, 30]}, {"circle": [0, 0, 5]}]),
        ("empty", []),
    ]
    for name, records in shapes:
        for i, point in enumerate([[0, 0], [10, 10], [10, 5], [5, 10], [3, 4],
                                    [3, 3.999999], [0, -5], [0, -4.999999], [25, 25], [30, 30]]):
            add(f"area_{name}_{i}", call("IsInArea", 1, *point), [])
            rows[-1]["inputs"]["areas"] = [{"id": 1, "shapes": records}]
    add("area_missing", call("IsInArea", 2, 0, 0), [])
    rows[-1]["inputs"]["areas"] = [{"id": 1, "shapes": [{"rect": [-1, -1, 1, 1]}]}]
    for i in range(fuzz * 2):
        x1, y1 = [rng.uniform(-1000, 1000) for _ in range(2)]
        x2, y2 = [rng.uniform(-1000, 1000) for _ in range(2)]
        for edge, point in enumerate([[x1, y1], [x2, y2]]):
            add(f"area_fractional_corner_{i:03}_{edge}", call("IsInArea", 1, *point), [])
            rows[-1]["inputs"]["areas"] = [{"id": 1, "shapes": [{"rect": [x1, y1, x2, y2]}]}]
    trigger("area_enter_exit_reenter", [call("IsInArea", 1, call("GetX", hero), call("GetY", hero))],
            [{"units": [dict(unit, pos=point)], "areas": [{"id": 1, "shapes": [{"rect": [0, 0, 10, 10]}]}]}
             for point in [[-1, 5], [0, 5], [10, 5], [10.00001, 5], [5, 10], [5, 5]]])
    return rows
