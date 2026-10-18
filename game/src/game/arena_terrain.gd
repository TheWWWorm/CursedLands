class_name ArenaTerrain
extends RefCounted
## Authored clearing surrounded by snow-covered Ingos ruins. The atlas and figure assets
## come from the installed game. This does not load any campaign scripts.
const PLAY_AREA := Rect2(18.5, 18.5, 27, 27)

class Sectors extends EIResArchive:
	var files := {}
	func read(key: String) -> PackedByteArray:
		return files.get(key, PackedByteArray())


static func create(rendered := true) -> EITerrain:
	var source := EIResArchive.open_path(GameData.root.path_join("maps/zone11.mpr"))
	if source == null: return null
	var header := source.read("zone11.mp").duplicate()
	if header.size() < 38: return null
	header.encode_u32(8, 2); header.encode_u32(12, 2)
	header.encode_float(4, 8.0)
	var ground := ArenaWinterTerrain.new()
	ground.map_name = "arena_courtyard"
	ground.resource_prefix = "zone11"
	if not ground._parse_header(header):
		ground.free()
		return null
	var archive := Sectors.new()
	for sy in 2:
		for sx in 2:
			var data := PackedByteArray()
			data.resize(5 + 33 * 33 * 8 + 16 * 16 * 2)
			data.encode_u32(0, EITerrain.SEC_MAGIC)
			for y in 33:
				for x in 33:
					var gx := sx * 32 + x
					var gy := sy * 32 + y
					var rim := maxf(absf(gx - 32), absf(gy - 32))
					# A flat playable clearing, framed by rolling drifts rather than
					# a straight square berm. Never change footing inside the field.
					var edge := maxf(0, rim - 15.5)
					var drift := 0.65 + 0.25 * sin(gx * 0.31 + gy * 0.17) + 0.10 * cos(gy * 0.55)
					var height := minf(3.2, edge * edge * 0.032 * drift)
					var offset := 5 + (y * 33 + x) * 8
					data.encode_u16(offset + 2, int(height / 8.0 * 65535))
					data.encode_u32(offset + 4, (1000 << 22) | (1000 << 11) | 1000)
			for y in 16:
				for x in 16:
					var gx := sx * 16 + x
					var gy := sy * 16 + y
					# The first two Ingos atlas tiles are uninterrupted snow. Using
					# their native surface type also enables winter ground details.
					var tile := (gx * 3 + gy * 7) % 2
					var code := tile | (((gx * 7 + gy * 3) % 4) << 14)
					data.encode_u16(5 + 33 * 33 * 8 + (y * 16 + x) * 2, code)
			archive.files["zone11%03d%03d.sec" % [sx, sy]] = data
			if not rendered:
				ground._read_vertices(data, 5, sx, sy, true)
				ground._record_ground(ground._read_u16s(data, 5 + 33 * 33 * 8), sx, sy)
	if rendered:
		ground._load_atlases()
		ground._build(archive)
		ArenaGroundDetails.install(ground)
		# Fade the distant woodland into the arena's dark backdrop. The native
		# campaign profile is too broad for this compact, overhead field.
		Gfx.set_border(ground.size_ei(), 8.0)
	else:
		ground.water_base = ground.water.duplicate()
		ground.surface.fill(0)
	ground.set_process(false)
	return ground


static func scenery(ground: EITerrain, parent: Node3D) -> Array[Node3D]:
	var placed: Array[Node3D] = []
	var scene := EIMapScene.new()
	scene.terrain = ground
	# Uneven groups frame a clear fighting ground: a broken gateway, exposed
	# rock shelves, frost-covered conifers and smaller saplings between them.
	var pieces := [
		["stst13", "columnruins01", 15.5, 17.0, -0.35, 0.4, 0.85],
		["stst13", "columnruins01", 48.0, 46.5, -0.5, -0.5, 0.80],
		["nast15", "stone03", 13.5, 25.0, -0.4, 0.5, 0.85],
		["nast16", "stone03", 49.5, 37.0, -0.45, 2.0, 0.8],
		["nast8", "stone03", 22.0, 48.5, -0.3, 1.0, 0.8],
		["nast7", "stone03", 38.0, 15.0, -0.2, 2.2, 1.1],
		["nast6", "stone03", 45.0, 15.5, -0.3, 0.6, 1.0],
		["nast9", "stone03", 15.5, 39.0, -0.3, 1.3, 0.7],
		["nafltr59", "tree03", 14.0, 31.0, -0.15, 1.1, 0.8],
		["nafltr56", "tree03", 12.5, 35.5, -0.15, 2.8, 0.8],
		["nafltr57", "tree03", 14.5, 44.0, -0.15, 3.0, 0.75],
		["nafltr59", "tree03", 46.8, 22.5, -0.15, 0.5, 0.50],
		["nafltr56", "tree03", 50.2, 28.0, -0.15, 2.0, 0.60],
		["nafltr69", "tree03", 47.8, 42.0, -0.15, 1.4, 0.60],
		["nafltr57", "tree03", 29.0, 13.5, -0.15, 1.9, 0.85],
		["nafltr70", "tree03", 35.0, 49.5, -0.15, 0.5, 0.7],
		["nafltr69", "tree03", 40.0, 51.0, -0.15, 1.8, 0.8],
		["naflbu6", "tree03", 17.0, 27.0, 0.0, 0.2, 0.85],
		["naflbu6", "tree03", 47.0, 40.5, 0.0, 2.2, 0.9],
		["naflbu9", "tree03", 25.0, 16.0, -0.15, 0.8, 0.8],
		["naflbu9", "tree03", 29.0, 47.5, -0.15, 1.1, 0.65],
	]
	for piece: Array in pieces:
		var record := {"kind": "OBJECT", "template": piece[0], "texture": piece[1],
			"complexion": Vector3(0.5, 0.5, 0.5), "parts": [], "name": "ArenaScenery",
			"position": Vector3(piece[2], piece[3], piece[4]), "rotation": Quaternion(Vector3.UP, piece[5])}
		var object := scene.place_object(record, parent)
		if object:
			object.scale = Vector3.ONE * float(piece[6])
			_keep_clearing(object, ground)
			if String(piece[0]).begins_with("nast") or String(piece[0]).begins_with("stst"):
				_snow_caps(object)
			placed.append(object)
	scene.free()
	return placed


## Both companies share the same clear field, including after X reflection.
## Native navigation uses unscaled FIG boxes; small decorative meshes can
## otherwise conceal large blockers. Keep those boxes and the visible model
## beyond the largest movement-class dilation, instead of changing formations.
static func _keep_clearing(object: Node3D, ground: EITerrain) -> void:
	var geometry := EIFigureGeometry.of(object)
	if geometry.is_empty(): return
	var record: Dictionary = object.get_meta("ei")
	var at: Vector3 = record.position
	var extent := maxf(1.0, object.scale.x)
	var transform := Transform3D(Basis(record.rotation).scaled(Vector3.ONE * extent), EISpace.vec(at))
	var box := transform * EIFigureGeometry.box(geometry)
	var footprint := Rect2(Vector2(box.position.x, -box.end.z), Vector2(box.size.x, box.size.z))
	var clearing := PLAY_AREA.grow(2.0)
	if not clearing.intersects(footprint): return
	var shifts := [Vector2(clearing.position.x - footprint.end.x, 0),
		Vector2(clearing.end.x - footprint.position.x, 0),
		Vector2(0, clearing.position.y - footprint.end.y),
		Vector2(0, clearing.end.y - footprint.position.y)]
	var shift: Vector2 = shifts[0]
	for candidate: Vector2 in shifts:
		if candidate.length_squared() < shift.length_squared(): shift = candidate
	at += Vector3(shift.x, shift.y, 0)
	record.position = at
	object.position = EISpace.pos(at.x, at.y, ground.height_at(at.x, at.y) + at.z)


static var _snow_materials := {}


## Snow settles on upward-facing rock and ruin surfaces; their native textures
## remain exposed on the sides. Local material copies never alter campaign art.
static func _snow_caps(object: Node3D) -> void:
	for mesh: MeshInstance3D in object.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as ShaderMaterial
			if source == null: continue
			if not _snow_materials.has(source):
				var material := source.duplicate() as ShaderMaterial
				var shader := source.shader.duplicate() as Shader
				shader.code = shader.code.replace("ALBEDO = t.rgb;", """ALBEDO = t.rgb;
	vec3 snow_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float snow_cap = smoothstep(0.42, 0.82, snow_normal.y);
	ALBEDO = mix(ALBEDO, vec3(0.82, 0.89, 0.95), snow_cap * 0.94);""")
				material.shader = shader
				_snow_materials[source] = material
			if mesh.material_override != null:
				mesh.material_override = _snow_materials[source]
				break
			mesh.set_surface_override_material(surface, _snow_materials[source])
