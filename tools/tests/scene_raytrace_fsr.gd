extends "res://tools/tests/water_raytrace_fsr.gd"
## Keep the production upscaler/frame-generation gate and measured FPS HUD
## regression while tracing both water reflections and main-scene lighting.
func setup() -> Array:
	var context := await super.setup()
	GameData.options.rt_shadows=1;GameData.options.rt_gi=1;GameData.options.q_rt_lighting=0
	Gfx.apply_env(context[1]._env)
	return context

func sample(label: String,expect_fg: bool,expect_rt: bool) -> void:
	await super.sample(label,expect_fg,expect_rt)
	var owner: Node = t.game_world().get_parent().get_node("SceneRaytrace")
	check(owner.stats.get("active",false),label+": scene RT shadows and GI remain active")
