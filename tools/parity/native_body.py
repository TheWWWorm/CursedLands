"""Execute original body/effect routines with supplied records, without hooks."""
import struct


def word(value):
    return struct.unpack("<I", struct.pack("<f", value))[0]


def body_health(o, case):
    body = o.alloc(0x800)
    for i, p in enumerate(case["parts"]):
        at = body + 0x110 + i * 0xf4
        o.write(at, p["type"])
        o.write(at + 0xe0, p["state"])
        o.floats(at + 0xe4, p["cur"], p["max"], p["size"], p["lethal"])
    maximum = case["max_hp"]
    output, argument, wrapper = o.alloc(4), o.alloc(4), o.alloc(32)
    # Keep executable wrapper bytes immutable: Unicorn may retain a translated
    # block after host mem_write. Read the changing argument from data memory.
    code = b"\xff\x35" + struct.pack("<I", argument)
    code += b"\xe8" + struct.pack("<i", 0x5259b0 - (wrapper + 11))
    code += b"\xd9\x1d" + struct.pack("<I", output) + b"\xc3"
    o.uc.mem_write(wrapper, code)

    def observation():
        # Native x87 result is stored at the same float32 boundary as the
        # original small-stat HP record. No Python arithmetic calculates HP.
        o.floats(argument, maximum)
        o.run(wrapper, body)
        return {"hp_bits": o.ints(output)[0], "max_hp_bits": word(maximum),
                "parts": [{"state": o.ints(body + 0x1f0 + i * 0xf4)[0],
                           "cur_bits": o.ints(body + 0x1f4 + i * 0xf4)[0],
                           "max_bits": o.ints(body + 0x1f8 + i * 0xf4)[0]} for i in range(6)]}

    states = [observation()]
    for operation in case["operations"]:
        if operation["kind"] == "heal":
            o.run(0x525800, body, [word(maximum), word(operation["value"])])
        elif operation["kind"] == "rescale":
            maximum = operation["value"]
            o.run(0x525a70, body, [word(maximum)])
        elif operation["kind"] != "query":
            raise ValueError("Unsupported body operation")
        states.append(observation())
    return states


def effect_lifetime(o, case):
    effect = o.alloc(20)
    o.write(effect + 4, case["counter"])
    alive = True
    states = []
    for _ in case["ticks"]:
        if alive:
            alive = bool(o.run(0x6884f0, effect) & 0xff)
        counter = struct.unpack("<i", o.uc.mem_read(effect + 4, 4))[0] if alive else None
        states.append({"alive": alive, "ticks": counter})
    return states


CAPTURES = {"body_health": body_health, "effect_lifetime": effect_lifetime}
