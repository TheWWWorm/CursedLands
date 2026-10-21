"""Native NPC behaviour commands: quest dispatcher against real AI records.

Base addresses are given inline; NATIVE maps them to Lost in Astral. Every
unit's logic object is built by the executable's own constructor (base
0x545580, Astral 0x4c9a20). Commands are compiled into native 0x94-byte records and executed
by the persistent-body dispatcher; motivation constructors, the motivation
list, diplomacy tables and the world alarm table are all native. Hooks only
supply the CRT heap, a no-op release for fixture actors (see Expressions) and
the temporary-command cleanup. The observation code reads fields; motivation
type ids come from each object's own virtual method (vtable + 0x20).
"""
import struct

from native_quests import ADDRESSES, OPS, Expressions

COMMANDS = {
    "UMClear": 0x24, "UMSentry": 0x25, "UMGuard": 0x26, "UMGuardEx": 0x27,
    "UMPatrol": 0x28, "UMPatrolClear": 0x29, "UMPatrolAddPoint": 0x2a,
    "UMPatrolAddPointLook": 0x2b, "UMStandard": 0x2c, "UMAggression": 0x2d,
    "UMRevenge": 0x2e, "UMSuspection": 0x2f, "UMCorpseWatcher": 0x30,
    "UMPlayer": 0x31, "BlockUnit": 0x32, "Guard": 0x33, "Idle": 0x34,
    "SetPlayer": 0x36, "SetDiplomacy": 0x37, "SetEnemy": 0x38, "Follow": 0x3b,
    "SetSpellAggression": 0x42, "InvokeAlarm": 0x43, "Sentry": 0x94,
    "SetPlayerAggression": 0xa4, "UMFear": 0xc7, "UMAg": 0xc8,
    "UMFollow": 0xca, "ResetTarget": 0xe8,
}
QUERIES = {"GetDiplomacy": 0x60, "IsEnemy": 0x61, "IsAlarm": 0x67,
           "AlarmTime": 0x8b, "AlarmPosX": 0x8c, "AlarmPosY": 0x8d}

AI = 0x980                      # motivation AI embedded in the unit logic
CONFIG_OFFSETS = {"GuardStayTime": 4, "SentryStayTime": 8, "FollowMinDist": 0xc,
                  "FollowMaxDist": 0x10, "GuardRadius": 0x14}
# Per-executable addresses (cases_ext_npc_commands.contracts lists the entry
# points executed for each kind).
NATIVE = {
    "original": {
        "logic": 0x545580,            # unit logic constructor (AI built by 0x545990)
        "new": 0x70056f, "delete": 0x700598,
        "config": 0x7c53e8,           # [Logic] values read by 0x5ce0f0
        "diplomacy": 0x7c2bb4,        # 32 friend masks, then 32 enemy masks
        "alarm_prologue": (0x5d53b0, 0x5d5413),   # AI tick through its alarm countdown
        "option_rebuild": 0x5ceed0,   # AI weapon/spell option list from the unit inventory
    },
    "lost_in_astral": {
        "logic": 0x4c9a20,            # AI built by 0x4c9930
        "new": 0x5ffa7b, "delete": 0x5ffaa6,
        "config": 0x6b8778,
        "diplomacy": 0x6b603c,
        "alarm_prologue": (0x51c4d0, 0x51c532),
        "option_rebuild": 0x518100,
    },
}
QUALIFIED = {"original": {"npc_motivation", "npc_diplomacy", "npc_alarm"},
             "lost_in_astral": {"npc_motivation", "npc_diplomacy", "npc_alarm"}}

DESCRIPTOR_SIZE = 0x4c

TYPE_NAMES = {0: "guard", 1: "patrol", 2: "sentry", 3: "suspection", 4: "aggression",
              5: "corpse_watcher", 6: "player", 7: "fear", 8: "tamed", 10: "follow"}


def bits(o, at):
    return o.ints(at)[0]


class NpcFixture:
    """Native unit records with constructed logic and a world unit container."""

    def __init__(self, o, case):
        self.o = o
        if case.get("_kind") not in QUALIFIED.get(o.campaign, ()):
            raise ValueError(f"{case.get('_kind')} addresses are not qualified for {o.campaign}")
        self.native, self.quest = NATIVE[o.campaign], ADDRESSES[o.campaign]
        self.world = self.quest["world"]
        self.heap_hooks(o, self.native)
        rows = case.get("units", [])
        self.fixture = Expressions(o, rows, environment=case)
        self.fixture.opcodes = OPS | COMMANDS | QUERIES
        self.units = self.fixture.units
        self.logic = []
        for row, unit in zip(rows, self.units):
            if not unit:
                self.logic.append(0)
                continue
            # Defaults written by the unit constructor 0x52e5b0.
            o.write(unit + 0x244, 0, 0xffffffff, 0, 0)
            o.write(unit + 0x250, row.get("side", 0))
            logic = o.alloc(0x2000)
            o.run(self.native["logic"], logic)
            # Attachment links (unit <-> logic <-> AI) made at spawn time.
            o.write(unit + 0x240, logic)
            o.write(logic + 0x1c, unit)
            o.write(logic + AI, logic)
            # Every spawned AI owns its .mob descriptor list (index 0 here).
            o.write(logic + AI + 0x94, self.descriptor(row.get("descriptor", {})))
            self.logic.append(logic)
        for key, value in case.get("config", {}).items():
            o.floats(self.native["config"] + CONFIG_OFFSETS[key], value)
        for row in case.get("diplomacy", []):
            self.seed_relation(*row)
        # Spawn-time hostility mask: the unit's side row of the seeded matrix.
        for index, unit in enumerate(self.units):
            if unit:
                o.write(unit + 0x244, self.diplomacy_enemy(rows[index].get("side", 0)))
        self.world_container()
        o.write(self.world + 0x64, case.get("tick", 0))   # world tick counter
        o.hook(self.quest["cleanup"], lambda: o.ret())
        # ResetTarget's descriptor rebuild ends by rebuilding attack options
        # from the unit's inventory and stats, outside this contract.
        if self.native["option_rebuild"]:
            o.hook(self.native["option_rebuild"], lambda: o.ret(cleanup=4))

    def descriptor(self, row):
        """One supplied .mob logic descriptor, laid out as 0x5d6630 reads it."""
        o = self.o
        record = o.alloc(DESCRIPTOR_SIZE)
        o.write(record, row.get("model", 0))
        o.floats(record + 0x18, *row.get("point", [0, 0, 0]))
        o.floats(record + 0x2c, row.get("radius", -1))
        o.write(record + 0x34, row.get("alarm_raise", 0))
        o.write(record + 0x40, row.get("alarm_cond", 0), row.get("countdown", 75), row.get("aggression", 0))
        return record

    @staticmethod
    def heap_hooks(o, native):
        def new():
            size = o.args(1)[0]
            block = o.alloc(max(size, 4))
            o.uc.mem_write(block, bytes(max(size, 4)))
            o.ret(block)
        o.hook(native["new"], new)
        # Fixture heap is a bump allocator; native destructors still run.
        o.hook(native["delete"], lambda: o.ret())

    def diplomacy_enemy(self, side):
        return self.o.ints(self.native["diplomacy"] + 0x80 + side * 4)[0] if 0 <= side < 32 else 0xffffffff

    def seed_relation(self, a, b, value):
        """Supplied .mob diplomacy matrix entry (0 friend, 1 neutral, 2 war)."""
        o, bit, table = self.o, 1 << b, self.native["diplomacy"]
        friend, enemy = o.ints(table + a * 4)[0], o.ints(table + 0x80 + a * 4)[0]
        friend = friend | bit if value == 0 else friend & ~bit
        enemy = enemy | bit if value == 2 else enemy & ~bit
        o.write(table + a * 4, friend)
        o.write(table + 0x80 + a * 4, enemy)

    def world_container(self):
        o = self.o
        container, nodes = o.alloc(0x40), [o.alloc(12) for unit in self.units if unit]
        present = [unit for unit in self.units if unit]
        for i, node in enumerate(nodes):
            o.write(node, nodes[i + 1] if i + 1 < len(nodes) else 0, nodes[i - 1] if i else 0, present[i])
        o.write(container + 0x38, nodes[0] if nodes else 0)
        o.write(self.world + 0x40, container)   # iterated by 0x404920/0x404960

    def run(self, statement):
        o = self.o
        record = self.fixture.compile(statement)
        vector, thread, killed = o.alloc(20), o.alloc(0xc0), o.alloc(4)
        o.write(vector + 4, record, 1)
        o.write(thread, vector, 0, 0, -1, killed)
        o.run(self.quest["program"], thread, [self.fixture.context])

    def query(self, expression):
        o = self.o
        command, output = self.fixture.compile(expression), o.alloc(4)
        o.run(self.quest["eval"], command, [self.fixture.context, self.fixture.instance, output])
        return o.ints(output)[0]

    def index_of(self, pointer):
        if pointer == 0:
            return -1
        return self.units.index(pointer) if pointer in self.units else -2

    def config_or_bits(self, value, key):
        configured = self.o.ints(self.native["config"] + CONFIG_OFFSETS[key])[0]
        return key if value == configured else value

    def motivation(self, item):
        o = self.o
        vtable = o.ints(item)[0]
        kind = o.run(o.ints(vtable + 0x20)[0], item)
        name = TYPE_NAMES.get(kind, f"type_{kind}")
        entry = {"type": name}
        if kind in (0, 2):
            entry["point_bits"] = o.ints(item + 8, 3)
        if kind == 0:
            entry["radius"] = self.config_or_bits(bits(o, item + 0x14), "GuardRadius")
            entry["stay"] = self.config_or_bits(bits(o, item + 0x18), "GuardStayTime")
        elif kind == 1:
            data, count = o.ints(item + 0xc, 2)
            points = []
            for i in range(count):
                point = data + i * 0x20
                looks_at, looks = o.ints(point + 0x10, 2)
                points.append({"point_bits": o.ints(point, 3), "looks": [
                    o.ints(looks_at + 16 * j, 3) + [o.uc.mem_read(looks_at + 16 * j + 12, 1)[0]]
                    for j in range(looks)]})
            entry["points"] = points
        elif kind == 4:
            entry["revenge"] = o.uc.mem_read(item + 0xc, 1)[0] != 0
        elif kind == 7:
            entry["flag"] = o.uc.mem_read(item + 0x28, 1)[0] != 0
        elif kind == 10:
            entry["target"] = self.index_of(o.ints(item + 8)[0])
        return kind, entry

    def ai_state(self, index):
        o, unit, logic = self.o, self.units[index], self.logic[index]
        state = {"present": bool(unit)}
        if not unit:
            return state
        flags = o.ints(unit + 8)[0]
        state.update({"blocked": bool(flags & 0x800000), "side": struct.unpack("<i", struct.pack("<I", o.ints(unit + 0x250)[0]))[0]})
        if not logic:
            return state
        ai = logic + AI
        motivations, node, seen = [], o.ints(ai + 0x74)[0], 0
        while node:
            seen += 1
            if seen > 64:
                raise RuntimeError("Corrupt native motivation list")
            motivations.append(self.motivation(o.ints(node + 8)[0]))
            node = o.ints(node)[0]
        if len(motivations) != o.ints(ai + 0x7c)[0]:
            raise RuntimeError("Native motivation count disagrees with its list")
        motivations.sort(key=lambda pair: pair[0])
        state.update({"motivations": [entry for _, entry in motivations],
                      "ai_state": o.ints(ai + 4)[0],
                      "script_target": self.index_of(o.ints(ai + 0x2c)[0])})
        return state


def motivation(o, case):
    fixture = NpcFixture(o, dict(case, _kind="npc_motivation"))
    states = []
    for statement in case["commands"]:
        fixture.run(statement)
        states.append({"units": [fixture.ai_state(i) for i in case["observe"]]})
    return states


def diplomacy(o, case):
    fixture = NpcFixture(o, dict(case, _kind="npc_diplomacy"))
    states = []
    for statement in case["commands"]:
        fixture.run(statement)
        relations = [fixture.query({"call": "GetDiplomacy", "args": list(pair)}) for pair in case["pairs"]]
        units = []
        for index in case["observe"]:
            enemy = 0
            for side in range(32):
                value = fixture.query({"call": "IsEnemy", "args": [{"unit": index}, side]})
                enemy |= int(struct.unpack("<f", struct.pack("<I", value))[0] != 0) << side
            unit = fixture.units[index] if 0 <= index < len(fixture.units) else 0
            units.append({"side": fixture.ai_state(index).get("side") if unit else None,
                          "enemy_bits": enemy})
        states.append({"relation_bits": relations, "units": units})
    return states


def alarm_table(fixture, indices):
    return [{"on_bits": fixture.query({"call": "IsAlarm", "args": [i]}),
             "time_bits": fixture.query({"call": "AlarmTime", "args": [i]}),
             "x_bits": fixture.query({"call": "AlarmPosX", "args": [i]}),
             "y_bits": fixture.query({"call": "AlarmPosY", "args": [i]})} for i in indices]


def alarm(o, case):
    fixture = NpcFixture(o, dict(case, _kind="npc_alarm"))
    sentinels = []
    for index, row in enumerate(case.get("units", [])):
        logic = fixture.logic[index] if row is not None else 0
        if logic and "alert" in row:
            ai = logic + AI
            # Supplied descriptor-derived alarm fields (normally written by
            # 0x5d6630 from the .mob logic descriptor) and the alerted flag.
            o.uc.mem_write(ai + 0x34, bytes([int(row["alert"]["alerted"]), row["alert"]["raise"] & 0xff]))
            o.write(ai + 0x40, row["alert"]["countdown"])
            sentinels.append((index, ai))
    states = []
    for step in case["steps"]:
        if "command" in step:
            fixture.run(step["command"])
        else:
            # Supplied world tick advance, then each alerted AI runs only the
            # native alarm countdown/raise prologue of its AI tick.
            tick = fixture.world + 0x64
            o.write(tick, o.ints(tick)[0] + 1)
            start, end = fixture.native["alarm_prologue"]
            for index, ai in sentinels:
                o.run(start, ai, end=end)
        states.append({"alarms": alarm_table(fixture, case["queries"]),
                       "countdowns": [struct.unpack("<i", struct.pack("<I", o.ints(ai + 0x40)[0]))[0]
                                      for _, ai in sentinels]})
    return states


CAPTURES = {"npc_motivation": motivation, "npc_diplomacy": diplomacy, "npc_alarm": alarm}
