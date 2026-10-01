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
# "c" for 2 s when health drops (with a red flash fading over 1 s), "b"
# while health is under 25 %, otherwise none. ("a", a smile, has a setter
#  that nothing calls.)
var _unit: GameUnit
var _mats: Array[StandardMaterial3D] = []
var _tex := ""
var _expr := -1
var _hit_t := 0.0
var _last_hp := -1.0
var _flash: ColorRect


## Rebuilds only when the unit's look changed (equipment swap).
func show_unit(u: GameUnit) -> void:
	var key := "%s|%s|%s" % [u.info.get("prototype", ""), u.info.get("armors", []), u.info.get("weapons", [])]
	if key == _key:
		return
	_key = key
	for c in get_children():
		c.queue_free()
	_mats.clear()
	stretch = true
	custom_minimum_size = Vector2(view_size)
	var vp := SubViewport.new()
	vp.size = view_size
	vp.own_world_3d = true
	vp.transparent_bg = true
	add_child(vp)
	if _infa_face(vp, u):
		return
	var info: Dictionary = u.info.duplicate()
	info.weld = false   # the head needs its own mesh here
	var m := EIUnitModel.create(info)
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
		_update_expression(dt)
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
	_unit = u
	_tex = names[1]
	_expr = -1
	_last_hp = u.hp
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
	if _unit.hp < _last_hp - 0.01:
		_hit_t = 2.0
		_flash.color.a = 0.5
	_last_hp = _unit.hp
	_hit_t = maxf(0.0, _hit_t - dt)
	_flash.color.a = maxf(0.0, _flash.color.a - dt * 0.5)
	var e := ""
	if _hit_t > 0.0:
		e = "c"
	elif _unit.max_hp <= 0.0 or _unit.hp / _unit.max_hp < 0.25:
		e = "b"
	var code := "_bc".find(e) if e else 0
	if code == _expr:
		return
	_expr = code
	var tex := GameData.get_texture(_tex + e) if e else null
	if tex == null:
		tex = GameData.get_texture(_tex)   # no such variant: the base face
	for m in _mats:
		m.albedo_texture = tex
