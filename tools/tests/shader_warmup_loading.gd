extends Node
## Real forced draws of a material set under the production loading cover.
## Limit redundant whole-world frames, then reveal the real source meshes
## and require their stationary and moving pipelines to be already ready.
class FixtureGame extends Game:
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass

class DrawProbe extends CompositorEffect:
	var mutex := Mutex.new()
	var draws := 0
	func _init() -> void: effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	func _render_callback(_kind: int, _data: RenderData) -> void:
		mutex.lock(); draws += 1; mutex.unlock()
	func count() -> int:
		mutex.lock(); var result := draws; mutex.unlock(); return result

var checks := 0
var failures := 0
var probe: DrawProbe
var progress: Array[Dictionary] = []

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

func observed(row: Dictionary) -> void:
	if row.phase == ShaderCompilationScreen.MATERIALS:
		var copy := row.duplicate(); copy.draws = probe.count()
		copy.covered = is_instance_valid(LoadingScreen._current)
		progress.append(copy)

func run() -> void:
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH), true)
	GameData.options.merge({"display_mode":0, "pt_mode":0, "q_aa":0, "gfx_water":0,
		"gfx_water_reflections":0, "auto_graphics":0, "gfx_contact_shadows":0}, true)
	Gfx.ensure_globals()
	var stage := FixtureGame.new(); add_child(stage)
	stage.world = GameWorld.new(); stage.add_child(stage.world)
	stage.world.set_process(false); stage.world.set_physics_process(false)
	stage.world.set_meta("quest_bird", true)
	stage.rig = CameraRig.new(); stage.add_child(stage.rig); stage.rig.set_process(false)
	stage.rig.camera.global_position = Vector3(0, 2, 5)
	stage.rig.camera.look_at(Vector3(0, 0, 0)); stage.rig.camera.current = true
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR; stage.add_child(environment)
	probe = DrawProbe.new(); environment.compositor = Compositor.new()
	environment.compositor.compositor_effects = [probe]
	var meshes: Array[MeshInstance3D] = []
	for i in 32:
		var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new()
		var material := ShaderMaterial.new(); material.shader = Shader.new()
		material.shader.code = "shader_type spatial; void fragment(){ALBEDO=vec3(%f,0.3,0.8);}" % (float(i+1)/33.0)
		mesh.material_override = material; mesh.visible = false
		stage.world.add_child(mesh); meshes.append(mesh)
	await frames(2)
	LoadingScreen.begin(get_tree(), {"id":"gz3g", "allod":1})
	check(is_instance_valid(LoadingScreen._current), "production loading cover is active")
	ShaderWarmup._warmed.clear()
	var initial_draws := probe.count()
	var old := ShaderCompilationScreen.on_progress; ShaderCompilationScreen.on_progress = observed
	ShaderWarmup.run(stage)
	var warm_draws := probe.count() - initial_draws
	ShaderCompilationScreen.on_progress = old
	check(ShaderWarmup.last_count >= 32, "all distinct source materials and effect representatives finish")
	check(warm_draws > 0 and warm_draws <= 40, "material preparation uses at most 40 whole-world draws: %d" % warm_draws)
	var previous := initial_draws; var completed := 0; var advances := 0; var ordered := true
	for row in progress:
		if int(row.completed) <= completed: continue
		ordered = ordered and bool(row.covered) and int(row.draws) >= previous + 4
		previous = row.draws; completed = row.completed; advances += 1
	check(ordered and advances >= 2 and completed == ShaderWarmup.last_count,
		"each progress advance follows four completed draws under the cover")
	LoadingScreen.end(); await frames(16)
	check(not ShaderCompilationScreen.active() and not is_instance_valid(LoadingScreen._current), "preparation releases its cover normally")
	for moving in [false, true]:
		var before := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW))
		for i in meshes.size():
			meshes[i].visible = true
			meshes[i].position = Vector3(float(i%8)*0.3-1.0, float(i/8)*0.3, 0.2 if moving else 0.0)
		await frames(8)
		var after := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW))
		check(after == before, "revealed source meshes need no new draw pipelines; moving=%s count=%d" % [moving, after-before])
	FileAccess.open("user://shader-warmup-loading.json", FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks, "failures":failures, "draws":warm_draws, "materials":ShaderWarmup.last_count, "progress":progress}, "\t"))
	stage.queue_free(); await frames(8); TexUpscale.shutdown()
	print("SHADER_WARMUP_LOADING ", checks, " checks ", failures, " failures")
	get_tree().quit(int(failures > 0))
