class_name ArenaTerrain
extends RefCounted
## Authored clearing surrounded by snow-covered Ingos ruins. The atlas and figure assets
## come from the installed game. This does not load any campaign scripts.

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
					var height := maxf(0, rim - 17) * 0.055
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
	var pieces := [
		["stst13", "columnruins01", 16.0, 17.0, -0.1, 0.4],
		["stst13", "columnruins01", 48.0, 17.0, -0.1, 2.2],
		["stst13", "columnruins01", 16.0, 47.0, -0.2, 1.3],
		["stst13", "columnruins01", 48.0, 47.0, -0.2, -0.5],
		["nast15", "stone03", 13.0, 25.0, -0.2, 0.5],
		["nast16", "stone03", 50.5, 39.0, -0.3, 2.0],
		["nast8", "stone03", 23.0, 48.0, -0.2, 1.0],
		["nast8", "stone03", 40.0, 16.0, -0.2, 2.2],
		["nafltr70", "tree03", 10.0, 18.0, -0.15, 1.1],
		["nafltr70", "tree03", 53.0, 19.0, -0.15, 2.8],
		["nafltr70", "tree03", 12.0, 45.0, -0.15, 3.0],
		["nafltr70", "tree03", 53.0, 46.0, -0.15, 0.5],
		["naflbu6", "tree03", 16.0, 37.0, 0.0, 0.2],
		["naflbu6", "tree03", 46.0, 26.0, 0.0, 2.2],
	]
	for piece: Array in pieces:
		var record := {"kind": "OBJECT", "template": piece[0], "texture": piece[1],
			"complexion": Vector3(0.5, 0.5, 0.5), "parts": [], "name": "ArenaScenery",
			"position": Vector3(piece[2], piece[3], piece[4]), "rotation": Quaternion(Vector3.UP, piece[5])}
		var object := scene.place_object(record, parent)
		if object: placed.append(object)
	scene.free()
	return placed
