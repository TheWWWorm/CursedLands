"""Execute state-changing quest commands through the original dispatcher.

A persistent command body runs through FUN_004b6760 tick by tick, exactly as
native_quest_programs.py does, but the observation is the campaign state the
commands changed: player zero's GS hash table (bucket chains, float32 bits and
count), the quest-item bag in list order, money, lever state/permission,
group arrays, For iteration order (through an ordinary global accumulator),
QStart/QObj*/QFinish registrations and supplied observation expressions.

Every state change is made by native code: the hash-table constructor
(581790), insertion/erase (460bc0/460db0 via 66edd0/66ee40/66eef0), bag
append/unlink (665430/665740), group insertion/removal (4b2ef0/4b2da0/4c2200),
lever state (52b7a0/52bad0), objective recording (4baa40/4bae10) and QFinish's
script generation (4baab0). Hooks only supply the declared boundaries listed
in cases_ext_quest_commands.contracts: heap/string allocators, Win32 imports,
the player lookup, item construction by name, the lever database, the world
object, network/UI notifications and the script compiler.
"""
import struct

from unicorn.x86_const import UC_X86_REG_ECX, UC_X86_REG_EDX
from native_quests import ADDRESSES, OPS, Expressions

COMMANDS = {
    "_SetGlobal": 0x78, "Sleep": 7, "KillScript": 0x79, "For": 0x6b,
    "AddObject": 0x22, "RemoveObject": 0x23,
    "GSSetVar": 0x7f, "GSDelVar": 0x82, "GSSetVarMax": 0x98,
    "GiveQuestItem": 0x92, "EraseQuestItem": 0x93, "GiveMoney": 0xa7,
    "SwitchLeverState": 0x91, "SwitchLeverStateEx": 0x9e, "EnableLever": 0xcc,
    "QStart": 0xd5, "QFinish": 0xd6, "QObjArea": 0xd7, "QObjSeeObject": 0xd8,
    "QObjSeeUnit": 0xd9, "QObjKillUnit": 0xda, "QObjKillGroup": 0xdb,
    "QObjUse": 0xdc, "QObjGetItem": 0xdd,
}
OBJECTIVES = {v: k for k, v in COMMANDS.items() if k.startswith("QObj")}

# Declared native addresses (base GOG executable only).
DISPATCH = 0x4b6760
CLEANUP = 0x4bec80
GS_CONSTRUCT = 0x581790      # player GS hash-table constructor (100 -> next prime)
GS_INSERT = 0x460bc0         # used to load the scenario's initial GS values
BAG_APPEND = 0x665430        # player bag append of a temporary item list
LIST_INIT = 0x4c98c0         # temporary item list constructor (block size)
LIST_ADD = 0x4c98f0          # temporary item list append
OPERATOR_NEW, OPERATOR_DELETE = 0x70056f, 0x700598
FIXED_ALLOC, FIXED_FREE = 0x6e6bf1, 0x6e6c80   # MFC CString size-class allocator
ITEM_FACTORY = 0x6ac930      # item construction by database name
LEVER_DB = 0x464750          # lever prototype lookup (switch time)
WORLD = 0x455950             # current world object getter
COMPILER = 0x4d23a0          # script text compiler used by QFinish
OBJECTIVE_ARRAY = 0x7aa5f8   # {vtable?, data +4, count +8, capacity +0xc, grow +0x10}
QUEST_NAME = 0x7aa60c        # CString: QStart's quest id
EMPTY_STRING = 0x796e38      # afxEmptyString data pointer (initialized .data)
CRT_FLOAT_INIT = 0x6e7294
IAT = (0x73b000, 0x73b400)
STUBS = 0x1900               # inside the always-mapped low page


def _f32_bits(value):
    return struct.unpack("<I", struct.pack("<f", value))[0]


class CommandFixture(Expressions):
    """Own fixture: real CString code runs; only allocators/imports are supplied."""

    def __init__(self, o, case):
        self.o = o
        self.case = case
        self.opcodes = OPS | COMMANDS
        self.hook_start = len(o.hooks)
        self.iterators, self.groups, self.areas = {}, {}, {}
        self.global_indices = {name: i for i, name in enumerate(sorted(case.get("globals", {})))}
        self.notifications = []      # supplied UI/network boundary calls (not compared)
        self.compiled = []           # QFinish registrations at the compiler boundary
        self.compiled_text = []      # generated script text (diagnostic only)
        self._imports()
        self._allocators()
        # CRT startup step (_cfltcvt_init): installs the printf float
        # converters that QFinish's CString::Format needs for %f.
        o.run(CRT_FLOAT_INIT)
        self.context = o.alloc(0x220)
        self.area_records = o.alloc(128 * 24)
        o.write(self.context + 0x198, self.area_records, 0)
        self.instance = o.alloc(0xc0)
        self._units(case.get("units", []))
        for name in case.get("groups", []):
            # An empty native group array; members are added by AddObject.
            self.groups[name] = o.alloc(20)
        self._player(case)
        self._boundaries(case)
        # Static constructor boundary: QStart's quest-name CString starts empty.
        o.write(QUEST_NAME, o.ints(EMPTY_STRING)[0])

    # ---------------------------------------------------------------- supplied
    def _imports(self):
        o = self.o
        names = {}
        at = STUBS
        data = bytes(o.uc.mem_read(IAT[0], IAT[1] - IAT[0]))
        for slot in range(IAT[0], IAT[1], 4):
            rva = struct.unpack_from("<I", data, slot - IAT[0])[0]
            if not 0x1000 < rva < 0x400000:
                continue
            raw = bytes(o.uc.mem_read(0x400000 + rva + 2, 40))
            name = raw.split(b"\0", 1)[0].decode("ascii", "replace")
            o.write(slot, at)
            names[at] = name
            at += 2
        self.import_names = names

        def call(address):
            name = names[address]
            if name == "lstrlenA":
                text = o.args(1)[0]
                length = 0
                while text and o.uc.mem_read(text + length, 1) != b"\0":
                    length += 1
                o.ret(length, cleanup=4)
            elif name in ("InterlockedIncrement", "InterlockedDecrement"):
                target = o.args(1)[0]
                value = (o.ints(target)[0] + (1 if name == "InterlockedIncrement" else -1)) & 0xffffffff
                o.write(target, value)
                o.ret(value, cleanup=4)
            elif name in ("EnterCriticalSection", "LeaveCriticalSection"):
                o.ret(cleanup=4)
            else:
                raise RuntimeError(f"Unsupported Win32 import reached: {name}")

        for address in names:
            o.hook(address, lambda address=address: call(address))

    def _allocators(self):
        o = self.o

        def new():
            size = o.args(1)[0]
            o.ret(o.alloc(max(16, size)))       # cdecl operator new

        def fixed():
            # Size classes are 64..512 data bytes plus the 12-byte header.
            o.ret(o.alloc(0x220))

        o.hook(OPERATOR_NEW, new)
        o.hook(OPERATOR_DELETE, lambda: o.ret())
        o.hook(FIXED_ALLOC, fixed)
        o.hook(FIXED_FREE, lambda: o.ret(cleanup=4))

    def string(self, text):
        # A retained CString buffer (refs 1, length, capacity, data).
        raw = text.encode("latin-1")
        allocation = self.o.alloc(16 + len(raw) + 1)
        self.o.write(allocation + 4, 1, len(raw), len(raw))
        self.o.uc.mem_write(allocation + 16, raw + b"\0")
        return allocation + 16

    def read_text(self, pointer):
        out = bytearray()
        while pointer:
            byte = self.o.uc.mem_read(pointer + len(out), 1)
            if byte == b"\0":
                break
            out += byte
        return out.decode("latin-1")

    def _units(self, rows):
        o = self.o
        self.units, self.dead, self.types = [], {}, {}
        vt = o.alloc(0x100)
        o.write(vt + 0x44, 0x1800)
        o.write(vt + 0x30, 0x1810)
        o.write(vt + 0x10, 0x1820)
        o.hook(0x1800, lambda: o.ret(self.dead[o.uc.reg_read(UC_X86_REG_ECX)]))
        o.hook(0x1810, lambda: o.ret(self.types[o.uc.reg_read(UC_X86_REG_ECX)]))
        # Fixture records stay allocated; releasing a reference is a no-op.
        o.hook(0x1820, lambda: o.ret())
        lever_name = self.string("lever")
        for row in rows:
            unit, stats = o.alloc(0x280), o.alloc(0x50)
            o.write(unit, vt)
            o.write(unit + 0xc, row.get("uid", 1))
            o.floats(unit + 0x1c, *row.get("pos", [0, 0]))
            o.write(unit + 0x170, stats)
            o.write(stats, vt)
            o.floats(stats + 0x28, row.get("hp", 10), row.get("max_hp", 10))
            self.dead[stats] = int(row.get("dead", False))
            lever = row.get("lever")
            self.types[unit] = 0x5d if lever else 0x50
            if lever:
                o.write(unit + 8, 0 if lever.get("enabled", True) else 0x80000)
                o.write(unit + 0xa4, lever_name)
                o.write(unit + 0x238, lever["state"], lever["states"], int(lever.get("cycled", False)))
            self.units.append(unit)

    def _player(self, case):
        o = self.o
        player, client = o.alloc(0x140), o.alloc(0x60)
        self.player = player
        client_vt, stream_vt = o.alloc(0x60), o.alloc(0x20)
        o.write(client, client_vt)
        o.write(client + 0x1c, player)
        # The client's embedded network stream object starts at +0x48.
        o.write(client + 0x48, stream_vt)
        o.write(player + 0x20, client)
        o.write(client_vt + 0x44, 0x1840)
        o.write(client_vt + 0x4c, 0x1844)
        o.write(stream_vt + 8, 0x1848)

        def notify(kind, cleanup):
            self.notifications.append(kind)
            o.ret(cleanup=cleanup)

        o.hook(0x1840, lambda: notify("items_received", 8))
        o.hook(0x1844, lambda: notify("item_removed", 4))
        o.hook(0x1848, lambda: notify("network_bytes", 8))
        o.write(player + 0xc0, case.get("money", 0))
        # Bag list allocation granularity (MFC CList default block size).
        o.write(player + 0xf8, 10)
        # Native constructor builds the empty table; native insertion fills it.
        o.run(GS_CONSTRUCT, player + 0xc4)
        for key, value in case.get("variables", []):
            o.run(GS_INSERT, player + 0xc4, [self.string(key), _f32_bits(value)])
        catalog = {name.lower(): ident for name, ident in case.get("catalog", [])}
        self.catalog = catalog
        item_vt = o.alloc(0x40)
        o.write(item_vt + 0x10, 0x1820)
        self.item_vt = item_vt
        initial = case.get("quest_items", [])
        if initial:
            container = o.alloc(0x20)
            o.run(LIST_INIT, container, [10])
            for name in initial:
                o.run(LIST_ADD, container, [self.item(catalog[name.lower()])])
            o.run(BAG_APPEND, player, [container, 0])
        self.notifications.clear()

    def item(self, ident):
        record = self.o.alloc(0x60)
        self.o.write(record, self.item_vt)
        self.o.write(record + 0x10, 0x3009)
        self.o.write(record + 0x4c, ident)
        return record

    def _boundaries(self, case):
        o = self.o
        o.hook(ADDRESSES["original"]["player"], lambda: o.ret(self.player if o.args(1)[0] == 0 else 0, cleanup=4))
        o.hook(ADDRESSES["original"]["network"], lambda: o.ret(0))
        o.hook(CLEANUP, lambda: o.ret())

        def factory():
            name = self.read_text(o.args(1)[0]).lower()
            o.ret(self.item(self.catalog[name]) if name in self.catalog else 0, cleanup=4)

        o.hook(ITEM_FACTORY, factory)
        no_record = o.alloc(4)
        o.hook(LEVER_DB, lambda: o.ret(no_record, cleanup=4))
        world, world_vt = o.alloc(0x100), o.alloc(0x80)
        o.write(world, world_vt)
        o.write(world_vt + 0x68, 0x184c)
        o.hook(0x184c, lambda: o.ret(0))
        o.hook(WORLD, lambda: o.ret(world))

        def compiler():
            text_object = o.args(1)[0]
            self.compiled_text.append(self.read_text(o.ints(text_object)[0]))
            self.compiled.append({"quest": self.read_text(o.ints(QUEST_NAME)[0]),
                                  "objectives": self.objectives()})
            o.ret(cleanup=8)

        o.hook(COMPILER, compiler)

    # ---------------------------------------------------------------- program
    def statement(self, statement, at):
        if "set" in statement:
            expression = {"call": "_SetGlobal", "args": [self.global_indices[statement["set"]], 0, statement["value"]]}
            return self.compile(expression, at)
        if statement["call"] not in COMMANDS:
            raise ValueError("Unsupported quest command " + statement["call"])
        command = self.compile({"call": statement["call"], "args": statement["args"]}, at)
        if statement["call"] == "For":
            self.o.write(command + 0x90, self.body(statement["body"]))
        return command

    def body(self, statements):
        o = self.o
        records = o.alloc(max(1, len(statements)) * 0x94)
        for i, statement in enumerate(statements):
            self.statement(statement, records + i * 0x94)
        vector = o.alloc(20)
        o.write(vector + 4, records, len(statements))
        return vector

    # ---------------------------------------------------------------- observe
    def gs_table(self):
        o = self.o
        table = self.player + 0xc4
        begin, end = o.ints(table + 4, 2)
        chains = []
        heads = o.ints(begin, (end - begin) // 4)
        for index, node in enumerate(heads):
            chain = []
            while node:
                following, key, value = o.ints(node, 3)
                chain.append([self.read_text(key), value])
                node = following
                if len(chain) > 100000:
                    raise RuntimeError("Corrupt native GS chain")
            if chain:
                chains.append([index, chain])
        return {"capacity": (end - begin) // 4, "count": o.ints(table + 0x10)[0], "chains": chains}

    def bag(self):
        o = self.o
        out, node = [], o.ints(self.player + 0xe4)[0]
        while node:
            following, _, item = o.ints(node, 3)
            out.append(o.ints(item + 0x4c)[0] if o.ints(item + 0x10)[0] == 0x3009 else -1)
            node = following
        if len(out) != o.ints(self.player + 0xec)[0]:
            raise RuntimeError("Native bag count disagrees with its list")
        return out

    def objectives(self):
        o = self.o
        data, count = o.ints(OBJECTIVE_ARRAY + 4, 2)
        out = []
        for i in range(count):
            kind, text, value = o.ints(data + 12 * i, 3)
            out.append([OBJECTIVES.get(kind, hex(kind)), self.read_text(text), value])
        return out

    def group_members(self, name):
        o = self.o
        entries, count = o.ints(self.groups[name] + 4, 2)
        index = {unit: i for i, unit in enumerate(self.units)}
        return [index.get(address, -1) for address in (o.ints(entries, count) if count else [])]

    def levers(self):
        o = self.o
        out = []
        for row, unit in zip(self.case.get("units", []), self.units):
            if row.get("lever"):
                out.append({"state": o.ints(unit + 0x238)[0] if o.ints(unit + 0x238)[0] < 0x80000000 else o.ints(unit + 0x238)[0] - (1 << 32),
                            "enabled": not o.ints(unit + 8)[0] & 0x80000})
        return out


def capture(o, case):
    if o.campaign != "original":
        raise ValueError("quest command addresses are qualified for the base executable only")
    fixture = CommandFixture(o, case)
    globals_at = o.alloc(max(1, len(fixture.global_indices)) * 4)
    o.write(fixture.context + 0xa4, globals_at, len(fixture.global_indices))
    for name, value in case.get("globals", {}).items():
        o.floats(globals_at + fixture.global_indices[name] * 4, value)
    vector = fixture.body(case["body"])
    thread, killed = o.alloc(0xc0), o.alloc(4)
    o.write(thread, vector, 0, 0, -1, killed)
    observations = [fixture.compile(e) for e in case.get("observe", [])]
    output = o.alloc(4)
    states = []
    for _ in case["ticks"]:
        o.run(DISPATCH, thread, [fixture.context])
        observed = []
        for command in observations:
            o.run(ADDRESSES["original"]["eval"], command, [fixture.context, fixture.instance, output])
            observed.append(o.ints(output)[0])
        states.append({
            "gs": fixture.gs_table(),
            "bag": fixture.bag(),
            "money": struct.unpack("<i", struct.pack("<I", o.ints(fixture.player + 0xc0)[0]))[0],
            "levers": fixture.levers(),
            "groups": {name: fixture.group_members(name) for name in case.get("groups", [])},
            "journal": {"recording": fixture.read_text(o.ints(QUEST_NAME)[0]),
                        "compiled": [dict(c) for c in fixture.compiled]},
            "globals": {name: o.ints(globals_at + i * 4)[0] for name, i in fixture.global_indices.items()},
            "observed_bits": observed,
            "finished": o.ints(thread + 4)[0] >= len(case["body"]),
            "killed": bool(o.ints(killed)[0]),
        })
    return states


CAPTURES = {kind: capture for kind in [
    "quest_cmd_gsvar", "quest_cmd_items", "quest_cmd_groups", "quest_cmd_levers", "quest_cmd_journal"]}
