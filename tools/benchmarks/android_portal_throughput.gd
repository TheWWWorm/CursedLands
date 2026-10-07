extends Node

func _ready() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://bench.json"))
	var backend = Engine.get_singleton("EISimulation")
	var path := "user://"+String(cfg.name)+"-simulation.json"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	# A blank frontend must not compete with the headless simulation for CPU/GPU.
	Engine.max_fps = 10
	RenderingServer.set_render_loop_enabled(false)
	var args := PackedStringArray(["--headless","--render-thread","safe","--audio-driver","Dummy","--max-fps","60","--","--ei-path="+GameData.root,"--tool=user://portal_throughput.gd"])
	var handle: int = backend.start(args)
	var deadline := Time.get_ticks_msec()+240000
	while backend.is_running(handle) and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	var ok: bool = handle>0 and FileAccess.file_exists(path) and not backend.is_running(handle)
	print("ANDROID_THROUGHPUT ",JSON.stringify({"ok":ok,"error":backend.last_error()}))
	if not ok:
		push_error("Headless throughput failed"); backend.stop(handle)
	get_tree().quit(0 if ok else 1)
