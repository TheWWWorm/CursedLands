extends "story_coop_traps_net.gd"
## One real Game owns all optional effects through a real authored map.
## Simulation is held; bounded terrain ticks drive installed presentation
## callbacks. This is a composition/lifetime test, not a performance sample.
const Ambient = preload("res://src/game/fx/ambient_life.gd")
const Mist = preload("res://src/game/fx/weather_mist.gd")
const Sources = preload("res://src/game/fx/weather_mist_sources.gd")
const EFFECTS := ["gfx_ambient_wildlife","gfx_ambient_particles","gfx_weather_mist","gfx_clouds","gfx_cloud_shadows","gfx_cloud_reflections","gfx_depth_of_field"]
const ZONE := "gz1g"
var ambient: Ambient
var mist: Mist
var lens: CameraDepthOfField
const WATER_POINT := Vector2(133.5,98.5)
var point := Vector2.INF
var water_height := 0.0
var rows := []
var cloud_quality := 1
var terrain_quality := 0


func configure_view() -> void:
	var game := host.game
	var w := host.world
	w.set_process(false); w.set_physics_process(false); w.terrain.set_process(false)
	host.set_physics_process(false); game.set_process(false); game.sound.set_process(false)
	game.rig.set_process(false); game.hud._tutorial.close()
	for u: GameUnit in w.unit_rows():
		u.set_process(false); u.set_physics_process(false)
		if u.model: u.model.set_process(false)
	var source := Sources.new(w.terrain)
	var hit := source.source(WATER_POINT)
	check(not hit.is_empty(),"authored river patch has actual drawn liquid")
	if not hit.is_empty(): water_height=float(hit.height)
	if not point.is_finite():
		# The river sample is wet. Choose a real nearby seeded
		# grass anchor with verified water within the same local effect range.
		var field := Ambient.Habitats.new(w.terrain)
		var origin := Vector2i((WATER_POINT/Ambient.Habitats.CELL).floor())
		var best := INF
		for y in range(origin.y-2,origin.y+3):
			for x in range(origin.x-2,origin.x+3):
				var p := field.anchor(Vector2i(x,y)); var land := field.habitat(p)
				if land.is_empty() or land.wet or not land.clear or land.area not in ["grass","dry"]: continue
				if absf((land.normal as Vector3).y)<0.94: continue
				for radius: float in [4.0,8.0,12.0,16.0]:
					for direction in 8:
						var q := p+Vector2.from_angle(direction*TAU/8.0)*radius
						var water := source.source(q)
						if water.is_empty() or absf(float(water.height)-float(land.height))>3.0: continue
						var distance := p.distance_squared_to(WATER_POINT)
						if distance<best:
							best=distance; point=p.lerp(q,0.35); water_height=float(water.height)
		check(point.is_finite(),"bounded nearby scan finds shared dry habitat and water")
		if not point.is_finite(): point=WATER_POINT
		print("LIFECYCLE_PATCH ",point," height=",water_height," biome=",field.biome)
	game.rig.pitch=-deg_to_rad(25); game.rig.distance=30
	game.rig.focus(Vector3(point.x,water_height+0.8,-point.y))
	game._update_daylight()
	ambient=game.get_node("AmbientLife") as Ambient
	mist=game.get_node("WeatherMist") as Mist
	lens=game.rig._depth_of_field
	if ambient: ambient.set_process(false)
	if mist: mist.set_process(false)
	if lens: lens.set_process(false)


func owners_tick() -> void:
	ambient._process(0.055); mist._process(0.055); lens._process(0.055)


func advance(count: int) -> void:
	for i in count:
		host.world.terrain._process(0.055)
		owners_tick()


func snapshot() -> Dictionary:
	var poses := []
	for row: Dictionary in ambient.residents.values(): poses.append(row.node.transform)
	for row: Dictionary in ambient.flock: poses.append(row.node.transform)
	return {"ambient":ambient.clock,"poses":poses,"mist":mist.clock,"drift":mist.drift,
		"weights":mist.weights,"clouds":Gfx._cloud_frame.duplicate(true),"focus":lens._focus}


func installed(label: String) -> void:
	var g := host.game; var w := host.world; var t := w.terrain
	check(g.world==w and w.get_parent()==g and w.map.get_parent()==w and t.get_parent()==w.map,
		label+": actual Game/World/Map/Terrain ownership")
	check(ambient.game==g and mist.game==g and lens.rig==g.rig,
		label+": naturally installed local effect owners share the Game")
	check(ambient.world==w and ambient.field.terrain==t and ambient.root.get_parent()==t,
		label+": ambient resources belong to current terrain")
	check(mist.world==w and mist.sources.field.terrain==t and mist.root.get_parent()==t,
		label+": mist resources belong to current terrain")
	check(Gfx._cloud_owner==t.get_instance_id() and t._clouds!=null and Gfx._cloud_frame.state.w==1.0,
		label+": current terrain owns enabled global clouds")
	if cloud_quality>1:
		if Gfx.Clouds.mode()>1:
			check(Gfx._cloud_volume_noise!=null and Gfx._cloud_volume_noise.shape!=null \
				and Gfx._cloud_volume_noise.detail!=null and Gfx._cloud_frame.volume.storm.z==1.0,
				label+": actual active world has ready volume textures and cloud state")
		else:
			check(Gfx._cloud_volume_noise==null,label+": unsupported volume falls back without allocating volume resources")
	check(g.rig.camera.attributes==lens._attributes and lens._attributes!=null,
		label+": current camera owns the optional low-angle lens")
	check(not ambient.flock.is_empty() or not ambient.residents.is_empty(),label+": original ambient models are present")
	check(ambient.particles!=null and ambient.particles.multimesh.visible_instance_count>0,
		label+": regional particles contain authored habitat instances")
	check(not mist.volumes.is_empty() and mist.weights.x>0.0,label+": verified morning sources admit native mist volumes")
	var shown := 0
	for row: Dictionary in mist.volumes.values():
		if row.node.visible and float(row.material.get_shader_parameter("reveal"))>0.0: shown+=1
	check(shown>0,label+": admitted mist has a positive reveal envelope")
	rows.append({"case":label,"world":w.get_instance_id(),"terrain":t.get_instance_id(),
		"point":str(point),"water_height":water_height,"ambient_models":ambient.residents.size()+ambient.flock.size(),
		"particles":ambient.particles.multimesh.visible_instance_count,"mist_volumes":shown,
		"mist_cell_size":Sources.CELL,"cloud_owner":Gfx._cloud_owner,"focus":lens._focus})


func clocks_and_gates() -> void:
	var held := snapshot()
	for i in 8:
		owners_tick(); host.world.terrain._update_cloud_parameters()
	check(snapshot()==held,"repeated held terrain stamp changes no installed effect state")
	var ticks_before := host.world.terrain._waves.time_ticks()
	host.world.terrain.set_process(true); ambient.set_process(true); mist.set_process(true)
	get_tree().paused=true
	await frames(8)
	check(not host.world.can_process() and not ambient.can_process() and not mist.can_process(),
		"real tree pause gates terrain and local effects under the always-processing Game")
	check(snapshot()==held and host.world.terrain._waves.time_ticks()==ticks_before,
		"real pause holds atmosphere, local poses and terrain time")
	host.world.terrain.set_process(false); ambient.set_process(false); mist.set_process(false)
	get_tree().paused=false
	# A newer received clock must still be ignored by the owners while each
	# session loading gate is set. Actual tree pause is checked separately.
	for gate: String in ["loading_game","_zone_holding","_remote_loading"]:
		var a := ambient.clock; var m := mist.clock; var drift := mist.drift
		host.set(gate,true); host.world.terrain._waves.advance(0.055); owners_tick()
		check(ambient.clock==a and mist.clock==m and mist.drift==drift,"installed owners respect "+gate)
		host.set(gate,false); owners_tick()
		check(ambient.clock>a and mist.clock>m,"installed owners resume after "+gate)
	host.world.terrain._update_cloud_parameters()
	var before := snapshot()
	host.lmp_travel=preload("res://src/game/lmp_travel.gd").new(host)
	host.world.terrain._process(0.1); owners_tick()
	check(snapshot()==before,"unregistered retained travel world cannot tick installed effects")
	host.lmp_travel=null
	host._movie_ev={"serial":123}
	owners_tick()
	check(host.game.rig.camera.attributes==null,"movie gate releases the camera lens")
	host._movie_ev={}; owners_tick()
	check(host.game.rig.camera.attributes==lens._attributes and lens._attributes!=null,
		"camera lens returns after movie gate")


func difference(a: Image,b: Image) -> Dictionary:
	var x := a.get_data(); var y := b.get_data(); var changed := 0; var peak := 0
	for i in x.size():
		var d := absi(int(x[i])-int(y[i])); peak=maxi(peak,d)
		if d>2: changed+=1
	return {"channels_over_2":changed,"peak":peak}


func capture(label: String) -> Image:
	await frames(16); await RenderingServer.frame_post_draw
	var result := host.get_viewport().get_texture().get_image()
	check(result.save_png("user://lifecycle-"+label+".png")==OK,"capture "+label)
	return result


func rendered_composition() -> void:
	if DisplayServer.get_name()=="headless": return
	await frames(60)
	# Keep posed models alive while holding their clips. Pausing/resetting an
	# AnimationPlayer can release the CPU-pose presentation cache. The HUD's
	# independent portrait look and clock hands also use wall time.
	for node: Node in host.get_viewport().find_children("*","",true,false):
		if node is AnimationPlayer: node.speed_scale=0.0
		elif node is Portrait or node is HudDial: node.set_process(false)
	var before := await capture("all-on")
	var held := difference(before,await capture("held"))
	check(int(held.channels_over_2)==0,"held composition changes no channels by more than 2/255")
	var floor_changes := maxi(32,int(held.channels_over_2)*2)
	var cloud_frame := Gfx._cloud_frame.duplicate(true)
	var comparisons := {}
	for effect: String in ["ambient","mist","clouds","lens"]:
		match effect:
			"ambient": ambient.root.hide()
			"mist": mist.root.hide()
			"clouds":
				var off := cloud_frame.duplicate(true); off.state.w=0.0
				Gfx.set_cloud_frame(host.world.terrain.get_instance_id(),off)
			"lens": lens.clear()
		var delta := difference(before,await capture(effect+"-off"))
		comparisons[effect]=delta
		check(int(delta.channels_over_2)>floor_changes,"composed view has a visible "+effect+" contribution above held-image variation")
		match effect:
			"ambient": ambient.root.show()
			"mist": mist.root.show()
			"clouds": Gfx.set_cloud_frame(host.world.terrain.get_instance_id(),cloud_frame)
			"lens": lens._process(0.1)
		await frames(16)
	rows.append({"case":"rendered_composition","held":held,"minimum_changed_channels":floor_changes,
		"comparison":comparisons,"renderer":RenderingServer.get_current_rendering_method()})


func options_release() -> void:
	var old_ambient := ambient.root; var old_mist := mist.root
	for key: String in EFFECTS: GameData.options[key]=0
	GameData.options_changed.emit(); owners_tick(); host.world.terrain._update_cloud_parameters()
	check(ambient.root==null and ambient.field==null and ambient.residents.is_empty() and ambient.flock.is_empty(),
		"live options release ambient ownership and models")
	check(mist.root==null and mist.sources==null and mist.cache.is_empty() and mist.volumes.is_empty(),
		"live options release mist ownership, masks and volumes")
	check(not old_ambient.visible and not old_mist.visible,"disabled local roots hide before deferred deletion")
	check(Gfx._cloud_owner==0 and host.world.terrain._clouds==null,"live options release global cloud ownership")
	if cloud_quality>1: check(Gfx._cloud_volume_noise==null,"live options also release volumetric cloud resources")
	check(host.game.rig.camera.attributes==null,"live option restores original camera attributes")
	for key: String in EFFECTS: GameData.options[key]=1
	GameData.options.gfx_clouds=cloud_quality
	GameData.options_changed.emit()
	ambient.set_process(false); mist.set_process(false); lens.set_process(false)
	advance(220)
	installed("re-enabled")


func reload_world() -> void:
	var old := host.world; var old_terrain := old.terrain
	var old_roots := [weakref(ambient.root),weakref(mist.root)]
	var old_id := old_terrain.get_instance_id()
	# The synchronous dispatcher is the normal enter_zone implementation.
	# Observe ownership before queued old-world deletion gets its next frame.
	host._enter_zone(ZONE,1,false)
	configure_view(); advance(220)
	check(host.world!=old and host.world.terrain!=old_terrain,"actual zone reload installs a distinct world and terrain")
	check(is_instance_valid(old) and old.is_queued_for_deletion(),"previous real world awaits deferred teardown")
	var owner := Gfx._cloud_owner; var current := Gfx._cloud_frame.duplicate(true)
	if is_instance_valid(old_terrain): old_terrain._update_cloud_parameters()
	check(Gfx._cloud_owner==owner and Gfx._cloud_frame==current,"retired terrain cannot overwrite active cloud globals")
	await frames(8)
	check(not is_instance_valid(old) and not is_instance_valid(old_terrain),"queued old world and terrain are released")
	check(old_roots.all(func(w):return w.get_ref()==null),"old terrain-owned ambient and mist roots are released")
	check(Gfx._cloud_owner==owner and Gfx._cloud_owner!=old_id and Gfx._cloud_frame==current,
		"old owner teardown cannot clear new global cloud state")
	installed("reloaded")


func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--cloud-quality="): cloud_quality=clampi(int(arg.trim_prefix("--cloud-quality=")),1,3)
		elif arg.begins_with("--terrain-quality="): terrain_quality=clampi(int(arg.trim_prefix("--terrain-quality=")),0,2)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	for key: String in EFFECTS: GameData.options[key]=1
	GameData.options.gfx_clouds=cloud_quality
	GameData.options.gfx_terrain=terrain_quality
	GameData.options.merge({"gfx_volumetric":1,"gfx_water":1,"gfx_wind":1,"autosave":0,"show_tutorial":0,
		"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"scroll_border":0,"unit_fog":0,
		"camera_style":0,"q_aa":0,"q_shadows":0,"confine_mouse":0},true)
	Gfx.ensure_globals(); Gfx.apply_surface_options()
	host=branch(true); host.state=CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	host.state.day=1; host.state.world_time=7.0; host.set_physics_process(false)
	await host.enter_zone(ZONE,1,false)
	configure_view()
	check(ambient!=null and mist!=null and lens!=null,"actual Game installs all requested supported owners")
	if ambient==null or mist==null or lens==null:
		await finish(); return
	advance(220); installed("initial")
	await clocks_and_gates()
	await rendered_composition()
	options_release()
	await reload_world()
	FileAccess.open("user://renderer-world-lifecycle.json",FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"rows":rows,"native_dof_guard":OS.has_feature("ei_far_dof_guard"),
		"cloud_quality":cloud_quality,"terrain_quality":terrain_quality},"\t"))
	print("RENDERER_WORLD_LIFECYCLE %d checks %d failures"%[checks,failures])
	await finish()
