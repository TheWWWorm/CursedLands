extends "arena_species_ui.gd"
## Render actual friendly/enemy dragon and cyclops figure replacements.
func _ready() -> void:
	OS.add_logger(errors); await frames(8)
	GameData._window_gen += 1; GameData.arena_mode = 1
	GameData.options.merge(GfxPresets.values(GfxPresets.ORIGINAL),true)
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"autosave":0,"net_directory":0,"net_upnp":0},true)
	GameData.options.merge({"gfx_hd_textures":0,"gfx_sharp_units":0,"gfx_materials":0,"q_aa":0,"q_shadows":0},true)
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(1280,800)
	screen = ArenaPveScreen.new(); add_child(screen); await frames(8)
	screen._seed_input.text = "7191"; screen._begin(); screen.run.auto_save = false
	await wait_models()
	screen.set_process(false); screen.battle.set_process(false)
	screen.battle.world.set_process(false); screen.battle.world.set_physics_process(false)
	screen.battle.formation_motion.clear()
	for unit: GameUnit in screen.battle.world.unit_rows(): screen.battle.world.remove_unit(unit)
	var actors: Array[GameUnit] = []
	var sizes: Array[Vector3] = []
	var heights: Array[float] = []
	for team in 2:
		for family in [23,27]:
			var actor := screen.battle._spawn({"id":ArenaRules.prototype(family,2),"team":team,"family":family,"rank":2,"point":Vector2(25+team*14,27 if family==23 else 37)})
			actors.append(actor); sizes.append(actor.model.scale); heights.append(actor.model.height_k)
			check(actor.model.scale.x < 1.0,"rendered large creature is fitted %d:%d" % [team,family])
	screen._round_banner._age = 10; screen._hide_inspector(); screen._clear_selection()
	await shot("scale-before-refresh")
	for index in actors.size():
		var actor := actors[index]
		actor.refresh_figure(true)
		check(actor.model.scale.is_equal_approx(sizes[index]),"rendered replacement keeps fitted size %d" % index)
		actor.buffs.strength = {"until":20.0}; actor.refresh_figure()
		var strength_height := actor.model.height_k
		var snapshot := actor.snapshot()
		actor.buffs.clear(); actor.refresh_figure(); actor.apply_snapshot(snapshot,true)
		check(actor.model.scale.is_equal_approx(sizes[index]) and is_equal_approx(actor.model.height_k,strength_height),"rendered body snapshot keeps fit and gait %d" % index)
		actor.buffs.clear(); actor.refresh_figure()
		check(actor.model.scale.is_equal_approx(sizes[index]) and is_equal_approx(actor.model.height_k,heights[index]),"rendered effect expiry keeps fitted size and gait %d" % index)
	await shot("scale-after-refresh")
	check(errors.messages.is_empty(),"no rendered diagnostics: "+str(errors.messages))
	if screen._tournament_battles is ArenaSoloBattles:
		var solo := screen._tournament_battles as ArenaSoloBattles
		if is_instance_valid(solo.connection): solo.connection.close()
	screen.queue_free(); screen = null; await frames(8)
	check(errors.messages.is_empty(),"clean preview teardown: "+str(errors.messages))
	print("ARENA_SCALE_PRESERVATION_UI ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
