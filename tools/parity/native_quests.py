"""Construct native command records and execute the original quest evaluator.

No operation below calculates a predicate result. Nested expressions are
evaluated by the executable itself, including its intermediate float stores.
"""
import struct
from unicorn.x86_const import UC_X86_REG_ECX

ADDRESSES = {
    "original": {"eval": 0x4b41e0, "gate": 0x4bb520, "cleanup": 0x4bec80, "body": 0x4bc420,
                 "player": 0x594180, "network": 0x57f440, "string": 0x70099e,
                 "rect": 0x4b1ed0, "circle": 0x4b2070, "world": 0x7aff50,
                 "unit_ground": 0x530280, "object_ground": 0x594220,
                 "program": 0x4b6760},
    "lost_in_astral": {"eval": 0x46cca0, "gate": 0x473b50, "cleanup": 0x46a610, "body": 0x473a70,
                       "player": 0x4e6c40, "network": 0x4de200, "string": 0x412ab0,
                       "rect": 0x4663e0, "circle": 0x466440, "world": 0x6a33d8,
                       "unit_ground": 0x4ae4d0, "object_ground": 0x4e7460,
                       "program": 0x4712c0},
}
OPS = {
    "IsEqual": 0x45, "IsLess": 0x46, "IsGreater": 0x47, "Add": 0x49,
    "Sub": 0x4a, "Mul": 0x4b, "Div": 0x4c, "Not": 0x4d,
    "HP": 0x4f, "MaxHP": 0x50, "DistanceUnitUnit": 0x53,
    "DistanceUnitPoint": 0x54, "GetX": 0x55, "GetY": 0x56,
    "IsAlive": 0x63, "IsDead": 0x64, "GetObjectID": 0x66, "UnitInSquare": 0xbc,
    "IsEqualString": 0x48, "GSGetVar": 0x80, "GetLeverState": 0x90,
    "GroupSize": 0x58, "GroupHas": 0x5c, "Every": 0x68, "Any": 0x69,
    "IsInArea": 0xc5,
    "GetWorldTime": 0xb5, "GetMoney": 0xe2, "HaveItem": 0x7c,
    "WasLooted": 0xe3, "IsUnitBlocked": 0xe6, "GetZ": 0x57,
}


class Expressions:
    def __init__(self, o, units, variables=None, groups=None, areas=None, environment=None):
        self.o = o
        self.opcodes = OPS
        self.hook_start = len(o.hooks)
        self.units = []
        self.dead = {}
        self.types = {}
        self.iterators = {}
        self.groups = {}
        self.areas = {}
        self.global_indices = {}
        environment = environment or {}
        self.context = o.alloc(0x220)
        self.area_records = o.alloc(128 * 24)
        o.write(self.context + 0x198, self.area_records, 0)
        self.instance = o.alloc(0xc0)
        vt = o.alloc(0x100)
        o.write(vt + 0x44, 0x1800)
        o.write(vt + 0x30, 0x1810)
        o.write(vt + 0x10, 0x1820)
        o.hook(0x1800, lambda: o.ret(self.dead[o.uc.reg_read(UC_X86_REG_ECX)]))
        o.hook(0x1810, lambda: o.ret(self.types[o.uc.reg_read(UC_X86_REG_ECX)]))
        # Fixture actors stay alive for the capture; releasing an iterator's
        # reference cannot destroy them. Native assignment and loops run.
        o.hook(0x1820, lambda: o.ret())
        for row in units:
            if row is None:
                self.units.append(0)
                continue
            unit, stats = o.alloc(0x280), o.alloc(0x50)
            o.write(unit, vt)
            o.write(unit + 0xc, row.get("uid", 1))
            o.write(unit + 8, (int(row.get("looted", False)) << 20) | (int(row.get("blocked", False)) << 23))
            o.floats(unit + 0x1c, *row["pos"])
            o.floats(unit + 0x24, row.get("relative_z", 0))
            o.write(unit + 0x170, 0 if row.get("map_object") else stats)
            o.write(stats, vt)
            o.floats(stats + 0x28, row["hp"], row["max_hp"])
            self.dead[stats] = int(row["dead"])
            self.types[unit] = 0x5d if "lever" in row else 0x4b if row.get("map_object") else 0x50
            o.write(unit + 0x238, row.get("lever", 0))
            self.units.append(unit)
        for name, indices in (groups or {}).items():
            members = [self.units[i] for i in indices]
            if any(not member for member in members):
                raise ValueError("Group fixtures require present actor records")
            group, entries = o.alloc(20), o.alloc(max(1, len(members)) * 4)
            if members:
                o.write(entries, *members)
            o.write(group + 4, entries, len(members))
            self.groups[name] = group
        addresses = ADDRESSES[o.campaign]
        # GetWorldTime is opcode b5 and computes (tick * rate + offset) % 24.
        # aa reads the night's intensity, not an hour. A frozen supplied hour
        # gives these predicate fixtures an actual native world-clock input.
        o.write(addresses["world"] + 0x64, 0)
        o.floats(addresses["world"] + 0x20, 0)
        o.floats(addresses["world"] + 0x1c, environment.get("world_time", 0))
        heights = {tuple(struct.unpack("<2f", struct.pack("<2f", *row["pos"]))): row.get("ground", 0)
                   for row in units if row is not None}
        ground_value = o.alloc(4)
        # Supplied terrain heights are a declared boundary. The executable
        # still adds the object's relative Z and stores the query result.
        o.uc.mem_write(0x1830, b"\xd9\x05" + struct.pack("<I", ground_value) + b"\xc2\x08\x00")
        def ground():
            xy = tuple(struct.unpack("<2f", struct.pack("<2I", *o.args(2))))
            o.floats(ground_value, heights.get(xy, 0))
            from unicorn.x86_const import UC_X86_REG_EIP
            o.uc.reg_write(UC_X86_REG_EIP, 0x1830)
        o.hook(addresses["unit_ground"], ground)
        o.hook(addresses["object_ground"], ground)
        for area in areas or []:
            record = self.ensure_area(area["id"], len(area["shapes"]))
            for shape in area["shapes"]:
                kind, values = next(iter(shape.items()))
                words = [struct.unpack("<I", struct.pack("<f", value))[0] for value in values]
                # Native construction stores corners / squares the radius;
                # capacity is supplied so allocator behavior is out of scope.
                o.run(addresses[kind], record, words)
        player, bucket = o.alloc(0x140), o.alloc(4)
        self.player = player
        o.write(player + 0xc0, environment.get("money", 0))
        # HaveItem scans original bag nodes. The owned-unit table is empty;
        # carried quest items and multiplayer ownership are separate contracts.
        head = 0
        for item_id in environment.get("quest_items", []):
            item, node = o.alloc(0x50), o.alloc(12)
            o.write(item + 0x10, 0x3009)
            o.write(item + 0x4c, item_id)
            o.write(node, head, 0, item)
            head = node
        o.write(player + 0xe4, head)
        o.write(player + 0xc8, bucket, bucket + 4)
        head = 0
        # A one-bucket table deliberately exercises native collision traversal.
        # Native hash, string comparison, missing-key fallback and value loads
        # execute normally. Only temporary-string allocation is supplied.
        for key, value in (variables or {}).items():
            node = o.alloc(12)
            o.write(node, head, self.string(key))
            o.floats(node + 8, value)
            head = node
        o.write(bucket, head)
        o.hook(addresses["player"], lambda: o.ret(player if o.args(1)[0] == 0 else 0, cleanup=4))
        o.hook(addresses["network"], lambda: o.ret(0))

        def temporary_string():
            o.write(o.uc.reg_read(UC_X86_REG_ECX), o.args(1)[0])
            o.ret(cleanup=4)

        o.hook(addresses["string"], temporary_string)
        if o.campaign == "original":
            o.hook(0x700930, lambda: o.ret())
        else:
            # Supply CRT thread-local locale storage; the executable's own
            # ASCII comparison still executes. Multibyte locales are excluded.
            thread, locale = o.alloc(0x100), o.alloc(0x200)
            o.write(thread + 0x60, locale)
            o.write(0x6bda2c, locale)
            o.hook(0x5f25dd, lambda: o.ret(thread))

    def ensure_area(self, area_id, capacity=1):
        if area_id not in self.areas:
            if len(self.areas) >= 128:
                raise ValueError("Area fixture capacity exceeded")
            record = self.area_records + len(self.areas) * 24
            self.areas[area_id] = record
            self.o.write(record + 4, self.o.alloc(max(1, capacity) * 20), 0, max(1, capacity), 0, area_id)
            self.o.write(self.context + 0x19c, len(self.areas))
        return self.areas[area_id]

    def string(self, text):
        raw = text.encode("ascii") + b"\0"
        allocation = self.o.alloc(16 + len(raw))
        self.o.write(allocation + 12, 10000)  # retained fixture string reference
        self.o.uc.mem_write(allocation + 16, raw)
        return allocation + 16

    def close(self):
        while len(self.o.hooks) > self.hook_start:
            self.o.uc.hook_del(self.o.hooks.pop())

    def compile(self, expression, at=None):
        o = self.o
        cmd = o.alloc(0x94) if at is None else at
        if expression["call"] == "IsInArea":
            # Missing IDs are empty areas in the native registry. Reserve the
            # empty record without exercising heap allocation during lookup.
            area_id = expression["args"][0]
            if not isinstance(area_id, (int, float)) or area_id != int(area_id):
                raise ValueError("Area fixtures require literal integer IDs")
            self.ensure_area(int(area_id))
        numeric, objects, strings, groups, children, bindings = [], [], [], [], [], []
        for arg in expression["args"]:
            if isinstance(arg, dict) and "global" in arg:
                bindings.append((1, len(numeric), self.global_indices[arg["global"]]))
                numeric.append(0)
            elif isinstance(arg, dict) and "unit" in arg:
                index = arg["unit"]
                value = self.units[index] if 0 <= index < len(self.units) else 0
                slot = o.alloc(4)
                o.write(slot, value)
                objects.append(slot)
            elif isinstance(arg, dict) and "iterator" in arg:
                name = arg["iterator"]
                if name not in self.iterators:
                    self.iterators[name] = o.alloc(4)
                objects.append(self.iterators[name])
            elif isinstance(arg, dict) and "group" in arg:
                groups.append(self.groups[arg["group"]])
            elif isinstance(arg, dict) and "string" in arg:
                strings.append(self.string(arg["string"]))
            elif isinstance(arg, dict):
                children.append((len(numeric), self.compile(arg)))
                numeric.append(0)
            else:
                numeric.append(arg)
        o.write(cmd, self.opcodes[expression["call"]])
        if numeric:
            values = o.alloc(4 * len(numeric))
            o.floats(values, *numeric)
            o.write(cmd + 8, values)
        if objects:
            values = o.alloc(4 * len(objects))
            o.write(values, *objects)
            o.write(cmd + 0x30, values)
        if strings:
            values = o.alloc(4 * len(strings))
            o.write(values, *strings)
            o.write(cmd + 0x1c, values)
        if groups:
            values = o.alloc(4 * len(groups))
            o.write(values, *groups)
            o.write(cmd + 0x44, values)
        if bindings:
            values = o.alloc(12 * len(bindings))
            for i, binding in enumerate(bindings):
                o.write(values + i * 12, *binding)
            o.write(cmd + 0x6c, values, len(bindings))
        if children:
            values = o.alloc(12 * len(children))
            for i, (index, child) in enumerate(children):
                o.write(values + 12 * i, 1, index, child)
            o.write(cmd + 0x80, values, len(children))
        return cmd


def predicate(o, case):
    fixture = Expressions(o, case["units"], case.get("variables"), case.get("groups"), case.get("areas"), case)
    command, output = fixture.compile(case["expression"]), o.alloc(4)
    o.run(ADDRESSES[o.campaign]["eval"], command, [fixture.context, fixture.instance, output])
    return [{"value_bits": o.ints(output)[0], "truth": o.number(output) != 0}]


def trigger(o, case):
    addresses = ADDRESSES[o.campaign]
    fired = [0]
    o.hook(addresses["cleanup"], lambda: o.ret())

    def body():
        fired[0] += 1
        o.ret(cleanup=8)

    o.hook(addresses["body"], body)
    roots, evaluated = {}, []

    def observe():
        command = o.uc.reg_read(UC_X86_REG_ECX)
        if command in roots:
            evaluated.append(roots[command])

    o.hook(addresses["eval"], observe)
    states = []
    for snapshot in case["snapshots"]:
        # Retire the previous supplied accessor before replacing its unit set.
        # Native expression/gate instructions remain untouched.
        fixture = Expressions(o, snapshot["units"], snapshot.get("variables"), snapshot.get("groups"), snapshot.get("areas"), snapshot)
        count = len(case["conditions"])
        records = o.alloc(max(1, count) * 0x94)
        roots.clear()
        evaluated.clear()
        for i, expr in enumerate(case["conditions"]):
            fixture.compile(expr, records + i * 0x94)
            roots[records + i * 0x94] = i
        vector, gate = o.alloc(20), o.alloc(8)
        o.write(vector + 4, records, count)
        o.write(gate, vector, 0)
        before = fired[0]
        o.run(addresses["gate"], gate, [fixture.context, fixture.instance])
        states.append({"fired": fired[0] != before, "dispatches": fired[0], "evaluated": list(evaluated)})
        # Hooks retain their owning fixture; remove this accessor now.
        fixture.close()
    return states


CAPTURES = {"quest_predicate": predicate, "quest_trigger": trigger}
