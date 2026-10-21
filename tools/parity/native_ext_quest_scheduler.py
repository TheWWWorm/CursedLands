"""Native script-instance scheduler: trigger lifecycle and thread cadence.

Every step is one call of the original per-tick script scheduler 0x4bf000
(the only caller of the condition gate 0x4bb520). The scheduler walks the
running-thread list (context +0x15c) and then the trigger-instance list
(context +0x140); the gate evaluates each block's conditions and starts the
body through 0x4bc420, which runs its first slice at once and queues the rest
as a thread. WorldScript threads are registered by 0x4bcc60 and user scripts
are started by the dispatcher's own script-call case (opcode 8 -> 0x4c7c90 and
parameter binding 0x4bb6a0). Nothing here decides a condition, a dispatch, an
order or a delay; hooks only observe calls and supply the CRT heap.
"""
import struct

from unicorn.x86_const import UC_X86_REG_ECX, UC_X86_REG_EIP, UC_X86_REG_ESP

# native.STOP; importing native here would be circular (it loads extensions).
STOP = 0x1000
from native_quests import OPS, Expressions

SCHEDULER, START_WORLD, BODY, PROGRAM, EVAL = 0x4bf000, 0x4bcc60, 0x4bc420, 0x4b6760, 0x4b41e0
CLEANUP, FATAL, NEW, DELETE = 0x4bec80, 0x480080, 0x70056f, 0x700598
# MFC CFixedAlloc pools used for short CString buffers (thiscall Alloc/Free).
FIXED_ALLOC, FIXED_FREE = 0x6e6bf1, 0x6e6c80
FIXED_POOLS = {0x7c8b70: 0x40, 0x7c8b48: 0x80, 0x7c8b20: 0x100, 0x7c8af8: 0x200}
# Kernel32 imports used by MFC CString copies (IAT slots).
STRING_LENGTH, INTERLOCKED_INCREMENT, INTERLOCKED_DECREMENT = 0x73b250, 0x73b254, 0x73b258
NIL_STRING = 0x796e38
COMMANDS = {"_SetGlobal": 0x78, "Sleep": 7, "SleepUntil": 0xde, "KillScript": 0x79, "_Script": 8}
THREADS, TRIGGERS = 0x15c, 0x140


class SchedulerExpressions(Expressions):
    """Adds instance-local parameter bindings (FUN_004b3f60 store=frame)."""

    def __init__(self, o, locals_by_name=None, **kwargs):
        super().__init__(o, [], **kwargs)
        self.locals = locals_by_name or {}

    def compile(self, expression, at=None):
        args, bindings = [], []
        numeric = strings = 0
        for arg in expression["args"]:
            if isinstance(arg, dict) and "local" in arg:
                kind, index = self.locals[arg["local"]]
                if kind == "float":
                    bindings.append((1, numeric, index))
                    numeric += 1
                    args.append(0)
                else:
                    bindings.append((2, strings, index))
                    strings += 1
                    args.append({"nil_string": True})
                continue
            if isinstance(arg, dict) and "string" in arg:
                strings += 1
            elif not (isinstance(arg, dict) and ({"unit", "iterator", "group"} & set(arg))):
                numeric += 1
            args.append(arg)
        nil = [i for i, a in enumerate(args) if isinstance(a, dict) and "nil_string" in a]
        for i in nil:
            args[i] = {"string": ""}
        command = super().compile(dict(expression, args=args), at)
        if nil:
            # Local string slots start as the shared MFC empty string.
            values = self.o.ints(command + 0x1c)[0]
            order = [i for i, a in enumerate(args) if isinstance(a, dict) and "string" in a]
            for slot, i in enumerate(order):
                if i in nil:
                    self.o.write(values + 4 * slot, self.o.ints(NIL_STRING)[0])
        if bindings:
            values = self.o.alloc(12 * len(bindings))
            for i, binding in enumerate(bindings):
                self.o.write(values + 12 * i, *binding)
            self.o.write(command + 0x58, values, len(bindings))
        return command


def locked_string(o, text):
    """An MFC CString buffer with nRefs=-1: assignments copy, never share."""
    raw = text.encode("ascii") + b"\0"
    at = o.alloc(12 + len(raw))
    o.write(at, 0xffffffff, len(raw) - 1, len(raw) - 1)
    o.uc.mem_write(at + 12, raw)
    return at + 12


def vector(o, records):
    at = o.alloc(20)
    o.write(at + 4, records, 0)
    return at


def scheduler(o, case):
    names = [s["name"] for s in case["scripts"]]
    index = {name: i for i, name in enumerate(names)}
    params = {s["name"]: s.get("params", []) for s in case["scripts"]}
    fixture = SchedulerExpressions(o, environment={})
    fixture.opcodes = OPS | COMMANDS
    fixture.global_indices = {name: i for i, name in enumerate(sorted(case["globals"]))}
    ctx = fixture.context
    globals_at = o.alloc(max(1, len(fixture.global_indices)) * 4)
    o.write(ctx + 0xa4, globals_at, len(fixture.global_indices))
    for name, value in case["globals"].items():
        o.floats(globals_at + fixture.global_indices[name] * 4, value)
    # Scheduler enabled flag; pool block sizes of the two node lists.
    o.write(ctx + 0x1a8, 1)
    o.write(ctx + TRIGGERS + 0x18, 10)
    o.write(ctx + THREADS + 0x18, 10)
    nil = o.ints(NIL_STRING)[0]

    # Supplied boundaries: CRT heap (bump allocator, frees ignored),
    # Kernel32 interlocked counters, temporary-value cleanup, fatal exit.
    def new():
        size = o.args(1)[0]
        o.ret(o.alloc(max(16, size)))
    o.hook(NEW, new)
    o.hook(DELETE, lambda: o.ret())
    # The CString pools (0x7c8af8..0x7c8b70, .bss) are set up by CRT static
    # constructors that never run here: supply each pool's element size.
    for pool, size in FIXED_POOLS.items():
        o.write(pool, 12 + size + 1)

    def fixed_alloc():
        size = o.ints(o.uc.reg_read(UC_X86_REG_ECX))[0]
        if not size:
            raise RuntimeError("Unsupplied MFC fixed allocation pool")
        o.ret(o.alloc(size))
    o.hook(FIXED_ALLOC, fixed_alloc)
    o.hook(FIXED_FREE, lambda: o.ret(cleanup=4))
    o.hook(CLEANUP, lambda: o.ret())
    # Kernel32 imports reached by MFC CString copies: each IAT slot points
    # at a fixture address whose hook performs the documented API effect.
    def interlocked(delta):
        def apply():
            at = o.args(1)[0]
            value = (o.ints(at)[0] + delta) & 0xffffffff
            o.write(at, value)
            o.ret(value, cleanup=4)
        return apply

    def string_length():
        at = o.args(1)[0]
        o.ret(0 if not at else bytes(o.uc.mem_read(at, 4096)).index(b"\0"), cleanup=4)

    imports = o.alloc(16)
    for i, (slot, function) in enumerate([(STRING_LENGTH, string_length),
                                          (INTERLOCKED_INCREMENT, interlocked(1)),
                                          (INTERLOCKED_DECREMENT, interlocked(-1))]):
        o.uc.mem_write(imports + i, b"\xc3")
        o.write(slot, imports + i)
        o.hook(imports + i, function)
    fatal = []

    def stop():
        message = o.uc.mem_read(o.args(1)[0], 120).split(b"\0")[0].decode("latin1")
        fatal.append(message)
        o.uc.emu_stop()
    o.hook(FATAL, stop)

    labels, roots = {}, {}

    def bind_locals(owner):
        # Parameter k of a type is slot k of that type's frame array.
        fixture.locals, counts = {}, {"float": 0, "string": 0, "object": 0}
        for pname, ptype in params.get(owner, []):
            fixture.locals[pname] = (ptype, counts[ptype])
            counts[ptype] += 1

    def statement(stmt, owner, at):
        bind_locals(owner)
        if "set" in stmt:
            return fixture.compile({"call": "_SetGlobal", "args": [fixture.global_indices[stmt["set"]], 0, stmt["value"]]}, at)
        if "script" in stmt:
            target = stmt["script"]
            numeric, strings, objects = [index[target]], [{"string": target}], []
            for (pname, ptype), value in zip(params[target], stmt.get("args", [])):
                if ptype == "object":
                    if value is not None:
                        raise ValueError("Script-call fixtures pass NULL objects only")
                    objects.append({"unit": -1})
                elif ptype == "string":
                    strings.append(value)
                else:
                    numeric.append(value)
            command = fixture.compile({"call": "_Script", "args": numeric + strings + objects}, at)
            # Command parameter vectors carry their sizes for 0x4bb6a0.
            o.write(command + 0xc, len(numeric))
            o.write(command + 0x20, len(strings))
            o.write(command + 0x34, len(objects))
            # Caller string arguments are locked copies (assignment copies them).
            if len(strings) > 1:
                values = o.ints(command + 0x1c)[0]
                for i, value in enumerate(strings[1:], 1):
                    o.write(values + 4 * i, locked_string(o, value["string"]))
            return command
        if stmt["call"] not in ("Sleep", "SleepUntil", "KillScript"):
            raise ValueError("Unsupported scheduler statement")
        return fixture.compile(stmt, at)

    def body(stmts, label, owner):
        records = o.alloc(max(1, len(stmts)) * 0x94)
        for i, stmt in enumerate(stmts):
            statement(stmt, owner, records + i * 0x94)
        result = vector(o, records)
        o.write(result + 8, len(stmts))
        labels[result] = label
        return result

    declarations = o.alloc(max(1, len(names)) * 0xc0)
    o.write(ctx + 0x90, declarations)
    owners = {}
    for i, script in enumerate(case["scripts"]):
        decl = declarations + i * 0xc0
        o.write(decl + 4, nil, nil)
        blocks = o.alloc(max(1, len(script["blocks"])) * 8)
        for b, block in enumerate(script["blocks"]):
            label = f"{script['name']}.{b}"
            conds = o.alloc(max(1, len(block["conds"])) * 0x94)
            for c, expression in enumerate(block["conds"]):
                bind_locals(script["name"])
                fixture.compile(expression, conds + c * 0x94)
                roots[conds + c * 0x94] = f"{label}.{c}"
            cv = vector(o, conds)
            o.write(cv + 8, len(block["conds"]))
            bv = body(block["body"], label, script["name"])
            owners[bv] = script["name"]
            o.write(blocks + 8 * b, cv, bv)
        o.write(decl + 0x10, blocks, len(script["blocks"]))
        kinds = [ptype for _, ptype in script.get("params", [])]
        floats = kinds.count("float")
        if floats:
            o.write(decl + 0x24, o.alloc(4 * floats), floats)
        if kinds.count("string"):
            count = kinds.count("string")
            values = o.alloc(4 * count)
            o.write(values, *([nil] * count))
            o.write(decl + 0x4c, values, count)
        if kinds.count("object"):
            count = kinds.count("object")
            o.write(decl + 0x74, o.alloc(4 * count), count)
    world = body(case["world"], "World", "")
    injected = set()

    trace = []

    def on_eval():
        command = o.uc.reg_read(UC_X86_REG_ECX)
        if command in roots:
            trace.append("c:" + roots[command])
    o.hook(EVAL, on_eval)
    o.hook(BODY, lambda: trace.append("fire:" + labels[o.args(1)[0]]))

    def on_run():
        thread = o.uc.reg_read(UC_X86_REG_ECX)
        # Only queued threads (pool nodes); a body's first slice runs on the
        # stack of 0x4bc420 and was already reported as its dispatch.
        if thread >= 0x9000000:
            return
        vec = o.ints(thread)[0]
        if vec in injected or o.ints(thread + 4)[0] >= o.ints(vec + 8)[0]:
            return
        trace.append("run:" + labels[vec])
    o.hook(PROGRAM, on_run)

    def call(address, this, args=()):
        o.write(0x91ff000, STOP, *args)
        o.uc.reg_write(UC_X86_REG_ESP, 0x91ff000)
        o.uc.reg_write(UC_X86_REG_ECX, this)
        o.uc.emu_start(address, STOP, timeout=5_000_000, count=5_000_000)
        stopped = o.uc.reg_read(UC_X86_REG_EIP)
        if stopped != STOP and not fatal:
            raise RuntimeError(f"Native scheduler stopped unexpectedly at {stopped:#x}")

    def observe():
        scripts, bodies = {}, {}
        node = o.ints(ctx + TRIGGERS + 4)[0]
        while node:
            blocks = o.ints(node + 8 + 0x10)[0]
            name = owners[o.ints(blocks + 4)[0]]
            scripts[name] = scripts.get(name, 0) + 1
            node = o.ints(node)[0]
        node = o.ints(ctx + THREADS + 4)[0]
        while node:
            vec = o.ints(node + 8)[0]
            if vec not in injected and o.ints(node + 12)[0] < o.ints(vec + 8)[0]:
                bodies[labels[vec]] = bodies.get(labels[vec], 0) + 1
            node = o.ints(node)[0]
        return {"trace": list(trace),
                "globals": {name: o.ints(globals_at + i * 4)[0] for name, i in fixture.global_indices.items()},
                "scripts": scripts, "bodies": bodies, "fatal": fatal[0] if fatal else ""}

    call(START_WORLD, ctx, [world])
    states = []
    for number, tick in enumerate(case["ticks"]):
        trace.clear()
        if fatal:
            states.append(observe())
            continue
        for name, value in tick.get("globals", {}).items():
            o.floats(globals_at + fixture.global_indices[name] * 4, value)
        if "briefing" in tick:
            event = tick["briefing"]
            # 0x592090 registers `WorldScript( GSSetVar(..., 2)
            # #OnBriefingComplete(...) )`; its flag is a numeric global here.
            carrier = body([{"set": event["flag"], "value": 2},
                            {"script": event["script"], "args": event.get("args", [])}], f"Briefing@{number}", "")
            injected.add(carrier)
            call(START_WORLD, ctx, [carrier])
        call(SCHEDULER, ctx)
        states.append(observe())
    return states


CAPTURES = {"quest_scheduler": scheduler}
