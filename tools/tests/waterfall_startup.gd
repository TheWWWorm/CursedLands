extends Node
## High-quality save loading constructs terrain before attaching it. Exercise
## that order, including restored water levels and the live option path.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func _ready() -> void:
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH),true)
	GameData.options.merge({"auto_graphics":0,"vsync":0,"confine_mouse":0},true)
	Gfx.ensure_globals()
	var zone := CampaignMap.load_from(GameData.texts).zone("gz11k")
	var terrain := EITerrain.load_map(zone.mpr)
	check(terrain != null,"original gz11k terrain loads with waterfall graphics enabled")
	if terrain == null: get_tree().quit(1); return
	var helper = terrain._waterfalls
	check(helper != null,"high preset creates the terrain-owned waterfall controller")
	if helper == null: terrain.free(); get_tree().quit(1); return
	var navigation := terrain.water.duplicate()
	var heights := terrain.heights.duplicate()
	check(not helper.field.falls.is_empty(),"the affected original map contains real waterfall sites")
	if helper.field.falls.is_empty(): terrain.free(); get_tree().quit(1); return
	check(helper.rebuilds == 0 and helper.get_child_count() == 0,"off-tree construction does not sample global transforms or allocate spray")
	var owner: int = helper.field.falls[0].top_owner
	terrain.set_water_offset(owner,0.1)
	terrain.set_water_offset(owner,0.2)
	await get_tree().process_frame
	check(helper._dirty and helper.rebuilds == 0,"deferred refresh retains saved levels until attachment")
	add_child(terrain); terrain.set_process(false)
	check(helper.rebuilds == 1 and not helper._dirty and helper.visible,"attachment consumes the pending refresh and builds once")
	check(helper.field.levels == terrain._level and absf(helper.field.levels[owner]-0.2)<0.001,"initial geometry uses restored water levels")
	check(helper.shell_vertices > 0 and helper.sprites > 0,"attached real waterfalls retain both foam and spray")
	await get_tree().process_frame
	check(helper.rebuilds == 1,"old deferred refresh cannot rebuild the attached terrain twice")
	terrain.set_water_offset(owner,0.0)
	await get_tree().process_frame
	check(helper.rebuilds == 2 and helper.visible and helper.field.levels == terrain._level,"live water level changes still refresh the effects")
	var original_sites: Array = helper.field.falls.duplicate(true)
	GameData.options.gfx_waterfalls=0; terrain.apply_gfx()
	check(terrain._waterfalls == null,"disabling waterfalls releases their controller")
	GameData.options.gfx_waterfalls=1; terrain.apply_gfx()
	helper=terrain._waterfalls
	check(helper != null and helper.rebuilds == 1 and helper.sprites > 0,"enabling the option on attached terrain builds immediately")
	check(helper.field.falls == original_sites,"live enabling retains the authored waterfall classification")
	check(terrain.heights == heights and terrain.water == navigation,"presentation changes preserve terrain and navigation")
	terrain.free()
	TexUpscale.shutdown()
	print("WATERFALL_STARTUP %d checks %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
