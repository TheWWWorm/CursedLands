extends Node
## Derived terrain surface maps record no push constants for the mip pipeline.
## RenderingDevice.compute_list_add_barrier replays the list's last push
## constant after rebinding the current pipeline; once the 32-byte map
## constants were set, every barrier with the constant-free mip pipeline bound
## pushed 32 bytes to it ("requires (0) bytes of push constant data" in debug
## builds, an out-of-range push in release builds), once per atlas layer.
## Every layer and mip must still be produced: a layer equals the same layer
## of a smaller job, and every mip equals the CPU average of its base level.
var checks := 0
var failures := 0

class Errors extends Logger:
	var messages: Array[String] = []
	func _log_error(fn: String, file: String, line: int, code: String, why: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind != ERROR_TYPE_WARNING: messages.append("%s %s (%s:%d %s)" % [code, why, file, line, fn])
var errors := Errors.new()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

## Original 128x128 atlas of four 64-texel tiles, different for every layer:
## a slanted ramp, a bright ridge and a dark pit, so the derived slope,
## roughness and sand channels all vary within each padded slot.
func atlas_layer(layer: int) -> Image:
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var tile := (x / 64) + 2 * (y / 64)
			var lx := x % 64; var ly := y % 64
			var v := 0.3 + 0.4 * float((lx + ly * (1 + tile) + layer * 7) % 64) / 63.0
			if absi(lx - 20 - layer) < 2: v = 0.95
			if absi(ly - 40 + tile) < 2: v = 0.05
			image.set_pixel(x, y, Color(v, v, v))
	return image

func build(layers: int) -> Texture2DArray:
	var padded: Array[Image] = []
	for layer in layers:
		var p := EITerrain.padded_atlas(atlas_layer(layer), 64, 8); p.generate_mipmaps(); padded.append(p)
	var atlas := Texture2DArray.new(); atlas.create_from_images(padded)
	return atlas

## Slot types: stone, sand, ice and grass repeat, so each layer carries every
## roughness and the sand flag.
func slot_types(layers: int) -> PackedInt32Array:
	var types := PackedInt32Array(); types.resize(layers * 4)
	for i in types.size(): types[i] = [2, 3, 10, 0][i % 4]
	return types

func _ready() -> void:
	OS.add_logger(errors)
	GameData.options.merge({"gfx_terrain":1, "gfx_materials":1, "gfx_terrain_surface":1, "auto_graphics":0, "confine_mouse":0,
		"show_fps":1, "volume_sfx":0, "volume_stream":0, "volume_voice":0}, true)
	RenderingServer.set_render_loop_enabled(true)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(3)
	check(TerrainSurfaceMaps.supported(), "Forward+ supplies the compute device for derived maps")
	var layers_read: Dictionary = {}
	if TerrainSurfaceMaps.supported():
		# Two layers (the feature test's job), three and eight (the Lost in
		# Astral weather zone that reported the error sixteen times has sixteen).
		for layers: int in [2, 3, 8]:
			var label := "%d layers" % layers
			var started := Time.get_ticks_usec()
			var maps := TerrainSurfaceMaps.create(build(layers), slot_types(layers), 2, 80)
			print("TERRAIN_SURFACE_CREATE_MS ", layers, " ", (Time.get_ticks_usec() - started) / 1000.0)
			check(maps != null, label + ": derived surface array is created")
			if maps == null: continue
			check(maps.get_layers() == layers and maps.get_width() == 160 and maps.get_height() == 160 and maps.has_mipmaps(),
				label + ": padded layout with a mip chain")
			await frames(4)
			var read: Array[PackedByteArray] = []
			for layer in layers:
				var actual := maps.get_layer_data(layer)
				check(actual != null and actual.get_width() == 160 and actual.get_mipmap_count() == 7, label + ": layer %d reads back with every mip" % layer)
				if actual == null: continue
				var bytes := actual.get_data()
				read.append(bytes)
				var base := Image.create_from_data(160, 160, false, Image.FORMAT_RGBA8, bytes.slice(0, 160 * 160 * 4))
				var sloped := 0
				for y in range(8, 72):
					for x in range(8, 72):
						var c := base.get_pixel(x, y)
						if absf(c.r - 0.5) > 0.05 or absf(c.g - 0.5) > 0.05: sloped += 1
				check(sloped > 200, label + ": layer %d carries painted relief slope (%d texels)" % [layer, sloped])
				var expected := base.duplicate() as Image; expected.generate_mipmaps()
				check(bytes == expected.get_data(), label + ": layer %d mip chain equals the CPU average of its base level" % layer)
			layers_read[layers] = read
			maps = null
			await frames(4)
		# A layer's content does not depend on the other layers of its job.
		for layers: int in [2, 3]:
			for layer in layers:
				check(layers_read.has(layers) and layers_read.has(8) and layers_read[layers][layer] == layers_read[8][layer],
					"%d-layer job layer %d equals the eight-layer job's layer" % [layers, layer])
	TerrainSurfaceMaps.shutdown()
	await frames(8)
	var pushes := errors.messages.filter(func(m: String) -> bool: return m.contains("push constant"))
	check(pushes.is_empty(), "no push constant errors: %d, %s" % [pushes.size(), JSON.stringify(pushes.slice(0, 2))])
	check(errors.messages.is_empty(), "no runtime errors: " + JSON.stringify(errors.messages.slice(0, 4)))
	OS.remove_logger(errors)
	print("TERRAIN_SURFACE_PUSH_CONSTANTS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
