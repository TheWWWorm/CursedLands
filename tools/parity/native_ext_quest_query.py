"""Native quest builtins with extra unit/world/party fixture fields."""
from unicorn.x86_const import UC_X86_REG_ECX
from native_quests import ADDRESSES, OPS, Expressions

QUERY_OPS = {"Mana": 0x51, "MaxMana": 0x52, "IsNight": 0xaa, "IsInSquare": 0xbb,
             "GetPlayer": 0x65, "Sum": 0x6a, "GetAIClass": 0x8f, "GetMercsNumber": 0xd1,
             "GetLootItemsCount": 0xe1, "GetUnitOfPlayer": 0xb4, "GetLeader": 0xe4}
# Builtins returning objects are evaluated by 0x4b56c0 (parameter type 3).
OBJECT_CALLS = {"GetUnitOfPlayer", "GetLeader"}
RECORD = 0x784          # party record stride; unit ID at +0x1c
# Per executable: party-record ID -> actor lookup, global object lookup used by
# GetLeader, CPlex-style block allocator (stdcall) for temporary object slots,
# and the network-session pointer that selects GetLeader's single-player path.
SUPPLIED = {
    "original": {"registry": 0x55fb00, "objects": 0x593aa0, "plex": 0x6fe8af, "network": 0x79b5cc},
    "lost_in_astral": {"registry": 0x4cd680, "objects": 0x4ea290, "plex": 0x5fed90, "network": 0x673c48},
}

class QueryExpressions(Expressions):
    def compile(self, expression, at=None):
        if not any(isinstance(a, dict) and a.get("call") in OBJECT_CALLS for a in expression.get("args", [])):
            return super().compile(expression, at)
        # Object-returning children occupy object slots and bind as type 3.
        o = self.o
        plain = dict(expression, args=[a for a in expression["args"]
                                       if not (isinstance(a, dict) and a.get("call") in OBJECT_CALLS)])
        cmd = super().compile(plain, at)
        children = [a for a in expression["args"] if isinstance(a, dict) and a.get("call") in OBJECT_CALLS]
        if plain["args"]:
            raise ValueError("Object calls must be the only arguments of their parent")
        slots = o.alloc(4 * len(children))
        o.write(cmd + 0x30, slots)
        bindings = o.alloc(12 * len(children))
        for i, child in enumerate(children):
            o.write(bindings + 12 * i, 3, i, super().compile(child))
        o.write(cmd + 0x80, bindings, len(children))
        return cmd


def query(o, case):
    fixture = QueryExpressions(o, case["units"], case.get("variables"), case.get("groups"), environment=case)
    fixture.opcodes = OPS | QUERY_OPS
    for row, unit in zip(case["units"], fixture.units):
        if row is not None and unit:
            stats = o.ints(unit + 0x170)[0]
            o.floats(stats + 0x34, row.get("mana", 0), row.get("max_mana", 0))
            o.write(unit + 0x250, row.get("player", 0))
            o.write(unit + 0x324, row.get("ai_class", 0))
    # The world's night intensity at 0x7affd4 is read directly by opcode 0xaa.
    o.floats(ADDRESSES[o.campaign]["world"] + 0x84, case.get("night", 0))
    supplied = SUPPLIED[o.campaign]
    # Party records live in player zero's record array (+0xa0, count +0xa4).
    party = case.get("party", [])
    by_id, dead = {}, {}
    records = o.alloc(max(1, len(party)) * RECORD)
    for i, row in enumerate(party):
        o.write(records + i * RECORD + 0x1c, row["id"])
        if row.get("unit", -1) >= 0:
            unit = fixture.units[row["unit"]]
            by_id[row["id"]] = unit
            dead[unit] = int(case["units"][row["unit"]]["dead"])
    # Fixture actors share one vtable; slot 0xdc reports each actor's death.
    vt = o.ints(fixture.units[0])[0] if any(fixture.units) else 0
    if vt:
        o.write(vt + 0xdc, 0x1840)
    o.hook(0x1840, lambda: o.ret(dead.get(o.uc.reg_read(UC_X86_REG_ECX), 0)))
    o.hook(supplied["registry"], lambda: o.ret(by_id.get(o.args(1)[0], 0), cleanup=4))
    o.hook(supplied["objects"], lambda: o.ret(by_id.get(o.args(1)[0], 0), cleanup=4))
    o.write(supplied["network"], 0)

    def plex():
        head, count, size = o.args(3)
        # Reserve both header layouts (data at +4 or +8); slots are never freed.
        block = o.alloc(8 + count * size)
        o.write(block, o.ints(head)[0])
        o.write(head, block)
        o.ret(block, cleanup=12)  # stdcall

    o.hook(supplied["plex"], plex)
    o.write(fixture.context + 0x1e4, 16)
    o.write(fixture.player + 0xa0, records, len(party))
    o.write(fixture.player + 0xec, case.get("loot_items", 0))
    command, output = fixture.compile(case["expression"]), o.alloc(4)
    o.run(ADDRESSES[o.campaign]["eval"], command, [fixture.context, fixture.instance, output])
    return [{"value_bits": o.ints(output)[0], "truth": o.number(output) != 0}]


CAPTURES = {"quest_query": query}
