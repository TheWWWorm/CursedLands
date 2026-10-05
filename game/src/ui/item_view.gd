class_name ItemView
extends SubViewportContainer
## One item's 3D model in a HUD slot, as the original shows weapons:
## the figure (Items.look) in the fixed orientation
## q = rot(z, -π/20) · rot(y, -π/3) · rot(z, 3π/4) (EI space).
## Weapon / armour models are skinned with their unit redress layer.
## No light (CI3DFigure::Draw → renderer
## with flag 0x100, set by the weapon bar and the camp
## ): every vertex colour = (white here) and specular =
## so the pixels are texture × white (+ add_color) — unshaded.
## Projection: the game's one perspective (fov 2π/7, no view
## matrix); (sx, sy, z) places the figure, so on screen a model
## unit is 400 / K · scale / z pixels of 800×600 (`unit_px`): weapon bar
## 1.2ⁿ / (24·1.2ⁿ) = 34.6, the active weapon 0.65 / 12 = 45.0.
## Camp uses scale = slot width · K · z · 0.0009375, so the
## 100-wide slots show 37.5 px/model unit. Dialog quest items instead use
## scale 1, depth 12 (69.2 px/model unit).
## With `screen_at` it is drawn in that perspective: camera
## at the origin, frustum near 1, the figure at the placed point, so a figure
## left of / below the screen centre is seen slightly from the side.
## Camp side info (mode 9) uses its authored FIG centre/extents and the
## same perspective, at width 120/depth 3, with fixed orientation and tint.
## `unit_px` 0 is the box-fitted fallback for an unavailable authored box.
## Camp slots (`camp = true`) follow the camp's item draw
## instead. Both draws set the orientation of the same UI 3D object
## so the original's q is used as is. The native
## Draw/TLP projection maps EI x right, y down and z forward for all callers:
## - spells, keystones and runes (0x3008, loot 2/3, 2/4): q = rot(z, π);
## - blueprints (loot 2/0..2): q = rot(x, π);
## - weapons (0x3004): q = rot(x, π) · rot((1,1,0), a), everything else
##   rot(x, π) · rot((0,1,0), a), where a turns while the item is the
##   widget's hovered one (`spin`): the speed gains 8 rad/s² up to 5 rad/s;
##   unhovered, a speed ≥ 0.1 becomes (2π − a) · 4 (back to the start),
##   below it a and the speed drop to 0.
## Enchanted weapons and armour (0x3004 / 0x3005 with a spell) pulse
## in the camp: phase = fmod(phase + dt · 5, 2π)
##  = trunc(table[s] · (sin(phase) + 1) · 0.15 · 255) per channel, with
## s the spell prototype's (subtype_id, < 8) and the table:
## red, cyan, green, yellow, yellow, magenta, magenta, blue (`PULSE`).
const PULSE := [Color(1, 0, 0), Color(0, 1, 1), Color(0, 1, 0), Color(1, 1, 0), Color(1, 1, 0),
	Color(1, 0, 1), Color(1, 0, 1), Color(0, 0, 1)]

var item := ""
var camp := false
## quick items and wands use rot(x, π).
var belt := false
##  mode 9: fixed item behind the info widget's text.
var info := false
## Remake: keep a camp item inside its icon cell throughout its spin.
var fit_slot := false
## A dialog's shown quest item: turned π about x.
var quest := false
## The UI figure's colour (default):
##  write it as every vertex's specular colour (with flag 0x100
## or as the specular base handed to the figure lighting), which the 2000
## renderer adds to the textured colour. The HUD on the
## active weapon and on a picked belt / spell cell
## . Drawn here as that 8-bit
## value added to the model's pixels (`add_color`).
var add_color := Color(0, 0, 0):
	set(v):
		add_color = v
		_apply_add()
static var _add_shader: Shader
var spin := false
## Screen pixels per model unit, 0 = fit the model's box (see the header).
var unit_px := 0.0
## With `unit_px`: (sx, sy) of the 800×600 screen and d = z / scale of the
## figure's placement — drawn in the original's perspective, the view
## centred on (sx, sy). d 0 = orthographic.
var screen_at := Vector3.ZERO
const K := 0.48157462
var _vp: SubViewport
var _model: Node3D
var _base := Quaternion.IDENTITY
var _axis := Vector3.ZERO   # EI axis of the turn, zero = none
var _angle := 0.0
var _speed := 0.0
var _pulse := -1   # PULSE index, -1 = none
var _phase := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	add_child(_vp)


func _apply_add() -> void:
	if add_color == Color(0, 0, 0):
		material = null
		return
	if _add_shader == null:
		_add_shader = Shader.new()
		_add_shader.code = """shader_type canvas_item;
uniform vec3 add_rgb;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(min(c.rgb + add_rgb * step(0.004, c.a), vec3(1.0)), c.a);
}
"""
	var m := material as ShaderMaterial
	if m == null:
		m = ShaderMaterial.new()
		m.shader = _add_shader
		material = m
	m.set_shader_parameter("add_rgb", Vector3(add_color.r, add_color.g, add_color.b))


func show_item(id: String) -> void:
	if id == item:
		return
	item = id
	for ch in _vp.get_children():
		ch.queue_free()
	_model = null
	var look := Items.look(id) if id else {}
	if look.is_empty():
		return
	#  returns before drawing if either its figure cache or
	# explicit texture cache is empty. Keep that refusal for unused database
	# rows whose authored picture is absent, rather than painting a fallback.
	if look.has("texture") and GameData.get_texture(String(look.texture)) == null:
		return
	var m := EIFigure.instantiate(look.model, look.get("texture", ""), Vector3.ZERO)
	if m == null:
		return
	if look.has("layer"):
		var mat := EIFigure.material_for("").duplicate() as StandardMaterial3D
		mat.albedo_color = Color.WHITE
		mat.albedo_texture = EIUnitModel._compose("unhuma", [look.layer] as Array[String])
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		# The item models address a 256×256 canvas holding the layer at its own
		# size: 256 layers (plates, boots, leggings, gloves) fill it, 128 ones
		# (swords, helms) its corner — initwesw2weapon's UVs are rh3.sword02's
		# halved there.
		var k := 256.0 / maxf(mat.albedo_texture.get_width(), 1.0) if mat.albedo_texture else 1.0
		mat.uv1_scale = Vector3(k, k, 1)
		mat.uv1_offset = Vector3(0, 1.0 - k, 0)
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat
	elif look.has("texture"):
		# Small skins (64×64 keystone / rune pictures) sit in the corner of the
		# same 256 canvas: initqi1item's UVs span 0..0.25.
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			var sm := mi.get_active_material(0) as StandardMaterial3D
			if sm == null or sm.albedo_texture == null or sm.albedo_texture.get_width() >= 256:
				continue
			sm = sm.duplicate()
			var k := 256.0 / float(sm.albedo_texture.get_width())
			sm.uv1_scale = Vector3(k, k, 1)
			sm.uv1_offset = Vector3(0, 1.0 - k, 0)
			mi.material_override = sm
	_vp.add_child(m)
	# Exact original float constants.
	var q := Quaternion(Vector3(0, 0, 1), -0.1570796371) * Quaternion(Vector3(0, 1, 0), -1.04719758) \
		* Quaternion(Vector3(0, 0, 1), 2.35619449)
	_axis = Vector3.ZERO
	_angle = 0.0
	_speed = 0.0
	if quest:
		q = Quaternion(Vector3(1, 0, 0), PI)
	elif belt:
		q = Quaternion(Vector3(1, 0, 0), PI)
	elif camp:
		var k := Items.kind(id)
		if id.begins_with("spell:") or k in ["keystone", "rune"]:
			q = Quaternion(Vector3(0, 0, 1), PI)
		else:
			q = Quaternion(Vector3(1, 0, 0), PI)
			if not info and k != "blueprint":
				_axis = Vector3(1, 1, 0).normalized() if k == "weapon" else Vector3(0, 1, 0)
	_pulse = -1
	_phase = 0.0
	if camp and not info and Items.kind(id) in ["weapon", "armor"] and not Items.spell_of(id).is_empty():
		var st := int(Spells.parse(Items.spell_of(id)).proto.get("subtype_id", 8))
		if st >= 0 and st < 8:
			_pulse = st
	if _pulse < 0 and camp:
		add_color = Color(0, 0, 0)
	_base = q
	_model = m
	m.quaternion = EISpace.quat(q.w, q.x, q.y, q.z)
	var box := AABB()
	var first := true
	var radius := 0.0
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var local_xf := m.global_transform.affine_inverse() * mi.global_transform
		var raw_box := mi.get_aabb()
		for corner in 8:
			var p := raw_box.position + raw_box.size * Vector3(1 if corner & 1 else 0, 1 if corner & 2 else 0, 1 if corner & 4 else 0)
			radius = maxf(radius, (local_xf * p).length())
		var b: AABB = m.transform * local_xf * raw_box
		box = b if first else box.merge(b)
		first = false
	# Unlit: flag 0x100 colours (see the header).
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override:
			mi.material_override = _unlit(mi.material_override)
		elif mi.mesh:
			for si in mi.mesh.get_surface_count():
				var sm := mi.get_active_material(si)
				if sm:
					mi.set_surface_override_material(si, _unlit(sm))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var aspect := size.x / maxf(size.y, 1.0) if size.y > 0 else 1.0
	var at := screen_at
	var crop_at := Vector2(at.x, at.y)
	var px := unit_px
	if info:
		# The info widget clips its complete 200x300 area. The placed figure
		# point is 50 below that area's centre (5ee440 / 5ee5c0).
		crop_at.y -= 50.0
		var fit := info_placement(look.model, Vector2(at.x, at.y))
		if not fit.is_empty():
			# Keep the model at unit scale; moving the camera by z/scale gives
			# the native perspective, including its off-centre view direction.
			var d: float = fit.depth / fit.scale
			at = Vector3(fit.screen.x, fit.screen.y, d)
			px = 400.0 / K / d * size.x / 200.0
	# CI3DFigure::Draw and the shipped TLP project all UI item callers with
	# the same right/down/forward basis, including camp, belt and weapons.
	cam.rotation_degrees = Vector3(90, 0, 0)
	if fit_slot:
		# A sphere around the figure origin contains every possible hovered
		# orientation, so a long hammer cannot spill into another icon.
		cam.size = maxf(radius * 2.1, 0.1) * maxf(1.0, 1.0 / aspect)
		cam.position = Vector3(0, -radius - 2.0, 0)
		cam.far = radius * 2.0 + 4.0
	elif px > 0.0 and at.z > 0.0:
		# The original's perspective (see the header): camera at the origin, the
		# figure at ((sx/400 − 1)·K·d, (sy/400 − 0.75)·K·d, d) with y down;
		# the view shows the part of that frustum around (sx, sy).
		var f := 400.0 / K
		var d := at.z
		var lx := (at.x - 400.0) / f * d
		var ly := -(at.y - 300.0) / f * d
		var b := Basis.from_euler(cam.rotation)
		cam.position = b.z * d - b.x * lx - b.y * ly
		var n := 1.0
		var offset := Vector2(crop_at.x - 400.0, -(crop_at.y - 300.0)) / f * n
		cam.set_frustum(maxf(size.y, 1.0) * n / (px * d), offset, n, d + 50.0)
	elif unit_px > 0.0:
		cam.size = maxf(size.y, 1.0) / unit_px
		var distance := maxf(-box.position.y, 0.0) + 2.0
		cam.position = Vector3(0, -distance, 0)
		cam.far = distance + maxf(box.end.y, 0.0) + 2.0
	else:
		cam.size = maxf(box.size.z, box.size.x / aspect) * 1.1
		cam.position = box.get_center() + Vector3(0, -box.size.length() - 2.0, 0)
	_vp.add_child(cam)


##  loads the authored centre and relative min/max at complexion
## zero. Mode 9 uses +18c/+190 to offset the placed screen point and divides
## by max(+1a8,+1ac), without rotating/refitting the box to actual vertices.
static func info_placement(template: String, screen: Vector2, width := 120.0, depth := 3.0) -> Dictionary:
	var model := EIFigure.get_model(template)
	if model.is_empty() or model.parts.size() != 1:
		return {}
	var fig: Dictionary = model.parts.values()[0]
	var data: PackedByteArray = fig.data
	var n := int(fig.n)
	if n <= 0 or data.size() < 40 + n * 40:
		return {}
	var centre := Vector2(data.decode_float(40), data.decode_float(44))
	var extent := maxf(data.decode_float(40 + n * 24), data.decode_float(44 + n * 24))
	if extent <= 0.0:
		return {}
	var at := screen + Vector2(-centre.x, centre.y) * width * 0.5
	return {"screen": at, "depth": depth,
		"position": Vector3((at.x * 0.0025 - 1.0) * K * depth, (at.y * 0.0025 - 0.75) * K * depth, depth),
		"scale": width * K * depth * 0.00125 / extent}


static func _unlit(mat: Material) -> Material:
	var b := mat as BaseMaterial3D
	if b == null or b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return mat
	b = b.duplicate()
	b.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return b


func _process(dt: float) -> void:
	if _pulse >= 0:
		_phase = fmod(_phase + dt * 5.0, TAU)
		var v := (sin(_phase) + 1.0) * 0.15 * 255.0
		var c: Color = PULSE[_pulse]
		add_color = Color8(int(c.r * v), int(c.g * v), int(c.b * v))
	if not camp or _axis == Vector3.ZERO or _model == null or not is_instance_valid(_model):
		return
	if spin:
		_speed = minf(5.0, _speed + dt * 8.0)
	elif _speed >= 0.1:
		_speed = minf(5.0, (TAU - _angle) * 4.0)
	else:
		if _angle == 0.0:
			return
		_angle = 0.0
		_speed = 0.0
	_angle += dt * _speed
	while _angle > TAU:
		_angle -= TAU
	var q := _base * Quaternion(_axis, _angle)
	_model.quaternion = EISpace.quat(q.w, q.x, q.y, q.z)
