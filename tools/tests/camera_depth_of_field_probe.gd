extends CompositorEffect
signal sampled(data: Dictionary)
var buffers: RenderSceneBuffersRD
var observed: Array[RID] = []

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT

func _render_callback(_kind: int, data: RenderData) -> void:
	buffers = data.get_render_scene_buffers() as RenderSceneBuffersRD

func read_buffers() -> void:
	var out := {"time": Time.get_ticks_usec() / 1e6, "allocated": false, "focus": [], "textures": {}, "previous_valid": 0}
	var rd := RenderingServer.get_rendering_device()
	for rid in observed:
		out.previous_valid += int(rd.texture_is_valid(rid))
	if buffers and buffers.has_texture("far_dof", "focus_a"):
		out.allocated = true
		observed.clear()
		for name in ["focus_a", "focus_b", "work_a", "work_b"]:
			observed.append(buffers.get_texture("far_dof", name))
			var format := buffers.get_texture_format("far_dof", name)
			out.textures[name] = [format.width, format.height, format.array_layers, format.format]
			if name.begins_with("focus"):
				var raw := rd.texture_get_data(buffers.get_texture("far_dof", name), 0)
				out.focus.append(raw.decode_float(0) if raw.size() == 4 else -1.0)
	call_deferred("emit_signal", "sampled", out)
