extends "coop_rename_reconnect.gd"
## Fresh process consumes only the actual ENet-produced personal save files.
func _ready() -> void:
	await get_tree().process_frame
	process_mode=Node.PROCESS_MODE_ALWAYS; outer_scene=get_tree().current_scene
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0},true)
	var directory:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--source-dir="): directory=arg.trim_prefix("--source-dir=")
	check(not directory.is_empty(),"actual network result directory supplied")
	if directory.is_empty(): await finish(); return
	for name_: String in ["ann","fresh"]:
		var slot:="solo_resume_"+name_
		var saved:=CampaignState.load_from(directory.path_join(slot+".sav"))
		check(saved!=null and saved.save(SaveInfo.path(slot))==OK,"copy received "+name_+" save into independent process profile")
		if saved==null: continue
		check(saved.current_party=="FPrison" and saved.current_zone=="gz1h","received "+name_+" selects the shared chapter and field")
		var app:=branch("Independent"+name_)
		var session:=Session.new(); app.add_child(session); app.start_game(session)
		session.set_physics_process(false)
		check(await session.load_game_shown(slot),"independent "+name_+" resumes through normal load")
		freeze(session)
		var units:=session.party_units(0)
		check(units.size()==1,"independent "+name_+" deploys one local protagonist")
		if units.is_empty(): continue
		var u: GameUnit=units[0]
		check(u.proto.get("name")=="Hero1" and String(u.info.get("name"))=="Hero","independent "+name_+" deploys authored Hero1 body/script identity")
		check(u.get_meta("hero").str==44.0 and not u.dead and u.hp>0.0,"independent "+name_+" retains new solo training on a usable actor")
		check(session.state.money==777 and session.state.items==["rune:e1","rune:e2","rune:ic"],"independent "+name_+" retains private money and acquired items")
		check(u.pos.distance_to(saved.heroes[0][0].get("pos",Vector2.INF))<0.01,"independent "+name_+" restores its own shared-world position")
		check(saved.quests.values().has(2) and session.state.quests==saved.quests,"independent "+name_+" retains completed own quest journal")
		check(session.state.heroes.size()==1 and session.world.units.values().all(func(actor: GameUnit):return not actor.has_meta("hero") or actor.controller==0),"independent "+name_+" has no borrowed network owner")
		app.get_parent().queue_free(); roots.erase(app.get_parent())
		for i in 4: await get_tree().process_frame
	await finish()

func finish() -> void:
	print("COOP_SOLO_RETURN_RESUME ",checks," checks ",failures," failures")
	await super.finish()
