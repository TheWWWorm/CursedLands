extends "arena_equipment_native_visual.gd"
## Native lifesteal/shield triggers plus an explicit visual-event/replay probe.
## The probe freezes AI so all supported feedback can be inspected clearly.
func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1; Engine.max_fps = 30
	GameData.arena_mode = 0
	get_tree().root.mode = Window.MODE_WINDOWED
	get_tree().root.size = Vector2i(1280,720); get_tree().root.position = Vector2i.ZERO
	var run := VisualDuel.new(); var rival := ArenaRun.new()
	company(rival)
	screen = ArenaPveScreen.new(); screen.run = run; add_child(screen)
	await frames(15)
	company(run); run.opposing.assign(rival.army.duplicate(true))
	screen.landing = false; screen._board_key = ""; run._touch()
	battle = screen.battle; battle.formation_motion.settle(battle.world)
	screen.field.zoom = 9.0; screen.field.pan_offset = Vector2(-2,0); screen.field._update_camera()
	await frames(15)
	check(battle.start(), "feedback fixture starts a real battle")
	battle.set_process(false); battle.world.set_process(false); battle.world.set_physics_process(false)
	var own := battle.world.unit_rows().filter(func(u): return u.faction == 1)
	var enemies := battle.world.unit_rows().filter(func(u): return u.faction == 2)
	var effects := battle.world.arena_effects
	var particles := ParticleFx.of(battle.world)
	own[0].hp = own[0].max_hp * 0.4
	var before: float = own[0].hp
	battle.world.combat.melee(own[0], enemies[0], {"hit":true,"backstab":false,"aim":1,"dmg":8.0,"types":PackedFloat32Array([0,0,1,0,0,0,0]),"bs_mul":1.0})
	check(own[0].hp > before and own[0].has_meta("arena_fx_heal"), "native lifesteal creates the original healing spiral")
	own[5].hp = own[5].max_hp * 0.36
	own[5].take_damage(own[5].max_hp * 0.08, enemies[0], -1, PackedFloat32Array(), 0, Callable(), false, {"kind":"attack"})
	check(own[5].has_meta("arena_shield_fx") and effects._shield_left(own[5]) > 0, "native ward creates a persistent protective sphere")
	var shield_state := effects.shield_visual_state()
	var shield: ParticleFx.Effect = own[5].get_meta("arena_shield_fx")
	check(shield.e.type == 0x2016 and shield.until > particles.tick, "shield uses the original lightning-protection particles")
	var heal: ParticleFx.Effect = own[0].get_meta("arena_fx_heal")
	ArenaItemFx.play(particles, {"uid":own[0].uid,"effect":"fang","amount":1.0})
	check(own[0].get_meta("arena_fx_heal") == heal, "rapid lifesteal does not accumulate identical emitters")
	own[3].hp = own[3].max_hp * 0.36
	own[3].take_damage(own[3].max_hp * 0.08, enemies[0], -1, PackedFloat32Array(), 0, Callable(), false, {"kind":"attack"})
	check(own[3].has_meta("arena_shield_fx"), "Guardian protection is visible on an allied creature")
	await frames(18)
	tag = "feedback"
	await shot("lifesteal-shield")
	ArenaItemFx.sync_shields(battle.world, shield_state)
	check(shield.deleted and own[5].has_meta("arena_shield_fx"), "scouting snapshot replaces rather than duplicates shield visuals")
	var hp_before := battle.world.unit_rows().map(func(u): return [u.uid,u.hp,u.stats.duplicate(true)])
	var rng_before := [battle.world.arena_rng.state,battle.world.combat.rng.state]
	# Use the replica event path, including the source actor for the bolt.
	var events: Array[Dictionary] = []
	for index in 6:
		events.append({"t":"arena_proc","effect":["storm","echo","venom","thorn","berserker","marked"][index],"uid":enemies[index].uid,"source":own[index].uid,"amount":1.0})
	battle.apply_effects({"generation":battle.generation,"events":events})
	check(battle.world.unit_rows().map(func(u): return [u.uid,u.hp,u.stats.duplicate(true)]) == hp_before and rng_before == [battle.world.arena_rng.state,battle.world.combat.rng.state], "feedback replay cannot change health, stats or combat RNG")
	check(not particles.bolts.is_empty(), "replicated storm event creates a source-to-target lightning bolt")
	for index in range(1,6):
		check(enemies[index].has_meta("arena_fx_" + ["storm","echo","venom","thorn","berserker","marked"][index]), "replicated effect has its original emitter %d" % index)
	await frames(3); await shot("procs")
	battle.world.time += 5.1; effects.tick()
	check(not own[5].has_meta("arena_shield_fx"), "shield expiry removes the protective sphere")
	# Depletion has a short impact flash, with no persistent protection left.
	effects.rows[own[4].uid].used = true # isolate depletion from the unused nearby Guardian
	effects._shield(own[5], 2.0, "ward")
	own[5].take_damage(3.0, enemies[0], -1, PackedFloat32Array(), 0, Callable(), false, {"kind":"attack"})
	check(not own[5].has_meta("arena_shield_fx") and own[5].has_meta("arena_fx_shield_hit"), "depleted shield ends with an impact flash")
	await frames(15)
	var music_screen := screen
	# Tournament standings are authoritative even if a spectated board won.
	var league := ArenaTournamentRun.new(); league.auto_save = false; league.begin(22)
	music_screen.run = league; league.stage = "won"; league.placements[0] = 3
	music_screen._sync_victory_music()
	check(not music_screen._victory_played, "watching another champion does not play personal victory music")
	league.placements[0] = 1; music_screen._sync_victory_music()
	check(music_screen._victory_played and music_screen._victory_music._cur == "victory", "first place plays the authored victory track")
	music_screen.run = run
	screen.queue_free(); await frames(8)
	OS.remove_logger(errors)
	check(errors.messages.is_empty(), "no runtime errors: " + str(errors.messages))
	print("ARENA_ITEM_FEEDBACK checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
