"""Execute persistent native command streams across supplied logic ticks.

No scheduler, delay, assignment, or condition result is implemented here.
The original dispatcher advances its own instruction pointer and wait counter.
"""
from native_quests import ADDRESSES, OPS, Expressions

COMMANDS = {"_SetGlobal": 0x78, "Sleep": 7, "SleepUntil": 0xde, "KillScript": 0x79}


def program(o, case):
    fixture = Expressions(o, case.get("units", []), environment=case)
    fixture.opcodes = OPS | COMMANDS
    fixture.global_indices = {name: i for i, name in enumerate(sorted(case["globals"]))}
    globals_at = o.alloc(max(1, len(fixture.global_indices)) * 4)
    o.write(fixture.context + 0xa4, globals_at, len(fixture.global_indices))
    for name, value in case["globals"].items():
        o.floats(globals_at + fixture.global_indices[name] * 4, value)
    records = o.alloc(max(1, len(case["body"])) * 0x94)
    for i, statement in enumerate(case["body"]):
        if "set" in statement:
            expression = {"call": "_SetGlobal", "args": [fixture.global_indices[statement["set"]], 0, statement["value"]]}
        else:
            if statement["call"] not in COMMANDS:
                raise ValueError("Unsupported quest program command")
            expression = statement
        # Command records share the native expression's parameter layout.
        # The opcode mapping is explicit; the actual dispatch is never hooked.
        fixture.compile(expression, records + i * 0x94)
    vector, thread, killed = o.alloc(20), o.alloc(0xc0), o.alloc(4)
    o.write(vector + 4, records, len(case["body"]))
    o.write(thread, vector, 0, 0, -1, killed)
    observations = [fixture.compile(e) for e in case["observe"]]
    output = o.alloc(4)
    # Cleanup frees temporary command values; there are none in this fixture.
    o.hook(ADDRESSES[o.campaign]["cleanup"], lambda: o.ret())
    states = []
    for tick in case["ticks"]:
        for name, value in tick.get("globals", {}).items():
            o.floats(globals_at + fixture.global_indices[name] * 4, value)
        o.run(ADDRESSES[o.campaign]["program"], thread, [fixture.context])
        values = []
        for command in observations:
            o.run(ADDRESSES[o.campaign]["eval"], command, [fixture.context, fixture.instance, output])
            values.append(o.ints(output)[0])
        states.append({"values": {name: o.ints(globals_at + index * 4)[0]
                                   for name, index in fixture.global_indices.items()},
                       "observed_bits": values, "finished": o.ints(thread + 4)[0] >= len(case["body"]),
                       "killed": bool(o.ints(killed)[0])})
    return states


CAPTURES = {"quest_program": program}
