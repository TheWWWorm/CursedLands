extends Node3D
## Map viewer: pick an island, look around, inspect the level script.

var _rig: CameraRig
var _map: EIMapScene
var _picker: OptionButton
var _stats: Label
var _script_view: TextEdit
var _objects_toggle: CheckBox
var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else true
	_setup_world()
	_setup_ui()
	var names := GameData.map_names()
	var start: String = _args.get("map", "bz2g" if "bz2g" in names else names[0])
	for n in names:
		_picker.add_item(n)
		if n == start:
			_picker.select(_picker.item_count - 1)
	await _load(start)
	if _args.has("info"):
		print(JSON.stringify(_map.stats if _map else {"error": "load failed"}))
		print("script chars: ", _map.mob.script_text.length() if _map and _map.mob else 0)
		get_tree().quit()
	elif _args.has("screenshot"):
		if _args.has("yaw"):
			_rig.yaw = deg_to_rad(float(_args.yaw))
		if _args.has("dist"):
			_rig.distance = float(_args.dist)
		if _args.has("focus"):
			var f: PackedStringArray = String(_args.focus).split(",")
			_rig.focus(EISpace.pos(float(f[0]), float(f[1]), 0))
		_rig._apply()
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_args.screenshot)
		get_tree().quit()


func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.5, 0.75)
	sky_mat.sky_horizon_color = Color(0.75, 0.78, 0.8)
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.75, 0.8)
	env.fog_density = 0.002
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)
	_rig = CameraRig.new()
	add_child(_rig)


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(10, 10)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var lbl := Label.new()
	lbl.text = "Map:"
	row.add_child(lbl)
	_picker = OptionButton.new()
	_picker.item_selected.connect(func(i: int): _load(_picker.get_item_text(i)))
	row.add_child(_picker)
	_objects_toggle = CheckBox.new()
	_objects_toggle.text = "Objects"
	_objects_toggle.button_pressed = true
	_objects_toggle.toggled.connect(func(on: bool):
		if _map and _map.has_node("Objects"):
			_map.get_node("Objects").visible = on)
	row.add_child(_objects_toggle)
	var script_btn := Button.new()
	script_btn.text = "Level script"
	script_btn.pressed.connect(func(): _script_view.visible = not _script_view.visible)
	row.add_child(script_btn)
	_stats = Label.new()
	box.add_child(_stats)
	var help := Label.new()
	help.text = "WASD pan · Q/E or right-drag rotate · wheel zoom · Shift fast"
	help.modulate = Color(1, 1, 1, 0.6)
	box.add_child(help)

	_script_view = TextEdit.new()
	_script_view.editable = false
	_script_view.visible = false
	_script_view.anchor_left = 0.5
	_script_view.anchor_right = 1.0
	_script_view.anchor_bottom = 1.0
	_script_view.offset_left = 0
	_script_view.offset_top = 10
	_script_view.offset_right = -10
	_script_view.offset_bottom = -10
	layer.add_child(_script_view)


func _load(map_name: String) -> void:
	_stats.text = "Loading %s..." % map_name
	await get_tree().process_frame
	await get_tree().process_frame
	if _map:
		_map.queue_free()
		_map = null
	var m := EIMapScene.load_map(map_name)
	if m == null:
		_stats.text = "Failed to load %s" % map_name
		return
	_map = m
	add_child(m)
	if m.has_node("Objects"):
		m.get_node("Objects").visible = _objects_toggle.button_pressed
	_rig.terrain = m.terrain
	var s := m.terrain.size_ei()
	_rig.focus(EISpace.pos(s.x * 0.5, s.y * 0.5, 0))
	var st := m.stats
	_stats.text = "%s: %dx%d sectors, %d/%d objects placed, terrain %d ms, objects %d ms" % [
		map_name, m.terrain.sectors_x, m.terrain.sectors_y, st.get("placed", 0), st.get("objects", 0),
		st.terrain_ms, st.objects_ms]
	if st.get("missing_models", []).size():
		_stats.text += "\nmissing models: %s" % ", ".join(st.missing_models.slice(0, 8))
	_script_view.text = m.mob.script_text if m.mob else "(no .mob)"
