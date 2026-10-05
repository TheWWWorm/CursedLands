class_name EIFigureMaterial
extends RefCounted
## Figure material identifiers in FIG. The original material manager
## loads these records from materials.res, then copies their
## diffuse/emissive values into each figure's draw group.

const ASSETS := {
	17: "leather.mat", 18: "wood.mat", 19: "metal.mat", 20: "cloth.mat",
	21: "skin.mat", 22: "stone.mat", 23: "magic.mat", 25: "metal.mat",
}

static var _root := ""
static var _loaded := false
static var _archive: EIResArchive
static var _profiles := {}


static func decode(data: PackedByteArray, id: int) -> Dictionary:
	# Missing material: the actual manager's fallback diffuse is .3, E = 0.
	var diffuse := Color(0.3, 0.3, 0.3, 1.0)
	var emissive := Vector3.ZERO
	if data.size() >= 2:
		var p := 2 + data.decode_u16(0)
		if p + 68 <= data.size():
			diffuse = Color(data.decode_float(p), data.decode_float(p + 4),
				data.decode_float(p + 8), data.decode_float(p + 12))
			emissive = Vector3(data.decode_float(p + 48), data.decode_float(p + 52), data.decode_float(p + 56))
	# The magic record's authored .7 is overwritten by the native loader.
	if id == 23:
		emissive = Vector3.ONE
	return {"diffuse": diffuse, "emissive": emissive}


static func profile(id: int) -> Dictionary:
	if not ASSETS.has(id):
		return {}   # no declared material on a fallback / synthetic mesh
	if not _loaded or _root != GameData.root:
		_root = GameData.root
		_loaded = true
		_profiles.clear()
		_archive = null
		var path := _root.path_join("res/materials.res")
		if not _root.is_empty() and GameFiles.exists(path):
			_archive = EIResArchive.open_path(path)
	if not _profiles.has(id):
		_profiles[id] = decode(_archive.read(ASSETS[id]) if _archive else PackedByteArray(), id)
	return _profiles[id]


static func apply(material: ShaderMaterial, id: int) -> void:
	var p := profile(id)
	if p.is_empty():
		return
	var d: Color = p.diffuse
	material.set_shader_parameter("ei_material_diffuse", Vector4(d.r, d.g, d.b, d.a))
	material.set_shader_parameter("ei_material_emissive", p.emissive)


## Body textures remain shared. Only parts whose native lighting differs
## need a draw-group material, reused within this one unit's model build.
static func part_material(base: Material, id: int, cache: Dictionary) -> Material:
	if not base is ShaderMaterial:
		return base
	var p := profile(id)
	if p.is_empty() or (p.diffuse == Color.WHITE and p.emissive == Vector3.ZERO):
		return base
	var key := "%d:%d" % [base.get_instance_id(), id]
	if not cache.has(key):
		var material := base.duplicate() as ShaderMaterial
		apply(material, id)
		cache[key] = material
	return cache[key]
