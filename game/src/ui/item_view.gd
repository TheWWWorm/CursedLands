class_name ItemView
extends SubViewportContainer
## One item's 3D model in a HUD slot, as the original shows weapons:
## the figure (Items.look) in the fixed orientation
## q = rot(z, -0.157) · rot(y, -1.047) · rot(z, 2.356) (EI space), seen from
## above. Weapon / armour models are skinned with their unit redress layer.
## Approx.: the orthographic camera, framing and light.
## Camp slots (`camp = true`) follow the camp's item draw
## instead. Both draws set the orientation of the same UI 3D object
## so the original's q is used as is: the HUD dagger
## with q unchanged matches the original's screenshots (tip leaning right),
## while rot(y, π) · q mirrors it (checked 2026-10-01; the camp's earlier
## rot(y, π) frame turn is gone):
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
	var q := Quaternion(Vector3(0, 0, 1), -0.157) * Quaternion(Vector3(0, 1, 0), -1.047) \
		* Quaternion(Vector3(0, 0, 1), 2.356)
	_axis = Vector3.ZERO
	_angle = 0.0
	_speed = 0.0
	if camp:
		var k := Items.kind(id)
		if id.begins_with("spell:") or k == "rune":
			q = Quaternion(Vector3(0, 0, 1), PI)
		else:
			q = Quaternion(Vector3(1, 0, 0), PI)
			if k != "blueprint":
				_axis = Vector3(1, 1, 0).normalized() if k == "weapon" else Vector3(0, 1, 0)
	_pulse = -1
	_phase = 0.0
	if camp and Items.kind(id) in ["weapon", "armor"] and not Items.spell_of(id).is_empty():
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
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = m.transform * mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var aspect := size.x / maxf(size.y, 1.0) if size.y > 0 else 1.0
	# Looking down the EI z axis (screen up = EI -y), where the original's
	# orientation stands the bottles up.
	cam.size = maxf(box.size.z, box.size.x / aspect) * 1.1
	cam.rotation_degrees = Vector3(-90, 180, 0)
	cam.position = box.get_center() + Vector3(0, box.size.length() + 2.0, 0)
	_vp.add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, 20, 0)
	_vp.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	_vp.add_child(env)


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
