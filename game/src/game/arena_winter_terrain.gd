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
# Mobile can pair only eight decals with a whole deformed terrain sector.
# Composite the native mark textures once into the snow instead, keeping their
# authored positions, growth, opacity and lifetime. Compatibility also uses
# this path because its renderer does not draw Decal nodes.
class GroundInk extends Node2D:
	var marks: GroundMarks
	var target: SubViewport
	var signature := 0
	var rows: Array = []

	func _process(_dt: float) -> void:
		if not is_instance_valid(marks): return
		var next: Array = []
		for list in [marks.foot_marks, marks.blood_marks, marks.fire_marks]:
			for mark in list:
				var decal: Decal = mark.decal
				decal.cull_mask = 0
				if decal.visible:
					next.append([Vector2(mark.x, mark.y), mark.a, mark.b, decal.basis,
						decal.texture_albedo, decal.modulate])
		var value := hash(next)
		if value == signature: return
		signature = value
		rows = next
		queue_redraw()
		target.render_target_update_mode = SubViewport.UPDATE_ONCE

	func _draw() -> void:
		var pixels := float(target.size.x) / 64.0
		for row in rows:
			var basis: Basis = row[3]
			var across := Vector2(basis.x.x, -basis.x.z)
			var along := Vector2(basis.z.x, -basis.z.z)
			draw_set_transform_matrix(Transform2D(across, along, row[0] * pixels))
			var half := Vector2(row[1], row[2]) * pixels
			draw_texture_rect(row[4], Rect2(-half, half * 2), false, row[5])

var _ink: SubViewport


func bind_ground_marks(marks: GroundMarks) -> void:
	if RenderingServer.get_current_rendering_method() == "forward_plus" or _ink != null: return
	_ink = SubViewport.new()
	_ink.name = "GroundInk"
	_ink.size = Vector2i(2048, 2048)
	_ink.transparent_bg = true
	_ink.disable_3d = true
	_ink.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_ink)
	var canvas := GroundInk.new()
	canvas.marks = marks
	canvas.target = _ink
	_ink.add_child(canvas)
	apply_gfx()


static var _winter_shaders := {}
static var _variants := {}


func apply_gfx() -> void:
	super.apply_gfx()
	_treat(_land_mat)
	_treat(_pair_land_mat)
	if _ink:
		for material in [_land_mat, _pair_land_mat]:
			if material:
				material.set_shader_parameter("arena_ink_enabled", true)
				material.set_shader_parameter("arena_ink", _ink.get_texture())
	if is_instance_valid(details) and is_instance_valid(details.soft_ground):
		details.soft_ground.refresh_materials()


static func _treat(material: ShaderMaterial) -> void:
	if material == null or material.shader == null or _variants.has(material.shader): return
	var source := material.shader
	if not _winter_shaders.has(source):
		var variant := source.duplicate() as Shader
		variant.code = source.code.replace("shader_type spatial;", "shader_type spatial;\nuniform bool arena_ink_enabled = false;\nuniform sampler2D arena_ink : source_color, filter_linear, repeat_disable;")
		variant.code = variant.code.replace("ALBEDO = c;", "if (arena_ink_enabled) { vec4 ink = texture(arena_ink, vec2(wpos.x, -wpos.z) / 64.0); c = c * (1.0 - ink.a) + ink.rgb; }\n\tALBEDO = c;")
		variant.code = variant.code.replace(
			"// Rain affects exposed ground", WINTER_COLOR + "\n\t// Rain affects exposed ground")
		# At the spectator distance, a slightly stronger compacted-snow tint
		# supplements the native geometric trough and planted-foot normals.
		variant.code = variant.code.replace("ground == 3 ? 0.12 : 0.16", "ground == 3 ? 0.12 : 0.28")
		_winter_shaders[source] = variant
		_variants[variant] = true
	material.shader = _winter_shaders[source]
