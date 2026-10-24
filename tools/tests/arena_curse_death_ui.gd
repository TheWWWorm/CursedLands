extends "arena_expansion_ui.gd"
## Observe the authored death cycle toppling and settling onto rendered snow.
func _ready() -> void:
	OS.add_logger(errors); await frames(24)
	GameData._window_gen += 1; GameData.arena_mode = 0
	get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1280,720)
	screen=ArenaPveScreen.new();add_child(screen);await frames(12)
	Engine.max_fps=30
	screen._begin();screen.run.auto_save=false
	var family := -1
	for index in ArenaRules.FAMILIES.size():
		if ArenaRules.FAMILIES[index].name == "Horrors": family=index
	var entry := screen.run._recruit(family,0,5)
	entry.deployed=true;entry.point=[31.0,31.0];screen.run._touch()
	await frames(40)
	while ShaderCompilationScreen.active(): await frames(2)
	var horror:=body(int(entry.uid))
	check(horror!=null,"Horror is present on the rendered board")
	screen._hud.hide()
	var center := horror.global_position + Vector3(0,1,0)
	screen.field.camera.position=center+Vector3(4,4,7)
	screen.field.camera.look_at(center)
	screen.field.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	screen.field.camera.size=6
	await shot("curse-alive")
	screen.battle.formation_motion.clear();screen.battle.phase=ArenaMatch.Phase.FINISHED
	screen.battle.world.set_process(false);screen.battle.world.set_physics_process(false)
	screen.run.stage="fight"
	var initial:=ArenaPveMatch._corpse_bounds(horror).get_center().y
	var living_basis := horror.model.basis
	horror.hp=0;horror.die()
	await shot("curse-falling")
	await get_tree().create_timer(1.1).timeout
	check(horror.is_frozen() and ArenaPveMatch._corpse_bounds(horror).get_center().y<initial-0.5,"corpse descends and settles")
	check(absf(ArenaPveMatch._corpse_clearance(horror))<0.001,"final visible vertices touch the ground")
	check(absf(horror.model.basis.y.normalized().dot(living_basis.y.normalized())) < 0.001,"corpse has toppled onto the snow")
	await shot("curse-landed")
	screen.run.stage="prepare";screen.queue_free();screen=null;await frames(6)
	check(errors.messages.is_empty(),"no new rendering or script errors")
	print("ARENA_CURSE_DEATH_UI ",checks," failures=",failures)
	OS.remove_logger(errors);TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
