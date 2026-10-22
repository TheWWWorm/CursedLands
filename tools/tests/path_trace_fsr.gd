extends "res://tools/tests/water_raytrace_fsr.gd"
## Production frame generation and its FPS HUD with both ray pipelines active.
func setup() -> Array:
	var context:=await super.setup()
	GameData.options.pt_mode=1;GameData.options.q_rt_lighting=0
	Gfx.apply_env(context[1]._env)
	return context

func sample(label: String,expect_fg: bool,expect_rt: bool) -> void:
	await super.sample(label,expect_fg,expect_rt)
	var owner: Node=t.game_world().get_parent().get_node("SceneRaytrace")
	check(owner.stats.get("active",false) and owner.stats.get("path_tracing",false),label+": path tracing remains active")
