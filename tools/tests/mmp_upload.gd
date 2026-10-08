extends Node
## Real-renderer check: compressed uploads must match independently uploaded
## RGBA copies of authored mips. BC1/2 GPU interpolation differs from CPU
## bcdec, notably NVIDIA green (up to 6/255); do not demand byte equality.
## See https://fgiesen.wordpress.com/2021/10/04/gpu-bcn-decoding/ .
var failures := 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("MMP_UPLOAD requires a real rendering backend")
		get_tree().quit(2)
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	Engine.max_fps = 30
	var view := SubViewport.new()
	view.size = Vector2i(384, 1152)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.gui_disable_input = true
	add_child(view)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D source_tex : source_color, filter_nearest_mipmap, repeat_disable;
uniform float mip = 0.0;
void fragment() { COLOR = textureLod(source_tex, UV, mip); }
"""
	var names := ["govenorhouse00", "tree02", "rikarrowsmoke"]
	var row := 0
	var formats := []
	var compressed_rows := []
	for name: String in names:
		var data := GameData.textures.read(name + ".mmp")
		var candidate := EIMmp.decode_texture(data, RenderingServer.has_os_feature("s3tc"))
		var reference := EIMmp.decode_texture(data, false)
		if candidate == null or reference == null:
			printerr("FAIL upload fixture ", name)
			get_tree().quit(1)
			return
		formats.append(candidate.get_format())
		var uploaded := ImageTexture.create_from_image(candidate)
		for mip in [0, 2, data.decode_u32(12) - 1, candidate.get_mipmap_count()]:
			# Authored levels use the independent source decode. For the
			# newly encoded tail, compare the same blocks decoded on CPU.
			var expected := reference
			if mip >= data.decode_u32(12):
				expected = candidate.duplicate() as Image
				if expected.is_compressed():
					expected.decompress()
			var textures := [uploaded, ImageTexture.create_from_image(expected)]
			compressed_rows.append(candidate.is_compressed())
			for column in 2:
				var rect := ColorRect.new()
				rect.position = Vector2(column * 192, row * 96)
				rect.size = Vector2(192, 96)
				var material := ShaderMaterial.new()
				material.shader = shader
				material.set_shader_parameter("source_tex", textures[column])
				material.set_shader_parameter("mip", mip)
				rect.material = material
				view.add_child(rect)
			row += 1
	for i in 8:
		RenderingServer.force_draw()
		await get_tree().process_frame
	var image := view.get_texture().get_image()
	var errors := []
	var maximum := 0.0
	for y in image.get_height():
		for x in 192:
			var a := image.get_pixel(x, y)
			var b := image.get_pixel(x + 192, y)
			var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
			maximum = maxf(maximum, delta)
			var tolerance := 6.01 / 255.0 if compressed_rows[y / 96] else 0.01 / 255.0
			if delta > tolerance:
				failures += 1
				if errors.size() < 8:
					errors.append([x, y, delta])
	var method := RenderingServer.get_current_rendering_method()
	var output := "user://mmp-upload-" + method + ".png"
	if image.save_png(output) != OK:
		failures += 1
	print("MMP_UPLOAD ", JSON.stringify({"failures": failures, "max_channel_delta": maximum,
			"errors": errors, "renderer": method, "adapter": RenderingServer.get_video_adapter_name(),
			"formats": formats, "s3tc": RenderingServer.has_os_feature("s3tc"),
			"editor": OS.has_feature("editor"),
			"image": ProjectSettings.globalize_path(output)}))
	view.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
