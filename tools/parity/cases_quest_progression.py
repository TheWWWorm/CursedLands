"""Quest inventory/time inputs and persistent command-stream comparisons."""
import random


def call(name, *args):
    return {"call": name, "args": list(args)}


def contracts(astral=False):
    return {"quest_program": {
        "entry": ["0x4712c0" if astral else "0x4b6760",
                  "0x46cca0" if astral else "0x4b41e0"],
        "scope": "Persistent native command dispatcher versus ScriptVM._run at consecutive 55 ms logic ticks: numeric global assignments, Sleep, SleepUntil and KillScript.",
        "stubs": ["supplied initial globals and external per-tick changes",
                  "temporary command cleanup (no temporary values in fixture)"],
        "limits": "One already-started body, not native thread-list scheduling, spawning, save serialization, reward delivery or a complete campaign.",
        "tolerances": {},
    }}


def scenarios(seed=20261020, fuzz=12):
    rows = []
    unit = {"pos": [2, 3], "hp": 100, "max_hp": 100, "dead": False, "uid": 42}
    hero, absent = {"unit": 0}, {"unit": -1}

    def predicate(name, expression, units=None, **environment):
        rows.append({"id": "quest_predicate/progression_" + name, "kind": "quest_predicate",
                     "inputs": {"expression": expression, "units": units or [], **environment}})

    for time in [0, .001, 5.999999, 6, 6.000001, 11.999999, 12, 17.999998, 18, 18.000002, 23.999998, 24]:
        predicate(f"time_{time}", call("GetWorldTime"), world_time=time)
        for threshold in [6, 12, 18]:
            predicate(f"time_{time}_before_{threshold}", call("IsLess", call("GetWorldTime"), threshold), world_time=time)
    for money in [0, 1, 99, 100, 999, 1000, 1001, 16777217, 2147483647]:
        for player in [0, 1, -1]:
            predicate(f"money_{money}_player_{player}", call("GetMoney", player), money=money)
        predicate(f"money_{money}_purchase", call("IsGreater", call("GetMoney", 0), 999), money=money)
    for items in [[], [2], [2, 3], [3, 2, 3], [99, 10, 68, 60, 37], [65535]]:
        suffix = "_".join(map(str, items)) or "empty"
        for item_id in [0, 2, 3, 5, 10, 37, 60, 68, 99, 65535]:
            predicate(f"item_bag_{suffix}_query{item_id}", call("HaveItem", 0, item_id), quest_items=items)
        predicate(f"item_bag_{suffix}_other_player", call("HaveItem", 1, 2), quest_items=items)
    for name, key in [("WasLooted", "looted"), ("IsUnitBlocked", "blocked")]:
        for dead in [False, True]:
            for enabled in [False, True]:
                predicate(f"{name}_dead{dead}_{enabled}", call(name, hero), [dict(unit, dead=dead, **{key: enabled})])
        predicate(name + "_missing", call(name, absent))
    for ground in [-16, 0, .1234567, 4.75, 1000.125]:
        predicate(f"unit_height_{ground}", call("GetZ", hero), [dict(unit, ground=ground)])
        for offset in [-3.75, 0, .000001, 12.25]:
            predicate(f"map_height_{ground}_{offset}", call("GetZ", hero),
                      [dict(unit, ground=ground, relative_z=offset, map_object=True)])
    predicate("height_missing", call("GetZ", absent))

    def trigger(name, conditions, snapshots):
        rows.append({"id": "quest_trigger/progression_" + name, "kind": "quest_trigger",
                     "inputs": {"conditions": conditions, "snapshots": snapshots}})

    trigger("night_gate", [call("IsGreater", call("GetWorldTime"), 18), call("IsEqual", call("GSGetVar", 0, {"string": "q.night"}), 1)],
            [{"units": [], "world_time": t, "variables": {"q.night": flag}}
             for t, flag in [(17, 0), (18, 1), (18.001, 1), (23.99, 1), (0, 1), (19, 2), (19, 1)]])
    trigger("item_acquire_consume_reacquire", [call("HaveItem", 0, 2), call("Not", call("IsUnitBlocked", hero))],
            [{"units": [dict(unit, blocked=blocked)], "quest_items": items}
             for items, blocked in [([], False), ([2], True), ([2], False), ([], False), ([3], False), ([2, 3], False)]])
    trigger("money_threshold", [call("IsGreater", call("GetMoney", 0), 999)],
            [{"units": [], "money": value} for value in [999, 1000, 999, 1001, 0, 5000]])
    trigger("loot_after_death", [call("IsDead", hero), call("WasLooted", hero)],
            [{"units": [dict(unit, dead=dead, looted=looted)]}
             for dead, looted in [(False, False), (True, False), (True, True), (False, True)]] + [{"units": [None]}])

    def set_value(name, value):
        return {"set": name, "value": value}

    def program(name, body, ticks=24, changes=None):
        rows.append({"id": "quest_program/" + name, "kind": "quest_program", "inputs": {
            "globals": {"phase": 0, "gate": 0, "result": 0}, "body": body,
            "observe": [call("IsGreater", {"global": "phase"}, 1), call("IsEqual", {"global": "result"}, 16777216)],
            "ticks": [{"globals": (changes or {}).get(i, {})} for i in range(ticks)],
        }})

    for delay in [-2, 0, .25, .5, .500001, 1, 1.5, 2, 2.5, 3.5, 4, 7, 12]:
        program(f"sleep_{delay}", [set_value("phase", 1), call("Sleep", delay), set_value("phase", 2),
                                   call("KillScript"), set_value("phase", 3)])
    for initial in [0, 1, -1, 2]:
        program(f"until_initial_{initial}", [set_value("gate", initial), call("SleepUntil", {"global": "gate"}),
                                             set_value("phase", 2), call("KillScript")],
                changes={3: {"gate": 1}, 7: {"gate": 0}})
    program("until_nested_then_sleep", [call("SleepUntil", call("IsGreater", {"global": "gate"}, 1)),
                                       set_value("phase", 1), call("Sleep", 2), set_value("phase", 2), call("KillScript")],
            changes={2: {"gate": 1}, 5: {"gate": 2}, 6: {"gate": 0}})
    program("killed_body_finishes_after_sleep", [call("KillScript"), set_value("phase", 1), call("Sleep", 3), set_value("phase", 2)])
    program("ordered_assignments", [set_value("phase", 1), set_value("phase", call("Add", {"global": "phase"}, 1)),
                                    set_value("result", call("Add", 16777216, {"global": "phase"})),
                                    set_value("result", call("Sub", {"global": "result"}, 2)), call("KillScript")])
    program("zero_delays_do_not_split_body", [call("Sleep", 0), call("SleepUntil", 1),
                                             call("Sleep", -1), set_value("phase", 2), call("KillScript")])
    for initial, changes in [(8, {3: {"gate": 2}}), (2, {1: {"gate": 8}}),
                             (12, {5: {"gate": 0}}), (3, {1: {"gate": 6}, 4: {"gate": 4}})]:
        program(f"dynamic_delay_{initial}", [set_value("gate", initial), call("Sleep", {"global": "gate"}),
                                             set_value("phase", 2), call("KillScript")], changes=changes)
    rng = random.Random(seed ^ 0x4712c0)
    for i in range(fuzz * 3):
        body = []
        for phase in range(1, 5):
            body.extend([call("Sleep", rng.choice([0, .5, 1, 1.5, 2, 3, 4])), set_value("phase", phase)])
        body.append(call("KillScript"))
        program(f"sleep_sequence_{i:03}", body)
    return rows
