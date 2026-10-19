extends "./coop_traversal_session.gd"
## Full Trials games followed by ordinary co-op traversal. Run with
## --trials-first --label=retention --duration=900 at the same Ultra/2x
## settings as coop_traversal_session. The player shops through the normal
## bot planner; combat, damage, economy and elimination are unchanged.
var retention_rows := []
var old_worlds: Array[WeakRef] = []

func census(label: String) -> void:
	var made_live := 0
	var made_bytes := 0
	for entry: Array in Gfx._made:
		if entry[0].get_ref() != null: made_live += 1
		made_bytes += String(entry[1]).length()
	var row := {
		"label":label, "ticks":Time.get_ticks_msec(), "pid":OS.get_process_id(),
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"video":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),
		"old_worlds_alive":old_worlds.filter(func(w):return w.get_ref()!=null).size(),
		"frame_listeners":get_tree().get_signal_connection_list("process_frame").size(),
		"figure_models":EIFigure._models.size(), "figure_meshes":EIFigure._meshes.size(),
		"figure_materials":EIFigure._materials.size(), "figure_world":EIFigure._world.size(),
		"figure_foliage":EIFigure._foliage.size(), "foliage_local":EIFigure._foliage_local.size(),
		"unit_textures":EIUnitModel._textures.size(), "unit_surfaces":EIUnitModel._surface_textures.size(),
		"anim_libraries":EIAnim._libraries.size(), "anim_morphs":EIAnim._morphs.size(),
		"textures":GameData._texture_cache.size(), "fade_materials":CameraFade._derived.size(),
		"fade_shaders":CameraFade._shaders.size(), "gfx_shaders":Gfx._made.size(),
		"gfx_live_shaders":made_live, "gfx_shader_chars":made_bytes,
		"warmed_keys":ShaderWarmup._warmed.size(), "warmed_materials":ShaderWarmup._keep.size(),
		"wound_composites":UnitWounds._composites.size(), "wound_bases":UnitWounds._bases.size(),
		"wound_layers":UnitWounds._wound_layers.size(), "wound_bytes":UnitWounds._wound_layer_bytes,
		"wound_jobs":UnitWounds._jobs.size(), "wound_waiters":UnitWounds._overlay_waiting.size()+UnitWounds._waiting.size()
	}
	retention_rows.append(row)
	print("RETENTION ", JSON.stringify(row))
	FileAccess.open("user://retention-"+run_label+("guest" if guest else "owner")+".json",FileAccess.WRITE).store_string(JSON.stringify(retention_rows,"\t"))

func trial(cycle: int) -> void:
	census("before-trials-%d" % cycle)
	GameData.arena_mode=1; GameData.arena_speed=2
	var screen:=ArenaPveScreen.new()
	get_parent().add_child(screen)
	await frames_wait(8)
	screen._seed_input.text=str(7319+cycle)
	screen._begin(); screen.run.auto_save=false
	var prepared := -1
	var next_census := Time.get_ticks_msec()+30000
	var start := Time.get_ticks_msec()
	while screen.run.stage not in ["won","lost"]:
		if screen.run.stage=="prepare" and prepared!=screen.run.wave:
			prepared=screen.run.wave
			ArenaTournamentRun.shop_for(screen.run,cycle+1,prepared,screen.run.lives)
			screen.run.arrange()
			screen._refresh()
			screen._tournament_battles.synchronize()
			await frames_wait(30)
			screen._fight()
		if Time.get_ticks_msec()>=next_census:
			next_census=Time.get_ticks_msec()+30000
			census("trials-%d-round-%d-%s" % [cycle,screen.run.wave,screen.run.stage])
			print("RETENTION_MATCH ",JSON.stringify({"cycle":cycle,"round":screen.run.wave,"stage":screen.run.stage,"health":screen.run.lives,"alive":(screen.run as ArenaTournamentRun).alive_players(),"seconds":(Time.get_ticks_msec()-start)/1000.0}))
		if Time.get_ticks_msec()-start>3600000:
			push_error("Full Trials game did not finish in one hour")
			get_tree().quit(2); return
		await get_tree().process_frame
	census("trials-%d-finished-%s-round-%d" % [cycle,screen.run.stage,screen.run.wave])
	old_worlds.append(weakref(screen.battle.world))
	for board: ArenaPveMatch in screen._tournament_battles.boards.values():
		old_worlds.append(weakref(board.world))
	screen.queue_free()
	await frames_wait(120)
	census("trials-%d-freed" % cycle)

func sample(t: float) -> void:
	super.sample(t)
	census("campaign-%d" % int(t))
