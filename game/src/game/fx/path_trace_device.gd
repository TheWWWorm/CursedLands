extends "res://src/game/fx/scene_raytrace_device.gd"
## Same scene and stable texture lifetime as RT lighting. Channels become
## diffuse illumination, normal/depth, glossy radiance and albedo/roughness.
const PATH_FILTER = preload("res://src/game/fx/shaders/path_trace_filter.glsl")
func shader_prefix() -> String: return "res://src/game/fx/shaders/path_trace_"
func frame_bytes() -> int: return 656
func filter_spirv() -> RDShaderSPIRV: return PATH_FILTER.get_spirv()
