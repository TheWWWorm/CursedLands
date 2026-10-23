extends Node
## Native atlas placement, actor ownership, body/speech lifetimes and both
## material paths, using installed original data. Render a 2×2 face plate
## when run with a display (closed/open columns; body/portrait head rows).
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func prototype(mask: String, skin := -1) -> String:
	for p: Dictionary in GameData.db.table("monster_prototypes"):
		var r := GameData.db.find("race_models", p.base_race)
		if String(r.get("mask", "")).to_lower() == mask and (skin < 0 or int(p.skin) == skin): return p.name
	return ""

func body_mesh(model: EIUnitModel) -> MeshInstance3D:
	for node in model._head.get_children():
		if node is MeshInstance3D and not node.has_meta("detailed_head"): return node
	return null

func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0}, true)
	var human := prototype("unhuma", 3)
	check(not human.is_empty(), "original skin 03 actor exists")
	for fixture in [["unhuma",3],["unhufe",0],["unorma",2],["unmodr",-1],["unmogo",-1],["unmoli",-1],["unmori",-1]]:
		var name := prototype(fixture[0], fixture[1])
		var model := EIUnitModel.create({"prototype":name,"armors":PackedStringArray(),"weapons":PackedStringArray()}, true)
		check(model != null, "%s original model loads" % fixture[0])
		if model == null: continue
		add_child(model)
		model.set_process(false)
		model.begin_dialogue(true, 1)
		check(model._mouth != null, "%s authored mouth loads" % fixture[0])
		if model._mouth:
			var mouth = model._mouth
			check(mouth.body_rect.has_area() and mouth.frame_size.y <= .5, "%s valid race rectangle and padded source strips" % fixture[0])
			var mesh := body_mesh(model)
			var mat = mesh.material_override
			var base: Texture2D = mat.albedo_texture
			var wound := ImageTexture.create_from_image(Image.create(1,1,false,Image.FORMAT_RGBA8))
			mat.wound_texture = wound
			mouth.advance(.055)
			check(mouth.opened and mouth.remaining >= .165 and mouth.remaining <= .55, "%s native randomized lip cadence" % fixture[0])
			check(mat.get_shader_parameter("mouth_enabled") and mat.get_shader_parameter("mouth_open"), "%s shader opens mouth" % fixture[0])
			var open_texture: Texture2D = mat.get_shader_parameter("mouth_open_tex")
			var closed_texture: Texture2D = mat.get_shader_parameter("mouth_closed_tex")
			check(open_texture.get_size() == base.get_size() and closed_texture.get_size() == base.get_size() and open_texture.get_image().has_mipmaps() and closed_texture.get_image().has_mipmaps(), "%s filters complete skin frames without adjacent strip bleed" % fixture[0])
			check(mat.albedo_texture == base and mat.wound_texture == wound, "%s preserves skin and independent wounds" % fixture[0])
			if model._dialogue_active:
				model.player.advance(100.0)
				model._process(0.0)
				check(model._speaking and mouth.speaking, "%s body-special completion does not end speech" % fixture[0])
			model.begin_dialogue(true, 1, false)
			check(not mouth.speaking and not mat.get_shader_parameter("mouth_enabled"), "%s #nolips keeps mouth closed" % fixture[0])
			model.begin_dialogue(true, 1)
			model.end_dialogue()
			check(not model._speaking and not mouth.speaking, "%s dialogue cleanup closes lips" % fixture[0])
		model.free()
	var first := EIUnitModel.create({"prototype":human,"armors":PackedStringArray(),"weapons":PackedStringArray()}, true)
	var second := EIUnitModel.create({"prototype":human,"armors":PackedStringArray(),"weapons":PackedStringArray()}, true)
	add_child(first); add_child(second)
	first.begin_dialogue(true,1)
	first._mouth.advance(.055)
	check(second._mouth == null and not second._speaking, "identical nearby actor does not inherit speech")
	if first._detail and second._detail:
		check(first._detail.material_override != second._detail.material_override, "portrait head owns its per-actor mouth material")
		check(not second._detail.material_override.get_shader_parameter("mouth_enabled"), "cached portrait material stays silent")
	var mesh := body_mesh(first)
	var standard := StandardMaterial3D.new()
	standard.albedo_texture = mesh.material_override.albedo_texture
	var skin := standard.albedo_texture
	mesh.material_override = standard
	first._mouth.apply()
	check(standard.albedo_texture != skin, "custom StandardMaterial3D receives mouth composite")
	var changed := standard.albedo_texture.get_image()
	var original := skin.get_image()
	check(changed.get_pixel(1,1) == original.get_pixel(1,1), "fallback leaves pixels outside native mouth rectangle unchanged")
	var different := 0
	for y in range(84,100):
		for x in range(56,88):
			if changed.get_pixel(x,y) != original.get_pixel(x,y): different += 1
	if DisplayServer.get_name() != "headless":
		check(different > 50, "fallback changes the actual lip region")
	first.end_dialogue()
	check(standard.albedo_texture == skin, "fallback cleanup restores its original skin")
	first.free(); second.free()
	# The in-world rebuild path must carry the same lip phase as the body.
	var world := GameWorld.new(); add_child(world)
	world.set_process(false); world.set_physics_process(false)
	var unit := world.spawn_unit({"nid":1,"prototype":human,"position":Vector3(1,1,0),"armors":PackedStringArray(),"weapons":PackedStringArray()})
	unit.set_process(false); unit.set_physics_process(false)
	var listener := world.spawn_unit({"nid":2,"prototype":human,"position":Vector3(2,1,0),"armors":PackedStringArray(),"weapons":PackedStringArray()})
	listener.set_process(false); listener.set_physics_process(false)
	var marks := OrderMarks.new()
	marks._lighten(unit.model,true); marks._lighten(listener.model,true)
	unit.model.begin_dialogue(true,1); unit.model._mouth.advance(.055)
	marks._lighten(unit.model,true)
	if unit.model._detail and listener.model._detail:
		check(unit.model._detail.get_meta("unlit") != listener.model._detail.get_meta("unlit"), "preselected identical portraits retain separate unlit materials")
		check(not listener.model._detail.material_override.get_shader_parameter("mouth_enabled") and not listener.model._detail.get_meta("unlit").get_shader_parameter("mouth_enabled"), "preexisting highlight cannot leak speech to listener")
	UnitWounds.apply(unit.model,PackedByteArray([1,0,0,0,0,0]),true)
	UnitWounds.flush()
	marks._lighten(unit.model,true)
	var head := body_mesh(unit.model)
	check(head.material_override.wound_texture != null and head.material_override.wound_texture == head.get_meta("unlit").wound_texture, "async wounds stay on current and original highlighted material")
	check(head.material_override.get_shader_parameter("mouth_enabled") and head.material_override.get_shader_parameter("mouth_open"), "wound completion preserves speaking shader state")
	marks._lighten(unit.model,false)
	check(head.material_override.get_shader_parameter("mouth_enabled") and head.material_override.get_shader_parameter("mouth_open"), "removing selection preserves speaker phase")
	var remaining: float = unit.model._mouth.remaining
	unit.set_equipment(PackedStringArray(), PackedStringArray(["battle axe.adamantium"]))
	check(unit.model._speaking and unit.model._mouth.opened and is_equal_approx(unit.model._mouth.remaining,remaining), "redress preserves speaking mouth and phase")
	unit.model.act("death")
	check(not unit.model._speaking and not unit.model._mouth.speaking, "death clears speaking lips")
	# Exercise the actual panel's actor routing and last-line timeout with
	# real actors; no invented replacement speech controller in the test.
	var game := Game.new(); game.world = world
	var hud := GameHUD.new(); hud.game = game
	var panel := DialogPanel.new(); panel.hud = hud
	panel._cast = {"names":{"speaker":unit.uid,"listener":listener.uid}}
	panel._pose_actors({"actor":"speaker"})
	check(unit.model._speaking and not listener.model._speaking, "panel routes lips only to named speaker")
	panel._pose_actors({"actor":"speaker","nolips":true})
	check(not unit.model._speaking, "panel honors authored #nolips")
	panel._pose_actors({"actor":"speaker"},true)
	check(not unit.model._speaking and not listener.model._speaking, "skipped dialogue leaves actors silent")
	panel._pose_actors({"actor":"speaker"})
	panel._mode = DialogPanel.LAST; panel._timer = .01; panel.visible = true
	panel._process(.02)
	check(not unit.model._speaking, "last unvoiced phrase stops lips when its text duration ends")
	panel._pose_actors({"actor":"speaker"})
	panel._mode = DialogPanel.LAST; panel._voiced = true
	panel._process(.02)
	check(not unit.model._speaking, "last voiced phrase stops lips when playback ends")
	panel._end_actor_poses()
	check(not unit.model._dialogue_active and not listener.model._dialogue_active, "panel close releases all dialogue states")
	panel.free(); hud.free(); game.free(); marks.free()
	world.free()
	if DisplayServer.get_name() != "headless":
		for preview in [true,false]: await render_faces(human, preview)
	print("DIALOGUE_MOUTHS ", JSON.stringify({"checks":checks,"failures":failures}))
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)

func render_faces(human: String, preview: bool) -> void:
	get_window().size = Vector2i(1024,1024)
	var containers: Array[SubViewportContainer] = []
	for detail in [false,true]:
		for opened in [false,true]:
			var container := SubViewportContainer.new()
			container.position = Vector2(512 * int(opened), 512 * int(detail))
			container.size = Vector2(512,512)
			add_child(container)
			containers.append(container)
			var view := SubViewport.new(); view.size = Vector2i(512,512); view.own_world_3d = true
			container.add_child(view)
			var model := EIUnitModel.create({"prototype":human,"armors":PackedStringArray(),"weapons":PackedStringArray()}, preview)
			view.add_child(model)
			model.set_process(false)
			model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			model.player.seek(0.0,true)
			model.set_detailed_head(detail)
			model.set_speaking(true)
			model._mouth.opened = opened; model._mouth.apply()
			var env := WorldEnvironment.new(); env.environment = Environment.new()
			env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(.08,.1,.12)
			env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = .7
			view.add_child(env)
			var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-25,-25,0); view.add_child(light)
			var camera := Camera3D.new(); view.add_child(camera)
			var mesh := body_mesh(model)
			var center := mesh.to_global(mesh.mesh.get_aabb().get_center())
			camera.position = center + Vector3(0,.02,.9)
			camera.look_at(center)
			camera.fov = 28.0
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "user://dialogue-mouths-%s.png" % ("preview" if preview else "world")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "rendered original and portrait head plate")
	print("DIALOGUE_MOUTH_IMAGE ", ProjectSettings.globalize_path(path))
	for container in containers: container.queue_free()
	await get_tree().process_frame
