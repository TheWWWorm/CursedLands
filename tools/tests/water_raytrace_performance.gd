extends "res://tools/tests/water_raytrace_artifact.gd"
## Repeated interleaved samples at one frozen camera. Mirror's matched case
## uses the RT resolution and one sample; material/scene fidelity still differs.
class BeforeReflection extends Node:
	var audit: Node
	func _process(_dt: float) -> void: audit.begin_gpu()

var selected := ""
var sampling := false
var rt_gpu: Array[float] = []
var runs := []
var _rd: RenderingDevice
var _last_gpu_frame := -1
var _stamp_label := ""
var cpu_begin := 0
var controller_cpu: Array[float] = []

func begin_gpu() -> void:
	cpu_begin = Time.get_ticks_usec()
	RenderingServer.call_on_render_thread(_begin_on_render_thread.bind(selected,sampling))

func _begin_on_render_thread(label: String, collect: bool) -> void:
	if _rd == null: _rd = RenderingServer.get_rendering_device()
	var frame := _rd.get_captured_timestamps_frame()
	if frame != _last_gpu_frame:
		_last_gpu_frame = frame
		var begin := -1
		var sample_label := ""
		for i in _rd.get_captured_timestamps_count():
			var name := _rd.get_captured_timestamp_name(i)
			if name.begins_with("water-audit-begin:"):
				begin = _rd.get_captured_timestamp_gpu_time(i)
				sample_label = name.trim_prefix("water-audit-begin:")
			elif name.begins_with("water-audit-end:") and begin >= 0:
				var elapsed := (_rd.get_captured_timestamp_gpu_time(i)-begin)/1000000.0
				accept_gpu.call_deferred(sample_label,elapsed)
	_stamp_label = label if collect else ""
	_rd.capture_timestamp("water-audit-begin:"+_stamp_label)

func accept_gpu(label: String, ms: float) -> void:
	if sampling and label == selected: rt_gpu.append(ms)

func _process(_dt: float) -> void:
	if t == null: return
	if sampling and cpu_begin > 0: controller_cpu.append((Time.get_ticks_usec()-cpu_begin)/1000.0)
	RenderingServer.call_on_render_thread(_end_on_render_thread)

func _end_on_render_thread() -> void:
	if _rd != null: _rd.capture_timestamp("water-audit-end:"+_stamp_label)

func summary(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	return {"n":values.size(),"median":values[values.size()/2],"p95":values[int(values.size()*0.95)]}

func benchmark_orders() -> Array:
	return [["off","mirror_full","rt_half","mirror_half"],
		["mirror_half","rt_half","mirror_full","off"],
		["rt_half","off","mirror_half","mirror_full"]]

func benchmark_note() -> String:
	return "Frozen camera and units hidden; sun/local shadow rays and live-scene polling enabled. RT uses quarter the pixels and approximate materials. CPU bracket covers controller callbacks, not total frame work."

func run() -> void:
	var context := await setup()
	process_priority = 101
	var before := BeforeReflection.new(); before.audit = self; before.process_priority = 99; add_child(before)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var orders := benchmark_orders()
	for order in orders:
		for name: String in order:
			selected = name
			if t._reflection != null: t._reflection.set_process(true)
			var mode := 0 if name == "off" else 3 if name == "rt_half" else 2
			var prepare_start := Time.get_ticks_msec()
			GameData.options.gfx_water_reflections = mode; t.apply_gfx(); await frames(4)
			if t._reflection != null:
				RenderingServer.viewport_set_measure_render_time(t._reflection.viewport.get_viewport_rid(),true)
				if name == "mirror_full": t._reflection.viewport.msaa_3d = Viewport.MSAA_2X
			if mode == 3:
				for i in 1200:
					if t._reflection._rt_ready or t._reflection._rt_failed: break
					await frames(1)
				if not t._reflection._rt_ready:
					push_error("Hardware RT did not prepare for benchmark"); get_tree().quit(1); return
			var prepare_ms := Time.get_ticks_msec()-prepare_start
			if name == "mirror_half":
				# This camera is frozen. Keep its last reflected pose and avoid
				# resizing full -> half twice on every controller tick. Only use
				# this case's GPU pass timing; normal modes retain their controllers.
				t._reflection.set_process(false)
				t._reflection.viewport.size = Vector2i(640,360)
				t._reflection.viewport.msaa_3d = Viewport.MSAA_DISABLED
			await frames(35)
			var wall := []; var main_gpu := []; var reflection_gpu := []; var reflection_cpu := []
			rt_gpu.clear(); controller_cpu.clear(); sampling = true
			var last := Time.get_ticks_usec()
			for i in 90:
				await frames(1)
				var now := Time.get_ticks_usec(); wall.append((now-last)/1000.0); last = now
				main_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
				if mode == 2:
					var view := t._reflection.viewport.get_viewport_rid()
					reflection_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view))
					reflection_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view))
			sampling = false
			var row := {"case":name,"prepare_ms":prepare_ms,"frame_ms":summary(wall),"main_gpu_ms":summary(main_gpu),
				"reflection_gpu_ms":summary(rt_gpu.duplicate() if mode == 3 else reflection_gpu),
				"reflection_cpu_ms":summary(reflection_cpu),
				"controller_cpu_ms":summary(controller_cpu.duplicate()),
				"controller_frozen":name == "mirror_half",
				"reflection_size":str(t._reflection._rt._size) if mode == 3 else str(t._reflection.viewport.size) if mode == 2 else "none"}
			runs.append(row); print("WATER_BENCH ",JSON.stringify(row))
			FileAccess.open(out.path_join("performance.json"),FileAccess.WRITE).store_string(JSON.stringify({
				"device":RenderingServer.get_video_adapter_name(),"resolution":[1280,720],"runs":runs,
				"note":benchmark_note()},"\t"))
	set_process(false); before.queue_free()
	context[1].queue_free(); context[0].queue_free(); await frames(12); TexUpscale.shutdown()
	get_tree().quit()
