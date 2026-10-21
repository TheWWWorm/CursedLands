"""Native dialogue triggers: topic lists, zone briefings and mercenary topics.

Every observation comes from instructions of the user's executable. The GS
variable table is constructed by the executable's own constructor (581790)
and filled through its own GSSetVar store routine (460bc0), so bucket
capacity, collision chains, deletion and growth follow real play. Hooks only
supply declared boundaries: heap allocation, a few KERNEL32 primitives,
player/zone/text lookups and presentation calls.
"""
import re
import struct

from unicorn.x86_const import UC_X86_REG_ECX, UC_X86_REG_ESP

A = {
    "gs_table_ctor": 0x581790, "gs_set": 0x460bc0, "gs_get": 0x460af0, "name_id": 0x461360,
    "topic_rows": 0x607320, "topic_open": 0x608b20, "topic_title": 0x607880,
    "zone_check": 0x602c90, "play_selected": 0x6064a0,
    "merc_recalc": 0x591800, "complete": 0x592090,
    "player": 0x594180, "player_object": 0x5699f0, "network": 0x57f440,
    "texts": 0x7af778, "zones": 0x79bef0,
    "new": 0x70056f, "delete": 0x700598, "malloc": 0x6eab91, "free": 0x6ea86d,
    "fixed_alloc": 0x6e6bf1, "fixed_free": 0x6e6c80,
}
# MFC CFixedAlloc pools used by CString (64/128/256/512 characters). Their
# static constructors never ran in this bounded replay, so the fixture heap
# supplies blocks of the pool's documented capacity.
FIXED_POOLS = {0x7c8b70: 64, 0x7c8b48: 128, 0x7c8b20: 256, 0x7c8af8: 512}
IAT = (0x73b000, 0x73b820)
# CRT multibyte tables that _setmbcp fills at process start (never run here):
# _mbctype (index c + 1) and _mbcasemap. Supplied for ASCII letters only, as
# the ANSI code page sets them (_SBUP 0x10 / _SBLOW 0x20 and the case map).
MBCTYPE, MBCASEMAP = 0x7cc160, 0x7cc060
HEAP, HEAP_SIZE = 0x3000000, 0x1000000
STUBS = 0x2000000


def f32_word(value):
    return struct.unpack("<I", struct.pack("<f", value))[0]


def word_f32(word):
    return struct.unpack("<f", struct.pack("<I", word))[0]


class NativeGame:
    """Supplied process boundaries around real native routines."""

    def __init__(self, o, multiplayer=False):
        self.o = o
        self.calls = []
        o.uc.mem_map(STUBS, 0x10000)
        o.uc.mem_map(HEAP, HEAP_SIZE)
        self.top = HEAP
        self.free_blocks = {}
        self.sizes = {}
        self._imports()
        types, casemap = bytearray(257), bytearray(256)
        for c in range(26):
            types[ord("A") + c + 1], casemap[ord("A") + c] = 0x10, ord("a") + c
            types[ord("a") + c + 1], casemap[ord("a") + c] = 0x20, ord("A") + c
        o.uc.mem_write(MBCTYPE, bytes(types))
        o.uc.mem_write(MBCASEMAP, bytes(casemap))
        o.hook(A["new"], lambda: o.ret(self.alloc(o.args(1)[0])))
        o.hook(A["malloc"], lambda: o.ret(self.alloc(o.args(1)[0])))
        o.hook(A["delete"], lambda: (self.release(o.args(1)[0]), o.ret()))
        o.hook(A["free"], lambda: (self.release(o.args(1)[0]), o.ret()))

        def fixed_alloc():
            pool = o.uc.reg_read(UC_X86_REG_ECX)
            o.ret(self.alloc(12 + FIXED_POOLS[pool] + 1))

        o.hook(A["fixed_alloc"], fixed_alloc)
        o.hook(A["fixed_free"], lambda: (self.release(o.args(1)[0]), o.ret(cleanup=4)))
        # Player zero owns the campaign GS store at +0xc4, its party vector at
        # +0xa0/+0xa4 and the current zone name at +0xd8.
        self.player = self.alloc(0x200)
        o.run(A["gs_table_ctor"], self.player + 0xc4)
        current = self.alloc(0x40)
        holder = self.alloc(0x40)
        self.o.write(holder + 0x1c, self.player)
        self.o.write(current + 0x20, holder)
        o.hook(A["player"], lambda: o.ret(self.player if o.args(1)[0] == 0 else 0, cleanup=4))
        o.hook(A["player_object"], lambda: o.ret(holder))
        o.hook(A["network"], lambda: o.ret(int(multiplayer)))
        self.texts = {}
        self._text_archive()

    # -- supplied process boundaries ------------------------------------
    def _imports(self):
        o = self.o

        def length(address):
            n = 0
            while o.uc.mem_read(address + n, 1) != b"\0":
                n += 1
            return n

        def interlocked(address, delta):
            value = (o.ints(address)[0] + delta) & 0xffffffff
            o.write(address, value)
            return value

        supported = {
            "lstrlenA": (1, lambda a: length(a[0])),
            "InterlockedIncrement": (1, lambda a: interlocked(a[0], 1)),
            "InterlockedDecrement": (1, lambda a: interlocked(a[0], -1)),
            "EnterCriticalSection": (1, lambda a: 0),
            "LeaveCriticalSection": (1, lambda a: 0),
            "InitializeCriticalSection": (1, lambda a: 0),
        }
        for index, slot in enumerate(range(*IAT, 4)):
            value = o.ints(slot)[0]
            if not value:
                continue
            name = self.read(0x400000 + value + 2) if value < 0x800000 else f"ordinal_{value & 0xffff}"
            stub = STUBS + index * 4
            o.write(slot, stub)

            def call(name=name):
                if name not in supported:
                    raise RuntimeError(f"Unsupplied import {name} reached from "
                                       f"{o.ints(o.uc.reg_read(UC_X86_REG_ESP))[0]:#x}")
                count, function = supported[name]
                o.ret(function(o.args(count)), cleanup=4 * count)

            o.hook(stub, call)

    def alloc(self, size):
        size = max(16, (size + 15) & ~15)
        reuse = self.free_blocks.get(size)
        if reuse:
            address = reuse.pop()
        else:
            address = self.top
            self.top += size
            if self.top > HEAP + HEAP_SIZE:
                raise RuntimeError("Native fixture heap exhausted")
        self.o.uc.mem_write(address, bytes(size))
        self.sizes[address] = size
        return address

    def release(self, address):
        size = self.sizes.pop(address, None)
        if size:
            self.free_blocks.setdefault(size, []).append(address)

    def string(self, text):
        raw = text.encode("latin-1") + b"\0"
        address = self.alloc(len(raw))
        self.o.uc.mem_write(address, raw)
        return address

    def read(self, address, limit=4096):
        raw = bytes(self.o.uc.mem_read(address, limit))
        return raw.split(b"\0", 1)[0].decode("latin-1")

    def _text_archive(self):
        """texts.res supplied as one archive; its line reader stays native."""
        o = self.o
        texts, head, node, archive, table = [self.alloc(0x40) for _ in range(5)]
        stub = STUBS + 0x8000
        o.write(head, node)
        o.write(node, head)
        o.write(node + 0x14, archive)
        o.write(archive, table)
        o.write(table + 0x14, stub)
        o.write(texts + 0x1c, head)
        o.write(A["texts"], texts)

        def lookup():
            key, size_out = o.args(2)
            data = self.texts.get(self.read(key))
            if not data:
                o.ret(0, cleanup=8)
                return
            raw = data.encode("latin-1")
            address = self.alloc(len(raw) + 1)
            o.uc.mem_write(address, raw)
            o.write(size_out, len(raw))
            o.ret(address, cleanup=8)

        o.hook(stub, lookup)

    # -- native routines ---------------------------------------------------
    def set_var(self, key, value, player=None):
        table = (self.player if player is None else player) + 0xc4
        self.o.run(A["gs_set"], table, [self.string(key), f32_word(value)])

    def get_var(self, key, player=None):
        table = (self.player if player is None else player) + 0xc4
        self.o.run(A["gs_get"], table, [self.string(key)])
        # 460af0 returns on the x87 stack; store ST0 through a tiny fixture.
        return self._st0()

    def _st0(self):
        o = self.o
        out = self.alloc(4)
        code = self.alloc(16)
        o.uc.mem_write(code, b"\xd9\x1d" + struct.pack("<I", out) + b"\xc3")
        o.run(code)
        return o.ints(out)[0]

    def name_id(self, name):
        return self.o.run(A["name_id"], self.string(name))

    def table_keys(self, player=None):
        """The store's chains in native bucket order (diagnostics only)."""
        table = (self.player if player is None else player) + 0xc4
        begin, end = self.o.ints(table + 4, 2)
        keys = []
        for bucket in range(begin, end, 4):
            node = self.o.ints(bucket)[0]
            while node:
                following, key, value = self.o.ints(node, 3)
                keys.append((self.read(key), word_f32(value)))
                node = following
        return keys


def string_array(game, array):
    data, count = game.o.ints(array + 4, 2)
    return [game.read(game.o.ints(data + 4 * i)[0]) for i in range(count)]


def topics(o, case):
    game = NativeGame(o, case.get("multiplayer", False))
    game.texts = dict(case.get("texts", {}))
    for key, value in case["variables"]:
        game.set_var(key, value)
    npc = case["npc"]
    unit = game.alloc(0x40)
    o.write(unit + 0xc, game.name_id(npc.get("id_name", npc["name"])))
    dialog, holder, table = game.alloc(0x300), game.alloc(0x10), game.alloc(0x80)
    # The list widget and its scroll bar are presentation boundaries.
    o.write(holder, table)
    o.write(table + 0x64, STUBS + 0x8010)
    o.hook(STUBS + 0x8010, lambda: o.ret(cleanup=4))
    o.write(dialog + 0x260, holder)
    o.hook(0x5ff830, lambda: o.ret(STUBS + 0x8020, cleanup=16))
    o.hook(0x5fc9e0, lambda: o.ret())
    o.hook(0x65afa0, lambda: o.ret(cleanup=4))
    o.hook(0x6071a0, lambda: o.ret())
    o.run(A["topic_open"], dialog, [unit])
    mode = o.ints(dialog + 0x16c)[0]
    rows = string_array(game, dialog + 0x170)
    if mode not in (0, 1):
        raise RuntimeError(f"Unexpected topic dialog mode {mode}")
    if mode == 1:
        # 608b20 appends its fixed farewell row after the GS-derived rows.
        if not rows or rows[-1] != "goodbye":
            raise RuntimeError("Native topic list did not end with goodbye")
        rows = rows[:-1]
    data = o.ints(dialog + 0x174)[0]
    titles = []
    for i in range(len(rows)):
        out = game.alloc(4)
        o.run(A["topic_title"], 0, [out, o.ints(data + 4 * i)[0]])
        titles.append(game.read(o.ints(out)[0]))
    return [{"open": mode == 1, "topics": rows, "titles": titles}]


def zone_briefing(o, case):
    game = NativeGame(o)
    for key, value in case["variables"]:
        game.set_var(key, value)
    # Zone registry (base 79bef0): one 0x5c-byte record naming the zone.
    record = game.alloc(0x5c)
    o.write(record, game.string(case["zone"]))
    o.write(A["zones"] + 0x18, record, 1)
    # The player's current-zone CString (+0xd8) is built by MFC's own ctor.
    o.run(0x70099e, game.player + 0xd8, [game.string(case["zone"])])
    # A one-member party whose leader reaches the native check.
    leader_id = 0x12345
    member = game.alloc(0x784)
    o.write(member + 0x1c, leader_id)
    o.write(game.player + 0xa0, member, 1)
    leader = game.alloc(0x40)
    o.write(leader + 0xc, leader_id)
    dialog = game.alloc(0x300)
    # The selected-briefing member is an empty MFC CString before selection.
    o.write(dialog + 0x184, o.ints(0x796e38)[0])
    chosen = []

    def play():
        chosen.append(game.read(o.ints(dialog + 0x184)[0]))
        o.ret(cleanup=8)

    # Camera focus and selection marks are presentation; the started
    # conversation is recorded where 6064a0 would begin staging it.
    o.hook(0x566030, lambda: o.ret(cleanup=4))
    o.hook(0x40d3b0, lambda: o.ret(cleanup=4))
    o.hook(0x55fb00, lambda: o.ret(0, cleanup=4))
    o.hook(A["play_selected"], play)
    o.run(A["zone_check"], dialog, [leader])
    return [{"started": bool(chosen), "briefing": chosen[0] if chosen else ""}]


def party_world(game, case):
    """World with player zero, its party vector and zone (591800/592090)."""
    o, player = game.o, game.player
    # Player zero is both the world's player-list entry and its GS store.
    # +0x20 is the network peer whose +0x1c points back to the player and
    # whose embedded +0x48 stream (vtable +8) receives replicated GS writes.
    peer, stream_table = game.alloc(0x80), game.alloc(0x20)
    o.write(player + 0x20, peer)
    o.write(player + 0x24, 0)
    o.write(player + 0xc0, case.get("money", 0))
    o.write(peer + 0x1c, player)
    o.write(peer + 0x48, stream_table)
    o.write(stream_table + 8, STUBS + 0x8030)
    o.hook(STUBS + 0x8030, lambda: o.ret(cleanup=8))
    world = game.alloc(0x13000)
    world_table, players, node = [game.alloc(0x200) for _ in range(3)]
    o.write(world, world_table)
    o.write(world_table + 0x50, STUBS + 0x8040)
    o.hook(STUBS + 0x8040, lambda: o.ret(players))
    o.write(players + 0x38, node)
    o.write(node, 0, 0, player)
    o.write(world + 0x120, game.string(case["zone"]))
    # Party vector: supplied members, their unit identities and life state.
    members = case["party"]
    vector = game.alloc(0x784 * max(1, len(members)))
    units, dead_flags = {}, {}
    unit_table = game.alloc(0x100)
    o.write(unit_table + 0xdc, STUBS + 0x8050)
    o.hook(STUBS + 0x8050, lambda: o.ret(dead_flags[o.uc.reg_read(UC_X86_REG_ECX)]))
    for i, member in enumerate(members):
        identity = game.name_id(member["name"])
        o.write(vector + 0x784 * i + 0x1c, identity)
        if member.get("present", True):
            unit = game.alloc(0x40)
            o.write(unit, unit_table)
            o.write(unit + 0xc, identity)
            units[identity] = unit
            dead_flags[unit] = int(member.get("dead", False))
    o.write(player + 0xa0, vector, len(members))
    o.hook(0x55fb00, lambda: o.ret(units.get(o.args(1)[0], 0), cleanup=4))
    return world


def merc_variables(game, skip=""):
    return dict(sorted((key, value) for key, value in game.table_keys()
                       if key.startswith(("b.merc", "amerc_")) and key != skip))


def merc_recalc(o, case):
    game = NativeGame(o)
    for key, value in case["variables"]:
        game.set_var(key, value)
    world = party_world(game, case)
    o.run(A["merc_recalc"], world)
    return [{"variables": merc_variables(game)}]


COMPLETION = re.compile(r'WorldScript\( GSSetVar\( (-?\d+),"(.*)",2 \) #OnBriefingComplete\( (-?\d+), "(.*)" \) \)$')
RECORD_LISTS = [("give_quests", 0x2c), ("give_quests2", 0x38), ("open_zones", 0x44), ("unknown2", 0x50)]


def briefing_complete(o, case):
    game = NativeGame(o)
    for key, value in case["variables"]:
        game.set_var(key, value)
    world = party_world(game, case)
    # briefings database row (map 7c87c4 lookup 4297a0) is a supplied
    # boundary; give/take item vectors stay empty.
    row = case.get("record")
    cell = game.alloc(4)
    if row is not None:
        record = game.alloc(0x60)
        o.floats(record + 0xc, row.get("experience", 0), row.get("money", 0))
        for field, offset in RECORD_LISTS:
            names = row.get(field, [])
            vector = game.alloc(4 * max(1, len(names)))
            for i, name in enumerate(names):
                o.write(vector + 4 * i, game.string(name))
            o.write(record + offset, vector, vector + 4 * len(names))
        o.write(cell, record)
    o.hook(0x4297a0, lambda: o.ret(cell, cleanup=4))
    experience, scripts, merc_events = [], [], []
    merc_ids = {game.name_id(f"merc{i}"): i for i in range(1, 11)}

    def grant():
        player, amount = o.args(2)
        experience.append(word_f32(amount))
        o.ret(cleanup=8)

    def run_script():
        scripts.append(game.read(o.ints(o.args(1)[0])[0]))
        o.ret(cleanup=8)

    o.hook(0x5911c0, grant)
    o.hook(0x4d23a0, run_script)
    # Party membership changes are recorded, not performed (boundary).
    o.hook(0x662890, lambda: (merc_events.append([int(game.read(o.args(1)[0])[4:]), "hire"]), o.ret(cleanup=12)))
    o.hook(0x6620b0, lambda: (merc_events.append([merc_ids[o.args(1)[0]], "remove"]), o.ret(cleanup=4)))
    o.hook(0x5935c0, lambda: o.ret(cleanup=4))
    # A hired party mercenary's prototype name (only used for the hire event).
    proto = game.alloc(4)
    o.write(proto, game.string("parity_proto"))
    o.hook(0x530930, lambda: o.ret(proto))
    o.run(A["complete"], world, [0, game.string(case["key"])])
    if len(scripts) != 1 or not COMPLETION.match(scripts[0]):
        raise RuntimeError(f"Unexpected completion script {scripts!r}")
    player, key, event_player, event_key = COMPLETION.match(scripts[0]).groups()
    variables = {k: v for k, v in game.table_keys() if k != case["key"]}
    return [{"completion": [int(player), key, 2.0, int(event_player), event_key],
             "money": o.ints(game.player + 0xc0)[0] - (1 << 32 if o.ints(game.player + 0xc0)[0] >> 31 else 0),
             "experience": experience, "merc_events": merc_events,
             "variables": dict(sorted(variables.items()))}]


CAPTURES = {"dialogue_topics": topics, "dialogue_zone": zone_briefing, "dialogue_merc": merc_recalc,
            "dialogue_complete": briefing_complete}
