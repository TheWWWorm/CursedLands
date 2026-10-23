extends "res://tools/tests/water_raytrace_fsr.gd"
## Production frame generation and its FPS HUD with both ray pipelines active.
func setup() -> Array:
	var context:=await super.setup()
	GameData.options.pt_mode=2 if OS.get_cmdline_user_args().has("--pt-deep") else 1;GameData.options.q_rt_lighting=0
	if OS.get_cmdline_user_args().has("--pt-detail"):
		GameData.options.gfx_terrain=1;GameData.options.gfx_materials=1;GameData.options.gfx_foliage_light=1;GameData.options.gfx_terrain_cliffs=1
		t.apply_gfx()
	Gfx.apply_env(context[1]._env)
	return context

func sample(label: String,expect_fg: bool,expect_rt: bool) -> void:
	await super.sample(label,expect_fg,expect_rt)
	var owner: Node=t.game_world().get_parent().get_node("SceneRaytrace")
	check(owner.stats.get("active",false) and owner.stats.get("path_tracing",false),label+": path tracing remains active")
	var viewport:=camera.get_viewport()
	var internal:=Vector2i(viewport.get_visible_rect().size*viewport.scaling_3d_scale)
	var expected:=Vector2i((Vector2(internal)*0.5).round())
	check(owner.stats.get("size",[])==[expected.x,expected.y],label+": PT follows the FSR render resolution")
	check(owner.device.output.get_size()==Vector2(expected) and owner.device.guide.get_size()==Vector2(expected),label+": actual PT images resize with FSR")
	fg_rows.back()["path_tracing"]=owner.stats.duplicate()
