class_name EIFigure
extends RefCounted
## Loads models from figures.res.
## A model is either a single "<name>.fig" or a "<name>.mod" package holding
## several .fig parts plus a .lnk part hierarchy. Part offsets live in "<name>.bon".
## Every vertex and offset has 8 morph variants blended trilinearly by the
## object's "complexion" (strength / dexterity / height for creatures,
## size variation for trees and props).

const FIG_MAGIC := "FIG"
const SurfaceResponse = preload("res://src/game/surface_materials.gd")

## template -> {"parts": {name: Dictionary}, "links": [[name, parent]], "bones": {name: PackedFloat32Array}}
static var _models := {}
static var _materials := {}
static var _foliage := {}
static var _wind := true

## Remake foliage: the original alpha-tested material plus optional wind
## (gfx_wind), bark detail (gfx_materials) and masked leaf transmission
## (gfx_foliage_light). Each switch returns to the corresponding original path.
## The sway grows with the height above the object's root (instance uniform
## part_y = the part's offset, + the vertex's own height), gusts travel across
## the island along the wind direction, and leaves flutter a little.
const FOLIAGE_SHADER := """
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;
varying vec3 ei_e;
varying float ei_k;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foliage_mask : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wind = 1.0;
uniform vec2 wind_dir = vec2(0.8, 0.6);
instance uniform float part_y = 0.0;
""" + SurfaceResponse.RELIEF_SHADER + """
void vertex() {
	ei_e = vec3(0.0);
	ei_k = 0.0;
	float hgt = max(part_y + VERTEX.y, 0.0);
	if (wind > 0.0 && hgt > 0.05) {
		vec3 o = NODE_POSITION_WORLD;
		float ph = dot(o.xz, wind_dir) * 0.12 + o.x * 0.05;
		float gust = sin(TIME * 0.9 - ph) * 0.55 + sin(TIME * 2.1 - ph * 1.7) * 0.25 + 0.45;
		float bend = (0.012 * hgt + 0.0006 * hgt * hgt) * gust * wind;
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float flutter = sin(TIME * 7.0 + dot(w, vec3(1.7, 2.3, 1.1))) * 0.018 * min(hgt, 2.0) * wind;
		vec3 dw = vec3(wind_dir.x * bend, -bend * bend * 0.3 + flutter * 0.5, wind_dir.y * bend) + vec3(flutter, 0.0, -flutter) * 0.6;
		// world offset into the model's space (objects are scaled 1, rotated)
		VERTEX += (inverse(mat3(MODEL_MATRIX)) * dw);
	}
}
void fragment() {
	FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = t.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));
	ROUGHNESS = 1.0;
	vec2 plant = texture(foliage_mask, UV).rg;
	ei_leaf = plant.r * ei_surface_fx.y * 0.75;
	if (ei_surface_fx.x > 0.5) {
		ei_surface = mix(vec3(0.16, 0.86, 0.0), vec3(0.13, 0.82, 0.0), plant.r);
		if (plant.g > 0.01) {
			NORMAL = ei_relief_normal(albedo_tex, UV, VERTEX, NORMAL, plant.g * 0.45);
		}
	}
}
"""


## Map objects in the original light model (Gfx.light_code: the 3dfpfpu.dll
## pipeline's max(ambient, sun · n·L, point lights), material emissive 0,
## diffuse 1, ObjectsLightingCoeff 1). Alpha-tested like material_for.
const OBJECT_SHADER := """
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;
varying vec3 ei_e;
varying float ei_k;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float a2c = 0.0;
uniform vec4 surface_profile = vec4(0.0, 1.0, 0.0, 0.0);
""" + SurfaceResponse.RELIEF_SHADER + """
void vertex() {
	ei_e = vec3(0.0);
	ei_k = 0.0;
}
void fragment() {
	FOG = ei_fog_of(VERTEX, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = t.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (a2c > 0.5) {
		ALPHA_ANTIALIASING_EDGE = 0.3;
		ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));
	}
	ROUGHNESS = 1.0;
	if (ei_surface_fx.x > 0.5) {
		ei_surface = surface_profile.xyz;
		if (surface_profile.w > 0.0) {
			NORMAL = ei_relief_normal(albedo_tex, UV, VERTEX, NORMAL, surface_profile.w);
		}
	}
}
"""
static var _oshader: Shader
static var _oshader_a2c: Shader
static var _world := {}


## The map-object material of a texture (falls back to material_for).
static func world_material_for(texture: String) -> Material:
	var key := texture + ("#hd" if Gfx.on("gfx_hd_textures") else "")   # option gfx_hd_textures (TexUpscale)
	if _world.has(key):
		return _world[key]
	var tex := Gfx.texture_3d(texture) if texture else null
	if tex == null:
		return material_for(texture)
	var a2c := texture.to_lower().begins_with("tree")
	if _oshader == null:
		Gfx.ensure_globals()
		_oshader = Gfx.make_shader(OBJECT_SHADER)
		# alpha-to-coverage puts a material into the transparent pass (see
		# material_for), so only the tree atlases get the variant that writes it
		_oshader_a2c = Gfx.make_shader(OBJECT_SHADER.replace("if (a2c > 0.5) {", "if (true) {"))
	var m := ShaderMaterial.new()
	m.shader = _oshader_a2c if a2c else _oshader
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("surface_profile", SurfaceResponse.object_profile(texture))
	_world[key] = m
	return m


## `morph`: levers (the original CLeverObject) animate by moving their complexion's
## second component (the remake's c.x) between 0 and 1
## with it each mesh gets that axis as blend shape 0 and each
## part node the metas "p0" / "p1" (its position at c.x = 0 / 1). The blend
## is linear along one axis, so the blend shape is exact.
static func instantiate(template: String, texture: String, complexion: Vector3,
		visible_parts: PackedStringArray = PackedStringArray(), morph := false, lit := false) -> Node3D:
	var model := get_model(template)
	if model.is_empty():
		return null
	var root := Node3D.new()
	root.name = template
	# "nafl*" figures are the flora (naflbu bushes, nafltr trees).
	var flora := template.begins_with("nafl") and not morph
	var mat: Material = foliage_material_for(texture) if flora else (world_material_for(texture) if lit else material_for(texture))
	var nodes := {}
	for link: Array in model.links:
		var part: String = link[0]
		var node := Node3D.new()
		node.name = part
		var bone: PackedFloat32Array = model.bones.get(part, PackedFloat32Array())
		if bone.size() >= 24:
			node.position = EISpace.vec(bone_pos(bone, complexion))
			if morph:
				node.set_meta("p0", EISpace.vec(bone_pos(bone, Vector3(0.0, complexion.y, complexion.z))))
				node.set_meta("p1", EISpace.vec(bone_pos(bone, Vector3(1.0, complexion.y, complexion.z))))
		var parent: Node3D = nodes.get(link[1], root)
		parent.add_child(node)
		nodes[part] = node
		var fig: Dictionary = model.parts.get(part, {})
		if fig.is_empty() or (not visible_parts.is_empty() and not part in visible_parts):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = build_morph_mesh(fig, complexion) if morph else build_mesh(fig, complexion)
		mi.material_override = mat
		node.add_child(mi)
		if flora and mat is ShaderMaterial:
			var y := 0.0
			var q: Node = node
			while q and q != root:
				y += (q as Node3D).position.y
				q = q.get_parent()
			if Portability.compatibility():
				var local_mat := mat.duplicate() as ShaderMaterial
				local_mat.set_shader_parameter("part_y", y)
				mi.material_override = local_mat
			else:
				mi.set_instance_shader_parameter("part_y", y)
		if morph:
			mi.set_blend_shape_value(0, complexion.x)
	return root


## build_mesh at c.x = 0 with blend shape 0 = the same mesh at c.x = 1.
static func build_morph_mesh(f: Dictionary, c: Vector3) -> ArrayMesh:
	var a := _build_mesh(f, Vector3(0.0, c.y, c.z))
	var b := _build_mesh(f, Vector3(1.0, c.y, c.z))
	if a.get_surface_count() == 0:
		return a
	var arrays := a.surface_get_arrays(0)
	var shape := b.surface_get_arrays(0)
	var target := []
	target.resize(Mesh.ARRAY_MAX)
	target[Mesh.ARRAY_VERTEX] = shape[Mesh.ARRAY_VERTEX]
	target[Mesh.ARRAY_NORMAL] = shape[Mesh.ARRAY_NORMAL]
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	mesh.add_blend_shape("t")
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [target])
	return mesh


static func get_model(template: String) -> Dictionary:
	if _models.has(template):
		return _models[template]
	var model := {}
	if GameData.has_figure(template + ".mod"):
		var pkg := EIResArchive.from_bytes(GameData.read_figure(template + ".mod"))
		if pkg:
			var parts := {}
			for entry: String in pkg.entries:
				if entry != template:
					var f := _parse_fig(pkg.read(entry))
					if not f.is_empty():
						parts[entry] = f
			var links := _parse_lnk(pkg.read(template))
			if links.is_empty():
				for p: String in parts:
					links.append([p, ""])
			model = {"parts": parts, "links": links, "bones": _parse_bones(template, parts.keys())}
	elif GameData.has_figure(template + ".fig"):
		var f := _parse_fig(GameData.read_figure(template + ".fig"))
		if not f.is_empty():
			model = {"parts": {template: f}, "links": [[template, ""]], "bones": _parse_bones(template, [template])}
	_models[template] = model
	return model


static func _parse_lnk(d: PackedByteArray) -> Array:
	var out := []
	if d.size() < 4:
		return out
	var p := 4
	for i in d.decode_u32(0):
		var n := d.decode_u32(p)
		var name := d.slice(p + 4, p + 4 + n).get_string_from_ascii().to_lower()
		p += 4 + n
		var pn := d.decode_u32(p)
		var parent := d.slice(p + 4, p + 4 + pn).get_string_from_ascii().to_lower() if pn else ""
		p += 4 + pn
		out.append([name, parent])
	return out


static func _parse_bones(template: String, part_names: Array) -> Dictionary:
	var out := {}
	var d := GameData.read_figure(template + ".bon")
	if EIResArchive.is_archive(d):
		var arc := EIResArchive.from_bytes(d)
		for part: String in arc.entries:
			out[part] = arc.read(part).to_float32_array()
	elif d.size() >= 96 and part_names.size() == 1:
		out[part_names[0]] = d.to_float32_array()
	return out


static func _parse_fig(d: PackedByteArray) -> Dictionary:
	if d.size() < 40 or d.slice(0, 3).get_string_from_ascii() != FIG_MAGIC:
		return {}
	var n := d[3] - 48  # morph variant count, '8' in practice
	var f := {
		"n": n,
		"vblocks": d.decode_u32(4), "nblocks": d.decode_u32(8), "uvs": d.decode_u32(12),
		"indices": d.decode_u32(16), "comps": d.decode_u32(20),
	}
	var p := 40 + n * 40  # skip center/min/max/radius per variant
	f.v_off = p
	p += f.vblocks * 12 * n * 4
	f.n_off = p
	p += f.nblocks * 16 * 4
	f.uv_off = p
	p += f.uvs * 8
	f.i_off = p
	p += f.indices * 2
	f.c_off = p
	f.data = d
	return f


## Trilinear blend of 8 morph variants. `stride` floats separate consecutive variants.
static func blend(a: PackedFloat32Array, base: int, stride: int, c: Vector3) -> float:
	var v1 := lerpf(lerpf(a[base], a[base + stride], c.y),
			lerpf(a[base + 2 * stride], a[base + 3 * stride], c.y), c.x)
	var v2 := lerpf(lerpf(a[base + 4 * stride], a[base + 5 * stride], c.y),
			lerpf(a[base + 6 * stride], a[base + 7 * stride], c.y), c.x)
	return lerpf(v1, v2, c.z)


## Bone offset of the 8 .bon variants: the same trilinear blend as vertices
## (the original, selected for 96-byte BON entries).
## Confirmed against the original x86 routine by verify_character_render.py.
##  belongs to the older figure-manager node system, not units.
static func bone_pos(b: PackedFloat32Array, c: Vector3) -> Vector3:
	return Vector3(blend(b, 0, 3, c), blend(b, 1, 3, c), blend(b, 2, 3, c))


## Built meshes by figure part and complexion: placed objects and units of one
## kind share them (meshes are never modified after building).
static var _meshes := {}
static var _fig_ids := 0


static func build_mesh(f: Dictionary, c: Vector3) -> ArrayMesh:
	if not f.has("id"):
		_fig_ids += 1
		f.id = _fig_ids
	var key := "%d|%s|%s|%s" % [f.id, c.x, c.y, c.z]
	var cached: ArrayMesh = _meshes.get(key)
	if cached:
		return cached
	if _meshes.size() > 30000:
		_meshes.clear()
	var mesh := _build_mesh(f, c)
	_meshes[key] = mesh
	return mesh


static func _build_mesh(f: Dictionary, c: Vector3) -> ArrayMesh:
	var d: PackedByteArray = f.data
	var n: int = f.n
	var verts := d.slice(f.v_off, f.n_off).to_float32_array()
	var norms := d.slice(f.n_off, f.uv_off).to_float32_array()
	var uvs := d.slice(f.uv_off, f.i_off).to_float32_array()
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	for i in f.comps:
		var cp: int = f.c_off + i * 6
		var vc := d.decode_u16(cp)
		var nc := d.decode_u16(cp + 2)
		var tc := d.decode_u16(cp + 4)
		var vb := vc >> 2
		var lane := vc & 3
		var p := Vector3()
		for axis in 3:
			var base := ((vb * 3 + axis) * n) * 4 + lane
			p[axis] = blend(verts, base, 4, c) if n >= 8 else verts[base]
		pos.append(EISpace.vec(p))
		var nb := (nc >> 2) * 16 + (nc & 3)
		nrm.append(EISpace.vec(Vector3(norms[nb], norms[nb + 4], norms[nb + 8])).normalized())
		uv.append(Vector2(uvs[tc * 2], uvs[tc * 2 + 1]) if tc * 2 + 1 < uvs.size() else Vector2.ZERO)
	# EI (D3D) triangles are the opposite winding of Godot's front faces.
	var idx := PackedInt32Array()
	for i in range(0, f.indices - 2, 3):
		var p: int = f.i_off + i * 2
		idx.append_array([d.decode_u16(p), d.decode_u16(p + 4), d.decode_u16(p + 2)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	if not pos.is_empty() and not idx.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func material_for(texture: String) -> StandardMaterial3D:
	if _materials.has(texture):
		return _materials[texture]
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	# D3D fixed-function lighting is Lambert (Godot defaults to Burley, which
	# darkens grazing faces and shows the low-poly facets).
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var tex := GameData.get_texture(texture) if texture else null
	if tex:
		m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		# Soft foliage edges with MSAA (remake rendering quality). Only on the
		# foliage atlases (tree*): Godot draws alpha-to-coverage materials in
		# its transparent pass, after the screen copy the remake water and
		# heat haze refract, so buildings and rocks stay in the opaque pass.
		if texture.to_lower().begins_with("tree"):
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		m.albedo_color = Color(0.8, 0.2, 0.8)
	_materials[texture] = m
	return m


## The foliage material of a texture: material_for's look plus wind sway
## (falls back to material_for when the texture is missing).
static func foliage_material_for(texture: String) -> Material:
	var key := texture + ("#hd" if Gfx.on("gfx_hd_textures") else "")
	if _foliage.has(key):
		return _foliage[key]
	var tex := Gfx.texture_3d(texture) if texture else null
	if tex == null:
		return material_for(texture)
	var m := ShaderMaterial.new()
	m.shader = _foliage_shader()
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("foliage_mask", SurfaceResponse.foliage_mask(texture))
	m.set_shader_parameter("wind", 1.0 if _wind else 0.0)
	_foliage[key] = m
	return m


static var _fshader: Shader


static func _foliage_shader() -> Shader:
	if _fshader == null:
		Gfx.ensure_globals()
		_fshader = Gfx.make_shader(FOLIAGE_SHADER)
	return _fshader


## Option gfx_wind on / off for every foliage material.
static func set_wind(on: bool) -> void:
	_wind = on
	for m: ShaderMaterial in _foliage.values():
		m.set_shader_parameter("wind", 1.0 if on else 0.0)


static func clear_cache() -> void:
	_meshes.clear()
	_models.clear()
	_materials.clear()
	_foliage.clear()
	_world.clear()
	SurfaceResponse.clear_cache()
