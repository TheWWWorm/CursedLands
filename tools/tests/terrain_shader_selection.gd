extends Node
## A fresh real map must compile only the selected terrain/water variants.
## Exercise every water option combination against the previous final source,
## including live switches, independently of the new selection helper.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	run.call_deferred()

func expected_water(fx: bool, current: bool, contact: bool, waves: bool) -> String:
	if not fx: return EITerrain.WATER_SHADER
	var code := EITerrain.WATER_FX_SHADER
	if current: code = EITerrain.WaterCurrentShader.source(code)
	if contact:
		code = EITerrain.WaterInteractionShader.source(code, current)
		if waves: code = EITerrain.WaterWaveShader.source(code)
	return code

func run() -> void:
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH), true)
	GameData.options.merge({"pt_mode":0, "rt_gi":0, "rt_shadows":0, "gfx_water_reflections":0}, true)
	Gfx.ensure_globals()
	var water_sources := {}
	for mask in 16: water_sources[expected_water(bool(mask&1),bool(mask&2),bool(mask&4),bool(mask&8))] = true
	var start := Gfx._made.size()
	var terrain := EITerrain.load_map("zone8")
	check(terrain != null, "real Ingos terrain loads")
	if terrain == null: finish(); return
	var created := 0
	for i in range(start,Gfx._made.size()):
		if water_sources.has(Gfx._made[i][1]): created += 1
	check(created == 1, "fresh loading creates exactly the selected water shader, got %d" % created)
	check(terrain._land_mat.shader.code == Gfx.compose(terrain.land_shader_source(),true,true), "ground retains its complete selected effects")
	var shape := terrain.heights.duplicate(); var navigation := terrain.water.duplicate()
	var selected := {}
	for mask in 16:
		GameData.options.merge({"gfx_water":int(bool(mask&1)), "gfx_water_current":int(bool(mask&2)),
			"gfx_water_interaction":int(bool(mask&4)), "gfx_water_waves":int(bool(mask&8))},true)
		terrain.apply_gfx()
		var expected := expected_water(bool(mask&1),bool(mask&2),bool(mask&4),bool(mask&8))
		check(terrain._water_mat.shader.code == Gfx.compose(expected,true,true), "unchanged final shader for water options %d" % mask)
		if selected.has(expected):
			check(selected[expected] == terrain._water_mat.shader, "returning to a water variant reuses its program %d" % mask)
		selected[expected] = terrain._water_mat.shader
		check(terrain._water_mat.get_shader_parameter("atlases") == terrain._atlases \
			and terrain._water_mat.get_shader_parameter("level") == terrain._level, "live water samplers and levels remain bound %d" % mask)
		var current := bool(mask&1) and bool(mask&2)
		check((terrain._current != null) == current, "current field follows selected options %d" % mask)
		if current:
			check(terrain._water_mat.get_shader_parameter("water_current") == terrain._current.texture, "current texture survives final shader assignment %d" % mask)
	check(shape == terrain.heights and navigation == terrain.water, "shader selection preserves original terrain and navigation")
	terrain.free(); await get_tree().process_frame; finish()

func finish() -> void:
	TexUpscale.shutdown()
	print("TERRAIN_SHADER_SELECTION ",checks," checks ",failures," failures")
	get_tree().quit(int(failures > 0))
