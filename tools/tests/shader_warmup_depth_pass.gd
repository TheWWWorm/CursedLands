extends Node
## RT/PT disables SSAO after warmup. A mesh outside the initial view must
## already have the resulting depth-only main-viewport pipeline when revealed.
class FixtureGame extends Game:
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func frames(count := 1) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH),true)
	GameData.options.merge({"pt_mode":1,"rt_gi":0,"gfx_ssao":1,"gfx_water":0,"gfx_water_reflections":0,"gfx_contact_shadows":0},true)
	Gfx.ensure_globals(); get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	var stage := FixtureGame.new(); add_child(stage)
	stage.world = GameWorld.new(); stage.add_child(stage.world)
	stage.world.set_process(false); stage.world.set_physics_process(false); stage.world.set_meta("quest_bird",true)
	stage.rig = CameraRig.new(); stage.add_child(stage.rig); stage.rig.set_process(false)
	stage.rig.camera.global_position = Vector3(0,2,5); stage.rig.camera.look_at(Vector3.ZERO); stage.rig.camera.current = true
	var environment := WorldEnvironment.new(); stage._env = Environment.new(); environment.environment = stage._env
	stage._env.background_mode = Environment.BG_COLOR; stage.add_child(environment)
	for deferred in [false,true]:
		Gfx.scene_rt_gi_active = false; stage._env.ssao_enabled = true
		var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); mesh.visible = false
		var material := ShaderMaterial.new(); material.shader = Shader.new()
		# Vertex code prevents the renderer substituting its default depth shader.
		material.shader.code = "shader_type spatial; void vertex(){VERTEX.y += sin(VERTEX.x)*%f;} void fragment(){ALBEDO=vec3(0.6,0.3,0.2);}" % (0.01 if deferred else 0.02)
		mesh.material_override = material; stage.world.add_child(mesh); await frames(2)
		LoadingScreen.force_deferred = deferred
		LoadingScreen.begin(get_tree(),{"id":"gz3g","allod":1})
		var prepared_key := ShaderWarmup._env_key(stage)
		ShaderWarmup._warmed.clear(); ShaderWarmup.run(stage)
		LoadingScreen.end()
		var deadline := Time.get_ticks_msec()+90000
		while (ShaderCompilationScreen.active() or is_instance_valid(LoadingScreen._current)) and Time.get_ticks_msec()<deadline: await frames()
		check(not ShaderCompilationScreen.active(),"warmup completes with deferred=%s" % deferred)
		check(stage._env.ssao_enabled,"warmup restores the selected pre-PT SSAO state with deferred=%s" % deferred)
		Gfx.scene_rt_gi_active = true; Gfx.apply_env(stage._env); await frames(2)
		check(ShaderWarmup._env_key(stage) == prepared_key,"completed depth pair is reused after PT activation, deferred=%s" % deferred)
		var before := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW))
		mesh.visible = true; await frames(4)
		var after := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW))
		check(after == before,"first revealed ground needs no depth pipeline after PT disables SSAO, deferred=%s delta=%d" % [deferred,after-before])
		before = after; mesh.position.x += 0.1; await frames(4)
		check(int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)) == before,"moving after reveal needs no pipeline, deferred=%s" % deferred)
		mesh.queue_free(); await frames(2)
	LoadingScreen.force_deferred = false; Gfx.scene_rt_gi_active = false
	stage.queue_free(); await frames(4); TexUpscale.shutdown()
	print("SHADER_WARMUP_DEPTH_PASS ",checks," checks ",failures," failures")
	get_tree().quit(int(failures > 0))
