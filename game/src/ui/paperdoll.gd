class_name Paperdoll
extends SubViewportContainer
## The inventory screen's hero figure («Переодевание»: the paperdoll on a
## pedestal in the middle): the hero's own model
## with its current armour and weapons, idling. CampView's painted arrows
## turn it; other previews support dragging. Pedestal = backdrop (CampView).

const SIZE := Vector2i(220, 300)
var view_size := SIZE
## figure at (400,440), UI depth 6, scaled 1.2 about its origin
## with the six depth-clear regions as a screen-space mask.
## No info_scale or altitude; UI camera axes are x right, y down, z forward.
var camp_frame := false
const CAMP_SCALE := 1.2
const CAMP_RECT := Rect2(272, 100, 256, 400)
const CAMP_CLIP := [Rect2(290, 100, 220, 400), Rect2(272, 190, 18, 70),
	Rect2(272, 340, 18, 70), Rect2(510, 190, 18, 20),
	Rect2(510, 290, 18, 20), Rect2(510, 390, 18, 20)]
var camp_angle := 0.0   # signed C fmod; retained when the hero / equipment changes
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
const EXE_K := 0.48157462
const EXE_DEPTH := 9.0
var exe_rect := Rect2()
var exe_px := Vector2(100, 200)

var _key := ""
var _model: EIUnitModel
var _pivot: Node3D
var _cam: Camera3D
var _framed := 0
var _drag := false
## The original poses the figure for every drawn frame: the unit panel re-renders
## the unit's own figure at the current game time (calls the
## object's with the clock, then draws it), the camp screen
## samples timeGetTime. The remake mirrors the unit's pose by copying its part
## transforms (cheap) every frame; phones and the web refresh at 30 Hz.
## Wounds are still compared at 15 Hz.
const POSE_INTERVAL := 1.0 / 15.0
const POSE_INTERVAL_CONSTRAINED := 1.0 / 30.0
var _pose_wait := 0.0
var _wound_wait := 0.0
var _pairs: Array = []   # [source part, preview part] in tree order (parents first)
var _pairs_src: EIUnitModel
var _pose_clip := ""
var _pose_time := -1.0
var _anim_roots: Array[EIAnimPart] = []
var _wound_levels := PackedByteArray()


func _ready() -> void:
	stretch = true
	# These previews are explicitly laid out inside an existing frame. Their
	# render resolution must not force the control to stay 160×220 on a phone.
	custom_minimum_size = Vector2.ZERO if exe_rect.has_area() or camp_frame else Vector2(view_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if camp_frame else Control.MOUSE_FILTER_STOP
	if camp_frame:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://src/ui/paperdoll_clip.gdshader")
		mat.set_shader_parameter("view_rect", Vector4(CAMP_RECT.position.x, CAMP_RECT.position.y,
			CAMP_RECT.size.x, CAMP_RECT.size.y))
		var rects := PackedVector4Array()
		for r: Rect2 in CAMP_CLIP:
			rects.append(Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
		mat.set_shader_parameter("clip_rects", rects)
		material = mat


## Rebuilds only when the look changed (prototype, complexion or equipment).
func show_unit(u: GameUnit) -> void:
	if u != _unit:
		_pose_wait = 0.0
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
	_pose_wait = 0.0
	_pose_clip = ""
	_pose_time = -1.0
	_anim_roots.clear()
	_pairs.clear()
	_pairs_src = null
	_wound_levels.clear()
	for c in get_children():
		c.queue_free()
	var vp := SubViewport.new()
	vp.size = view_size
	vp.own_world_3d = true
	vp.transparent_bg = true
	add_child(vp)
	_model = EIUnitModel.create(info, true)
	if _model == null:
		return
	_pivot = Node3D.new()
	vp.add_child(_pivot)
	_pivot.add_child(_model)
	_model.act("idle")
	for n in _model.get_children():
		if n is EIAnimPart and n.animation_parent == null:
			_anim_roots.append(n)
	if camp_frame or follow_pose:
		_model.set_process(false)
		_model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
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
func _process(dt: float) -> void:
	if _model == null or not _model.is_inside_tree():
		return
	if not is_visible_in_tree():
		_pose_wait = 0.0
		return
	# Every frame on desktop, 30 Hz on phones / web (POSE_INTERVAL_CONSTRAINED).
	# Resume hidden previews with an immediate sample.
	_pose_wait = maxf(0.0, _pose_wait - dt)
	var sample := is_zero_approx(_pose_wait)
	if sample and Portability.constrained():
		_pose_wait = POSE_INTERVAL_CONSTRAINED
	if follow_pose and sample:
		_wound_wait = maxf(0.0, _wound_wait - dt)
		_sync_pose(is_zero_approx(_wound_wait))
		if is_zero_approx(_wound_wait):
			_wound_wait = POSE_INTERVAL
	if camp_frame:
		if _framed == 0:
			_ui_camera(CAMP_RECT)
			_camp_transform()
			_framed = 3
		if sample:
			_sample_camp_pose(Time.get_ticks_msec())
		return
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


func _ui_camera(rect: Rect2) -> void:
	var n := 0.1
	var k := EXE_K * n
	var c := rect.get_center()
	_cam.near = n
	_cam.far = 100.0
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.set_frustum(rect.size.y * 0.0025 * k,
		Vector2((c.x * 0.0025 - 1.0) * k, -(c.y * 0.0025 - 0.75) * k), n, 100.0)
	_cam.transform = Transform3D.IDENTITY


func _exe_frame() -> void:
	_ui_camera(exe_rect)
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


func _camp_transform() -> void:
	if not is_instance_valid(_pivot):
		return
	var to_godot := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))
	var ei_local := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	var rot := Basis(Vector3.UP, camp_angle) * Basis(Vector3.RIGHT, PI * 0.5)
	_pivot.transform = Transform3D((to_godot * rot * ei_local.inverse()).scaled_local(Vector3.ONE * CAMP_SCALE),
		to_godot * Vector3(0.0, 1.0113066, 6.0))


func turn_camp_by(angle: float) -> void:
	# Original mode 1 (left arrow) increases the angle: the front turns left.
	camp_angle = fmod(camp_angle + angle, TAU)
	_camp_transform()


func _sample_camp_pose(clock_ms: float) -> void:
	# The original supplies animation frame time timeGetTime / 1024 * 15.
	# EIAnim stores the original keys at 20 frames/s, so convert to its seconds.
	var length := _model.player.current_animation_length
	if length > 0.0:
		_seek_pose(fmod(clock_ms / 1024.0 * 15.0 / EIAnim.FPS, length))


func _seek_pose(time: float) -> void:
	var clip := String(_model.player.assigned_animation)
	if clip == _pose_clip and time == _pose_time:
		return   # paused / finished source: the displayed pose is already correct
	# Store all animation keys before composing the hierarchy once. Otherwise
	# each written track recursively re-applies its entire subtree.
	var was_batch := EIAnimPart.batch
	if not _anim_roots.is_empty():
		EIAnimPart.batch = true
	_model.player.seek(time, true)
	EIAnimPart.batch = was_batch
	for root in _anim_roots:
		root._apply_key()
	_pose_clip = clip
	_pose_time = time


func _sync_pose(wounds := true) -> void:
	if wounds and is_instance_valid(_unit) and _unit.parts.size() >= 6:   # the unit's wound layers too
		var levels := UnitWounds.levels(_unit)
		if levels != _wound_levels:
			UnitWounds.apply(_model, levels, int(_unit.race.get("type_id", 0)) == 0x32)
			_wound_levels = levels
	if not is_instance_valid(_unit) or _unit.model == null:
		return
	var src: EIUnitModel = _unit.model
	if src != _pairs_src:
		_pairs_src = src
		_pairs.clear()
		var by_name := {}
		for n: Node in src.find_children("*", "EIAnimPart", true, false):
			by_name[n.name] = n
		for n: Node in _model.find_children("*", "EIAnimPart", true, false):
			if by_name.has(n.name):
				_pairs.append([by_name[n.name], n])
	# The unit's figure as posed this frame, part by part in the model's own
	# space (both models are built from the same unit spec).
	var to_src := src.global_transform.affine_inverse()
	var from_dst := _model.global_transform
	for pair: Array in _pairs:
		var a: Node3D = pair[0]
		if not is_instance_valid(a):
			_pairs_src = null
			return
		(pair[1] as Node3D).global_transform = from_dst * (to_src * a.global_transform)


## Radians around Godot's up axis; CampView supplies the original held-arrow rate.
func turn_by(angle: float) -> void:
	if is_instance_valid(_pivot):
		_pivot.rotate_y(angle)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		turn_by(e.relative.x * 0.01)
