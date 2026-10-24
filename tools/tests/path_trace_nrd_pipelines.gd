extends Node
const ROOT := "res://src/game/fx/shaders/nrd/"
signal completed
var passed := true
func _ready() -> void:run.call_deferred()
func compile_shader(name: String) -> void:
	print("NRD_PIPELINE_BEGIN ",name)
	var rd:=RenderingServer.get_rendering_device()
	var spirv:=RDShaderSPIRV.new();spirv.bytecode_compute=FileAccess.get_file_as_bytes(name if name.is_absolute_path() else ROOT+name+".spv")
	var shader:=rd.shader_create_from_spirv(spirv,"NRD pipeline test "+name)
	var pipeline:=rd.compute_pipeline_create(shader)
	passed=passed and shader.is_valid() and pipeline.is_valid()
	if pipeline.is_valid():rd.free_rid(pipeline)
	if shader.is_valid():rd.free_rid(shader)
	print("NRD_PIPELINE_END ",name)
	completed.emit.call_deferred()
func run() -> void:
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"build.json"))
	var names: Array=manifest.layouts.keys();names.sort()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--nrd-shader="):names=[arg.trim_prefix("--nrd-shader=")]
	for name: String in names:
		RenderingServer.call_on_render_thread(compile_shader.bind(name));await completed
		for i in 4:await get_tree().process_frame
	print("NRD_PIPELINES ",names.size()," checks ",0 if passed else 1," failures")
	get_tree().quit(0 if passed else 1)
