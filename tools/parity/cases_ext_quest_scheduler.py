"""Script-instance scheduler: when trigger blocks fire and how threads run.

Inputs only: a small program in the original script language (numeric
globals, DeclareScript/Script blocks, WorldScript), external global changes
per 55 ms logic tick and optional briefing completions. No expected values.
Shapes follow the authored base campaign: `if (...) then ( KillScript ... )`
check/trigger chains, if/else block pairs, per-unit copies, sleeping trigger
bodies and `#OnBriefingComplete( player, szComplete )` handlers.
"""
import random

KIND = "quest_scheduler"
STEP_COUNTS = {KIND: "ticks"}
BRIEFING_PARAMS = (("nPlayer", "float"), ("szComplete", "string"))


def call(name, *args):
    return {"call": name, "args": list(args)}


def g(name):
    return {"global": name}


def setv(name, value):
    return {"set": name, "value": value}


def inc(name, by=1):
    return setv(name, call("Add", g(name), by))


KILL = call("KillScript")


def sleep(n):
    return call("Sleep", n)


def run(name, *args):
    return {"script": name, "args": list(args)}


def script(name, blocks, params=(("this", "object"),)):
    return {"name": name, "params": [list(p) for p in params],
            "blocks": [{"conds": list(conds), "body": list(body)} for conds, body in blocks]}


def contracts(campaign):
    if campaign != "original":
        return {}
    return {KIND: {
        "entry": ["0x4bf000", "0x4bcc60", "0x4bb520", "0x4bc420", "0x4b6760", "0x4c7c90", "0x4bb6a0", "0x4b41e0"],
        "scope": ("Native per-tick script scheduler 0x4bf000 (running-thread list, then trigger-instance list; "
                  "gate 0x4bb520, body dispatch 0x4bc420, dispatcher 0x4b6760, script start 0x4c7c90/0x4bb6a0, "
                  "WorldScript registration 0x4bcc60) versus ScriptVM.tick / _run / spawn / fire_event on the "
                  "production ScriptParser AST: per-tick condition order, dispatches, resumed threads, numeric "
                  "global assignments, live trigger instances, running bodies and fatal script errors."),
        "stubs": ["CRT operator new/delete 0x70056f/0x700598 and MFC CFixedAlloc 0x6e6bf1/0x6e6c80 (fixture bump heap, frees ignored)",
                  "Kernel32 lstrlenA/InterlockedIncrement/InterlockedDecrement import slots 0x73b250-0x73b258",
                  "temporary command cleanup 0x4bec80 (no temporary values in fixture)",
                  "fatal script error 0x480080 records its message and halts the replay",
                  "CString destructor 0x700930 and temporary strings (shared quest fixture)",
                  "player lookup / network mode (shared quest fixture, single player)",
                  "briefing completion 0x592090 represented by its registration of the compiled "
                  "`WorldScript( GSSetVar(...,2) #OnBriefingComplete(...) )` through 0x4bcc60; the GS flag is a numeric global",
                  "remake Briefings.tick automatic-briefing polling"],
        "limits": ("Numeric globals, NULL object parameters and float/string parameters only; no units, AI "
                   "(SleepUntilIdle), For loops, save/load, multiplayer once-per-world rules or the five extra "
                   "0x4bf000 passes 0x592090 makes when its mode field +0x12d64 is 3."),
        "tolerances": {},
    }}


def scenarios(seed=20261020, fuzz=12):
    rows = []

    def add(name, scripts, world, ticks=12, changes=None, briefings=None, globals_=None, boot="event"):
        names = set(globals_ or {})
        briefings = dict(briefings or {})
        if boot == "handler":
            # The script under test is itself the briefing handler: both
            # sides poll it first in the step of the briefing (no spawn).
            if len(scripts) != 1 or world or 0 in briefings:
                raise ValueError("Handler boot takes one script and no WorldScript")
            scripts = [dict(scripts[0], name="#OnBriefingComplete", params=[list(p) for p in BRIEFING_PARAMS])]
            briefings[0] = {"script": "#OnBriefingComplete", "args": [0, {"string": "b.boot"}], "flag": "flag"}
            names.add("flag")
        elif boot == "event":
            # Start the scripts from a briefing handler's first slice. The
            # handler is polled in the tick its WorldScript carrier runs on
            # both sides, so later steps are not offset by WorldScript start.
            if any("call" in s and s["call"] == "Sleep" for s in world) or 0 in briefings:
                raise ValueError("Event boot needs an unsleeping start body at tick 0")
            scripts = scripts + [script("#OnBriefingComplete", [([], [KILL, *world])], BRIEFING_PARAMS)]
            briefings[0] = {"script": "#OnBriefingComplete", "args": [0, {"string": "b.boot"}], "flag": "flag"}
            names.add("flag")
            world = []
        tick_rows = []
        for i in range(ticks):
            row = {}
            if changes and i in changes:
                row["globals"] = changes[i]
            if i in briefings:
                row["briefing"] = briefings[i]
            tick_rows.append(row)
        rows.append({"id": f"{KIND}/{name}", "kind": KIND, "inputs": {
            "globals": {n: 0 for n in sorted(names)} | (globals_ or {}),
            "scripts": scripts, "world": world, "ticks": tick_rows}})

    G = lambda *names, **values: {n: 0 for n in names} | values

    # zone1 VCheck#0#1 -> VTriger#0#15: a check kills itself and starts a trigger.
    add("authored_check_trigger_chain", [
        script("VCheck#0#1", [([call("IsEqual", g("gate"), 1)], [KILL, run("VTriger#0#15", None)])]),
        script("VTriger#0#15", [([], [KILL, setv("step", 1), sleep(3), setv("step", 2)])]),
    ], [sleep(2), run("VCheck#0#1", None)], 14, {5: {"gate": 1}, 9: {"gate": 0}}, globals_=G("gate", "step"), boot="world")
    # basecam VCheck#0#309: if/else through KillScript in each block.
    for name, time in [("night", 2), ("edge_low", 4), ("day", 12), ("edge_high", 23)]:
        add(f"authored_if_else_{name}", [script("VCheck#0#309", [
            ([call("IsGreater", g("t"), 4), call("IsLess", g("t"), 23)], [KILL, setv("r", 1)]),
            ([], [KILL, setv("r", 2)])])], [run("VCheck#0#309", None)], 4, globals_=G("r", t=time))
    add("authored_if_else_world_start", [script("VCheck#0#309", [
        ([call("IsGreater", g("t"), 4), call("IsLess", g("t"), 23)], [KILL, setv("r", 1)]),
        ([], [KILL, setv("r", 2)])])], [run("VCheck#0#309", None)], 4, {1: {"t": 12}}, globals_=G("r", t=2), boot="world")
    add("authored_if_else_late_start", [script("VCheck#0#317", [
        ([call("IsGreater", g("t"), 4), call("IsLess", g("t"), 23)], [KILL, setv("r", 1)]),
        ([], [KILL, setv("r", 2)])])], [sleep(3), run("VCheck#0#317", None)], 6, {2: {"t": 5}}, globals_=G("r", t=2), boot="world")
    # Blocks without KillScript: every block is a separate trigger.
    multi = [([call("IsEqual", g("a"), 1)], [inc("n0")]), ([call("IsEqual", g("b"), 1)], [inc("n1")]),
             ([call("IsEqual", g("c"), 1)], [inc("n2")])]
    add("blocks_without_kill", [script("Multi", multi)], [], 8,
        {1: {"a": 1}, 2: {"b": 1}, 3: {"a": 0}, 4: {"c": 1}, 6: {"a": 1}}, globals_=G("a", "b", "c", "n0", "n1", "n2"), boot="handler")
    add("first_block_kills_siblings", [script("Pair", [
        ([call("IsEqual", g("a"), 1)], [KILL, inc("n0")]), ([call("IsEqual", g("b"), 1)], [inc("n1")])])],
        [], 6, {1: {"b": 1}, 3: {"a": 1}}, globals_=G("a", "b", "n0", "n1"), boot="handler")
    add("second_block_kills", [script("Pair", [
        ([call("IsEqual", g("a"), 1)], [inc("n0")]), ([call("IsEqual", g("b"), 1)], [KILL, inc("n1")])])],
        [], 6, {1: {"a": 1}, 2: {"b": 1}}, globals_=G("a", "b", "n0", "n1"), boot="handler")
    # Re-arming after a body finished, with and without a sleeping body.
    add("rearm_instant_body", [script("Rearm", [([call("IsEqual", g("gate"), 1)], [inc("n")])])],
        [], 9, {2: {"gate": 1}, 6: {"gate": 0}}, globals_=G("gate", "n"), boot="handler")
    add("rearm_empty_conditions", [script("CreateRunPoint1", [([], [inc("n")])])], [], 5, globals_=G("n"), boot="handler")
    add("rearm_sleeping_body", [script("Rearm", [([call("IsEqual", g("gate"), 1)], [inc("n"), sleep(3), inc("done")])])],
        [], 12, {1: {"gate": 1}, 7: {"gate": 0}}, globals_=G("gate", "n", "done"), boot="handler")
    add("rearm_sleep_until_body", [script("Rearm", [([call("IsEqual", g("gate"), 1)],
        [inc("n"), call("SleepUntil", call("IsEqual", g("go"), 1)), inc("done")])])],
        [], 10, {1: {"gate": 1}, 4: {"go": 1}, 5: {"gate": 0}}, globals_=G("gate", "go", "n", "done"), boot="handler")
    # Sleep inside a dispatched body: tick numbering of each slice.
    for first, second in [(0, 1), (1, 1), (2, 3), (3, 0), (5, 2), (0.5, 1.5), (2.5, 3.5), (-1, 1)]:
        add(f"body_sleep_{first}_{second}", [script("VTriger#0#20", [([], [
            KILL, setv("p", 1), sleep(first), setv("p", 2), sleep(second), setv("p", 3)])])],
            [], 12, globals_=G("p"), boot="handler")
    add("body_sleep_until", [script("VTriger#0#21", [([], [KILL, call("SleepUntil", call("IsEqual", g("go"), 1)), setv("p", 1), sleep(1), setv("p", 2)])])],
        [], 8, {3: {"go": 1}, 4: {"go": 0}}, globals_=G("go", "p"), boot="handler")
    add("world_sleep_then_start", [script("VCheck#0#137", [([call("IsEqual", g("gate"), 1)], [KILL, setv("p", 1)])])],
        [setv("p", 5), sleep(2), run("VCheck#0#137", None), setv("p", 6)], 6, {0: {"gate": 1}}, globals_=G("gate", "p"), boot="world")
    # New threads: started by a first slice, a resumed slice or WorldScript.
    child = script("Child", [([], [KILL, inc("seen")])])
    add("spawn_from_first_slice", [script("Parent", [([], [KILL, run("Child", None)])]), child],
        [run("Parent", None)], 4, globals_=G("seen"))
    add("spawn_from_resumed_slice", [script("Parent", [([], [KILL, sleep(2), run("Child", None)])]), child],
        [run("Parent", None)], 6, globals_=G("seen"))
    add("spawn_from_world_first_tick", [child], [run("Child", None)], 3, globals_=G("seen"), boot="world")
    add("spawn_from_event_first_tick", [child], [run("Child", None)], 3, globals_=G("seen"))
    add("spawn_order_three", [script(n, [([], [KILL, setv("seq", call("Add", call("Mul", g("seq"), 10), k))])])
                              for k, n in [(1, "A"), (2, "B"), (3, "C")]],
        [run("A", None), run("B", None), run("C", None)], 3, globals_=G("seq"))
    add("spawn_order_three_world", [script(n, [([], [KILL, setv("seq", call("Add", call("Mul", g("seq"), 10), k))])])
                                    for k, n in [(1, "A"), (2, "B"), (3, "C")]],
        [run("A", None), run("B", None), run("C", None)], 3, globals_=G("seq"), boot="world")
    add("spawn_order_rearmed", [script(n, [([call("IsLess", g("seq"), 10000)], [setv("seq", call("Add", call("Mul", g("seq"), 10), k))])])
                                for k, n in [(1, "A"), (2, "B"), (3, "C")]],
        [run("A", None), run("B", None), run("C", None)], 4, globals_=G("seq"))
    # A sleeping body of an older script and a newer script's trigger.
    add("cross_script_same_tick", [
        script("Old", [([], [KILL, sleep(2), setv("g", 1)])]),
        script("New", [([call("IsEqual", g("g"), 1)], [KILL, setv("seen", 1)])])],
        [run("Old", None), run("New", None)], 6, globals_=G("g", "seen"))
    add("cross_script_newer_body", [
        script("Watch", [([call("IsEqual", g("g"), 1)], [KILL, setv("seen", 1)])]),
        script("Late", [([], [KILL, sleep(2), setv("g", 1)])])],
        [run("Watch", None), run("Late", None)], 6, globals_=G("g", "seen"))
    # For( VSS#i#val, Heroes ) VCheck( VSS#i#val ): one copy per party unit.
    add("per_unit_copies", [script("VCheck#0#8", [([call("IsEqual", g("gate"), 1)], [KILL, inc("n")])])],
        [run("VCheck#0#8", None), run("VCheck#0#8", None), run("VCheck#0#8", None)], 5, {2: {"gate": 1}}, globals_=G("gate", "n"))
    add("per_unit_copies_world", [script("VCheck#0#8", [([call("IsEqual", g("gate"), 1)], [KILL, inc("n")])])],
        [run("VCheck#0#8", None), run("VCheck#0#8", None), run("VCheck#0#8", None)], 5, {2: {"gate": 1}}, globals_=G("gate", "n"), boot="world")
    add("declared_never_started", [script("Unused", [([], [KILL, setv("p", 1)])])], [], 3, globals_=G("p"))
    add("kill_after_assignments", [script("DaughterBrief", [([], [setv("p", 1), setv("q", 2), KILL])])],
        [], 4, globals_=G("p", "q"), boot="handler")
    # Float parameters bound at the call.
    param = script("Param", [([call("IsGreater", {"local": "n"}, g("gate"))], [KILL, setv("s", call("Add", call("Mul", g("s"), 10), {"local": "n"}))])],
                   params=[("n", "float")])
    add("float_parameters", [param], [run("Param", 1), run("Param", 5), run("Param", call("Add", g("gate"), 3))],
        6, {2: {"gate": 0.5}}, globals_=G("s", gate=2))
    # #OnBriefingComplete( nPlayer, szComplete ) as authored in bz10k.
    handler = script("#OnBriefingComplete", [
        ([call("IsEqualString", {"local": "szComplete"}, {"string": "b.YCF.Yc50"})], [KILL, setv("m", 1)]),
        ([call("IsEqualString", {"local": "szComplete"}, {"string": "b.YCF.Yc47_2"})], [KILL, setv("y", call("Add", {"local": "nPlayer"}, 1))]),
        ([], [KILL])], params=BRIEFING_PARAMS)

    def brief(key, player=0):
        return {"script": "#OnBriefingComplete", "args": [player, {"string": key}], "flag": "flag"}

    add("briefing_handler", [handler], [sleep(3), setv("w", 1)], 9,
        briefings={1: brief("b.YCF.Yc47_2", 2), 4: brief("b.Other"), 6: brief("b.YCF.Yc50")}, globals_=G("flag", "m", "y", "w"), boot="world")
    add("briefing_handler_sleeps", [script("#OnBriefingComplete", [([], [KILL, setv("a", 1), sleep(2), setv("a", 2)])],
                                           params=BRIEFING_PARAMS),
                                    script("Watch", [([call("IsEqual", g("a"), 1)], [KILL, setv("seen", 1)])])],
        [run("Watch", None)], 6, briefings={1: brief("b.x")}, globals_=G("flag", "a", "seen"), boot="world")
    # Shapes the original rejects: KillScript in a queued thread.
    add("kill_after_sleep", [script("Late", [([], [sleep(1), KILL, setv("p", 1)])])], [], 4, boot="handler", globals_=G("p"))
    add("world_kill", [], [setv("p", 1), KILL, setv("p", 2)], 3, globals_=G("p"), boot="world")

    rng = random.Random(seed ^ 0x4bf000)

    def fuzz_body(rng, k, kill, later):
        body = [KILL] if kill else []
        for _ in range(rng.randint(1, 3)):
            choice = rng.random()
            if choice < 0.35:
                body.append(sleep(rng.choice([0, 1, 2, 3])))
            elif choice < 0.45:
                body.append(call("SleepUntil", call("IsEqual", g(rng.choice("abc")), rng.choice([0, 1]))))
            elif choice < 0.6 and kill and later:
                body.append(run(rng.choice(later), None))
            else:
                body.append(setv(f"o{k}", call("Add", call("Mul", g(f"o{k}"), 2), rng.randint(1, 3))))
        return body

    def fuzz_conds(rng):
        return [call(rng.choice(["IsEqual", "IsGreater", "IsLess"]), g(rng.choice("abc")), rng.choice([0, 1, 2]))
                for _ in range(rng.randint(0, 2))]

    def fuzz_changes(rng):
        return {t: {rng.choice("abc"): rng.choice([0, 1, 2])} for t in range(1, 16) if rng.random() < 0.4}

    # One handler script: both sides poll it from the first step.
    for i in range(fuzz):
        blocks = [(fuzz_conds(rng), fuzz_body(rng, 0, rng.random() < 0.5, [])) for _ in range(rng.randint(1, 4))]
        add(f"fuzz_blocks_{i:03}", [script("Fuzz", blocks)], [], 16, fuzz_changes(rng),
            globals_=G("a", "b", "c", "o0"), boot="handler")
    # Several scripts started by WorldScript or by an event handler.
    for i in range(fuzz):
        names = [f"S{k}" for k in range(rng.randint(2, 4))]
        scripts = [script(name, [(fuzz_conds(rng), fuzz_body(rng, k, rng.random() < 0.7, names[k + 1:]))
                                 for _ in range(rng.randint(1, 3))]) for k, name in enumerate(names)]
        world, boot = [], "world" if i % 2 else "event"
        for name in names:
            if boot == "world" and rng.random() < 0.4:
                world.append(sleep(rng.choice([1, 2])))
            world.append(run(name, None))
        add(f"fuzz_scripts_{i:03}", scripts, world, 16, fuzz_changes(rng),
            globals_=G("a", "b", "c", *[f"o{k}" for k in range(len(names))]), boot=boot)
    return rows


def validate(case, steps, role):
    inputs = case["inputs"]
    names = {s["name"] for s in inputs["scripts"]}
    labels = {f"{s['name']}.{b}" for s in inputs["scripts"] for b in range(len(s["blocks"]))} | {"World"}
    for step in steps:
        state = step["state"]
        if (set(state) != {"trace", "globals", "scripts", "bodies", "fatal"} or type(state["fatal"]) is not str
                or not isinstance(state["trace"], list) or not all(type(e) is str for e in state["trace"])
                or not isinstance(state["globals"], dict) or set(state["globals"]) != set(inputs["globals"])
                or not all(type(v) is int and 0 <= v <= 0xffffffff for v in state["globals"].values())
                or not isinstance(state["scripts"], dict) or not set(state["scripts"]) <= names
                or not isinstance(state["bodies"], dict) or not set(state["bodies"]) <= labels
                or not all(type(v) is int and v > 0 for v in [*state["scripts"].values(), *state["bodies"].values()])):
            raise ValueError(f"{role} {case['id']} has an invalid quest_scheduler observation")
        for event in state["trace"]:
            kind, _, label = event.partition(":")
            block = label.rsplit(".", 1)[0] if kind == "c" else label
            if kind not in ("c", "fire", "run") or block not in labels:
                raise ValueError(f"{role} {case['id']} has an unknown scheduler event {event}")
