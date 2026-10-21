"""Quest-condition builtins outside the core predicate family.

Inputs only: no expected values. Several of these builtins are not used by the
authored base campaign; they remain part of the original script language.
"""


def call(name, *args):
    return {"call": name, "args": list(args)}


ENTRY = {"original": ["0x4b41e0", "0x4b4030", "0x4b56c0", "0x591740"],
         "lost_in_astral": ["0x46cca0", "0x46ee90", "0x46b8d0", "0x4e87d0"]}


def contracts(campaign):
    if campaign not in ENTRY:
        return {}
    return {"quest_query": {
        "entry": ENTRY[campaign],
        "scope": "Native expression opcodes 0x51 Mana, 0x52 MaxMana, 0x65 GetPlayer, 0x6a Sum, 0x8f GetAIClass, 0xaa IsNight, 0xbb IsInSquare, 0xd1 GetMercsNumber, 0xe1 GetLootItemsCount and object opcodes 0xb4 GetUnitOfPlayer / 0xe4 GetLeader (through the native object evaluator, read with GetObjectID) versus ScriptVM._eval.",
        "stubs": ["supplied unit mana/max-mana stat records, player number and AI class", "supplied world night value",
                  "player-zero lookup", "single-player mode", "supplied party records (ID only) and ID-to-actor lookups (base 0x55fb00/0x593aa0, Astral 0x4cd680/0x4ea290)",
                  "actor death accessor (vtable 0xdc)", "temporary object-slot block allocator (base 0x6fe8af, Astral 0x5fed90)",
                  "supplied player-zero loot-item counter", "supplied group membership"],
        "limits": "Query results only; no mana regeneration, spellcasting, day/night simulation, party management or looting.",
        "tolerances": {},
    }}


def scenarios(seed=20261020, fuzz=12):
    rows = []
    unit = {"pos": [0, 0], "hp": 10, "max_hp": 20, "dead": False, "uid": 1, "mana": 7.5, "max_mana": 30}

    def add(name, expression, units=None, **environment):
        rows.append({"id": "quest_query/" + name, "kind": "quest_query",
                     "inputs": {"expression": expression, "units": [dict(unit)] if units is None else units, **environment}})

    for x, y in [(5, 5), (0, 0), (10, 10), (-0.000001, 5), (10.000001, 5), (5, -1), (5, 11)]:
        add(f"in_square_{x}_{y}", call("IsInSquare", x, y, 0, 0, 10, 10), [])
    add("in_square_reversed", call("IsInSquare", 5, 5, 10, 10, 0, 0), [])
    add("in_square_degenerate", call("IsInSquare", 0, 0, 0, 0, 0, 0), [])
    for mana, maximum in [(0, 0), (7.5, 30), (30, 30), (0.1, 1e6)]:
        for name in ["Mana", "MaxMana"]:
            add(f"{name}_{mana}_{maximum}", call(name, {"unit": 0}), [dict(unit, mana=mana, max_mana=maximum)])
            add(f"{name}_dead_{mana}", call(name, {"unit": 0}), [dict(unit, mana=mana, max_mana=maximum, dead=True)])
    add("Mana_missing", call("Mana", {"unit": -1}), [])
    add("MaxMana_missing", call("MaxMana", {"unit": -1}), [])
    add("mana_half_gate", call("IsLess", call("Mana", {"unit": 0}), call("Div", call("MaxMana", {"unit": 0}), 2)))
    for night in [0, 0.25, 0.5, 1]:
        add(f"IsNight_{night}", call("IsNight"), [], night=night)
    for player in [0, 1, 2, 5]:
        add(f"GetPlayer_{player}", call("GetPlayer", {"unit": 0}), [dict(unit, player=player)])
    add("GetPlayer_missing", call("GetPlayer", {"unit": -1}), [])
    for ai_class in [0, 1, 3, 7]:
        add(f"GetAIClass_{ai_class}", call("GetAIClass", {"unit": 0}), [dict(unit, ai_class=ai_class)])
    add("GetAIClass_missing", call("GetAIClass", {"unit": -1}), [])
    for count in [0, 1, 7]:
        add(f"GetLootItemsCount_{count}", call("GetLootItemsCount", 0), [], loot_items=count)
    add("GetLootItemsCount_other_player", call("GetLootItemsCount", 1), [], loot_items=3)
    members = [dict(unit, uid=10 + i, hp=5 + 5 * i, dead=i == 1) for i in range(3)]
    for indices in [[], [0], [0, 1, 2], [2, 0]]:
        suffix = "_".join(map(str, indices)) or "empty"
        groups = {"guards": indices}
        group, iterator = {"group": "guards"}, {"iterator": "g"}
        add(f"Sum_hp_{suffix}", call("Sum", iterator, group, call("HP", iterator)), members, groups=groups)
        add(f"Sum_alive_{suffix}", call("Sum", iterator, group, call("IsAlive", iterator)), members, groups=groups)
        add(f"Sum_literal_{suffix}", call("Sum", iterator, group, 2.5), members, groups=groups)
    # Party slots: the protagonist first, then mercenaries in record order.
    # "unit": -1 keeps a record whose actor is absent from the world.
    hero = dict(unit, uid=100)
    parties = {
        "solo": ([dict(hero)], [0]),
        "solo_dead": ([dict(hero, dead=True)], [0]),
        "two_mercs": ([dict(hero), dict(hero, uid=101), dict(hero, uid=102)], [0, 1, 2]),
        "dead_merc": ([dict(hero), dict(hero, uid=101, dead=True), dict(hero, uid=102)], [0, 1, 2]),
        "dead_hero": ([dict(hero, dead=True), dict(hero, uid=101)], [0, 1]),
        "all_dead": ([dict(hero, dead=True), dict(hero, uid=101, dead=True)], [0, 1]),
        "absent_merc": ([dict(hero), dict(hero, uid=102)], [0, -1, 1]),
    }
    for name, (actors, slots) in parties.items():
        party = [{"id": 500 + i, "unit": slot} for i, slot in enumerate(slots)]
        add(f"GetMercsNumber_{name}", call("GetMercsNumber", 0), actors, party=party)
        # The original builtin takes no parameters and ignores this extra
        # literal. Authored z18q1/z7q3 triggers call GetLeader() with none;
        # the remake indexes a missing argument there (see the family doc).
        add(f"GetLeader_{name}", call("GetObjectID", call("GetLeader", 0)), actors, party=party)
        for k in [-1, 0, 1, 2, 3, 1.4, 1.6]:
            add(f"GetUnitOfPlayer_{name}_{k}", call("GetObjectID", call("GetUnitOfPlayer", 0, k)), actors, party=party)
    add("GetMercsNumber_other_player", call("GetMercsNumber", 1), [dict(hero)], party=[{"id": 500, "unit": 0}])
    add("GetUnitOfPlayer_other_player", call("GetObjectID", call("GetUnitOfPlayer", 1, 0)), [dict(hero)],
        party=[{"id": 500, "unit": 0}])
    return rows


def validate(case, steps, role):
    for step in steps:
        state = step["state"]
        if (set(state) != {"value_bits", "truth"} or type(state["value_bits"]) is not int
                or not 0 <= state["value_bits"] <= 0xffffffff or type(state["truth"]) is not bool):
            raise ValueError(f"{role} {case['id']} has an invalid quest_query observation")
