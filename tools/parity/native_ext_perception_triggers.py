"""Original perception-driven quest triggers: real evaluator, groups and AI update.

Layer 1 (perception_group): supplied AI noticed/corpse lists on actor logic
records (+0x240 -> +0xa94 / +0xab0). The native group evaluator 0x4b5b00
(UnitSee 0x5d, GroupSee 0x5e, PlayerSee 0xa5, GroupCross 0x5b), the sorted
set insertion 0x4b2ef0, the player visibility aggregation 0x66e0f0 and the
expression evaluator 0x4b41e0 (GroupSize, GroupHas, Any, Every, IsUnitVisible
0xe5) execute. Layer 2 (perception_ticks): the native AI perception update
0x5caa00 (drop pass, 0x5ca5a0 acquisition scan, 0x5ca410 eye/facing) runs per
tick for one watcher, then the same evaluator reads its list.

Python never decides membership or truth. Hooks supply only the boundaries
listed in the contracts (allocator, debug log sink, spatial candidates,
terrain ray, fixture accessors).
"""
import math
import struct

from unicorn.x86_const import UC_X86_REG_ECX, UC_X86_REG_EIP, UC_X86_REG_ESI
from native_quests import ADDRESSES, OPS, Expressions

EVAL = 0x4b41e0          # expression evaluator (numeric results)
GROUP_EVAL = 0x4b5b00    # group-returning builtins (parameter type 4)
INSERT = 0x4b2ef0        # sorted-set insertion used by AddObject and group builtins
VISIBLE_UPDATE = 0x66e0f0  # per-player visible group (+0x510c) aggregation
PERCEIVE = 0x5caa00      # AI perception update: drop pass then 0x5ca5a0 scan
SCRATCH = 0x7b2788       # global perception scratch passed in ECX by 0x5cb700
CANDIDATES = 0x5ca1d0    # spatial candidate list builder (friend-cell grid, rand refresh)
RAY = 0x5bc3e0           # terrain sight-ray factor
MALLOC, FREE, PLEX = 0x70056f, 0x700598, 0x6fe8af
# Debug log stream operators used by the perception routines: thiscall,
# return the stream, pop their argument(s).
LOG = {0x6fc2dd: 4, 0x6fc986: 4, 0x6fc070: 4, 0x434fe0: 4, 0x6fc7ba: 8}
GROUP_VTABLE = 0x73d110
# Layer 1 per qualified executable. Lost in Astral analogues were matched
# by structure: group evaluator 0x46db40 (same opcodes, same temp pool at
# context +0x1b0), insertion 0x4688b0, list merge 0x4689b0, visible-group
# update 0x597590 (+0x50f8 / +0x510c, +0x24 == -1 branch, +0x1c player,
# player +0x40 unit map) and IsUnitVisible 0xe5 in 0x46cca0 reading
# player(0) +0x20 -> +0x510c via 0x466560. Its CPlex 0x5fed90 runs natively
# over the supplied operator new 0x5ffa7b. Layer 2 is qualified only for the
# base executable.
CAMPAIGN = {
    "original": {"group_eval": GROUP_EVAL, "insert": INSERT, "visible_update": VISIBLE_UPDATE,
                 "group_vtable": GROUP_VTABLE, "malloc": MALLOC, "free": FREE, "plex": PLEX, "log": LOG},
    "lost_in_astral": {"group_eval": 0x46db40, "insert": 0x4688b0, "visible_update": 0x597590,
                       "group_vtable": 0x62789c, "malloc": 0x5ffa7b, "free": 0x5ecb7c, "plex": None, "log": {}},
}
GROUP_CALLS = {"UnitSee": 0x5d, "GroupSee": 0x5e, "PlayerSee": 0xa5, "GroupCross": 0x5b,
               "GroupAdd": 0x59, "GroupSub": 0x5a}
CALLS = dict(OPS, IsUnitVisible=0xe5, **GROUP_CALLS)
DEAD_ACCESSOR, POSITION_ACCESSOR, RAY_STUB = 0x1860, 0x1870, 0x1880
LOGIC_SIZE = 0xc00
PERCEPTION = 0xa50       # perception state inside the logic record (ECX of 0x5cb700)
NOTICED_LIST, CORPSE_LIST, ENEMY_CORPSE_LIST = 0xa90, 0xaac, 0xac8
CANDIDATE_HEAD = PERCEPTION + 0x28


class Perception(Expressions):
    """Expression fixture whose actors carry AI logic records and lists."""

    def __init__(self, o, case):
        rows = [dict(row, pos=list(row["pos"])) for row in case["units"]]
        super().__init__(o, rows, environment=case)
        self.rows = rows
        self.opcodes = CALLS
        self.index = {unit: i for i, unit in enumerate(self.units)}
        self.unit_dead = {unit: int(row["dead"]) for unit, row in zip(self.units, rows)}
        self.stats = [o.ints(unit + 0x170)[0] for unit in self.units]
        self.addresses = addresses = CAMPAIGN[o.campaign]
        self.eval_address = ADDRESSES[o.campaign]["eval"]
        o.hook(addresses["malloc"], lambda: o.ret(o.alloc(max(4, o.args(1)[0]))))
        o.hook(addresses["free"], lambda: o.ret())

        def plex():
            head, count, size = o.args(3)
            block = o.alloc(4 + count * size)
            o.write(block, o.ints(head)[0])
            o.write(head, block)
            o.ret(block, cleanup=12)

        if addresses["plex"]:
            o.hook(addresses["plex"], plex)
        for address, cleanup in addresses["log"].items():
            o.hook(address, lambda cleanup=cleanup: o.ret(o.uc.reg_read(UC_X86_REG_ECX), cleanup))
        # CList / CPlex block sizes of the evaluator's temporary group and
        # object-slot pools (constructor state of the script context).
        o.write(self.context + 0x1c8, 16)
        o.write(self.context + 0x1e4, 16)
        vt = o.ints(self.units[0])[0]
        o.write(vt + 0xdc, DEAD_ACCESSOR)
        o.write(vt + 0xc0, POSITION_ACCESSOR)
        o.hook(DEAD_ACCESSOR, lambda: o.ret(self.unit_dead[o.uc.reg_read(UC_X86_REG_ECX)]))

        def position():
            unit = o.uc.reg_read(UC_X86_REG_ECX)
            output = o.args(1)[0]
            o.uc.mem_write(output, bytes(o.uc.mem_read(unit + 0x1c, 12)))
            o.ret(cleanup=4)

        o.hook(POSITION_ACCESSOR, position)
        self.logic = []
        for unit, row in zip(self.units, rows):
            logic = o.alloc(LOGIC_SIZE)
            o.uc.mem_write(logic, bytes(LOGIC_SIZE))
            o.write(unit + 0x240, logic)
            o.write(logic + 0x1c, unit)
            o.write(unit + 0x250, row.get("side", 0))
            o.write(unit + 0x24c, self.player if row.get("party") else 0)
            for offset in (NOTICED_LIST, CORPSE_LIST, ENEMY_CORPSE_LIST):
                o.write(logic + offset + 0x18, 10)
            self.logic.append(logic)
        for unit, row, logic in zip(self.units, rows, self.logic):
            self.set_list(logic + NOTICED_LIST, row.get("noticed", []))
            self.set_list(logic + CORPSE_LIST, row.get("corpses", []))
        for name, members in case.get("groups", {}).items():
            self.groups[name] = self.sorted_group(members)
        # Player zero's units (hash map at +0x40, one bucket) and its
        # visibility record (+0x20): extra-visible (+0x50f8) and visible
        # (+0x510c) groups; +0x24 = -1 selects the aggregation branch.
        self.visibility = o.alloc(0x5200)
        o.uc.mem_write(self.visibility, bytes(0x5200))
        o.write(self.player + 0x20, self.visibility)
        o.write(self.visibility + 0x1c, self.player)
        o.write(self.visibility + 0x24, 0xffffffff)
        for offset in (0x50f8, 0x510c):
            o.write(self.visibility + offset, addresses["group_vtable"])
        for i in case.get("extra_visible", []):
            o.run(addresses["insert"], self.visibility + 0x50f8, [self.units[i]])
        bucket, chain = o.alloc(4), 0
        for i in reversed(case.get("player_units", [])):
            node = o.alloc(12)
            o.write(node, chain, self.uids(i), self.units[i])
            chain = node
        o.write(bucket, chain)
        o.write(self.player + 0x44, bucket, bucket + 4)

    def uids(self, i):
        return self.rows[i].get("uid", i + 1)

    def set_list(self, list_object, members):
        """Supplied CList contents: nodes [next, prev, actor], head first."""
        o = self.o
        nodes = [o.alloc(12) for _ in members]
        for k, (node, i) in enumerate(zip(nodes, members)):
            o.write(node, nodes[k + 1] if k + 1 < len(nodes) else 0, nodes[k - 1] if k else 0, self.units[i])
        o.write(list_object + 4, nodes[0] if nodes else 0, nodes[-1] if nodes else 0, len(nodes))

    def read_list(self, list_object):
        result, node = [], self.o.ints(list_object + 4)[0]
        while node:
            result.append(self.index[self.o.ints(node + 8)[0]])
            node = self.o.ints(node)[0]
            if len(result) > 4096:
                raise RuntimeError("Corrupt native list")
        return result

    def sorted_group(self, members):
        """Script groups are sorted sets; build them with native insertion."""
        group = self.o.alloc(20)
        self.o.write(group, self.addresses["group_vtable"], 0, 0, 0, 0)
        for i in members:
            self.o.run(self.addresses["insert"], group, [self.units[i]])
        return group

    def read_group(self, group):
        entries, count = self.o.ints(group + 4, 2)
        pointers = self.o.ints(entries, count) if count else []
        return [self.index[p] for p in pointers]

    def set_dead(self, i, dead):
        self.unit_dead[self.units[i]] = int(dead)
        self.dead[self.stats[i]] = int(dead)

    def compile(self, expression, at=None):
        o = self.o
        cmd = o.alloc(0x94) if at is None else at
        o.uc.mem_write(cmd, bytes(0x94))
        numeric, objects, groups, bindings = [], [], [], []
        for arg in expression["args"]:
            if isinstance(arg, dict) and "unit" in arg:
                index = arg["unit"]
                slot = o.alloc(4)
                o.write(slot, self.units[index] if 0 <= index < len(self.units) else 0)
                objects.append(slot)
            elif isinstance(arg, dict) and "iterator" in arg:
                if arg["iterator"] not in self.iterators:
                    self.iterators[arg["iterator"]] = o.alloc(4)
                    o.write(self.iterators[arg["iterator"]], 0)
                objects.append(self.iterators[arg["iterator"]])
            elif isinstance(arg, dict) and "group" in arg:
                groups.append(self.groups[arg["group"]])
            elif isinstance(arg, dict) and arg.get("call") in GROUP_CALLS:
                bindings.append((4, len(groups), self.compile(arg)))
                groups.append(0)
            elif isinstance(arg, dict):
                bindings.append((1, len(numeric), self.compile(arg)))
                numeric.append(0)
            else:
                numeric.append(arg)
        o.write(cmd, self.opcodes[expression["call"]])
        for offset, values, pack in [(8, numeric, "f"), (0x30, objects, "I"), (0x44, groups, "I")]:
            if values:
                array = o.alloc(4 * len(values))
                o.uc.mem_write(array, struct.pack("<" + pack * len(values), *values))
                o.write(cmd + offset, array)
        if bindings:
            array = o.alloc(12 * len(bindings))
            for i, binding in enumerate(bindings):
                o.write(array + 12 * i, *binding)
            o.write(cmd + 0x80, array, len(bindings))
        return cmd

    def evaluate(self, expression, command=None):
        o = self.o
        command = command or self.compile(expression)
        if expression["call"] in GROUP_CALLS:
            slot = o.alloc(4)
            o.run(self.addresses["group_eval"], command, [self.context, self.instance, slot])
            members = self.read_group(o.ints(slot)[0])
            # Native order is pointer order (= fixture index order here);
            # the comparison uses membership, and count exposes duplicates.
            return {"count": len(members), "members": sorted(members)}
        output = o.alloc(4)
        o.run(self.eval_address, command, [self.context, self.instance, output])
        return {"truth": o.number(output) != 0, "value_bits": o.ints(output)[0]}


def group_case(o, case):
    fixture = Perception(o, case)
    # Server player update before scripts: builds the +0x510c visible group
    # that IsUnitVisible reads (and merges the party's corpse lists).
    o.run(fixture.addresses["visible_update"], fixture.visibility)
    return [fixture.evaluate(case["expression"])]


def facing_quaternion(angle):
    """Quaternion whose native forward vector (0x5ca410) is (cos a, sin a)."""
    half = (angle + math.pi / 2) / 2
    return [math.cos(half), 0.0, 0.0, math.sin(half)]


def ticks_case(o, case):
    if o.campaign != "original":
        raise ValueError("perception_ticks is qualified only for the base executable")
    fixture = Perception(o, case)
    units, logic = fixture.units, fixture.logic
    watcher = case["watcher"]
    observer = case["observer"]
    unit, brain = units[watcher], logic[watcher]
    o.floats(brain + 0x294, observer["sight"])
    o.floats(brain + 0x904, observer["sight_factor"])
    o.floats(brain + 0x2a4, observer["life"])
    o.floats(brain + 0x224, math.cos(observer["cone_half"]))
    o.floats(brain + 0x228, observer["peripheral"])
    o.floats(unit + 0x34, *facing_quaternion(observer["facing"]))
    # 0x530150 hostility: allowed mask (+0x244) AND hostility mask (+0x248).
    hostile_sides = sum(1 << side for side in observer["hostile_sides"])
    o.write(unit + 0x244, 0xffffffff, hostile_sides)
    for row, other in zip(case["units"], logic):
        o.floats(other + 0x900, row.get("visibility", 1.0))
        o.floats(other + 0x2c4, row.get("detect", 1.0))
        o.floats(other + 0x2d4, row.get("life_detect", 1.0))
    # Eye-height ground lookup in 0x5ca410 reads an empty terrain grid.
    grid = o.alloc(0x2700)
    o.uc.mem_write(grid, bytes(0x2700))
    o.write(SCRATCH, grid)
    ray, rays = o.alloc(4), {}
    o.uc.mem_write(RAY_STUB, b"\xd9\x05" + struct.pack("<I", ray) + b"\xc2\x08\x00")

    def terrain_ray():
        target = fixture.index[o.uc.reg_read(UC_X86_REG_ESI)]
        o.floats(ray, rays.get(target, 1.0))
        o.uc.reg_write(UC_X86_REG_EIP, RAY_STUB)

    o.hook(RAY, terrain_ray)

    def candidates():
        # Supplied spatial broadphase: every other living-or-dead actor,
        # refreshed every tick (the native grid refresh is random 8..11 ticks).
        others = [i for i in range(len(units)) if i != watcher]
        fixture.set_list(brain + CANDIDATE_HEAD - 4, others)
        o.ret(cleanup=8)

    o.hook(CANDIDATES, candidates)
    command = fixture.compile(case["trigger"])
    states, perceiving = [], True
    for tick in case["ticks"]:
        for key, xy in tick.get("positions", {}).items():
            o.floats(units[int(key)] + 0x1c, *xy)
        for i in tick.get("dead", []):
            fixture.set_dead(i, True)
        rays.clear()
        rays.update({int(k): v for k, v in tick.get("rays", {}).items()})
        if fixture.unit_dead[unit]:
            # Declared assumption: no perception update for a dead watcher.
            perceiving = False
        if perceiving:
            o.run(PERCEIVE, SCRATCH, [brain, brain + PERCEPTION])
            forward = struct.unpack("<3f", o.uc.mem_read(SCRATCH + 0x14, 12))
            if abs(forward[0] - math.cos(observer["facing"])) > 1e-5 or abs(forward[1] - math.sin(observer["facing"])) > 1e-5:
                raise RuntimeError(f"Fixture facing mismatch {forward}")
        result = fixture.evaluate(case["trigger"], command)
        states.append({"count_bits": result["value_bits"], "fired": result["truth"],
                       "noticed": sorted(fixture.read_list(brain + NOTICED_LIST))})
    return states


CAPTURES = {"perception_group": group_case, "perception_ticks": ticks_case}
