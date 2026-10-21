"""NPC behaviour commands issued by quest scripts (inputs only, no expectations).

Three kinds share one fixture: units whose logic objects the original builds
with its own constructor, a supplied .mob diplomacy matrix and .mob logic
descriptor, supplied [Logic] GuardRadius/GuardStayTime values and a supplied
world tick counter.

- npc_motivation: UM*/Guard/Sentry/Idle/Follow/BlockUnit/ResetTarget and the
  aggression no-ops; one observation of the AI record after every command.
- npc_diplomacy: SetDiplomacy/SetPlayer/SetEnemy; GetDiplomacy pairs and
  IsEnemy over sides 0..31 after every command.
- npc_alarm: InvokeAlarm and the AI tick's alarm countdown; IsAlarm,
  AlarmTime and AlarmPosX/Y after every command or tick.
"""
import random

STEP_COUNTS = {"npc_motivation": "commands", "npc_diplomacy": "commands", "npc_alarm": "steps"}

# Sentinel [Logic] values: a stored value equal to one is reported as that key.
CONFIG = {"GuardRadius": 1234.5, "GuardStayTime": 2345.5}

MOTIVATION_COMMANDS = ["UMClear", "UMSentry", "UMGuard", "UMGuardEx", "UMPatrol", "UMPatrolClear",
                       "UMPatrolAddPoint", "UMPatrolAddPointLook", "UMStandard", "UMAggression",
                       "UMRevenge", "UMSuspection", "UMCorpseWatcher", "UMPlayer", "BlockUnit",
                       "Guard", "Idle", "Follow", "SetSpellAggression", "Sentry",
                       "SetPlayerAggression", "UMFear", "UMAg", "UMFollow", "ResetTarget"]
TYPES = ["guard", "patrol", "sentry", "suspection", "aggression", "corpse_watcher", "player",
         "fear", "tamed", "follow"]


def contracts(campaign):
    if campaign != "original":
        return {}
    common = ["CRT operator new (bump heap, zero-filled) and operator delete (no-op)",
              "native temporary-expression cleanup", "fixture actor reference release (Expressions vtable +0x10)",
              "unit type/dead accessors (Expressions vtable)", "unit<->logic<->AI attachment links",
              "unit constructor defaults for +0x244/+0x248/+0x250",
              "supplied .mob diplomacy matrix", "supplied world unit container (world+0x40)",
              "player-zero lookup", "single-player mode"]
    return {
        "npc_motivation": {
            "entry": ["0x4b6760", "0x545580", "0x5d5f60", "0x5d4df0", "0x5d6230", "0x5d64e0",
                      "0x5d6140", "0x5d5e30", "0x5d12b0", "0x5d7790", "0x5d7e40", "0x5d7c30", "0x5d6630"],
            "scope": "AI motivation list, AI state, script target, blocked flag and side after quest "
                     "commands 0x24-0x34, 0x3b, 0x42, 0x94, 0xa4, 0xc7, 0xc8, 0xca and 0xe8, versus ScriptVM._run "
                     "with the remake record mapped to the native list.",
            "stubs": common + ["supplied [Logic] GuardRadius/GuardStayTime sentinels at 0x7c53fc/0x7c53ec",
                               "supplied .mob logic descriptor (ResetTarget)",
                               "AI weapon/spell option rebuild 0x5ceed0 (unit inventory)"],
            "limits": "Motivation records only: no AI tick, priority selection, movement or combat. "
                      "List order is compared as type order (at most one motivation per type).",
            "tolerances": {},
        },
        "npc_diplomacy": {
            "entry": ["0x4b6760", "0x4554e0", "0x455660", "0x455630", "0x52e970", "0x52e940",
                      "0x530120", "0x4b41e0"],
            "scope": "GetDiplomacy (0x60) pairs and IsEnemy (0x61) masks after SetDiplomacy, SetPlayer and "
                     "SetEnemy versus ScriptVM._call and GameWorld.diplomacy.",
            "stubs": common,
            "limits": "Diplomacy and unit hostility masks only; no hate lists, notifications or network sync.",
            "tolerances": {},
        },
        "npc_alarm": {
            "entry": ["0x4b6760", "0x593fc0", "0x5d53b0..0x5d5413", "0x4b41e0"],
            "scope": "World alarm table (IsAlarm 0x67, AlarmTime 0x8b, AlarmPosX/Y 0x8c/0x8d) after "
                     "InvokeAlarm and the AI tick's alarm countdown/raise versus UnitAI.invoke_alarm/tick.",
            "stubs": common + ["supplied world tick counter (world+0x64), advanced once per tick step",
                               "supplied descriptor alarm fields: alerted flag, raise index, countdown"],
            "limits": "Alarm table and countdown only; no descriptor switching of other units, "
                      "alert detection or the rest of the AI tick.",
            "tolerances": {},
        },
    }


def u(i):
    return {"unit": i}


def call(name, *args):
    return {"call": name, "args": list(args)}


UNIT = {"pos": [1, 2], "hp": 10, "max_hp": 10, "dead": False, "uid": 1}


def actors(**actor):
    """Actor 0, an independent target 1, and a dead unit 2."""
    return [dict(UNIT, **actor), dict(UNIT, uid=2, pos=[5, 5]), dict(UNIT, uid=3, pos=[9, 9], dead=True, hp=0)]


def scenarios(seed=20261020, fuzz=12):
    rows = []

    def motivation(name, commands, units=None, observe=(0, 1)):
        rows.append({"id": "npc_motivation/" + name, "kind": "npc_motivation",
                     "inputs": {"units": units or actors(), "observe": list(observe),
                                "config": dict(CONFIG), "commands": commands}})

    a, b, dead, missing = u(0), u(1), u(2), u(-1)
    # UMSentry (128 authored uses): fresh, values, replacement of calm motivations.
    for i, (x, y) in enumerate([(3.25, -4), (0, 0), (1000.25, -512.75), (0.1, 0.2), (-0.0, 16777217)]):
        motivation(f"UMSentry_point_{i}", [call("UMSentry", a, x, y)])
    motivation("UMSentry_twice", [call("UMSentry", a, 1, 2), call("UMSentry", a, 3, 4)])
    motivation("UMSentry_replaces_guard", [call("UMGuard", a, 7, 8, 5), call("UMSentry", a, 1, 2)])
    motivation("UMSentry_replaces_follow", [call("UMFollow", a, b), call("UMSentry", a, 1, 2)])
    motivation("UMSentry_keeps_noncalm", [call("UMStandard", a), call("UMFear", a, 1), call("UMSentry", a, 1, 2)])
    motivation("UMSentry_missing_actor", [call("UMSentry", missing, 1, 2)])
    motivation("UMSentry_dead_actor", [call("UMSentry", dead, 1, 2)], observe=(2,))
    # Idle (100), UMPlayer (74), UMClear (27).
    motivation("Idle_fresh", [call("Idle", a)])
    motivation("Idle_after_standard_follow", [call("UMSentry", a, 1, 2), call("UMStandard", a), call("Follow", a, b), call("Idle", a)])
    motivation("Idle_after_player", [call("UMPlayer", a), call("Idle", a)])
    motivation("Idle_missing", [call("Idle", missing)])
    motivation("UMPlayer_fresh", [call("UMPlayer", a)])
    motivation("UMPlayer_after_standard", [call("UMSentry", a, 1, 2), call("UMStandard", a), call("UMPlayer", a)])
    motivation("UMPlayer_after_follow", [call("Follow", a, b), call("UMPlayer", a)])
    motivation("UMPlayer_then_UMSentry", [call("UMPlayer", a), call("UMSentry", a, 4, 4)])
    motivation("UMPlayer_then_UMStandard", [call("UMPlayer", a), call("UMStandard", a)])
    motivation("UMClear_after_sentry_standard", [call("UMSentry", a, 1, 2), call("UMStandard", a), call("UMClear", a)])
    motivation("UMClear_keeps_follow_state", [call("Follow", a, b), call("UMClear", a)])
    motivation("UMClear_then_UMFear", [call("UMClear", a), call("UMFear", a, 0)])
    # Guard (19), UMGuard (8), UMGuardEx.
    for i, radius in enumerate([9, -1, 0, -0.0, 0.5, 1e6]):
        motivation(f"Guard_radius_{i}", [call("Guard", a, 1, 2, radius)])
    motivation("Guard_after_fear1_follow", [call("UMFear", a, 1), call("Follow", a, b), call("Guard", a, 3, 4, 6)])
    for i, radius in enumerate([5, -1, 0, -0.0]):
        motivation(f"UMGuard_radius_{i}", [call("UMGuard", a, 7, 8, radius)])
    for i, (radius, stay) in enumerate([(3, 4), (-1, 4), (3, -1), (0, 0), (-0.0, -0.0), (-5, -5)]):
        motivation(f"UMGuardEx_{i}", [call("UMGuardEx", a, 7, 8, radius, stay)])
    motivation("UMGuard_replaces_sentry", [call("UMSentry", a, 1, 2), call("UMGuard", a, 7, 8, 5)])
    # Sentry (7): full reset like Guard.
    motivation("Sentry_fresh", [call("Sentry", a, 1, 2)])
    motivation("Sentry_after_fear1", [call("UMFear", a, 1), call("Sentry", a, 1, 2)])
    motivation("Sentry_after_follow", [call("Follow", a, b), call("Sentry", a, 1, 2)])
    motivation("Sentry_after_player", [call("UMPlayer", a), call("Sentry", a, 1, 2)])
    # UMStandard (12), UMAggression (7), UMRevenge (3), UMSuspection, UMCorpseWatcher.
    motivation("UMStandard_fresh", [call("UMStandard", a)])
    motivation("UMStandard_twice", [call("UMStandard", a), call("UMStandard", a)])
    motivation("UMStandard_after_revenge", [call("UMRevenge", a), call("UMStandard", a)])
    motivation("UMAggression_fresh", [call("UMAggression", a)])
    motivation("UMRevenge_fresh", [call("UMRevenge", a)])
    motivation("UMRevenge_then_UMAggression", [call("UMRevenge", a), call("UMAggression", a)])
    motivation("UMSuspection_fresh", [call("UMSuspection", a)])
    motivation("UMCorpseWatcher_fresh", [call("UMCorpseWatcher", a)])
    motivation("UMSuspection_CorpseWatcher_after_sentry", [call("UMSentry", a, 1, 2), call("UMSuspection", a), call("UMCorpseWatcher", a)])
    # UMFear (6), UMAg.
    for i, flag in enumerate([1, 0, 0.5, -1, -0.0]):
        motivation(f"UMFear_flag_{i}", [call("UMFear", a, flag)])
    motivation("UMFear_replaces_fear", [call("UMFear", a, 1), call("UMFear", a, 0)])
    for i, mode in enumerate([0, 1, 2, 3, 4, 2.5, 1.5, -1]):
        motivation(f"UMAg_mode_{i}", [call("UMAg", a, mode)])
        motivation(f"UMAg_after_standard_{i}", [call("UMSentry", a, 1, 2), call("UMStandard", a), call("UMFear", a, 1), call("UMAg", a, mode)])
    # UMFollow (6), Follow (4).
    motivation("UMFollow_target", [call("UMFollow", a, b)])
    motivation("UMFollow_missing_target", [call("UMFollow", a, missing)])
    motivation("UMFollow_self", [call("UMFollow", a, a)])
    motivation("UMFollow_dead_target", [call("UMFollow", a, dead)])
    motivation("UMFollow_after_sentry", [call("UMSentry", a, 1, 2), call("UMFollow", a, b)])
    motivation("Follow_target", [call("Follow", a, b)])
    motivation("Follow_missing_target", [call("Follow", a, missing)])
    motivation("Follow_self", [call("Follow", a, a)])
    motivation("Follow_dead_target", [call("Follow", a, dead)])
    motivation("Follow_by_dead", [call("Follow", dead, b)], observe=(2, 1))
    motivation("Follow_retarget", [call("Follow", a, b), call("Follow", a, dead)])
    motivation("Follow_then_Idle", [call("Follow", a, b), call("Idle", a)])
    # Patrol commands.
    motivation("UMPatrol_fresh", [call("UMPatrol", a)])
    motivation("UMPatrol_points", [call("UMPatrol", a), call("UMPatrolAddPoint", a, 1.3, 2.2),
                                   call("UMPatrolAddPoint", a, 0.24, -0.26), call("UMPatrolAddPoint", a, 1000.3, 0.75)])
    motivation("UMPatrol_looks", [call("UMPatrol", a), call("UMPatrolAddPoint", a, 1, 2),
                                  call("UMPatrolAddPointLook", a, 1, 2, 3), call("UMPatrolAddPointLook", a, 4, 5, 6),
                                  call("UMPatrolAddPoint", a, 3, 4), call("UMPatrolAddPointLook", a, 0.5, 0, 1)])
    motivation("UMPatrol_clear", [call("UMPatrol", a), call("UMPatrolAddPoint", a, 1, 2), call("UMPatrolClear", a)])
    motivation("UMPatrolAddPoint_without_patrol", [call("UMPatrolAddPoint", a, 1, 2), call("UMPatrolAddPointLook", a, 1, 2, 3)])
    motivation("UMPatrolAddPointLook_without_point", [call("UMPatrol", a), call("UMPatrolAddPointLook", a, 1, 2, 3)])
    motivation("UMPatrol_replaces_sentry", [call("UMSentry", a, 1, 2), call("UMPatrol", a)])
    # BlockUnit (2) and aggression no-ops.
    for i, flag in enumerate([1, 0, -0.0, 0.5, -1]):
        # Set first so clearing values are observable.
        motivation(f"BlockUnit_{i}", [call("BlockUnit", a, 1), call("BlockUnit", a, flag)])
    motivation("BlockUnit_dead", [call("BlockUnit", dead, 1)], observe=(2,))
    motivation("BlockUnit_missing", [call("BlockUnit", missing, 1)])
    motivation("SetSpellAggression_noop", [call("UMStandard", a), call("SetSpellAggression", a, 1)])
    motivation("SetPlayerAggression_noop", [call("UMStandard", a), call("SetPlayerAggression", 0, 1)])
    # ResetTarget (1): rebuild from the unit's .mob logic descriptor.
    for i, descriptor in enumerate([
        {"model": 3, "point": [4, 5, 0], "aggression": 0},
        {"model": 1, "point": [4, 5, 0], "radius": 6, "aggression": 1},
        {"model": 1, "point": [4, 5, 0], "radius": -1, "aggression": 2},
        {"model": 0, "aggression": 0},
        {"model": 4, "aggression": 3},
        {"model": 3, "point": [-2, 7.5, 0], "aggression": 3},
    ]):
        motivation(f"ResetTarget_descriptor_{i}",
                   [call("UMClear", a), call("ResetTarget", a), call("Follow", a, b), call("ResetTarget", a)],
                   units=actors(descriptor=descriptor))
    # Seeded command sequences.
    rng = random.Random(seed ^ 0x4B6760)

    def random_command():
        name = rng.choice(MOTIVATION_COMMANDS)
        point = [round(rng.uniform(-50, 50), 2) for _ in range(2)]
        if name in ("UMSentry", "Sentry", "UMPatrolAddPoint"):
            return call(name, a, *point)
        if name in ("UMGuard", "Guard"):
            return call(name, a, *point, rng.choice([-1, 0, 3.5, 12]))
        if name == "UMGuardEx":
            return call(name, a, *point, rng.choice([-1, 2]), rng.choice([-1, 0, 7]))
        if name == "UMPatrolAddPointLook":
            return call(name, a, *[round(rng.uniform(-3, 3), 2) for _ in range(3)])
        if name in ("UMFollow", "Follow"):
            return call(name, a, rng.choice([b, dead, missing]))
        if name in ("UMFear", "BlockUnit", "SetSpellAggression"):
            return call(name, a, rng.choice([0, 1]))
        if name == "UMAg":
            return call(name, a, rng.choice([0, 1, 2, 3]))
        if name == "SetPlayerAggression":
            return call(name, 0, 1)
        return call(name, a)

    for i in range(fuzz * 2):
        descriptor = {"model": rng.choice([0, 1, 3, 4]), "point": [rng.randint(-9, 9), rng.randint(-9, 9), 0],
                      "radius": rng.choice([-1, 4]), "aggression": rng.randint(0, 3)}
        motivation(f"seeded_{i:03}", [random_command() for _ in range(rng.randint(3, 8))],
                   units=actors(descriptor=descriptor))

    # ---- diplomacy
    base_matrix = [[i, i, 0] for i in range(8)] + [[1, 2, 2], [2, 1, 2], [3, 4, 0], [4, 3, 0]]
    pairs = [[a_, b_] for a_ in range(6) for b_ in range(6)]

    def diplomacy(name, commands, units=None, extra_pairs=(), matrix=None):
        rows.append({"id": "npc_diplomacy/" + name, "kind": "npc_diplomacy",
                     "inputs": {"units": units or [dict(UNIT, side=1), dict(UNIT, uid=2, side=2), dict(UNIT, uid=3, side=5, dead=True, hp=0)],
                                "observe": [0, 1, 2, -1], "pairs": pairs + [list(p) for p in extra_pairs],
                                "diplomacy": base_matrix if matrix is None else matrix, "commands": commands}})

    for i, value in enumerate([-1, 0, 1, 0.5, -0.5, -0.0, 2, -100]):
        diplomacy(f"SetDiplomacy_value_{i}", [call("SetDiplomacy", 1, 3, value)])
    diplomacy("SetDiplomacy_one_direction", [call("SetDiplomacy", 3, 5, -1), call("SetDiplomacy", 5, 3, 1)])
    diplomacy("SetDiplomacy_own_side", [call("SetDiplomacy", 1, 1, -1), call("SetDiplomacy", 1, 1, 0)])
    diplomacy("SetDiplomacy_fraction_sides", [call("SetDiplomacy", 1.7, 3.9, -1), call("SetDiplomacy", -0.5, 2.2, -1)])
    diplomacy("SetDiplomacy_war_peace_cycle", [call("SetDiplomacy", 1, 2, 1), call("SetDiplomacy", 1, 2, 0), call("SetDiplomacy", 1, 2, -1)])
    diplomacy("SetDiplomacy_unit_side_rows", [call("SetDiplomacy", 2, 4, -1), call("SetDiplomacy", 4, 2, -1), call("SetDiplomacy", 2, 1, 0)])
    diplomacy("SetDiplomacy_side31", [call("SetDiplomacy", 31, 0, -1), call("SetDiplomacy", 0, 31, -1)], extra_pairs=[(31, 0), (0, 31)])
    diplomacy("SetDiplomacy_side32_overflow", [call("SetDiplomacy", 32, 3, -1)], extra_pairs=[(32, 3), (0, 3)])
    diplomacy("GetDiplomacy_side33_shift", [call("SetDiplomacy", 1, 1, 1)], extra_pairs=[(1, 33), (1, 34), (2, 33)])
    diplomacy("empty_initial_matrix", [call("SetDiplomacy", 0, 1, -1)], matrix=[])
    diplomacy("SetPlayer_side", [call("SetPlayer", u(1), 1)])
    diplomacy("SetPlayer_then_war", [call("SetPlayer", u(1), 4), call("SetDiplomacy", 4, 0, -1), call("SetDiplomacy", 4, 3, -1)])
    diplomacy("SetPlayer_fraction", [call("SetPlayer", u(0), 3.8)])
    diplomacy("SetPlayer_out_of_range", [call("SetPlayer", u(0), 40)])
    diplomacy("SetPlayer_negative", [call("SetPlayer", u(0), -1)])
    diplomacy("SetPlayer_dead", [call("SetPlayer", u(2), 1)])
    diplomacy("SetPlayer_missing", [call("SetPlayer", u(-1), 1)])
    diplomacy("SetEnemy_bit", [call("SetEnemy", u(0), 5)])
    diplomacy("SetEnemy_then_peace", [call("SetEnemy", u(0), 3), call("SetDiplomacy", 1, 3, 1), call("SetDiplomacy", 1, 2, 0)])
    diplomacy("SetEnemy_shift", [call("SetEnemy", u(0), 33)])
    diplomacy("SetEnemy_missing", [call("SetEnemy", u(-1), 3)])
    def random_relation():
        roll = rng.random()
        if roll < 0.6:
            return call("SetDiplomacy", rng.randint(0, 5), rng.randint(0, 5), rng.choice([-1, 0, 1]))
        if roll < 0.85:
            return call("SetPlayer", u(rng.randint(0, 1)), rng.randint(0, 5))
        return call("SetEnemy", u(rng.randint(0, 1)), rng.randint(0, 5))

    for i in range(fuzz):
        diplomacy(f"seeded_{i:03}", [random_relation() for _ in range(rng.randint(2, 6))])

    # ---- alarms
    indices = [0, 1, 2, 3, 4]

    def alarm(name, steps, units=None, tick=100, queries=indices):
        rows.append({"id": "npc_alarm/" + name, "kind": "npc_alarm",
                     "inputs": {"units": units or [dict(UNIT, pos=[3.5, -2])], "tick": tick,
                                "queries": list(queries), "steps": steps}})

    def invoke(n, x=7, y=8):
        return {"command": call("InvokeAlarm", n, x, y)}

    tick = {"tick": 1}
    for n in [0, 1, 2, 3, 4]:
        alarm(f"InvokeAlarm_{n}", [invoke(n, 7.25, -8.5)])
    alarm("InvokeAlarm_out_of_range", [invoke(5), invoke(-1), invoke(100)])
    alarm("InvokeAlarm_fraction_index", [invoke(4.9), invoke(1.2)])
    alarm("InvokeAlarm_negative_fraction_clears", [invoke(2), invoke(3), invoke(-0.5, 1, 1)])
    alarm("InvokeAlarm_forced_overwrite", [invoke(1, 1, 1), tick, tick, invoke(1, 2, 2)])
    alarm("InvokeAlarm_zero_clears_all", [invoke(1), invoke(2), invoke(4), tick, invoke(0, 5, 6)])
    alarm("InvokeAlarm_zero_twice", [invoke(0, 1, 1), tick, invoke(0, 2, 2)])
    alarm("alarm_lifetime", [invoke(2, 3, 4)] + [tick] * 6)
    alarm("query_rounding", [invoke(1), invoke(2), invoke(3)], queries=[0.5, 1.5, 2.5, 3.5, 2.7, 1.2, 0.49])
    alarm("tick_counter_zero", [tick, invoke(3)], tick=0)
    alarm("tick_counter_large", [invoke(3), tick, invoke(4)], tick=1000000)

    def alerted(raise_index, countdown, flag=True, **unit):
        return dict(UNIT, alert={"alerted": flag, "raise": raise_index, "countdown": countdown}, **unit)

    alarm("countdown_raises", [tick] * 5, units=[alerted(2, 3, pos=[3.5, -2])])
    alarm("countdown_one", [tick, tick], units=[alerted(3, 1)])
    alarm("countdown_zero", [tick, tick], units=[alerted(3, 0)])
    alarm("countdown_negative", [tick, tick], units=[alerted(3, -4)])
    alarm("countdown_not_alerted", [tick, tick], units=[alerted(3, 1, flag=False)])
    alarm("countdown_raise_zero", [tick, tick], units=[alerted(0, 1)])
    alarm("countdown_raise_out_of_range", [tick, tick], units=[alerted(5, 1)])
    alarm("countdown_alarm_already_set", [invoke(2, 1, 1), tick, tick], units=[alerted(2, 2, pos=[9, 9])])
    alarm("countdown_after_forced_clear", [invoke(2, 1, 1), invoke(0, 0, 0), tick], units=[alerted(2, 2, pos=[9, 9])])
    alarm("countdown_two_units_same_alarm", [tick, tick],
          units=[alerted(1, 2, pos=[1, 1]), alerted(1, 2, uid=2, pos=[2, 2])])
    alarm("countdown_two_units_two_alarms", [tick, tick, tick],
          units=[alerted(1, 2, pos=[1, 1]), alerted(4, 3, uid=2, pos=[2, 2])])
    alarm("countdown_default_75", [tick] * 77, units=[alerted(1, 75, pos=[-3.25, 0.5])], tick=13)
    for i in range(fuzz):
        steps = [rng.choice([tick, tick, invoke(rng.randint(0, 4), round(rng.uniform(-99, 99), 2), round(rng.uniform(-99, 99), 2))])
                 for _ in range(rng.randint(3, 9))]
        alarm(f"seeded_{i:03}", steps, units=[alerted(rng.randint(0, 4), rng.randint(0, 4), pos=[rng.randint(-9, 9), rng.randint(-9, 9)])],
              tick=rng.randint(0, 5000))
    return rows


def _bits(value):
    return type(value) is int and 0 <= value <= 0xffffffff


def _motivation_entry(entry):
    if not isinstance(entry, dict) or not isinstance(entry.get("type"), str):
        return False
    kind = entry["type"]
    fields = {"guard": {"type", "point_bits", "radius", "stay"}, "sentry": {"type", "point_bits"},
              "patrol": {"type", "points"}, "aggression": {"type", "revenge"}, "fear": {"type", "flag"},
              "follow": {"type", "target"}}.get(kind, {"type"})
    if set(entry) != fields:
        return False
    if "point_bits" in entry and not (isinstance(entry["point_bits"], list) and len(entry["point_bits"]) == 3
                                      and all(_bits(v) for v in entry["point_bits"])):
        return False
    if kind == "guard" and not all(_bits(entry[k]) or entry[k] in ("GuardRadius", "GuardStayTime") for k in ("radius", "stay")):
        return False
    if kind in ("aggression", "fear") and type(entry[next(iter(fields - {"type"}))]) is not bool:
        return False
    if kind == "follow" and type(entry["target"]) is not int:
        return False
    return True


def validate(case, steps, role):
    kind = case["kind"]
    for step in steps:
        state, ok = step["state"], False
        if kind == "npc_motivation":
            units = state.get("units")
            ok = set(state) == {"units"} and isinstance(units, list) and len(units) == len(case["inputs"]["observe"])
            for row in units or []:
                if not ok:
                    break
                if row == {"present": False}:
                    continue
                ok = (isinstance(row, dict) and set(row) == {"present", "blocked", "side", "motivations", "ai_state", "script_target"}
                      and row["present"] is True and type(row["blocked"]) is bool and type(row["side"]) is int
                      and type(row["ai_state"]) is int and type(row["script_target"]) is int
                      and isinstance(row["motivations"], list) and all(_motivation_entry(m) for m in row["motivations"]))
        elif kind == "npc_diplomacy":
            units = state.get("units")
            ok = (set(state) == {"relation_bits", "units"} and isinstance(state["relation_bits"], list)
                  and len(state["relation_bits"]) == len(case["inputs"]["pairs"]) and all(_bits(v) for v in state["relation_bits"])
                  and isinstance(units, list) and len(units) == len(case["inputs"]["observe"])
                  and all(isinstance(r, dict) and set(r) == {"side", "enemy_bits"} and _bits(r["enemy_bits"])
                          and (r["side"] is None or type(r["side"]) is int) for r in units))
        elif kind == "npc_alarm":
            table = state.get("alarms")
            ok = (set(state) == {"alarms", "countdowns"} and isinstance(table, list)
                  and len(table) == len(case["inputs"]["queries"])
                  and all(isinstance(r, dict) and set(r) == {"on_bits", "time_bits", "x_bits", "y_bits"}
                          and all(_bits(v) for v in r.values()) for r in table)
                  and isinstance(state["countdowns"], list) and all(type(v) is int for v in state["countdowns"]))
        if not ok:
            raise ValueError(f"{role} {case['id']} has an invalid {kind} observation")
