extends Node
## Prepared actual-map state round-trip; no organic campaign or network claim.
var out := "user://"
var s: Session
var game: Game
var checks := 0
var failures := []
var report := {"before":{},"after":{},"assertions":[]}
func check(ok: bool, label: String) -> void:
	checks+=1; report.assertions.append({"ok":ok,"label":label})
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func stop() -> void:
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	game.rig.set_process(false)
func hero() -> GameUnit:
	return s.party_units(0).filter(func(u:GameUnit):return u.has_meta("hero") and not u.get_meta("hero").has("merc"))[0]
func capture(u: GameUnit, n: GameUnit) -> Dictionary:
	return {"hero_facing":u.facing,"hero_mana":u.mana,"hero_gait":u.gait(),"hero_orders":u.orders.duplicate(true),
		"hero_order":u.order.duplicate(true),"npc_id":n.uid,"npc_name":n.info.get("name",""),"npc_proto":n.proto.get("name",""),
		"npc_mana":n.mana,"npc_max_mana":n.max_mana,"npc_facing":n.facing,"npc_gait":n.gait(),
		"npc_is_enemy":s.world.is_enemy(n,u),"npc_hates":s.world.ai._hates(n,0),"npc_hate":n.get_meta("hate",{}),"npc_body":CampaignState.body_state(n),
		"npc_orders":n.orders.duplicate(true),"npc_order":n.order.duplicate(true),"npc_ai_state":n.get_meta("ai_state",0),"npc_order_failed":n.order_failed,"lasting":Spells.save_lasting(s.world),
		"projectiles":s.world.get_children().filter(func(c):return c is Projectile).size(),
		"hero_hp":u.hp,"hero_body":CampaignState.body_state(u)}
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out=arg.trim_prefix("--audit-out=")
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"auto_graphics":0,"autosave":0,"confine_mouse":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	s=Session.new(); add_child(s); s.set_physics_process(false)
	game=Game.new(); game.session=s; s.game=game; add_child(game)
	s.state.ensure_hero(0,"Human Hero"); s._enter_zone("gz1g",1,false); stop()
	var h := hero()
	var candidates := s.world.units.values().filter(func(u:GameUnit):return not u.has_meta("hero") and not u.dead and u.max_mana>0 and not u.has_meta("npc_character"))
	check(not candidates.is_empty(),"actual map has ordinary NPC with mana and no character override")
	if candidates.is_empty(): await finish(); return
	var n: GameUnit=candidates[0]; var nid:=n.uid
	s.world.set_relation(n.faction,h.faction,1)
	check(not s.world.is_enemy(n,h),"prepared neutral diplomacy before personal hostility")
	h.facing=0.987654; h.mana=h.max_mana*0.37; h.restore_gait(0)
	h.command({"type":"move","to":h.pos+Vector2(3,0),"run":false})
	n.mana=n.max_mana*0.23; n.facing=-1.234567; n.restore_gait(0)
	s.world.ai._hate(n,0)
	check(s.world.is_enemy(n,h),"production personal-hostility path makes neutral NPC hostile")
	var call:=ScriptVM.Instance.new(); call.locals={"attacker":n,"target":h}
	s.world.vm._call("Attack",[[ScriptParser.N_VAR,"attacker"],[ScriptParser.N_VAR,"target"]],call)
	n.order_failed=true
	h.body_damage(1.0)
	var arrow:=Projectile.launch(s.world,h,n,true); arrow.roll={"hit":true,"backstab":false}
	var direct:=Projectile.launch_direct(s.world,h,Vector3.RIGHT,true)
	report.before=capture(h,n)
	check(s.save_game("audit_roundtrip")==OK,"full Session save succeeds")
	var disk:Dictionary=CampaignState.read_data(SaveInfo.path("audit_roundtrip"))
	report.saved_hero=disk.heroes[0][0]
	report.saved_npc=disk.zones.gz1g.units[nid]
	report.saved_keys=disk.keys()
	check(s.load_game("audit_roundtrip"),"full Session load succeeds")
	stop(); h=hero(); n=s.world.units[nid]
	report.after=capture(h,n)
	check(is_equal_approx(h.facing,float(report.before.hero_facing)),"hero facing survives full save/load")
	check(is_equal_approx(h.mana,float(report.before.hero_mana)),"hero mana survives full save/load")
	check(h.gait()==int(report.before.hero_gait),"hero gait survives full save/load")
	check(h.orders.is_empty() and h.order.is_empty(),"uncommitted manual movement retains the stop-on-load policy")
	check(is_equal_approx(n.mana,float(report.before.npc_mana)),"ordinary NPC mana survives full save/load")
	check(is_equal_approx(n.facing,float(report.before.npc_facing)),"ordinary NPC facing survives full save/load")
	check(n.gait()==int(report.before.npc_gait),"ordinary NPC gait survives full save/load")
	check(s.world.ai._hates(n,0),"personal hostility survives full save/load")
	check(s.world.is_enemy(n,h),"personally hostile neutral NPC remains an enemy after load")
	check(n.orders.size()==report.before.npc_orders.size() and n.get_meta("ai_state",0)==3,"pending script Attack order and state survive load")
	check(not n.orders.is_empty() and n.orders[0].get("target") == h,"script Attack rebinds its target to the restored hero")
	check(int(report.after.projectiles)==int(report.before.projectiles),"targeted and direct arrows both survive full save/load")
	check(is_equal_approx(h.hp,float(report.before.hero_hp)),"hero wounds survive full save/load")
	await finish()
func finish() -> void:
	report.checks=checks; report.failures=failures; report.campaign=GameData.campaign_id
	FileAccess.open(out.path_join("save-probe.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	game.queue_free(); s.queue_free()
	for i in 10: await get_tree().process_frame
	TexUpscale.shutdown(); print("AUDIT_SAVE ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if not failures.is_empty() else 0)
