extends Node
## V1 prerequisite experiment, NOT a production effect. Compare a world-space
## surface query with pixels rasterized from the real, displaced terrain mesh.
## Uses authored xy offsets, triangle planes and UVs, plus the ACTUALLY installed
## dense footprint tiles. Track arrays below are diagnostic CPU snapshots;
## production must share their storage, not duplicate them or read back the GPU.
var checks := 0
var failures := 0
var rows: Array[Dictionary] = []
var _linear_capture := false
const SIZE := 256
const SPAN := 8.0

## Frozen pre-extraction displacement oracle: derives profiles from type IDs,
## independent of the production texture's newly populated B/A channels.
const PROFILE_REFERENCE := """vec2 reference_soft_type(int g) {
	// Loose layer thickness and maximum compression, in metres. The swept
	// floor stays near the authored ground where the actor's feet stand.
	if (g == 9) { return vec2(0.20, 0.30); }
	if (g == 12) { return vec2(0.075, 0.12); }
	if (g == 3) { return vec2(0.008, 0.025); }
	return vec2(0.0);
}
int reference_soft_ground_at(ivec2 p) {
	return int(texelFetch(terrain_tiles, clamp(p, ivec2(0), textureSize(terrain_tiles, 0) - 1), 0).g + 0.5);
}
vec2 reference_soft_surface(vec2 p, float height) {
	ivec2 tile = ivec2(floor(p * 0.5));
	vec2 profile = reference_soft_type(reference_soft_ground_at(tile));
	if (profile.x == 0.0) { return vec2(0.0); }
	// Soft materials of different thickness share the same border height.
	vec2 grid = p * 0.5 - 0.5;
	ivec2 base = ivec2(floor(grid));
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(grid));
	profile = mix(mix(reference_soft_type(reference_soft_ground_at(base)), reference_soft_type(reference_soft_ground_at(base + ivec2(1, 0))), blend.x),
		mix(reference_soft_type(reference_soft_ground_at(base + ivec2(0, 1))), reference_soft_type(reference_soft_ground_at(base + ivec2(1, 1))), blend.x), blend.y);
	vec2 local = p - vec2(tile) * 2.0;
	// Taper to zero at hard material boundaries instead of opening cracks
	// between the loose layer and the original rock/road triangles.
	float mask = 1.0;
	if (reference_soft_type(reference_soft_ground_at(tile + ivec2(-1, 0))).x == 0.0) { mask *= smoothstep(0.0, 0.6, local.x); }
	if (reference_soft_type(reference_soft_ground_at(tile + ivec2(1, 0))).x == 0.0) { mask *= smoothstep(0.0, 0.6, 2.0 - local.x); }
	if (reference_soft_type(reference_soft_ground_at(tile + ivec2(0, -1))).x == 0.0) { mask *= smoothstep(0.0, 0.6, local.y); }
	if (reference_soft_type(reference_soft_ground_at(tile + ivec2(0, 1))).x == 0.0) { mask *= smoothstep(0.0, 0.6, 2.0 - local.y); }
	vec4 cell = textureLod(terrain_cells, p / vec2(textureSize(terrain_cells, 0)), 0.0);
	float water_y = cell.r + level[clamp(int(cell.a + 0.5), 0, 63)];
	return profile * mask * smoothstep(0.025, 0.10, height - water_y);
}
"""

var QUERY := GroundSurfaceShader.QUERY_SHADER.replace("const bool query_", "uniform bool query_")

const OUTPUT := """
uniform int query_output = 0;
vec3 query_colour(vec3 c) {
	return OUTPUT_IS_SRGB ? c : mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}
"""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)

func fragment(source: String, first: String, last: String) -> String:
	var a := source.find(first)
	var b := source.find(last, a + first.length())
	assert(a >= 0 and b > a, "terrain shader extraction markers changed")
	return source.substr(a, b - a)

func make_shader(query: bool) -> Shader:
	var original := EITerrain.TERRAIN_SHADER
	var declarations := fragment(original, "uniform sampler2DArray atlases", "varying vec3 wpos;")
	var soft := GroundSurfaceShader.SOFT_FUNCTIONS
	var tiles := fragment(original, "vec2 tile_turn", "float ground_height")
	var code := "shader_type spatial;\nrender_mode unshaded, cull_disabled, fog_disabled;\n" + declarations
	code += "varying vec3 wpos;\n" + soft + PROFILE_REFERENCE + tiles + OUTPUT + QUERY
	if query:
		code += """
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float h; vec2 grid; ivec2 tile; mat2 jacobian;
	if (!query_surface(vec2(wpos.x, -wpos.z), h, grid, tile, jacobian)) { discard; }
	vec3 c = vec3(0.0);
	if (query_output == 1) {
		vec4 traits;
		vec2 p = grid * 0.5;
		vec2 dx = jacobian * dFdx(wpos.xz * vec2(1.0,-1.0)) * 0.5;
		vec2 dy = jacobian * dFdy(wpos.xz * vec2(1.0,-1.0)) * 0.5;
		if (query_implicit_gradients) { dx = dFdx(p); dy = dFdy(p); }
		c = ground_sample(tile, p - vec2(tile), dx, dy, traits);
	} else if (query_output == 2) { c = vec3(fract(grid * 0.03125), 0.5); }
	ALBEDO = query_output == 1 ? c : query_colour(c);
}
"""
	else:
		code += """
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (soft_ground) {
		vec2 profile = reference_soft_surface(vec2(wpos.x, -wpos.z), wpos.y);
		VERTEX.y += profile.x;
		if (soft_tracks) { VERTEX.y += soft_height(soft_sample(soft_uv(vec2(wpos.x, -wpos.z)))) * profile.y; }
		wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
}
void fragment() {
	vec3 c = vec3(0.0);
	if (query_output == 0) {
		float h; vec2 grid; ivec2 owner; mat2 jacobian;
		if (!query_surface(vec2(wpos.x, -wpos.z), h, grid, owner, jacobian)) {
			c = vec3(0.0, 1.0, 1.0);
		} else {
			float error = abs(h - wpos.y);
			// Compare the tolerance ON THE GPU. Colour-space conversion and
			// target quantization must not decide whether a 2 mm error passes.
			// R/G are only approximate statistics, kept above dark-code loss.
			c = vec3(0.5 + min(error * 0.25, 0.5), 0.5 + min(error * 25.0, 0.5), error > 0.002 ? 0.5 : 0.0);
		}
	}
	int id = int(UV2.y + 0.5);
	int width = textureSize(terrain_tiles, 0).x;
	ivec2 tile = ivec2(id % width, id / width);
	int code = int(tile_info(tile).r + 0.5);
	float border = 8.0 * source_texel * tiles_per_axis;
	int packed_tile = code & 63;
	int per_row = int(tiles_per_axis);
	vec2 origin = vec2(float(packed_tile % per_row), float(per_row - 1 - packed_tile / per_row));
	vec2 local = (UV * tiles_per_axis - origin - border) / (1.0 - 2.0 * border);
	local = 0.5 + tile_turn(vec2(local.x, 1.0 - local.y) - 0.5, (4 - ((code >> 14) & 3)) % 4);
	if (query_output == 1) {
		vec4 traits;
		c = detail > 0.0 ? ground_sample(tile, clamp(local, vec2(0.0), vec2(0.99999)), dFdx(local), dFdy(local), traits) : EI_ATLAS(UV, UV2.x).rgb;
	} else if (query_output == 2) { c = vec3(fract((vec2(tile) + local) * 0.0625), 0.5); }
	ALBEDO = query_output == 1 ? c : query_colour(c);
}
"""
	var shader := Shader.new()
	shader.code = code
	check(not shader.get_shader_uniform_list().is_empty(), "diagnostic shader compiles: " + str(query))
	return shader

func copy_material(original: ShaderMaterial, shader: Shader) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = shader
	# Read the target's declarations: production specialization can compile
	# currently disabled uniforms out, even though the material stores them.
	for field: Dictionary in shader.get_shader_uniform_list():
		var value: Variant = original.get_shader_parameter(field.name)
		if value != null:
			result.set_shader_parameter(field.name, value)
	return result

func surface_data(terrain: EITerrain, soft: SoftGroundDeform) -> Dictionary:
	var data := PackedFloat32Array()
	data.resize(terrain.heights.size() * 4)
	for i in terrain.heights.size():
		data[i * 4] = terrain.land_xy[i].x
		data[i * 4 + 1] = terrain.heights[i]
		data[i * 4 + 2] = terrain.land_xy[i].y
	var verts := ImageTexture.create_from_image(Image.create_from_data(terrain.grid_w,
		terrain.sectors_y * 32 + 1, false, Image.FORMAT_RGBAF, data.to_byte_array()))
	var table := Image.create(terrain.sectors_x * 16, terrain.sectors_y * 16, false, Image.FORMAT_RGF)
	table.fill(Color(0, 0, 0, 0))
	var images: Array[Image] = []
	if soft:
		for key: Vector2i in soft.sectors:
			var rec: Dictionary = soft.sectors[key]
			var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
			if node == null or node.mesh == rec.source:
				continue # Work queued/in flight is not yet visible on the surface.
			images.append(rec.image)
			for y in 16:
				for x in 16:
					var dense: bool = rec.tiles.get(y * 16 + x) != null
					table.set_pixel(key.x * 16 + x, key.y * 16 + y, Color(images.size(), float(dense), 0, 0))
	if images.is_empty():
		var empty := Image.create(1, 1, false, Image.FORMAT_RGBAF)
		empty.fill(Color(0, 0, 0, 0))
		images.append(empty)
	var tracks := Texture2DArray.new()
	check(tracks.create_from_images(images) == OK, "diagnostic track snapshot accepted")
	return {"query_vertices": verts, "query_tiles": ImageTexture.create_from_image(table),
		"query_tracks": tracks, "query_clock": _clock_texture(soft._age if soft else 0.0)}

func _clock_texture(time: float) -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RF)
	image.fill(Color(time, 0, 0, 0))
	return ImageTexture.create_from_image(image)

func make_view(p: Vector2, height: float) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true
	view.use_hdr_2d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_DISABLED
	if not Portability.compatibility():
		view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(view)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = SPAN
	camera.near = 0.01
	camera.far = 200
	view.add_child(camera)
	camera.position = Vector3(p.x, height + 60, -p.y)
	camera.look_at(Vector3(p.x, height, -p.y), Vector3.BACK)
	camera.current = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.MAGENTA
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	view.add_child(env)
	return view

func capture(view: SubViewport) -> Image:
	for i in 3:
		RenderingServer.force_draw()
		await get_tree().process_frame
	var result := view.get_texture().get_image()
	# Calibrate the returned colour space on this backend. Keep float pixels;
	# packing height across RGB8 channel boundaries creates false large errors.
	if _linear_capture:
		for y in result.get_height():
			for x in result.get_width():
				result.set_pixel(x, y, result.get_pixel(x, y).linear_to_srgb())
	return result

func calibrate() -> void:
	var view := make_view(Vector2.ZERO, 0.0)
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * SPAN
	plane.mesh = mesh
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, fog_disabled;\n" + OUTPUT + "\nvoid fragment() { ALBEDO = query_colour(vec3(0.25, 0.5, 0.75)); }"
	material.shader = shader
	plane.material_override = material
	view.add_child(plane)
	var raw := (await capture(view)).get_pixel(SIZE / 2, SIZE / 2)
	var expected := Color(0.25, 0.5, 0.75)
	_linear_capture = absf(raw.r - expected.srgb_to_linear().r) < 0.001
	var value := raw.linear_to_srgb() if _linear_capture else raw
	check(absf(value.r - expected.r) < 0.001 and absf(value.g - expected.g) < 0.001 and absf(value.b - expected.b) < 0.001,
		"floating render capture calibrated " + str(raw))
	print("GROUND_CAPTURE ", raw, " linear=", _linear_capture)
	view.free()
	await get_tree().process_frame

func height_errors(image: Image) -> Dictionary:
	var values := PackedFloat32Array()
	var missing := 0
	var raster_holes := 0
	var changed := 0
	var total := 0.0
	var max_error := 0.0
	var examples := []
	for y in range(1, SIZE - 1):
		for x in range(1, SIZE - 1):
			var c := image.get_pixel(x, y)
			if c.b > 0.99:
				if c.r > 0.99:
					raster_holes += 1
				else:
					missing += 1
				continue
			var error := maxf(0.0, (c.g - 0.5) / 25.0 if c.g < 0.95 else (c.r - 0.5) * 4.0)
			values.append(error)
			total += error
			max_error = maxf(max_error, error)
			changed += int(c.b > 0.25)
			if c.b > 0.25 and examples.size() < 5:
				examples.append({"pixel": str(Vector2i(x, y)), "error": error})
	values.sort()
	return {"max": max_error, "mean": total / maxf(values.size(), 1),
		"p99": values[int(values.size() * 0.99)] if not values.is_empty() else 0.0,
		"changed": changed, "pixels": values.size(), "missing": missing, "raster_holes": raster_holes, "examples": examples}

func compare(a: Image, b: Image) -> Dictionary:
	var max_error := 0.0
	var total := 0.0
	var changed := 0
	var errors := PackedFloat32Array()
	var missing := 0
	var raster_holes := 0
	# Leave only the framebuffer boundary out (not interior triangle edges).
	for y in range(1, SIZE - 1):
		for x in range(1, SIZE - 1):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if ca.r > 0.99 and ca.b > 0.99 and ca.g < 0.01:
				raster_holes += 1
				continue
			if cb.r > 0.99 and cb.b > 0.99 and cb.g < 0.01:
				missing += 1
			var error := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			max_error = maxf(max_error, error)
			total += error
			changed += int(error > 2.0 / 255.0)
			errors.append(error)
	errors.sort()
	return {"max": max_error, "mean": total / errors.size(), "p99": errors[int(errors.size() * 0.99)],
		"changed": changed, "pixels": errors.size(), "missing": missing, "raster_holes": raster_holes}

func find_patch(t: EITerrain, type_id: int) -> Vector2:
	var result := Vector2.ZERO
	var score := -INF
	var width := t.sectors_x * 32
	for y in range(6, t.sectors_y * 32 - 6):
		for x in range(6, width - 6):
			var i := y * width + x
			if t.ground[i] != type_id or is_finite(t.water[i]):
				continue
			var vi := y * t.grid_w + x
			var slope := absf(t.heights[vi + 1] - t.heights[vi]) + absf(t.heights[vi + t.grid_w] - t.heights[vi])
			# Prefer displaced, sloping terrain in this 8 m patch.
			var value := t.land_xy[vi].length() * 2 + minf(slope, 1.0)
			if value > score:
				score = value
				result = Vector2(x, y) + Vector2(0.35, 0.45)
	return result

func render_case(t: EITerrain, p: Vector2, label: String, soft: SoftGroundDeform) -> void:
	var h := t.height_at(p.x, p.y)
	var actual := make_view(p, h)
	var query := make_view(p, h)
	var real_shader := make_shader(false)
	var query_shader := make_shader(true)
	var snapshot := surface_data(t, soft)
	# Independent CPU snapshot remains the geometry oracle. The query plane
	# consumes production storage, including slot reuse and the shared clock.
	var shared := snapshot.duplicate()
	if soft:
		var field := soft.shared_field()
		shared.query_tiles = field.tiles
		shared.query_tracks = field.texture
		shared.query_clock = field.clock
	var materials: Array[ShaderMaterial] = []
	for sector: Node in t.get_children():
		if not sector is EITerrainSector:
			continue
		for part: MeshInstance3D in sector._parts:
			var copy := MeshInstance3D.new()
			copy.mesh = part.mesh
			var original := part.mesh.surface_get_material(0) as ShaderMaterial
			var mat := copy_material(original, real_shader)
			for key: String in shared:
				mat.set_shader_parameter(key, shared[key])
			materials.append(mat)
			copy.material_override = mat
			actual.add_child(copy)
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * SPAN
	plane.mesh = mesh
	plane.position = Vector3(p.x, h, -p.y)
	var qm := copy_material(t._land_mat, query_shader)
	qm.set_shader_parameter("blend_edges", Gfx.on("gfx_terrain"))
	for key: String in shared:
		qm.set_shader_parameter(key, shared[key])
	plane.material_override = qm
	query.add_child(plane)
	for output in [0, 2, 1]:
		for mat: ShaderMaterial in materials:
			mat.set_shader_parameter("query_output", output)
		qm.set_shader_parameter("query_output", output)
		var a := await capture(actual)
		var b: Image = await capture(query) if output != 0 else null
		var row := height_errors(a) if output == 0 else compare(a, b)
		row.merge({"case": label, "output": ["height", "albedo", "uv"][output], "position": str(p)})
		rows.append(row)
		# Dense geometry can have subpixel raster cracks: report every such
		# uncovered pixel, but don't decode the magenta background as height.
		check(row.missing == 0, label + " query covers rasterized terrain")
		check(row.changed == 0 if output == 0 else row.p99 <= 2.0 / 255.0,
			label + " " + row.output + " matches rendered triangles: " + JSON.stringify(row))
		if output == 0:
			for mat: ShaderMaterial in materials:
				mat.set_shader_parameter("query_bilinear", true)
			var control := height_errors(await capture(actual))
			control.merge({"case": label, "output": "bilinear_control", "position": str(p)})
			rows.append(control)
			for mat: ShaderMaterial in materials:
				mat.set_shader_parameter("query_bilinear", false)
			if label == "bz10k-type9-original":
				for mat: ShaderMaterial in materials:
					mat.set_shader_parameter("query_first_hit", true)
				control = height_errors(await capture(actual))
				control.merge({"case": label, "output": "first_hit_control", "position": str(p)})
				rows.append(control)
				check(control.changed > 100 and control.max > 0.5, "steep fixture detects overlapping triangles")
				for mat: ShaderMaterial in materials:
					mat.set_shader_parameter("query_first_hit", false)
			if soft:
				for mat: ShaderMaterial in materials:
					mat.set_shader_parameter("query_undeformed", true)
				control = height_errors(await capture(actual))
				control.merge({"case": label, "output": "undeformed_control", "position": str(p)})
				rows.append(control)
				for mat: ShaderMaterial in materials:
					mat.set_shader_parameter("query_undeformed", false)
				if label.ends_with("-tracks") or label.ends_with("-fading"):
					for mat: ShaderMaterial in materials:
						mat.set_shader_parameter("query_no_tracks", true)
					control = height_errors(await capture(actual))
					control.merge({"case": label, "output": "no_tracks_control", "position": str(p)})
					rows.append(control)
					check(control.changed > 0, label + " actual footprint deformation is visible")
					for mat: ShaderMaterial in materials:
						mat.set_shader_parameter("query_no_tracks", false)
		else:
			if output == 1:
				qm.set_shader_parameter("query_implicit_gradients", true)
				var control := compare(a, await capture(query))
				control.merge({"case": label, "output": "implicit_gradients_control", "position": str(p)})
				rows.append(control)
				qm.set_shader_parameter("query_implicit_gradients", false)
			var suffix := "%s-%s-%s" % [RenderingServer.get_current_rendering_method(), label, row.output]
			a.save_png("user://ground-surface-" + suffix + "-mesh.png")
			b.save_png("user://ground-surface-" + suffix + "-query.png")
	actual.free()
	query.free()
	await get_tree().process_frame

func drain(soft: SoftGroundDeform) -> void:
	for i in 16:
		soft._process(0.0)
		soft._finish_mesh_jobs(true)
		if soft._mesh_jobs.is_empty() and soft._queue.is_empty() and not soft.sectors.values().any(func(r: Dictionary) -> bool: return r.build_pending):
			return
	check(false, "deformation jobs drain")

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("GROUND_CONTACT_SURFACE requires a real renderer")
		get_tree().quit(2)
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	Engine.max_fps = 60
	await calibrate()
	GameData.options["gfx_hd_textures"] = 0
	GameData.options["gfx_grass"] = 0
	GameData.options["gfx_soft_ground"] = 0
	GameData.options["gfx_terrain"] = 0
	GameData.options["gfx_volumetric"] = 0
	for map_name in ["bz2g", "bz10k", "bz13h"]:
		var t := EITerrain.load_map(map_name)
		check(t != null, map_name + " loaded")
		if t == null:
			continue
		add_child(t)
		t.set_process(false)
		var census := {}
		for g: int in t.ground:
			census[g] = int(census.get(g, 0)) + 1
		print("GROUND_CENSUS ", map_name, " ", JSON.stringify(census))
		var types := [0] if map_name == "bz2g" else [9] if map_name == "bz10k" else [3]
		for type_id: int in types:
			var p := find_patch(t, type_id)
			check(p != Vector2.ZERO, map_name + " ground type fixture found: " + str(type_id))
			if p == Vector2.ZERO:
				continue
			var label := "%s-type%d" % [map_name, type_id]
			await render_case(t, p, label + "-original", null)
			GameData.options["gfx_terrain"] = 1
			Gfx._set_vol_fog(false)
			t.apply_gfx()
			await render_case(t, p, label + "-padded", null)
			GameData.options["gfx_terrain"] = 0
			Gfx._set_vol_fog(false)
			t.apply_gfx()
			if type_id in SoftGroundDeform.TYPES:
				GameData.options["gfx_soft_ground"] = 1
				Gfx._set_vol_fog(false)
				t.apply_gfx()
				var soft := t.details.soft_ground
				soft.set_process(false)
				await render_case(t, p, label + "-loose", soft)
				soft._age = 123.0
				for step in 5:
					soft.add_step(p + Vector2(0.28 * step, 0.2 * step), Vector2(0.12, 0.23), 0.3)
				check(not soft._queue.is_empty(), label + " footprint work queued")
				await render_case(t, p, label + "-pending", soft)
				drain(soft)
				await render_case(t, p, label + "-tracks", soft)
				soft._age += 210
				soft._process(0)
				await render_case(t, p, label + "-fading", soft)
				soft.clear()
				await render_case(t, p, label + "-cleared", soft)
				GameData.options["gfx_soft_ground"] = 0
				Gfx._set_vol_fog(false)
				t.apply_gfx()
		t.free()
		await get_tree().process_frame
	var result := {"checks": checks, "failures": failures, "rows": rows,
		"renderer": RenderingServer.get_current_rendering_method(), "editor": OS.has_feature("editor"),
		"adapter": RenderingServer.get_video_adapter_name(), "size": SIZE, "span": SPAN}
	print("GROUND_CONTACT_SURFACE ", JSON.stringify(result))
	var file := FileAccess.open("user://ground-contact-surface-" + RenderingServer.get_current_rendering_method() + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	get_tree().quit(1 if failures else 0)
