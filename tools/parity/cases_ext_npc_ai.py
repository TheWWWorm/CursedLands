"""NPC AI decisions (internal behaviour, not script commands).

Inputs only: authored situations and seeded fuzz. No expected values, and no
Python model of a priority, suspicion or score formula.
"""
import random

SHIPPED = {"RangedAttackDist": 7.0, "RangedRunDist": 4.0, "DamageLevelRunLimit": 0.5}
# Sides: 1 observer, 0 party, 2 hostile, 3 allied.
RELATIONS = [[1, 2, 2], [2, 1, 2], [1, 0, 1], [0, 1, 1], [1, 3, 0], [3, 1, 0]]
LEG = 3


def contracts(campaign):
    if campaign != "original":
        return {}
    return {
        "npc_fear": {
            "entry": ["0x5d53b0..0x5d547d", "0x5d2960", "0x5cbbe0", "0x5d7e90"],
            "scope": "Fear motivation priority (5d2960: kiting 15000, noticed hostile 3000, danger cell 350, "
                     "Fear(1) party suspicion, suspicion level / 6, flee radius and spread updates) after the "
                     "original AI tick prologue (5d53b0 head: perception tick 5cb700 with delayed sounds and decay, "
                     "noticed-hostile flag), with original suspicion (5cbbe0) and hit-hook (5d7e90) events, versus "
                     "UnitAI._fear_priority with UnitAI.suspect and UnitAI.on_attacked.",
            "stubs": ["perception scan 5caa00 adds nothing (noticed list supplied; remake player_perceive cached)",
                      "ranged-weapon predicate 54b6c0 (remake stats.ranged)",
                      "danger-cell test 5bbdb0 by exact point (remake danger_at override)",
                      "legs wound factor controller+0x238 (remake wound_factor(3) override)",
                      "ai.reg RangedAttackDist/RangedRunDist/DamageLevelRunLimit values",
                      "unit dead/type virtual getters, reference release no-op",
                      "CRT allocation and debug-log stream output",
                      "one unit-grid cell holding all fixture units for the help-call query 5c0bd0",
                      "attacker reset at the AI tick end (5d53b0 epilogue not executed)",
                      "remake party-unit noticing mapped to life-sense detectability",
                      "remake world.nav is an empty NavGrid (a kiting spot search finds no path)",
                      "remake world clock advanced by time += 55 ms per tick, as GameWorld._tick_body does"],
            "limits": "Motivation bodies (Fear tick, walking, look round) are not executed; the kiting spot "
                      "path search is outside the contract (kiters are walking or out of range); "
                      "current motivation and walk state are supplied per tick.",
            "tolerances": {},
        },
        "npc_suspicion": {
            "entry": ["0x5cbbe0", "0x5d5990", "0x5d7e90", "0x5d53b0..0x5d547d"],
            "scope": "Suspicion records of several units: acceptance (5cbbe0, strictly above the current level), "
                     "per-tick decay, call for help (5d5990: unit-grid query 5c0bd0 within the caller's help "
                     "radius, diplomacy-friend filter, delayed sound 5cbba0/5ccd40 of 26 ticks replacing the "
                     "unit's entries of 26 or more), hit-hook routing (5d7e90) and delayed-sound conversion to "
                     "900/-3 below level 900 (5cc9d0 in the perception tick 5cb700 of each unit's AI tick "
                     "prologue), versus UnitAI.suspect, call_for_help, hit_hook, tick and _susp_level.",
            "stubs": ["perception scan 5caa00 adds nothing (no noticed-list maintenance)",
                      "one unit-grid cell holding all fixture units for the help-call query 5c0bd0",
                      "unit dead/type virtual getters, reference release no-op",
                      "CRT allocation, CString and debug-log stream output",
                      "help radius written to AI+0x38 directly (the descriptor mapping of "
                      "CallForHelpRadiusDefault is not executed; shipped values make it the identity)",
                      "remake world clock advanced by time += 55 ms per tick, as GameWorld._tick_body does"],
            "limits": "Only living non-party units are observed; motivation priorities and bodies are not run "
                      "(no Suspection/Fear reaction to the attacker); sounds other than help calls are not "
                      "produced; party units and dead units are never diplomacy friends of a caller here.",
            "tolerances": {},
        },
        "npc_target_score": {
            "entry": ["0x5cf9a0"],
            "scope": "AI option/target score (5cf9a0: weapon, bolt, area, lasting, effect and heal options; "
                     "current-target bonus, damage against armour 522ae0, area sums with the 5cfe20 distance, "
                     "has-effect 50f630, healing maximum 524020, threshold early return, distance/range "
                     "penalty and the HP-per-damage term), stored as float32 as its caller 5d0030 does, versus "
                     "UnitAI._score.",
            "stubs": ["CRT allocation",
                      "candidate/caster HP records (unit+0x17e/+0x180) supplied (remake _get_hp override, max_hp)",
                      "option power controller+0xa4c supplied (remake UnitAI.options override)",
                      "effect id n <-> remake buff key 'effect<n>'",
                      "option damage shorts at option+0x1a and armour shorts at controller+0x8e6 <-> remake opt.v "
                      "and stats.armor (types 0-6)",
                      "caster position argument = the caster unit's position"],
            "limits": "Type 3's NO_SCORE branch (candidate controller+0x164 == 0) is not compared: the field is "
                      "a creature state whose mapping to the remake's 'walking a path' test is not established; "
                      "all candidates have +0x164 = 1 and an empty remake path. Choice ordering, area safety and "
                      "reachability (5d0030) are not executed.",
            "tolerances": {},
        },
        "npc_motivation": {
            "entry": ["0x5d53b0..0x5d56de", "0x5cbbe0"],
            "scope": "Motivation arbitration of the AI tick (5d53b0: perception tick, the real priorities of the "
                     "logic-model-3 motivation set of aggression modes 0, 2 and 3 - Sentry 5d0a80, Aggression "
                     "5d2390, Suspection 5d1e90, CorpseWatcher 5d27d0, Fear 5d2960 - the current motivation's "
                     "+100, strict-greater choice in list order, leave/enter/tick dispatch) without noticed "
                     "hostiles, versus UnitAI.think.",
            "stubs": ["motivation tick/enter/leave entries are recorders (remake _fear_tick, _susp_go and _sentry "
                      "overrides record; calm_tick finds no buff)",
                      "perception scan 5caa00 adds nothing (noticed list supplied; remake player_perceive cached)",
                      "danger-cell test 5bbdb0 by exact point (remake danger_at override)",
                      "ranged-weapon predicate 54b6c0 false",
                      "unit dead/type virtual getters, reference release no-op",
                      "CRT allocation, CString and debug-log stream output",
                      "remake world clock advanced by time += 55 ms per tick, as GameWorld._tick_body does"],
            "limits": "No living hostile is noticed (Aggression, kiting and the 3000 Fear branch need the option "
                      "choice 5d0030 and path search); the corpse queue is empty; the AI-state switch after the "
                      "motivation tick is not executed.",
            "tolerances": {},
        },
    }


STEP_COUNTS = {"npc_fear": "ticks", "npc_suspicion": "ticks", "npc_target_score": "evals", "npc_motivation": "ticks"}


def _unit(pos, side=1, **extra):
    row = {"pos": list(pos), "side": side}
    row.update(extra)
    return row


def _fear(rows, name, units, ticks, flag=1, **extra):
    inputs = {"flag": flag, "aggression": 3 if flag else 2, "config": dict(SHIPPED),
              "relations": RELATIONS, "units": units, "ticks": ticks}
    inputs.update(extra)
    rows.append({"id": "npc_fear/" + name, "kind": "npc_fear", "inputs": inputs})


def fear_scenarios(seed, fuzz):
    rows = []
    me = (5.0, 5.0, 1.5)
    calm = {"current": "calm"}
    # Fear(1): a noticed party unit within the flee radius raises suspicion 1000.
    for distance in [4.0, 9.9, 10.0, 10.1, 12.0]:
        _fear(rows, f"flag1_party_noticed_d{distance}",
              [_unit(me), _unit((5.0 + distance, 5.0, 1.5), 0, party=True, noticed=True)],
              [calm, calm, {"current": "fear"}])
    _fear(rows, "flag1_party_not_noticed",
          [_unit(me), _unit((8.0, 5.0, 1.5), 0, party=True)], [calm, calm])
    _fear(rows, "flag0_party_noticed",
          [_unit(me), _unit((8.0, 5.0, 1.5), 0, party=True, noticed=True)], [calm, calm], flag=0)
    # Two noticed party units: the farther one first in registry order.
    _fear(rows, "flag1_two_party_order",
          [_unit(me), _unit((12.0, 5.0, 1.5), 0, party=True, noticed=True),
           _unit((7.0, 5.0, 1.5), 0, party=True, noticed=True)], [calm, calm])
    # Fear current versus calm while the party unit walks away: level / 6
    # hysteresis and the radius test (with the unit's own height).
    leave = {"moves": {"1": [15.9, 15.9, 1.5]}}
    for current in ["fear", "calm"]:
        ticks = [calm, dict(calm, **leave)] + [{"current": current}] * 6
        _fear(rows, f"flag1_party_leaves_{current}",
              [_unit(me), _unit((8.0, 5.0, 1.5), 0, party=True, noticed=True)], ticks)
    for height in [0.0, 1.5, 6.0, 9.0, 12.0]:
        _fear(rows, f"suspicion_point_height_{height}",
              [_unit((5.0, 5.0, height))],
              [{"current": "calm", "events": [{"kind": "suspect", "point": [8.0, 5.0, 0.0], "level": 900, "delta": -2}]},
               calm, calm, {"current": "fear"}], flag=0)
    for level in [49, 50, 51, 52, 56, 57, 300, 905, 906, 907]:
        for current in ["fear", "calm"]:
            _fear(rows, f"suspicion_level_{level}_{current}",
                  [_unit(me)],
                  [{"current": current, "events": [{"kind": "suspect", "point": [6.0, 6.0, 0.0], "level": level + 1, "delta": -1}]},
                   {"current": current}, {"current": current}], flag=0)
    # Noticed hostiles: 3000 unless dead; dead hostiles ignored.
    for flag in [0, 1]:
        _fear(rows, f"hostile_noticed_flag{flag}",
              [_unit(me), _unit((14.0, 14.0, 0.0), 2, noticed=True)], [calm, {"current": "fear"}], flag=flag)
        _fear(rows, f"hostile_dead_flag{flag}",
              [_unit(me), _unit((14.0, 14.0, 0.0), 2, noticed=True, dead=True)], [calm], flag=flag)
        _fear(rows, f"hostile_not_noticed_flag{flag}",
              [_unit(me), _unit((14.0, 14.0, 0.0), 2)], [calm], flag=flag)
    # Kiting (15000 while walking): every predicate on its own.
    kiter = dict(ranged=True, move_class=3, wound=1.0)
    hostile_near = _unit((10.0, 5.0, 1.5), 2, noticed=True)
    walking = {"current": "fear", "walking": "fear"}
    _fear(rows, "kite_walking", [_unit(me, **kiter), hostile_near], [walking, walking])
    _fear(rows, "kite_not_ranged", [_unit(me, **dict(kiter, ranged=False)), hostile_near], [walking])
    for move_class in [5, 6, 7]:
        _fear(rows, f"kite_move_class_{move_class}", [_unit(me, **dict(kiter, move_class=move_class)), hostile_near], [walking])
    _fear(rows, "kite_spell_slot0", [_unit(me, **dict(kiter, spell0=True)), hostile_near], [walking])
    for wound in [0.5, 0.6, 0.6000001, 1.0]:
        _fear(rows, f"kite_wound_{wound}", [_unit(me, **dict(kiter, wound=wound)), hostile_near], [walking])
    for cur in [5.0, 4.99, 4.0]:
        legs = [{"type": LEG, "state": 2, "cur": cur, "max": 10.0}, {"type": LEG, "state": 2, "cur": 10.0, "max": 10.0}]
        _fear(rows, f"kite_leg_{cur}_of_10", [_unit(me, **dict(kiter, parts=legs)), hostile_near], [walking])
    severed = [{"type": LEG, "state": 0, "cur": 0.0, "max": 10.0}]
    _fear(rows, "kite_leg_absent", [_unit(me, **dict(kiter, parts=severed)), hostile_near], [walking])
    for distance in [6.9, 7.0, 7.1]:
        _fear(rows, f"kite_distance_{distance}", [_unit(me, **kiter), _unit((5.0 + distance, 5.0, 1.5), 2, noticed=True)], [walking])
    for distance in [4.0, 4.1, 6.0]:
        _fear(rows, f"kite_in_aggression_distance_{distance}",
              [_unit(me, **kiter), _unit((5.0 + distance, 5.0, 1.5), 2, noticed=True)],
              [{"current": "aggression", "target": 1}])
    # Nearest noticed hostile: original 3D distance, remake ordering.
    _fear(rows, "kite_nearest_3d_versus_2d",
          [_unit(me, **kiter), _unit((12.5, 5.0, 1.5), 2, noticed=True), _unit((5.0, 10.0, 7.5), 2, noticed=True)],
          [walking])
    _fear(rows, "kite_other_walk", [_unit(me, **kiter), hostile_near], [{"current": "calm", "walking": "other"}])
    # Danger cells: the unit's own spot, then the kept spot.
    _fear(rows, "danger_own_then_kept",
          [_unit(me)],
          [{"current": "calm", "danger": [[5.0, 5.0]]},
           {"current": "fear", "danger": [[5.0, 5.0]], "moves": {"0": [6.0, 5.0, 1.5]}},
           {"current": "fear", "danger": []}, {"current": "fear"}], flag=0)
    _fear(rows, "danger_beats_party_suspicion",
          [_unit(me), _unit((8.0, 5.0, 1.5), 0, party=True, noticed=True)],
          [{"current": "calm", "danger": [[5.0, 5.0]]}, calm])
    _fear(rows, "danger_with_hostile",
          [_unit(me), _unit((12.0, 12.0, 0.0), 2, noticed=True)],
          [{"current": "calm", "danger": [[5.0, 5.0]]}], flag=0)
    # Hit events: radius growth, suspicion at the attacker, forced notice.
    for name, attacker, current in [
            ("hostile_fighting", _unit((12.0, 12.0, 0.0), 2, fighting=True), "calm"),
            ("hostile_fighting_fear", _unit((12.0, 12.0, 0.0), 2, fighting=True), "fear"),
            ("hostile_near_not_fighting", _unit((8.0, 5.0, 1.5), 2), "calm"),
            ("hostile_far_not_fighting", _unit((15.0, 15.0, 0.0), 2), "calm"),
            ("party_not_fighting", _unit((8.0, 5.0, 1.5), 0, party=True), "calm"),
            ("ally_fighting", _unit((9.0, 9.0, 0.0), 3, fighting=True), "calm"),
            ("hostile_far_height", _unit((5.0, 15.0, 9.0), 2, fighting=True), "calm")]:
        _fear(rows, "hit_" + name, [_unit(me), attacker],
              [{"current": current, "events": [{"kind": "hit", "by": 1, "when": "before"}]},
               {"current": current}, {"current": current}, {"current": current}], flag=0)
    # The same hit landing after the observer's decision in its world tick.
    for current in ["calm", "fear"]:
        _fear(rows, f"hit_after_decision_{current}", [_unit(me), _unit((12.0, 12.0, 0.0), 2, fighting=True)],
              [{"current": current, "events": [{"kind": "hit", "by": 1}]}, {"current": current}, {"current": current}], flag=0)
    # Flee radius decay back towards 10 m after a far attacker.
    _fear(rows, "radius_decay_after_hit",
          [_unit((0.5, 0.5, 0.0)), _unit((15.5, 15.5, 0.0), 0, party=True)],
          [{"current": "calm", "events": [{"kind": "hit", "by": 1, "when": "before"}]}] + [calm] * 40, flag=0)
    rng = random.Random(seed ^ 0xf3a2)
    for trial in range(fuzz):
        flag = rng.choice([0, 1])
        me_row = _unit((rng.uniform(1, 15), rng.uniform(1, 15), rng.choice([0.0, 1.5, 4.0])))
        if rng.random() < 0.3:
            me_row.update(kiter)
        units = [me_row]
        for _ in range(rng.randint(0, 3)):
            side = rng.choice([0, 2, 3])
            dead = rng.random() < 0.15
            # The original perception scan drops dead units before the
            # priority runs, so a dead unit is never in the noticed input.
            units.append(_unit((rng.uniform(0.1, 15.9), rng.uniform(0.1, 15.9), rng.choice([0.0, 1.5, 3.0])), side,
                               party=side == 0, noticed=not dead and rng.random() < 0.6, dead=dead,
                               fighting=side != 0 and not dead and rng.random() < 0.4))
        ticks = []
        for _ in range(rng.randint(3, 10)):
            tick = {"current": rng.choice(["calm", "fear", "none"])}
            if me_row.get("ranged"):
                tick["walking"] = "fear"   # a standing kiter in range would search a spot
            if rng.random() < 0.2:
                tick["danger"] = [list(me_row["pos"][:2])]
            events = []
            if rng.random() < 0.25:
                events.append({"kind": "suspect", "point": [rng.uniform(0, 16), rng.uniform(0, 16), 0.0],
                               "level": rng.choice([60, 300, 800, 900, 1000]), "delta": rng.choice([-1, -2, -3])})
            # Hitters are living non-allies: the allied-attacker case is a
            # named scenario (hit_ally_fighting) and would dominate the fuzz.
            hitters = [i for i in range(1, len(units)) if not units[i]["dead"] and units[i]["side"] != 3]
            if hitters and rng.random() < 0.2:
                events.append({"kind": "hit", "by": rng.choice(hitters), "when": rng.choice(["before", "after"])})
            if events:
                tick["events"] = events
            ticks.append(tick)
        _fear(rows, f"seeded_{trial:03}", units, ticks, flag=flag)
    return rows


HELP_CONFIG = {"CallForHelpRadius": 7.0, "CallForHelpRadiusDefault": 7.0}


def _susp(rows, name, units, ticks):
    inputs = {"config": dict(HELP_CONFIG), "relations": RELATIONS, "units": units, "ticks": ticks}
    rows.append({"id": "npc_suspicion/" + name, "kind": "npc_suspicion", "inputs": inputs})


def _quiet(n):
    return [{} for _ in range(n)]


def suspicion_scenarios(seed, fuzz):
    rows = []
    caller = (8.0, 8.0, 0.0)
    # Help radius boundary (2D distance; the friend stands above the caller
    # in one case) for radius 7 and 10.
    for radius, distances in ((7.0, (6.9, 7.0, 7.1)), (10.0, (9.99, 10.0))):
        for d in distances:
            _susp(rows, f"help_radius_{radius:g}_d{d:g}",
                  [_unit(caller, help_radius=radius), _unit((8.0 + d, 8.0, 0.0))],
                  [{"events": [{"kind": "help", "unit": 0, "point": [3.0, 4.0, 0.0]}]}] + _quiet(29))
    _susp(rows, "help_radius_height",
          [_unit(caller, help_radius=7.0), _unit((14.5, 8.0, 6.0))],
          [{"events": [{"kind": "help", "unit": 0, "point": [3.0, 4.0, 0.0]}]}] + _quiet(29))
    # Friend filter: own side, allied side, hostile side, neutral party.
    _susp(rows, "help_friend_filter",
          [_unit(caller), _unit((9.0, 8.0, 0.0)), _unit((8.0, 9.0, 0.0), 3), _unit((7.0, 8.0, 0.0), 2),
           _unit((8.0, 7.0, 0.0), 0, party=True)],
          [{"events": [{"kind": "help", "unit": 0, "point": [3.0, 4.0, 0.0]}]}] + _quiet(29))
    # Event order within the tick.
    for when in ("before", "after"):
        _susp(rows, f"help_{when}_decision",
              [_unit(caller), _unit((9.0, 8.0, 0.0))],
              [{"events": [{"kind": "help", "unit": 0, "point": [3.0, 4.0, 0.0], "when": when}]}] + _quiet(30))
    # Existing level against the 900 conversion (delta 0 holds the level).
    for level in (899, 900, 950):
        _susp(rows, f"help_over_level_{level}",
              [_unit(caller), _unit((9.0, 8.0, 0.0))],
              [{"events": [{"kind": "suspect", "unit": 1, "point": [12.0, 12.0, 0.0], "level": level, "delta": 0},
                           {"kind": "help", "unit": 0, "point": [3.0, 4.0, 0.0]}]}] + _quiet(29))
    # Repeated calls: the same tick replaces the entry, a tick later keeps
    # both; the second conversion moves the point.
    _susp(rows, "help_twice_same_tick",
          [_unit(caller), _unit((9.0, 8.0, 0.0))],
          [{"events": [{"kind": "help", "unit": 0, "point": [3.0, 4.0, 0.0]},
                       {"kind": "help", "unit": 0, "point": [5.0, 6.0, 0.0]}]}] + _quiet(29))
    _susp(rows, "help_twice_next_tick",
          [_unit(caller), _unit((9.0, 8.0, 0.0))],
          [{"events": [{"kind": "help", "unit": 0, "point": [3.0, 4.0, 0.0]}]},
           {"events": [{"kind": "help", "unit": 0, "point": [5.0, 6.0, 0.0]}]}] + _quiet(30))
    _susp(rows, "help_two_callers_one_friend",
          [_unit(caller), _unit((9.0, 8.0, 0.0)), _unit((10.0, 9.0, 0.0))],
          [{"events": [{"kind": "help", "unit": 0, "point": [3.0, 4.0, 0.0]},
                       {"kind": "help", "unit": 2, "point": [5.0, 6.0, 0.0]}]}] + _quiet(29))
    # The friend walks out of range before a second call.
    _susp(rows, "help_friend_leaves",
          [_unit(caller), _unit((9.0, 8.0, 0.0))],
          [{"events": [{"kind": "help", "unit": 0, "point": [3.0, 4.0, 0.0]}]},
           {"moves": {"1": [15.5, 15.5, 0.0]}, "events": [{"kind": "help", "unit": 0, "point": [5.0, 6.0, 0.0]}]}]
          + _quiet(29))
    # Hit-hook routing: hostile, party (neutral), allied attacker, none.
    for name, side, party in (("hostile", 2, False), ("party", 0, True), ("ally", 3, False)):
        _susp(rows, f"hit_by_{name}",
              [_unit(caller), _unit((9.0, 8.0, 0.0)), _unit((6.5, 9.5, 1.0), side, party=party)],
              [{"events": [{"kind": "hit", "unit": 0, "by": 2}]}] + _quiet(29))
    _susp(rows, "hit_by_nothing",
          [_unit(caller), _unit((9.0, 8.0, 0.0))],
          [{"events": [{"kind": "hit", "unit": 0, "by": None}]}] + _quiet(29))
    # Acceptance strictly above the current level, same tick and later.
    _susp(rows, "suspect_equal_rejected",
          [_unit(caller)],
          [{"events": [{"kind": "suspect", "unit": 0, "point": [1.0, 1.0, 0.0], "level": 500, "delta": -1},
                       {"kind": "suspect", "unit": 0, "point": [2.0, 2.0, 0.0], "level": 500, "delta": -3}]},
           {"events": [{"kind": "suspect", "unit": 0, "point": [3.0, 3.0, 0.0], "level": 499, "delta": -2}]},
           {"events": [{"kind": "suspect", "unit": 0, "point": [4.0, 4.0, 0.0], "level": 499, "delta": -2}]},
           {}])
    _susp(rows, "suspect_below_zero",
          [_unit(caller)],
          [{"events": [{"kind": "suspect", "unit": 0, "point": [1.0, 1.0, 0.0], "level": 10, "delta": -3}]}]
          + _quiet(6) + [{"events": [{"kind": "suspect", "unit": 0, "point": [2.0, 2.0, 0.0], "level": -5,
                                      "delta": -1}]}] + _quiet(3))
    _susp(rows, "suspect_rising",
          [_unit(caller)],
          [{"events": [{"kind": "suspect", "unit": 0, "point": [1.0, 1.0, 0.0], "level": 100, "delta": 2}]}]
          + _quiet(5))
    _susp(rows, "decay_long",
          [_unit(caller)],
          [{"events": [{"kind": "suspect", "unit": 0, "point": [1.0, 1.0, 0.0], "level": 1000, "delta": -2}]}]
          + _quiet(60))
    rng = random.Random(seed ^ 0x5a17)
    for trial in range(fuzz):
        units = []
        for i in range(rng.randint(2, 5)):
            side = rng.choice([1, 1, 3, 2, 0]) if i else 1
            units.append(_unit((rng.uniform(0.5, 15.5), rng.uniform(0.5, 15.5), rng.choice([0.0, 1.5, 3.0])), side,
                               party=side == 0, help_radius=rng.choice([4.0, 7.0, 10.0, 16.0])))
        npcs = [i for i, row in enumerate(units) if not row.get("party")]
        ticks = []
        for _ in range(rng.randint(30, 45)):
            tick, events = {}, []
            for _ in range(rng.choice([0, 0, 0, 1, 1, 2])):
                kind = rng.choice(["suspect", "help", "help", "hit"])
                unit = rng.choice(npcs)
                when = rng.choice(["before", "after"])
                if kind == "suspect":
                    events.append({"kind": kind, "unit": unit, "when": "after",
                                   "point": [rng.uniform(0, 16), rng.uniform(0, 16), 0.0],
                                   "level": rng.choice([60, 300, 800, 899, 900, 950, 1000]),
                                   "delta": rng.choice([0, -1, -2, -3])})
                elif kind == "help":
                    events.append({"kind": kind, "unit": unit, "when": when,
                                   "point": [rng.uniform(0, 16), rng.uniform(0, 16), rng.choice([0.0, 2.0])]})
                else:
                    others = [i for i in range(len(units)) if i != unit]
                    events.append({"kind": kind, "unit": unit, "when": when,
                                   "by": rng.choice(others + [None])})
            if events:
                tick["events"] = events
            if rng.random() < 0.1:
                mover = rng.randrange(len(units))
                tick["moves"] = {str(mover): [rng.uniform(0.5, 15.5), rng.uniform(0.5, 15.5), 0.0]}
            ticks.append(tick)
        _susp(rows, f"seeded_{trial:03}", units, ticks)
    return rows


def _fighter(pos, hp=40, max_hp=40, armour=(0,) * 7, **extra):
    row = {"pos": list(pos), "side": 1, "hp": hp, "max_hp": max_hp, "armour": list(armour)}
    row.update(extra)
    return row


def _opt(kind, v=(0,) * 7, **extra):
    row = {"type": kind, "v": list(v)}
    row.update(extra)
    return row


def _eval(option, candidate=1, members=(1,), caster=0, cur=None, threshold=-1e20):
    return {"caster": caster, "candidate": candidate, "list": list(members), "cur": cur,
            "threshold": threshold, "option": option}


def _score_case(rows, name, units, evals):
    rows.append({"id": "npc_target_score/" + name, "kind": "npc_target_score",
                 "inputs": {"relations": RELATIONS, "units": units, "evals": evals}})


def score_scenarios(seed, fuzz):
    rows = []
    sword = (0, 0, 12, 0, 0, 0, 0)
    base = [_fighter((2.0, 2.0, 0.0)), _fighter((2.0, 4.5, 0.0), hp=37, armour=(0, 0, 5, 0, 0, 0, 0)),
            _fighter((5.0, 2.0, 0.0), hp=9), _fighter((2.0, 2.0, 0.0), hp=0)]
    # Weapon: damage against armour, current-target bonus, threshold, HP/D.
    _score_case(rows, "weapon_basic", base, [
        _eval(_opt(0, sword)), _eval(_opt(0, sword), cur=1), _eval(_opt(0, sword), candidate=2, members=(1, 2)),
        _eval(_opt(0, (3, 0, 4, 0, 0, 0, 0))), _eval(_opt(0, (0, 0, 5, 0, 0, 0, 0))),
        _eval(_opt(0, sword), threshold=8.0), _eval(_opt(0, sword), threshold=7.0),
        _eval(_opt(0, sword), threshold=-55.0), _eval(_opt(0, sword), candidate=3, members=(3,)),
        _eval(_opt(0, (100, 200, 300, 400, 500, 600, 700)), candidate=2)])
    # Bolt: 1.3 D + bonus + 3 + D min(n - 1, k), damage sweep.
    evals = []
    for damage in (1, 7, 13, 100, 777, 1567, 2047, 3134, 5000, 12345, 32767):
        for k in (0, 2):
            evals.append(_eval(_opt(1, (0, 0, 0, damage, 0, 0, 0), n1=k), candidate=2, members=(1, 2, 3)))
    _score_case(rows, "bolt_damage_sweep", base, evals)
    # Area: members within the radius of the candidate (f32 r squared
    # against the exact squared distance), n = members, lasting duration.
    ring = [_fighter((0.0, 0.0, 0.0))]
    radii = (0.7, 1.1, 1.3, 2.7, 3.3, 4.1, 5.9)
    for r in radii:
        ring += [_fighter((0.0, 5.0, 0.0), armour=(0, 1, 0, 0, 0, 0, 0)), _fighter((r, 5.0, 0.0))]
    evals = []
    for i, r in enumerate(radii):
        cand, edge = 1 + 2 * i, 2 + 2 * i
        evals.append(_eval(_opt(2, (0, 9, 0, 0, 0, 0, 0), radius=r, n1=3), candidate=cand, members=(cand, edge)))
    _score_case(rows, "area_radius_edge", ring, evals)
    evals = []
    for dur in (0, 7, 8, 15, 16, 33, 200):
        evals.append(_eval(_opt(3, (0, 9, 0, 0, 0, 0, 0), radius=3.0, n1=1, dur=dur), candidate=1, members=(1, 2)))
    for k in (0, 1, 5):
        evals.append(_eval(_opt(2, (4, 4, 4, 4, 4, 4, 4), radius=10.0, n1=k), candidate=2, members=(1, 2, 3)))
    _score_case(rows, "area_lasting", base, evals)
    # Effects: candidate already has it, n and k, range penalty for 5/6.
    fx = [_fighter((1.0, 1.0, 0.0)), _fighter((1.0, 3.0, 0.0), effects=[5, 17]), _fighter((9.0, 1.0, 0.0)),
          _fighter((1.0, 1.0, 0.0))]
    evals = []
    for kind in (4, 5, 6):
        for effect in (5, 9):
            for rng in (0.0, 2.0, 7.9, 8.0, 8.1):
                evals.append(_eval(_opt(kind, effect=effect, n1=2, range=rng), candidate=1, members=(1, 2, 3)))
                evals.append(_eval(_opt(kind, effect=effect, n1=0, range=rng), candidate=2, members=(2,), cur=2))
    _score_case(rows, "effects", fx, evals)
    # Heal: HP against the effective maximum (severed parts), a third of it,
    # caster unhurt or not, range penalty.
    severed = [{"type": 1, "state": 0, "cur": 10.0, "max": 10.0, "size": 0.2, "lethal": 0.25},
               {"type": 2, "state": 0, "cur": 10.0, "max": 10.0, "size": 0.4, "lethal": 1.0},
               {"type": 3, "state": 1, "cur": 0.0, "max": 10.0, "size": 0.1, "lethal": 0.15},
               {"type": 3, "state": 1, "cur": 0.0, "max": 10.0, "size": 0.1, "lethal": 0.15},
               {"type": 4, "state": 0, "cur": 10.0, "max": 10.0, "size": 0.1, "lethal": 0.1},
               {"type": 4, "state": 0, "cur": 10.0, "max": 10.0, "size": 0.1, "lethal": 0.1}]
    heal_units = [_fighter((1.0, 1.0, 0.0), hp=50, max_hp=50), _fighter((1.0, 1.0, 0.0), hp=49, max_hp=50)]
    for hp in (47, 48, 49, 16, 17, 33, 34, 23, 24, 25, 1):
        heal_units.append(_fighter((4.0, 1.0, 0.0), hp=hp, max_hp=50, power=7.3))
    heal_units.append(_fighter((4.0, 1.0, 0.0), hp=24, max_hp=50, power=7.3, parts=severed))
    heal_units.append(_fighter((4.0, 1.0, 0.0), hp=33, max_hp=50, power=7.3, parts=severed))
    heal_units.append(_fighter((4.0, 1.0, 0.0), hp=11, max_hp=50, power=7.3, parts=severed))
    evals = []
    for cand in range(2, len(heal_units)):
        for caster in (0, 1):
            evals.append(_eval(_opt(7, n1=1, range=2.5), caster=caster, candidate=cand, members=(cand, 0)))
    evals.append(_eval(_opt(7, n1=1, range=3.5), candidate=5, members=(5,)))
    evals.append(_eval(_opt(7, n1=1, range=3.0), candidate=5, members=(5,), cur=5))
    _score_case(rows, "heal", heal_units, evals)
    # Damage vector edges: 16-bit sums, armour above the damage.
    edge = [_fighter((0.0, 0.0, 0.0)), _fighter((0.0, 1.0, 0.0), hp=32767, max_hp=32767),
            _fighter((0.0, 2.0, 0.0), armour=(32767,) * 7), _fighter((0.0, 1.5, 0.0), armour=(-10, 0, 0, 0, 0, 0, 0))]
    _score_case(rows, "damage_edges", edge, [
        _eval(_opt(0, (32767,) * 7)), _eval(_opt(1, (32767,) * 7, n1=2), members=(1, 2, 3)),
        _eval(_opt(2, (32767,) * 7, radius=5.0, n1=2), members=(1, 2, 3)),
        _eval(_opt(0, (1,) * 7), candidate=2, members=(2,)), _eval(_opt(0, (32767, 0, 0, 0, 0, 0, 0)), candidate=3)])
    rng = random.Random(seed ^ 0x5c0e)
    for trial in range(fuzz):
        units = []
        for _ in range(rng.randint(2, 6)):
            max_hp = rng.randint(5, 400)
            row = _fighter((round(rng.uniform(0, 20), 3), round(rng.uniform(0, 20), 3), 0.0),
                           hp=rng.randint(1, max_hp), max_hp=max_hp,
                           armour=[rng.choice([0, 0, rng.randint(0, 40)]) for _ in range(7)],
                           power=round(rng.uniform(0, 60), 2))
            if rng.random() < 0.3:
                row["effects"] = rng.sample(range(1, 40), rng.randint(1, 3))
            units.append(row)
        evals = []
        for _ in range(rng.randint(8, 16)):
            kind = rng.randrange(8)
            option = _opt(kind, [rng.choice([0, 0, rng.randint(0, 120)]) for _ in range(7)],
                          n1=rng.randint(0, 4), range=round(rng.uniform(0, 12), 2))
            if kind in (2, 3):
                option["radius"] = round(rng.uniform(0.5, 8), 2)
            if kind == 3:
                option["dur"] = rng.randint(0, 100)
            if kind in (4, 5, 6):
                option["effect"] = rng.randint(1, 40)
            members = rng.sample(range(len(units)), rng.randint(1, len(units)))
            evals.append(_eval(option, caster=rng.randrange(len(units)), candidate=rng.choice(members),
                               members=members, cur=rng.choice([None, rng.randrange(len(units))]),
                               threshold=rng.choice([-1e20, -1e20, round(rng.uniform(-300, 200), 1)])))
        _score_case(rows, f"seeded_{trial:03}", units, evals)
    return rows


def _mot(rows, name, aggression, units, ticks):
    inputs = {"aggression": aggression, "config": dict(SHIPPED), "relations": RELATIONS,
              "units": units, "ticks": ticks}
    rows.append({"id": "npc_motivation/" + name, "kind": "npc_motivation", "inputs": inputs})


def _suspect_at(point, level, delta):
    return {"kind": "suspect", "point": list(point) + [0.0], "level": level, "delta": delta}


def motivation_scenarios(seed, fuzz):
    rows = []
    me = _unit((8.0, 8.0, 0.0))
    near, far = (11.0, 9.0), (8.0, 15.5)
    spot = [[8.0, 8.0]]
    # Fear by suspicion and how long it stays current (Fear(1) and Fear(0)).
    for aggression in (2, 3):
        for level in (600, 905, 906, 1000):
            _mot(rows, f"fear_hold_mode{aggression}_level{level}", aggression, [me],
                 [{"events": [_suspect_at(near, level, -25)]}] + [{}] * 44)
    _mot(rows, "fear_hold_far_point", 3, [me], [{"events": [_suspect_at(far, 1000, -25)]}] + [{}] * 44)
    _mot(rows, "fear1_party_noticed", 3, [me, _unit((10.0, 12.0, 0.0), 0, party=True, noticed=True)],
         [{}] * 4 + [{"moves": {"1": [15.0, 15.5, 0.0]}}] + [{}] * 45)
    # Danger cells: Fear 350, kept point, Sentry current.
    _mot(rows, "danger_mode3", 3, [me], [{"danger": spot}] * 3 + [{}] * 3 + [{"danger": [[9.0, 9.0]]}] + [{}] * 3)
    # Suspection activation and hold (mode 0 has Suspection).
    for level in (150, 151, 240):
        _mot(rows, f"suspection_start_level{level}", 0, [me], [{"events": [_suspect_at(near, level, 0)]}] + [{}] * 4)
    _mot(rows, "suspection_decay_to_minus50", 0, [me], [{"events": [_suspect_at(near, 200, -10)]}] + [{}] * 30)
    # Danger against a current Suspection with M around 250-350.
    for level in (200, 249, 250, 251, 260, 300, 349, 351):
        _mot(rows, f"danger_vs_suspection_m{level}", 0, [me],
             [{"events": [_suspect_at(near, level, 0)]}, {}, {"danger": spot}, {"danger": spot}, {}, {}])
    # Fear ends while a Suspection is low: the original picks the calm one
    # unless M is above 50.
    for level in (240, 300):
        _mot(rows, f"fear_then_suspection_level{level}", 0, [me],
             [{"events": [_suspect_at(near, level, -5)]}, {}] + [{"danger": spot}] * 36 + [{}] * 6)
    # A new suspicion at the same point keeps the Suspection's minimum.
    _mot(rows, "same_point_resuspect", 0, [me],
         [{"events": [_suspect_at(near, 400, -10)]}] + [{}] * 18
         + [{"events": [_suspect_at(near, 900, -10)]}, {}, {"danger": spot}, {"danger": spot}, {}])
    _mot(rows, "new_point_resuspect", 0, [me],
         [{"events": [_suspect_at(near, 400, -10)]}] + [{}] * 18
         + [{"events": [_suspect_at((12.0, 8.0), 900, -10)]}, {}, {"danger": spot}, {"danger": spot}, {}])
    rng = random.Random(seed ^ 0x3077)
    for trial in range(fuzz):
        aggression = rng.choice([0, 2, 3])
        units = [_unit((round(rng.uniform(3, 13), 2), round(rng.uniform(3, 13), 2), 0.0))]
        for _ in range(rng.randint(0, 2)):
            units.append(_unit((round(rng.uniform(0.5, 15.5), 2), round(rng.uniform(0.5, 15.5), 2), 0.0), 0,
                               party=True, noticed=rng.random() < 0.6))
        ticks = []
        for _ in range(rng.randint(20, 50)):
            tick = {}
            if rng.random() < 0.15:
                tick["events"] = [_suspect_at((round(rng.uniform(0, 16), 2), round(rng.uniform(0, 16), 2)),
                                              rng.choice([60, 151, 240, 300, 600, 900, 1000]),
                                              rng.choice([0, -2, -5, -10, -25]))]
            if rng.random() < 0.15:
                tick["danger"] = [list(units[0]["pos"][:2])]
            if len(units) > 1 and rng.random() < 0.05:
                mover = rng.randrange(1, len(units))
                tick["moves"] = {str(mover): [round(rng.uniform(0.5, 15.5), 2), round(rng.uniform(0.5, 15.5), 2), 0.0]}
            ticks.append(tick)
        _mot(rows, f"seeded_{trial:03}", aggression, units, ticks)
    return rows


def scenarios(seed=20261020, fuzz=12):
    return (fear_scenarios(seed, fuzz) + suspicion_scenarios(seed, fuzz) + score_scenarios(seed, fuzz)
            + motivation_scenarios(seed, fuzz))


def validate(case, steps, role):
    kind = case["kind"]
    for step in steps:
        state = step["state"]
        if kind == "npc_fear":
            ok = (set(state) == {"decision_priority", "j_bits", "kept_danger", "level", "delta", "point_bits", "r_bits"}
                  and type(state["decision_priority"]) is int and type(state["kept_danger"]) is bool
                  and all(type(state[k]) is int for k in ["j_bits", "r_bits", "level", "delta"])
                  and isinstance(state["point_bits"], list) and len(state["point_bits"]) == 2
                  and all(type(v) is int and 0 <= v <= 0xffffffff for v in state["point_bits"] + [state["j_bits"], state["r_bits"]]))
        elif kind == "npc_suspicion":
            ok = (set(state) == {"units"} and isinstance(state["units"], list)
                  and all(isinstance(row, dict) and set(row) == {"level", "delta", "point_bits", "pending"}
                          and type(row["level"]) is int and type(row["delta"]) is int
                          and isinstance(row["point_bits"], list) and len(row["point_bits"]) == 2
                          and all(type(v) is int and 0 <= v <= 0xffffffff for v in row["point_bits"])
                          and isinstance(row["pending"], list) and all(type(v) is int for v in row["pending"])
                          for row in state["units"]))
        elif kind == "npc_target_score":
            ok = (set(state) == {"score_bits"} and type(state["score_bits"]) is int
                  and 0 <= state["score_bits"] <= 0xffffffff)
        elif kind == "npc_motivation":
            ok = set(state) == {"motivation"} and state["motivation"] in (
                "none", "calm", "aggression", "suspection", "corpse", "fear")
        else:
            ok = False
        if not ok:
            raise ValueError(f"{role} {case['id']} has an invalid {kind} observation")
