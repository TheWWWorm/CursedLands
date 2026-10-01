class_name Paperdoll
extends SubViewportContainer
## The inventory screen's hero figure («Переодевание»: the paperdoll on a
## pedestal in the middle, docs/original_reference.md): the hero's own model
## with its current armour and weapons, idling. Drag or hold CampView's
## painted arrows to turn it. Pedestal = backdrop (CampView).
## The original camp figure's placement and camera are not reproduced.

const SIZE := Vector2i(220, 300)
var view_size := SIZE
## Framing: view height / figure height, and the figure's centre offset down
## the view (fraction of the view height).
var frame_scale := 1.15
var frame_drop := 0.0
## Mirror the unit's in-world animation (clip and time) instead of idling:
## the original's unit panel re-renders the unit's own figure object.
var follow_pose := false
var fov := 30.0
## Camera height above the framed centre (fraction of the figure height).
var eye_lift := 0.0
var _unit: GameUnit
var _info := {}
## the original unit-panel camera, used when exe_rect has an area:
## the view shows exe_rect of the 800x600 virtual screen through the original's
## pixel -> camera mapping (: x = (px/400 - 1)*K*z
## y_down = (py/400 - 0.75)*K*z, K = 0.481575); the figure stands at virtual
## pixel exe_px, depth EXE_DEPTH, turned by the fixed quaternions (EI camera space: x right,
## y down, z forward), scaled 1 / info_scale and lowered by altitude / info_scale.
const EXE_K := 0.481575
const EXE_DEPTH := 9.0
var exe_rect := Rect2()
var exe_px := Vector2(100, 200)

var _key := ""
var _model: EIUnitModel
var _pivot: Node3D
var _cam: Camera3D
var _framed := 0
var _drag := false


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(view_size)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Rebuilds only when the look changed (prototype, complexion or equipment).
func show_unit(u: GameUnit) -> void:
	_unit = u
	show_info(u.info)


## Same for a bare unit spec (prototype, complexion, armors, weapons).
func show_info(info: Dictionary) -> void:
	var key := "%s|%s|%s|%s" % [info.get("prototype", ""), info.get("complexion", ""),
		info.get("armors", []), info.get("weapons", [])]
	if key == _key:
		return
	_key = key
	_info = info
	for c in get_children():
		c.queue_free()
	var vp := SubViewport.new()
	vp.size = view_size
	vp.own_world_3d = true
	vp.transparent_bg = true
	add_child(vp)
	_model = EIUnitModel.create(info)
	if _model == null:
		return
	_pivot = Node3D.new()
	vp.add_child(_pivot)
	_pivot.add_child(_model)
	_model.act("idle")
	_cam = Camera3D.new()
	_cam.fov = fov
	vp.add_child(_cam)
	vp.msaa_3d = Viewport.MSAA_4X
	# Lit like the game world (the original draws the preview figure with the
	# scene's sun): a key light from the upper front-left.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, -35, 0)
	light.light_energy = 1.25
	vp.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.42, 0.42, 0.45)
	vp.add_child(env)
	_framed = 0
	set_process(true)


## Frames the whole figure once the idle pose has applied (models face
## Godot +Z).
func _process(_dt: float) -> void:
	if _model == null or not _model.is_inside_tree():
		return
	if follow_pose:
		_sync_pose()
	if exe_rect.has_area():
		if _framed == 0:
			_exe_frame()
			_framed = 3
		if not follow_pose:
			set_process(false)
		return
	if _framed >= 3:
		return
	_framed += 1
	if _framed < 3:
		return
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var c := box.get_center()
	var dist := box.size.y * 0.5 / tan(deg_to_rad(_cam.fov) * 0.5) * frame_scale
	c.y += box.size.y * frame_scale * frame_drop
	_cam.position = Vector3(c.x, c.y + box.size.y * eye_lift, c.z + dist)
	_cam.look_at(c)
	if not follow_pose:
		set_process(false)


func _exe_frame() -> void:
	var n := 0.1
	var k := EXE_K * n
	var c := exe_rect.get_center()
	_cam.near = n
	_cam.far = 100.0
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.set_frustum(exe_rect.size.y * 0.0025 * k,
		Vector2((c.x * 0.0025 - 1.0) * k, -(c.y * 0.0025 - 0.75) * k), n, 100.0)
	_cam.transform = Transform3D.IDENTITY
	var proto := GameData.db.find("monster_prototypes", str(_info.get("prototype", "")))
	# panel = prototype (info_scale), =
	# (altitude); multiplies info_scale by the.adb height ratio
	# the unit's two complexion copies, equal unless reshaped.
	var b := float(proto.get("info_scale", 1.0))
	if b == 0.0:
		b = 1.0
	var a := float(proto.get("altitude", 0.0))
	var x := (exe_px.x * 0.0025 - 1.0) * EXE_K * EXE_DEPTH
	var y := (exe_px.y * 0.0025 - 0.75) * EXE_K * EXE_DEPTH + a / b
	# EI camera space (x right, y down, z forward) -> Godot camera (y up, -z).
	var to_godot := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))
	# Model local space is EI local mapped by EISpace (x, z, -y).
	var ei_local := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	#  = pi / 2: quaternions (0,0,1) x 0.05, (1,0,0) x 1.15
	# (0,0,1) x 0.4 of it, multiplied in that order.
	var h := PI * 0.5
	var rot := Basis(Vector3(0, 0, 1), h * 0.05) * Basis(Vector3(1, 0, 0), h * 1.15) \
		* Basis(Vector3(0, 0, 1), h * 0.4)
	_pivot.transform = Transform3D((to_godot * rot * ei_local.inverse()).scaled_local(Vector3.ONE / b),
		to_godot * Vector3(x, y, EXE_DEPTH))


func _sync_pose() -> void:
	if is_instance_valid(_unit) and _unit.parts.size() >= 6:   # the unit's wound layers too
		UnitWounds.apply(_model, UnitWounds.levels(_unit), int(_unit.race.get("type_id", 0)) == 0x32)
	if not is_instance_valid(_unit) or _unit.model == null or _unit.model.player == null or _model.player == null:
		return
	var src: EIUnitModel = _unit.model
	var key := src.player.assigned_animation
	if key.is_empty() or not _model.player.has_animation(key):
		return
	var clip := key.trim_prefix("ei/")
	if clip != _model._current:
		_model.play(clip, 0.0)
	if _model.player.assigned_animation == key:
		_model.player.seek(src.player.current_animation_position, true)
		_model.player.pause()


## Radians around Godot's up axis; CampView supplies the original held-arrow rate.
func turn_by(angle: float) -> void:
	if is_instance_valid(_pivot):
		_pivot.rotate_y(angle)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		turn_by(e.relative.x * 0.01)
