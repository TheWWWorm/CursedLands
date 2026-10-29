extends Node
## Creating shader modules alone does not compile a Vulkan ray-tracing
## pipeline. Exercise every terrain hit variant, including camera transmission.
const Programs=preload("res://src/game/fx/raytrace_programs.gd")
signal compiled
var checks:=0
var failures: Array[String]=[]

func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func compile_programs() -> void:
	var rd:=RenderingServer.get_rendering_device()
	check(rd!=null,"rendering device is available")
	if rd==null:compiled.emit.call_deferred();return
	var programs:=Programs.new()
	var prefix:="res://src/game/fx/shaders/path_trace_"
	var directx:=RenderingServer.get_current_rendering_driver_name()=="d3d12"
	for transmission: bool in [false,true]:
		for terrain: String in ["","_terrain","_transitions","_terrain_maps","_transitions_maps"]:
			var hit:="closest_hit"+terrain+("_transmission" if transmission else "")
			var paths:={
				RenderingDevice.SHADER_STAGE_RAYGEN:prefix+("raygen_transmission_no_emitters" if transmission else "raygen_no_emitters"),
				RenderingDevice.SHADER_STAGE_MISS:prefix+"miss",
				RenderingDevice.SHADER_STAGE_CLOSEST_HIT:prefix+hit,
				RenderingDevice.SHADER_STAGE_ANY_HIT:prefix+"any_hit",
			}
			print("PT_PROGRAM_BEGIN ",hit)
			var shader: RID=programs.program(rd,paths,directx)
			check(shader.is_valid(),hit+" shader module")
			var wrapper:=RDPipelineShader.new();wrapper.shader=shader
			var pipeline: RID=programs.pipeline(wrapper) if shader.is_valid() else RID()
			check(pipeline.is_valid(),hit+" native pipeline")
			check(programs.program(rd,paths,directx)==shader,hit+" reuses its shader")
			check(pipeline.is_valid() and programs.pipeline(wrapper)==pipeline,hit+" reuses its pipeline")
	programs.dispose()
	compiled.emit.call_deferred()

func _ready() -> void:
	RenderingServer.call_on_render_thread(compile_programs)
	await compiled
	print("PT_PROGRAMS ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
