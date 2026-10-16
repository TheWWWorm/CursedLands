class_name ArenaWinterTerrain
extends EITerrain
## The courtyard artwork lives in the native land material. Footprints, snow
## deformation, blood decals and contact shadows all reach the same surface.

const WINTER_UNIFORMS := "uniform sampler2D arena_paving : source_color, filter_linear_mipmap_anisotropic, repeat_disable;\n"
const WINTER_COLOR := """
	vec2 court_uv = vec2(wpos.x - 16.0, wpos.z + 48.0) / 32.0;
	vec2 court_edge = abs(court_uv - vec2(0.5));
	float court_rim = max(court_edge.x, court_edge.y);
	float court_drift = sin(court_uv.x * 42.0 + sin(court_uv.y * 23.0)) * 0.017
		+ sin(court_uv.y * 51.0 - court_uv.x * 19.0) * 0.012;
	float court_snow = 0.48 + 0.52 * smoothstep(0.20, 0.46, court_rim + court_drift);
	vec3 court_stone = texture(arena_paving, court_uv).rgb * vec3(0.70, 0.78, 0.86);
	c = mix(court_stone, c * vec3(0.86, 0.93, 1.0), court_snow);
"""
static var _winter_shaders := {}
static var _variants := {}


func apply_gfx() -> void:
	super.apply_gfx()
	_treat(_land_mat)
	_treat(_pair_land_mat)
	if is_instance_valid(details) and is_instance_valid(details.soft_ground):
		details.soft_ground.refresh_materials()


static func _treat(material: ShaderMaterial) -> void:
	if material == null or material.shader == null or _variants.has(material.shader): return
	var source := material.shader
	if not _winter_shaders.has(source):
		var variant := source.duplicate() as Shader
		variant.code = source.code.replace("varying vec3 wpos;", WINTER_UNIFORMS + "varying vec3 wpos;").replace(
			"// Rain affects exposed ground", WINTER_COLOR + "\n\t// Rain affects exposed ground")
		# At the spectator distance, a slightly stronger compacted-snow tint
		# supplements the native geometric trough and planted-foot normals.
		variant.code = variant.code.replace("ground == 3 ? 0.12 : 0.16", "ground == 3 ? 0.12 : 0.28")
		_winter_shaders[source] = variant
		_variants[variant] = true
	material.shader = _winter_shaders[source]
	material.set_shader_parameter("arena_paving", preload("res://assets/arena/courtyard-v2.png"))
