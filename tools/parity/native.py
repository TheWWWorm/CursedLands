"""Bounded execution of the user's original x86 executable, never a formula port.

The loader never writes game.exe. Hooks supply only boundaries declared by each
contract. Entry/exit addresses are locked to the executable SHA-256. This is
subsystem replay in Unicorn, not a claim that the full Windows game was run.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

import unicorn
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import (
    UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_EBP, UC_X86_REG_ECX,
    UC_X86_REG_EDI, UC_X86_REG_EIP, UC_X86_REG_ESP, UC_X86_REG_FPCW,
)
from cases import REFERENCES
from compare import digest

STOP = 0x1000


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def float_bits(value):
    return struct.unpack("<I", struct.pack("<f", value))[0]


class Original:
    def __init__(self, data, control=0x27f):
        pe = struct.unpack_from("<I", data, 0x3c)[0]
        count, opt_size = struct.unpack_from("<H12xH", data, pe + 6)
        opt = pe + 24
        base = struct.unpack_from("<I", data, opt + 28)[0]
        size = struct.unpack_from("<I", data, opt + 56)[0]
        self.uc = Uc(UC_ARCH_X86, UC_MODE_32)
        self.uc.mem_map(base, (size + 4095) & ~4095)
        for i in range(count):
            _, va, raw_size, raw = struct.unpack_from("<4I", data, opt + opt_size + 40 * i + 8)
            self.uc.mem_write(base + va, data[raw:raw + raw_size])
        # Windows SEH prologues read/write FS:[0]. The fixture supplies an
        # empty exception-chain page; exceptions are never handled here.
        self.uc.mem_map(0, 0x2000)
        self.uc.mem_map(0x1000000, 0x200000)
        self.uc.mem_map(0x9000000, 0x200000)
        self.uc.reg_write(UC_X86_REG_FPCW, control)
        self.heap = 0x1000000
        self.hooks = []
        self.campaign = "original"

    def close(self):
        # Break callback ownership cycles so a large suite stays bounded.
        for handle in self.hooks:
            self.uc.hook_del(handle)
        self.hooks.clear()

    def hook(self, address, callback):
        self.hooks.append(self.uc.hook_add(
            UC_HOOK_CODE, lambda uc, pc, size, user: callback(), begin=address, end=address))

    def alloc(self, size):
        result = self.heap
        self.heap += (size + 15) & ~15
        if self.heap >= 0x1200000:
            raise RuntimeError("Native fixture heap exhausted")
        return result

    def write(self, at, *values):
        self.uc.mem_write(at, struct.pack("<" + "I" * len(values), *(int(v) & 0xffffffff for v in values)))

    def ints(self, at, count=1):
        return list(struct.unpack("<" + "I" * count, self.uc.mem_read(at, count * 4)))

    def floats(self, at, *values):
        self.uc.mem_write(at, struct.pack("<" + "f" * len(values), *values))

    def number(self, at):
        return struct.unpack("<f", self.uc.mem_read(at, 4))[0]

    def args(self, count):
        return self.ints(self.uc.reg_read(UC_X86_REG_ESP) + 4, count)

    def ret(self, value=0, cleanup=0):
        sp = self.uc.reg_read(UC_X86_REG_ESP)
        self.uc.reg_write(UC_X86_REG_EIP, self.ints(sp)[0])
        self.uc.reg_write(UC_X86_REG_ESP, sp + 4 + cleanup)
        self.uc.reg_write(UC_X86_REG_EAX, value & 0xffffffff)

    def run(self, address, this=0, args=(), end=STOP):
        self.write(0x91ff000, STOP, *args)
        self.uc.reg_write(UC_X86_REG_ESP, 0x91ff000)
        self.uc.reg_write(UC_X86_REG_ECX, this)
        self.slice(address, end)
        return self.uc.reg_read(UC_X86_REG_EAX)

    def slice(self, address, end, alternatives=()):
        self.uc.emu_start(address, end, timeout=2_000_000, count=1_000_000)
        stopped = self.uc.reg_read(UC_X86_REG_EIP)
        if stopped not in (end, *alternatives):
            raise RuntimeError(f"Native replay stopped unexpectedly at {stopped:#x}, expected {end:#x}")


def clock(o, case):
    engine, api = o.alloc(16), o.alloc(16)
    o.uc.mem_write(api, b"\xc3")
    o.write(0x73b6a0, api)
    o.write(0x78ff34, case["interval_ms"])
    for address in [0x79bc54, 0x79bc58, 0x79bc44, 0x7af614, 0x79b9ec]:
        o.write(address, 0)
    now, counts = [0], [0]
    o.hook(api, lambda: o.ret(now[0]))
    o.hook(0x500960, lambda: o.ret(engine))
    o.hook(0x5790e0, lambda: o.ret(cleanup=4))
    for address in [0x4122d0, 0x566ef0, 0x566ec0, 0x57c700]:
        o.hook(address, lambda: o.ret())
    o.hook(0x566e20, lambda: o.ret(1))

    def tick():
        counts[0] += 1
        o.ret(1)

    o.hook(0x58dff0, tick)
    o.hook(0x5641f0, lambda: o.ret(1))
    o.hook(0x40fb30, lambda: o.ret(cleanup=4))
    o.hook(0x457602, o.uc.emu_stop)
    states = []
    for timestamp, active in case["frames"]:
        before = counts[0]
        now[0] = timestamp & 0xffffffff
        o.write(engine + 4, int(active))
        o.uc.reg_write(UC_X86_REG_ESP, 0x91f0000)
        o.uc.reg_write(UC_X86_REG_EBP, 0x91f1000)
        o.uc.reg_write(UC_X86_REG_EDI, 0)
        o.slice(0x4571c1, 0x457405, (0x457602,))
        states.append({"ticks": counts[0] - before, "total_ticks": counts[0],
                       "remainder_ms": o.ints(0x79bc54)[0],
                       "draw_fraction": o.number(0x7afc98),
                       "consumed_ms": o.ints(0x79b9e8)[0]})
    return states


def cast_rank(o, case):
    vt = o.alloc(0xe0)
    o.write(vt + 0xdc, 0x1800)
    o.hook(0x1800, lambda: o.ret(o.ints(o.uc.reg_read(UC_X86_REG_ECX) + 0x28)[0]))
    o.hook(0x52ca10, lambda: o.ret())
    for address in [0x58eb7e, 0x58ec8c]:
        o.hook(address, o.uc.emu_stop)
    units = {}
    for i, row in enumerate(case["units"]):
        unit = o.alloc(0x40)
        o.write(unit, vt)
        o.floats(unit + 0x1c, *row["pos"])
        o.write(unit + 0x28, int(row.get("dead", False)))
        units[i] = unit
    target = case["target"]
    point = o.alloc(12)
    o.floats(point, *case["point"])
    remaining = case["pool"].copy()
    if target >= 0:
        if target in remaining:
            remaining.remove(target)
        remaining.insert(0, target)
    states = []
    # Include the terminal selection so dead-only/empty pools are observed.
    while True:
        nodes = [o.alloc(12) for _ in remaining]
        for i, key in enumerate(remaining):
            o.write(nodes[i], nodes[i + 1] if i + 1 < len(nodes) else 0,
                    nodes[i - 1] if i else 0, units[key])
        sp = 0x91fe000
        o.uc.mem_write(sp, bytes(0x100))
        o.write(sp + 0x34, nodes[0] if nodes else 0, nodes[-1] if nodes else 0, len(nodes), 0)
        o.write(sp + 0x68, units.get(target, 0), point)
        o.uc.reg_write(UC_X86_REG_ESP, sp)
        o.uc.reg_write(UC_X86_REG_EBX, nodes[0] if nodes else 0)
        o.uc.reg_write(UC_X86_REG_EBP, 0)
        o.slice(0x58eaab, STOP, (0x58eb7e, 0x58ec8c))
        chosen = o.uc.reg_read(UC_X86_REG_EBP)
        # Read the native list after native dead-node erasures.
        pointer = o.ints(sp + 0x34)[0]
        remaining = []
        while pointer:
            address = o.ints(pointer + 8)[0]
            remaining.append(next(i for i, unit in units.items() if unit == address))
            pointer = o.ints(pointer)[0]
            if len(remaining) > len(units):
                raise RuntimeError("Corrupt native candidate list")
        key = next((i for i, unit in units.items() if unit == chosen), -1)
        if key >= 0:
            remaining.remove(key)
        states.append({"selected": key, "remaining": remaining.copy()})
        if key < 0 or not remaining:
            break
    return states


def script_random(o, case):
    command, args, result = [o.alloc(n) for n in [0x100, 32, 32]]
    o.write(command, 0x5f, 0, args)
    o.floats(args, case["maximum"])
    word = [0]

    def queue_word():
        o.write(o.uc.reg_read(UC_X86_REG_ECX) + 4, 1, word[0])

    astral = o.campaign == "lost_in_astral"
    if not astral:
        o.hook(0x4667f0, queue_word)
    states = []
    for value in case["words"]:
        word[0] = value
        if astral:
            # Astral's range function consumes its existing 256-word queue.
            # Locate that object from the evaluator's MOV ECX immediate;
            # its independently inspected address is pinned here.
            o.write(0x69d440 + 4, 1, value)
        o.run(0x46cca0 if astral else 0x4b41e0, command, [0, 0, result])
        states.append({"word": value, "value_bits": o.ints(result)[0]})
    return states


def sight_factor(o, case):
    world, unit, creature = [o.alloc(n) for n in [0x100, 0x600, 0xc00]]
    o.hook(0x455950, lambda: o.ret(world))
    o.hook(0x455940, lambda: o.ret(world))
    o.hook(0x553742, lambda: o.uc.reg_write(UC_X86_REG_EIP, STOP))
    o.write(creature + 0x1c, unit)
    o.floats(world + 0x84, case["dark"], case["weather"])
    o.floats(creature + 0x29c, case["night"])
    states = []
    for posture in case["postures"]:
        o.write(unit + 0x264, posture)
        o.run(0x5536b0, creature)
        states.append({"posture": posture, "factor_bits": o.ints(creature + 0x904)[0]})
    return states


def interaction_reach(o, case):
    brain, unit, target, vt, tv, order, output = [o.alloc(n) for n in [0xa00, 0x500, 0x500, 256, 256, 0x30, 4]]
    ur, tr, kind = [o.alloc(16) for _ in range(3)]
    # Fixture-only virtual getters: FLD [provided radius]; RET.
    o.uc.mem_write(ur, b"\xd9\x05" + struct.pack("<I", unit + 0x328) + b"\xc3")
    o.uc.mem_write(tr, b"\xd9\x05" + struct.pack("<I", target + 0x328) + b"\xc3")
    o.uc.mem_write(kind, b"\xb8" + struct.pack("<I", 0x50 if case["kind"] == "steal" else 0x3f) + b"\xc3")
    o.write(brain + 0x1c, unit)
    o.write(unit, vt)
    o.write(target, tv)
    o.write(vt + 0xf0, ur)
    o.write(tv + 0xf0, tr)
    o.write(tv + 0x30, kind)
    own, other = f32(case["own_figure"]), f32(case["target_figure"])
    o.floats(unit + 0x328, own + f32(0.05))
    o.floats(target + 0x328, case["target_use"] if case["kind"] == "lever" else other + f32(0.05))
    o.floats(unit + 0x32c, own + f32(0.2))
    o.floats(target + 0x32c, other)
    o.write(order, 6, {"loot": 0x18a95, "steal": 1, "lever": 0}[case["kind"]], target, 0, 0, 0, 0)
    wrapper = o.alloc(32)
    o.uc.mem_write(wrapper, b"\xff\x74\x24\x04\xb8" + struct.pack("<I", 0x54c070) + b"\xff\xd0\xd9\x1d" + struct.pack("<I", output) + b"\xc2\x04\x00")
    o.run(wrapper, brain, [order])
    return [{"reach_bits": o.ints(output)[0]}]


def attack(o, case, probability=False):
    attacker, defender, a_logic, d_logic, vt, body_vt, record = [o.alloc(n) for n in [0x600, 0x600, 0xc00, 0xc00, 0x100, 0x100, 0x80]]
    o.write(attacker, body_vt)
    o.write(defender, body_vt)
    o.write(attacker + 0x240, a_logic)
    o.write(defender + 0x240, d_logic)
    o.write(a_logic, vt)
    o.write(d_logic, vt)
    o.write(a_logic + 0x1c, attacker)
    o.write(d_logic + 0x1c, defender)
    o.write(vt + 0xc8, 0x1800)
    o.write(body_vt + 0xf0, 0x1840)
    o.floats(attacker + 0x1c, 0, 0, 0)
    o.floats(defender + 0x1c, case["distance"], 0, case.get("height", 0))
    o.floats(defender + 0x328, case["radius"])
    o.uc.mem_write(0x1840, b"\xd9\x05" + struct.pack("<I", defender + 0x328) + b"\xc3")
    o.hook(0x522b80, lambda: o.ret(0))

    def info():
        output = o.args(1)[0]
        attacking = o.uc.reg_read(UC_X86_REG_ECX) == a_logic
        o.uc.mem_write(output, bytes(32))
        o.floats(output + 8, case["attack_actions"] if attacking else case["defence_actions"])
        o.floats(output + 20, case["spread"])
        o.write(output + 24, case["attack"])
        o.write(output + 28, case["defence"])
        o.ret(cleanup=4)

    o.hook(0x1800, info)
    o.write(record + 0x2c, max(case["aim"], 0))
    o.floats(record + 0x34, 1)
    o.write(record + 0x38, int(case["aim"] >= 0))
    hits = []
    for word in range(case["spread"] + 1 if probability else 1):
        o.write(0x7a9d34, 1, word)
        hits.append(bool(o.run(0x553df0, d_logic, [record, attacker])))
    if probability:
        return [{"probability": sum(hits) / len(hits)}]
    return [{"hit": hits[0]}]


CAPTURES = {
    "clock": clock, "cast_rank": cast_rank, "script_random": script_random,
    "sight_factor": sight_factor, "interaction_reach": interaction_reach,
    "attack": attack, "attack_chance": lambda o, c: attack(o, c, True),
}
from native_extended import CAPTURES as EXTRA_CAPTURES
CAPTURES.update(EXTRA_CAPTURES)
from native_quests import CAPTURES as QUEST_CAPTURES
CAPTURES.update(QUEST_CAPTURES)
from native_body import CAPTURES as BODY_CAPTURES
CAPTURES.update(BODY_CAPTURES)


def capture(binary, inputs):
    data = Path(binary).read_bytes()
    fingerprint = hashlib.sha256(data).hexdigest()
    from run import check_inputs
    check_inputs(inputs)
    reference = inputs["reference"]
    if fingerprint != reference["executable_sha256"]:
        raise ValueError("Unsupported original executable/reference. Never reuse addresses for another build.")
    result = {"schema": 1, "role": "original", "input_sha256": digest(inputs),
              "executable_sha256": fingerprint, "emulator": "Unicorn " + unicorn.__version__,
              "fpu_control_word": "0x027f", "scenarios": []}
    for case in inputs["scenarios"]:
        original = Original(data)
        original.campaign = reference["campaign"]
        try:
            states = CAPTURES[case["kind"]](original, case["inputs"])
            result["scenarios"].append({"id": case["id"], "steps": [
                {"step": i, "state": state} for i, state in enumerate(states)]})
            print("ORIGINAL", case["id"], len(states), flush=True)
        except Exception as exc:
            raise RuntimeError(f"{case['id']}: {exc}") from exc
        finally:
            original.close()
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--inputs", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = capture(args.binary, json.loads(args.inputs.read_text()))
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
