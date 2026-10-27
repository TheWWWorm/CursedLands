extends Node
## Exercise the real arena preparation, recruit card and animated world figure.
## Compilation counters detect first-use work without a machine-specific timer.
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
var rows: Array[Dictionary] = []
var out := "user://wisp-loading"
var field: ArenaPveField
var probe: DrawProbe
var watched := 0
var preparation_views := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames(count := 1) -> void:
	for i in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func pipelines() -> Vector3i:
	return Vector3i(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
		Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),
		Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH))

func _process(_dt: float) -> void:
	if not is_instance_valid(field): return
	var preview := field.find_child("WispPreparation", true, false) as Paperdoll
	if preview == null or preview.get_instance_id() == watched: return
	watched = preview.get_instance_id(); preparation_views += 1
	probe = DrawProbe.new()
	var compositor := Compositor.new(); compositor.compositor_effects = [probe]
	preview._cam.compositor = compositor

func _ready() -> void: run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH), true)
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,
		"volume_stream":0,"volume_voice":0,"vsync":0,"autosave":0}, true)
	Gfx.ensure_globals(); ShaderWarmup.enabled = true; ShaderWarmup._warmed.clear()
	if OS.get_cmdline_user_args().has("--wisp-no-roster"):
		await no_wisp_roster()
		return
	var warmer := ArenaAnimationWarmup.new(); add_child(warmer)
	var deadline := Time.get_ticks_msec() + 60000
	while warmer.task >= 0 and Time.get_ticks_msec() < deadline: await frames()
	check(warmer.task < 0, "ordinary animation catalog completes")
	check(not ArenaAnimationWarmup.ready_for("WillowispM1"), "restored wisp offer waits for material preparation")
	field = ArenaPveField.new(); field.size = Vector2(640,480); field.position = Vector2(600,100); add_child(field)
	await ShaderWarmup.arena(field); await frames(12)
	check(ArenaAnimationWarmup.ready_for("WillowispM1"), "wisp offer is released after preparation")
	check(probe != null and probe.count() >= 4, "real transparent preview completes at least four rendering-thread draws")
	check(field.find_child("WispPreparation", true, false) == null, "temporary preparation viewport is retired")
	var card := ArenaCreatureCard.new(); card.prototype = ArenaRules.prototype(1,0)
	card.position = Vector2(250,150); card.size = Vector2(240,340); add_child(card)
	await frames(24)
	for id in ["WillowispM1","WillowispM3","WillowispM5","WillowispM1"]:
		var before := pipelines(); var samples := []
		card.prototype = id; card.update_offer()
		var previous := Time.get_ticks_usec()
		for i in 24:
			await frames(); var now := Time.get_ticks_usec(); samples.append((now-previous)/1000.0); previous = now
		var model := card.preview.creature._model
		check(model != null and model._morph_parts.size() == 5, id+": all five authored animated crystals load in the real shop card")
		check(pipelines() == before, id+": recruit appearance compiles no new draw, surface or mesh pipelines")
		var phases := {}
		for part: Array in model._morph_parts: phases[part[0].material_override.get_shader_parameter("wisp_phase")] = true
		check(phases.size() == 5, id+": per-crystal phase remains independent")
		rows.append({"kind":"card","id":id,"frames_ms":samples,"pipelines_before":str(before),"pipelines_after":str(pipelines())})
	get_viewport().get_texture().get_image().save_png(out.path_join("recruited.png"))
	for id in ["WillowispM1","WillowispM3","WillowispM5"]:
		var before := pipelines()
		var model := EIUnitModel.create({"prototype":id},false)
		field.stage.add_child(model); await frames(12)
		check(model._morph_parts.size() == 5, id+": combat figure retains five animated crystals")
		check(pipelines() == before, id+": first combat appearance uses prepared pipelines")
		rows.append({"kind":"combat","id":id,"pipelines_before":str(before),"pipelines_after":str(pipelines())})
		model.queue_free(); await frames(3)
	var before := pipelines(); var old_views := preparation_views
	await ShaderWarmup.arena(field); await frames(4)
	check(pipelines() == before, "repeated arena preparation reuses the compiled programs")
	check(preparation_views == old_views, "repeated preparation allocates no wisp preview viewport")
	var shader := EIUnitModel._wisp_preview_shader; var source := shader.code
	shader.code = source + "\n// loading regression refresh\n"
	check(not ArenaAnimationWarmup.ready_for("WillowispM1"), "changed preview shader invalidates readiness")
	await ShaderWarmup.arena(field); await frames(4)
	check(ArenaAnimationWarmup.ready_for("WillowispM1"), "changed shader becomes ready after rendering")
	shader.code = source
	check(not ArenaAnimationWarmup.ready_for("WillowispM1"), "restoring prior source still invalidates a rebuilt shader resource")
	await ShaderWarmup.arena(field); await frames(4)
	check(ArenaAnimationWarmup.ready_for("WillowispM1"), "restored shader is prepared again")
	ShaderWarmup._warmed.clear()
	var cancel := ArenaPveField.new(); cancel.size = Vector2(320,240); add_child(cancel)
	ShaderWarmup.arena(cancel); await frames(); cancel.queue_free(); await frames(12)
	check(not ShaderCompilationScreen.active(), "leaving during preparation releases the compilation cover")
	check(not ArenaAnimationWarmup.ready_for("WillowispM1"), "cancelled preparation does not admit an undrawn preview")
	check(get_tree().root.find_children("WispPreparation", "", true, false).is_empty(), "cancelled preview leaves no viewport or model behind")
	await ShaderWarmup.arena(field); await frames(4)
	check(ArenaAnimationWarmup.ready_for("WillowispM1"), "re-entry completes the cancelled work")
	ShaderWarmup._warmed.clear()
	var hidden := Control.new(); hidden.hide(); add_child(hidden)
	var preparation := ShaderWarmup.new()
	if preparation.has_method("_prepare_wisp_preview"):
		preparation.call("_prepare_wisp_preview", hidden, true)
	check(ArenaAnimationWarmup.ready_for("WillowispM1"), "forced campaign preparation finishes synchronously beneath a hidden HUD")
	check(not hidden.visible, "preparing the portrait preserves the hidden HUD state")
	await frames(4)
	check(hidden.get_child_count() == 0 and not ShaderCompilationScreen.active(), "forced preparation retires its canvas and compilation owner")
	preparation.free(); hidden.queue_free()
	FileAccess.open(out.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"adapter":RenderingServer.get_video_adapter_name()},"\t")+"\n")
	card.queue_free(); field.queue_free(); warmer.queue_free(); await frames(4)
	TexUpscale.shutdown(); print("WISP_LOADING ",checks," checks ",failures," failures"); get_tree().quit(int(failures > 0))

## LiA has a different monster catalog and does not offer the base Autochess
## roster. Campaign loading must skip the absent figure without leaving a
## compilation owner or waiting for a preview that can never be constructed.
func no_wisp_roster() -> void:
	check(GameData.campaign_id == "lost_in_astral", "fixture uses the actual LiA catalog")
	check(not ArenaRules.available(), "base Autochess roster is unavailable in LiA")
	check(GameData.db.find("monster_prototypes", "WillowispM1").is_empty(), "base wisp prototype is absent in LiA")
	var parent := Control.new(); parent.hide(); add_child(parent)
	var preparation := ShaderWarmup.new()
	if preparation.has_method("_prepare_wisp_preview"): preparation.call("_prepare_wisp_preview", parent, true)
	check(parent.get_child_count() == 0, "forced preparation allocates no absent wisp")
	check(not ShaderCompilationScreen.active(), "forced preparation owns no unnecessary cover")
	if preparation.has_method("_prepare_wisp_preview"): await preparation.call("_prepare_wisp_preview", parent)
	await frames(4)
	check(parent.get_child_count() == 0, "deferred preparation allocates no absent wisp")
	check(not ShaderCompilationScreen.active(), "deferred preparation leaves no compilation owner")
	check(not parent.visible, "absent-wisp preparation preserves the hidden HUD")
	var items := []; var seen := {}
	if preparation.has_method("_add_wisp"): preparation.call("_add_wisp", items, seen, "lia-fixture")
	check(items.is_empty() and seen.is_empty(), "world preparation skips the absent wisp vertex format")
	check(ShaderWarmup._warmed.is_empty(), "absent content never marks an undrawn preview ready")
	FileAccess.open(out.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"campaign":GameData.campaign_id},"\t")+"\n")
	preparation.free(); parent.queue_free(); await frames(4)
	TexUpscale.shutdown(); print("WISP_LOADING ",checks," checks ",failures," failures"); get_tree().quit(int(failures > 0))
