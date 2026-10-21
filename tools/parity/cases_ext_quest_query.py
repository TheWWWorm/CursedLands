"""Quest-condition builtins outside the core predicate family.

Inputs only: no expected values. Several of these builtins are not used by the
authored base campaign; they remain part of the original script language.
"""


def call(name, *args):
    return {"call": name, "args": list(args)}


def contracts(campaign):
    if campaign != "original":
        return {}
    return {"quest_query": {
        "entry": ["0x4b41e0"],
        "scope": "Native expression opcodes 0x51 Mana, 0x52 MaxMana, 0xaa IsNight and 0xbb IsInSquare versus ScriptVM._eval.",
        "stubs": ["supplied unit mana/max-mana stat records", "supplied world night value", "player-zero lookup", "single-player mode"],
        "limits": "Query results only; no mana regeneration, spellcasting or day/night simulation.",
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
    return rows


def validate(case, steps, role):
    for step in steps:
        state = step["state"]
        if (set(state) != {"value_bits", "truth"} or type(state["value_bits"]) is not int
                or not 0 <= state["value_bits"] <= 0xffffffff or type(state["truth"]) is not bool):
            raise ValueError(f"{role} {case['id']} has an invalid quest_query observation")
