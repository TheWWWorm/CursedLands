extends Node
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func _ready() -> void:
	await get_tree().process_frame
	var worlds: Array[GameWorld] = []
	var surfaces: Array[GroundSurfaceData] = []
	for index in 2:
		var world := GameWorld.new(); world.presentation = true; add_child(world)
		world.set_process(false); world.set_physics_process(false)
		world.terrain = ArenaTerrain.create(true); world.add_child(world.terrain)
		worlds.append(world); surfaces.append(world.terrain.ground_surface_data())
	var a := surfaces[0]; var b := surfaces[1]
	for property in ["vertices", "normals", "light_inputs", "candidates"]:
		check(a.get(property) == b.get(property), "identical boards share " + property)
	var ground := worlds[0].terrain
	var expected := {"vertices":GroundSurfaceData._vertex_image(ground),
		"normals":GroundSurfaceData._normal_image(ground),
		"light_inputs":GroundSurfaceData._light_input_image(ground),
		"candidates":GroundSurfaceData._candidate_image(ground)}
	for property in expected:
		var texture: ImageTexture = a.get(property)
		if texture: check(texture.get_image().get_data() == expected[property].get_data(), "original texture bytes: " + property)
	var mats: Array[ShaderMaterial] = []
	for surface in surfaces:
		var material := ShaderMaterial.new()
		material.shader = Shader.new()
		material.shader.code = "shader_type spatial; uniform sampler2D query_tiles; uniform sampler2DArray query_tracks; uniform sampler2D query_clock;"
		surface.bind(material); mats.append(material)
	for property in ["query_tiles", "query_tracks", "query_clock"]:
		check(mats[0].get_shader_parameter(property) != mats[1].get_shader_parameter(property), "board owns dynamic " + property)
	var original := a.vertices.get_image().get_data()
	for index in 6:
		ground.heights[0] += 0.1
		var changed := ArenaSurfaceCache.acquire(ground)
		check(changed.vertices != a.vertices, "changed geometry invalidates static snapshot")
	check(ArenaSurfaceCache._entries.size() <= ArenaSurfaceCache.CAPACITY, "static snapshots remain bounded")
	check(a.vertices.get_image().get_data() == original, "new geometry cannot mutate a retained snapshot")
	var source := "shader_type spatial; void fragment() { ALBEDO = vec3(1.0); }"
	check(ArenaSurfaceCache.shader(source) == ArenaSurfaceCache.shader(source), "identical contact shaders are shared")
	var grass := []
	for index in 2:
		var material := ShaderMaterial.new(); material.shader = Shader.new()
		material.shader.code = "shader_type spatial; void vertex() { }"
		ArenaGroundDetails._treat(material); grass.append(material)
	check(grass[0].shader == grass[1].shader, "separate lazy grass sources share one courtyard shader")
	var treated: Shader = grass[0].shader
	ArenaGroundDetails._treat(grass[0])
	check(grass[0].shader == treated, "courtyard shader treatment is idempotent")
	for index in 20:
		var material := ShaderMaterial.new(); material.shader = Shader.new()
		material.shader.code = "shader_type spatial; // variant %d\nvoid vertex() { }" % index
		ArenaGroundDetails._treat(material)
	check(ArenaGroundDetails._court_shaders.size() <= 16, "courtyard shader cache is bounded")
	var refs := worlds.map(func(w):return weakref(w.terrain))
	for world in worlds: world.queue_free()
	worlds.clear(); surfaces.clear(); ground = null
	await get_tree().process_frame; await get_tree().process_frame
	check(refs.all(func(r):return r.get_ref()==null), "static cache does not retain terrain nodes")
	print("ARENA_SURFACE_CACHE ", checks, " checks; failures=", JSON.stringify(failures))
	TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
