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
    }


STEP_COUNTS = {"npc_fear": "ticks"}


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


def scenarios(seed=20261020, fuzz=12):
    return fear_scenarios(seed, fuzz)


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
        else:
            ok = False
        if not ok:
            raise ValueError(f"{role} {case['id']} has an invalid {kind} observation")
