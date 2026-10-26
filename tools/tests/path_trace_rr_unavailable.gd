extends "res://tools/tests/path_trace_camera_routes.gd"
## Start with standard DLSS/SR DLLs but without sl.dlss_d/nvngx_dlssd. This is
## a real missing-runtime fallback, not a fabricated capabilities dictionary.
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	var native:=RtxGraphics.bridge()
	check(native!=null and RtxGraphics.facts().sr and not RtxGraphics.facts().rr,"missing RR plugin preserves real DLSS SR availability")
	if native==null or not RtxGraphics.facts().sr:finish_unavailable([]);return
	resolution=Vector2i(1280,720)
	GameData.options.merge({"rtx_upscaling":2,"rtx_frame_generation":0,"pt_ray_reconstruction":1,"pt_denoiser":1},true)
	var context:=await setup_route()
	if context.is_empty():finish_unavailable(context);return
	GameData.options.fps_limit=1;GameData._apply_window();Engine.max_fps=30
	var rt: Node=context[1].get_node("SceneRaytrace")
	check(await ready_scene(rt),"unsupported saved RR request prepares normal campaign PT")
	check(rt.device!=null and rt.device.nrd_active and rt.device.nrd.directional,"missing RR runtime falls back to selected directional NRD")
	check(rt._rr_effect==null and camera.compositor==null and not rt._rr_active,"fallback does not attach an incomplete RR callback")
	var before: Dictionary=native.call("get_status");await frames(20)
	var after: Dictionary=native.call("get_status")
	check(after.dlss_evaluations>before.dlss_evaluations and after.rr_evaluations==0,"SR evaluates while RR count stays zero")
	check(RtxGraphics.reason(RtxGraphics.RAY_RECONSTRUCTION)==RtxGraphics.NEED_RR,"settings explain the unavailable RR runtime")
	await shot("rr-unavailable-fallback")
	FileAccess.open(out.path_join("rr-unavailable-status.json"),FileAccess.WRITE).store_string(JSON.stringify(after,"\t"))
	await finish_unavailable(context)
func finish_unavailable(context: Array) -> void:
	if context.size()==2:context[1].queue_free();context[0].queue_free()
	await frames(16);TexUpscale.shutdown()
	FileAccess.open(out.path_join("rr-unavailable.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("PT_RR_UNAVAILABLE ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
