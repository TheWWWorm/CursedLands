class_name Portrait
extends SubViewportContainer
## A party member's face in a small viewport, as the original draws it
## the interface face model
## "infa<model><th|me|fa><hair + 1>face" from figures.res with the texture
## "face<m|f><skin, 2 digits>". <model> is the race model (unhuma / unhufe),
## th / me / fa follow the figure's second complexion value, the fat axis
## (the remake's complexion x; < 0.2 thin, > 0.8 fat). The
## face texture sits in a 256 atlas cell whose V starts at 0.5, so the model's
## UVs map to the 128 texture as (2u, 2v - 1). The model is seen from its +Y
## (EI) side. Units without a face model fall back to their own model's head.

const SIZE := Vector2i(64, 64)
var view_size := SIZE

var _key := ""
var _model: Node3D
var _cam: Camera3D
var _framed := 0
# Expressions: the face texture gets suffix
# "c" for 2 s when health drops, "a" for 4 s on kill ack 0x30, otherwise
# "b" below 25 % stamina. The independent 1 s red flash uses trunc(t * 200).
var _unit: GameUnit
var _mats: Array[StandardMaterial3D] = []
var _tex := ""
var _expr := -1
var _expression := ""
var _expression_t := 0.0
var _flash_t := 0.0
var _last_hp := -1.0
var _flash: ColorRect
var selected := false
var _head_motion := 0   # 1 nod, 2 shake, 3 idle look
var _motion_t := 0.0
var _look_q := Quaternion.IDENTITY
var _look_speed := 1.0
var _selection_q := Quaternion.IDENTITY
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## Rebuilds only when the unit's look changed (equipment swap).
func show_unit(u: GameUnit) -> void:
	if u != _unit:
		_expression = ""
		_expression_t = 0.0
		_flash_t = 0.0
		_last_hp = u.hp
		_head_motion = 0
		_selection_q = Quaternion.IDENTITY
	_unit = u
	var key := "%s|%s|%s|%s|%s" % [u.get_instance_id(), u.info.get("prototype", ""),
		u.info.get("complexion", Vector3.ZERO), u.info.get("armors", []), u.info.get("weapons", [])]
	if key == _key:
		return
	_key = key
	for c in get_children():
		c.queue_free()
	_mats.clear()
	_model = null
	_flash = null
	stretch = true
	custom_minimum_size = Vector2.ZERO
	var vp := SubViewport.new()
	vp.size = view_size
	vp.own_world_3d = true
	vp.transparent_bg = true
	add_child(vp)
	if _infa_face(vp, u):
		return
	var info: Dictionary = u.info.duplicate()
	info.weld = false   # the head needs its own mesh here
	var m := EIUnitModel.create(info, true)
	if m == null:
		return
	vp.add_child(m)
	m.act("idle")
	_model = m
	_cam = Camera3D.new()
	_cam.fov = 30.0
	vp.add_child(_cam)
	_framed = 0
	set_process(true)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, 20, 0)
	vp.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	vp.add_child(env)


## Frames the head once the posed model is in the tree: the top of its
## bounds, seen from the front (models face EI -Y, which is Godot +Z).
func _process(dt: float) -> void:
	if not _mats.is_empty():
		if get_tree().paused:
			dt = 0.0   #  uses zero UI delta while paused.
		_update_expression(dt)
		_update_head(dt)
		return
	if _model == null or not _model.is_inside_tree():
		return
	_framed += 1
	if _framed < 2:
		return   # let the idle pose apply first
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var top := box.position.y + box.size.y
	var h := box.size.y * 0.2
	var c := Vector3(box.get_center().x, top - h * 0.5, box.get_center().z)
	# Centre on the head part when the model has one ("hd").
	var head := _model.find_child("hd", true, false) as Node3D
	if head:
		var hb := AABB()
		var got := false
		for mi: MeshInstance3D in head.find_children("*", "MeshInstance3D", false, false):
			var b: AABB = mi.global_transform * mi.get_aabb()
			hb = b if not got else hb.merge(b)
			got = true
		if got:
			c = Vector3(hb.get_center().x, hb.position.y + hb.size.y * 0.3, hb.get_center().z)
			h = hb.size.y * 1.6
	var fwd := _model.global_transform.basis.z.normalized()
	var eye := c + (fwd + Vector3(0.12, 0.08, 0)).normalized() * (h * 0.6 / tan(deg_to_rad(15.0)))
	_cam.global_transform = Transform3D(Basis.looking_at(c - eye), eye)
	set_process(false)


## Interface face name and texture for a unit ("" when it has none).
static func face_names(u: GameUnit) -> PackedStringArray:
	var model := String(u.race.get("mask", "")).to_lower()
	var c: Vector3 = u.info.get("complexion", Vector3.ZERO)
	if c == Vector3.ZERO:
		c = GameUnit.proto_complexion(u.proto)
	var build := "th" if c.x < 0.2 else ("fa" if c.x > 0.8 else "me")
	var fig := "infa%s%s%dface" % [model, build, int(u.proto.get("hair", 0)) + 1]
	var sex: String = {"unhuma": "m", "unhufe": "f"}.get(model, "")
	var tex := "face%s%02d" % [sex, int(u.proto.get("skin", 0))]
	return PackedStringArray([fig, tex])


func _infa_face(vp: SubViewport, u: GameUnit) -> bool:
	var names := face_names(u)
	if EIFigure.get_model(names[0]).is_empty() or GameData.get_texture(names[1]) == null:
		return false
	var c: Vector3 = u.info.get("complexion", Vector3.ZERO)
	var n := EIFigure.instantiate(names[0], names[1], c)
	if n == null:
		return false
	vp.add_child(n)
	_model = n
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var mat: StandardMaterial3D = mi.material_override.duplicate()
		# CI3DFigure::Draw (005e6d90 -> 00501d00 -> 005a7640) uses a
		# uniform tint, bypassing the world figure's vertex-lighting routine.
		# The portrait texture already contains its facial highlights/shadows.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# The original HUD atlas has one level (00640020 -> 005ff0b0 ->
		# 00691d40 -> 0068f680). Mipmaps blur eyes/mouth when this 128 px
		# face is drawn in a 50–100 px HUD cell. Keep bilinear sampling.
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		mat.uv1_scale = Vector3(2, 2, 1)
		mat.uv1_offset = Vector3(0, -1, 0)
		mi.material_override = mat
		_mats.append(mat)
		var b := mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.x, box.size.z) * 1.05
	var ctr := box.get_center()
	cam.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), ctr + Vector3(0, box.size.y + 1.0, 0))
	vp.add_child(cam)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	vp.add_child(env)
	_tex = names[1]
	_expr = -1
	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)
	set_process(true)
	return true


func _update_expression(dt: float) -> void:
	if not is_instance_valid(_unit):
		return
	if _unit.hp < _last_hp:
		_expression = "c"
		_expression_t = 0.0
		_flash_t = 1.0
	else:
		_flash_t = maxf(0.0, _flash_t - dt)
	_last_hp = _unit.hp
	_flash.color.a = int(_flash_t * 200.0) / 255.0
	if not _expression.is_empty():
		_expression_t += dt
		if _expression_t > (4.0 if _expression == "a" else 2.0):
			_expression = ""
	var e := _expression
	if e.is_empty() and (_unit.max_mana <= 0.0 or _unit.mana / _unit.max_mana < 0.25):
		e = "b"
	var code := "_abc".find(e) if e else 0
	if code == _expr:
		return
	_expr = code
	var tex := GameData.get_texture(_tex + e) if e else null
	if tex == null:
		tex = GameData.get_texture(_tex)   # no such variant: the base face
	for m in _mats:
		m.albedo_texture = tex


##  updates the face even when the acknowledgement is silent.
func acknowledge(code: int) -> void:
	if code == 0x30:
		_expression = "a"
		_expression_t = 0.0
	elif code >= 0x0b and code <= 0x15:
		_begin_motion(2)


## each party member given a world order nods after 0..0.3 s.
func nod() -> void:
	_begin_motion(1)


func _begin_motion(kind: int) -> void:
	_head_motion = kind
	_motion_t = -_rng.randf_range(0.0, 0.3)
	if kind == 3:
		_look_q = Quaternion(Vector3.UP, _rng.randf_range(-PI / 24.0, PI / 24.0)) \
			* Quaternion(Vector3.RIGHT, _rng.randf_range(-PI / 24.0, PI / 24.0))
		_look_speed = _rng.randf_range(1.0, 3.0)


func _update_head(dt: float) -> void:
	if not is_instance_valid(_model):
		return
	if _head_motion == 0 and dt > 0.0 and _rng.randf() < dt / 3.0:
		_begin_motion(3)
	var motion := Quaternion.IDENTITY
	if _head_motion != 0:
		_motion_t += dt
		if _motion_t >= 0.0:
			var duration := PI / 5.0 if _head_motion == 1 else TAU / 5.0
			if _head_motion == 3:
				duration = TAU / _look_speed
			if _motion_t >= duration:
				_head_motion = 0
			elif _head_motion == 3:
				motion = Quaternion.IDENTITY.slerp(_look_q, 0.5 - 0.5 * cos(_motion_t * _look_speed))
			else:
				var axis := Vector3.RIGHT if _head_motion == 1 else Vector3.UP
				motion = Quaternion(axis, PI * 0.5 * 0.1 * sin(5.0 * _motion_t))
	var target := Quaternion(Vector3.LEFT, PI / 14.0) if selected else Quaternion.IDENTITY
	_selection_q = _selection_q.slerp(target, minf(1.0, 2.0 * dt))
	var q := _selection_q * motion
	_model.quaternion = EISpace.quat(q.w, q.x, q.y, q.z)
