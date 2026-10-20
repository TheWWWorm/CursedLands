extends Node
## Real LiA companion, death, reward, save/reload and revival.
## Default: prepare the original prison-camp Kel using the recruitment path.
## --route-save optionally retains the previous read-only diagnostic workflow.
var checks := 0
var failures := 0
class ProbeSession extends Session:
	var events: Array = []
	func broadcast(event: Dictionary) -> void: events.append(event)
	func sync_state() -> void: pass
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func kel_of(s: Session) -> GameUnit:
	for u: GameUnit in s.world.units.values():
		if u.has_meta("hero") and u.get_meta("hero").get("merc", -1) == 2: return u
	return null
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--route-save="): source = arg.trim_prefix("--route-save=")
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"confine_mouse":0,"control_mode":1,"display_mode":0}, true)
	var s := ProbeSession.new(); add_child(s)
	var g := Game.new(); g.session=s; s.game=g; add_child(g)
	s.set_physics_process(false)
	if source.is_empty():
		s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
		await s.enter_zone("bz1h",1,false)
		s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
		s.state.set_var(0,"apartyn2",1);s.merc_changed(2,true,0)
		check(s.world!=null,"prepared original LiA prison camp loads")
	else:
		var state := CampaignState.load_from(source)
		check(state != null and s._load_state("fallen_xp_fixture",state), "supplied LiA save loads")
	if s.world == null: get_tree().quit(1); return
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false); s.world.vm.instances.clear()
	var kel := kel_of(s)
	check(kel != null, "party includes recruited Kel")
	if kel == null: get_tree().quit(1); return
	s.mod_config.rules.revive=1; GameData.options.revive=1
	var original_max := kel.max_hp
	kel.take_damage(1000000.0,null)
	check(kel.dead and Revive.revivable(s,kel), "Kel dies through combat and remains revivable")
	var record: Dictionary = kel.get_meta("hero")
	var corpse_hp := kel.hp
	for mode in ["single_split","single_full","coop_full"]:
		s.online = mode == "coop_full"
		GameData.options.sp_full_xp=int(mode == "single_full"); s.mod_config.rules.sp_full_xp=GameData.options.sp_full_xp
		GameData.options.coop_full_xp=1; s.mod_config.rules.coop_full_xp=1
		for reward in ["kill","quest","talk","side"]:
			var before := float(record.exp_total)
			var intel := float(record.int)+Perks.attr_bonus(record,"int")
			var expected := (50.0 if mode == "single_split" else 100.0)*pow(1.04,intel-25.0)
			XpRules.give(s,100.0,reward,kel.controller)
			check(absf(float(record.exp_total)-before-expected)<0.003, mode+": downed Kel receives "+reward+" XP")
		check(kel.dead and is_equal_approx(kel.hp,corpse_hp) and is_equal_approx(kel.max_hp,original_max), mode+": XP does not heal or revive the corpse")
	s.online=false
	GameData.options.revive=0; s.mod_config.rules.revive=0
	var before := float(record.exp_total)
	XpRules.give(s,100.0,"quest",kel.controller)
	check(record.exp_total==before, "revival disabled excludes dead companions")
	GameData.options.revive=1; s.mod_config.rules.revive=1
	s.state.store_zone(s.zone_id,s.world)
	check(s.state.save("user://fallen-xp.sav")==OK, "save records XP earned while downed")
	var saved := CampaignState.load_from("user://fallen-xp.sav")
	check(saved != null and saved.mercs[2].exp_total==record.exp_total, "reload preserves Kel's earned XP")
	Revive.finish(s,kel)
	check(not kel.dead and absf(kel.hp-ModStore.capability("revival.health"))<0.001, "revival keeps its configured HP amount")
	check(kel.max_hp>original_max, "revival applies the pools from accumulated XP")
	check(kel.get_meta("hero").exp_total==before, "revival retains all XP")
	g.queue_free(); s.queue_free()
	for i in 8: await get_tree().process_frame
	print("FALLEN_PARTY_XP ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
