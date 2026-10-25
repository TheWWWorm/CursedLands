extends "res://tools/tests/path_trace_recording_route.gd"
## Actual separate-process campaign movement with the production eye camera.
## Image readbacks are deliberate visual evidence, not a performance benchmark.
var capture_phase := ""
var capture_tick := 0
var capture_count := 0
var visual_phases := ["ruins-held", "east-opening", "downhill-path", "slope-to-boar", "look-back-uphill"]

func create_session() -> Session:
	if OS.get_cmdline_user_args().has("--route-dlss"):
		GameData.options.rtx_upscaling = 4 # Recorded DLSS Performance setting.
	return super.create_session()

func stage(label: String, seconds: float, predicate := Callable()) -> void:
	Engine.max_fps = 30
	capture_phase = label
	capture_tick = 0
	await super.stage(label, seconds, predicate)
	capture_phase = ""
	await shot("motion-" + label)
	FileAccess.open(out.path_join("motion-route-progress.json"), FileAccess.WRITE).store_string(JSON.stringify({
		"checks": checks, "failures": failures, "stages": route_results, "track": track,
		"distance": route_distance, "inactive_frames": inactive_frames, "inactive_nrd_frames": inactive_nrd_frames,
		"captured_frames": capture_count, "capture_note": "Readbacks included: frame times are not benchmark results."
	}, "\t"))

func frames(count: int) -> void:
	for i in count:
		await super.frames(1)
		if capture_phase.is_empty(): continue
		capture_tick += 1
		if capture_phase in visual_phases and capture_tick >= 40 and capture_tick < 64:
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image()
			frame.resize(1920, 1080, Image.INTERPOLATE_LANCZOS)
			frame.save_png(out.path_join("sequence-%s-%03d.png" % [capture_phase, capture_tick - 40]))
			capture_count += 1
