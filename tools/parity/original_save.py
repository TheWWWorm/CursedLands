#!/usr/bin/env python3
"""Read the original game's save files (saves\\<slot>\\*.sav).

Container (base loader 579830): u32 magic (0xdead scenario.sav, 0x102
mission.sav and zone files), u32 version (0x74), u32 checksum (version
> 0x6b), u8 packed flag (version > 0x71), then the payload. A packed payload is
unpacked by the executable's own Nival LZ decoder (430960, state object
42fca0) run in Unicorn; nothing of the codec is reimplemented here. The
checksum (h ^= dword; h *= (h & 0xfc) | 3, over the unpacked dwords) is
verified. Lost in Astral writes the same container and codec.

Campaign record (written 661bd0, read 661880): the party's zone name and
item containers, then u32 hero count and the 0x784-byte hero records
(read 65f970: five strings, u32, the 0x704-byte stats block, 12 bytes, four
id lists, string, u32 u32 u8 u32 u32, name), the GS var table (460fe0 /
461260: name, f32 ... "") and the money as two u32s XORed (661b81 / 661b98).
scenario.sav keeps the record as the zone was entered (chunk 2, the object
whose body is 1: one byte, 2: {1: u32, 2: record}); mission.sav holds the
live one. The item containers before the hero count are not decoded: the hero
count is found by parsing forward from each offset and accepting only a
complete, structurally valid run of hero records and var table.
"""
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

from cases import REFERENCE

DECODER = {"state_init": 0x42fca0, "decode": 0x430960, "buffer_init": 0x4da7f0,
           "new": 0x70056f, "delete": 0x700598}


def checksum(data):
    h = 0
    for (w,) in struct.iter_unpack("<I", data[:len(data) & ~3]):
        h ^= w
        h = (h * ((h & 0xfc) | 3)) & 0xffffffff
    return h


class Decoder:
    """The original's LZ decoder in Unicorn; one instance decodes many files."""

    def __init__(self, exe):
        from native import Original
        data = Path(exe).read_bytes()
        sha = hashlib.sha256(data).hexdigest()
        if sha != REFERENCE["executable_sha256"]:
            raise SystemExit(f"{exe}: not the verified base-game game.exe ({sha})")
        self.o = Original(data)
        self.o.uc.mem_map(0x20000000, 0x8000000)
        self.top = 0x20000000

        def new():
            n = self.o.args(1)[0]
            p = self.top
            self.top += (n + 15) & ~15
            if self.top >= 0x28000000:
                raise RuntimeError("decoder heap exhausted")
            self.o.ret(p)
        self.o.hook(DECODER["new"], new)
        self.o.hook(DECODER["delete"], lambda: self.o.ret())

    def _buffer(self, data=b""):
        o = self.o
        b = o.alloc(0x20)
        o.run(DECODER["buffer_init"], this=b)
        if data:
            p = self.top
            self.top += (len(data) + 15) & ~15
            o.uc.mem_write(p, data)
            o.write(b + 4, p, p, p + len(data), p + len(data))   # begin, position, capacity, size
        return b

    def unpack(self, payload):
        from native import STOP
        from unicorn.x86_const import UC_X86_REG_ECX, UC_X86_REG_ESP
        o = self.o
        self.top = 0x20000000
        o.heap = 0x1000000
        state = o.alloc(0x2830)
        o.run(DECODER["state_init"], this=state)
        src, dst = self._buffer(payload), self._buffer()
        o.write(0x91ff000, STOP, src, dst)
        o.uc.reg_write(UC_X86_REG_ESP, 0x91ff000)
        o.uc.reg_write(UC_X86_REG_ECX, state)
        o.uc.emu_start(DECODER["decode"], STOP, timeout=0, count=0)   # large zones exceed the slice budget
        begin, position, _, size = o.ints(dst + 4, 4)
        return bytes(o.uc.mem_read(begin, max(position, size) - begin))


def read_container(path, decoder):
    raw = Path(path).read_bytes()
    magic, version = struct.unpack_from("<II", raw)
    offset, stored, packed = 8, None, False
    if version > 0x6b:
        stored = struct.unpack_from("<I", raw, offset)[0]
        offset += 4
    if version > 0x71:
        packed = raw[offset] != 0
        offset += 1
    body = decoder.unpack(raw[offset:]) if packed else raw[offset:]
    if stored is not None and checksum(body) != stored:
        raise ValueError(f"{path}: checksum mismatch")
    return {"magic": magic, "version": version, "data": body}


class Reader:
    def __init__(self, data, offset, end):
        self.d, self.o, self.end = data, offset, end

    def u32(self):
        v = struct.unpack_from("<I", self.d, self.o)[0]
        self.o += 4
        return v

    def f32(self):
        v = struct.unpack_from("<f", self.d, self.o)[0]
        self.o += 4
        return v

    def u8(self):
        v = self.d[self.o]
        self.o += 1
        return v

    def raw(self, n):
        if self.o + n > self.end:
            raise ValueError("past end")
        v = self.d[self.o:self.o + n]
        self.o += n
        return v

    def cstr(self):
        e = self.d.index(b"\0", self.o, min(self.end, self.o + 257))
        v = self.d[self.o:e]
        if any(c < 32 for c in v):
            raise ValueError("string")
        self.o = e + 1
        return v.decode("cp1251")


def read_hero(r):
    h = {"strings": [r.cstr() for _ in range(5)], "u1c": r.u32()}
    h["stats"] = r.raw(0x704).hex()
    h["b724"] = r.raw(12).hex()
    h["lists"] = []
    for _ in range(4):
        n = r.u32()
        if n > 4096:
            raise ValueError("list")
        h["lists"].append([r.u32() for _ in range(n)])
    h["name"] = r.cstr()
    h["u770"], h["u774"], h["b778"], h["u77c"], h["u780"] = r.u32(), r.u32(), r.u8(), r.u32(), r.u32()
    h["player_name"] = r.cstr()
    if not h["strings"][1].startswith("un"):   # the unit prototype (unhuma, unhufe, ...)
        raise ValueError("prototype")
    return h


def read_vars(r):
    out = {}
    while True:
        name = r.cstr()
        if not name:
            return out
        if name in out:
            raise ValueError("duplicate var")
        out[name] = r.f32()


def find_party(data, start, stop, end, exact_end=None):
    """The first offset in [start, stop) that parses as hero count, heroes,
    vars, money within data[:end]."""
    for p in range(start, min(stop, end - 13)):
        try:
            r = Reader(data, p, end)
            m = r.u32()
            if not 0 < m <= 16:
                continue
            heroes = [read_hero(r) for _ in range(m)]
            gs = read_vars(r)
            if "gtime" not in gs:
                continue
            a, key = r.u32(), r.u32()
            if exact_end is not None and r.o != exact_end:
                continue
            return {"heroes": heroes, "vars": gs, "money": a ^ key, "offset": p, "end": r.o}
        except (ValueError, struct.error, IndexError):
            pass
    raise ValueError("no campaign record found")


def chunks(d, s, e):
    out, o = [], s
    while o < e:
        if o + 2 > e:
            return None
        cid, b = d[o], d[o + 1]
        if b & 1:
            n, p = struct.unpack_from("<I", d, o + 1)[0] >> 1, o + 5
        else:
            n, p = b >> 1, o + 2
        if p + n > e:
            return None
        out.append((cid, p, p + n))
        o = p + n
    return out


def scenario_record(d):
    n = struct.unpack_from("<H", d, 0)[0]
    o = 2
    if n & 1:
        n, o = struct.unpack_from("<I", d, 0)[0], 4
    end = o + (n >> 1)
    top = {cid: (p, q) for cid, p, q in chunks(d, o, end) or []}
    for cid, p, q in chunks(d, *top[2]) or []:
        body = [k for k in chunks(d, p, q) or [] if k[0] == 1] if cid == 1 else []
        inner = chunks(d, body[0][1], body[0][2]) if body else None
        if inner and inner[0][0] == 1 and inner[0][2] - inner[0][1] == 1:
            record = [k for k in inner if k[0] == 2][0]
            fields = [k for k in chunks(d, record[1], record[2]) or [] if k[0] == 2]
            if fields:
                return fields[0][1], fields[0][2]
    raise ValueError("scenario.sav: campaign object not found")


def read_slot(slot, decoder):
    """The live campaign state of a save slot (mission.sav) plus its zone."""
    slot = Path(slot)
    scen = read_container(slot / "scenario.sav", decoder)["data"]
    s, e = scenario_record(scen)
    zone = Reader(scen, s, e).cstr()
    entry = find_party(scen, s, e, e, exact_end=e)
    mission = read_container(slot / "mission.sav", decoder)["data"]
    # Scripts may name "gtime" too; the table is the occurrence a party record
    # parses up to.
    live, at = None, mission.find(b"gtime\0")
    while live is None and at >= 0:
        try:
            live = find_party(mission, max(0, at - 0x10000), at, len(mission))
        except ValueError:
            at = mission.find(b"gtime\0", at + 1)
    if live is None:
        raise ValueError("mission.sav: campaign record not found")
    for h in entry["heroes"] + live["heroes"]:
        h.pop("stats")   # raw unit block: kept out of the JSON summary
    return {"zone": zone, "entry": {"vars": entry["vars"], "money": entry["money"],
                                     "heroes": [h["name"] for h in entry["heroes"]]},
            "live": {"vars": live["vars"], "money": live["money"],
                     "heroes": [{"name": h["name"], "prototype": h["strings"][1], "items": h["lists"]}
                                for h in live["heroes"]]}}


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--game-exe", required=True, type=Path, help="The verified base-game game.exe (decoder)")
    p.add_argument("slot", nargs="+", type=Path, help="An original save slot directory (saves\\saveq, ...)")
    a = p.parse_args()
    decoder = Decoder(a.game_exe)
    json.dump({str(s): read_slot(s, decoder) for s in a.slot}, sys.stdout, indent=1, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
