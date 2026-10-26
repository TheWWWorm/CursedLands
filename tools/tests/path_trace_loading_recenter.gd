extends "shader_compilation_scene.gd"
## Saved/direct cameras can settle after the initial snapshot starts. The
## replacement must keep the same uninterrupted loading cover until lit.
func run() -> void:
	GameData.options.merge({"pt_mode":0,"rt_shadows":0,"rt_gi":0,"fsr_upscaling":0,"fsr_frame_generation":0},true)
	var context:=await setup();campaign=context[1];campaign.rig.camera=camera
	controller=campaign.get_node("SceneRaytrace")
	GameData.options.merge({"gfx_water_reflections":0,"pt_accumulation":0,"render_scale":4},true)
	GameData._apply_window();t.apply_gfx();Gfx.apply_env(campaign._env)
	get_window().borderless=true;get_window().size=Vector2i(1280,720)
	await wait_cover_removed("initial materials")
	old_observer=Screen.on_progress;Screen.on_progress=observe_progress
	RenderingServer.frame_post_draw.connect(observe_post_draw)
	case_name="saved-camera-settles"
	controller.set_process(false)
	change_mode(1,0);controller._process(1.0/30.0)
	check(controller.device==null and (controller._gather!=null or controller._pending_scene!=null),"initial PT snapshot is pending")
	check(not controller._preparation_owner.is_empty(),"initial loading owns a preparation cover")
	var old_token: int=controller._preparation_token
	# The production camera-recenter branch cancels this real pending scene.
	camera.global_position+=Vector3(40,0,0)
	controller._process(1.0/30.0)
	check(not controller._preparation_owner.is_empty() and Screen.active(),"restored camera retains its preparation cover")
	check(controller._preparation_token>old_token,"replacement rejects the previous camera's render acknowledgment")
	controller.set_process(true)
	await wait_preparation(case_name)
	check(controller.device!=null and controller.device.nrd_active,"replacement reaches real NRD lighting before reveal")
	await finish(context)
