class_name ArenaSnowSurround
extends MeshInstance3D
## A visual continuation of the courtyard, outside its navigation and marks.
## One ring surrounds either the watched board or the complete 3x3 overview.
const MARGINS := [0.0, 2.0, 8.0, 24.0, 64.0, 160.0, 512.0]
const SOURCE := """
shader_type spatial;
#define EI_TERRAIN_LIGHT
render_mode cull_disabled, ambient_light_disabled;
uniform sampler2DArray snow_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform float atlas_size = 512.0;
uniform float tile_size = 64.0;
varying vec3 ei_e;
varying float ei_k;
varying vec3 wpos;
void vertex() {
	ei_e = vec3(0.0); ei_k = 0.0;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	FOG = ei_fog_of(VERTEX, wpos);
	vec2 uv = (vec2(8.0, atlas_size - tile_size + 8.0)
		+ fract(wpos.xz * 0.5) * (tile_size - 16.0)) / atlas_size;
	vec3 c = texture(snow_atlas, vec3(uv, 0.0)).rgb;
""" + ArenaWinterTerrain.WINTER_COLOR + """
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
"""
var extent := 0.0
var _material: ShaderMaterial


func bind(ground: EITerrain) -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = Gfx.make_shader(SOURCE, true, true)
		_material.set_shader_parameter("macro_tex", Gfx.noise("macro", 256, 0.015, 3))
		material_override = _material
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.set_shader_parameter("snow_atlas", ground._atlases)
	_material.set_shader_parameter("atlas_size", float(ground.texture_size))
	_material.set_shader_parameter("tile_size", float(ground.tile_size))
	show()


func set_overview(overview: bool) -> void:
	var next := 192.0 if overview else 64.0
	if extent == next: return
	extent = next
	# One vertex per native metre, including the 192 m overview boundary.
	var segments := int(extent)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for margin: float in MARGINS:
		for side in 4:
			for step in segments:
				var t := float(step) / segments
				var direction: Vector2 = [Vector2(lerpf(-1,1,t),-1), Vector2(1,lerpf(-1,1,t)),
					Vector2(lerpf(1,-1,t),1), Vector2(-1,lerpf(1,-1,t))][side]
				var edge := (direction + Vector2.ONE) * (extent * 0.5)
				var point := edge + direction * margin
				var local := Vector2(fposmod(edge.x,64), fposmod(edge.y,64))
				if local.x == 0 and edge.x > 0: local.x = 64
				if local.y == 0 and edge.y > 0: local.y = 64
				var border := floorf(ArenaTerrain.snow_height(local.x,local.y) / 8.0 * 65535.0) * (8.0 / 65535.0)
				var drift := 3.2 + 0.7 * sin(point.x * 0.067 + point.y * 0.041) * cos(point.y * 0.083)
				var height := lerpf(border, drift, smoothstep(0,24,margin))
				# Courtyard sectors carry the authored upward snow normal even
				# on drifts. Match it so ring tessellation cannot draw a seam.
				surface.set_normal(Vector3.UP)
				surface.add_vertex(Vector3(point.x,height,-point.y))
	var count := 4 * segments
	for ring in MARGINS.size() - 1:
		for index in count:
			var a := ring * count + index
			var b := ring * count + (index + 1) % count
			# Godot's clockwise front face, matching the native land sectors.
			# A reversed face flips the fragment normal even with culling off.
			for vertex in [a,b,a+count,b,b+count,a+count]: surface.add_index(vertex)
	mesh = surface.commit()
