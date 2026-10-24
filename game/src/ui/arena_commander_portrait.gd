class_name ArenaCommanderPortrait
extends SubViewportContainer
## Transparent native bust. The face belongs to this preview alone; reactions
## never mutate the campaign's shared materials or a combat actor.
var commander := ""
var view: SubViewport
var model: EIUnitModel
var camera: Camera3D
var face: EIUnitModel.PreviewMaterial
var face_texture := ""
var reaction := -2
var _age := 0.0
var _framed := false
var _pose_frames := 0
var _head_base := Transform3D.IDENTITY
var _result_event := ""
var _motion_age := 10.0
var _upgrade_left := 0.0
var _reaction_left := 0.0
const REACTION_SECONDS := 1.8
const GESTURE_SECONDS := 1.4
var _idle_rng := RandomNumberGenerator.new()
var _glance_wait := 0.0
var _glance_left := 0.0
var _glance_duration := 0.0
var _glance_angles := Vector2.ZERO
var _idle_weight := 1.0

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	view = SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.size = Vector2i(240, 220)
	view.msaa_3d = Viewport.MSAA_2X
	add_child(view)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	view.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -20, 0)
	view.add_child(light)
	var ambient := WorldEnvironment.new()
	ambient.environment = Environment.new()
	ambient.environment.background_mode = Environment.BG_CLEAR_COLOR
	ambient.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambient.environment.ambient_light_color = Color(0.65, 0.65, 0.65)
	view.add_child(ambient)

func show_character(id: String) -> void:
	id = ArenaCommanders.valid(id)
	if id == commander: return
	commander = id
	if is_instance_valid(model):
		view.remove_child(model); model.queue_free()
	face = null; reaction = -2; _age = 0; _framed = false; _pose_frames = 0
	_result_event = ""; _motion_age = 10.0; _upgrade_left = 0.0; _reaction_left = 0.0
	# Portrait motion has its own RNG; looking around never advances game RNG.
	_idle_rng.seed = hash(id)
	_glance_wait = _idle_rng.randf_range(2.5, 4.5)
	_glance_left = 0.0; _idle_weight = 1.0
	var proto := ArenaCommanders.prototype(id)
	var row := GameData.db.find("monster_prototypes", proto)
	# Portraits show the face beneath headgear, as the original party HUD does.
	# Keep native clothing, and keep weapons out of the close crop.
	var clothing := Array(row.get("wears", [])).filter(func(item): return Items.info(item).row.get("type", "") != "helm")
	model = EIUnitModel.create({"prototype":proto, "weapons":[], "armors":clothing, "weld":false}, true)
	if model == null: return
	model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# The right-hand portrait looks inward across the board.
	model.rotation_degrees.y = -30.0
	view.add_child(model)
	model.act("idle", 1, 0.0)
	model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.player.advance(0.0)
	model.player.speed_scale = 0.0
	model.set_detailed_head(true)
	model.remove_from_group(&"detailed_heads")
	if model._detail:
		face = model._detail.material_override as EIUnitModel.PreviewMaterial
		var race := GameData.db.find("race_models", String(row.base_race))
		face_texture = Portrait.proto_face_names(row, race, Vector3.ZERO)[1]
	_apply_expression()
	accessibility_name = ArenaCommanders.title(id)

func set_result(winner: int, event: String = "") -> void:
	if reaction == winner and _result_event == event: return
	reaction = winner; _result_event = event
	_motion_age = 0.0 if winner in [0, 1] else 10.0
	_reaction_left = REACTION_SECONDS if winner in [0, 1] else 0.0
	_upgrade_left = 0.0
	_apply_expression()

func celebrate_upgrade() -> void:
	_upgrade_left = REACTION_SECONDS
	_reaction_left = 0.0
	_motion_age = 0.0
	_apply_expression()

func _apply_expression() -> void:
	if face == null: return
	var suffix := "a" if _upgrade_left > 0.0 or (_reaction_left > 0.0 and reaction == 0) else "b" if _reaction_left > 0.0 and reaction == 1 else ""
	var texture := GameData.get_texture(face_texture + suffix)
	face.albedo_texture = texture if texture else GameData.get_texture(face_texture)

func _process(dt: float) -> void:
	if not is_instance_valid(model): return
	model.process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED
	if not is_visible_in_tree(): return
	var seconds := dt / maxf(Engine.time_scale, 0.001)
	_age += seconds
	_motion_age += seconds
	if _reaction_left > 0.0:
		_reaction_left = maxf(0.0, _reaction_left - seconds)
		# Retain the event identity after returning to neutral, so snapshots
		# and a finished match cannot restart the same smile or frown.
		if _reaction_left == 0.0: _apply_expression()
	if _upgrade_left > 0.0:
		_upgrade_left = maxf(0.0, _upgrade_left - seconds)
		if _upgrade_left == 0.0: _apply_expression()
	if not _framed:
		_pose_frames += 1
		if _pose_frames < 4: return
		model.flush_pending_pose()
		var head := model._head
		if head == null: return
		_head_base = head.transform
		var box := AABB(); var first := true
		for mesh: MeshInstance3D in head.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree(): continue
			var bounds := mesh.global_transform * mesh.get_aabb()
			box = bounds if first else box.merge(bounds); first = false
		if first: return
		# Head, neck and collarbones, with room above the hair for idle motion.
		var height := box.size.y * 1.35
		var center := box.get_center() - Vector3(0, box.size.y * 0.10, 0)
		camera.size = height
		camera.position = center + Vector3(0, 0, 5)
		camera.look_at(center)
		_framed = true
		# Keep the torso in its neutral pose. A random full-body idle gesture
		# can otherwise bring a hand across the face in this close crop.
		model.set_process(false)
		model.player.speed_scale = 0.0
	if model._head:
		var reacting := _upgrade_left > 0.0 or _reaction_left > 0.0
		var idle := _idle_angles(seconds, reacting)
		var happy := _upgrade_left > 0.0 or (_reaction_left > 0.0 and reaction == 0)
		var envelope := sin(PI * clampf(_motion_age / GESTURE_SECONDS, 0.0, 1.0)) if reacting else 0.0
		var gesture := (1.0 - cos(_motion_age * TAU / 0.7)) * 0.09 * envelope if happy else sin(_motion_age * TAU / 0.6) * 0.20 * envelope
		var axis := Vector3.RIGHT if happy else Vector3.UP
		# Turn at the neck, keeping the original hair and face together.
		model._head.transform = _head_base * Transform3D(Basis.from_euler(Vector3(idle.x, idle.y, sin(_age * 0.65) * 0.008)) * Basis(axis, gesture), Vector3.ZERO)

func _idle_angles(seconds: float, reacting: bool) -> Vector2:
	_idle_weight = move_toward(_idle_weight, 0.0 if reacting else 1.0, seconds * 5.0)
	if not reacting:
		if _glance_left > 0.0:
			_glance_left = maxf(0.0, _glance_left - seconds)
		else:
			_glance_wait -= seconds
			if _glance_wait <= 0.0:
				_glance_duration = _idle_rng.randf_range(2.4, 3.4)
				_glance_left = _glance_duration
				_glance_wait = _idle_rng.randf_range(3.0, 6.0)
				_glance_angles = Vector2(deg_to_rad(_idle_rng.randf_range(-4.0, 4.0)), deg_to_rad(_idle_rng.randf_range(9.0, 15.0)) * (-1.0 if _idle_rng.randi() % 2 else 1.0))
	var progress := 1.0 - _glance_left / maxf(_glance_duration, 0.001)
	var glance := smoothstep(0.0, 0.32, progress) * (1.0 - smoothstep(0.65, 1.0, progress))
	return (_glance_angles * glance + Vector2(sin(_age * 0.9) * 0.009, sin(_age * 0.7) * 0.012)) * _idle_weight
