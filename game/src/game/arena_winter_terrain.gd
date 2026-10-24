class_name ArenaWinterTerrain
extends EITerrain
## Unbroken snow on the native land receiver: tracks deform this exact surface,
## and combat blood remains above it. No courtyard image or extra floor mesh.

const WINTER_COLOR := """
	// Powder has soft tonal variation, without paving or a coarse tile pattern.
	float arena_snow = texture(macro_tex, wpos.xz * 0.035).r;
	c = mix(vec3(0.83, 0.89, 0.95), c * vec3(0.88, 0.94, 1.0), 0.20);
	c *= 0.94 + 0.10 * arena_snow;
"""
const DEPLOY_GUIDE_UNIFORMS := """
uniform float arena_deploy_weight = 0.0;
uniform vec3 arena_deploy_edge = vec3(0.0);
"""
const DEPLOY_GUIDE_COLOR := """
	// A little reflected warmth beneath the native low flames. No solid beam.
	if (arena_deploy_weight > 0.0) {
		vec2 p = vec2(wpos.x, -wpos.z);
		float ends = smoothstep(0.0, 1.6, p.y - arena_deploy_edge.y)
			* smoothstep(0.0, 1.6, arena_deploy_edge.z - p.y);
		float d = p.x - arena_deploy_edge.x;
		if (ends > 0.0 && abs(d) < 0.9) {
			float halo = exp(-d * d / 0.18);
			float flicker = 0.78 + 0.12 * sin(p.y * 2.4 + TIME * 2.0)
				+ 0.10 * sin(p.y * 4.7 - TIME * 3.1);
			float weight = ends * arena_deploy_weight * halo * flicker;
			// Soft contact beneath the roots, with reflected warmth around it.
			// This is temporary shading, never a persistent scorch decal.
			float contact = exp(-d * d / 0.018) * ends * arena_deploy_weight;
			c = mix(c, vec3(0.35, 0.27, 0.20), contact * 0.35);
			c = mix(c, vec3(0.95, 0.49, 0.16), weight * 0.25);
			EMISSION += vec3(1.0, 0.29, 0.025) * weight * 0.07;
		}
	}
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
var _color: Texture2DArray
var arena_world: WeakRef
var publish_environment := true
var deployment_guide := 0.0
var _guide_fire: ParticleFx


class DeploymentFire extends ParticleFx:
	static var _rooted_shaders := {}

	static func _rooted_shader(soft: bool) -> Shader:
		if not _rooted_shaders.has(soft):
			var source:=ParticleFx._shader_source(0,soft)
			var shader:=Shader.new()
			# Keep the native atlas animation, but draw upright tongues with
			# their bottom edge on the snow. Free-flying fire particles leave
			# a gap as they rise and read as sparks at the spectator distance.
			shader.code=source.replace(
				"VERTEX = vc.xyz + vec3(VERTEX.xy * size, 0.0);",
				"""vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 rooted = centre + world_offset + right * VERTEX.x * size * 0.65;
	rooted.y += (VERTEX.y + 1.0) * size * 1.1 + 0.015;
	VERTEX = (VIEW_MATRIX * vec4(rooted, 1.0)).xyz;""")
			# Taper the native square atlas into flame tips while retaining its
			# animated detail. Warm roots stay opaque enough to touch the snow.
			shader.code=shader.code.replace("varying float psize;","varying float psize;\nvarying vec2 flame_uv;\nvarying float flame_phase;")
			shader.code=shader.code.replace("mat4 m = MODEL_MATRIX;","flame_uv = vec2(UV.x, 1.0 - UV.y);\n\tmat4 m = MODEL_MATRIX;")
			shader.code=shader.code.replace("float size = abs", "flame_phase = centre.x * 3.7 + centre.z * 7.1;\n\tfloat size = abs")
			shader.code=shader.code.replace("ALPHA = clamp(t.a * COLOR.a * soft, 0.0, 1.0);", """
	float y = flame_uv.y;
	float tip = 0.82 + 0.10 * sin(flame_phase + TIME * 2.4);
	float bend = sin(flame_phase + y * 4.0 - TIME * 2.0) * y * 0.09;
	float width = 0.50 * pow(max(0.0, 1.0 - y / tip), 0.65);
	float tongue = 1.0 - smoothstep(max(0.0, width - 0.05), width + 0.025,
		abs(flame_uv.x - 0.5 - bend));
	tongue *= 1.0 - smoothstep(tip - 0.08, tip, y);
	ALPHA = clamp(t.a * COLOR.a * soft * tongue, 0.0, 1.0);""")
			_rooted_shaders[soft]=shader
		return _rooted_shaders[soft]

	func _material_of(emitter: FxEmitter) -> ShaderMaterial:
		var material:=super._material_of(emitter)
		material.shader=_rooted_shader(Gfx.on("gfx_soft_particles"))
		return material

	func _draw(interpolation: float) -> void:
		super._draw(interpolation)
		# The rooted shader extends above the native centred billboard box.
		for effect in effects:
			if is_instance_valid(effect.mmi):
				var bounds:=effect.mmi.multimesh.custom_aabb
				bounds.position+=display_origin()
				bounds.size.y+=1.0
				effect.mmi.custom_aabb=bounds

	# The native draw batches use absolute transforms. Follow this terrain
	# when scouting moves a board, without attaching effects to combat.
	func display_origin() -> Vector3:
		return global_position

	func _apply_material_options() -> void:
		super._apply_material_options()
		# A planning cue should retain the atlas' orange tongues, rather
		# than receiving the HDR boost used for damaging spell impacts.
		var shader:=_rooted_shader(Gfx.on("gfx_soft_particles"))
		for material: ShaderMaterial in _mats.values():
			if material.shader!=shader: material.shader=shader
			material.set_shader_parameter("boost", 0.50)
			material.set_shader_parameter("soft_distance", 0.06 if Gfx.on("gfx_soft_particles") else 0.0)
			material.set_shader_parameter("light_tint", Vector3(1.0, 0.38, 0.10))


func set_deployment_guide(weight: float) -> void:
	if is_equal_approx(deployment_guide, weight): return
	deployment_guide = weight
	_sync_deployment_guide()
	if weight <= 0.0:
		if is_instance_valid(_guide_fire):
			_guide_fire.hide(); _guide_fire.sync_visibility(); _guide_fire.queue_free()
		_guide_fire = null
	elif not is_instance_valid(_guide_fire) and is_inside_tree():
		_guide_fire = DeploymentFire.new()
		add_child(_guide_fire)
		var rect := ArenaRun.DEPLOY
		var effect := _guide_fire.spawn(0x2010, Vector3(rect.end.x, rect.get_center().y, 0.01),
			0.46, null, {"v130":Vector3(0, rect.size.y * 0.5 - 0.2, 0)})
		if effect:
			# The original fire atlas and animation, with a low rise and slower
			# frame progression. One bounded emitter; no lights, sound or damage.
			effect.e.d8 = 256
			effect.e.e4 = 2
			effect.e.a110 = 0.0
			effect.e.m114 = 0.97
			for tick in 16: _guide_fire._process(ParticleFx.TICK)


func _sync_deployment_guide() -> void:
	if not _land_mat: return
	var rect := ArenaRun.DEPLOY
	var parameters := {&"arena_deploy_weight": deployment_guide,
		&"arena_deploy_edge": Vector3(rect.end.x, rect.position.y, rect.end.y)}
	for parameter: StringName in parameters:
		_set_land_parameter(parameter, parameters[parameter])
		if is_instance_valid(color_cache): color_cache.sync_parameter(parameter, parameters[parameter])
		# Footprints use material copies. Keep those in sync so a walked-on
		# sector cannot retain the preparation line after combat starts.
		if is_instance_valid(details) and is_instance_valid(details.soft_ground):
			details.soft_ground.sync_parameter(parameter, parameters[parameter])


func _update_wind_parameters(refresh := false) -> void:
	if publish_environment: super._update_wind_parameters(refresh)


func _update_cloud_parameters() -> void:
	if publish_environment: super._update_cloud_parameters()


func game_world() -> GameWorld:
	return arena_world.get_ref() as GameWorld if arena_world else super.game_world()


func bind_ground_marks(marks: GroundMarks) -> void:
	if RenderingServer.get_current_rendering_method() == "forward_plus": return
	if _ink != null:
		var canvas := _ink.get_child(0) as GroundInk
		canvas.marks = marks; canvas.rows.clear(); canvas.signature = 0
		canvas.queue_redraw(); _ink.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
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
	var cached := ArenaTerrainColor.available(self)
	if cached and _color == null: _color = ArenaTerrainColor.acquire(self)
	_treat(_land_mat, _color if cached else null)
	_treat(_pair_land_mat, _color if cached else null)
	if _ink:
		for material in [_land_mat, _pair_land_mat]:
			if material:
				material.set_shader_parameter("arena_ink_enabled", true)
				material.set_shader_parameter("arena_ink", _ink.get_texture())
	if is_instance_valid(details) and is_instance_valid(details.soft_ground):
		details.soft_ground.refresh_materials()
	_sync_deployment_guide()


static func _treat(material: ShaderMaterial, color: Texture2DArray = null) -> void:
	if material == null or material.shader == null or _variants.has(material.shader): return
	var source := material.shader
	# Gfx can recompose this same Shader resource when an option changes.
	# Rebuild its winter variants from the new source, not an old copy.
	if not _winter_shaders.has(source) or _winter_shaders[source].code != source.code:
		if _winter_shaders.has(source):
			for old_kind in ["plain", "cached"]:
				if _winter_shaders[source].has(old_kind): _variants.erase(_winter_shaders[source][old_kind])
		_winter_shaders[source] = {"code": source.code}
	var kind := "cached" if color != null else "plain"
	var shaders: Dictionary = _winter_shaders[source]
	if not shaders.has(kind):
		var variant := source.duplicate() as Shader
		variant.code = source.code.replace("shader_type spatial;", "shader_type spatial;\nuniform bool arena_ink_enabled = false;\nuniform sampler2D arena_ink : source_color, filter_linear, repeat_disable;\n" + DEPLOY_GUIDE_UNIFORMS)
		# The native snow layer is raised above the base mesh. Bring that layer
		# down gently at the distant boundary where the surround joins it;
		# the playable field and its deformable footprints retain full depth.
		variant.code = variant.code.replace("soft_profile = soft_profile_grid(grid);", "soft_profile = soft_profile_grid(grid);\n\t\tsoft_profile *= smoothstep(0.0, 2.0, min(min(grid.x, grid.y), min(64.0 - grid.x, 64.0 - grid.y))); ")
		variant.code = variant.code.replace("ALBEDO = c;", "if (arena_ink_enabled) { vec4 ink = texture(arena_ink, vec2(wpos.x, -wpos.z) / 64.0); c = c * (1.0 - ink.a) + ink.rgb; }\n\tALBEDO = c;")
		variant.code = variant.code.replace(
			"// Rain affects exposed ground", WINTER_COLOR + DEPLOY_GUIDE_COLOR + "\n\t// Rain affects exposed ground")
		# At the spectator distance, a slightly stronger compacted-snow tint
		# supplements the native geometric trough and planted-foot normals.
		variant.code = variant.code.replace("ground == 3 ? 0.12 : 0.16", "ground == 3 ? 0.12 : 0.28")
		if color != null: variant.code = ArenaTerrainColor.source(variant.code)
		shaders[kind] = variant
		_variants[variant] = true
	material.shader = shaders[kind]
	material.set_shader_parameter("baked_ground", color)
