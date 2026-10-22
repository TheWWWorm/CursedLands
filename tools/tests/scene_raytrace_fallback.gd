extends "res://tools/tests/water_raytrace_artifact.gd"
## Unqualified renderers retain the world, with no live lighting resources.
## --baseline-only also records validation for the same scene with RT off.
func run() -> void:
	var context:=await setup();var game: Game=context[1]
	var rt: Node=game.get_node("SceneRaytrace")
	GameData.options.gfx_water_reflections=0;t.apply_gfx();await frames(12)
	check(rt.device==null and not rt.stats.get("active",false),"conventional baseline has no scene RT resources")
	if not OS.get_cmdline_user_args().has("--baseline-only"):
		GameData.options.rt_shadows=1;GameData.options.rt_gi=1;Gfx.apply_env(game._env);await frames(20)
		check(rt.device==null and not rt.stats.get("active",false) and rt.stats.get("fallback","")=="unsupported","unsupported renderer stays on conventional lighting")
		check(not Gfx.scene_rt_gi_active,"unavailable RT does not suppress ordinary ambient effects")
		GameData.options.pt_mode=2;Gfx.apply_env(game._env);await frames(20)
		check(rt.device==null and rt.stats.get("fallback","")=="unsupported","unsupported renderer keeps conventional lighting with path mode saved")
		check(not Gfx.scene_rt_gi_active,"unavailable path tracing preserves ordinary ambient effects")
	await shot("conventional-fallback")
	FileAccess.open(out.path_join("scene-fallback.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stats":rt.stats},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("SCENE_RT_FALLBACK ",checks," checks ",failures.size()," failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
