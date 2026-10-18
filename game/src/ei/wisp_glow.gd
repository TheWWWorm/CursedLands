class_name EIWispGlow
extends RefCounted
## Small, depth-tested coronas on the five authored moving motes. Geometry,
## animation and gameplay size still belong to the figure.
## Self-lit cores stay readable on grass even without post-process bloom.

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
instance uniform float unit_stealth = 0.0;
void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x,
		INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float halo = exp(-5.0 * r * r) * (1.0 - smoothstep(0.65, 1.0, r));
	float core = 1.0 - smoothstep(0.08, 0.31, r);
	ALBEDO = mix(vec3(0.18, 0.78, 0.5), vec3(0.9, 1.0, 0.72), core);
	ALPHA = (0.38 * halo + 0.62 * core) * (1.0 - unit_stealth);
	// WORLD_FOG
}
"""
static var _world_shader: Shader
static var _preview_shader: Shader


static func attach(part: Node3D, preview: bool) -> MeshInstance3D:
	var geometry: Dictionary = part.get_meta(EIFigureGeometry.META)
	var glow := MeshInstance3D.new()
	glow.name = "WispGlow"
	glow.set_meta("ei_visual_only", true)
	var quad := QuadMesh.new()
	var radius := float(geometry.radius)
	quad.size = Vector2.ONE * radius * 5.5
	glow.mesh = quad
	glow.position = EISpace.vec(geometry.centre)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# LitMaterial keeps per-unit invisibility and selection material ownership
	# consistent on Compatibility as well as RenderingDevice backends.
	var mat := EIUnitModel.LitMaterial.new()
	if preview:
		if _preview_shader == null:
			_preview_shader = Shader.new()
			_preview_shader.code = SHADER.replace("instance uniform", "uniform")
		mat.shader = _preview_shader
	else:
		if _world_shader == null:
			_world_shader = Gfx.make_shader(SHADER.replace("// WORLD_FOG",
				"FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);"), false)
		mat.shader = _world_shader
	glow.material_override = mat
	part.add_child(glow)
	return glow
