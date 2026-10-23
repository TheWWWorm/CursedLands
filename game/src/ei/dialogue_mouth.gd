extends RefCounted
## Native 538db0 loads <mask>mouth[_skin]. 538ed0 / 539010 copy the
## race's mouth_width × mouth_height strips into its 256-space rectangle.
## Compose each full skin before filtering so adjacent open/closed strips
## cannot bleed across their edges. Shipped shaders retain the wound layer;
## custom StandardMaterial3D swaps the same two immutable composites.

const FETCH := """
uniform sampler2D mouth_closed_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mouth_open_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool mouth_enabled = false;
uniform bool mouth_open = false;
vec4 ei_unit_mouth(vec4 base, vec2 uv) {
	if (!mouth_enabled) { return base; }
	if (mouth_open) { return ei_unit_tex(mouth_open_tex, uv); }
	return ei_unit_tex(mouth_closed_tex, uv);
}
"""

var image: Image
var body_rect := Rect2()
var frame_size := Vector2.ZERO
var bindings: Array[Dictionary] = []
var speaking := false
var opened := false
var remaining := 0.0
var random := RandomNumberGenerator.new()


static func specification(proto: Dictionary, race: Dictionary) -> Dictionary:
	var size := Vector2(int(race.get("mouth_width", 0)), int(race.get("mouth_height", 0)))
	if size.x <= 0.0 or size.y <= 0.0: return {}
	var mask := String(race.get("mask", "")).to_lower()
	var name := mask + "mouth"
	if int(race.get("type_id", 0)) == 0x32:
		name += "_%02d" % int(proto.get("skin", 0))
	var pos := Vector2(int(race.get("mouth_x", 0)), 256 - int(race.get("mouth_y", 0)) - size.y)
	return {"name":name, "rect":Rect2(pos, size)}


func prepare(model: Node, spec: Dictionary) -> bool:
	if spec.is_empty() or model._head == null: return false
	var name := String(spec.name) + ".mmp"
	var data := GameData.redress.read(name)
	if data.is_empty(): data = GameData.textures.read(name)
	image = EIMmp.decode(data) if not data.is_empty() else null
	if image == null: return false
	body_rect = spec.rect
	# Mouth atlases are padded to a power of two. Their width is the next
	# power of two containing the authored strip, independently of skin HD.
	var logical_width := nearest_po2(int(body_rect.size.x))
	var density := float(image.get_width()) / float(logical_width)
	frame_size = body_rect.size * density / Vector2(image.get_size())
	if frame_size.x > 1.0 or frame_size.y > .5: return false
	random.randomize()
	for node in model._head.get_children():
		if not node is MeshInstance3D: continue
		var mesh := node as MeshInstance3D
		if mesh.material_override == null: continue
		# Head materials are owned at model construction, before OrderMarks
		# can retain an unlit/bright pair. Keep those material identities.
		var rect := body_rect
		var extent := 256.0
		if mesh.has_meta("detailed_head"):
			# Original face<m/f> textures contain the body's head painting
			# (x 0..128, y 28..156), in the separate 128² portrait atlas.
			rect.position.y -= 28.0
			extent = 128.0
		bindings.append({"mesh":weakref(mesh), "rect":Rect2(rect.position / extent, rect.size / extent)})
	return not bindings.is_empty()


func set_speaking(on: bool) -> void:
	if speaking == on: return
	speaking = on
	opened = false
	remaining = 0.0
	apply()


func advance(dt: float) -> void:
	if not speaking: return
	remaining -= dt
	if remaining > 0.0: return
	opened = not opened
	# Native 5341a0 sets a countdown 2..9, then toggles on the next
	# 55 ms update after it reaches zero. Use a separate cosmetic RNG.
	remaining = random.randi_range(3, 10) * .055
	apply()


func apply() -> void:
	for binding in bindings:
		var mesh: MeshInstance3D = binding.mesh.get_ref()
		if mesh == null: continue
		var materials := [mesh.material_override]
		if mesh.has_meta("unlit"): materials.append(mesh.get_meta("unlit"))
		for material in materials:
			if material is EIUnitModel.LitMaterial or material is EIUnitModel.PreviewMaterial:
				_apply_shader(material, binding)
			elif material is StandardMaterial3D:
				_apply_standard(material, binding.rect)


func _apply_shader(material: ShaderMaterial, binding: Dictionary) -> void:
	var base: Texture2D = material.get_shader_parameter("albedo_tex")
	if speaking and base != null:
		# Native copy-before-filter order also preserves mip levels and the
		# optional sharp fetch. Cache per skin, shared by lit/unlit copies;
		# changing the lip phase does no image work or GPU readback.
		var frames: Dictionary = binding.get("frames", {})
		if not frames.has(base):
			frames[base] = [_composite(base, binding.rect, false), _composite(base, binding.rect, true)]
			binding.frames = frames
		var pair: Array = frames[base]
		material.set_shader_parameter("mouth_closed_tex", pair[0])
		material.set_shader_parameter("mouth_open_tex", pair[1])
	material.set_shader_parameter("mouth_enabled", speaking and base != null)
	material.set_shader_parameter("mouth_open", opened)


func _apply_standard(material: StandardMaterial3D, rect: Rect2) -> void:
	var base: Texture2D = material.get_meta("mouth_base", material.albedo_texture)
	var pair: Array = material.get_meta("mouth_pair", [])
	if material.albedo_texture != base and not material.albedo_texture in pair:
		# Wounds or another custom producer replaced the albedo since the
		# previous tick. Preserve that new image outside the mouth rectangle.
		base = material.albedo_texture
		pair = []
	if base == null: return
	if speaking and pair.is_empty():
		for is_open in [false, true]: pair.append(_composite(base, rect, is_open))
		material.set_meta("mouth_base", base)
		material.set_meta("mouth_pair", pair)
	var next: Texture2D = pair[int(opened)] if speaking else base
	if material.emission_texture == material.albedo_texture and material.emission_texture != null:
		material.emission_texture = next
	material.albedo_texture = next


func _composite(base: Texture2D, rect: Rect2, is_open: bool) -> Texture2D:
	var result := base.get_image()
	if result == null: return base
	if result.is_compressed(): result.decompress()
	result.clear_mipmaps()
	result.convert(Image.FORMAT_RGBA8)
	var source_size := Vector2i((frame_size * Vector2(image.get_size())).round())
	var source_y := image.get_height() - source_size.y * (2 if is_open else 1)
	var strip := image.get_region(Rect2i(Vector2i(0, source_y), source_size))
	strip.convert(Image.FORMAT_RGBA8)
	var target := Rect2i((rect.position * Vector2(result.get_size())).round(), (rect.size * Vector2(result.get_size())).round())
	strip.resize(target.size.x, target.size.y, Image.INTERPOLATE_BILINEAR)
	result.blit_rect(strip, Rect2i(Vector2i.ZERO, strip.get_size()), target.position)
	result.generate_mipmaps()
	return ImageTexture.create_from_image(result)
