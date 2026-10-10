class_name GroundContact
extends Node
## A world's rigid-scenery material variants. Register only placed map figures;
## character models, attachments, portraits and other uses of EIFigure remain
## on their original materials. Identical base/bounds pairs share one variant.
var terrain: EITerrain
var surface: GroundSurfaceData
var _meshes := {} # instance id -> weak node, current base/owned material, local bounds
var _variants := {} # base material -> {extent: ShaderMaterial}
var _shaders := {} # raw figure source -> Shader
var _queued := false
var _cliffs := false
var _transitions := false


static func attach(root: Node3D, ground: EITerrain) -> void:
	if DisplayServer.get_name() == "headless":
		return # Dedicated simulation workers do not build visual field caches.
	if not is_instance_valid(ground.contact):
		var owner := GroundContact.new()
		owner.name = "GroundContact"
		owner.terrain = ground
		ground.contact = owner
		ground.add_child(owner)
	ground.contact.register(root)


func _ready() -> void:
	GameData.options_changed.connect(queue_refresh)


func _exit_tree() -> void:
	_clear_derived()
	_meshes.clear()
	_variants.clear()
	_shaders.clear()
	surface = null


func register(root: Node3D) -> void:
	for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var original := node.material_override as ShaderMaterial
		if original == null or not original.has_meta("ground_contact_source") or node.mesh == null:
			continue
		var entry := {"node": weakref(node), "base": original, "applied": original, "extent": node.mesh.get_aabb().size}
		_meshes[node.get_instance_id()] = entry
		if Gfx.on("gfx_ground_contact"):
			node.material_override = _variant(original, entry.extent)
			entry.applied = node.material_override


func queue_refresh() -> void:
	if not _queued:
		_queued = true
		call_deferred("refresh")


func refresh() -> void:
	_queued = false
	_clear_derived()
	var enabled := Gfx.on("gfx_ground_contact")
	var cliffs := terrain._cliffs != null and terrain._cliffs.admitted > 0
	var transitions := terrain._transitions != null and terrain._transitions.admitted > 0
	if _cliffs != cliffs or _transitions != transitions:
		# Optional samplers exist only for admitted worlds. Rebuild variants
		# after either mode changes; keep normal/fade ownership unchanged.
		_variants.clear()
		_shaders.clear()
		_cliffs = cliffs
		_transitions = transitions
	for base: ShaderMaterial in _variants:
		for material: ShaderMaterial in _variants[base].values():
			_copy_base(base, material)
			if enabled:
				surface.bind(material)
	for id: int in _meshes.keys():
		var entry: Dictionary = _meshes[id]
		var node := (entry.node as WeakRef).get_ref() as MeshInstance3D
		if node == null:
			_meshes.erase(id)
			continue
		if not _retain_material(node, entry):
			_meshes.erase(id)
			continue
		var material := _variant(entry.base, entry.extent) if enabled else entry.base as ShaderMaterial
		_replace(node, material)
		entry.applied = material
	if not enabled:
		_variants.clear()
		_shaders.clear()
		surface = null


func refresh_parameters() -> void:
	if surface == null:
		return
	for variants: Dictionary in _variants.values():
		for material: ShaderMaterial in variants.values():
			surface.bind(material)
			var dither := CameraFade._derived.get(material) as ShaderMaterial
			if dither:
				surface.bind(dither)
	# Compatibility fades own a further material copy; its texture resources
	# already share updates, while water levels/option uniforms need a rebind.
	for entry: Dictionary in _meshes.values():
		var node := (entry.node as WeakRef).get_ref() as MeshInstance3D
		if node and node.has_meta("cam_fade_mat") and node.get_meta("cam_fade_mat") == entry.applied and node.material_override is ShaderMaterial:
			surface.bind(node.material_override)


func _retain_material(node: MeshInstance3D, entry: Dictionary) -> bool:
	# The menu replaces placed figure materials with its labelled boards.
	# Other callers can also install a new material after registration. Only
	# replace the material we last applied; adopt a new eligible scenery base
	# and leave unrelated overrides in their caller's ownership. Camera fades
	# keep that underlying material in metadata while drawing a dither copy.
	var current := (node.get_meta("cam_fade_mat") if node.has_meta("cam_fade_mat") else node.material_override) as Material
	if current == entry.applied:
		return true
	var base := current as ShaderMaterial
	if base == null or not base.has_meta("ground_contact_source"):
		return false
	entry.base = base
	entry.applied = base
	return true


func _variant(base: ShaderMaterial, extent: Vector3) -> ShaderMaterial:
	if surface == null:
		surface = terrain.ground_surface_data()
		_cliffs = terrain._cliffs != null and terrain._cliffs.admitted > 0
		_transitions = terrain._transitions != null and terrain._transitions.admitted > 0
	var variants: Dictionary = _variants.get(base, {})
	if variants.has(extent):
		return variants[extent]
	var source: String = base.get_meta("ground_contact_source")
	if not _shaders.has(source):
		var code := GroundContactShader.source(source, _cliffs)
		if _transitions: code = terrain._transitions.source(code)
		else: code = GroundContactShader.compact_relief(code)
		_shaders[source] = Gfx.make_shader(code)
	var material := ShaderMaterial.new()
	material.shader = _shaders[source]
	_copy_base(base, material)
	material.set_shader_parameter("contact_extent", extent)
	surface.bind(material)
	variants[extent] = material
	_variants[base] = variants
	return material


static func _copy_base(base: ShaderMaterial, target: ShaderMaterial) -> void:
	for field: Dictionary in target.shader.get_shader_uniform_list():
		var value: Variant = base.get_shader_parameter(field.name)
		if value != null:
			target.set_shader_parameter(field.name, value)
	target.render_priority = base.render_priority


static func _replace(node: MeshInstance3D, material: ShaderMaterial) -> void:
	SceneryBatches.changed(node)
	if node.has_meta("cam_fade_mat"):
		var alpha := 0.0
		if Portability.compatibility() and node.material_override is ShaderMaterial:
			alpha = float(node.material_override.get_shader_parameter("cam_fade"))
		node.set_meta("cam_fade_mat", material)
		var dither := CameraFade._dither_material(material)
		node.material_override = dither.duplicate() if Portability.compatibility() else dither
		if Portability.compatibility():
			node.material_override.set_shader_parameter("cam_fade", alpha)
	else:
		node.material_override = material


func _clear_derived() -> void:
	# CameraFade's normal bases are global figure materials. These bases own
	# world textures, so its strong cache must not outlive this world/option.
	for variants: Dictionary in _variants.values():
		for material: ShaderMaterial in variants.values():
			CameraFade._derived.erase(material)
			CameraFade._shaders.erase(material.shader)
