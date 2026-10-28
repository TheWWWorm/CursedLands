"""Perception-driven quest triggers ("an NPC notices the heroes").

Inputs only: supplied noticed/corpse lists (layer 1) or supplied senses,
positions, rays and hostility per tick (layer 2). No expected values.
"""
import random

CONTRACTS = {
    "perception_group": {
        "entry": ["0x4b41e0", "0x4b5b00", "0x4b2ef0", "0x66e0f0"],
        "scope": "Original group evaluator 0x4b5b00 (UnitSee 0x5d, GroupSee 0x5e, PlayerSee 0xa5, GroupCross 0x5b) "
                 "with sorted-set insertion 0x4b2ef0, the player visible-group aggregation 0x66e0f0 and the "
                 "expression evaluator 0x4b41e0 (GroupSize, GroupHas, Any, Every, IsAlive, IsDead, IsUnitVisible 0xe5) "
                 "reading SUPPLIED AI noticed lists (actor +0x240 -> +0xa94) and corpse lists (+0xab0), versus "
                 "ScriptVM._eval with UnitAI.can_notice_with answering exactly the same (watcher, target) pairs.",
        "stubs": ["supplied noticed and corpse list contents per actor (remake: can_notice_with true exactly for "
                  "noticed+corpse pairs; every actor within the watchers' sight radius)",
                  "supplied script groups (built by native insertion, i.e. sorted sets)",
                  "player zero's unit map (+0x40, one hash bucket) = supplied player_units (remake: controller 0)",
                  "player zero lookup 0x594180", "actor type/death/release accessors",
                  "CRT malloc/free 0x70056f/0x700598 and CPlex block allocator 0x6fe8af",
                  "empty clairvoyance extra-visible group (+0x50f8)"],
        "limits": "Group algebra and list reading only: does not establish how the lists are maintained (see "
                  "perception_ticks), whether a dead watcher keeps its list, or whether a dead hero stays in the "
                  "player's unit map. Group results are compared as sorted fixture indices plus a count; native "
                  "order is pointer order.",
        "tolerances": {},
    },
    "perception_ticks": {
        "entry": ["0x5caa00", "0x5ca5a0", "0x5ca410", "0x4b41e0", "0x4b5b00"],
        "scope": "Original AI perception update 0x5caa00 (drop pass, corpse transfer, acquisition scan 0x5ca5a0 "
                 "with sight cone, terrain ray, peripheral vision and life sense, hostility 0x530150, party test "
                 "0x5301a0) run per tick for one NPC watcher, then the quest trigger evaluated by 0x4b41e0 over "
                 "the maintained list; versus production UnitAI.player_perceive (noticed meta) and ScriptVM._eval "
                 "of the same trigger after the same movement.",
        "stubs": ["spatial candidate list 0x5ca1d0 = every other actor, refreshed each tick (remake: "
                  "_notice_candidates returns every other actor)",
                  "terrain sight ray 0x5bc3e0 = supplied factor per target (remake: GameWorld.sight_ray)",
                  "senses: sight, sight factor, life sense, cone half-angle (native cosine), peripheral range; "
                  "targets' visibility, sight and life detectability",
                  "flat ground and zero eye height (empty terrain grid read by 0x5ca410)",
                  "target position accessor (vtable +0xc0) and death accessor (vtable +0xdc)",
                  "debug log stream operators", "CRT malloc/free and CPlex block allocator",
                  "no perception update while the watcher is dead (assumption)"],
        "limits": "One watcher; no suspicion/alarm behaviour, hearing, Aggression target or combat stance; "
                  "candidate staleness (8..11 tick refresh) is removed on both sides. Noticed lists are compared "
                  "as sorted fixture indices (native push-front order is not compared).",
        "tolerances": {},
    },
    "perception_candidates": {
        "entry": ["0x5caa00", "0x5ca1d0", "0x5bf8f0", "0x5c0df0", "0x5c11d0", "0x5ca5a0"],
        "scope": "Original AI perception update 0x5caa00 with its candidate-list refresh 0x5ca1d0 running natively: "
                 "the notice-cell table built by 0x5bf8f0 (CRT qsort 0x6e88bc), the 16 m unit-cell map filled by native "
                 "placement 0x5c0df0 in the supplied arrival order and native moves 0x5c11d0, then the acquisition "
                 "scan 0x5ca5a0; versus production GameWorld.notice_units_near through UnitAI._notice_candidates "
                 "(registered world, coarse buckets filled in the same arrival and move order) and "
                 "UnitAI.player_perceive.",
        "stubs": ["AI-map occupancy stamp 0x5b6a80 = success (both placement and moves)",
                  "CRT rand 0x6e77b7 = 0; the refresh countdown is reset every tick (remake: ai_near_t cleared)",
                  "empty unit-cell map of the supplied size with the fixture list block size",
                  "terrain sight ray 0x5bc3e0 = 1 (remake: GameWorld.sight_ray)",
                  "senses, flat ground and zero eye height as in perception_ticks",
                  "debug log stream operators", "CRT malloc/free and CPlex block allocator"],
        "limits": "One watcher; arrival order is supplied rather than produced by spawning, saving or loading; "
                  "the 8..11-tick refresh interval and its random draw are not compared. Candidate lists are "
                  "compared in native list order (head first); noticed lists as sorted indices.",
        "tolerances": {},
    },
}
STEP_COUNTS = {"perception_ticks": "ticks", "perception_candidates": "ticks"}


ASTRAL_CONTRACTS = {
    "perception_group": dict(
        CONTRACTS["perception_group"],
        entry=["0x46cca0", "0x46db40", "0x4688b0", "0x597590"],
        scope="Lost in Astral group evaluator 0x46db40 (UnitSee 0x5d, GroupSee 0x5e, PlayerSee 0xa5, "
              "GroupCross 0x5b) with sorted-set insertion 0x4688b0, list merge 0x4689b0, the player "
              "visible-group update 0x597590 and the expression evaluator 0x46cca0 (GroupSize, GroupHas, Any, "
              "Every, IsAlive, IsDead, IsUnitVisible 0xe5 via 0x466560) reading SUPPLIED AI noticed lists "
              "(actor +0x240 -> +0xa94) and corpse lists (+0xab0), versus ScriptVM._eval with "
              "UnitAI.can_notice_with answering exactly the same (watcher, target) pairs.",
        stubs=["supplied noticed and corpse list contents per actor (remake: can_notice_with true exactly for "
               "noticed+corpse pairs; every actor within the watchers' sight radius)",
               "supplied script groups (built by native insertion, i.e. sorted sets)",
               "player zero's unit map (+0x40, one hash bucket) = supplied player_units (remake: controller 0)",
               "player zero lookup 0x4e6c40", "actor type/death/release accessors",
               "CRT operator new/free 0x5ffa7b/0x5ecb7c (CPlex 0x5fed90 runs natively)",
               "CRT thread-local single-byte locale",
               "empty clairvoyance extra-visible group (+0x50f8)"]),
}


def contracts(campaign):
    if campaign == "original":
        return dict(CONTRACTS)
    # Only layer 1 is address-qualified for Lost in Astral; its perception
    # update 0x514d70 is identified but not qualified (see the docs).
    return dict(ASTRAL_CONTRACTS) if campaign == "lost_in_astral" else {}


def call(name, *args):
    return {"call": name, "args": list(args)}


def unit(i):
    return {"unit": i}


GROUP_CALLS = {"UnitSee", "GroupSee", "PlayerSee", "GroupCross", "GroupAdd", "GroupSub"}

# Layer-1 world. 0 NPC watcher, 1-2 living heroes, 3 dead hero, 4-5 guards,
# 6 bystander. Heroes keeps its corpse, as the original deployment group does.
A, H1, H2, H3, G1, G2, B = range(7)


def world(**changes):
    rows = [
        {"side": 1},
        {"side": 0, "party": True},
        {"side": 0, "party": True},
        {"side": 0, "party": True, "dead": True},
        {"side": 1},
        {"side": 1},
        {"side": 2},
    ]
    units = []
    for i, row in enumerate(rows):
        dead = row.pop("dead", False)
        units.append({"uid": i + 1, "pos": [i * 1.5, (i % 3) * 2.0], "hp": 0 if dead else 50, "max_hp": 50,
                      "dead": dead, **row, "noticed": [], "corpses": []})
    for index, fields in changes.items():
        units[int(index[1:])].update(fields)
        if fields.get("dead"):
            units[int(index[1:])]["hp"] = 0
    return {"units": units, "groups": {"Heroes": [H1, H2, H3], "guards": [G1, G2]}, "player_units": [H1, H2]}


VARIANTS = {
    "empty": world(),
    "npc_sees_hero": world(u0={"noticed": [H1]}),
    "npc_sees_both_reversed": world(u0={"noticed": [H2, H1]}),
    "npc_duplicate_entry": world(u0={"noticed": [H1, H1, H2]}),
    "npc_list_holds_corpse": world(u0={"noticed": [H3, H1]}),
    "npc_sees_bystander": world(u0={"noticed": [B]}),
    "dead_npc_retained_list": world(u0={"noticed": [H1], "dead": True}),
    "guards_split": world(u4={"noticed": [H1]}, u5={"noticed": [H2, A]}),
    "dead_guard_retained_list": world(u4={"noticed": [B]}, u5={"noticed": [H1], "dead": True}),
    "heroes_see_npc_and_guard": world(u1={"noticed": [A]}, u2={"noticed": [G1, B]}),
    "hero_corpse_list": world(u1={"noticed": [A], "corpses": [G2]}, u5={"dead": True}),
    "hero_list_holds_corpse": world(u2={"noticed": [G2, A]}, u5={"dead": True}),
    "dead_hero_retained_list": world(u3={"noticed": [A, G1]}),
}


def expressions():
    heroes, guards, player = {"group": "Heroes"}, {"group": "guards"}, 0
    rows = {
        # Authored base-campaign shapes (see the family doc for counts).
        "size_cross_unitsee_heroes": call("GroupSize", call("GroupCross", call("UnitSee", unit(A)), heroes)),
        "size_cross_groupsee_heroes": call("GroupSize", call("GroupCross", call("GroupSee", guards), heroes)),
        "size_cross_heroes_groupsee": call("GroupSize", call("GroupCross", heroes, call("GroupSee", guards))),
        "size_cross_playersee_guards": call("GroupSize", call("GroupCross", call("PlayerSee", player), guards)),
        "size_cross_groupsee_heroes_guards": call("GroupSize", call("GroupCross", call("GroupSee", heroes), guards)),
        "has_groupsee_heroes_npc": call("GroupHas", call("GroupSee", heroes), unit(A)),
        # Group values and the remake fast paths.
        "cross_unitsee_heroes": call("GroupCross", call("UnitSee", unit(A)), heroes),
        "cross_heroes_unitsee": call("GroupCross", heroes, call("UnitSee", unit(A))),
        "unitsee": call("UnitSee", unit(A)),
        "unitsee_missing": call("UnitSee", unit(-1)),
        "groupsee_guards": call("GroupSee", guards),
        "groupsee_heroes": call("GroupSee", heroes),
        "cross_groupsee_heroes": call("GroupCross", call("GroupSee", guards), heroes),
        "playersee": call("PlayerSee", player),
        "playersee_other_player": call("PlayerSee", 1),
        "has_unitsee_hero": call("GroupHas", call("UnitSee", unit(A)), unit(H1)),
        "has_unitsee_corpse": call("GroupHas", call("UnitSee", unit(A)), unit(H3)),
        "size_unitsee": call("GroupSize", call("UnitSee", unit(A))),
        "any_groupsee_alive": call("Any", {"iterator": "i"}, call("GroupSee", guards), call("IsAlive", {"iterator": "i"})),
        "every_unitsee_alive": call("Every", {"iterator": "i"}, call("UnitSee", unit(A)), call("IsAlive", {"iterator": "i"})),
        "any_heroes_seen": call("Any", {"iterator": "h"}, heroes, call("GroupHas", call("UnitSee", unit(A)), {"iterator": "h"})),
    }
    for name, index in [("npc", A), ("guard", G1), ("dead_guard", G2), ("bystander", B), ("hero", H1)]:
        rows[f"has_playersee_{name}"] = call("GroupHas", call("PlayerSee", player), unit(index))
        rows[f"visible_{name}"] = call("IsUnitVisible", unit(index))
    rows["visible_missing"] = call("IsUnitVisible", unit(-1))
    return rows


def unit_row(i, pos, **fields):
    row = {"uid": i + 1, "pos": list(pos), "hp": 50, "max_hp": 50, "dead": False, "side": 1 if i == 0 else 0,
           "party": i != 0, "noticed": [], "corpses": []}
    row.update(fields)
    return row


def observer(**changes):
    row = {"sight": 10.0, "sight_factor": 1.0, "life": 0.0, "cone_half": 1.0, "peripheral": 0.0,
           "facing": 0.0, "hostile_sides": []}
    row.update(changes)
    return row


TRIGGERS = {
    "cross": call("GroupSize", call("GroupCross", call("UnitSee", unit(0)), {"group": "Heroes"})),
    "cross_fastpath": call("GroupSize", call("GroupCross", {"group": "Heroes"}, call("UnitSee", unit(0)))),
    "has": call("GroupHas", call("UnitSee", unit(0)), unit(1)),
}


def ticks_input(heroes, path, trigger="cross", obs=None, rays=None, deaths=None, extra=None):
    """path: per tick hero-1 position; extra: per tick {index: pos} for others."""
    units = [unit_row(0, [0, 0], life_detect=0.0)] + [unit_row(i, pos, **fields) for i, (pos, fields) in
                                                      enumerate(heroes, start=1)]
    ticks = []
    for t, pos in enumerate(path):
        tick = {"positions": {"1": list(pos)}} if pos is not None else {}
        for index, value in ((extra or [{}] * len(path))[t]).items():
            tick.setdefault("positions", {})[str(index)] = list(value)
        if rays and rays[t]:
            tick["rays"] = {str(k): v for k, v in rays[t].items()}
        if deaths and deaths[t]:
            tick["dead"] = deaths[t]
        ticks.append(tick)
    return {"units": units, "groups": {"Heroes": list(range(1, len(units)))},
            "player_units": list(range(1, len(units))), "watcher": 0,
            "observer": obs or observer(), "trigger": TRIGGERS[trigger], "ticks": ticks}


CENTRE = (104.0, 104.0)   # cell (6, 6) of 16 m; every query stays inside the map


def candidates_input(positions, arrivals, ticks, sight=25.0, life=0.0, grid_cells=16):
    """positions[0] is the watcher; ticks: [{"moves": [[i, [x, y]], ...], "dead": [...]}]."""
    units = [unit_row(0, positions[0], life_detect=0.0)] + [unit_row(i, pos) for i, pos in
                                                           enumerate(positions[1:], start=1)]
    return {"units": units, "groups": {"Heroes": list(range(1, len(units)))},
            "player_units": list(range(1, len(units))), "watcher": 0, "grid_cells": grid_cells,
            "arrivals": list(arrivals), "observer": observer(sight=sight, life=life, cone_half=3.0),
            "trigger": TRIGGERS["cross"], "ticks": ticks}


def cell_point(dx, dy, ox=0.0, oy=0.0):
    return [CENTRE[0] + 16 * dx + ox, CENTRE[1] + 16 * dy + oy]


def candidate_scenarios(seed, fuzz):
    rows = {}
    # One unit per D <= 1 cell (equal distances: the unstable native sort).
    ring = [(dx, dy) for dy in range(-2, 3) for dx in range(-2, 3) if not (abs(dx) == 2 and abs(dy) == 2)]
    positions = [list(CENTRE)] + [cell_point(dx, dy, 3, -2) for dx, dy in ring]
    rows["equal_distance_cells"] = candidates_input(positions, range(len(positions)), [{}])
    rows["equal_distance_cells_reversed_arrival"] = candidates_input(
        positions, reversed(range(len(positions))), [{}])
    # Several arrivals in one cell; moving out and back makes a new arrival.
    crowd = [list(CENTRE)] + [cell_point(0, 0, -6 + i, 3 - i) for i in range(5)] + [cell_point(1, 0, 2, 2)]
    rows["one_cell_arrivals"] = candidates_input(crowd, [0, 3, 1, 5, 2, 4, 6], [
        {}, {"moves": [[3, cell_point(1, 0, -3, 1)]]}, {"moves": [[3, cell_point(0, 0, 4, 4)]]},
        {"moves": [[6, cell_point(0, 0, 0, 7)], [1, cell_point(-1, 0, 5, 0)]]}, {"dead": [2]}, {}])
    # The regression layout of tools/tests/notice_candidate_order.gd.
    layout = [[104, 104], [105, 104], [88, 88], [120, 120], [100, 106], [136, 104], [72, 104], [104, 72],
              [120, 104], [89, 90], [152, 104], [168, 104]]
    rows["mixed_cells"] = candidates_input(layout, range(len(layout)), [
        {}, {"moves": [[2, [110, 99]]]}, {"dead": [8]}, {"moves": [[1, [105, 120]], [1, [105, 104]]]}])
    # The watcher crosses cells; nearest-even cell boundaries (x = 112).
    rows["watcher_moves"] = candidates_input(layout, [5, 3, 0, 1, 2, 4, 6, 7, 8, 9, 10, 11], [
        {}, {"moves": [[0, [111.75, 104]]]}, {"moves": [[0, [112, 104]]]}, {"moves": [[0, [128.25, 90]]]},
        {"moves": [[0, [104, 104]], [4, [112, 112]]]}], sight=12.0)
    # Sense radii choose the cells: sight 6 (D <= 0), life sense 40 (D <= 2).
    rows["small_sight"] = candidates_input(layout, range(len(layout)), [{}], sight=6.0)
    rows["life_sense_cells"] = candidates_input(layout, range(len(layout)), [{}], sight=6.0, life=40.0)
    rng = random.Random(seed ^ 0xce115)
    for trial in range(fuzz):
        count = rng.randint(4, 14)
        positions = [list(CENTRE)] + [[round(CENTRE[0] + rng.uniform(-44, 44), 2),
                                       round(CENTRE[1] + rng.uniform(-44, 44), 2)] for _ in range(count)]
        arrivals = list(range(len(positions)))
        rng.shuffle(arrivals)
        ticks = []
        current = [list(p) for p in positions]
        for _ in range(6):
            tick = {}
            for _ in range(rng.randint(0, 3)):
                i = rng.randrange(len(current))
                current[i] = [round(min(max(current[i][0] + rng.uniform(-20, 20), 60.0), 148.0), 2),
                              round(min(max(current[i][1] + rng.uniform(-20, 20), 60.0), 148.0), 2)]
                tick.setdefault("moves", []).append([i, list(current[i])])
            if rng.random() < 0.2:
                tick["dead"] = [rng.randrange(1, len(current))]
            ticks.append(tick)
        rows[f"seeded_{trial:03}"] = candidates_input(
            positions, arrivals, ticks, sight=rng.choice([6.0, 10.0, 25.0, 40.0]),
            life=rng.choice([0.0, 0.0, 12.0, 30.0]))
    return rows


def scenarios(seed=20261021, fuzz=12):
    rows = []

    def add(kind, name, inputs):
        rows.append({"id": f"{kind}/{name}", "kind": kind, "inputs": inputs})

    for variant, fixture in VARIANTS.items():
        for name, expression in expressions().items():
            add("perception_group", f"{variant}/{name}", dict(fixture, expression=expression))

    hero = [([20, 0], {})]
    walk = [[20, 0], [12, 0], [10, 0], [9.5, 0], [10.25, 0], [10.5, 0], [10.75, 0], [12, 0], [30, 0], [100, 0]]
    for hostile in [False, True]:
        sides = [0] if hostile else []
        for trigger in TRIGGERS:
            add("perception_ticks", f"approach_retreat_hostile{int(hostile)}_{trigger}",
                ticks_input(hero, walk, trigger, observer(hostile_sides=sides)))
        # Circle at 5 m: noticed in the cone, then behind the watcher.
        circle = [[5, 0], [3.25, 3.75], [1.75, 4.75], [-2.5, 4.25], [-5, 0], [-2.5, -4.25], [4.75, -1.5], [8, 0]]
        add("perception_ticks", f"circle_behind_hostile{int(hostile)}",
            ticks_input([([1.75, 4.75], {})], [[1.75, 4.75]] + circle, obs=observer(hostile_sides=sides)))
        # Hero dies in full view, then the corpse stays there.
        add("perception_ticks", f"hero_dies_in_view_hostile{int(hostile)}",
            ticks_input([([5, 0], {})], [[5, 0]] * 5, obs=observer(hostile_sides=sides),
                        deaths=[None, None, [1], None, None]))
        # Life sense beyond the sight radius, behind the watcher.
        add("perception_ticks", f"life_sense_beyond_sight_hostile{int(hostile)}",
            ticks_input([([-30, 0], {"life_detect": 1.0})], [[-30, 0], [-14, 0], [-12, 0], [-9, 0], [-12, 0], [-16, 0]],
                        obs=observer(life=15.0, hostile_sides=sides)))
        # Terrain blocks the ray inside the cone but peripheral range covers it.
        add("perception_ticks", f"peripheral_blocked_ray_hostile{int(hostile)}",
            ticks_input([([2, 3], {})], [[2, 3], [2, 3], [0, 3], [0, -3], [-1, 3]],
                        obs=observer(peripheral=6.0, hostile_sides=sides),
                        rays=[{1: 0.0}] * 5))
        add("perception_ticks", f"ray_half_hostile{int(hostile)}",
            ticks_input([([20, 0], {})], [[20, 0], [6, 0], [4.5, 0], [6, 0], [12, 0]],
                        obs=observer(hostile_sides=sides), rays=[{1: 0.5}] * 5))
        # Crawling hero (visibility 0.5) and low detectability.
        add("perception_ticks", f"crawling_hero_hostile{int(hostile)}",
            ticks_input([([8, 0], {"visibility": 0.5, "detect": 0.75})],
                        [[8, 0], [4, 0], [3.5, 0], [3.875, 0], [3.9375, 0], [5, 0]],
                        obs=observer(hostile_sides=sides)))
        # Watcher dies with the hero noticed (no update while dead, declared).
        add("perception_ticks", f"watcher_dies_hostile{int(hostile)}",
            ticks_input([([5, 0], {})], [[5, 0], [5, 0], [5, 0], [20, 0]], obs=observer(hostile_sides=sides),
                        deaths=[None, [0], None, None]))
        # Two heroes; only the first moves away.
        add("perception_ticks", f"two_heroes_hostile{int(hostile)}",
            ticks_input([([3, 0], {}), ([4, 1], {})], [[3, 0], [3, 0], [11, 0], [25, 0], [25, 0]],
                        obs=observer(hostile_sides=sides),
                        extra=[{}, {}, {}, {2: [4, 9]}, {2: [12, 0]}]))
    # Exact thresholds: sight distance 10 and retention 10.5 (dyadic values).
    add("perception_ticks", "exact_thresholds", ticks_input(hero, [[10, 0], [9.75, 0], [10.5, 0], [10.4375, 0], [10.5, 0]]))
    add("perception_ticks", "first_notice_from_outside_cone",
        ticks_input([([3, 6], {})], [[3, 6], [3, 5], [4, 4], [5, 3], [6, 2]]))

    for name, inputs in candidate_scenarios(seed, fuzz).items():
        add("perception_candidates", name, inputs)

    rng = random.Random(seed ^ 0x5ee5)
    for trial in range(fuzz):
        obs = observer(sight=rng.choice([6.0, 8.5, 10.0, 15.0]), sight_factor=rng.choice([1.0, 0.75, 0.5]),
                       life=rng.choice([0.0, 0.0, 4.0, 9.0]), cone_half=rng.choice([0.5, 1.0, 1.5]),
                       peripheral=rng.choice([0.0, 0.0, 2.5, 5.0]), facing=rng.choice([0.0, 1.0, 2.5, -2.0]),
                       hostile_sides=rng.choice([[], [0]]))
        count = rng.choice([1, 2])
        heroes = [([round(rng.uniform(-12, 12), 2), round(rng.uniform(-12, 12), 2)],
                   {"visibility": rng.choice([1.0, 0.5, 0.75]), "detect": rng.choice([1.0, 0.75]),
                    "life_detect": rng.choice([1.0, 0.5])}) for _ in range(count)]
        length = 16
        positions = [[pos for pos, _ in heroes]]
        for _ in range(length - 1):
            positions.append([[round(x + rng.uniform(-2, 2), 2), round(y + rng.uniform(-2, 2), 2)]
                              for x, y in positions[-1]])
        rays = [{i: rng.choice([1.0, 1.0, 1.0, 0.5, 0.0]) for i in range(1, count + 1)} for _ in range(length)]
        deaths = [None] * length
        if rng.random() < 0.4:
            deaths[rng.randrange(4, length)] = [1]
        add("perception_ticks", f"seeded_{trial:03}",
            ticks_input(heroes, [p[0] for p in positions], rng.choice(list(TRIGGERS)), obs, rays, deaths,
                        [{i + 2: p[i + 1] for i in range(count - 1)} for p in positions]))
    return rows


def _check_group_state(state):
    if set(state) == {"count", "members"}:
        return (type(state["count"]) is int and isinstance(state["members"], list)
                and all(type(i) is int and i >= 0 for i in state["members"])
                and state["members"] == sorted(state["members"]) and state["count"] >= len(set(state["members"])))
    return (set(state) == {"truth", "value_bits"} and type(state["truth"]) is bool
            and type(state["value_bits"]) is int and 0 <= state["value_bits"] <= 0xffffffff)


def validate(case, steps, role):
    for step in steps:
        state = step["state"]
        if case["kind"] == "perception_group":
            grouped = case["inputs"]["expression"]["call"] in GROUP_CALLS
            ok = _check_group_state(state) and (("members" in state) == grouped)
        elif case["kind"] == "perception_candidates":
            count = len(case["inputs"]["units"])
            ok = (set(state) == {"count_bits", "fired", "noticed", "candidates"}
                  and isinstance(state["candidates"], list) and len(set(state["candidates"])) == len(state["candidates"])
                  and all(type(i) is int and 0 < i < count for i in state["candidates"])
                  and isinstance(state["noticed"], list) and state["noticed"] == sorted(set(state["noticed"]))
                  and all(type(i) is int and 0 < i < count for i in state["noticed"]))
        else:
            ok = (set(state) == {"count_bits", "fired", "noticed"} and type(state["fired"]) is bool
                  and type(state["count_bits"]) is int and 0 <= state["count_bits"] <= 0xffffffff
                  and isinstance(state["noticed"], list)
                  and all(type(i) is int and 0 < i < len(case["inputs"]["units"]) for i in state["noticed"])
                  and state["noticed"] == sorted(set(state["noticed"])))
        if not ok:
            raise ValueError(f"{role} {case['id']} has an invalid {case['kind']} observation")


# ---------------------------------------------------------------- authored
# Perception condition trees from this installation's MOBs. Only identifiers
# are bound (to fixture actors/groups); no text is copied. Each perception
# condition is evaluated on its own against supplied perception snapshots.
AUTHORED_SIGNATURES = {"UnitSee": "u", "GroupSee": "g", "PlayerSee": "n", "GroupCross": "gg",
                       "GroupHas": "gu", "GroupSize": "g", "IsUnitVisible": "u", "Not": "n",
                       "IsGreater": "nn", "IsLess": "nn", "IsEqual": "nn"}
PERCEPTION_CALLS = {"UnitSee", "GroupSee", "PlayerSee", "IsUnitVisible"}


def _uses_perception(expression):
    return isinstance(expression, dict) and "call" in expression and (
        expression["call"] in PERCEPTION_CALLS or any(_uses_perception(a) for a in expression["args"]))


def _authored_tree(expression, actors, groups, kind="n"):
    if kind in ("u", "g"):
        if not isinstance(expression, dict) or "symbol" not in expression:
            if kind == "g" and isinstance(expression, dict) and expression.get("call") in GROUP_CALLS:
                return _authored_tree(expression, actors, groups, "n")
            raise ValueError("dynamic " + ("group" if kind == "g" else "actor"))
        name = expression["symbol"]
        if kind == "g":
            groups.setdefault(name, len(groups))
            return {"group": name}
        if name == "NULL":
            return {"unit": -1}
        actors.setdefault(name, len(actors))
        return {"actor": name}
    if isinstance(expression, (int, float)):
        return expression
    name = expression.get("call")
    if name not in AUTHORED_SIGNATURES or len(AUTHORED_SIGNATURES[name]) != len(expression["args"]):
        raise ValueError("call:" + str(name))
    return {"call": name, "args": [_authored_tree(a, actors, groups, k)
                                   for a, k in zip(expression["args"], AUTHORED_SIGNATURES[name])]}


def _authored_world(tree, actors, groups):
    """Bound actors, then 2 living + 1 dead hero, then 1 living + 1 dead member per group."""
    units, index = [], {}
    for name in actors:
        index[name] = len(units)
        units.append({"side": 1})
    heroes = [len(units), len(units) + 1, len(units) + 2]
    units += [{"side": 0, "party": True}, {"side": 0, "party": True}, {"side": 0, "party": True, "dead": True}]
    members = {}
    for name in groups:
        if name == "Heroes":
            continue
        members[name] = [len(units), len(units) + 1]
        units += [{"side": 1}, {"side": 1, "dead": True}]
    rows = []
    for i, row in enumerate(units):
        dead = row.pop("dead", False)
        rows.append({"uid": i + 1, "pos": [i * 1.25, (i % 4) * 1.5], "hp": 0 if dead else 50, "max_hp": 50,
                     "dead": dead, "noticed": [], "corpses": [], **row})
    named = {name: (heroes if name == "Heroes" else members[name]) for name in groups}
    named.setdefault("Heroes", heroes)

    def bind(e):
        if isinstance(e, dict) and "actor" in e:
            return {"unit": index[e["actor"]]}
        if isinstance(e, dict) and "call" in e:
            return {"call": e["call"], "args": [bind(a) for a in e["args"]]}
        return e

    return rows, named, heroes, bind(tree)


def _authored_snapshots(rows, heroes):
    living = [i for i, r in enumerate(rows) if not r["dead"]]
    others = [i for i in range(len(rows)) if i not in heroes]
    alive_heroes = [h for h in heroes if not rows[h]["dead"]]
    dead_hero = [h for h in heroes if rows[h]["dead"]]
    dead_others = [i for i in others if rows[i]["dead"]]
    snapshots = {}

    def snap(name, fill):
        copy = [dict(r, noticed=[], corpses=[]) for r in rows]
        fill(copy)
        snapshots[name] = copy

    snap("nothing_noticed", lambda c: None)

    def all_living(c):
        for i in others:
            if not c[i]["dead"]:
                c[i]["noticed"] = list(alive_heroes)
        for h in alive_heroes:
            c[h]["noticed"] = [i for i in others if i in living]

    snap("living_mutual", all_living)

    def corpses(c):
        for i in others:
            if not c[i]["dead"]:
                c[i]["noticed"] = list(dead_hero)
        for h in alive_heroes:
            c[h]["corpses"] = list(dead_others)

    snap("corpses_only", corpses)

    def dead_watchers(c):
        for i in others + dead_hero:
            if c[i]["dead"]:
                c[i]["noticed"] = list(alive_heroes) if i in others else [j for j in others if j in living]

    snap("dead_watchers_retain", dead_watchers)
    return snapshots


def authored(game_dir, limit=120):
    """Rows for authored perception conditions; (rows, summary). No outcomes."""
    from collections import Counter
    from pathlib import Path
    from campaign_quests import Reader, script_bytes
    rows, skipped, lists = [], Counter(), 0
    for path in sorted((Path(game_dir) / "maps").glob("*.mob")):
        text = script_bytes(path.read_bytes())
        if not text:
            continue
        try:
            blocks = Reader(text.decode("cp1251")).blocks()
        except ValueError:
            skipped["parse"] += 1
            continue
        for script, block, conditions in blocks:
            selected = [(k, c) for k, c in enumerate(conditions) if _uses_perception(c)]
            if not selected:
                continue
            if limit and lists >= limit:
                skipped["limit"] += 1
                continue
            lists += 1
            for k, condition in selected:
                actors, groups = {}, {}
                try:
                    tree = _authored_tree(condition, actors, groups)
                except ValueError as exc:
                    skipped[str(exc)] += 1
                    continue
                units, named, heroes, bound = _authored_world(tree, actors, groups)
                for snapshot, fixture in _authored_snapshots(units, heroes).items():
                    rows.append({"id": f"perception_group/authored/{path.stem}/{script}/block{block}/cond{k}/{snapshot}",
                                 "kind": "perception_group",
                                 "source": {"mob": path.name, "script": script, "block": block, "condition": k,
                                            "actor_bindings": actors, "group_bindings": groups},
                                 "inputs": {"units": fixture, "groups": named, "player_units": [h for h in heroes if not units[h]["dead"]],
                                            "expression": bound}})
    summary = {"scope": "Authored perception conditions evaluated one at a time with supplied noticed/corpse lists.",
               "condition_lists": lists, "rows": len(rows), "skipped": dict(sorted(skipped.items()))}
    return rows, summary


if __name__ == "__main__":
    # Writes replay inputs (core family rows + authored rows) for
    # `run.py --replay-inputs`; MOB-derived inputs stay out of the repository.
    import argparse
    import json
    from pathlib import Path
    from cases import make_inputs
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--case", default="perception_")
    parser.add_argument("--campaign", choices=["original", "lost_in_astral"], default="original")
    args = parser.parse_args()
    inputs = make_inputs(pattern=args.case, campaign=args.campaign)
    extra, summary = authored(args.game_dir, args.limit)
    inputs["scenarios"].extend(extra)
    inputs["authored_perception"] = summary
    args.output.write_text(json.dumps(inputs, indent=1) + "\n")
    print(json.dumps(summary))
