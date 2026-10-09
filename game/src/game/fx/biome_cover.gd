extends RefCounted
## Immutable, optional dry-land cover snapshot. TerrainDetails owns streaming,
## workers, barriers and pressure; this class never reads live scene state in a job.
const Geometry = preload("res://src/game/fx/biome_cover_mesh.gd")
enum Kind { FLOWER, DRY, LEAF, NEEDLES, TWIG, STONE, BUSH }
const SPACING := 0.8
const TREE_RANGE := 6.0
const RADII := [0.22,0.30,0.16,0.22,0.38,0.14,0.44]
const BROADLEAF := ["nafltr56","nafltr57","nafltr75","nafltr76"]
const WOOD := ["nafltr20","nafltr21","nafltr22","nafltr23","nafltr68","nafltr69","nafltr70","nafltr74","nafltr83","nafltr86"]
var size := Vector2i.ZERO
var grid_w := 0
var map_name := ""
var biome := "unknown"
var heights := PackedFloat32Array()
var xy := PackedVector2Array()
var tiles := PackedInt32Array()
var ground := PackedByteArray()
var water := PackedFloat32Array()
var surface := PackedFloat32Array()
var uv_table := {}
var images := {}
var native: RefCounted
static var _campaign: CampaignMap
static var _texts_id := 0


static func region(terrain: EITerrain) -> String:
	var world := terrain.game_world()
	var zone: Dictionary = world.zone if world else {}
	if zone.is_empty() and GameData.texts:
		if _campaign == null or _texts_id != GameData.texts.get_instance_id():
			_campaign = CampaignMap.load_from(GameData.texts)
			_texts_id = GameData.texts.get_instance_id()
		# Some campaigns reuse a map in different contexts. Do not arbitrarily
		# choose the first zone when the owning world has not been assigned yet.
		for candidate: Dictionary in _campaign.zones.values():
			if candidate.get("mpr","") != terrain.map_name: continue
			if not zone.is_empty() and zone != candidate: return "unknown"
			zone = candidate
	if String(zone.get("sky","")).to_lower() == "cave": return "cave"
	return String(zone.get("allod","unknown")).to_lower()


static func tree_kind(info: Dictionary) -> int:
	var model := String(info.get("template","")).to_lower()
	if model in WOOD: return 3
	if model in BROADLEAF or model == "nafltr59":
		if not EIFigure.sways(model,String(info.get("texture","")),EIFigure.get_model(model),
				PackedStringArray(info.get("parts",[]))): return 3
		return 2 if model == "nafltr59" else 1
	return 0


func configure(terrain: EITerrain, field: RefCounted, atlases: Dictionary, context: String) -> void:
	size = Vector2i(terrain.size_ei()); grid_w = terrain.grid_w
	map_name = terrain.map_name; biome = context; native = field
	# GDScript packed-array Variants can share the same mutable wrapper. Copy
	# explicitly before workers publish; a flood may call fill() on the source.
	heights = terrain.heights.duplicate(); xy = terrain.land_xy.duplicate(); tiles = terrain.land_tile.duplicate()
	ground = terrain.ground.duplicate(); water = terrain.water.duplicate(); surface = terrain.surface.duplicate()
	for code: int in tiles:
		if uv_table.has(code): continue
		var uvs := PackedVector2Array()
		for y in 3:
			for x in 3: uvs.append(terrain._tile_uv(code,x,y)[0])
		uv_table[code] = uvs
	for key: int in atlases:
		var original: Image = atlases[key]
		if original == null: continue
		var copy := original.duplicate() as Image
		if copy.is_compressed(): copy.decompress()
		images[key] = copy


func sample(p: Vector2) -> Dictionary:
	if native: return native.sample(p)
	if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y: return {}
	# Same authored jittered triangles/rotated atlas UVs as the existing grass.
	var cell := Vector2i(p.floor())
	for delta: Vector2i in [Vector2i.ZERO,Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
		var q := cell+delta
		if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y: continue
		var corners := [q,q+Vector2i(1,0),q+Vector2i(0,1),q+Vector2i.ONE]
		var points: Array[Vector2] = []; var hs: Array[float] = []
		for c: Vector2i in corners:
			var at := c.y*grid_w+c.x
			points.append(Vector2(c)+xy[at]); hs.append(heights[at])
		for tri: Array in [[2,1,0],[1,2,3]]:
			var a: Vector2 = points[tri[0]]; var b: Vector2 = points[tri[1]]; var c: Vector2 = points[tri[2]]
			var determinant := (b-a).cross(c-a)
			if absf(determinant) < 1e-7: continue
			var u := (p-a).cross(c-a)/determinant; var v := (b-a).cross(p-a)/determinant
			if u < -1e-5 or v < -1e-5 or u+v > 1.00001: continue
			var code := tiles[(q.y/2)*(size.x/2)+q.x/2]
			var uv := Vector2.ZERO; var h := 0.0; var vertices: Array[Vector3] = []
			var weights := [1.0-u-v,u,v]
			for j in 3:
				var at: int = tri[j]; var corner: Vector2i = corners[at]-Vector2i(q.x/2,q.y/2)*2
				uv += (uv_table[code] as PackedVector2Array)[corner.y*3+corner.x]*weights[j]
				h += hs[at]*weights[j]; vertices.append(Vector3(points[at].x,hs[at],-points[at].y))
			return {"code":code,"uv":uv,"height":h,"normal":(vertices[2]-vertices[0]).cross(vertices[1]-vertices[0]).normalized()}
	return {}


func colour(hit: Dictionary) -> Color:
	var image: Image = images.get((int(hit.code)>>6)&255)
	if image == null: return Color.TRANSPARENT
	return image.get_pixelv(Vector2i((hit.uv as Vector2)*Vector2(image.get_size())).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE))


func dry_surface(p: Vector2) -> Dictionary:
	var hit := sample(p)
	if hit.is_empty() or absf((hit.normal as Vector3).y) < 0.90: return {}
	var at := int(p.y)*size.x+int(p.x)
	if surface[at] > float(hit.height)+0.08 or water[at] > float(hit.height)-0.06: return {}
	hit.type = int(ground[at]); hit.colour = colour(hit)
	if (hit.colour as Color).a < 0.5: return {}
	return hit


func pressure_allowed(p: Vector2) -> bool:
	if biome in ["cave","unknown"]: return false
	var hit := dry_surface(p)
	return not hit.is_empty() and int(hit.type) in [0,3,5,9,11,12]


static func tree_influence(p: Vector2, trees: Array) -> Vector3:
	var result := Vector3.ZERO
	for tree: Dictionary in trees:
		var amount := 1.0-smoothstep(1.0,TREE_RANGE,p.distance_to(tree.p))
		var channel := int(tree.kind)-1
		result[channel] = maxf(result[channel],amount)
	return result


func patch(p: Vector2) -> Vector3:
	# One sparse flower patch per 8 m cell, shared by both sides of a chunk.
	var key := Vector2i((p/8.0).floor())
	var seed := hash("%s:flowers:%d:%d" % [map_name,key.x,key.y])
	var centre := Vector2(key)*8.0+Vector2(2.0+float(seed&255)/255.0*4.0,2.0+float((seed>>8)&255)/255.0*4.0)
	return Vector3(1.0-smoothstep(0.8,1.6,p.distance_to(centre)),float((seed>>16)&1),float((seed>>17)&255)/255.0)


func weights(hit: Dictionary, influence: Vector3, flowers: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array([0,0,0,0,0,0,0])
	var type: int = hit.type; var c: Color = hit.colour
	# Roads, liquid materials, ice and high rocks are never decorated here.
	if not type in [0,1,2,3,4,5,9,11,12]: return out
	var snow := type in [9,12]
	out[Kind.STONE] = 0.025 if snow else (0.12 if type in [1,2,4,5,11] else 0.025)
	if biome in ["cave","unknown"]: return out
	var green := TerrainDetails.green_colour(c)
	var woods := biome in ["gipat","ingos"]
	if type == 0 and green: out[Kind.FLOWER] = 0.85*flowers.x*(1.0-maxf(influence.x,influence.y)*0.8)
	if type in [5,11] and not green: out[Kind.DRY] = 0.8
	if type == 3: out[Kind.DRY] = 0.12
	if snow and biome == "ingos": out[Kind.DRY] = 0.22*flowers.x
	if woods:
		if not snow:
			out[Kind.LEAF] = influence.x*(0.25 if biome == "ingos" else 0.9)
		out[Kind.NEEDLES] = influence.y*(0.12 if snow else 0.6)
		out[Kind.TWIG] = maxf(influence.x,maxf(influence.y,influence.z))*(0.035 if not snow else 0.012)
	if type in [1,5,11]: out[Kind.BUSH] = 0.008
	return out


func footprint(p: Vector2, hit: Dictionary, kind: int, radius: float) -> bool:
	for offset: Vector2 in [Vector2(-1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,1)]:
		var edge := dry_surface(p+offset*radius)
		if edge.is_empty() or absf(float(edge.height)-float(hit.height)) > 0.12: return false
		if kind in [Kind.LEAF,Kind.NEEDLES,Kind.TWIG,Kind.STONE]:
			var n: Vector3 = hit.normal
			var plane := float(hit.height)-(n.x*offset.x-n.z*offset.y)*radius/n.y
			if absf(float(edge.height)-plane) > 0.025: return false
		if int(edge.type) in [6,7,8,10,13,14,15]: return false
		if kind == Kind.FLOWER and (int(edge.type) != 0 or not TerrainDetails.green_colour(edge.colour)): return false
	return true


func records(key: Vector2i, boxes: Array, trees: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new(); rng.seed = hash("%s:cover:%d:%d" % [map_name,key.x,key.y])
	for y in 10:
		for x in 10:
			var p := Vector2(key)*8.0+Vector2(x+rng.randf_range(0.15,0.85),y+rng.randf_range(0.15,0.85))*SPACING
			# Consume every species' random input even if this point is rejected.
			var rolls := PackedFloat32Array()
			for i in Kind.size(): rolls.append(rng.randf())
			var angle := rng.randf()*TAU; var scale := rng.randf_range(0.80,1.15); var seed := rng.randf()
			var hit := dry_surface(p)
			if hit.is_empty(): continue
			var blocked := false
			for box: Dictionary in boxes:
				var inverse: Transform3D = box.inverse
				if (box.box as AABB).intersects_segment(inverse*Vector3(p.x,float(hit.height)-0.025,-p.y),inverse*Vector3(p.x,float(hit.height)+0.88,-p.y)) != null:
					blocked = true; break
			if blocked: continue
			var flowers := patch(p)
			var density := weights(hit,tree_influence(p,trees),flowers)
			for kind in Kind.size():
				if rolls[kind] >= density[kind]*SPACING*SPACING or not footprint(p,hit,kind,RADII[kind]*scale): continue
				result.append({"kind":kind,"p":p,"height":float(hit.height),"normal":hit.normal,"colour":hit.colour,
					"angle":angle,"scale":scale,"seed":seed,"snow":int(hit.type) in [9,12],"flower":flowers.y,"cold":biome=="ingos"})
	return result


func build(key: Vector2i, boxes: Array, trees: Array) -> Dictionary:
	var placed := records(key,boxes,trees)
	return {"records":placed,"arrays":Geometry.new().build(placed,key)}


class ChunkJob extends RefCounted:
	var grass: RefCounted
	var cover: RefCounted
	var key: Vector2i
	var boxes: Array
	var trees: Array
	var result := {}
	func run() -> void:
		if grass: grass.run(); result = grass.read_result()
		else:
			var transforms: Array[Transform3D] = []; var colours: Array[Color] = []; var custom: Array[Color] = []
			result = {"transforms":transforms,"colours":colours,"custom":custom}
		result.cover = cover.build(key,boxes,trees)
	func read_result() -> Dictionary:
		return result
