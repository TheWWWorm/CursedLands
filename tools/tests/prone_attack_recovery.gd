extends "attack_after_action.gd"
## #118: a prone hero can finish a hit/cast immediately before an attack.
## The completed one-shot must not consume the standing transition.

func _ready() -> void:
	var w := GameWorld.new(); add_child(w)
	w.set_process(false); w.set_physics_process(false); w.zone = {"type":"game"}
	var rw := GameWorld.new(); add_child(rw); rw.authority = false
	rw.set_process(false); rw.set_physics_process(false)
	var rendered := DisplayServer.get_name() != "headless"
	if rendered:
		rw.position.x = 2.5
		var camera := Camera3D.new(); add_child(camera)
		camera.position = Vector3(6.25,2.1,-1.5)
		camera.look_at(Vector3(6.25,0.6,-5)); camera.current = true
		var env := WorldEnvironment.new(); add_child(env); env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.13,0.16,0.18)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color.WHITE
		env.environment.ambient_light_energy = 0.7
		var light := DirectionalLight3D.new(); add_child(light)
		light.rotation_degrees = Vector3(-45,-30,0)
	var target := unit(w, Vector3(5.6,5,0)); target.controller = -1; target.faction = 1
	target.hide()
	var traces := []
	for gait in [GameUnit.STANCE_CRAWL, GameUnit.STANCE_KNEEL]:
		for prior in ["idle", "hit", "cast", "attack", "damage"]:
			for direct in [false, true]:
				var u := unit(w, Vector3(5,5,0))
				u.stance = gait; u.action = "idle"; u.alert = false
				u._update_pose(); u.model.player.advance(0)
				var capture: bool = rendered and gait == GameUnit.STANCE_CRAWL and prior == "damage" and not direct
				var replica := unit(rw, Vector3(5,5,0))
				replica.apply_snapshot(u.snapshot(), true)
				var late_replica := unit(rw, Vector3(5,5,0))
				late_replica.apply_snapshot(u.snapshot(), true)
				late_replica.hide()
				u._anim_lock = 0.0; u._attack_cd = 0.0; u.facing = 0.0
				if prior == "damage":
					# Use the real damage path and leave its hit lock running.
					# A deterministic RNG stream makes this a reacting blow.
					for attempt in 16:
						u.take_damage(0.1, target, 1)
						if u.action == "hit": break
					check(u.action == "hit" and u._anim_lock > 0.0, "damage starts a locked prone/kneeling reaction")
				else:
					u.action = prior
					if prior != "idle": u.model.act(prior, 1, 0)
				u.direct_controlled = direct
				replica.apply_snapshot(u.snapshot())
				u.command({"type":"direct_attack", "direction":Vector3.RIGHT} if direct else {"type":"attack", "target":target})
				if capture:
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("user://prone-hit.png")
				var lock_ticks := ceili(u._anim_lock / GameUnit.TICK)
				var host_cross := false; var client_cross := false; var struck := false
				var frames := []
				for tick in 100:
					w.time += GameUnit.TICK
					u.tick(GameUnit.TICK); u._draw_step(GameUnit.TICK); u.anim_flush()
					replica.apply_snapshot(u.snapshot(), false, PackedFloat64Array(), w.time)
					replica._draw_step(GameUnit.TICK); replica.anim_flush()
					host_cross = host_cross or u.model._current.begins_with("ucross")
					client_cross = client_cross or replica.model._current.begins_with("ucross")
					frames.append([tick,u.action,u.model._current,replica.model._current,u.stance,u._anim_lock])
					if prior == "damage" and tick < lock_ticks:
						check(u.model.pose_state == (EIUnitModel.ST_LIE if gait == GameUnit.STANCE_CRAWL else EIUnitModel.ST_WARRY) and u._pending_hit.is_empty(), "queued attack waits for hit recovery")
					if capture:
						await get_tree().process_frame
						await RenderingServer.frame_post_draw
						if tick == lock_ticks + 3 or not u._pending_hit.is_empty():
							get_viewport().get_texture().get_image().save_png("user://prone-attack.png" if not u._pending_hit.is_empty() else "user://prone-rise.png")
					if not u._pending_hit.is_empty(): struck = true; break
					u.model.player.advance(GameUnit.TICK); u.model._process(0)
					replica.model.player.advance(GameUnit.TICK); replica.model._process(0)
				var label := "gait=%d after=%s direct=%s" % [gait,prior,direct]
				check(struck, label + " commits a strike")
				check(host_cross, label + " stands up before striking on authority")
				check(client_cross, label + " shows stand-up on replica")
				check(u.model.pose_state == EIUnitModel.ST_ATTACK, label + " uses standing combat pose")
				# A replica may miss the cross snapshot. The committed attack
				# must still be an attack, not restart the authority's recovery.
				late_replica.apply_snapshot(u.snapshot())
				check(late_replica.action == "attack" and late_replica.model._current == u.model._current, label + " accepts a committed strike after a missed cross")
				traces.append({"case":label,"frames":frames})
				u.hide(); replica.hide(); late_replica.hide()
	w.free(); rw.free()
	FileAccess.open("user://prone-attack-recovery.json",FileAccess.WRITE).store_string(JSON.stringify(traces))
	print("PRONE_ATTACK_RECOVERY ",checks," checks ",failures," failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
