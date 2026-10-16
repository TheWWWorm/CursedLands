class_name ArenaWinterTerrain
extends EITerrain
## Unbroken snow on the native land receiver: tracks deform this exact surface,
## and combat blood remains above it. No courtyard image or extra floor mesh.

const WINTER_COLOR := """
	// Powder has soft tonal variation, without paving or a coarse tile pattern.
	float arena_snow = texture(macro_tex, wpos.xz * 0.035).r;
	c = mix(vec3(0.83, 0.89, 0.95), c * vec3(0.88, 0.94, 1.0), 0.20);
	c *= 0.97 + 0.04 * arena_snow;
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
		variant.code = source.code.replace(
			"// Rain affects exposed ground", WINTER_COLOR + "\n\t// Rain affects exposed ground")
		# At the spectator distance, a slightly stronger compacted-snow tint
		# supplements the native geometric trough and planted-foot normals.
		variant.code = variant.code.replace("ground == 3 ? 0.12 : 0.16", "ground == 3 ? 0.12 : 0.28")
		_winter_shaders[source] = variant
		_variants[variant] = true
	material.shader = _winter_shaders[source]
