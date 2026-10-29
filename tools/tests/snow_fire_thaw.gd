extends Node
## Snow round the map's lit fires starts thawed when a zone is shown: the
## loose layer (and its track depth) is scaled by 1 - thaw in the raster and
## its CPU mirrors. Map data only; unlit braziers and raised torches excluded.
const SnowMelt = preload("res://src/game/fx/snow_melt.gd")
const RayGround = preload("res://src/game/fx/raytrace_ground.gd")
const DrawnGround = preload("res://src/game/fx/ambient_ground.gd")
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)


func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.gfx_soft_ground = 1
	Gfx.ensure_globals(); Gfx.apply_surface_options()
	_sources()
	_shader_sources()
	var started := Time.get_ticks_msec()
	var map := EIMapScene.load_map("zone12")
	check(map != null and map.mob != null, "zone12 loads with its records")
	if map == null: return finish()
	print("THAW_ZONE_LOAD ms=", Time.get_ticks_msec() - started)
	add_child(map)
	var t := map.terrain
	t.set_process(false)
	if is_instance_valid(t.details): t.details.set_process(false)
	var fires := SnowMelt.sources(map.mob)
	var lit := 0
	for o: Dictionary in map.mob.objects:
		if String(o.get("kind", "")) == "TORCH" and float(o.get("torch_strength", 0.0)) > 0.0: lit += 1
	check(fires.size() == lit and lit >= 8, "every lit TORCH record is a source (%d of %d)" % [fires.size(), lit])
	check(not t.snow_melt.is_empty() and t.snow_melt_revision > 0, "loading the zone installs the thaw (%d vertices)" % t.snow_melt.size())
	check(t.snow_melt == SnowMelt.field(t, fires), "the thaw is a pure function of the map data")
	var fresh := EIMob.load_bytes(GameData.read_file("maps/zone12.mob"))
	check(SnowMelt.field(t, SnowMelt.sources(fresh)) == t.snow_melt, "a second read of the records reproduces it exactly")
	# The uploaded loose-ground vertices (dummy rendering keeps no texture
	# updates, so check the image that set_snow_melt uploads).
	var image := GroundSurfaceData._vertex_image(t)
	check(t._soft_vertices != null and t._land_mat.get_shader_parameter("soft_vertices") == t._soft_vertices, "the land keeps its loose-ground texture")
	var ray := RayGround.new(); ray.configure(t)
	var on_snow := 0
	var cores := 0
	var partial := 0
	var outside_clear := true
	var drawn_ok := true
	for fire: Vector4 in fires:
		var centre := Vector2(fire.x, fire.y)
		var vertex := Vector2i(centre.round())
		var index := vertex.y * t.grid_w + vertex.x
		var loose := ray.profile_at(Vector2i(vertex / 2)).x > 0.0
		if not loose: continue
		on_snow += 1
		var melt := float(t.snow_melt.get(index, 0.0))
		if melt > 0.99 and fire.w > 0.99: cores += 1
		check(melt > 0.0 and is_equal_approx(image.get_pixelv(vertex).a, melt), "land vertex data carries the thaw at %s" % centre)
		check(ray.vertex_profile(vertex).x <= 0.20 * (1.0 - melt) + 1e-5, "ray-traced snow lift thaws at %s" % centre)
		var h := t.heights[index]
		var drawn := DrawnGround.surface(t, Vector2(vertex) + t.land_xy[index], h)
		if drawn.x > 0.20 * (1.0 - melt) + 0.02: drawn_ok = false
		for y in range(vertex.y - 7, vertex.y + 8):
			for x in range(vertex.x - 7, vertex.x + 8):
				var i := y * t.grid_w + x
				var p := Vector2(x, y) + t.land_xy[i]
				var d := p.distance_to(centre)
				var value := float(t.snow_melt.get(i, 0.0))
				if value > 0.05 and value < 0.95: partial += 1
				if d > fire.z * (1.0 + SnowMelt.EDGE_NOISE) + 0.01 and value > 0.0:
					# Another fire may overlap this window.
					var covered := false
					for other: Vector4 in fires:
						if p.distance_to(Vector2(other.x, other.y)) < other.z * (1.0 + SnowMelt.EDGE_NOISE): covered = true
					if not covered: outside_clear = false
	check(on_snow >= 6, "authored fires stand in loose snow (%d)" % on_snow)
	check(cores >= on_snow - 1, "the snow at each fire has thawed completely (%d of %d)" % [cores, on_snow])
	check(partial >= on_snow * 6, "the thaw fades softly to the untouched snow (%d partial vertices)" % partial)
	check(outside_clear, "snow beyond each fire's reach is untouched")
	check(drawn_ok, "small animals walk on the thawed (drawn) surface")
	# Far from every fire the loose layer is unchanged.
	var far := Vector2i(-1, -1)
	for y in range(8, t.sectors_y * 32 - 8, 7):
		for x in range(8, t.grid_w - 8, 7):
			if far.x >= 0: break
			var p := Vector2(x, y)
			var near := false
			for fire: Vector4 in fires:
				if p.distance_to(Vector2(fire.x, fire.y)) < 12.0: near = true
			if not near and is_equal_approx(ray.profile_at(Vector2i(x / 2, y / 2)).x, 0.20) and ray.vertex_profile(Vector2i(x, y)).x > 0.19:
				far = Vector2i(x, y)
	check(far.x >= 0 and image.get_pixelv(far).a == 0.0 and ray.vertex_profile(far).is_equal_approx(Vector2(0.20, 0.30)), "untouched loose snow keeps its full depth")
	# Ground-contact consumers share the thaw; the broad phase bound moved to
	# the normal map's alpha and still covers every neighbouring vertex.
	var data := t.ground_surface_data()
	check(data.vertices.get_image().get_data() == image.get_data(), "contact and cover queries read the same thawed vertices")
	var normals := GroundSurfaceData._normal_image(t)
	var bounded := true
	for sample: Vector2i in [Vector2i(0, 0), Vector2i(31, 31), Vector2i(32, 32), Vector2i(100, 77), Vector2i(t.grid_w - 2, t.sectors_y * 32 - 1)]:
		var top := normals.get_pixelv(sample + sample / 32).a
		for dy in range(-1, 3):
			for dx in range(-1, 3):
				var q := (sample + Vector2i(dx, dy)).clamp(Vector2i.ZERO, Vector2i(t.grid_w - 1, t.sectors_y * 32))
				if t.heights[q.y * t.grid_w + q.x] > top: bounded = false
	check(bounded, "contact upper bounds still cover each candidate cell")
	# Clearing and reinstalling refreshes existing consumers in place.
	var vertices := data.vertices
	var revision := t.snow_melt_revision
	t.set_snow_melt({})
	check(t.snow_melt_revision == revision + 1 and GroundSurfaceData._vertex_image(t).get_pixelv(Vector2i(Vector2(fires[0].x, fires[0].y).round())).a == 0.0, "a cleared thaw restores the full loose layer")
	t.set_snow_melt(SnowMelt.field(t, fires))
	check(data.vertices == vertices and t._land_mat.get_shader_parameter("soft_vertices") == t._soft_vertices and GroundSurfaceData._vertex_image(t).get_data() == image.get_data(), "reinstalling keeps the bound textures")
	data = null
	map.free()
	_trails_off()
	finish()


func _sources() -> void:
	var mob := EIMob.new()
	mob.objects = [
		{"kind":"TORCH", "torch_strength":0.5, "position":Vector3(10, 12, 0), "torch_offset":Vector3(0.1, 0, 0.5)},
		{"kind":"TORCH", "torch_strength":0.0, "position":Vector3(20, 12, 0), "torch_offset":Vector3(0.1, 0, 0.5)},
		{"kind":"TORCH", "torch_strength":0.4, "position":Vector3(30, 12, 3.5), "torch_offset":Vector3.ZERO},
		{"kind":"OBJECT", "template":"stto8", "position":Vector3(40, 12, 0)},
		{"kind":"TORCH", "torch_strength":0.7, "position":Vector3(50, 12, 0), "torch_offset":Vector3.ZERO},
	]
	var fires := SnowMelt.sources(mob)
	check(fires.size() == 2, "only lit fires near the ground thaw snow (unlit, wall-high and other records skipped)")
	if fires.size() == 2:
		check(Vector2(fires[0].x, fires[0].y).is_equal_approx(Vector2(10.1, 12)) and fires[0].w == 1.0, "the flame offset places the brazier's thaw")
		check(fires[1].z > fires[0].z and fires[1].z <= SnowMelt.MAX_RADIUS, "larger fires thaw a wider, bounded area")
		check(fires[0].z >= 3.6, "a campfire thaws a trampled-size patch (%.2f m radius)" % fires[0].z)
	# A uniform loose-snow field: complete core, soft edge, nothing beyond.
	var t := EITerrain.new()
	t.sectors_x = 2; t.sectors_y = 1; t.grid_w = 65
	t.heights.resize(65 * 33); t.land_xy.resize(65 * 33)
	t.land_tile.resize(32 * 16); t.land_tile.fill(0); t.tile_types = PackedInt32Array([9, 0])
	for i in 16: t.land_tile[i * 32 + 31] = 1 # one hard column: nothing to thaw there
	var field := SnowMelt.field(t, [Vector4(32, 16, 3.0, 1.0), Vector4(63.2, 16, 3.0, 1.0)] as Array[Vector4])
	var index := func(x: int, y: int) -> int: return y * 65 + x
	check(is_equal_approx(field.get(index.call(32, 16), 0.0), 1.0), "a fire's own vertex is fully thawed")
	check(not field.has(index.call(32, 25)) and not field.has(index.call(38, 16)), "the thaw ends within its radius")
	var ring: float = field.get(index.call(34, 16), 0.0)
	check(ring > 0.0 and ring < 1.0, "the thaw fades softly (%.3f at 2 m)" % ring)
	check(not field.has(index.call(64, 16)), "ground without loose snow stores no thaw")
	t.free()


func _shader_sources() -> void:
	check(GroundSurfaceShader.SOFT_FUNCTIONS.contains("soft_surface(vec2(grid) + data.xz, data.y) * (1.0 - data.a)"), "the shared loose profile is scaled by the thaw")
	check(EITerrain.TERRAIN_SHADER.contains("soft_thaw = soft_thaw_grid(grid);") and EITerrain.TERRAIN_SHADER.count("soft_profile = soft_profile_grid(grid);") == 1, "the land shows the thaw; the arena profile anchor stays unique")
	check(GroundSurfaceShader.SOFT_FUNCTIONS.contains("vec3 soft_thaw_smooth(vec2 grid)") and EITerrain.TERRAIN_SHADER.contains("vec2 slope = soft_thaw_smooth(thaw_p).yz"), "the thawed edge is shaded from the smooth field, not mesh triangles")
	check(EITerrain.TERRAIN_SHADER.contains("c *= 1.0 - trodden * 0.16;") and EITerrain.TERRAIN_SHADER.contains("c * vec3(0.47, 0.40, 0.33), bare * 0.75"), "the thaw shows a trodden floor and wet ground, like a trail")
	check(GroundContactShader.FUNCTIONS.contains("texelFetch(query_normals,cell+cell/32,0).a"), "the contact broad phase reads its bound from the normal map")


func _trails_off() -> void:
	GameData.options.gfx_soft_ground = 0
	Gfx.apply_surface_options()
	var map := EIMapScene.load_map("zone12")
	if map == null: return
	check(not map.terrain.snow_melt.is_empty(), "the thaw is recorded with Snow deformation off")
	check(map.terrain._soft_vertices == null and not bool(map.terrain._land_mat.get_shader_parameter("soft_ground")), "with Snow deformation off no loose-snow texture or shader work exists")
	map.free()


func finish() -> void:
	print("SNOW_FIRE_THAW checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
