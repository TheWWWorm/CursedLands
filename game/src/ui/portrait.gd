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
## the original places the interface face in the 800x600 interface
## camera space (: pixel (px, py) at depth z -> ((px/400 - 1)·K·z
## (py/400 - 0.75)·K·z, z), K = 0.48157462, perspective): the model's origin at
## the cell's centre x, y 548, depth 7, scaled (0.3 for a cell
## wider than 49 px, else 0.22), turned by π about the view x axis (the face
## model looks up its +z). The faces sit low on the screen, so the view ray
## comes from above: about 16° for y 548. Set by PartyFaces: the face's
## 800x600 rect (the viewport) and its centre x; empty = the old ortho framing.
var exe_rect := Rect2()
var exe_x := 400.0
var exe_scale := 0.3
## The face centre's y (800x600): EXE_Y, or lower for the remake's smaller
## co-op faces (PartyFaces).
var exe_y := EXE_Y
var exe_angle := PI
const EXE_K := 0.48157462
const EXE_Y := 548.0
const EXE_DEPTH := 7.0
var _pivot: Node3D
var _face_cam: Camera3D
var _box_cam_size := 0.0

var _key := ""
var _model: Node3D
var _cam: Camera3D
var _framed := 0
var _vp: SubViewport
var _preview_pending := false
var _preview_drawn := false
var _preview_alpha := 1.0
var _preview_update := SubViewport.UPDATE_WHEN_VISIBLE
# Expressions: the face texture gets suffix
# "c" for 2 s when health drops, "a" for 4 s on kill ack 0x30 (and, remake
# option "smile_faces", the moments of SmileFaces), otherwise "b" below 25 %
# stamina. The independent 1 s red flash uses trunc(t * 200).
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
## Remake: the live portrait of each unit (instance id -> Portrait).
## PartyFaces.rebuild (on every "inventory" event: a kill's experience, loot,
## a state sync) frees the cells and makes new portraits; the new one takes
## over the old one's expression, red flash and last health. Before this the
## kill's smile (ack 0x30, with the kill's experience right after it) and
## often the pain face were dropped at once and never seen.
static var _live := {}
## A live portrait freed before its successor was made (the rebuild came from
## a callback after this frame's PartyFaces._process, e.g. a theft or loot at
## the end of the use clip): its state, taken over by the next portrait of the
## unit (instance id -> [expression, its time, flash, last health]).
static var _left := {}


func _ready() -> void:
	_rng.randomize()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_disconnect_preview_draw()
	elif what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_VISIBILITY_CHANGED:
		if _preview_pending and is_visible_in_tree():
			_arm_preview_draw()
		elif not is_visible_in_tree():
			_disconnect_preview_draw()
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_unit) and _live.get(_unit.get_instance_id()) == self:
		_live.erase(_unit.get_instance_id())
		_left[_unit.get_instance_id()] = [_expression, _expression_t, _flash_t, _last_hp]


## Rebuilds only when the unit's look changed (equipment swap).
func show_unit(u: GameUnit) -> void:
	if u != _unit:
		_expression = ""
		_expression_t = 0.0
		_flash_t = 0.0
		_last_hp = u.hp
		_head_motion = 0
		_selection_q = Quaternion.IDENTITY
		var old = _live.get(u.get_instance_id())
		if is_instance_valid(old) and old is Portrait and old != self and old.is_queued_for_deletion() and old._unit == u:
			_expression = old._expression
			_expression_t = old._expression_t
			_flash_t = old._flash_t
			_last_hp = old._last_hp
		elif _left.has(u.get_instance_id()):
			var st: Array = _left[u.get_instance_id()]
			_expression = st[0]
			_expression_t = st[1]
			_flash_t = st[2]
			_last_hp = st[3]
		_left.erase(u.get_instance_id())
		_live[u.get_instance_id()] = self
	_unit = u
	var shown := u.figure_info()
	var key := "%s|%s|%s|%s|%s" % [u.get_instance_id(), u.info.get("prototype", ""),
		shown.get("complexion", Vector3.ZERO), u.info.get("armors", []), u.info.get("weapons", [])]
	if key == _key:
		return
	_key = key
	if is_instance_valid(_vp) and _vp.size_changed.is_connected(_wait_for_draw):
		_vp.size_changed.disconnect(_wait_for_draw)
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
	_vp = vp
	_vp.size_changed.connect(_wait_for_draw)
	_wait_for_draw()
	if _infa_face(vp, u):
		return
	var info: Dictionary = shown
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
	var c: Vector3 = u.info.get("complexion", Vector3.ZERO)
	return proto_face_names(u.proto, u.race, c)


## The same for a prototype and race record (complexion zero = the prototype's).
static func proto_face_names(proto: Dictionary, race: Dictionary, c: Vector3) -> PackedStringArray:
	var model := String(race.get("mask", "")).to_lower()
	if c == Vector3.ZERO:
		c = GameUnit.proto_complexion(proto)
	var build := "th" if c.x < 0.2 else ("fa" if c.x > 0.8 else "me")
	var fig := "infa%s%s%dface" % [model, build, int(proto.get("hair", 0)) + 1]
	var sex: String = {"unhuma": "m", "unhufe": "f"}.get(model, "")
	var tex := "face%s%02d" % [sex, int(proto.get("skin", 0))]
	return PackedStringArray([fig, tex])


## A face without a unit (the network character screen's face strips,
## "infa%sme%dface" of the prototype's race
## model and hair, texture "face%s%02d" of its skin).
func show_proto(proto_name: String, c := Vector3.ZERO) -> void:
	var key := "proto|%s|%s" % [proto_name, c]
	if key == _key:
		return
	_key = key
	_unit = null
	if is_instance_valid(_vp) and _vp.size_changed.is_connected(_wait_for_draw):
		_vp.size_changed.disconnect(_wait_for_draw)
	for ch in get_children():
		ch.queue_free()
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
	_vp = vp
	_vp.size_changed.connect(_wait_for_draw)
	_wait_for_draw()
	var proto := GameData.db.find("monster_prototypes", proto_name)
	var race := GameData.db.find("race_models", String(proto.get("base_race", "")))
	_build_face(vp, proto_face_names(proto, race, c), c if c != Vector3.ZERO else GameUnit.proto_complexion(proto))
	set_process(false)


## Allocated and resized render targets have no image until their first
## draw. Keep only this container's texture transparent while the viewport
## clears/renders; the parent's tint and the damage flash remain independent.
func _wait_for_draw() -> void:
	if not _preview_pending:
		_preview_alpha = self_modulate.a
		# The container itself disables viewports under a hidden parent. A
		# hidden resize must retain the visible policy rather than that pause.
		if is_visible_in_tree() or _vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_preview_update = _vp.render_target_update_mode
	_preview_pending = true
	_preview_drawn = false
	self_modulate.a = 0.0
	if is_inside_tree() and is_visible_in_tree():
		_arm_preview_draw()


func _arm_preview_draw() -> void:
	if not is_instance_valid(_vp):
		return
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if not RenderingServer.frame_pre_draw.is_connected(_before_preview_draw):
		RenderingServer.frame_pre_draw.connect(_before_preview_draw)
	if not RenderingServer.frame_post_draw.is_connected(_after_preview_draw):
		RenderingServer.frame_post_draw.connect(_after_preview_draw)


func _before_preview_draw() -> void:
	_preview_drawn = is_visible_in_tree() and is_instance_valid(_vp) and _vp.is_inside_tree() \
		and _vp.size.x > 1 and _vp.size.y > 1 \
		and (not is_instance_valid(_model) or not _mats.is_empty() or _framed >= 2)
	if _preview_drawn:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _after_preview_draw() -> void:
	if not _preview_drawn:
		return
	_preview_pending = false
	self_modulate.a = _preview_alpha
	_vp.render_target_update_mode = _preview_update
	_disconnect_preview_draw()


func _disconnect_preview_draw() -> void:
	_preview_drawn = false
	if _preview_pending and is_instance_valid(_vp):
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if RenderingServer.frame_pre_draw.is_connected(_before_preview_draw):
		RenderingServer.frame_pre_draw.disconnect(_before_preview_draw)
	if RenderingServer.frame_post_draw.is_connected(_after_preview_draw):
		RenderingServer.frame_post_draw.disconnect(_after_preview_draw)


func _infa_face(vp: SubViewport, u: GameUnit) -> bool:
	return _build_face(vp, face_names(u), u.info.get("complexion", Vector3.ZERO))


func _build_face(vp: SubViewport, names: PackedStringArray, c: Vector3) -> bool:
	if EIFigure.get_model(names[0]).is_empty() or GameData.get_texture(names[1]) == null:
		return false
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
	# The model under a pivot that holds the interface placement; its own
	# rotation is the head motion (_update_head).
	vp.remove_child(n)
	_pivot = Node3D.new()
	vp.add_child(_pivot)
	_pivot.add_child(n)
	var cam := Camera3D.new()
	_face_cam = cam
	_box_cam_size = maxf(box.size.x, box.size.z) * 1.05
	vp.add_child(cam)
	_place_face()
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


## Camera and model placement for exe_rect (see exe_rect above).
func _place_face() -> void:
	if not is_instance_valid(_face_cam) or not is_instance_valid(_pivot):
		return
	var cam := _face_cam
	if not exe_rect.has_area():
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = _box_cam_size
		cam.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0, 10, 0))
		_pivot.transform = Transform3D.IDENTITY
		return
	# The interface camera through exe_rect (as Paperdoll._ui_camera).
	var near := 0.1
	var k := EXE_K * near
	var c := exe_rect.get_center()
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.set_frustum(exe_rect.size.y * 0.0025 * k,
		Vector2((c.x * 0.0025 - 1.0) * k, -(c.y * 0.0025 - 0.75) * k), near, 100.0)
	cam.transform = Transform3D.IDENTITY
	# EI camera space (x right, y down, z forward) -> Godot camera space; the
	# model's local axes are EI's mapped by EISpace (x, z, -y).
	var to_godot := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))
	var ei_local := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	var rot := Basis(Vector3(1, 0, 0), exe_angle)
	var at := Vector3((exe_x * 0.0025 - 1.0) * EXE_K * EXE_DEPTH,
		(exe_y * 0.0025 - 0.75) * EXE_K * EXE_DEPTH, EXE_DEPTH)
	_pivot.transform = Transform3D((to_godot * rot * ei_local.inverse()).scaled_local(Vector3.ONE * exe_scale),
		to_godot * at)


## PartyFaces: the face's 800x600 rect, its centre x and the cell's scale
## (and its centre y, EXE_Y in the original).
func set_exe_place(rect: Rect2, x: float, scale: float, y := EXE_Y, angle := PI) -> void:
	if rect == exe_rect and x == exe_x and scale == exe_scale and y == exe_y and angle == exe_angle:
		return
	exe_rect = rect
	exe_x = x
	exe_scale = scale
	exe_y = y
	exe_angle = angle
	_place_face()


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
