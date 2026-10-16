class_name ArenaTerrain
extends RefCounted
## Authored clearing surrounded by Gipath ruins. The atlas and figure assets
## come from the installed game. This does not load any campaign scripts.

class Sectors extends EIResArchive:
	var files := {}
	func read(key: String) -> PackedByteArray:
		return files.get(key, PackedByteArray())


static func create(rendered := true) -> EITerrain:
	var source := EIResArchive.open_path(GameData.root.path_join("maps/basegipat.mpr"))
	if source == null: return null
	var header := source.read("basegipat.mp").duplicate()
	if header.size() < 38: return null
	header.encode_u32(8, 2); header.encode_u32(12, 2)
	header.encode_float(4, 8.0)
	var ground := EITerrain.new()
	ground.map_name = "arena_courtyard"
	ground.resource_prefix = "basegipat"
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
					var tile := 0
					var distance := Vector2(gx - 15.5, gy - 15.5).length()
					# Broken paving and encroaching grass form an old circular
					# courtyard. Native transition tiles soften the perimeter.
					if distance < 5.6:
						tile = 6
					elif distance < 7.5:
						tile = 49 + (gx * 3 + gy * 5) % 15
					elif gy in [15, 16] and gx > 4 and gx < 27:
						tile = 6
					else:
						tile = (gx * 3 + gy * 7) % 6
					var code := tile | (((gx * 7 + gy * 3) % 4) << 14)
					data.encode_u16(5 + 33 * 33 * 8 + (y * 16 + x) * 2, code)
			archive.files["basegipat%03d%03d.sec" % [sx, sy]] = data
			if not rendered:
				ground._read_vertices(data, 5, sx, sy, true)
				ground._record_ground(ground._read_u16s(data, 5 + 33 * 33 * 8), sx, sy)
	if rendered:
		ground._load_atlases()
		ground._build(archive)
		# The campaign's broad border fog would cover most of this compact map.
		Gfx.set_border(ground.size_ei(), 0.25)
		var paving := MeshInstance3D.new()
		paving.name = "CourtyardPaving"
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(32, 32)
		paving.mesh = mesh
		paving.position = Vector3(32, 0.025, -32)
		paving.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = preload("res://src/ui/arena_paving.gdshader")
		material.set_shader_parameter("paving", preload("res://assets/arena/courtyard.png"))
		paving.material_override = material
		ground.add_child(paving)
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
		["nast15", "stone02", 13.0, 25.0, -0.2, 0.5],
		["nast16", "stone02", 50.5, 39.0, -0.3, 2.0],
		["nast8", "stone02", 23.0, 48.0, -0.2, 1.0],
		["nast8", "stone02", 40.0, 16.0, -0.2, 2.2],
		["nafltr56", "tree02", 10.0, 18.0, -0.15, 1.1],
		["nafltr56", "tree02", 53.0, 19.0, -0.15, 2.8],
		["nafltr56", "tree02", 12.0, 45.0, -0.15, 3.0],
		["nafltr56", "tree02", 53.0, 46.0, -0.15, 0.5],
		["naflbu6", "tree02", 16.0, 37.0, 0.0, 0.2],
		["naflbu6", "tree02", 46.0, 26.0, 0.0, 2.2],
	]
	for piece: Array in pieces:
		var record := {"kind": "OBJECT", "template": piece[0], "texture": piece[1],
			"complexion": Vector3(0.5, 0.5, 0.5), "parts": [], "name": "ArenaScenery",
			"position": Vector3(piece[2], piece[3], piece[4]), "rotation": Quaternion(Vector3.UP, piece[5])}
		var object := scene.place_object(record, parent)
		if object: placed.append(object)
	scene.free()
	return placed
