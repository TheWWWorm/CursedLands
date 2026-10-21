"""Native quest builtins with extra unit/world fixture fields."""
from native_quests import ADDRESSES, OPS, Expressions

QUERY_OPS = {"Mana": 0x51, "MaxMana": 0x52, "IsNight": 0xaa, "IsInSquare": 0xbb}


def query(o, case):
    fixture = Expressions(o, case["units"], environment=case)
    fixture.opcodes = OPS | QUERY_OPS
    for row, unit in zip(case["units"], fixture.units):
        if row is not None and unit:
            stats = o.ints(unit + 0x170)[0]
            o.floats(stats + 0x34, row.get("mana", 0), row.get("max_mana", 0))
    # The world's night intensity at 0x7affd4 is read directly by opcode 0xaa.
    o.floats(ADDRESSES["original"]["world"] + 0x84, case.get("night", 0))
    command, output = fixture.compile(case["expression"]), o.alloc(4)
    o.run(ADDRESSES[o.campaign]["eval"], command, [fixture.context, fixture.instance, output])
    return [{"value_bits": o.ints(output)[0], "truth": o.number(output) != 0}]


CAPTURES = {"quest_query": query}
