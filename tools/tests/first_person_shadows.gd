extends Node
## Render the shadow of the final composed pose, including late pre-draw updates.
var checks := 0
var failures := []
var measurements := []
var actor: GameUnit
var pose: DirectPose
var camera: Camera3D
var pending_phase := -1.0
var native_clip := ""
var capture_requested := false
var sources: Array[MeshInstance3D] = []
signal captured(image: Image)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)

func frames(count := 3) -> void:
	for i in count: await get_tree().process_frame

func apply_pose(phase: float) -> void:
	pose.restore_pose()
	actor.model.play(native_clip, 0.0, true)
	var clip := actor.model.player.get_animation("ei/"+native_clip)
	actor.model.player.seek(clip.length * 0.35, true)
	pose.phase = phase
	pose.weight = 1.0
	pose.apply_pose(0.0)
	# Make the ordinary figure a settled reference for this exact pose.
	if not actor.model._view_active:
		for mesh in sources: mesh.force_update_transform()

func _process(_dt: float) -> void:
	if pending_phase < 0.0: return
	apply_pose(pending_phase)
	pending_phase = -1.0
	capture_requested = true

func record_frame() -> void:
	if not capture_requested: return
	capture_requested = false
	captured.emit(get_viewport().get_texture().get_image())

func capture(phase: float, first_person: bool) -> Image:
	actor.model.set_first_person_view(first_person)
	# Observe only shadows. First person normally draws its close-view mesh;
	# hide those renderer instances without changing the source visibility
	# that the shadow copies deliberately mirror.
	for mesh in sources:
		RenderingServer.instance_set_visible(mesh.get_instance(), mesh.is_visible_in_tree() and not first_person)
	# Establish a different early pose, just as the native animation and
	# camera callbacks precede DirectPose's late lower-body composition.
	apply_pose(0.0 if first_person else phase)
	if first_person:
		actor.model.align_first_person_body(Vector3(0, 1.7, 0), Vector3.RIGHT)
	await frames()
	pending_phase = phase
	return await captured

func difference(a: Image, b: Image) -> int:
	var count := 0
	# The requested development FPS counter changes independently of the scene.
	for y in range(40,a.get_height()):
		for x in a.get_width():
			if absf(a.get_pixel(x,y).r - b.get_pixel(x,y).r) > 0.05: count += 1
	return count

func _ready() -> void:
	check(DisplayServer.get_name() != "headless", "shadow regression uses a real renderer")
	if DisplayServer.get_name() == "headless": get_tree().quit(1); return
	process_priority = 20
	RenderingServer.frame_post_draw.connect(record_frame)
	# Startup applies the saved display mode after its first few frames.
	# Let that finish before choosing a fixed-size comparison viewport.
	await frames(16)
	GameData._window_gen += 1
	GameData.options.display_mode = 0
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(640,640)
	get_viewport().scaling_3d_scale = 1.0
	Engine.max_fps = 60
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.WHITE
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.2
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-25,0)
	sun.shadow_enabled = true
	RenderingServer.directional_shadow_atlas_set_size(2048,true)
	sun.directional_shadow_max_distance = 25.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_normal_bias = 0.1
	add_child(sun)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(20,20)
	ground.material_override = StandardMaterial3D.new()
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0,8,4)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	camera.near = 0.1
	camera.far = 20.0
	camera.cull_mask = 3
	camera.current = true
	actor = GameUnit.new()
	actor.set_process(false); actor.set_physics_process(false)
	actor.direct_controlled = true
	actor.direct_motion = Vector2.RIGHT
	actor._move_speed = 3.0
	actor.gait_run = true
	actor.action = "attack"
	actor.model = EIUnitModel.create({"prototype":"Human Hero","complexion":Vector3(.5,.5,.5)})
	actor.add_child(actor.model)
	add_child(actor)
	actor.model.set_process(false)
	actor.model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for mesh: MeshInstance3D in actor.model.find_children("*","MeshInstance3D",true,false):
		sources.append(mesh)
		mesh.layers = 2
		mesh.material_override = StandardMaterial3D.new()
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	pose = DirectPose.new(actor)
	add_child(pose); pose.set_process(false)
	for action: String in ["run","attack","cast"]:
		actor.action = action
		pose.restore_pose()
		actor.model.act(action,1,0.0)
		native_clip = actor.model._current
		var still := await capture(0.0, false)
		for phase: float in [0.2,0.5,0.8]:
			var ordinary := await capture(phase, false)
			var first := await capture(phase, true)
			var changed := difference(still,ordinary)
			var wrong := difference(ordinary,first)
			var label := "%s phase %.1f" % [action,phase]
			check(ordinary.get_size()==first.get_size() and first.get_size()==Vector2i(640,640),label+" keeps the comparison viewport fixed")
			check(changed > 20,label+" has a moving leg silhouette")
			check(wrong < 10,label+" first-person shadow matches the final running pose")
			measurements.append({"case":label,"moving_pixels":changed,"wrong_pixels":wrong})
			ordinary.save_png("user://shadow-%s-%.1f-world.png" % [action,phase])
			first.save_png("user://shadow-%s-%.1f-first.png" % [action,phase])
	actor.model.set_first_person_view(false)
	actor.queue_free(); pose.queue_free()
	await frames()
	print("FIRST_PERSON_SHADOWS ",JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements}))
	TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
