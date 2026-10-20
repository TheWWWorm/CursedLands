class_name EIObjectWater
extends MeshInstance3D
## Authored basin water lives inside a scenery atlas, outside the terrain's
## liquid layer. Split only its two water triangles; keep collision and stone.
static var _shader: Shader
var _classic: Material
var _modern: ShaderMaterial
var _clock := 0.0

static func attach(target: MeshInstance3D, template: String, texture: String) -> void:
	if template != "stst101" or texture.to_lower() != "pool00" or target.mesh.get_surface_count() != 1: return
	var arrays := target.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var water := PackedInt32Array(); var stone := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		var a := indices[i]; var b := indices[i + 1]; var c := indices[i + 2]
		# The pool00 water island occupies the lower-left atlas rectangle.
		# Require a horizontal face too, so the lion's falling stream stays intact.
		var liquid := absf(points[a].y - points[b].y) < 0.001 and absf(points[a].y - points[c].y) < 0.001
		for k in [a, b, c]: liquid = liquid and uv[k].x < 0.37 and uv[k].y > 0.37
		if liquid: water.append_array(PackedInt32Array([a, b, c]))
		else: stone.append_array(PackedInt32Array([a, b, c]))
	if water.is_empty(): return
	arrays[Mesh.ARRAY_INDEX] = stone
	var solid := ArrayMesh.new(); solid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	target.mesh = solid
	arrays[Mesh.ARRAY_INDEX] = water
	var surface := ArrayMesh.new(); surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var pool := EIObjectWater.new(); pool.name = "BasinWater"; pool.mesh = surface
	pool._classic = target.material_override
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.layers = 1 << 16
	target.add_child(pool)

func _ready() -> void:
	Gfx.ensure_globals()
	if _shader == null:
		# Use the same ripple normals, Fresnel, sun glints and scene reflection
		# as the new terrain water. Basin walls replace the terrain's tile grid.
		var code := EITerrain.WATER_FX_SHADER
		code = code.replace("varying vec3 ei_e;", "uniform vec3 pool_tint = vec3(0.12, 0.38, 0.36);\nvarying vec3 ei_e;")
		code = code.replace("bool swamp = is_lava < 0.5 && int(texture(terrain_cells, cells_uv).b + 0.5) == 14;", "bool swamp = false;")
		code = code.replace("t = water_texture(own.rgb, tile_dx, tile_dy);", "t = OUTPUT_IS_SRGB ? pool_tint : ei_lin(pool_tint);")
		code = code.replace("float exposed = 1.0 - smoothstep(0.08, 0.40, texture(rain_cover, cells_uv).r - wpos.y);", "float exposed = 1.0;")
		_shader = Gfx.make_shader(code, true, true)
	_modern = ShaderMaterial.new(); _modern.shader = _shader
	_modern.render_priority = ParticleFx.RENDER_PRIORITY - 1
	var alpha := PackedFloat32Array(); alpha.resize(64); alpha.fill(1.0)
	var ripple := PackedFloat32Array(); ripple.resize(64); ripple.fill(0.65)
	_modern.set_shader_parameter("mat_a", alpha)
	_modern.set_shader_parameter("ripple", ripple)
	_modern.set_shader_parameter("waves", 0.0)
	_modern.set_shader_parameter("mirror", 0.0)
	_modern.set_shader_parameter("wave_a", Gfx.noise("wave_a", 256, 0.018, 4, true, 5.0))
	_modern.set_shader_parameter("wave_b", Gfx.noise("wave_b", 256, 0.03, 3, true, 4.0))
	_modern.set_shader_parameter("foam_tex", Gfx.noise("foam", 256, 0.03, 4))
	Gfx.WaterTextureData.bind(_modern, EITerrain.wave_sine_texture(), EITerrain.wave_phase_texture(), [
		Gfx.noise("wave_a", 256, 0.018, 4, true, 5.0),
		Gfx.noise("wave_b", 256, 0.03, 3, true, 4.0), Gfx.noise("foam", 256, 0.03, 4)])
	GameData.options_changed.connect(_options)
	_options()

func _options() -> void:
	material_override = _modern if Gfx.on("gfx_water") else _classic
	_modern.set_shader_parameter("reflections", Gfx.on("gfx_water_reflections"))

func _process(dt: float) -> void:
	_clock += dt
	if material_override == _modern: _modern.set_shader_parameter("wave_ticks", _clock / GameUnit.TICK)
