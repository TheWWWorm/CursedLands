"""Dialogue triggers driven by campaign (GS) variables.

Inputs only: ordered GSSetVar operations, the clicked unit, the zone, the
party and supplied briefing texts. No expected topic lists or variable values
are written here; each side derives them with its own production code.
"""
import random

ENTRY_STUBS = [
    "fixture heap for operator new/delete, malloc/free and MFC CFixedAlloc CString pools",
    "KERNEL32 lstrlenA and Interlocked{Increment,Decrement}; critical sections are single-threaded no-ops",
    "player-zero lookup (594180) and current-player object (5699f0)",
    "CRT _mbctype/_mbcasemap for ASCII letters (normally filled by _setmbcp at start-up)",
]


def contracts(campaign):
    if campaign != "original":
        return {}
    return {
        "dialogue_topics": {
            "entry": ["0x608b20", "0x607320", "0x607880", "0x581790", "0x460bc0", "0x460ee0", "0x461360", "0x4dbe40"],
            "scope": "NPC click topic list: GS store built by native GSSetVar, then 608b20/607320 build the ordered "
                     "b.<owner>.<id> == 1 rows, the last constr* row and goodbye, or leave the dialog closed; "
                     "607880 derives each row title. Versus Briefings.interact (topics event).",
            "stubs": ENTRY_STUBS + [
                "single-player/multiplayer flag (57f440)",
                "texts.res supplied as one archive member table (exact lowercase key match); native line reader runs",
                "topic-list widget redraw, scroll bar and row drawing (5ff830, 5fc9e0, 65afa0, vtable +0x64, 6071a0)",
            ],
            "limits": "Player zero only; ASCII keys; no village command gate (see village_gate), Astral paid offers, "
                      "smith assortments, mercenary ownership overlays or topic selection/playback. The native "
                      "goodbye row is verified and removed; the remake's dialog panel appends its own.",
            "tolerances": {},
        },
        "dialogue_zone": {
            "entry": ["0x602c90", "0x578c40", "0x460ee0", "0x581790", "0x460bc0", "0x45e850", "0x4dbe40"],
            "scope": "Automatic zone briefing selection: which pending b.<zone>.<id> == 1 the party leader's "
                     "check starts (native 602c90 up to 6064a0) versus Briefings.tick (play_named).",
            "stubs": ENTRY_STUBS + [
                "zone registry with one record named as the input zone (79bef0)",
                "one-member party whose leader is checked",
                "camera focus/selection (566030, 40d3b0), unit lookup (55fb00) and conversation staging 6064a0 recorded as the start event",
            ],
            "limits": "One poll with the leader; no movie deferral, 0.5 s poll cadence, side-quest rewards or "
                      "conversation playback. Zone names are lowercase like remake zone ids.",
            "tolerances": {},
        },
        "dialogue_merc": {
            "entry": ["0x591800", "0x66edd0", "0x460af0", "0x460bc0", "0x461360"],
            "scope": "RecalcMercBriefings: b.merc<i>.n<k>_<i> and amerc_<i> variables after the native "
                     "recalculation (591800) versus ScriptVM.recalc_merc_briefings.",
            "stubs": ENTRY_STUBS + [
                "world player list with player zero, its network peer and replicated-write stream",
                "party vector, unit lookup (55fb00) and unit dead getter (vtable +0xdc)",
                "remake: a hired mercenary is st.mercs[i] in the current party, a dead one also has adeadn<i> = 1 "
                "as GameWorld records a mercenary death",
            ],
            "limits": "Single player; home zones from the executable's own table; no hiring/dismissal side effects "
                      "(591de0), unit spawning or co-op ownership layers.",
            "tolerances": {},
        },
        "dialogue_complete": {
            "entry": ["0x592090", "0x591de0", "0x591800", "0x66ee40", "0x66edd0", "0x4dbe40", "0x6fdf1f"],
            "scope": "Briefing completion: native 592090 (mercenary topic handling 591de0/591800, money, "
                     "GSSetVarMax(.,1)/GSSetVar(.,2) reward lists and the WorldScript GSSetVar(..,2) + "
                     "#OnBriefingComplete it emits) versus Briefings.complete.",
            "stubs": ENTRY_STUBS + [
                "world player list, party vector, unit lookup and dead getter as in dialogue_merc",
                "briefings database row (map 7c87c4 lookup 4297a0): experience +0xc, money +0x10 and the four "
                "variable lists +0x2c/+0x38/+0x44/+0x50 mapped to give_quests/give_quests2/open_zones/unknown2; "
                "no item lists",
                "experience distribution (5911c0) recorded, hire/remove party changes (662890/6620b0/5935c0) "
                "recorded and not performed; remake give_experience/merc_changed recorded the same way",
                "the emitted WorldScript text (4d23a0) is recorded and its GSSetVar/#OnBriefingComplete "
                "arguments are read from that fixed format; the script is not executed",
            ],
            "limits": "Single player, player 0; no items, smile faces, side-quest (sq.) or multiplayer-quest "
                      "paths, conversation actor return walks or script handler bodies.",
            "tolerances": {},
        },
    }


def scenarios(seed=20261020, fuzz=12):
    rows = []

    def topics(name, variables, npc="Smith", **extra):
        rows.append({"id": "dialogue_topics/" + name, "kind": "dialogue_topics",
                     "inputs": {"npc": {"name": npc} if isinstance(npc, str) else npc,
                                "variables": [list(v) for v in variables], **extra}})

    topics("empty_table", [])
    topics("unrelated_only", [("q.gz1g.q1", 1), ("z.gz1g", 1)])
    for value in [1, 2, 3, 0.5, -1, 1.0000001, 0.99999994]:
        topics(f"single_value_{value}", [("b.smith.t1", value)])
    topics("set_then_cleared", [("b.smith.t1", 1), ("b.smith.t1", 0)])
    topics("cleared_then_reset", [("b.smith.t1", 1), ("b.smith.t2", 1), ("b.smith.t1", 0), ("b.smith.t1", 1)])
    topics("completed_and_pending", [("b.smith.t1", 2), ("b.smith.t2", 1), ("b.smith.t3", 2), ("b.smith.t4", 1)])
    many = [(f"b.smith.{i}", 1) for i in ["hello", "work", "quest", "rumours", "s1", "s2", "s10", "z9", "a0"]]
    topics("many_topics", many)
    topics("many_topics_reversed", list(reversed(many)))
    topics("many_topics_multiplayer", many, multiplayer=True)
    topics("many_topics_reversed_multiplayer", list(reversed(many)), multiplayer=True)
    topics("multiplayer_case_order", [("b.smith.Beta", 1), ("b.smith.alpha", 1), ("b.smith.ALPHA2", 1),
                                      ("b.smith._x", 1), ("b.smith.n10", 1), ("b.smith.n2", 1)], multiplayer=True)
    topics("owner_case", [("b.Smith.t1", 1), ("b.SMITH.t2", 1), ("b.smith.t3", 1), ("b.sMiTh.t4", 1)])
    topics("owner_case_npc_upper", [("b.smith.t1", 1), ("b.Smith.t2", 1)], npc="SMITH")
    topics("prefix_case", [("B.smith.t1", 1), ("b.smith.t2", 1)])
    topics("prefix_collisions", [("b.smith2.t1", 1), ("b.smit.t2", 1), ("b.smithy.t3", 1), ("b.smith.t4", 1)])
    topics("other_npcs_only", [("b.elder.t1", 1), ("b.smith2.t2", 1)])
    topics("part_counts", [("b.smith", 1), ("b.smith.t1.extra", 1), ("b.smith.", 1), ("b.smith.t2", 1),
                           ("b..smith", 1)])
    topics("empty_owner", [("b..t1", 1)], npc={"name": "Nobody", "id_name": ""})
    topics("spaces_in_key", [("b. smith.t1", 1), ("b.smith .t2", 1), ("b.smith. t3", 1), ("b.smith.t4", 1)])
    topics("name_differs_from_id", [("b.orcc.t1", 1), ("b.shaivar.t2", 1), ("b.Shaivar.t3", 1)],
           npc={"name": "Shaivar", "id_name": "OrcC"})
    topics("constr_only", [("b.smith.constr3", 1)])
    topics("constr_last_found", [("b.smith.constr1", 1), ("b.smith.constr2", 1), ("b.smith.constr7", 1),
                                 ("b.smith.t1", 1)])
    topics("constr_completed", [("b.smith.constr1", 2), ("b.smith.t1", 1)])
    topics("constr_spellings", [("b.smith.Constr4", 1), ("b.smith.constr", 1), ("b.smith.CONSTRx", 1),
                                ("b.smith.cons", 1), ("b.smith.xconstr", 1)])
    topics("constr_multiplayer", [("b.smith.constr2", 1), ("b.smith.b", 1), ("b.smith.a", 1)], multiplayer=True)
    text = {"briefing t1": "Ask about work\r\n#phrase hero 1\r\nHello",
            "briefing t2": "  Padded title  \r\n#phrase hero 1\r\nx",
            "briefing t3": "\r\nsecond line only",
            "briefing constr": "Trade\r\n",
            "briefing upper": "Upper id\r\n"}
    topics("titles", [("b.smith.t1", 1), ("b.smith.t2", 1), ("b.smith.t3", 1), ("b.smith.missing", 1),
                      ("b.smith.Upper", 1), ("b.smith.constr5", 1)], texts=text)
    topics("titles_missing_constr_text", [("b.smith.constr5", 1)], texts={"briefing t1": "x\r\n"})
    # Enough unrelated variables to force native table growth (193 -> 389)
    # between topic insertions.
    fill = [(f"q.fill.v{i}", 1) for i in range(220)]
    topics("growth_rehash", many[:4] + fill + many[4:])
    topics("growth_with_deletes", many + fill + [(k, 0) for k, _ in fill[::2]] + [("b.smith.late", 1)])

    rng = random.Random(seed ^ 0x607320)
    owners = ["smith", "Smith", "SMITH", "smith2", "elder", "smit"]
    ids = ["t1", "t2", "s10", "s2", "Hello", "constr1", "constr2", "Constr9", "quest", "z", "a", "n11_1"]
    for i in range(fuzz * 2):
        variables = []
        for _ in range(rng.randint(1, 30)):
            key = f"b.{rng.choice(owners)}.{rng.choice(ids)}"
            variables.append((key, rng.choice([0, 1, 1, 1, 2, 3])))
        for _ in range(rng.choice([0, 0, 5, 200])):
            variables.append((f"q.r{rng.randint(0, 999)}", 1))
        topics(f"seeded_{i:03}", variables, multiplayer=rng.random() < 0.3)

    def zone(name, variables, zone_id="zone1"):
        rows.append({"id": "dialogue_zone/" + name, "kind": "dialogue_zone",
                     "inputs": {"zone": zone_id, "variables": [list(v) for v in variables]}})

    zone("none", [])
    zone("single", [("b.zone1.intro", 1)])
    for value in [2, 0.5, 3, -1]:
        zone(f"value_{value}", [("b.zone1.intro", value)])
    zone("other_zone", [("b.zone2.intro", 1)])
    zone("prefix_collision", [("b.zone10.far", 1)])
    zone("prefix_collision_both", [("b.zone10.far", 1), ("b.zone1.near", 1)])
    zone("several_pending", [(f"b.zone1.{i}", 1) for i in ["a", "b", "c", "intro", "s10", "s2", "zz"]])
    zone("several_pending_reversed", [(f"b.zone1.{i}", 1) for i in reversed(["a", "b", "c", "intro", "s10", "s2", "zz"])])
    zone("four_parts", [("b.zone1.a.b", 1)])
    zone("four_parts_and_valid", [("b.zone1.a.b", 1), ("b.zone1.c", 1)])
    zone("empty_id", [("b.zone1.", 1)])
    zone("zone_case_in_key", [("b.Zone1.x", 1), ("b.ZONE1.y", 1)])
    zone("spaces_in_key", [("b.zone1. x", 1)])
    zone("mixed_with_topics", [("b.smith.t1", 1), ("b.zone1.t2", 2), ("b.zone1.t3", 1), ("b.elder.t4", 1)])
    briefs = [(f"b.npc{i}.t{i}", 2) for i in range(200)]
    zone("many_b_keys", briefs[:100] + [("b.zone1.first", 1)] + briefs[100:] + [("b.zone1.second", 1)])
    zone("many_b_keys_alt", [("b.zone1.alpha", 1)] + briefs + [("b.zone1.omega", 1), ("b.zone1.mid", 1)])
    zone("real_zone_id", [("b.bz1g.intro", 1), ("b.bz1g.other", 2)], zone_id="bz1g")
    rng = random.Random(seed ^ 0x602c90)
    for i in range(fuzz):
        variables = []
        for _ in range(rng.randint(1, 12)):
            variables.append((f"b.{rng.choice(['zone1', 'zone10', 'zone2', 'zone1'])}.{rng.choice(ids)}",
                              rng.choice([0, 1, 1, 2])))
        for _ in range(rng.choice([0, 10, 250])):
            variables.append((f"b.n{rng.randint(0, 999)}.x", 2))
        zone(f"seeded_{i:03}", variables)

    def merc(name, variables, party, zone_id="bz2g"):
        rows.append({"id": "dialogue_merc/" + name, "kind": "dialogue_merc",
                     "inputs": {"zone": zone_id, "party": party, "variables": [list(v) for v in variables]}})

    hero = {"name": "Hero"}
    merc("nothing_set", [], [hero])
    merc("available_first", [("amerc_3", 1)], [hero])
    merc("available_again", [("amerc_3", 2)], [hero])
    merc("not_yet", [("amerc_3", 1), ("b.merc3.n8_3", 1)], [hero])
    merc("not_yet_unavailable", [("b.merc3.n8_3", 1)], [hero])
    merc("farewell_unhired", [("amerc_3", 1), ("b.merc3.n10_3", 1), ("b.merc3.n1_3", 1)], [hero])
    for zone_id in ["bz2g", "bz1g", "BZ2G"]:
        merc(f"hired_in_{zone_id}", [("amerc_3", 2), ("b.merc3.n1_3", 1)], [hero, {"name": "merc3"}], zone_id)
    merc("hired_farewell", [("amerc_3", 2), ("b.merc3.n10_3", 1), ("b.merc3.n2_3", 1)], [hero, {"name": "merc3"}])
    merc("hired_dead", [("amerc_3", 2), ("adeadn3", 1)], [hero, {"name": "merc3", "dead": True}])
    two = [hero, {"name": "merc1"}, {"name": "merc4"}]
    merc("party_full", [("amerc_1", 2), ("amerc_4", 2), ("amerc_5", 1), ("amerc_6", 2)], two)
    merc("party_one_dead", [("amerc_1", 2), ("amerc_4", 2), ("adeadn4", 1), ("amerc_5", 1)],
         [hero, {"name": "merc1"}, {"name": "merc4", "dead": True}])
    merc("guest_member", [("amerc_5", 1)], [hero, {"name": "Guest"}])
    merc("two_guests", [("amerc_5", 1)], [hero, {"name": "Guest"}, {"name": "Guest2"}])
    merc("missing_member_unit", [("amerc_5", 1)], [hero, {"name": "Ghost", "present": False},
                                                   {"name": "Ghost2", "present": False}])
    merc("dead_hero", [("amerc_5", 1)], [{"name": "Hero", "dead": True}, {"name": "merc1"}, {"name": "merc2"}])
    merc("all_ten", [(f"amerc_{i}", 1 + i % 2) for i in range(1, 11)] + [("b.merc7.n8_7", 1), ("b.merc9.n10_9", 1)],
         [hero, {"name": "merc10"}], "bz14h")
    merc("stale_topics_cleared", [("amerc_2", 1), ("b.merc2.n9_2", 1), ("b.merc2.n2_2", 1), ("b.merc2.n11_2", 1),
                                  ("b.merc2.n3_2", 1)], [hero])
    rng = random.Random(seed ^ 0x591800)
    for i in range(fuzz):
        variables, party = [], [hero]
        for n in range(1, 11):
            if rng.random() < 0.6:
                variables.append((f"amerc_{n}", rng.choice([1, 2])))
            for k in [8, 10, 1, 2, 3, 9, 11]:
                if rng.random() < 0.12:
                    variables.append((f"b.merc{n}.n{k}_{n}", rng.choice([1, 2])))
        for n in rng.sample(range(1, 11), rng.choice([0, 1, 1, 2, 3])):
            dead = rng.random() < 0.25
            party.append({"name": f"merc{n}", "dead": dead})
            if dead:
                variables.append((f"adeadn{n}", 1))
        if rng.random() < 0.3:
            party.append({"name": "Guest"})
        merc(f"seeded_{i:03}", variables, party, rng.choice(["bz1g", "bz2g", "bz6g", "bz8k", "bz14h", "bz9k", "gz1g"]))
    def complete(name, key, variables=(), record=None, party=(hero,), zone_id="bz2g", money=100):
        rows.append({"id": "dialogue_complete/" + name, "kind": "dialogue_complete",
                     "inputs": {"key": key, "variables": [list(v) for v in variables], "record": record,
                                "party": list(party), "zone": zone_id, "money": money}})

    complete("no_record", "b.smith.t1", [("b.smith.t1", 1)])
    complete("money_and_experience", "b.smith.t1", [("b.smith.t1", 1)], {"experience": 150, "money": 40})
    for money in [10.7, -3.5, -0.5, 0.999]:
        complete(f"money_{money}", "b.smith.t1", [("b.smith.t1", 1)], {"money": money})
    complete("quest_lists", "b.elder.s3", [("b.elder.s3", 1), ("q.gz1g.q1", 2), ("z.gz2g", 1)],
             {"give_quests": ["q.gz1g.q1", "q.gz1g.q2"], "give_quests2": ["q.gz1g.q3.1"],
              "open_zones": ["z.gz2g", "z.gz3g"], "unknown2": ["z.gz11k"]})
    complete("same_var_in_lists", "b.elder.s4", [("b.elder.s4", 1)],
             {"give_quests": ["q.x"], "give_quests2": ["q.x"], "open_zones": ["q.x", "q.y"], "unknown2": ["q.y"]})
    complete("rewards_name_own_key", "b.elder.s5", [("b.elder.s5", 1)], {"give_quests": ["b.elder.s5"]})
    complete("not_pending", "b.smith.t9", [])
    complete("two_part_key", "b.smith", [("b.smith", 1)], {"money": 5})
    complete("four_part_key", "b.smith.t1.x", [("b.smith.t1.x", 1)], {"money": 5})
    complete("mixed_case_key", "b.Smith.T1", [("b.Smith.T1", 1)], {"money": 5, "give_quests": ["q.Mixed"]})
    complete("merc_not_yet", "b.merc3.n8_3", [("amerc_3", 1), ("b.merc3.n8_3", 1)])
    complete("merc_hire", "b.merc3.n1_3", [("amerc_3", 1), ("b.merc3.n1_3", 1)])
    complete("merc_rehire", "b.merc3.n3_3", [("amerc_3", 2), ("b.merc3.n3_3", 1)])
    complete("merc_dismiss_home", "b.merc3.n2_3", [("amerc_3", 2), ("b.merc3.n2_3", 1)],
             party=[hero, {"name": "merc3"}])
    complete("merc_dismiss_not_in_party", "b.merc3.n2_3", [("amerc_3", 2), ("b.merc3.n2_3", 1)])
    complete("merc_farewell", "b.merc3.n10_3", [("amerc_3", 2), ("b.merc3.n10_3", 1)],
             party=[hero, {"name": "merc3"}])
    complete("merc_farewell_not_in_party", "b.merc3.n10_3", [("amerc_3", 2), ("b.merc3.n10_3", 1)])
    complete("merc_mismatched_index", "b.merc3.n1_4", [("amerc_4", 1), ("b.merc3.n1_4", 1)])
    complete("merc_story_farewell", "b.merc2.n2_10", [("amerc_2", 2), ("b.merc2.n2_10", 1)],
             party=[hero, {"name": "merc2"}])
    complete("merc_upper_case", "B.MERC3.N1_3", [("amerc_3", 1), ("B.MERC3.N1_3", 1)])
    complete("merc_with_reward", "b.merc4.n1_4", [("amerc_4", 1), ("b.merc4.n1_4", 1)], {"money": -50})
    rng = random.Random(seed ^ 0x592090)
    for i in range(fuzz):
        n = rng.randint(1, 10)
        key = rng.choice([f"b.merc{n}.n{rng.choice([1, 2, 3, 8, 9, 10, 11])}_{n}", "b.smith.t1", "b.elder.s3"])
        variables = [(key, 1)] + [(f"amerc_{m}", rng.choice([1, 2])) for m in rng.sample(range(1, 11), 3)]
        record = None if rng.random() < 0.3 else {
            "experience": rng.choice([0, 25, 300.5]), "money": rng.choice([0, 15, -20, 7.25]),
            "give_quests": [f"q.f{rng.randint(0, 5)}" for _ in range(rng.randint(0, 3))],
            "give_quests2": [f"q.f{rng.randint(0, 5)}" for _ in range(rng.randint(0, 2))],
            "open_zones": [f"z.f{rng.randint(0, 3)}" for _ in range(rng.randint(0, 2))],
            "unknown2": [f"z.f{rng.randint(0, 3)}" for _ in range(rng.randint(0, 2))]}
        for m in range(rng.randint(0, 3)):
            variables.append((f"q.f{rng.randint(0, 5)}", rng.choice([1, 2, 3])))
        party = [hero] + [{"name": f"merc{m}"} for m in rng.sample(range(1, 11), rng.randint(0, 2))]
        complete(f"seeded_{i:03}", key, variables, record, party,
                 rng.choice(["bz1g", "bz2g", "bz8k", "bz14h"]), rng.randint(0, 500))
    return rows


def _string_list(value):
    return isinstance(value, list) and all(type(v) is str for v in value)


def validate(case, steps, role):
    kind = case["kind"]
    for step in steps:
        state = step["state"]
        if kind == "dialogue_topics":
            ok = (set(state) == {"open", "topics", "titles"} and type(state["open"]) is bool
                  and _string_list(state["topics"]) and _string_list(state["titles"])
                  and len(state["topics"]) == len(state["titles"])
                  and state["open"] == bool(state["topics"]))
        elif kind == "dialogue_zone":
            ok = (set(state) == {"started", "briefing"} and type(state["started"]) is bool
                  and type(state["briefing"]) is str and (state["started"] or state["briefing"] == ""))
        elif kind == "dialogue_complete":
            completion = state.get("completion")
            ok = (set(state) == {"completion", "money", "experience", "merc_events", "variables"}
                  and isinstance(completion, list) and len(completion) == 5 and type(state["money"]) is int
                  and isinstance(state["experience"], list) and isinstance(state["merc_events"], list)
                  and isinstance(state["variables"], dict))
        else:
            values = state.get("variables")
            ok = (set(state) == {"variables"} and isinstance(values, dict)
                  and all(type(k) is str and k.startswith(("b.merc", "amerc_")) and type(v) in (int, float)
                          and v != 0 for k, v in values.items()))
        if not ok:
            raise ValueError(f"{role} {case['id']} has an invalid {kind} observation")
