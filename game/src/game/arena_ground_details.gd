class_name ArenaGroundDetails
extends TerrainDetails
## Courtyard-only vegetation treatment. The native grass field, collision,
## terrain types and worker snapshots are untouched; only its drawing changes.

const EDGE_SOURCE := """
float arena_court_edge(vec2 point) {
	vec2 edge = abs(point - vec2(32.0, -32.0));
	float rim = max(edge.x, edge.y);
	// Worn, irregular fringes instead of grass through the paved floor.
	float wear = sin(point.x * 1.13 + point.y * 0.71) * 0.24
		+ sin(point.y * 2.31 - point.x * 0.53) * 0.13;
	return smoothstep(12.8, 15.6, rim + wear);
}
"""
static var _court_shaders := {}
static var _variants := {}


static func install(ground: EITerrain) -> void:
	# _build has not entered the scene tree or submitted vegetation jobs yet.
	# Keep this owner even when grass is disabled, so later option changes
	# continue to use the courtyard presentation without affecting campaign maps.
	if is_instance_valid(ground.details): ground.details.free()
	var details := ArenaGroundDetails.new()
	details.name = "CourtyardDetails"
	details.terrain = ground
	ground.details = details
	ground.add_child(details)
	details.apply_options()


func _apply_grass_material() -> void:
	super._apply_grass_material()
	_treat(_material)
	_treat(_cover_material)


func _process(delta: float) -> void:
	super._process(delta)
	# The distant layer is created lazily and can be rebuilt by quality options.
	_treat(_far_grass._material)


static func _treat(material: ShaderMaterial) -> void:
	if material == null or material.shader == null or _variants.has(material.shader): return
	var source := material.shader
	if not _court_shaders.has(source):
		var shader := source.duplicate() as Shader
		var code := source.code.replace("void vertex() {", EDGE_SOURCE + "\nvoid vertex() {")
		code = code.replace("float tip =", "fade *= arena_court_edge(origin.xz);\n\tfloat tip =")
		code = code.replace("VERTEX.y *= 0.90 + shape * 0.20;", "VERTEX.y *= 0.48 + shape * 0.18;")
		code = code.replace("VERTEX *= fade;", "VERTEX.y *= 0.57;\n\tVERTEX *= fade;")
		code = code.replace("blade_colour = COLOR.rgb;", "blade_colour = mix(COLOR.rgb, vec3(dot(COLOR.rgb, vec3(0.3, 0.59, 0.11))), 0.28) * vec3(0.94, 0.91, 0.82);")
		shader.code = code
		_court_shaders[source] = shader
		_variants[shader] = true
	material.shader = _court_shaders[source]
