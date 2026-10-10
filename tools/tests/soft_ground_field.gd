extends Node
## Shared GPU footprint storage: growth, pending/installed tiles, layer reuse,
## clear and a shader that keeps the same resources bound across all changes.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func stamp(value: float) -> Image:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBAF)
	image.fill(Color(value, value * 0.5, 0, 1))
	return image

func dense_fixture() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var colors := PackedColorArray()
	colors.resize(8 * 153) # Eight parents, each with the native 16-way lattice.
	colors.fill(Color(0, 0, 0, 0))
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays

func capture(view: SubViewport) -> Image:
	for i in 3:
		RenderingServer.force_draw()
		await get_tree().process_frame
	return view.get_texture().get_image()

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("SOFT_GROUND_FIELD requires a real renderer")
		get_tree().quit(2)
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var field := SoftGroundField.new(64, 32)
	var rid := field.texture.get_rid()
	var tile_rid := field.tiles.get_rid()
	var clock_rid := field.clock.get_rid()
	var view := SubViewport.new()
	view.size = Vector2i(64, 32)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var rect := ColorRect.new()
	rect.size = view.size
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """shader_type canvas_item;
uniform sampler2DArray tracks : filter_nearest, repeat_disable;
uniform sampler2D tiles : filter_nearest, repeat_disable;
uniform sampler2D clock : filter_nearest, repeat_disable;
void fragment() {
	vec2 state=texture(tiles,UV).rg;
	float sample_value=state.r>0.0 ? texture(tracks,vec3(vec2(0.5),state.r-1.0)).r : 0.0;
	COLOR=vec4(sample_value,state.g,texture(clock,vec2(0.5)).r/100.0,1.0);
}"""
	mat.set_shader_parameter("tracks", field.texture)
	mat.set_shader_parameter("tiles", field.tiles)
	mat.set_shader_parameter("clock", field.clock)
	rect.material = mat
	view.add_child(rect)
	var original: Array[Image] = []
	for i in 8:
		var key := Vector2i(i % 4, i / 4)
		var image := stamp((i + 1) * 0.1)
		original.append(image)
		check(field.allocate(key, image) == i, "new layer " + str(i))
		check(field.texture.get_rid() == rid, "growth preserves bound RID " + str(i))
		check(field._images[i] == image, "no retained CPU copy " + str(i))
		check(field._tile_image.get_pixelv(key * 16).r == 0, "pending mesh not exposed " + str(i))
		field.install(key, {0: dense_fixture(), 17: null})
		field.flush(12.0)
		var pixels := await capture(view)
		for j in range(i + 1):
			var origin := Vector2i(j % 4, j / 4) * 16
			var colour := pixels.get_pixelv(origin)
			check(absf(colour.r - (j + 1) * 0.1) < 0.006, "shader retains layer after growth " + str(j))
			check(colour.g > 0.99 and absf(colour.b - 0.12) < 0.006, "dense flag/shared clock " + str(j))
			check(pixels.get_pixelv(origin + Vector2i.ONE).g < 0.01, "queued tile stays coarse " + str(j))
	check(field.texture.get_layers() == 8, "bounded capacity")
	original[3].fill(Color(0.92, 0, 0, 1))
	field.update(Vector2i(3, 0))
	check(absf((await capture(view)).get_pixel(48, 0).r - 0.92) < 0.006, "updates original CPU image layer")
	field.release(Vector2i(1, 0))
	field.flush(25.0)
	var pixels := await capture(view)
	check(pixels.get_pixel(16, 0).r < 0.01 and pixels.get_pixel(16, 0).g < 0.01, "eviction hides old sector")
	var replacement := stamp(0.33)
	check(field.allocate(Vector2i(1, 0), replacement) == 1, "reuse vacant layer")
	field.install(Vector2i(1, 0), {17: dense_fixture()})
	field.flush(25.0)
	pixels = await capture(view)
	check(absf(pixels.get_pixel(17, 1).r - 0.33) < 0.006 and pixels.get_pixel(17, 1).g > 0.99, "replacement renders new contents")
	check(pixels.get_pixel(16, 0).g < 0.01, "replacement has no retired dense tiles")
	field.uninstall(Vector2i(1, 0))
	field.flush(25.0)
	check((await capture(view)).get_pixel(17, 1).r < 0.01, "capacity reset uninstalls without releasing layer")
	for key: Vector2i in field._slots.keys():
		field.release(key)
	field.flush(25.0)
	check(field._images.is_empty() and field.texture.get_width() == 1 and field.texture.get_layers() == 1, "clear releases peak storage")
	check(field.texture.get_rid() == rid and field.tiles.get_rid() == tile_rid and field.clock.get_rid() == clock_rid, "clear preserves resource bindings")
	check((await capture(view)).get_pixel(0, 0).r < 0.01, "empty field samples no old layer")
	check(field.allocate(Vector2i.ZERO, stamp(0.61)) == 0, "reuse after clear")
	field.install(Vector2i.ZERO, {0:dense_fixture()})
	field.flush(42.0)
	pixels = await capture(view)
	check(absf(pixels.get_pixel(0, 0).r - 0.61) < 0.006 and absf(pixels.get_pixel(0, 0).b - 0.42) < 0.006, "existing material sees new storage after clear")
	view.free()
	print("SOFT_GROUND_FIELD checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
