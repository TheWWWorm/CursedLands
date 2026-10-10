extends Node
## A close view of an authored rigid wall root under enhanced lighting.
## Run the same script against frozen baseline/candidate packs. Native lit
## captures are the evidence; masks only classify their pixels. This is not
## a terrain/figure RGB-parity test (their full material responses differ).
const SIZE := Vector2i(800, 600)
const VIEW_DIRECTION := Vector3(0.6, 0.0, 0.8)
const SPAN := 3.8
const PAINTED_MARKER := "result.normal=normalize(relief_frame[2]-"
var checks := 0
var failures := 0
var rows: Array[Dictionary] = []
var map_name := "bz13h"
var object_name := "HadoganHouse00-14473"
var object_nid := 42968
var baseline_dir := ""
var composed := false
var ablate := false
var fixture := {}
var anchor_witness := {}
var mask_on: Image
var captures := {}
var capture_settle_ms := 0


func camera_span() -> float:
	return SPAN


func upper_mask_offset() -> float:
	return 1.0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func frames(count := 12) -> void:
	for i in count:
		RenderingServer.force_draw()
		await get_tree().process_frame


func filename(label: String) -> String:
	return "ground-contact-relief-scene-" + map_name + "-" + label + ".png"


func capture(view: SubViewport, label: String) -> Image:
	# Optional diagnostic pre-roll for asynchronous renderer preparation.
	# Pixel thresholds and the original short-wait checks are unchanged.
	var start := Time.get_ticks_msec()
	await frames()
	while Time.get_ticks_msec()-start<capture_settle_ms:
		await frames()
	var image := view.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var path := "user://" + filename(label)
	check(image.save_png(path) == OK, "capture saved " + label)
	captures[label] = FileAccess.get_sha256(path)
	return image


func difference(a: Image, b: Image, region := "all") -> Dictionary:
	var aa := a.get_data(); var bb := b.get_data()
	var mm := mask_on.get_data() if mask_on else PackedByteArray()
	var count := 0; var changed := 0; var visible := 0; var peak := 0; var total := 0
	for i in range(0, aa.size(), 4):
		var band := not mm.is_empty() and mm[i] > 250 and mm[i + 1] > 250
		var upper := not mm.is_empty() and mm[i] > 250 and mm[i + 2] > 250 and not band
		if region == "band" and not band: continue
		if region == "upper" and not upper: continue
		if region == "outside_band" and band: continue
		count += 1
		var delta := 0
		for channel in 3: delta = maxi(delta, absi(int(aa[i + channel]) - int(bb[i + channel])))
		changed += int(delta > 0); visible += int(delta > 2)
		peak = maxi(peak, delta); total += delta
	return {"pixels":count, "changed_pixels":changed, "over_two_bytes":visible,
		"peak_byte_delta":peak, "mean_byte_delta":float(total) / maxi(count, 1)}


func target_meshes(object: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node: MeshInstance3D in object.find_children("*", "MeshInstance3D", true, false):
		if node.mesh: result.append(node)
	return result


func select_object(map: EIMapScene) -> Node3D:
	for object: Node3D in map.object_nodes:
		var record: Dictionary = object.get_meta("ei")
		# Display names repeat in the shipped mob. The native ID fixes the
		# placement, and the name check catches selecting an unexpected asset.
		if int(record.get("nid", -1)) != object_nid: continue
		check(String(record.get("name", "")) == object_name, "fixed native ID has the expected authored name")
		check(record.kind == "OBJECT" and not String(record.template).begins_with("nafl")
			and not String(record.template).begins_with("ef"), "selected object is authored rigid scenery")
		var meshes := target_meshes(object)
		check(not meshes.is_empty(), "selected object has native meshes")
		for mesh in meshes:
			var material := mesh.material_override as ShaderMaterial
			check(material != null and material.has_meta("ground_contact_source"), "native part is contact eligible")
			if material:
				check(not String(material.get_meta("ground_contact_source", "")).contains("EI_FOLIAGE_WIND"), "native part is not foliage")
		return object
	check(false, "fixed authored object found: " + object_name + " nid=" + str(object_nid))
	return null


func root_anchor(object: Node3D, terrain: EITerrain) -> Vector3:
	# Native walls can have every bottom vertex buried below the terrain and
	# their next row well above it. Intersect the actual indexed mesh edges
	# with native land triangles; height_at() is only a bilinear heightfield.
	# This selects a camera point without moving either piece of geometry.
	var anchor := Vector3.INF; var score := -INF
	var bounds := AABB(); var first := true; var edges := {}; var closest := INF
	for mesh in target_meshes(object):
		var box := mesh.global_transform * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box); first = false
		var vertices := mesh.mesh.get_faces()
		for i in range(0, vertices.size(), 3):
			for k in 3:
				var a := mesh.global_transform * vertices[i + k]
				var b := mesh.global_transform * vertices[i + (k + 1) % 3]
				closest = minf(closest, absf(a.y - terrain.height_at(a.x, -a.z)))
				if a.is_equal_approx(b): continue
				var key := str(a) + ":" + str(b)
				var reverse := str(b) + ":" + str(a)
				if not edges.has(reverse): edges[key] = [a, b, AABB(a, Vector3.ZERO).expand(b).grow(0.001)]
	var triangles := []
	for sector: Node in terrain.get_children():
		if not sector is EITerrainSector: continue
		for mesh: MeshInstance3D in sector._parts:
			if not bounds.intersects(mesh.global_transform * mesh.mesh.get_aabb()): continue
			var vertices := mesh.mesh.get_faces()
			for i in range(0, vertices.size(), 3):
				var a := mesh.global_transform * vertices[i]
				var b := mesh.global_transform * vertices[i + 1]
				var c := mesh.global_transform * vertices[i + 2]
				var box := AABB(a, Vector3.ZERO).expand(b).expand(c).grow(0.001)
				if bounds.intersects(box): triangles.append([a, b, c, box])
	var crossings := 0
	for edge: Array in edges.values():
		for triangle: Array in triangles:
			if not edge[2].intersects(triangle[3]): continue
			var hit: Variant = Geometry3D.segment_intersects_triangle(edge[0], edge[1], triangle[0], triangle[1], triangle[2])
			if hit == null: continue
			var p: Vector3 = hit
			var water := terrain.water_at(p.x, -p.z)
			if is_finite(water) and water > p.y - 0.15: continue
			crossings += 1
			var facing := (p - object.global_position).dot(VIEW_DIRECTION)
			if facing > score:
				score = facing; anchor = p
				anchor_witness = {"edge":[str(edge[0]), str(edge[1])], "land_triangle":[str(triangle[0]), str(triangle[1]), str(triangle[2])]}
	anchor_witness.merge({"native_edges":edges.size(), "nearby_land_triangles":triangles.size(),
		"dry_crossings":crossings, "closest_vertex_bilinear_gap":closest, "bounds":str(bounds)})
	print("GROUND_CONTACT_RELIEF_SCENE_ANCHOR ", JSON.stringify(anchor_witness))
	check(anchor.is_finite(), "dry native edge/land-triangle crossing found for close framing")
	return anchor


func material_set(map: EIMapScene, object: Node3D) -> Dictionary:
	var selected := target_meshes(object)
	var result := {}
	for mesh: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material: result[material] = selected.has(mesh)
	return result


func mask(view: SubViewport, map: EIMapScene, object: Node3D, upper_y: float, label: String) -> Image:
	var materials := material_set(map, object); var saved := {}
	for material: ShaderMaterial in materials:
		var original := material.shader
		var code := original.code
		# Keep the complete native vertex/fragment program, especially its
		# alpha and cutout assignments. The final RGB write is diagnostic.
		code = code.replace("render_mode ", "render_mode unshaded, fog_disabled, ")
		var colour := "vec3(0.0)"
		if materials[material]:
			# Contact darkness can extend beyond its colour blend. Include both
			# effects when identifying pixels the existing feature may change.
			var active := "(contact_diffuse_weight.a>0.0 || contact_specular_dark.a<1.0) ? 1.0:0.0" if code.contains("#define EI_GROUND_CONTACT") else "0.0"
			colour = "vec3(1.0,%s,(INV_VIEW_MATRIX*vec4(VERTEX,1.0)).y>%.9f ? 1.0:0.0)" % [active, upper_y]
		code = Gfx._function_tail(code, "fragment", "\n\tALBEDO=" + colour + "; FOG=vec4(0.0); EMISSION=vec3(0.0);\n")
		var program := Shader.new(); program.code = code
		check(not program.get_shader_uniform_list().is_empty(), "native diagnostic shader compiles")
		saved[material] = original; material.shader = program
	var image := await capture(view, label)
	for material: ShaderMaterial in saved: material.shader = saved[material]
	return image


func coverage(off: Image, on: Image) -> Dictionary:
	var aa := off.get_data(); var bb := on.get_data()
	var pixels := 0; var band := 0; var upper := 0; var mismatch := 0
	for i in range(0, aa.size(), 4):
		var first := aa[i] > 250; var second := bb[i] > 250
		pixels += int(second); mismatch += int(first != second)
		band += int(second and bb[i + 1] > 250)
		upper += int(second and bb[i + 2] > 250 and bb[i + 1] < 5)
	return {"object_pixels":pixels, "band_pixels":band, "upper_pixels":upper, "silhouette_mismatches":mismatch}


func painted_control(object: Node3D) -> Dictionary:
	var saved := {}
	for mesh in target_meshes(object):
		var material := mesh.material_override as ShaderMaterial
		if saved.has(material): continue
		var original := material.shader
		check(original.code.count(PAINTED_MARKER) == 1, "candidate-only painted perturbation marker is unique")
		if original.code.count(PAINTED_MARKER) != 1: continue
		var program := Shader.new()
		program.code = original.code.replace(PAINTED_MARKER, PAINTED_MARKER + "0.0*")
		saved[material] = original; material.shader = program
	return saved


func lights(mode: String, sun: DirectionalLight3D, point: OmniLight3D, anchor: Vector3) -> void:
	sun.visible = mode != "packed-point"
	sun.light_color = Color(0.9, 0.8, 0.65) if mode == "sun" else Color(0.06, 0.06, 0.06)
	Gfx.set_light(Color(0.045, 0.045, 0.045), sun.light_color if sun.visible else Color.BLACK)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir", sun.global_basis.z.normalized() if sun.visible else Vector3.ZERO)
	Gfx.sync_sun_pass(sun)
	point.visible = mode != "sun"
	point.light_specular = Gfx.LOCAL_SPECULAR if mode == "local-light" else 0.0
	point.light_energy = 0.8
	point.light_color = Color(0.75, 0.85, 1.0)
	point.position = anchor + Vector3(1.8, 0.7 if mode == "local-light" else 0.16, 2.4)
	point.omni_range = 7.0
	Gfx.update_pass_lights(get_tree(), anchor)


func reference(label: String, current: Image, region := "all") -> Dictionary:
	var path := baseline_dir.path_join(filename(label))
	check(FileAccess.file_exists(path), "frozen baseline capture exists " + label)
	if not FileAccess.file_exists(path): return {}
	var previous := Image.load_from_file(path)
	check(previous != null and previous.get_size() == current.get_size(), "baseline capture size matches " + label)
	if previous == null or previous.get_size() != current.get_size(): return {}
	previous.convert(Image.FORMAT_RGBA8)
	var result := difference(previous, current, region)
	result["baseline_sha256"] = FileAccess.get_sha256(path)
	return result


func light_case(mode: String, view: SubViewport, object: Node3D, owner: GroundContact,
		sun: DirectionalLight3D, point: OmniLight3D, anchor: Vector3) -> void:
	lights(mode, sun, point, anchor)
	GameData.options.gfx_ground_contact = 0; owner.refresh()
	var off := await capture(view, mode + "-off")
	GameData.options.gfx_ground_contact = 1; owner.refresh()
	var on := await capture(view, mode + "-on")
	await frames(24)
	var held := await capture(view, mode + "-held")
	var row := {"light":mode, "band":difference(off, on, "band"), "upper":difference(off, on, "upper"),
		"outside_band":difference(off, on, "outside_band"), "held":difference(on, held)}
	check(row.band.over_two_bytes > 50, mode + " visible native contact band " + str(row.band))
	check(row.upper.changed_pixels == 0 and row.outside_band.changed_pixels == 0, mode + " contact leaves upper and non-band pixels exact")
	check(row.held.changed_pixels == 0, mode + " held contact image is stable")
	if mode == "local-light":
		point.visible = false; Gfx.update_pass_lights(get_tree(), anchor)
		var dark := await capture(view, mode + "-disabled")
		row["light_contribution"] = difference(dark, on, "band")
		check(row.light_contribution.over_two_bytes > 50, "actual marked local light illuminates the contact band")
		point.visible = true; Gfx.update_pass_lights(get_tree(), anchor)
	if ablate:
		var saved := painted_control(object)
		var control := await capture(view, mode + "-painted-disabled")
		row["painted_attribution"] = difference(on, control, "band")
		check(difference(on, control, "outside_band").changed_pixels == 0, mode + " painted ablation stays inside contact band")
		if mode != "packed-point":
			check(row.painted_attribution.over_two_bytes > 8, mode + " painted perturbation affects lit wall-root pixels")
		for material: ShaderMaterial in saved: material.shader = saved[material]
		check(difference(on, await capture(view, mode + "-painted-restored")).changed_pixels == 0, mode + " painted ablation restores exactly")
	GameData.options.gfx_ground_contact = 0; owner.refresh()
	var restored := await capture(view, mode + "-restored")
	row["restored"] = difference(off, restored)
	check(row.restored.changed_pixels == 0, mode + " disabling contact restores the exact native image")
	if not baseline_dir.is_empty():
		row["baseline_off"] = reference(mode + "-off", off)
		row["baseline_band"] = reference(mode + "-on", on, "band")
		row["baseline_outside_band"] = reference(mode + "-on", on, "outside_band")
		if not row.baseline_off.is_empty(): check(row.baseline_off.changed_pixels == 0, mode + " frozen packs agree with contact Off")
		if not row.baseline_outside_band.is_empty(): check(row.baseline_outside_band.changed_pixels == 0, mode + " frozen-pack change stays inside contact band")
		if mode != "packed-point" and not row.baseline_band.is_empty():
			check(row.baseline_band.over_two_bytes > 8, mode + " frozen candidate visibly changes the contact band")
	rows.append(row)
	print("GROUND_CONTACT_RELIEF_SCENE_CASE ", JSON.stringify(row))


func run_scene() -> void:
	var view := SubViewport.new(); view.size = SIZE; view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; view.msaa_3d = Viewport.MSAA_DISABLED
	if not Portability.compatibility(): view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	add_child(view)
	var map := EIMapScene.load_map(map_name, "", false)
	check(map != null, "authored map loaded")
	if map == null: view.free(); return
	view.add_child(map); map.terrain.set_process(false)
	var object := select_object(map)
	if object == null or failures > 0: view.free(); return
	var placement := object.global_transform
	var original_meshes := target_meshes(object)
	var geometry := []
	for mesh in original_meshes: geometry.append([mesh, mesh.mesh, mesh.global_transform, mesh.material_override])
	for other: Node3D in map.object_nodes: other.visible = other == object
	var anchor := root_anchor(object, map.terrain)
	if not anchor.is_finite(): view.free(); return
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = camera_span()
	camera.near = 0.05; camera.far = 100; view.add_child(camera)
	camera.position = anchor + VIEW_DIRECTION * 9.0 + Vector3.UP * 3.6
	camera.position.y = maxf(camera.position.y, map.terrain.height_at(camera.position.x, -camera.position.z) + 1.0)
	camera.look_at(anchor + Vector3.UP * 0.9); camera.current = true
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	Gfx.setup_original_env(environment.environment); environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK; environment.environment.fog_enabled = false; view.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.light_specular = Gfx.SUN_MARK
	# Grazing elevation with the sun on the visible side of this native wall.
	view.add_child(sun); sun.rotation_degrees = Vector3(-12, 55, 0)
	var point := OmniLight3D.new(); view.add_child(point); point.add_to_group(Gfx.POINT_LIGHT_GROUP)
	var owner := map.terrain.contact
	check(owner != null and owner._meshes.size() > 0, "native map owner registered placed scenery")
	if owner == null: view.free(); return
	if composed:
		check(map.terrain._transitions != null and map.terrain._transitions.admitted > 0, "Natural owner admitted authored terrain")
		check(map.terrain._cliffs != null and map.terrain._cliffs.admitted > 0, "Cliffs owner admitted authored terrain")
	var record: Dictionary = object.get_meta("ei")
	fixture = {"map":map_name, "object":object_name, "nid":record.nid, "template":record.template,
		"texture":record.texture, "placement":str(placement), "anchor":str(anchor), "camera":str(camera.global_transform),
		"span":camera_span(), "upper_mask_offset":upper_mask_offset(), "size":[SIZE.x, SIZE.y], "composed":composed, "parts":original_meshes.size(), "anchor_witness":anchor_witness}
	print("GROUND_CONTACT_RELIEF_SCENE_FIXTURE ", JSON.stringify(fixture))
	RenderingServer.global_shader_parameter_set(&"ei_border", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog", Vector3(90, 100, 0))
	if is_instance_valid(map.terrain.color_cache):
		map.terrain.color_cache.prepare(camera); map.terrain.color_cache.set_process(false)
	await frames(30)
	GameData.options.gfx_ground_contact = 0; owner.refresh()
	var off_mask := await mask(view, map, object, anchor.y + upper_mask_offset(), "off-mask")
	GameData.options.gfx_ground_contact = 1; owner.refresh()
	mask_on = await mask(view, map, object, anchor.y + upper_mask_offset(), "on-mask")
	var scope := coverage(off_mask, mask_on)
	check(scope.object_pixels > 2000 and scope.band_pixels > 100 and scope.upper_pixels > 1000, "non-vacuous authored wall, contact band and upper surface " + str(scope))
	check(scope.silhouette_mismatches == 0, "native alpha/cutout silhouette exact between Off and On")
	fixture["coverage"] = scope
	if not baseline_dir.is_empty():
		var report_path := baseline_dir.path_join("ground-contact-relief-scene.json")
		check(FileAccess.file_exists(report_path), "frozen baseline report exists")
		if FileAccess.file_exists(report_path):
			var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
			# Normalize both records through JSON: parsed numeric values can
			# differ in Variant type from the live integer/float dictionary.
			var normalized: Variant = JSON.parse_string(JSON.stringify(fixture))
			check(previous is Dictionary and previous.get("fixture", {}) == normalized, "frozen packs use identical scene/camera inputs")
		var mask_comparison := reference("on-mask", mask_on)
		if not mask_comparison.is_empty(): check(mask_comparison.changed_pixels == 0, "frozen packs agree on contact scope and silhouette")
	for mode in ["sun", "packed-point", "local-light"]:
		await light_case(mode, view, object, owner, sun, point, anchor)
	check(object.global_transform == placement, "native root placement unchanged")
	for entry: Array in geometry:
		check(entry[0].mesh == entry[1] and entry[0].global_transform == entry[2] and entry[0].material_override == entry[3], "native mesh, transform and original material restored")
	view.free(); await frames(4)


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("GROUND_CONTACT_RELIEF_SCENE requires a real renderer"); get_tree().quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--contact-scene-map="): map_name = arg.trim_prefix("--contact-scene-map=")
		if arg.begins_with("--contact-scene-object="): object_name = arg.trim_prefix("--contact-scene-object=")
		if arg.begins_with("--contact-scene-nid="): object_nid = int(arg.trim_prefix("--contact-scene-nid="))
		if arg.begins_with("--contact-scene-baseline="): baseline_dir = arg.trim_prefix("--contact-scene-baseline=")
		if arg.begins_with("--contact-scene-settle-ms="): capture_settle_ms = maxi(0,int(arg.trim_prefix("--contact-scene-settle-ms=")))
		if arg == "--contact-scene-composed": composed = true
		if arg == "--contact-scene-ablate": ablate = true
	check(not SceneryBatches.requested(), "fixture uses the native unbatched map meshes")
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.merge({"gfx_terrain":2 if composed else 1, "gfx_materials":1, "gfx_terrain_cliffs":int(composed),
		"q_aa":0, "auto_graphics":0, "confine_mouse":0, "vsync":0}, true)
	Gfx.ensure_globals(); Gfx.apply_surface_options(); EIFigure.set_wind(false)
	Engine.time_scale = 0; Engine.max_fps = 120; process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_render_loop_enabled(true); DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await run_scene()
	TexUpscale.shutdown(); await frames(4)
	var report := {"checks":checks, "failures":failures, "fixture":fixture, "rows":rows, "captures":captures,
		"renderer":RenderingServer.get_current_rendering_method(), "adapter":RenderingServer.get_video_adapter_name(),
		"baseline_directory":baseline_dir, "painted_ablation":ablate,
		"scope":"Authored rigid wall-root lighting; no full terrain/figure RGB parity, shadow, frame-time or device claim."}
	FileAccess.open("user://ground-contact-relief-scene.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("GROUND_CONTACT_RELIEF_SCENE checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
