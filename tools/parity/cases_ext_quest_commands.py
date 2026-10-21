"""State-changing quest commands: inputs only, never expected values.

Each scenario is a persistent command body run tick by tick through the
original dispatcher (FUN_004b6760) and through ScriptVM._run. After every
tick both sides report player zero's GS hash table, quest-item bag, money,
lever states, group arrays, QStart/QFinish registrations, globals and a list
of observation expressions. Commands are prioritised by authored usage
(re/usage.txt): AddObject, GSSetVarMax, GSSetVar, EraseQuestItem, For,
SwitchLeverState, QStart/QObj*/QFinish, GiveQuestItem, GiveMoney, EnableLever,
GSDelVar, plus RemoveObject.
"""
import random

KINDS = ["quest_cmd_gsvar", "quest_cmd_items", "quest_cmd_groups", "quest_cmd_levers", "quest_cmd_journal"]
STEP_COUNTS = {kind: "ticks" for kind in KINDS}

# Quest-item names and script IDs from the original items.idb "quest items"
# section (scriptID column). The native item factory boundary resolves these
# names; the remake resolves the same names through its own database.
CATALOG = [["sackofgold", 17], ["dcbook", 16], ["palantir", 8], ["minekey00", 29],
           ["lizardclaw00", 25], ["cagekey00", 48], ["cavegear00", 52], ["minekey01", 30],
           ["ogrekey1", 61], ["goldnugget00", 28]]
# Three keys that share one bucket of the initial 193-bucket table.
COLLIDE = ["q.ak", "q.bf", "q.ca"]

STUBS = [
    "Win32 imports lstrlenA, InterlockedIncrement/Decrement, Enter/LeaveCriticalSection (stdcall stubs)",
    "operator new 0x70056f / delete 0x700598 and MFC CString size-class allocator 0x6e6bf1/0x6e6c80 (bump allocator, frees are no-ops)",
    "player lookup 0x594180: player zero only (single player); network check 0x57f440 returns single player",
    "item construction by name 0x6ac930: catalog name -> quest item record (type 0x3009, script id +0x4c); unknown names -> none",
    "player client notifications (vtable +0x44 items received, +0x4c item removed) and its network stream (+0x48 vtable +8)",
    "lever database lookup 0x464750: no record (native default switch time 10)",
    "world getter 0x455950: world whose vtable +0x68 reports no active map, so no figure/footprint/sound update",
    "script compiler 0x4d23a0: QFinish's generated text is recorded, not compiled or scheduled",
    "temporary command-value cleanup 0x4bec80 (none allocated by these bodies)",
    "unit/lever record accessors: type (+0x30), death (+0x44 on stats), release (+0x10) through a fixture vtable",
    "static initial state: empty quest-name CString, player bag block size 10, CRT float-format initializer 0x6e7294 executed",
]


def contracts(campaign):
    if campaign != "original":
        return {}
    common = {
        "entry": ["0x4b6760", "0x581790", "0x460bc0"],
        "stubs": STUBS,
        "tolerances": {},
    }
    return {
        "quest_cmd_gsvar": dict(common, scope=(
            "GSSetVar 0x7f (66edd0/460bc0), GSSetVarMax 0x98 (66ee40/460af0), GSDelVar 0x82 (66eef0/460db0) "
            "against the native player-zero GS hash: bucket chains, float32 bits, count, rehash at growth."),
            limits="Player zero only; no network replication of GS messages, no co-op per-player stores."),
        "quest_cmd_items": dict(common, scope=(
            "GiveQuestItem 0x92 (594ab0/665430), EraseQuestItem 0x93 (665740), GiveMoney 0xa7 and HaveItem 0x7c "
            "against the native player bag list order, duplicates and money."),
            limits="Quest items from the catalog only; no unit-carried items, pickup messages or LMP owners."),
        "quest_cmd_groups": dict(common, scope=(
            "AddObject 0x22 (4b2ef0), RemoveObject 0x23 (4b2da0/4c2200) and For 0x6b (recursive 4b6760) "
            "group arrays and per-iteration order through a global accumulator."),
            limits="Fixture records are allocated in ascending address order of their input index; the native "
                   "group order is pointer order. ForIf is not compared (no authored use, no remake parser form)."),
        "quest_cmd_levers": dict(common, scope=(
            "SwitchLeverState 0x91 / SwitchLeverStateEx 0x9e (52b7a0) and EnableLever 0xcc (52bad0) with "
            "GetLeverState 0x90: target state, cycling, clamping and use permission."),
            limits="State and permission only; no figure motion, footprint, timing or sound."),
        "quest_cmd_journal": dict(common, scope=(
            "QStart 0xd5 (4baa40), QObjArea..QObjGetItem 0xd7-0xdd (4bae10) and QFinish 0xd6 (4baab0): the quest "
            "being recorded and each registration (quest id and ordered objective records) handed to the compiler."),
            limits="The generated Su0..SuN scripts are not compiled or run; objective progress and QuestComplete "
                   "are outside this family."),
    }


def call(name, *args):
    return {"call": name, "args": list(args)}


def cmd(name, *args):
    return {"call": name, "args": list(args)}


def s(text):
    return {"string": text}


def u(index):
    return {"unit": index}


def it(name="i"):
    return {"iterator": name}


def g(name):
    return {"group": name}


def nan():
    return call("Div", 0, 0)


def ticks(n):
    return [{} for _ in range(n)]


def scenarios(seed=20261020, fuzz=12):
    rows = []

    def add(kind, name, body, n=1, **inputs):
        inputs = {"catalog": CATALOG, "units": [], "groups": [], "globals": {}, "variables": [],
                  "quest_items": [], "money": 0, "observe": [], **inputs, "body": body, "ticks": ticks(n)}
        rows.append({"id": f"{kind}/{name}", "kind": kind, "inputs": inputs})

    # ------------------------------------------------------------ GS variables
    K = "quest_cmd_gsvar"
    get = lambda key: call("GSGetVar", 0, s(key))
    add(K, "set_new_and_collisions", [cmd("GSSetVar", 0, s(k), i + 1) for i, k in enumerate(COLLIDE)]
        + [cmd("GSSetVar", 0, s("z.single"), 0.5)])
    add(K, "update_keeps_chain_order", [cmd("GSSetVar", 0, s(COLLIDE[0]), 7), cmd("GSSetVar", 0, s(COLLIDE[2]), -3.25)],
        variables=[[k, i + 1] for i, k in enumerate(COLLIDE)])
    add(K, "set_zero_and_negative_zero_delete", [cmd("GSSetVar", 0, s(COLLIDE[1]), 0), cmd("GSSetVar", 0, s(COLLIDE[0]), -0.0),
                                                 cmd("GSSetVar", 0, s("missing"), 0)],
        variables=[[k, i + 1] for i, k in enumerate(COLLIDE)])
    for position, key in enumerate(COLLIDE):
        add(K, f"delvar_chain_{position}", [cmd("GSDelVar", 0, s(key)), cmd("GSDelVar", 0, s(key))],
            variables=[[k, i + 1] for i, k in enumerate(COLLIDE)], observe=[get(key)])
    add(K, "delvar_missing", [cmd("GSDelVar", 0, s("nothing"))], variables=[["a", 1]])
    for label, value in [("new_positive", 2), ("new_negative", -2), ("new_zero", 0), ("new_fraction", 0.1)]:
        add(K, "max_" + label, [cmd("GSSetVarMax", 0, s("m"), value)], observe=[get("m")])
    for label, old, value in [("lower", 3, 2), ("equal", 3, 3), ("higher", 3, 4), ("fraction_up", 1, 1.0000001),
                              ("negative_to_zero", -3, 0), ("negative_up", -3, -1), ("tiny_above_zero", 0.5, 1e-30)]:
        add(K, "max_existing_" + label, [cmd("GSSetVarMax", 0, s("m"), value)], variables=[["m", old], ["other", 9]],
            observe=[get("m")])
    add(K, "max_nan_then_number", [cmd("GSSetVarMax", 0, s("m"), nan()), cmd("Sleep", 1), cmd("GSSetVarMax", 0, s("m"), 5)],
        n=3, variables=[["m", 1]], observe=[get("m")])
    add(K, "set_nan_then_max", [cmd("GSSetVar", 0, s("m"), nan()), cmd("Sleep", 1), cmd("GSSetVarMax", 0, s("m"), 5)],
        n=3, observe=[get("m")])
    add(K, "max_counter_increment", [cmd("GSSetVarMax", 0, s("count"), call("Add", get("count"), 1)) for _ in range(4)],
        observe=[get("count")])
    add(K, "absent_player_one", [cmd("GSSetVar", 1, s("p"), 4), cmd("GSSetVarMax", 1, s("q"), 5), cmd("GSDelVar", 1, s("a"))],
        variables=[["a", 1]])
    add(K, "empty_key", [cmd("GSSetVar", 0, s(""), 5), cmd("GSSetVarMax", 0, s(""), 6), cmd("GSDelVar", 0, s(""))])
    add(K, "case_sensitive_keys", [cmd("GSSetVar", 0, s("Key"), 1), cmd("GSSetVar", 0, s("key"), 2), cmd("GSDelVar", 0, s("KEY"))])
    add(K, "latin1_key", [cmd("GSSetVar", 0, s("q.äß"), 3), cmd("GSSetVarMax", 0, s("q.äß"), 4)],
        observe=[get("q.äß")])
    add(K, "gtime_key", [cmd("GSSetVar", 0, s("gtime"), 30.5), cmd("Sleep", 1), cmd("GSSetVar", 0, s("gtime"), 0)], n=3)
    add(K, "quest_journal_keys", [cmd("GSSetVar", 0, s("q.z1.z1"), 1), cmd("GSSetVarMax", 0, s("q.z1.z1.1"), 2),
                                  cmd("GSSetVarMax", 0, s("q.z1.z1"), 2)])
    add(K, "per_tick_sleeps", [cmd("GSSetVar", 0, s("a"), 1), cmd("Sleep", 2), cmd("GSSetVarMax", 0, s("a"), 3),
                               cmd("Sleep", 1), cmd("GSDelVar", 0, s("a"))], n=5)
    growth = [cmd("GSSetVar", 0, s(f"k{i:03d}"), i + 1) for i in range(200)]
    add(K, "growth_rehash_193_to_389", growth + [cmd("Sleep", 1), cmd("GSDelVar", 0, s("k007")), cmd("GSSetVar", 0, s("k500"), 1)], n=2)
    add(K, "growth_existing_update_at_capacity", [cmd("GSSetVar", 0, s(f"k{i:03d}"), 1) for i in range(193)]
        + [cmd("Sleep", 1), cmd("GSSetVar", 0, s("k000"), 2)], n=2)

    # ------------------------------------------------------------ items/money
    K = "quest_cmd_items"
    have = lambda ident: call("HaveItem", 0, ident)
    add(K, "give_one", [cmd("GiveQuestItem", 0, s("SackofGold"))], observe=[have(17)])
    add(K, "give_duplicate_then_erase_once", [cmd("GiveQuestItem", 0, s("sackofgold")), cmd("GiveQuestItem", 0, s("sackofgold")),
                                               cmd("Sleep", 1), cmd("EraseQuestItem", 0, 17)], n=3, observe=[have(17)])
    add(K, "initial_order_then_appends", [cmd("GiveQuestItem", 0, s("palantir")), cmd("GiveQuestItem", 0, s("MineKey00"))],
        quest_items=["dcbook", "lizardclaw00"])
    for label, ident in [("head", 25), ("middle", 48), ("tail", 52)]:
        add(K, f"erase_{label}", [cmd("EraseQuestItem", 0, ident), cmd("GiveQuestItem", 0, s("cagekey00"))],
            quest_items=["lizardclaw00", "cagekey00", "cavegear00"], observe=[have(ident)])
    add(K, "erase_missing", [cmd("EraseQuestItem", 0, 30)], quest_items=["minekey00"], observe=[have(30), have(29)])
    add(K, "erase_all_then_give", [cmd("EraseQuestItem", 0, 29), cmd("EraseQuestItem", 0, 61), cmd("GiveQuestItem", 0, s("ogrekey1"))],
        quest_items=["minekey00", "ogrekey1"], observe=[have(61)])
    add(K, "erase_fractional_id", [cmd("EraseQuestItem", 0, 29.9)], quest_items=["minekey00"], observe=[have(29)])
    add(K, "absent_player_one", [cmd("GiveQuestItem", 1, s("palantir")), cmd("EraseQuestItem", 1, 29), cmd("GiveMoney", 1, 50)],
        quest_items=["minekey00"], money=10)
    for label, value in [("positive", 120), ("negative", -40), ("fraction_up", 7.9), ("fraction_down", -7.9),
                         ("zero", 0), ("large", 1e6)]:
        add(K, "money_" + label, [cmd("GiveMoney", 0, value)], money=100, observe=[call("GetMoney", 0)])
    add(K, "money_repeated_sleeps", [cmd("GiveMoney", 0, 10), cmd("Sleep", 1), cmd("GiveMoney", 0, -25)], n=3, money=5,
        observe=[call("GetMoney", 0)])

    # ------------------------------------------------------------ groups/For
    K = "quest_cmd_groups"
    people = [{"uid": 3}, {"uid": 1}, {"uid": 2}, {"uid": 4, "dead": True}]
    order = lambda iterator="i": {"set": "order", "value": call("Add", call("Mul", {"global": "order"}, 10),
                                                                 call("GetObjectID", it(iterator)))}
    adds = lambda *indices: [cmd("AddObject", g("G"), u(i)) for i in indices]
    add(K, "add_order", adds(2, 0, 1), units=people, groups=["G"])
    add(K, "add_duplicate_and_missing", adds(1, 1) + [cmd("AddObject", g("G"), u(-1))], units=people, groups=["G"])
    add(K, "for_order", adds(2, 0, 1) + [{"call": "For", "args": [it(), g("G")], "body": [order()]}],
        units=people, groups=["G"], globals={"order": 0})
    add(K, "for_dead_member", adds(3, 1) + [{"call": "For", "args": [it(), g("G")], "body": [order()]}],
        units=people, groups=["G"], globals={"order": 0})
    add(K, "for_empty_group", [{"call": "For", "args": [it(), g("G")], "body": [order()]}],
        units=people, groups=["G"], globals={"order": 0})
    add(K, "for_nested", adds(0, 1) + [cmd("AddObject", g("H"), u(2)), cmd("AddObject", g("H"), u(0)),
        {"call": "For", "args": [it("a"), g("G")], "body": [
            {"call": "For", "args": [it("b"), g("H")], "body": [order("a"), order("b")]}]}],
        units=people, groups=["G", "H"], globals={"order": 0})
    add(K, "remove_existing_and_missing", adds(0, 1, 2) + [cmd("RemoveObject", g("G"), u(1)), cmd("RemoveObject", g("G"), u(3))],
        units=people, groups=["G"])
    add(K, "remove_then_for", adds(0, 1, 2) + [cmd("RemoveObject", g("G"), u(0)),
                                               {"call": "For", "args": [it(), g("G")], "body": [order()]}],
        units=people, groups=["G"], globals={"order": 0})
    add(K, "for_body_removes_current", adds(0, 1, 2) + [{"call": "For", "args": [it(), g("G")], "body": [
        order(), cmd("RemoveObject", g("G"), it())]}], units=people, groups=["G"], globals={"order": 0})
    add(K, "for_body_adds_member", adds(1, 2) + [{"call": "For", "args": [it(), g("G")], "body": [
        order(), cmd("AddObject", g("G"), u(0))]}], units=people, groups=["G"], globals={"order": 0})
    add(K, "for_copy_into_second_group", adds(2, 0) + [{"call": "For", "args": [it(), g("G")], "body": [
        cmd("AddObject", g("H"), it())]}], units=people, groups=["G", "H"])
    add(K, "for_body_sleep_unauthored", adds(0, 1) + [{"call": "For", "args": [it(), g("G")], "body": [
        cmd("Sleep", 2), order()]}, {"set": "after", "value": 1}], n=4, units=people, groups=["G"],
        globals={"order": 0, "after": 0})
    add(K, "group_queries_after_changes", adds(0, 1, 2) + [cmd("RemoveObject", g("G"), u(2))], units=people, groups=["G"],
        observe=[call("GroupSize", g("G")), call("GroupHas", g("G"), u(2)), call("GroupHas", g("G"), u(0))])

    # ------------------------------------------------------------ levers
    K = "quest_cmd_levers"

    def lever(state=0, states=3, cycled=False, enabled=True):
        return {"uid": 7, "lever": {"state": state, "states": states, "cycled": cycled, "enabled": enabled}}

    state_of = call("GetLeverState", u(0))
    for label, value in [("in_range", 1), ("last", 2), ("above", 7), ("fraction", 1.7), ("negative_fraction", -0.5),
                         ("next", -1), ("very_negative", -5), ("huge_unauthored", 3e9)]:
        add(K, "switch_" + label, [cmd("SwitchLeverState", u(0), value)], units=[lever(state=1)], observe=[state_of])
    add(K, "next_stops_at_last", [cmd("SwitchLeverState", u(0), -1)] * 3, units=[lever()], observe=[state_of])
    add(K, "next_wraps_cycled", [cmd("SwitchLeverState", u(0), -1)] * 3, units=[lever(cycled=True)], observe=[state_of])
    add(K, "single_state", [cmd("SwitchLeverState", u(0), -1), cmd("SwitchLeverState", u(0), 3)],
        units=[lever(states=1)], observe=[state_of])
    add(K, "single_state_cycled", [cmd("SwitchLeverState", u(0), -1)], units=[lever(states=1, cycled=True)], observe=[state_of])
    for label, time in [("zero", 0), ("five", 5), ("negative", -1)]:
        add(K, "ex_time_" + label, [cmd("SwitchLeverStateEx", u(0), 2, time)], units=[lever()], observe=[state_of])
    add(K, "enable_values", [cmd("EnableLever", u(0), 0), cmd("Sleep", 1), cmd("EnableLever", u(0), 2.5),
                             cmd("Sleep", 1), cmd("EnableLever", u(0), -0.0)], n=3, units=[lever()])
    add(K, "enable_disabled", [cmd("EnableLever", u(0), 1)], units=[lever(enabled=False)])
    add(K, "switch_keeps_permission", [cmd("SwitchLeverState", u(0), 1)], units=[lever(enabled=False)])
    add(K, "non_lever_target", [cmd("SwitchLeverState", u(0), 1), cmd("EnableLever", u(0), 0), cmd("SwitchLeverState", u(1), 1)],
        units=[{"uid": 5}, lever()], observe=[call("GetLeverState", u(1))])
    add(K, "missing_target", [cmd("SwitchLeverState", u(-1), 1), cmd("EnableLever", u(-1), 0)], units=[lever()])

    # ------------------------------------------------------------ journal
    K = "quest_cmd_journal"
    authored = [cmd("QStart", s("z17q1")), cmd("QObjSeeUnit", s("GetObject(1000061)")), cmd("QObjGetItem", 82)]
    add(K, "authored_z17q1", authored + [cmd("QFinish")])
    add(K, "all_objective_kinds", [cmd("QStart", s("z18q9")), cmd("QObjArea", 1), cmd("QObjSeeObject", s("GetObject(46470)")),
                                   cmd("QObjSeeUnit", s("GetObject(1000284)")), cmd("QObjKillUnit", s("GetObject(1000181)")),
                                   cmd("QObjKillGroup", s("OhranaJunHouse")), cmd("QObjUse", s("GetObject(5)"), 2),
                                   cmd("QObjGetItem", 82), cmd("QFinish")])
    add(K, "recording_across_ticks", [cmd("QStart", s("z18q1")), cmd("QObjArea", 1), cmd("Sleep", 1),
                                      cmd("QObjKillGroup", s("OhranaJunHouse")), cmd("Sleep", 1), cmd("QFinish")], n=4)
    add(K, "objective_without_qstart", [cmd("QObjArea", 3), cmd("QFinish")])
    add(K, "qfinish_without_objectives", [cmd("QStart", s("z7q3")), cmd("QFinish")])
    add(K, "restart_same_quest", [cmd("QStart", s("z17q2")), cmd("QObjArea", 1), cmd("QStart", s("z17q2")),
                                  cmd("QObjKillUnit", s("GetObject(1000181)")), cmd("QFinish")])
    add(K, "second_registration_same_quest", authored + [cmd("QFinish"), cmd("Sleep", 1)] + authored + [cmd("QFinish")], n=2)
    add(K, "switch_quest_before_finish", [cmd("QStart", s("a1")), cmd("QObjArea", 1), cmd("QStart", s("b2")), cmd("QObjArea", 2),
                                          cmd("QFinish")])
    add(K, "mixed_case_quest_id", [cmd("QStart", s("Z17Q1")), cmd("QObjArea", 1), cmd("QFinish")])
    add(K, "objectives_after_finish", authored + [cmd("QFinish"), cmd("QObjArea", 4), cmd("QFinish")])
    add(K, "seventeen_objectives", [cmd("QStart", s("big"))] + [cmd("QObjArea", i) for i in range(17)] + [cmd("QFinish")])
    for label, value in [("fraction", 2.5), ("tenth", 0.1), ("negative", -1), ("large", 123456789)]:
        add(K, "area_value_" + label, [cmd("QStart", s("v")), cmd("QObjArea", value), cmd("QObjUse", s("GetObject(5)"), value),
                                       cmd("QObjGetItem", value), cmd("QFinish")])

    _fuzz(rows, random.Random(seed), fuzz, add)
    return rows


def _fuzz(rows, rng, fuzz, add):
    keys = ["f.a", "f.b", "f.c"] + COLLIDE
    values = [0, -0.0, 1, 2, -1, 0.5, 3.25, 1e-3, 100]
    for n in range(max(0, fuzz)):
        body = []
        for _ in range(rng.randint(3, 10)):
            op = rng.choice(["GSSetVar", "GSSetVarMax", "GSSetVarMax", "GSDelVar", "Sleep"])
            if op == "Sleep":
                body.append(cmd("Sleep", rng.randint(0, 2)))
            elif op == "GSDelVar":
                body.append(cmd(op, 0, s(rng.choice(keys))))
            else:
                body.append(cmd(op, 0, s(rng.choice(keys)), rng.choice(values)))
        initial = [[k, rng.choice(values[2:])] for k in rng.sample(keys, rng.randint(0, 4))]
        add("quest_cmd_gsvar", f"fuzz_{n}", body, n=6, variables=initial,
            observe=[call("GSGetVar", 0, s(k)) for k in keys[:3]])
    for n in range(max(0, fuzz)):
        names = [c[0] for c in CATALOG[:5]]
        body = []
        for _ in range(rng.randint(3, 8)):
            op = rng.choice(["GiveQuestItem", "EraseQuestItem", "GiveMoney", "Sleep"])
            if op == "GiveQuestItem":
                body.append(cmd(op, 0, s(rng.choice(names))))
            elif op == "EraseQuestItem":
                body.append(cmd(op, 0, rng.choice(CATALOG[:5])[1]))
            elif op == "GiveMoney":
                body.append(cmd(op, 0, rng.choice([-30, -2.5, 1, 15.75, 200])))
            else:
                body.append(cmd("Sleep", 1))
        add("quest_cmd_items", f"fuzz_{n}", body, n=5, money=rng.randint(0, 100),
            quest_items=rng.sample(names, rng.randint(0, 3)),
            observe=[call("HaveItem", 0, c[1]) for c in CATALOG[:5]])
    for n in range(max(0, fuzz)):
        count = rng.randint(2, 6)
        units = [{"uid": rng.randint(1, 9)} for _ in range(count)]
        body = []
        for _ in range(rng.randint(3, 9)):
            op = rng.choice(["AddObject", "AddObject", "RemoveObject", "For"])
            if op == "For":
                body.append({"call": "For", "args": [it(), g("G")], "body": [
                    {"set": "order", "value": call("Add", call("Mul", {"global": "order"}, 10), call("GetObjectID", it()))}]})
            else:
                body.append(cmd(op, g("G"), u(rng.randrange(count))))
        add("quest_cmd_groups", f"fuzz_{n}", body, units=units, groups=["G"], globals={"order": 0})
    for n in range(max(0, fuzz)):
        states = rng.randint(1, 4)
        body = []
        for _ in range(rng.randint(2, 6)):
            op = rng.choice(["SwitchLeverState", "SwitchLeverStateEx", "EnableLever", "Sleep"])
            if op == "SwitchLeverState":
                body.append(cmd(op, u(0), rng.choice([-1, -1, 0, 1, 2, 3, 5])))
            elif op == "SwitchLeverStateEx":
                body.append(cmd(op, u(0), rng.choice([-1, 0, 1, 2]), rng.choice([0, 3, 10])))
            elif op == "EnableLever":
                body.append(cmd(op, u(0), rng.choice([0, 1])))
            else:
                body.append(cmd("Sleep", 1))
        lever = {"uid": 7, "lever": {"state": rng.randrange(states), "states": states,
                                     "cycled": rng.random() < 0.5, "enabled": rng.random() < 0.7}}
        add("quest_cmd_levers", f"fuzz_{n}", body, n=4, units=[lever], observe=[call("GetLeverState", u(0))])


def validate(case, steps, role):
    def bits(value):
        return type(value) is int and 0 <= value <= 0xffffffff

    inputs = case["inputs"]
    for step in steps:
        state = step["state"]
        ok = set(state) == {"gs", "bag", "money", "levers", "groups", "journal", "globals", "observed_bits", "finished", "killed"}
        if ok:
            gs = state["gs"]
            ok = (isinstance(gs, dict) and set(gs) == {"capacity", "count", "chains"}
                  and type(gs["capacity"]) is int and gs["capacity"] > 0 and type(gs["count"]) is int
                  and isinstance(gs["chains"], list)
                  and all(isinstance(c, list) and len(c) == 2 and type(c[0]) is int and 0 <= c[0] < gs["capacity"]
                          and isinstance(c[1], list) and c[1]
                          and all(isinstance(e, list) and len(e) == 2 and isinstance(e[0], str) and bits(e[1]) for e in c[1])
                          for c in gs["chains"])
                  and [c[0] for c in gs["chains"]] == sorted({c[0] for c in gs["chains"]}))
        ok = ok and isinstance(state["bag"], list) and all(type(i) is int for i in state["bag"])
        ok = ok and type(state["money"]) is int
        ok = ok and isinstance(state["levers"], list) and len(state["levers"]) == sum(1 for r in inputs["units"] if r.get("lever")) \
            and all(isinstance(l, dict) and set(l) == {"state", "enabled"} and type(l["state"]) is int
                    and type(l["enabled"]) is bool for l in state["levers"])
        ok = ok and isinstance(state["groups"], dict) and set(state["groups"]) == set(inputs["groups"]) \
            and all(isinstance(m, list) and all(type(i) is int for i in m) for m in state["groups"].values())
        journal = state["journal"]
        ok = ok and isinstance(journal, dict) and set(journal) == {"recording", "compiled"} \
            and isinstance(journal["recording"], str) and isinstance(journal["compiled"], list) \
            and all(isinstance(r, dict) and set(r) == {"quest", "objectives"} and isinstance(r["quest"], str)
                    and all(isinstance(o, list) and len(o) == 3 and isinstance(o[0], str) and isinstance(o[1], str)
                            and bits(o[2]) for o in r["objectives"]) for r in journal["compiled"])
        ok = ok and isinstance(state["globals"], dict) and set(state["globals"]) == set(inputs["globals"]) \
            and all(bits(v) for v in state["globals"].values())
        ok = ok and isinstance(state["observed_bits"], list) and len(state["observed_bits"]) == len(inputs["observe"]) \
            and all(bits(v) for v in state["observed_bits"])
        ok = ok and type(state["finished"]) is bool and type(state["killed"]) is bool
        if not ok:
            raise ValueError(f"{role} {case['id']} has an invalid quest command observation")
