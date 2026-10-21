extends Node
## Installed z3q2 overlay: live perception -> journal -> death -> completion.
## Hero start/kill are controlled inputs; map, VM startup and save/load are real.
const QUEST := 'z3q2'
const TARGET := 1000324
var checks := 0
var failures := 0
var trace: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr('FAIL ',label)

func _ready() -> void:
	GameData.options.merge({'autosave':0,'show_tutorial':0,'net_lan':0,'net_upnp':0,'net_directory':0,'auto_graphics':0,'smile_faces':0},true)
	var s := Session.new(); add_child(s); s.set_physics_process(false)
	s.state.ensure_hero(0,'Human Hero'); s.state.world_time = 12.0
	s.state.side_quests[QUEST] = 'active'
	s.state.set_var(0,'q.z3q2.z3q2',1); s.state.set_var(0,'q.z3q2.z3q2.1',1)
	s.state.god_modes[0] = 1
	var g := Game.new(); g.session = s; s.game = g; add_child(g)
	var campaign := CampaignMap.load_from(GameData.texts)
	var zone: String = campaign.zone_by_map(SideQuests.get_quest(QUEST).mpr).id
	await s.enter_zone(zone,1,false)
	s.set_physics_process(false)
	var w := s.world; w.set_process(false); w.set_physics_process(false)
	check(w.get_meta('quest_mob','') == QUEST and w.units.has(TARGET),'normal zone loading injects the authored quest and toad')
	if not w.units.has(TARGET): get_tree().quit(2); return
	for i in 12: w._tick(GameUnit.TICK)
	check(w.vm.qobjs.has(QUEST) and w.vm.qobjs[QUEST].objs.size() == 2,'original overlay script registers both objectives')
	check(s.state.get_var(0,'q.z3q2.z3q2.1') == 1,'unseen toad has not completed the sighting objective')
	var target: GameUnit = w.units[TARGET]
	var hero: GameUnit = s.party_units(0)[0]
	hero.aggressive = false; hero.order.clear(); hero.orders.clear()
	var found := false
	for distance: float in [4.0,6.0,8.0,10.0]:
		for direction in 32:
			var p := target.pos + Vector2.from_angle(direction * TAU / 32.0) * distance
			if not w.nav.cell_open(p,hero.move_class()): continue
			hero.pos = p; hero.facing = (target.pos-p).angle(); hero._sync_transform(0); w.nav.track_unit(hero)
			if w.ai.can_notice(hero,target,float(hero.stats.sight)): found = true; break
		if found: break
	check(found,'prepared nearby start has real terrain visibility to the authored toad')
	if not found: get_tree().quit(2); return
	# Expire the candidate cache after the controlled start placement. Then
	# use the ordinary world phase order; the VM runs before the AI update.
	w.time += 12 * GameUnit.TICK
	var seen_tick := -1; var objective_tick := -1
	for tick in 20:
		w._tick(GameUnit.TICK)
		var seen := w.vm._player_visible().has(target)
		var complete := s.state.get_var(0,'q.z3q2.z3q2.1') == 2
		trace.append({'tick':tick,'seen':seen,'objective':complete,'hero':[hero.pos.x,hero.pos.y]})
		if seen and seen_tick < 0: seen_tick = tick
		if complete and objective_tick < 0: objective_tick = tick
		if seen_tick >= 0 and objective_tick >= 0: break
	check(seen_tick >= 0 and objective_tick >= seen_tick and objective_tick <= seen_tick+1,'live sighting reaches the journal within the next VM tick')
	check(s.state.get_var(0,'q.z3q2.z3q2.2') == 1 and not target.dead,'kill objective activates while the seen target is still alive')
	check(s.save_game('quest-toad-seen') == OK,'save a real loaded map between sighting and kill')
	check(await s.load_game('quest-toad-seen'),'reload the authored overlay and waiting objective')
	s.set_physics_process(false); w = s.world; w.set_process(false); w.set_physics_process(false)
	check(w.vm.qobjs.has(QUEST) and int(w.vm.qobjs[QUEST].cur) == 1,'restored objective remains at the kill step')
	check(s.state.side_quests[QUEST] == 'active','loading a seen-but-living target cannot complete the quest')
	target = w.units[TARGET]; hero = s.party_units(0)[0]
	target.take_damage(target.max_hp * 10,hero)
	check(target.dead,'controlled fatal hit uses the normal death path')
	for i in 2: w._tick(GameUnit.TICK)
	check(s.state.side_quests[QUEST] == 'done' and s.state.get_var(0,'q.z3q2.z3q2') == 2,'death advances and completes the saved authored chain')
	var before := s.state.to_dict()
	for i in 10: w._tick(GameUnit.TICK)
	check(s.state.side_quests[QUEST] == 'done' and s.state.money == before.money,'continued simulation leaves the reward pending without duplicate money')
	FileAccess.open('user://quest-objective-map.json',FileAccess.WRITE).store_string(JSON.stringify({'checks':checks,'failures':failures,'trace':trace,
		'scope':'Authored map/overlay and actual perception, controlled hero start and fatal hit, full campaign save/load. No original whole-scene replay.'},'\t'))
	g.queue_free(); s.queue_free()
	for i in 10: await get_tree().process_frame
	print('QUEST_OBJECTIVE_MAP ',checks,' checks ',failures,' failures')
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
