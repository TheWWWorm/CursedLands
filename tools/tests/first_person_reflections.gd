extends Node
## Native figure rendered through the production mirror transform and mask.
const Reflection := preload("res://src/game/fx/water_reflection.gd")
var checks := 0
var failures: Array[String] = []
var rows := []
var view: SubViewport
var mirror: Camera3D
# Keep temporary overrides alive until both viewports release their geometry.
var materials: Array[Material] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)

func frames(n := 3) -> void:
	for i in n: await RenderingServer.frame_post_draw

func picture() -> Image:
	await frames()
	return view.get_texture().get_image()

func difference(a: Image, b: Image) -> int:
	var changed := 0
	for y in a.get_height():
		for x in a.get_width():
			var delta := a.get_pixel(x,y) - b.get_pixel(x,y)
			if absf(delta.r) + absf(delta.g) + absf(delta.b) + absf(delta.a) > 0.05: changed += 1
	return changed

func _ready() -> void:
	check(Reflection.supported(), "uses rendered Forward+ reflection path")
	if not Reflection.supported(): get_tree().quit(1); return
	var terrain_layers := EITerrain.SHADOW_RECEIVER_LAYER | EITerrain.DECAL_LAYER | Reflection.WATER_LAYER | GameUnit.OFFSCREEN_LAYER
	check(((EIUnitModel.CLOSE_VIEW_LAYER | EIUnitModel.REFLECTION_LAYER) & terrain_layers) == 0,"character view layers do not overlap terrain, decals, water or distant units")
	await frames(16)
	var rig := CameraRig.new(); add_child(rig); rig.set_process(false)
	check((rig.camera.cull_mask & EIUnitModel.REFLECTION_LAYER) == 0, "main game camera excludes complete reflection copies")
	check((Reflection.reflection_mask(rig.camera.cull_mask) & EIUnitModel.CLOSE_VIEW_LAYER) == 0, "mirror excludes the camera-adjusted body")
	view = SubViewport.new()
	view.size = Vector2i(480,480); view.world_3d = get_viewport().world_3d
	view.transparent_bg = true; view.gui_disable_input = true
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	mirror = Camera3D.new(); view.add_child(mirror)
	var source := Transform3D(Basis.IDENTITY, Vector3(0,2,4.5)).looking_at(Vector3(0,-1,0))
	mirror.global_transform = Reflection.reflected_transform(source,0.0)
	mirror.cull_mask = Reflection.reflection_mask(rig.camera.cull_mask)
	mirror.fov = 50.0; mirror.current = true
	for smooth: bool in [false,true]:
		var model := EIUnitModel.create({"prototype":"Human Hero", "complexion":Vector3(.5,.5,.5), "smooth_joints":smooth})
		add_child(model); model.set_process(false)
		model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if mesh.material_override: materials.append(mesh.material_override)
			for surface in mesh.mesh.get_surface_count():
				var original := mesh.get_active_material(surface) as ShaderMaterial
				if original: materials.append(original)
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_texture = original.get_shader_parameter("albedo_tex") if original else null
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mesh.set_surface_override_material(surface,mat)
				materials.append(mat)
			mesh.material_override = null
		for action: String in ["idle","run","attack","cast"]:
			model.set_first_person_view(false)
			model.act(action,1,0.0)
			var clip := model.player.get_animation("ei/" + model._current)
			model.player.seek(clip.length * 0.4,true)
			var reference := await picture()
			model.set_part_visible("hd",false)
			var without_head := await picture()
			model.set_part_visible("hd",true)
			model.set_first_person_view(true)
			model.align_first_person_body(Vector3(.2,1.7,.1),Vector3.RIGHT)
			model._update_first_person_shadows()
			var reflected := await picture()
			var label := "%s smooth=%s" % [action,smooth]
			var head_pixels := difference(reference,without_head)
			var wrong := difference(reference,reflected)
			check(head_pixels > 20,label + " reference contains a visible head/face")
			check(wrong < 10,label + " first-person mirror matches the complete original figure")
			check(not model._head.is_visible_in_tree(),label + " local camera still hides the real head")
			# Shadow quality changes must not hide a physical reflection.
			for row: Dictionary in model._view_shadows:
				model.apply_view_shadow_option(row.source,false)
				model.apply_view_shadow_option(row.shadow,false)
				model.apply_view_shadow_option(row.reflection,false)
			model._update_first_person_shadows()
			check(difference(reference,await picture()) < 10,label + " mirror remains intact with shadows disabled")
			model.set_part_visible("hd",false); model._update_first_person_shadows()
			check(difference(without_head,await picture()) < 10,label + " severed head is absent from the reflection")
			model.set_part_visible("hd",true)
			for row: Dictionary in model._view_shadows:
				model.apply_view_layer_option(row.source,1)
			model._update_first_person_shadows()
			check(model._view_shadows.all(func(row): return row.source.layers == EIUnitModel.CLOSE_VIEW_LAYER and row.reflection.layers == EIUnitModel.REFLECTION_LAYER),label + " screen visibility updates retain separate camera layers")
			model.set_first_person_view(false)
			check(model._view_shadows.all(func(row): return row.source.layers == 1 and not row.reflection.visible),label + " leaving first person restores ordinary geometry and layers")
			rows.append({"case":label,"head_pixels":head_pixels,"wrong_pixels":wrong})
			if action == "idle": reflected.save_png("user://first-person-reflection-smooth-%s.png" % smooth)
		model.hide()
		await frames()
		model.queue_free()
		await frames()
	rig.free(); view.free(); await frames()
	materials.clear()
	print("FIRST_PERSON_REFLECTIONS ",JSON.stringify({"checks":checks,"failures":failures,"rows":rows}))
	TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
