extends Node
## Production ground-contact shaders, world ownership, material sharing,
## option/fade lifetime and actual rendered band behavior.
var checks := 0
var failures := 0
var rows: Array[Dictionary] = []
const SIZE := 256

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", label)

func texture(colour: Color, format := Image.FORMAT_RGBAF, size := 1) -> ImageTexture:
	var image := Image.create(size, size, false, format)
	image.fill(colour)
	return ImageTexture.create_from_image(image)

func terrain_fixture() -> EITerrain:
	var terrain := EITerrain.new()
	terrain.sectors_x = 1; terrain.sectors_y = 1; terrain.grid_w = 33
	terrain.heights.resize(33 * 33); terrain.heights.fill(0.0)
	terrain.land_xy.resize(33 * 33); terrain.land_xy.fill(Vector2.ZERO)
	terrain.land_n.resize(33 * 33); terrain.land_n.fill(Vector3.UP)
	# The production contact data reads the source sector arrays, including
	# ArrayMesh normal packing and sector-owned light input bytes.
	var sector := EITerrainSector.new(); sector.name = "Sector_0_0"
	sector._arrays.resize(Mesh.ARRAY_MAX)
	var normals := PackedVector3Array(); normals.resize(16*16*9); normals.fill(Vector3.UP)
	var colors := PackedColorArray(); colors.resize(16*16*9); colors.fill(Color(0,0,0,0))
	sector._arrays[Mesh.ARRAY_NORMAL] = normals
	sector._arrays[Mesh.ARRAY_COLOR] = colors
	terrain.add_child(sector)
	terrain._land_mat = ShaderMaterial.new()
	terrain._land_mat.shader = Gfx.make_shader(EITerrain.TERRAIN_SHADER, true, true)
	var atlas := Texture2DArray.new()
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.65, 0.3)); image.generate_mipmaps()
	atlas.create_from_images([image])
	terrain._land_mat.set_shader_parameter("atlases", atlas)
	terrain._land_mat.set_shader_parameter("terrain_tiles", texture(Color(0, 0, 0, 0), Image.FORMAT_RGF, 16))
	terrain._land_mat.set_shader_parameter("terrain_cells", texture(Color(-100, 0, 0, 0), Image.FORMAT_RGBAF, 32))
	terrain._land_mat.set_shader_parameter("rain_cover", texture(Color(-100, 0, 0, 0), Image.FORMAT_RF, 32))
	terrain._land_mat.set_shader_parameter("macro_tex", texture(Color(0.5, 0.5, 0.5)))
	var level := PackedFloat32Array(); level.resize(64); level.fill(0)
	terrain._land_mat.set_shader_parameter("level", level)
	return terrain

func base_material(foliage := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var source := EIFigure.FOLIAGE_SHADER if foliage else EIFigure.OBJECT_SHADER
	material.shader = Gfx.make_shader(source)
	material.set_meta("ground_contact_source", source)
	material.set_shader_parameter("albedo_tex", texture(Color(0.7, 0.05, 0.03), Image.FORMAT_RGBA8))
	material.set_shader_parameter("wind", 0.0)
	material.set_shader_parameter("foliage_mask", texture(Color(0, 0, 0)))
	return material

func object_fixture(parent: Node, base: Material, size := Vector2(2, 2)) -> MeshInstance3D:
	var root := Node3D.new(); parent.add_child(root)
	var node := MeshInstance3D.new()
	var mesh := QuadMesh.new(); mesh.size = size
	node.mesh = mesh; node.material_override = base
	root.add_child(node)
	node.position = Vector3(16, 1, -16)
	return node

func owner_fixture(terrain: EITerrain) -> GroundContact:
	var owner := GroundContact.new()
	owner.terrain = terrain; terrain.contact = owner; terrain.add_child(owner)
	return owner

func ownership() -> void:
	GameData.options["gfx_ground_contact"] = 1
	var terrain := terrain_fixture(); add_child(terrain)
	var owner := owner_fixture(terrain)
	var base := base_material(true)
	var one := object_fixture(terrain, base)
	var two := object_fixture(terrain, base)
	var small := object_fixture(terrain, base, Vector2(0.4, 0.4))
	owner.register(one.get_parent()); owner.register(two.get_parent()); owner.register(small.get_parent())
	var contact := one.material_override as ShaderMaterial
	check(contact != base and contact == two.material_override, "same world/base/bounds share contact material")
	if RenderingServer.get_current_rendering_method() == "mobile":
		var original_contact := Gfx.make_shader(GroundContactShader.source(base.get_meta("ground_contact_source")))
		check(contact.shader.code == original_contact.code, "Mobile owner retains its exact original contact program")
	check(small.material_override != contact, "small parts keep proportionate band")
	check(contact.get_shader_parameter("contact_extent") == Vector3(2, 2, 0), "exact mesh bounds passed to shader")
	check(contact.get_shader_parameter("albedo_tex") == base.get_shader_parameter("albedo_tex"), "original atlas shared")
	var terrain2 := terrain_fixture(); add_child(terrain2)
	var owner2 := owner_fixture(terrain2)
	var other := object_fixture(terrain2, base); owner2.register(other.get_parent())
	check(other.material_override != contact, "worlds cannot share field-bound materials")
	check(other.material_override.get_shader_parameter("query_vertices") != contact.get_shader_parameter("query_vertices"), "worlds own different field textures")
	var untouched := object_fixture(terrain, base)
	check(untouched.material_override == base, "unregistered models keep original material")
	var relabelled := object_fixture(terrain, base)
	owner.register(relabelled.get_parent())
	var labels := StandardMaterial3D.new()
	relabelled.material_override = labels
	owner.refresh()
	check(relabelled.material_override == labels and not owner._meshes.has(relabelled.get_instance_id()), "later menu/custom material keeps ownership during enabled refresh")
	var replaced := object_fixture(terrain, base)
	owner.register(replaced.get_parent())
	var replacement := base_material()
	replaced.material_override = replacement
	owner.refresh()
	check(replaced.material_override != replacement and owner._meshes[replaced.get_instance_id()].base == replacement, "later eligible scenery material becomes the new contact base")
	check(replaced.material_override.get_shader_parameter("albedo_tex") == replacement.get_shader_parameter("albedo_tex"), "replacement scenery parameters reach its contact variant")
	var fade := CameraFade.new()
	fade._nodes.append(one.get_parent()); fade._meshes.append([one])
	fade._set_alpha(0, 0.375)
	check(one.has_meta("cam_fade_mat") and one.material_override != contact, "normal camera fade applies")
	fade._nodes.append(replaced.get_parent()); fade._meshes.append([replaced])
	fade._set_alpha(1, 0.625)
	replacement = base_material(true)
	replacement.set_shader_parameter("wind", 0.625)
	GroundContact._replace(replaced, replacement)
	owner.refresh()
	var replacement_alpha: float = replaced.material_override.get_shader_parameter("cam_fade") if Portability.compatibility() else replaced.get_instance_shader_parameter("cam_fade")
	check(owner._meshes[replaced.get_instance_id()].base == replacement and replaced.get_meta("cam_fade_mat") != replacement, "a replaced fading scenery base receives its own contact variant")
	check(is_equal_approx(replacement_alpha, 0.625) and is_equal_approx(replaced.material_override.get_shader_parameter("wind"), 0.625), "replacement retains active fade and new material parameters")
	fade._set_alpha(1, 0.0)
	base.set_shader_parameter("wind", 0.75)
	owner.refresh()
	var alpha: float = one.material_override.get_shader_parameter("cam_fade") if Portability.compatibility() else one.get_instance_shader_parameter("cam_fade")
	check(is_equal_approx(alpha, 0.375), "refresh preserves active fade")
	check(is_equal_approx(one.material_override.get_shader_parameter("wind"), 0.75), "wind updates active fade")
	var levels := PackedFloat32Array(); levels.resize(64); levels.fill(0.3)
	terrain._land_mat.set_shader_parameter("level", levels); owner.refresh_parameters()
	check(one.material_override.get_shader_parameter("level") == levels, "water change reaches active fade")
	var old_field: WeakRef = weakref(owner.surface.vertices)
	GameData.options["gfx_ground_contact"] = 0
	owner.refresh()
	check(one.get_meta("cam_fade_mat") == base and two.material_override == base and small.material_override == base, "option off restores exact originals")
	check(relabelled.material_override == labels and replaced.material_override == replacement, "option off preserves later custom and eligible material replacements")
	var label_after_registration := object_fixture(terrain, base)
	owner.register(label_after_registration.get_parent())
	label_after_registration.material_override = labels
	owner.refresh()
	check(label_after_registration.material_override == labels, "unrelated option refresh cannot restore a stale base while contact is off")
	check(not CameraFade._derived.has(contact) and not CameraFade._shaders.has(contact.shader), "option off removes world materials from global fade cache")
	contact = null
	check(old_field.get_ref() == null, "option off releases static field")
	fade._set_alpha(0, 0.0)
	check(one.material_override == base, "fade completion restores original while off")
	GameData.options["gfx_ground_contact"] = 1
	owner.refresh()
	contact = one.material_override
	check(relabelled.material_override == labels and label_after_registration.material_override == labels, "re-enabling contact leaves relinquished menu materials intact")
	fade._set_alpha(0, 0.4)
	old_field = weakref(owner.surface.vertices)
	terrain.free()
	check(not CameraFade._derived.has(contact) and not CameraFade._shaders.has(contact.shader), "world removal clears global derived cache")
	contact = null
	check(old_field.get_ref() == null, "world removal releases static textures")
	terrain2.free()
	var cfg := ConfigFile.new()
	check(GameData.ground_effect_defaults(cfg).gfx_ground_contact == 0, "unproven first-use cost keeps desktop opt-in")
	check(GameData.ground_effect_defaults(cfg, {"gfx_ground_contact":0}).gfx_ground_contact == 0, "constrained platform default off")
	cfg.set_value("options", "gfx_terrain", 0)
	check(GameData.ground_effect_defaults(cfg).gfx_ground_contact == 0, "existing Original look preserved")
	cfg.set_value("options", "gfx_ground_contact", 1)
	check(GameData.ground_effect_defaults(cfg, {"gfx_ground_contact":0}).gfx_ground_contact == 1, "explicit saved choice wins")

func capture(view: SubViewport) -> Image:
	for i in 3:
		RenderingServer.force_draw()
		await get_tree().process_frame
	return view.get_texture().get_image()

func compare(a: Image, b: Image, area: Rect2i) -> Dictionary:
	var count := 0; var peak := 0.0; var total := 0.0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var ca := a.get_pixel(x, y); var cb := b.get_pixel(x, y)
			var delta := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			count += int(delta > 2.0 / 255.0); peak = maxf(peak, delta); total += delta
	return {"changed":count, "peak":peak, "mean":total / area.get_area()}

func render_bands() -> void:
	var view := SubViewport.new(); view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_DISABLED
	if not Portability.compatibility(): view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(view)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color.MAGENTA
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	view.add_child(env)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 2
	camera.near = 0.01; camera.far = 100; view.add_child(camera)
	camera.position = Vector3(16, 1, -12); camera.look_at(Vector3(16, 1, -16)); camera.current = true
	var sun := DirectionalLight3D.new(); sun.light_specular = Gfx.SUN_MARK; view.add_child(sun)
	Gfx.set_light(Color.WHITE, Color.BLACK)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir", Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(100, 200, 0))
	var terrain := terrain_fixture(); view.add_child(terrain)
	var owner := owner_fixture(terrain)
	var base := base_material()
	var wall := object_fixture(terrain, base)
	owner.register(wall.get_parent())
	var contact := wall.material_override as ShaderMaterial
	wall.material_override = base
	var off := await capture(view)
	wall.material_override = contact
	var on := await capture(view)
	var upper := compare(off, on, Rect2i(2, 2, 252, 120))
	var lower := compare(off, on, Rect2i(2, 224, 252, 30))
	check(upper.changed == 0, "upper surface untouched: " + JSON.stringify(upper))
	check(lower.changed > 3000, "visible lower contact band: " + JSON.stringify(lower))
	check(on.get_pixel(128, 253).g > off.get_pixel(128, 253).g + 0.1, "ground colour reaches wall base")
	rows.append({"case":"basic", "upper":upper, "lower":lower})
	on.save_png("user://ground-contact-" + RenderingServer.get_current_rendering_method() + "-on.png")
	off.save_png("user://ground-contact-" + RenderingServer.get_current_rendering_method() + "-off.png")
	# A full-weight ground pixel is independent of figure tint, emission and
	# zero texture channels. This checks final lighting, not shader strings.
	contact.set_shader_parameter("contact_strength", 1.0)
	var reference := await capture(view)
	var rise := 2.0 * (1.0 - 253.5 / SIZE)
	var dark := 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.15, rise))
	var expected := Color(51.0 / 255.0, 166.0 / 255.0, 77.0 / 255.0) * dark
	var actual := reference.get_pixel(128, 253)
	check(maxf(absf(expected.r - actual.r), maxf(absf(expected.g - actual.g), absf(expected.b - actual.b))) < 3.0 / 255.0,
		"ground RGB stays in correct colour space: " + str(actual) + " expected " + str(expected))
	for colour: Color in [Color.BLACK, Color.RED, Color(0.2, 0.1, 0.9)]:
		contact.set_shader_parameter("albedo_tex", texture(colour, Image.FORMAT_RGBA8))
		contact.set_shader_parameter("ei_material_diffuse", Color(0.2, 0.1, 0.8, 1))
		contact.set_shader_parameter("ei_material_emissive", Vector3(0.3, 0.1, 0.7))
		var pixels := await capture(view)
		var row := compare(reference, pixels, Rect2i(4, 252, 248, 2))
		check(row.changed == 0, "ground weight unaffected by mesh modulation " + str(colour) + " " + JSON.stringify(row))
	contact.set_shader_parameter("albedo_tex", base.get_shader_parameter("albedo_tex"))
	contact.set_shader_parameter("ei_material_diffuse", Color.WHITE)
	contact.set_shader_parameter("ei_material_emissive", Vector3.ZERO)
	contact.set_shader_parameter("contact_strength", 0.7)
	contact.set_shader_parameter("contact_extent", Vector3(0.1, 0.1, 0.1))
	var tiny := await capture(view)
	check(compare(off, tiny, Rect2i(2, 2, 252, 236)).changed == 0, "small props restrict contact reach")
	contact.set_shader_parameter("contact_extent", Vector3(2, 2, 0))
	# Raising water above the ground removes the dry-ground projection.
	terrain._land_mat.set_shader_parameter("terrain_cells", texture(Color(0.5, 0, 0, 0), Image.FORMAT_RGBAF, 32))
	owner.refresh_parameters()
	check(compare(off, await capture(view), Rect2i(2, 2, 252, 252)).changed == 0, "underwater band suppressed")
	terrain._land_mat.set_shader_parameter("terrain_cells", texture(Color(-100, 0, 0, 0), Image.FORMAT_RGBAF, 32))
	owner.refresh_parameters()
	# Alpha cutouts must keep the same holes at the contact line and above it.
	var cutout := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	cutout.fill(Color(0.7, 0.05, 0.03, 1)); cutout.fill_rect(Rect2i(2, 0, 3, 8), Color(0, 0, 0, 0))
	var cutout_texture := ImageTexture.create_from_image(cutout)
	base.set_shader_parameter("albedo_tex", cutout_texture); contact.set_shader_parameter("albedo_tex", cutout_texture)
	wall.material_override = base; off = await capture(view)
	wall.material_override = contact; on = await capture(view)
	var mismatch := 0; var holes := 0
	for y in SIZE:
		for x in SIZE:
			var a := off.get_pixel(x, y); var b := on.get_pixel(x, y)
			var hole := a.r > 0.95 and a.b > 0.95 and a.g < 0.05
			var other_hole := b.r > 0.95 and b.b > 0.95 and b.g < 0.05
			holes += int(hole); mismatch += int(hole != other_hole)
	check(holes > 10000 and mismatch == 0, "cutout coverage unchanged")
	view.free()
	await get_tree().process_frame

func _ready() -> void:
	GameData.options["gfx_hd_textures"] = 0
	GameData.options["gfx_volumetric"] = 0
	GameData.options["gfx_terrain"] = 0
	GameData.options["gfx_soft_ground"] = 0
	GameData.options["gfx_weather_surfaces"] = 0
	for material_mode in [0, 1]:
		GameData.options["gfx_materials"] = material_mode
		for original in [EIFigure.OBJECT_SHADER, EIFigure.FOLIAGE_SHADER]:
			var shader := Gfx.make_shader(GroundContactShader.source(original))
			check(not shader.get_shader_uniform_list().is_empty(), "contact shader compiles " + str(material_mode))
	GameData.options["gfx_materials"] = 0
	Gfx.apply_surface_options()
	ownership()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		await render_bands()
	var result := {"checks":checks, "failures":failures, "rows":rows, "renderer":RenderingServer.get_current_rendering_method()}
	FileAccess.open("user://ground-contact-" + RenderingServer.get_current_rendering_method() + ".json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("GROUND_CONTACT checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
