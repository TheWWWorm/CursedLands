"""Original NPC AI decisions executed from the pinned base executable.

Every observation is produced by the original routines named in
cases_ext_npc_ai.py. Python only lays out records and supplies the declared
boundaries (debug-log streams, CRT allocation, dead/type virtual getters,
ranged-weapon and danger-cell predicates, motivation bodies). It never
evaluates a priority, suspicion or score formula itself.
"""
import struct

from unicorn.x86_const import UC_X86_REG_ECX, UC_X86_REG_EIP

WORLD = 0x7aff50
FRIENDS = WORLD + 0x12c64          # diplomacy friend mask per side (0x7c2bb4)
CONFIG = 0x7c53e8                  # ai.reg [Logic]/[RPG] block filled by 5ce0f0
CONFIG_KEYS = {"GuardStayTime": 0x04, "SentryStayTime": 0x08, "GuardRadius": 0x14,
               "CallForHelpRadius": 0x18, "CallForHelpRadiusDefault": 0x1c,
               "RangedRunDist": 0x28, "RangedAttackDist": 0x2c, "DamageLevelRunLimit": 0x54}
GRID_SEARCH, GRID_COUNTS, GRID_OFFSETS = 0x7c2fc8, 0x7c2fb4, 0x7c2fec
UNIT_GRID_OWNER = 0x7b01e4         # ECX of the unit-grid query 5c0bd0
AI_OFFSET = 0x980                  # AI record inside the creature controller
PERCEPTION = 0xd0                  # perception record inside the AI
DANGER_SENTINEL = 0xc4a42000       # -1313.0, "no kept danger point"
# Motivation virtual tables (13 slots: +0x10 priority, +0x14 tick,
# +0x18 enter, +0x1c leave, +0x20 type).
VT_GUARD, VT_SENTRY, VT_FOLLOW, VT_SUSPECTION = 0x73d128, 0x73d190, 0x73d1c4, 0x73d1f8
VT_AGGRESSION, VT_CORPSE, VT_FEAR, VT_PATROL = 0x73d260, 0x73d294, 0x73ff8c, 0x73ff40
MOTIVATION_TYPES = {0: "guard", 1: "patrol", 2: "sentry", 3: "suspection", 4: "aggression",
                    5: "corpse", 6: "player", 7: "fear", 8: "tamed", 10: "follow"}


def bits(value):
    return struct.unpack("<I", struct.pack("<f", value))[0]


def signed(value):
    return struct.unpack("<i", struct.pack("<I", value & 0xffffffff))[0]


class Rig:
    """Native world fixture: units, creature controllers, AI records."""

    def __init__(self, o, case):
        self.o = o
        self.units = []
        self.dead = []
        self.code = o.alloc(0x400)
        self._code_at = self.code
        # Fixture-only virtual getters.
        self.ret0 = self.stub(b"\x31\xc0\xc3")                          # xor eax,eax; ret
        self.ret4 = self.stub(b"\x31\xc0\xc2\x04\x00")                  # xor eax,eax; ret 4
        self.unit_kind = self.stub(b"\xb8\x50\x00\x00\x00\xc3")         # unit object kind 0x50
        self.creature_kind = self.stub(b"\xb8\x3e\x00\x00\x00\xc3")     # non-hero controller kind
        self.dead_getter = self.stub(b"\x8b\x81\xf0\x05\x00\x00\xc3")  # mov eax,[ecx+0x5f0]
        self.unit_vt = o.alloc(0x100)
        o.write(self.unit_vt + 0x10, self.ret0)       # reference release: fixtures are never freed
        o.write(self.unit_vt + 0x30, self.unit_kind)
        o.write(self.unit_vt + 0xdc, self.dead_getter)
        self.creature_vt = o.alloc(0x100)
        o.write(self.creature_vt + 0x30, self.creature_kind)
        # CRT heap and debug-log boundaries.
        o.hook(0x70056f, lambda: o.ret(o.alloc(max(o.args(1)[0], 4))))
        o.hook(0x700598, lambda: o.ret())
        for address, cleanup in [(0x6fc2dd, 4), (0x6fc986, 4), (0x6fc070, 4), (0x6fc7ba, 8), (0x434fe0, 4)]:
            o.hook(address, lambda c=cleanup: o.ret(o.uc.reg_read(UC_X86_REG_ECX), cleanup=c))
        for address, cleanup in [(0x700930, 0), (0x70099e, 4), (0x700a69, 4), (0x700ab9, 4), (0x6fdf1f, 0)]:
            o.hook(address, lambda c=cleanup: o.ret(o.uc.reg_read(UC_X86_REG_ECX), cleanup=c))
        o.write(0x7c7b58, 0)   # call-for-help debug text disabled
        for key, offset in CONFIG_KEYS.items():
            if key in case.get("config", {}):
                o.floats(CONFIG + offset, case["config"][key])
        self.relations = case.get("relations", [])
        for side in range(32):
            mask = 1 << side
            for a, b, value in self.relations:
                if a == side and value == 0:
                    mask |= 1 << b
                if a == side and value != 0:
                    mask &= ~(1 << b)
            o.write(FRIENDS + side * 4, mask)
        self._grid()

    def stub(self, code):
        at = self._code_at
        self.o.uc.mem_write(at, code)
        self._code_at += (len(code) + 15) & ~15
        return at

    def hostile_mask(self, side):
        mask = 0
        for a, b, value in self.relations:
            if a == side and value == 2:
                mask |= 1 << b
        return mask

    def _grid(self):
        """One 16 m unit-grid cell (0, 0) holding every fixture unit."""
        o = self.o
        o.write(GRID_SEARCH + 0x14, 0)
        o.write(GRID_SEARCH + 0x18, 1)
        counts, offsets = o.alloc(8), o.alloc(4)
        o.write(counts, 0, 1)
        o.write(GRID_COUNTS, counts)
        o.write(offsets, 0)
        o.write(GRID_OFFSETS, offsets)
        grid, cells = o.alloc(0x140), o.alloc(0x60)
        o.write(UNIT_GRID_OWNER + 0x24, grid)
        o.write(grid + 0x128, 1, 1)
        o.write(grid + 0x138, cells - 0x20)
        self.cell_list = cells - 0x20 + 0x20
        self.cell_nodes = []

    def add(self, row):
        o = self.o
        unit, controller = o.alloc(0x600), o.alloc(0xc00)
        o.write(unit, self.unit_vt)
        o.write(unit + 0xc, len(self.units) + 1)
        o.write(unit + 0x240, controller)
        side = int(row.get("side", 1))
        o.write(unit + 0x244, self.hostile_mask(side), 0xffffffff, int(bool(row.get("party", False))), side)
        o.write(unit + 0x324, int(row.get("move_class", 3)))
        o.write(unit + 0x5f0, int(bool(row.get("dead", False))))
        o.write(controller, self.creature_vt)
        o.write(controller + 0x1c, unit)
        o.write(controller + 0x164, 0)
        ai = controller + AI_OFFSET
        o.write(ai, controller)
        o.write(ai + 0x28, 0xffffd8f0)
        o.write(ai + 0x40, 1)
        o.floats(ai + 0x38, float(row.get("help_radius", 10.0)))
        o.floats(ai + 0x4c, 1.0)
        for block in (0x3c, 0x58, 0x74, 0x90):   # perception CList block sizes
            o.write(ai + PERCEPTION + block, 10)
        # Senses read by the hit hook's forced-notice test (5cbc80).
        o.floats(controller + 0x900, float(row.get("visibility", 1.0)))
        o.floats(controller + 0x904, float(row.get("sight_factor", 1.0)))
        o.floats(controller + 0x294, float(row.get("sight", 8.5)))
        o.floats(controller + 0x2a4, float(row.get("life", 0.0)))
        o.floats(controller + 0x2c4, float(row.get("detect", 1.0)))
        o.floats(controller + 0x2d4, float(row.get("life_detect", 1.0)))
        self.units.append(unit)
        self.move(len(self.units) - 1, row["pos"])
        node = o.alloc(12)
        o.write(node, 0, self.cell_nodes[-1] if self.cell_nodes else 0, unit)
        if self.cell_nodes:
            o.write(self.cell_nodes[-1], node)
        else:
            o.write(self.cell_list + 4, node)
        self.cell_nodes.append(node)
        return unit

    def move(self, index, pos):
        p = list(pos) + [0.0] * (3 - len(pos))
        self.o.floats(self.units[index] + 0x1c, *p[:3])

    def set_dead(self, index, dead):
        self.o.write(self.units[index] + 0x5f0, int(bool(dead)))

    def controller(self, index):
        return self.o.ints(self.units[index] + 0x240)[0]

    def ai(self, index):
        return self.controller(index) + AI_OFFSET

    def set_list(self, address, units):
        """Write a CList head (+0 head, +4 tail, +8 count) of unit pointers."""
        o = self.o
        nodes = [o.alloc(12) for _ in units]
        for i, unit in enumerate(units):
            o.write(nodes[i], nodes[i + 1] if i + 1 < len(nodes) else 0, nodes[i - 1] if i else 0, unit)
        o.write(address, nodes[0] if nodes else 0, nodes[-1] if nodes else 0, len(nodes))

    def list_units(self, address):
        out, node = [], self.o.ints(address)[0]
        while node:
            out.append(self.units.index(self.o.ints(node + 8)[0]))
            node = self.o.ints(node)[0]
            if len(out) > 64:
                raise RuntimeError("Corrupt native unit list")
        return out

    def perception(self, index):
        p = self.ai(index) + PERCEPTION
        x, y, level, delta = self.o.ints(p + 0x10, 4)
        return {"level": signed(level), "delta": signed(delta), "point_bits": [x, y],
                "pending": self.o.ints(p + 0xa8 + 8)[0]}

    def pending(self, index):
        """Counters of the perception's delayed sounds (+0xa8 array, 0x18 bytes each)."""
        p = self.ai(index) + PERCEPTION + 0xa8
        base, count = self.o.ints(p + 4, 2)
        return [signed(self.o.ints(base + i * 0x18 + 0xc)[0]) for i in range(count)]

    def suspect(self, index, point, level, delta):
        o = self.o
        at = o.alloc(12)
        p = list(point) + [0.0] * (3 - len(point))
        o.floats(at, *p[:3])
        o.run(0x5cbbe0, self.ai(index) + PERCEPTION, [at, level & 0xffffffff, delta & 0xffffffff])

    def hit(self, index, attacker):
        """Original AI hit hook 5d7e90 (attacker kept, help call, forced notice)."""
        self.o.run(0x5d7e90, self.ai(index), [self.units[attacker] if attacker is not None else 0])

    def help_call(self, index, point):
        o = self.o
        at = o.alloc(12)
        p = list(point) + [0.0] * (3 - len(point))
        o.floats(at, *p[:3])
        o.run(0x5d5990, self.ai(index), [at])

    def motivation(self, vtable, **fields):
        o = self.o
        record = o.alloc(0x40)
        o.write(record, vtable, 1)
        if vtable == VT_FEAR:
            o.floats(record + 8, 10.0, 3.0)
            o.write(record + 0x10, DANGER_SENTINEL)
            o.uc.mem_write(record + 0x28, bytes([int(fields.get("flag", 0))]))
        return record

    def ai_prologue(self, index):
        """5d53b0 up to the motivation choice: perception tick 5cb700 (sound
        list, delayed sounds 5cc9d0, level += delta) and the noticed-hostile
        flag. The perception scan 5caa00 is the declared boundary (no scan)."""
        _slice_to(self.o, 0x5d53b0, self.ai(index), 0x5d547d)


def install_scan_stub(o):
    # 5caa00 (perception scan of the unit grid) is another family's subject;
    # here the noticed list is a supplied input, so the scan adds nothing.
    o.hook(0x5caa00, lambda: o.ret(cleanup=8))


def _slice_to(o, address, this, end):
    from native import STOP
    o.write(0x91ff000, STOP)
    o.uc.reg_write(UC_X86_REG_ECX, this)
    from unicorn.x86_const import UC_X86_REG_ESP
    o.uc.reg_write(UC_X86_REG_ESP, 0x91ff000)
    o.slice(address, end)


def fear(o, case):
    """Fear motivation priority 5d2960 after the AI tick prologue, per tick."""
    rig = Rig(o, case)
    install_scan_stub(o)
    for row in case["units"]:
        rig.add(row)
    me = case["units"][0]
    observer, controller, ai = rig.units[0], rig.controller(0), rig.ai(0)
    for i, row in enumerate(case["units"]):
        if row.get("fighting"):   # AI state 3 (attack) with the observer as target
            o.write(rig.ai(i) + 4, 3)
            o.write(rig.ai(i) + 0x2c, observer)
    o.floats(controller + 0x238, float(me.get("wound", 1.0)))
    for i, part in enumerate(me.get("parts", [])):
        at = controller + 0x1e0 + 0x110 + i * 0xf4
        o.write(at, part["type"])
        o.write(at + 0xe0, part["state"])
        o.floats(at + 0xe4, part["cur"], part["max"], part.get("size", 0.2), part.get("lethal", 0.0))
    if me.get("spell0", False):
        spell = o.alloc(0x50)
        o.write(spell + 0x44, 1)
        o.write(observer + 0x460, spell)
    ranged = bool(me.get("ranged", False))
    o.hook(0x54b6c0, lambda: o.ret(int(ranged)))
    danger = []

    def danger_cell():
        x, y = struct.unpack("<ff", o.uc.mem_read(o.args(1)[0], 8))
        o.ret(int(any(bits(x) == bits(px) and bits(y) == bits(py) for px, py in danger)), cleanup=4)

    o.hook(0x5bbdb0, danger_cell)

    def out_of_contract():
        raise RuntimeError("kiting spot search reached: outside the npc_fear contract")

    o.hook(0x4667f0, out_of_contract)
    rig.set_list(ai + 0x114, [rig.units[i] for i, row in enumerate(case["units"]) if row.get("noticed")])
    fear_record = rig.motivation(VT_FEAR, flag=case["flag"])
    others = {"calm": rig.motivation(VT_SENTRY), "aggression": rig.motivation(VT_AGGRESSION),
              "fear": fear_record, "none": 0}
    def apply(tick, when):
        for event in tick.get("events", []):
            if event.get("when", "after") != when:
                continue
            if event["kind"] == "suspect":
                rig.suspect(0, event["point"], event["level"], event["delta"])
            elif event["kind"] == "hit":
                rig.hit(0, event["by"])

    states = []
    for tick in case["ticks"]:
        for index, pos in tick.get("moves", {}).items():
            rig.move(int(index), pos)
        danger[:] = [tuple(p) for p in tick.get("danger", [])]
        o.write(ai + 0x8c, others[tick.get("current", "calm")])
        o.write(controller + 0x190, 1 if tick.get("walking", "none") != "none" else 0, )
        o.write(controller + 0x1b4, 0)
        apply(tick, "before")
        rig.ai_prologue(0)
        priority = signed(o.run(0x5d2960, fear_record, [ai]))
        r, j = o.ints(fear_record + 8, 2)
        seen = rig.perception(0)
        states.append({"decision_priority": priority, "j_bits": j,
                       "kept_danger": o.ints(fear_record + 0x10)[0] != DANGER_SENTINEL,
                       "level": seen["level"], "delta": seen["delta"], "point_bits": seen["point_bits"],
                       "r_bits": r})
        # End of the AI tick: the hit attacker is held for one AI tick only.
        o.write(ai + 0x30, 0)
        apply(tick, "after")
    return states


def suspicion(o, case):
    """Suspicion records of several units over ticks: original suspicion
    5cbbe0, call for help 5d5990 (unit-grid query, friend filter, delayed
    sound 5cbba0/5ccd40), hit hook 5d7e90 and each unit's AI tick prologue
    (perception tick 5cb700: delayed sounds 5cc9d0, level += delta)."""
    rig = Rig(o, case)
    install_scan_stub(o)
    for row in case["units"]:
        rig.add(row)
    calm = rig.motivation(VT_SENTRY)
    watched = [i for i, row in enumerate(case["units"]) if not row.get("party") and not row.get("dead")]
    for i in watched:
        o.write(rig.ai(i) + 0x8c, calm)

    def apply(tick, when):
        for event in tick.get("events", []):
            if event.get("when", "after") != when:
                continue
            i = int(event.get("unit", 0))
            if event["kind"] == "suspect":
                rig.suspect(i, event["point"], event["level"], event["delta"])
            elif event["kind"] == "help":
                rig.help_call(i, event["point"])
            elif event["kind"] == "hit":
                rig.hit(i, event.get("by"))
                o.write(rig.ai(i) + 0x30, 0)   # attacker held for one AI tick only

    states = []
    for tick in case["ticks"]:
        for index, pos in tick.get("moves", {}).items():
            rig.move(int(index), pos)
        apply(tick, "before")
        for i in watched:
            rig.ai_prologue(i)
        rows = []
        for i in watched:
            seen = rig.perception(i)
            rows.append({"level": seen["level"], "delta": seen["delta"], "point_bits": seen["point_bits"],
                         "pending": rig.pending(i)})
        states.append({"units": rows})
        apply(tick, "after")
    return states


SCORE = 0x5cf9a0


def target_score(o, case):
    """AI option/target score 5cf9a0 (with its damage 522ae0, healing maximum
    524020, has-effect 50f630 and distance 5cfe20 callees), per evaluation."""
    rig = Rig(o, case)
    for row in case["units"]:
        rig.add(row)
    for i, row in enumerate(case["units"]):
        unit, controller = rig.units[i], rig.controller(i)
        o.write(controller + 0x164, 1)   # creature state tested by type 3 (see limits)
        o.uc.mem_write(unit + 0x17e, struct.pack("<hh", int(row["hp"]), int(row["max_hp"])))
        o.uc.mem_write(controller + 0x8e6, struct.pack("<7h", *row.get("armour", [0] * 7)))
        o.floats(controller + 0xa4c, float(row.get("power", 0.0)))
        effects = row.get("effects", [])
        table = o.alloc(max(4, 20 * len(effects)))
        for k, effect in enumerate(effects):
            o.write(table + 20 * k, int(effect))
        o.write(unit + 0x198, table, len(effects))
        for k, part in enumerate(row.get("parts", [])):
            at = controller + 0x1e0 + 0x110 + k * 0xf4
            o.write(at, part["type"])
            o.write(at + 0xe0, part["state"])
            o.floats(at + 0xe4, part["cur"], part["max"], part.get("size", 0.2), part.get("lethal", 0.0))
    output = o.alloc(4)
    wrapper = o.alloc(48)
    code = b"\x8b\xc4" + b"".join(b"\xff\x70" + bytes([offset]) for offset in (0x1c, 0x18, 0x14, 0x10, 0x0c, 0x08, 0x04))
    code += b"\xb8" + struct.pack("<I", SCORE) + b"\xff\xd0"
    code += b"\xd9\x1d" + struct.pack("<I", output) + b"\xc2\x1c\x00"
    o.uc.mem_write(wrapper, code)
    states = []
    for evaluation in case["evals"]:
        option = evaluation["option"]
        record = o.alloc(0x28)
        o.write(record, int(option["type"]))
        o.floats(record + 8, float(option.get("range", 0.0)))
        o.write(record + 0xc, int(option.get("n1", 0)))
        o.floats(record + 0x10, float(option.get("radius", 0.0)))
        o.write(record + 0x14, int(option.get("dur", option.get("effect", 0))))
        o.uc.mem_write(record + 0x1a, struct.pack("<7h", *option.get("v", [0] * 7)))
        members = o.alloc(0x10)
        rig.set_list(members + 4, [rig.units[i] for i in evaluation["list"]])
        caster, candidate = rig.units[evaluation["caster"]], rig.units[evaluation["candidate"]]
        current = rig.units[evaluation["cur"]] if evaluation.get("cur") is not None else 0
        o.run(wrapper, 0, [caster + 0x1c, caster, members, current, candidate,
                           bits(float(evaluation["threshold"])), record])
        states.append({"score_bits": o.ints(output)[0]})
    return states


CAPTURES = {"npc_fear": fear, "npc_suspicion": suspicion, "npc_target_score": target_score}
