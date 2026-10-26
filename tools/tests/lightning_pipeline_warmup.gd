extends Node
## Use the campaign preparation entry point, then the real native/script bolt
## builders. Pipeline counts, not a timing threshold or a warm-up stand-in,
## detect the first-use compilation on both cold and cached drivers.
const Warm = preload("res://src/game/shader_warmup.gd")

class FixtureGame extends Game:
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames(count := 1) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func changed_pixels(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, mini(a.get_height(), b.get_height()), 2):
		for x in range(0, mini(a.get_width(), b.get_width()), 2):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if maxf(absf(p.r-q.r), maxf(absf(p.g-q.g), absf(p.b-q.b))) > 0.05: count += 1
	return count

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	run.call_deferred()

func run() -> void:
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA), true)
	GameData.options.merge({"display_mode":0, "pt_mode":0, "q_aa":0,
		"gfx_water":0, "gfx_water_reflections":0, "auto_graphics":0}, true)
	Gfx.ensure_globals()
	var stage := FixtureGame.new()
	add_child(stage)
	stage.set_process(false)
	stage.world = GameWorld.new()
	stage.add_child(stage.world)
	stage.world.set_process(false)
	stage.world.set_physics_process(false)
	stage.world.set_meta("quest_bird", true)
	stage.rig = CameraRig.new()
	stage.add_child(stage.rig)
	stage.rig.set_process(false)
	var camera := stage.rig.camera
	camera.global_position = Vector3(0, 2, 5)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.1, 0.1, 0.1)
	stage.add_child(environment)
	Warm.run(stage)
	for i in 900:
		await frames()
		if Warm.last_count > 0 and not ShaderCompilationScreen.active(): break
	check(not ShaderCompilationScreen.active(), "campaign material preparation finishes")
	check(Warm.last_count > 0, "campaign preparation draws effect representatives")
	await frames(16)
	var empty := get_viewport().get_texture().get_image()
	var fx := ParticleFx.new()
	stage.add_child(fx)
	fx.set_process(false)
	var results := []
	for script in [false, true]:
		for demon in [false, true]:
			for parameter in [-7.0, 5.0, 0.0]:
				var before := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW))
				var bolt := FxLightning.new(fx, Vector3(-1, 0, 2), Vector3(1, 0, 0.8), parameter, script)
				bolt.demon = demon
				stage.add_child(bolt.node)
				bolt.draw(0.0)
				await frames(8)
				var after := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW))
				var label := "script=%s demon=%s parameter=%s" % [script, demon, parameter]
				check(after == before, "first bolt draw has no new pipeline: " + label)
				var image := get_viewport().get_texture().get_image()
				var pixels := changed_pixels(empty, image)
				check(pixels > 8, "real bolt/glow visibly draws: " + label)
				results.append({"script":script, "demon":demon, "parameter":parameter,
					"new_pipelines":after-before, "changed_pixels":pixels})
				if results.size() == 1: image.save_png("user://lightning-pipeline-first.png")
				bolt.node.queue_free()
				await frames(8)
	FileAccess.open("user://lightning-pipeline-warmup.json", FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks, "failures":failures, "rows":results}, "\t"))
	stage.queue_free()
	await frames(8)
	TexUpscale.shutdown()
	print("LIGHTNING_PIPELINE_WARMUP ", checks, " checks ", failures, " failures")
	get_tree().quit(int(failures > 0))
