extends "water_wave_render.gd"
## Exercise active numerical water history in the composed cloud/terrain/water
## programs, using the existing real-actor and exact-pixel wave controls.
## Per-feature receipts cover individual effects; this catches integration.
const COMPOSED := ["gfx_water", "gfx_water_interaction", "gfx_water_current",
	"gfx_water_caustics", "gfx_waterfalls", "gfx_water_reflections", "gfx_terrain",
	"gfx_terrain_cliffs", "gfx_ground_contact", "gfx_materials", "gfx_clouds",
	"gfx_weather_surfaces", "gfx_wind"]
var cloud_quality := 1
var terrain_quality := 1


func snap(view: SubViewport, label: String) -> Image:
	# The composed native programs specialize asynchronously. Keep the game
	# clock fixed while that first pipeline settles before exact comparisons.
	if label in ["wave-off","wave-empty"]: await frames(180)
	return await super.snap(view,label)


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--cloud-quality="): cloud_quality=clampi(int(arg.trim_prefix("--cloud-quality=")),1,3)
		elif arg.begins_with("--terrain-quality="): terrain_quality=clampi(int(arg.trim_prefix("--terrain-quality=")),0,2)
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	for key in COMPOSED: GameData.options[key]=1
	GameData.options.gfx_clouds=cloud_quality
	GameData.options.gfx_terrain=terrain_quality
	GameData.options.merge({"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":3},true)
	Gfx.ensure_globals(); Gfx.apply_surface_options()
	Engine.time_scale=0; Engine.max_fps=120; process_mode=Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	await render_case()
	check(Gfx._cloud_owner==0,"combined map exit clears shared cloud ownership")
	UnitWounds.shutdown(); TexUpscale.shutdown(); await frames(12)
	FileAccess.open("user://renderer-followup-integration.json",FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"rows":rows,"options":COMPOSED,
		"cloud_quality":cloud_quality,"terrain_quality":terrain_quality},"\t"))
	print("RENDERER_FOLLOWUP_INTEGRATION checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
