extends "lia_kel_support.gd"
## Prepared late-Jigran records supply the previously earned fragments and
## archived Kel. Actual dialogue and installed scripts decide every outcome.
## Native 1.02 distinguishes an unsynchronized cheat-given bag from a bag
## stored by LeaveToZone: AddLoot reads the named party's saved snapshot.
## Synchronized AddLoot restores the three stored fragments after the ritual
## consumes the live set; saving alone does not synchronize a named bag.
const FRAGMENTS := ["kel1","kel2","kel3"]
var kel_stats: Array
var kel_equipment: Array

func _ready() -> void: run.call_deferred()

func settle() -> void:
	await frames(4)
	var deadline := Time.get_ticks_msec()+45000
	while s.loading_game and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	freeze()
	ticks(8)

func fragments(expected: Array, label: String) -> void:
	check(s.state.quest_items.size() == expected.size() and s.state.quest_items.has_all(expected),label)

func synchronize() -> void:
	# Match the native checkpoint's real same-zone travel, not a test-only
	# snapshot assignment. A same ID is insufficient to prove travel occurred.
	var previous_world := s.world
	vm()._call("LeaveToZone",[[ScriptParser.N_NUM,0],[ScriptParser.N_STR,"bz31j"],
		[ScriptParser.N_NUM,0]],ScriptVM.Instance.new())
	ticks(1)
	await frames(4)
	var deadline := Time.get_ticks_msec()+45000
	while (s.world == previous_world or s.loading_game) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	check(s.world != previous_world and s.zone_id == "bz31j" and not s.loading_game,
		"real same-zone LeaveToZone stores the prepared named party")
	freeze(); ticks(8)
	vm().recalc_merc_briefings()

func finish_rescue(tag: String, expected_fragments: Array) -> void:
	await complete("b.Deva.brief_345")
	check(value("b.Junofil.fq20") == 1 and value("b.merc2.fq21") == 0,
		tag+": all three fragments offer Junofil while Kel awaits ritual completion")
	fragments(FRAGMENTS,tag+": fragment check leaves the live bag intact before ritual closes")
	await complete("b.Junofil.fq20"); await settle()
	fragments(expected_fragments,tag+": completed ritual retains the original stored fragment set")
	check(s.state.current_party == "Jigran3" and value("b.merc2.fq21") == 1,
		tag+": ritual completes actual party transition and offers Kel conversation")
	var restored := s.state.party_member("Jigran3::merc2")
	if check(not restored.is_empty(),tag+": rescued party contains original Kel role"):
		check([restored.str,restored.dex,restored["int"],restored.exp,restored.exp_total] == kel_stats,
			tag+": rescue restores Kel's archived stats and earned experience")
		check([restored.weapons,restored.armors] == kel_equipment,tag+": rescue restores Kel's archived equipment")
	var actor: GameUnit = vm()._by_name("merc2")
	check(actor != null and not actor.dead and actor.has_meta("hero"),tag+": rescued Kel is a living deployed party actor")
	check(s.state.mercs.is_empty() and value("b.merc2.n11_2") == 0,
		tag+": actual roster recalculation recognizes named-party Kel without a hired-merc record")
	await complete("b.merc2.fq21")
	check(value("b.merc2.fq21") == 2,tag+": rescued Kel conversation is passable")
	await roundtrip("lia_kel_rescued_"+tag,["b.Junofil.fq20","b.merc2.fq21"],expected_fragments)
	fragments(expected_fragments,tag+": saved final inventory remains exact after reload")
	if tag == "synchronized":
		for fragment: String in FRAGMENTS:
			check(s.state.quest_items.has(fragment),"reload retains native AddLoot's restored "+fragment)
	check(s.state.party_records(0).filter(func(row): return String(row.get("name","")).to_lower() == "merc2").size() == 1,
		tag+": reload retains exactly one rescued Kel")
	actor = vm()._by_name("merc2")
	check(actor != null and not actor.dead and actor.has_meta("hero") and actor.controller == 0,
		tag+": reloaded Kel remains alive and under player control")
	vm().recalc_merc_briefings()
	check(value("b.merc2.n11_2") == 0,tag+": reload recalculation still recognizes named-party Kel")

func run() -> void:
	boot()
	s.state.create_party("Jigran2"); s.state.add_party_unit("Jigran2","Hero","Hero3")
	s.state.create_party("Jigran5"); s.state.add_party_unit("Jigran5","merc2","merc2")
	var original_kel := s.state.party_member("Jigran5::merc2")
	original_kel.str = 40.0; original_kel.dex = 41.0; original_kel["int"] = 42.0
	original_kel.exp = 150.0; original_kel.exp_total = 4444.0
	kel_stats = [original_kel.str,original_kel.dex,original_kel["int"],original_kel.exp,original_kel.exp_total]
	kel_equipment = [original_kel.weapons.duplicate(),original_kel.armors.duplicate()]
	s.state.set_current_party("Jigran2")
	s.state.set_var(0,"q.gz35j.q17j",2)
	s.state.set_var(0,"b.Deva.brief_345",1)
	await enter("bz31j")
	start(["VCheck#0#5","VCheck#0#6","VCheck#0#7"])
	for item: String in FRAGMENTS: s.state.add_item(item)
	vm().recalc_merc_briefings()
	check(value("b.Junofil.fq20") == 0 and s.state.current_party == "Jigran2",
		"all fragments alone do not skip the preceding Deva conversation")
	check(value("b.merc2.n11_2") == 1 and s.state.mercs.is_empty(),
		"archived Kel alone is not treated as a member of the current party")
	check(s.save_game("lia_kel_before_rescue") == OK,"save prepared three-fragment rescue checkpoint")

	# This control matches the old native cheat fixture: items were given
	# after arrival and no travel has stored them in Jigran2's bag snapshot.
	await finish_rescue("unsynchronized",[])

	for missing: String in FRAGMENTS:
		check(await s.load_game_shown("lia_kel_before_rescue"),"restore independent missing-fragment branch "+missing)
		freeze(); s.state.quest_items.erase(missing)
		var remaining := FRAGMENTS.duplicate(); remaining.erase(missing)
		await synchronize()
		fragments(remaining,"missing "+missing+": same-zone travel preserves exactly the two supplied fragments")
		await complete("b.Deva.brief_345"); await settle()
		check(value("b.Junofil.fq20") == 0 and value("b.merc2.fq21") == 0,
			"missing "+missing+" refuses both rescue conversations")
		check(s.state.current_party == "Jigran3" and s.state.party_member("Jigran3::merc2").is_empty(),
			"missing "+missing+" follows original solo branch without resurrecting Kel")
		fragments(remaining,"missing "+missing+": native AddLoot retains exactly the other two synchronized fragments")
		check(value("b.merc2.n11_2") == 1,"missing "+missing+": archived Kel is still excluded from current-roster recalculation")
		await roundtrip("lia_kel_missing_"+missing,["b.Junofil.fq20","b.merc2.fq21"],remaining)
		fragments(remaining,"missing "+missing+": reload preserves the exact retained fragment set")

	check(await s.load_game_shown("lia_kel_before_rescue"),"restore complete fragment set before real travel")
	freeze(); await synchronize()
	fragments(FRAGMENTS,"same-zone travel preserves all three supplied fragments before ritual")
	await finish_rescue("synchronized",FRAGMENTS)
	await finish("LIA_KEL_RESCUE","Prepared late-Jigran records and fragment set. Actual LeaveToZone precedes all four rescue branches: each missing fragment blocks restoration and retains its other two; the complete set enables actual preceding/ritual/reunion dialogues and once-only Kel restoration with archived stats/equipment. Native AddLoot restores stored fragments after consuming the live set; the unsynchronized control has no stored fragments to restore. Save/load preserves both outcomes and current named-mercenary recalculation. Not a full island-to-island playthrough or native executable replay.")
