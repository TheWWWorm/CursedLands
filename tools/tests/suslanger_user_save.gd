extends "story_coop_traps_net.gd"
## Read-only inspection of a supplied save, copied into an isolated profile.
var source_file := ""
var report := {}

func unit_row(u: GameUnit) -> Dictionary:
	return {"uid":u.uid,"name":u.display_name,"prototype":u.info.get("prototype",""),"pos":[u.pos.x,u.pos.y],
		"hp":u.hp,"dead":u.dead,"controller":u.controller,"faction":u.faction,"mode":u.mode,
		"gait":u.gait(),"running":u.running,"action":u.action,"facing":u.facing,
		"hidden":u.hidden,"sight":u.stats.get("sight"),"sight_factor":u.sight_factor(),"detect":u.detect(0),
		"order":str(u.order),"orders":str(u.orders),"logic":host.world.ai.logic(u),"mots":host.world.ai.mots(u)}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--supplied-save="): source_file=arg.trim_prefix("--supplied-save=")
	check(FileAccess.file_exists(source_file),"supplied source exists")
	if failures: await finish(); return
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0,"confine_mouse":0,"show_fps":1,
		"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	check(DirAccess.copy_absolute(source_file,SaveInfo.path("suslanger-inspect"))==OK,"copy save into disposable slot")
	report.source_sha256=FileAccess.get_sha256(source_file)
	host=branch(false); check(host.host(29951,2)==OK,"open isolated inspection host"); host.set_physics_process(false)
	check(host.load_game("suslanger-inspect"),"load supplied save through Session")
	if host.world==null: await finish(); return
	freeze(host)
	report.zone=host.zone_id; report.time=host.world.time; report.party=[]; report.nearby=[]
	report.trap_scripts={}
	for name: String in host.world.vm.ast.scripts:
		var script: Dictionary = host.world.vm.ast.scripts[name]
		if "Trap" in name or "trap" in str(script).to_lower(): report.trap_scripts[name]=script
	report.units=[]
	for u: GameUnit in host.world.unit_rows(): report.units.append(unit_row(u))
	check(host.zone_id=="gz19h","restores Suslanger frontier")
	for hero: GameUnit in host.party_units(0):
		report.party.append(unit_row(hero))
		var rows:=host.world.units_near(hero.pos,60.0)
		rows.sort_custom(func(a,b):return a.pos.distance_squared_to(hero.pos)<b.pos.distance_squared_to(hero.pos))
		for u: GameUnit in rows:
			if u.controller>=0: continue
			var row:=unit_row(u)
			row.distance=u.pos.distance_to(hero.pos); row.enemy=host.world.is_enemy(u,hero)
			row.sight_ray=host.world.sight_ray(u,hero)
			row.can_notice=host.world.ai.can_notice(u,hero,float(u.stats.get("sight",0)))
			row.noticed_before=str(u.get_meta("noticed",{}))
			row.enemies=str(host.world.ai.enemies(u)); row.choices=str(host.world.ai.choose(u,[hero]))
			row.reach=host.world.ai._reachable(u,hero)
			report.nearby.append(row)
		report.traps=str(host.world.traps.traps)
		if OS.get_cmdline_user_args().has("--combat"):
			report.combat=[]
			for id: int in [997373,997375,997376]:
				var u: GameUnit = host.world.units[id]
				var origin:=u.pos
				hero.pos=origin+Vector2(-11,0); hero._moving=false; host.world.nav.track_unit(hero)
				u.facing=(hero.pos-u.pos).angle(); u.take_damage(1,hero)
				var trace:=[]; var run_ticks:=0; var shot:=false; var retained:=true
				for tick in 160:
					host.world.time+=GameUnit.TICK; u._tick(GameUnit.TICK)
					if u.action=="run": run_ticks+=1
					retained=retained and u.get_meta("noticed",{}).has(hero.get_instance_id())
					for child in host.world.get_children():
						if child is Projectile and child.source==u: shot=true; child.queue_free()
					if tick%10==0: trace.append({"tick":tick,"pos":str(u.pos),"action":u.action,"running":u.running,"order":str(u.order),"noticed":str(u.get_meta("noticed",{}))})
				check(retained,"saved %d keeps its distant living attacker throughout retaliation"%id)
				check(shot if id!=997373 else run_ticks>=10,"saved %d retaliates with %s after a distant hit"%[id,"a projectile" if id!=997373 else "a running approach"])
				report.combat.append({"uid":id,"shot":shot,"run_ticks":run_ticks,"retained":retained,"range":u.stats.get("range"),"stats":u.stats,"trace":trace})
				u.pos=origin;host.world.nav.track_unit(u)
		break
	FileAccess.open("user://suslanger-inspect.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	check(FileAccess.get_sha256(source_file)==report.source_sha256,"source remains byte identical")
	await finish()
