extends "local_host_campaign.gd"
## Loaded campaign actors and terrain, real authority subprocess, wall clock,
## and replicated movement/stamina at deliberately low frontend frame rates.
## This is a runtime regression check, not a recording of native gameplay.
var samples: Array[Dictionary] = []
var endpoint := Vector2.ZERO
var zone := "gz1g"
var avoid_combat := OS.get_cmdline_user_args().has("--avoid-combat")
var party_size := 1

func clear_of_actors(w: GameWorld, hero: GameUnit, points: PackedVector2Array) -> bool:
	for other: GameUnit in w.unit_rows():
		if other.controller==hero.controller or other.dead or other.hidden:continue
		# Neutral miners occupy almost every LiA passage. Keep enough space
		# to avoid body collision; reserve the full combat margin for enemies.
		var clearance := 30.0 if w.is_enemy(other,hero) else 4.0
		for p in points:
			if p.distance_squared_to(other.pos)<clearance*clearance:return false
	return true

func seconds(duration: float) -> void:
	await get_tree().create_timer(duration, true, false, true).timeout

func measure(s: Session, u: GameUnit, duration: float, moving: bool, command := {}, members: Array = []) -> Dictionary:
	var start := Time.get_ticks_usec()
	var start_time := s.world.time
	var start_mana := u.mana
	var previous := u.pos
	var distance := 0.0
	var frame_start := Engine.get_process_frames()
	var first_motion_wall := -1.0
	var first_motion_sim := 0.0
	var party := []
	for member: GameUnit in members:
		party.append({"uid":member.uid,"previous":member.pos,"distance":0.0,"mana":member.mana,"hp":member.hp})
	if not command.is_empty():s.submit(command)
	while s.world.time-start_time < duration and Time.get_ticks_usec()-start < 12000000:
		await get_tree().process_frame
		distance += previous.distance_to(u.pos)
		previous = u.pos
		for i in members.size():
			party[i].distance += party[i].previous.distance_to(members[i].pos)
			party[i].previous = members[i].pos
		if first_motion_wall<0.0 and distance>0.25:
			first_motion_wall=(Time.get_ticks_usec()-start)/1000000.0
			first_motion_sim=s.world.time-start_time
	var wall := (Time.get_ticks_usec()-start)/1000000.0
	var simulation := s.world.time-start_time
	for i in members.size():
		party[i].erase("previous")
		party[i].metres_per_sim_second=party[i].distance/maxf(simulation,0.001)
		party[i].stamina_change=members[i].mana-party[i].mana
		party[i].hp_change=members[i].hp-party[i].hp
		party[i].dead=members[i].dead
	return {"wall":wall,"simulation":simulation,"rate":simulation/wall,
		"distance":distance,"metres_per_sim_second":distance/maxf(simulation,0.001),
		"stamina_change":u.mana-start_mana,"moving":moving,
		"first_motion_wall":first_motion_wall,"first_motion_sim":first_motion_sim,
		"after_first_motion_rate":(simulation-first_motion_sim)/maxf(wall-first_motion_wall,0.001) if first_motion_wall>=0.0 else 0.0,
		"fps":float(Engine.get_process_frames()-frame_start)/wall,"party":party}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zone="): zone = arg.trim_prefix("--zone=")
		if arg.begins_with("--party-size="): party_size = clampi(int(arg.trim_prefix("--party-size=")),1,3)
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,
		"autosave":0,"show_tutorial":0,"auto_graphics":0,"free_run":0,"stamina_regen":0,
		"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	# Build one full save so every trial begins with the same map and hero.
	var seed := Session.new(); add_child(seed)
	var seed_game := Game.new(); seed_game.session=seed; seed.game=seed_game; add_child(seed_game)
	seed.state.ensure_hero(0,"Human Hero")
	for i in range(1,party_size):
		seed.state.add_party_unit(seed.state.current_party,"TimingParty%d"%i,"Human Hero")
	if not seed.zone_exists(zone):
		check(false,"selected timing zone exists in this campaign: "+zone)
		get_tree().quit(1);return
	await seed.enter_zone(zone,1,false)
	if seed.world==null:
		check(false,"timing fixture loads the selected world")
		get_tree().quit(1);return
	seed.set_physics_process(false); seed.world.set_process(false); seed.world.set_physics_process(false)
	var hero: GameUnit = seed.party_units(0)[0]
	var origin := hero.pos
	var found := false
	for ring in (48 if avoid_combat else 12):
		for angle in 16:
			var at := origin+Vector2.from_angle(float(angle)*TAU/16.0)*float(ring*3)
			if not seed.world.nav.is_walkable(at,hero.move_class()):continue
			hero.pos=at; seed.world.nav.track_unit(hero)
			if avoid_combat and not clear_of_actors(seed.world,hero,PackedVector2Array([at])):continue
			for direction in 16:
				var to := at+Vector2.from_angle(float(direction)*TAU/16.0)*40.0
				var path:=seed.world.nav.find_path(at,to,[hero],[],0.0,hero.move_class())
				if not path.is_empty() and path[-1].distance_to(at)>35.0 and (not avoid_combat or clear_of_actors(seed.world,hero,path)):
					endpoint=path[-1];found=true;break
			if found:break
		if found:break
	check(found,"loaded map has a traversable route longer than the timing sample")
	if not found:
		get_tree().quit(1);return
	var party: Array = seed.party_units(0)
	check(party.size()==party_size,"requested party is present in the loaded campaign")
	var starts := []
	var direction := hero.pos.direction_to(endpoint)
	for i in party.size():
		var member: GameUnit=party[i]
		if i>0:
			var wanted := hero.pos-direction*float(i)*2.5
			var placed := false
			for ring in 5:
				for angle in 16:
					var candidate := wanted+Vector2.from_angle(float(angle)*TAU/16.0)*float(ring)*1.5
					# Check before stamping the unit: is_walkable includes actors,
					# so a valid occupied cell becomes closed to this raw query.
					if not seed.world.nav.is_walkable(candidate,member.move_class()):continue
					if avoid_combat and not clear_of_actors(seed.world,hero,PackedVector2Array([candidate])):continue
					var overlaps := false
					for j in range(i):
						if candidate.distance_to(party[j].pos)<1.5:overlaps=true
					if overlaps:continue
					var path:=seed.world.nav.find_path(candidate,endpoint,[member],[],0.0,member.move_class())
					if path.is_empty() or path[-1].distance_to(endpoint)>1.0:continue
					member.pos=candidate;seed.world.nav.track_unit(member);placed=true;break
				if placed:break
			check(placed,"party member starts on a connected, unoccupied cell away from unrelated actors")
			if not placed:
				get_tree().quit(1);return
		member.command({"type":"wait","t":0.1});member.mana=member.max_mana*0.8;member.set_gait(3)
		starts.append([member.pos.x,member.pos.y])
	seed.state.play_clock={"speed":0,"paused":false}
	check(seed.save_game("loaded-rate-seed")==OK,"repeatable loaded-map seed saved")
	var population := seed.world.units.size()
	var fixture := {"campaign":GameData.campaign_id,"zone":zone,"title":seed.zone_title(zone),
		"mob":seed.campaign.zone(zone).get("mob",""),"mpr":seed.campaign.zone(zone).get("mpr",""),
		"from":[hero.pos.x,hero.pos.y],"to":[endpoint.x,endpoint.y],"population":population,"party_size":party_size,"party_starts":starts}
	seed_game.queue_free();seed.queue_free()
	for i in 6:await get_tree().process_frame
	var s := Session.new();get_parent().add_child(s)
	var g := Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	check(await s.local_host.start(0,1,true)==OK,"real solo authority process starts")
	for fps in [60,20,10]:
		for speed in [1,2]:
			Engine.max_fps=60
			check(await s.load_game_shown("loaded-rate-seed"),"loaded-map seed restored")
			check(await until(func():return s.world!=null and not s._remote_loading and not s.movie_active(),30),"frontend receives loaded world")
			var u: GameUnit=s.party_units(0)[0]
			var members: Array=s.party_units(0)
			var ids:=members.map(func(member):return member.uid)
			check(members.size()==party_size,"full party survives the authority save/load")
			g.set_speed(speed);Engine.max_fps=fps
			await seconds(0.6)
			var hp := u.hp
			# Include command/path startup in the wall-time window. Starting
			# only after movement excludes that stall but includes its retained
			# clock debt, producing a false apparent acceleration.
			var moving := await measure(s,u,4.0,true,{"t":"move","units":ids,"x":endpoint.x,"y":endpoint.y,"run":true},members)
			check(moving.first_motion_wall>=0.0 and moving.first_motion_wall<5.0,"movement command reaches real authority")
			s.submit({"t":"stop","units":ids})
			await seconds(0.5)
			var idle := await measure(s,u,3.3,false,{},members)
			var row := {"cap":fps,"speed":speed,"moving":moving,"idle":idle,"population":population,
				"hp_before":hp,"hp_after":u.hp,"dead":u.dead,"paused":get_tree().paused,"movie":s.movie_active()}
			samples.append(row);print("LOADED_RATE ",JSON.stringify(row))
			var expected := 55.0/27.0 if speed==2 else 1.0
			check(absf(moving.rate-expected)<0.20 and absf(idle.rate-expected)<0.20,"loaded simulation follows wall time at %d FPS, speed %d"%[fps,speed])
			check(moving.distance>2.0 and moving.stamina_change<0,"running moves and consumes stamina")
			check(idle.distance<0.15 and idle.stamina_change>0,"stopped character recovers stamina")
			check(u.hp==hp and not u.dead,"unrelated combat did not contaminate timing sample")
			for i in members.size():
				var m:Dictionary=moving.party[i]
				var rest:Dictionary=idle.party[i]
				check(m.distance>8.0 and m.stamina_change<0,"each party member runs a substantial distance")
				check(rest.distance<0.15 and rest.stamina_change>0,"each party member stops and recovers stamina")
				check(m.hp_change==0 and rest.hp_change==0 and not rest.dead,"party movement is not contaminated by combat")
				if samples.size()>1:
					var reference:Dictionary=samples[0].moving.party[i]
					check(absf(m.metres_per_sim_second/reference.metres_per_sim_second-1.0)<0.25,
						"party member progression stays comparable across speed and frontend FPS")
			if samples.size()>1:
				var baseline:Dictionary=samples[0]
				check(absf(moving.metres_per_sim_second/baseline.moving.metres_per_sim_second-1.0)<0.12,"movement per simulation second is independent of speed and frontend FPS")
				check(absf(moving.stamina_change/moving.simulation-baseline.moving.stamina_change/baseline.moving.simulation)<u.max_mana*0.025,"running stamina per simulation second is independent of frontend FPS")
	Engine.max_fps=60;g.set_speed(1)
	await s.local_host.stop();g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	FileAccess.open("user://local-host-loaded-rate.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"zone":zone,"fixture":fixture,"samples":samples,
		"window":"command submission through four simulation seconds",
		"animation_binding_prepare":ClassDB.class_has_method("AnimationPlayer","prepare_track_caches"),
		"animation_cache_retention":ClassDB.class_has_method("AnimationPlayer","set_preserve_track_caches_on_finish")},"\t"))
	print("LOCAL_HOST_LOADED_RATE ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
