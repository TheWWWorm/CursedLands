extends "hd_resident_array.gd"
## Renderer-device HD textures record no push constants for the mip pipeline.
## RenderingDevice.compute_list_add_barrier replays the list's last push
## constant after rebinding the current pipeline; once the 16-byte upscale
## constants were set, every barrier with the constant-free mip pipeline bound
## pushed 16 bytes to it ("requires (0) bytes of push constant data" in debug
## builds, an out-of-range push in release builds). Every byte and mip must
## still match the CPU upscale.

class Errors extends Logger:
	var messages: Array[String] = []
	func _log_error(fn: String, file: String, line: int, code: String, why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind != ERROR_TYPE_WARNING: messages.append("%s %s (%s:%d %s)" % [code, why, file, line, fn])
var errors := Errors.new()


func single(label: String, source: Image, wrap: bool) -> void:
	var expected := TexUpscale.up2(source, wrap); expected.generate_mipmaps()
	var texture := TexUpscaleTexture.create(source, wrap)
	check(texture is Texture2DRD, label + " renderer-owned texture")
	if texture == null: return
	await frames(4)
	var actual := texture.get_image()
	check(actual != null and actual.get_mipmap_count() == expected.get_mipmap_count(), label + " complete mip count")
	var bytes := actual.get_data() if actual else PackedByteArray()
	check(bytes == expected.get_data(), label + " every byte/mip exact")
	texture = null
	await frames(4)


func _ready() -> void:
	OS.add_logger(errors)
	RenderingServer.set_render_loop_enabled(true)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	check(RenderingServer.get_rendering_device() != null, "renderer has a RenderingDevice (" + RenderingServer.get_current_rendering_method() + ")")
	if RenderingServer.get_rendering_device() != null:
		for size: Vector2i in [Vector2i(1, 1), Vector2i(7, 1), Vector2i(3, 5), Vector2i(32, 64)]:
			await single(str(size) + " single clamp", fixture(size, 0), false)
			await single(str(size) + " single repeat", fixture(size, 1), true)
			var sources: Array[Image] = [fixture(size, 0), fixture(size, 1), fixture(size, 2)]
			await specimen(str(size) + " array clamp", sources)
			await specimen(str(size) + " array repeat", sources, true, true)
	TexUpscale.shutdown()
	await frames(8)
	var pushes := errors.messages.filter(func(m: String) -> bool: return m.contains("push constant"))
	check(pushes.is_empty(), "no push constant errors: %d, %s" % [pushes.size(), JSON.stringify(pushes.slice(0, 2))])
	check(errors.messages.is_empty(), "no runtime errors: " + JSON.stringify(errors.messages.slice(0, 4)))
	OS.remove_logger(errors)
	print("TEX_UPSCALE_PUSH_CONSTANTS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
