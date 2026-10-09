extends RefCounted
## Immutable, optional ground-cover snapshot. TerrainDetails owns streaming,
## workers, barriers and pressure; this class never reads live scene state in a job.
const Contact = preload("res://src/game/fx/biome_cover_contact.gd")
const Geometry = preload("res://src/game/fx/biome_cover_mesh.gd")
const Sea = preload("res://src/game/fx/biome_cover_water.gd")
const Mounds = preload("res://src/game/fx/biome_mounds.gd")
const Families = preload("res://src/game/fx/biome_cover_tiles.gd")
const Regions = preload("res://src/game/fx/biome_cover_regions.gd")
enum Kind { FLOWER, DRY, LEAF, NEEDLES, TWIG, STONE, BUSH, REED, CATTAIL, WRACK, SHELL, SEAGRASS, KELP, SEA_SHELL,
	ASH, SCORIA, OBSIDIAN, CRUST, MOSS, LICHEN, FERN, ROOTS, MUSHROOM, WET, SLAB, RUBBLE, BONES, SKULL, WEB, CRYSTAL }
const DRY_KINDS := 7 # Preserve the original random stream when adding species.
const SPACING := 0.8
const TREE_RANGE := 6.0
const RADII := [0.22,0.30,0.16,0.22,0.38,0.14,0.44,0.38,0.30,0.32,0.15,0.24,0.35,0.15]+Regions.RADII
const BANK_HEIGHT := 2.0 # Tallest scaled cattail plus optional soft-ground lift.
const SHORE_RANGE := 6.0
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
var loose_tiles := PackedByteArray()
var water := PackedFloat32Array()
var surface := PackedFloat32Array()
var uv_table := {}
var images := {}
var families := {} # Original atlas -> immutable per-slot bare/sand corner masks.
var native: RefCounted
var shores := {} # Chunk -> immutable Vector4(water x, height, EI y, 1 river / 2 swamp / 3 sea).
var sea := Sea.new()
var mounds := Mounds.new()
var regions := Regions.new()
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
	# LiA also has a zone9, on gipat2. It is not the base game's Dead City.
	if zone.get("allod","")=="gipat" and zone.get("mpr","")=="zone9": return "dead_city"
	return String(zone.get("allod","unknown")).to_lower()


static func tree_kind(info: Dictionary) -> int:
	var model := String(info.get("template","")).to_lower()
	if model in WOOD: return 3
	if model in BROADLEAF or model == "nafltr59":
		if not EIFigure.sways(model,String(info.get("texture","")),EIFigure.get_model(model),
				PackedStringArray(info.get("parts",[]))): return 3
		return 2 if model == "nafltr59" else 1
	return 0


func configure(terrain: EITerrain, field: RefCounted, atlases: Dictionary, context: String, scenery: Dictionary = {}) -> void:
	size = Vector2i(terrain.size_ei()); grid_w = terrain.grid_w
	map_name = terrain.map_name; biome = context; native = field
	families.clear()
	# GDScript packed-array Variants can share the same mutable wrapper. Copy
	# explicitly before workers publish; a flood may call fill() on the source.
	heights = terrain.heights.duplicate(); xy = terrain.land_xy.duplicate(); tiles = terrain.land_tile.duplicate()
	ground = terrain.ground.duplicate(); water = terrain.water.duplicate(); surface = terrain.surface.duplicate()
	loose_tiles.resize(tiles.size())
	for i in tiles.size():
		var type_id := tiles[i]&0x3fff
		loose_tiles[i] = int(type_id<terrain.tile_types.size() and terrain.tile_types[type_id] in SoftGroundDeform.TYPES)
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
		if terrain.texture_size==512 and terrain.tile_size==64:
			var masks := Families.masks(copy)
			if not masks.is_empty(): families[key] = masks
	_prepare_shores(terrain)
	regions.configure(terrain,self,scenery)
	mounds.configure(terrain,self)


func _prepare_shores(terrain: EITerrain) -> void:
	# Use actual wet mesh centres at their authored mean level. The gameplay
	# water[] grid uses a maximum corner and can mark a dry slope as wet.
	# No animation phase is sampled: wind cannot regenerate the shoreline.
	if biome in ["cave","unknown"]: return
	for node in terrain.get_children():
		if not node is MeshInstance3D or not String(node.name).begins_with("Water_") or node.mesh == null: continue
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var owners: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		assert(vertices.size()%9 == 0 and owners.size() == vertices.size())
		for first in range(0,vertices.size(),9):
			var centre := vertices[first+4]
			var m := int(owners[first+4].y+0.5)%64
			var tile := Vector2i(roundi(vertices[first].x/2.0),roundi(-vertices[first].z/2.0))
			var type := terrain.liquid_ground[tile.y*2*size.x+tile.x*2]
			if not type in [6,14] or m >= terrain.materials.size(): continue
			var emission := terrain.material_e(m)
			if emission.r+emission.g+emission.b > 0.0: continue
			var same := true
			for i in 9:
				if int(owners[first+i].y+0.5)%64 != m: same = false; break
			if not same: continue # Shared vertices can belong to another liquid.
			if type==6 and m in EITerrain.SEA_MATERIALS.get(terrain.resource_prefix,[]):
				sea.add_tile(tile,vertices.slice(first,first+9),m,terrain.materials[m],float(terrain.water_offsets.get(m,0.0)))
			var p := Vector2(centre.x,-centre.z)
			var hit := sample(p)
			var level := centre.y+float(terrain.water_offsets.get(m,0.0))
			if hit.is_empty() or level <= float(hit.height)+0.10: continue
			var cell := Vector2i(p.floor())
			if surface[cell.y*size.x+cell.x] > level: continue
			var channel := 2 if type == 14 else (3 if m in EITerrain.SEA_MATERIALS.get(terrain.resource_prefix,[]) else 1)
			var point := Vector4(p.x,level,p.y,channel)
			var lo := Vector2i(((p-Vector2.ONE*SHORE_RANGE)/8.0).floor())
			var hi := Vector2i(((p+Vector2.ONE*SHORE_RANGE)/8.0).floor())
			for y in range(lo.y,hi.y+1):
				for x in range(lo.x,hi.x+1):
					var key := Vector2i(x,y)
					if not shores.has(key): shores[key] = PackedVector4Array()
					shores[key].append(point)


func shore(p: Vector2) -> Vector3:
	var result := Vector3(INF,0,0) # Distance, level, classification.
	var closest := INF
	for point: Vector4 in shores.get(Vector2i((p/8.0).floor()),PackedVector4Array()):
		var distance := p.distance_to(Vector2(point.x,point.z))
		if distance < closest:
			closest = distance
			# Centres are on the original 2 m tile lattice; this is an
			# approximate bank band, not a collision or exact water query.
			result = Vector3(maxf(distance-1.0,0.0),point.y,point.w)
	return result


func bank_weights(p: Vector2, hit: Dictionary, nearby: Vector3) -> Vector4:
	var out := Vector4.ZERO
	if biome in ["cave","unknown"] or not int(hit.type) in [0,1,3,5,11]: return out
	var above := float(hit.height)-nearby.y
	if above < 0.06 or above > 0.8: return out # No reeds on cliffs above water.
	var key := Vector2i((p/4.0).floor())
	var seed := hash("%s:banks:%d:%d" % [map_name,key.x,key.y])
	var centre := Vector2(key)*4.0+Vector2(1.0+float(seed&255)/255.0*2.0,1.0+float((seed>>8)&255)/255.0*2.0)
	var patch := 1.0-smoothstep(0.5,1.8,p.distance_to(centre))
	if nearby.z == 2:
		out.x = (1.0-smoothstep(1.0,3.0,nearby.x))*patch*0.95
		out.y = (1.0-smoothstep(0.7,2.2,nearby.x))*patch*0.30
	elif nearby.z == 1:
		out.x = (1.0-smoothstep(0.4,1.6,nearby.x))*patch*0.55
	elif nearby.z == 3 and beach_sand(hit) and absf((hit.normal as Vector3).y) >= 0.94:
		out.z = smoothstep(0.1,0.4,nearby.x)*(1.0-smoothstep(1.0,2.0,nearby.x))*patch*0.80
		out.w = (1.0-smoothstep(2.0,5.0,nearby.x))*0.12
	return out


func family_mask(hit: Dictionary) -> int:
	var code := int(hit.get("code",-1))
	var slots: PackedByteArray = families.get((code>>6)&255,PackedByteArray())
	return int(slots[code&63]) if code>=0 and not slots.is_empty() else 0


func beach_sand(hit: Dictionary) -> bool:
	return int(hit.type)==3 or (family_mask(hit)&0xf0)!=0


func bare_share(hit: Dictionary) -> float:
	var mask := family_mask(hit)&15
	if mask==0: return 0.0
	if mask==15: return 1.0
	var slot := int(hit.code)&63
	# Metadata corners use the original atlas V direction; our decoded image
	# and hit UV use flipped V. Invert once, then remove the 8-pixel tile gutter.
	# The sampled UV already includes rotation and authored triangle jitter.
	var uv: Vector2 = hit.uv
	var p := ((Vector2(uv.x,1.0-uv.y)*512.0-Vector2(slot%8,slot/8)*64.0-Vector2.ONE*8.0)/48.0).clamp(Vector2.ZERO,Vector2.ONE)
	return lerpf(lerpf(float(mask&1),float((mask>>1)&1),p.x),lerpf(float((mask>>3)&1),float((mask>>2)&1),p.x),p.y)


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
	if biome == "unknown": return false
	var hit := dry_surface(p)
	if biome=="cave": return not hit.is_empty() and int(hit.type) in [0,1,2,3,4]
	return not hit.is_empty() and (int(hit.type) in [0,3,5,9,11,12] or bank_weights(p,hit,shore(p)).x > 0.0)


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
	var woods := biome in ["gipat","ingos","dead_city"]
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
	if biome=="dead_city":
		if type in [1,2,4,5,11] and not green: out[Kind.DRY]=0.65
		if not snow: out[Kind.LEAF]=maxf(influence.x,influence.z)*(0.35 if type in [3,5,11] else 1.05)
		if type in [1,2,4,5,11]: out[Kind.BUSH]=0.022
	if type in [0,5,11]:
		# Meadow/dry tufts fade toward verified soil, rock and paving corners.
		# Snow straw, sand tufts and fallen litter retain their existing rules.
		var meadow := 1.0-smoothstep(0.30,0.75,bare_share(hit))
		out[Kind.FLOWER] *= meadow
		if biome!="dead_city": out[Kind.DRY] *= meadow
	return out


func footprint(p: Vector2, hit: Dictionary, kind: int, radius: float) -> bool:
	for offset: Vector2 in [Vector2(-1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,1)]:
		var edge := dry_surface(p+offset*radius)
		if edge.is_empty() or absf(float(edge.height)-float(hit.height)) > 0.12: return false
		if kind in [Kind.LEAF,Kind.NEEDLES,Kind.TWIG,Kind.STONE,Kind.WRACK,Kind.SHELL] or kind>=Regions.FIRST:
			var n: Vector3 = hit.normal
			var plane := float(hit.height)-(n.x*offset.x-n.z*offset.y)*radius/n.y
			if absf(float(edge.height)-plane) > 0.025: return false
		if int(edge.type) in [6,7,8,10,13,14,15]: return false
		if kind == Kind.FLOWER and (int(edge.type) != 0 or not TerrainDetails.green_colour(edge.colour) or bare_share(edge)>0.75): return false
		if kind in [Kind.WRACK,Kind.SHELL] and not beach_sand(edge): return false
	return true


func surface_anchor(p: Vector2) -> Vector4:
	# Most cover never touches loose terrain: retain the cheap original shader
	# path there. Include neighbouring cells and their authored vertex offsets.
	var cell := Vector2i(p.floor())
	var near_soft := false
	for y in range(maxi(0,(cell.y-3)/2),mini(size.y/2-1,(cell.y+3)/2)+1):
		for x in range(maxi(0,(cell.x-3)/2),mini(size.x/2-1,(cell.x+3)/2)+1):
			if loose_tiles[y*(size.x/2)+x]: near_soft = true; break
		if near_soft: break
	if not near_soft: return Vector4(-1,0,0,0)
	var anchor := Vector4.INF
	for dy in range(-1,2):
		for dx in range(-1,2):
			var q := cell+Vector2i(dx,dy)
			if q.x<0 or q.y<0 or q.x>=size.x or q.y>=size.y: continue
			var corners := [q,q+Vector2i(1,0),q+Vector2i(0,1),q+Vector2i.ONE]
			var points: Array[Vector2] = []
			for c: Vector2i in corners: points.append(Vector2(c)+xy[c.y*grid_w+c.x])
			for side in 2:
				var tri := [2,1,0] if side==0 else [1,2,3]
				var a: Vector2 = points[tri[0]]; var b: Vector2 = points[tri[1]]; var c: Vector2 = points[tri[2]]
				var determinant := (b-a).cross(c-a)
				if absf(determinant)<1e-7: continue
				var u := (p-a).cross(c-a)/determinant; var v := (b-a).cross(p-a)/determinant
				if u< -1e-5 or v< -1e-5 or u+v>1.00001: continue
				# Folded/overlapping triangles can exchange the topmost surface
				# after a footprint. Omit these rare ambiguous roots instead of
				# performing the scenery effect's nine-cell search per vertex.
				if anchor.is_finite(): return Vector4.INF
				anchor = Vector4(q.x*2+side,q.y,u,v)
	return anchor


func records(key: Vector2i, boxes: Array, trees: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new(); rng.seed = hash("%s:cover:%d:%d" % [map_name,key.x,key.y])
	for y in 10:
		for x in 10:
			var p := Vector2(key)*8.0+Vector2(x+rng.randf_range(0.15,0.85),y+rng.randf_range(0.15,0.85))*SPACING
			# Consume every species' random input even if this point is rejected.
			var rolls := PackedFloat32Array()
			for i in DRY_KINDS: rolls.append(rng.randf())
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
			# Species use independent rolls on one placement lattice. A solid
			# stone reserves its root so a tuft/flower/bush cannot sprout inside
			# it. Consume the same random stream and retain all other roots.
			var stone := rolls[Kind.STONE] < density[Kind.STONE]*SPACING*SPACING and footprint(p,hit,Kind.STONE,RADII[Kind.STONE]*scale)
			var anchor := Vector4(-2,0,0,0)
			for kind in DRY_KINDS:
				var fitted := scale/3.0 if biome=="dead_city" and kind==Kind.BUSH else scale
				if kind == Kind.STONE:
					if not stone: continue
				else:
					if stone and kind in [Kind.FLOWER,Kind.DRY,Kind.BUSH]: continue
					if rolls[kind] >= density[kind]*SPACING*SPACING or not footprint(p,hit,kind,RADII[kind]*fitted): continue
				if anchor.x == -2: anchor = surface_anchor(p)
				if not anchor.is_finite(): break
				result.append({"kind":kind,"p":p,"height":float(hit.height),"normal":hit.normal,"colour":hit.colour,
					"angle":angle,"scale":fitted,"seed":seed,"snow":int(hit.type) in [9,12],"flower":flowers.y,"cold":biome=="ingos","anchor":anchor})
				if biome=="dead_city": result[-1]["dead_city"]=true
	result.append_array(bank_records(key,boxes))
	result.append_array(sea_records(key,boxes))
	result.append_array(regions.records(self,key,boxes))
	return result


func bank_records(key: Vector2i, boxes: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not shores.has(key): return result
	var rng := RandomNumberGenerator.new(); rng.seed = hash("%s:bank-cover:%d:%d" % [map_name,key.x,key.y])
	for y in 10:
		for x in 10:
			var p := Vector2(key)*8.0+Vector2(x+rng.randf_range(0.15,0.85),y+rng.randf_range(0.15,0.85))*SPACING
			var rolls := Vector4(rng.randf(),rng.randf(),rng.randf(),rng.randf())
			var angle := rng.randf()*TAU; var scale := rng.randf_range(0.80,1.15); var seed := rng.randf()
			var hit := dry_surface(p)
			if hit.is_empty(): continue
			var density := bank_weights(p,hit,shore(p))
			if density == Vector4.ZERO: continue
			var blocked := false
			for box: Dictionary in boxes:
				var inverse: Transform3D = box.inverse
				if (box.box as AABB).intersects_segment(inverse*Vector3(p.x,float(hit.height)-0.025,-p.y),inverse*Vector3(p.x,float(hit.height)+BANK_HEIGHT,-p.y)) != null:
					blocked = true; break
			if blocked: continue
			var anchor := Vector4(-2,0,0,0)
			for i in 4:
				var kind := DRY_KINDS+i
				if rolls[i] >= density[i] or not footprint(p,hit,kind,RADII[kind]*scale): continue
				if anchor.x == -2: anchor = surface_anchor(p)
				if not anchor.is_finite(): break
				result.append({"kind":kind,"p":p,"height":float(hit.height),"normal":hit.normal,"colour":hit.colour,
					"angle":angle,"scale":scale,"seed":seed,"snow":false,"flower":0.0,"cold":biome=="ingos","anchor":anchor})
	return result


func sea_surface(p: Vector2) -> Dictionary:
	var water_plane := sea.sample(p)
	if water_plane.w <= 0.0: return {}
	var hit := sample(p)
	if hit.is_empty() or absf((hit.normal as Vector3).y)<0.90: return {}
	var at := int(p.y)*size.x+int(p.x)
	if surface[at]>float(hit.height)+0.08 or not int(ground[at]) in [0,1,2,3,4,5,9,11,12]: return {}
	hit.colour = colour(hit); hit.depth = water_plane.x*p.x-water_plane.y*p.y+water_plane.z-float(hit.height)
	if (hit.colour as Color).a<0.5 or hit.depth<0.12: return {}
	return hit


func sea_records(key: Vector2i, boxes: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not sea.chunks.has(key): return result
	var rng := RandomNumberGenerator.new(); rng.seed = hash("%s:sea-cover:%d:%d" % [map_name,key.x,key.y])
	for y in 10:
		for x in 10:
			var p := Vector2(key)*8.0+Vector2(x+rng.randf_range(0.15,0.85),y+rng.randf_range(0.15,0.85))*SPACING
			var rolls := Vector3(rng.randf(),rng.randf(),rng.randf())
			var angle := rng.randf()*TAU; var scale := rng.randf_range(0.80,1.15); var seed := rng.randf()
			var hit := sea_surface(p)
			if hit.is_empty(): continue
			var depth := float(hit.depth)
			var patch := 0.25+0.75*patch(p).x
			var density := Vector3(smoothstep(0.4,0.7,depth)*(1.0-smoothstep(2.5,3.5,depth))*0.85*patch,
				smoothstep(1.5,2.0,depth)*(1.0-smoothstep(5.5,6.5,depth))*0.18*patch,
				(1.0-smoothstep(1.0,2.0,depth))*0.08)
			var anchor := Vector4(-2,0,0,0)
			for i in 3:
				if rolls[i]>=density[i]: continue
				if anchor.x == -2: anchor=surface_anchor(p)
				if not anchor.is_finite(): break
				var kind := Kind.SEAGRASS+i
				var radius: float = RADII[kind]*scale
				var low := sea.ceiling(p,radius+0.04)
				# Size plants below the worst-wave surface, including root lift.
				var lift := SoftGroundDeform.DEPTH if anchor.x>=0 else 0.0
				# The shell also tilts with a seabed normal down to y=0.90.
				var plant_height: float = [0.70,1.40,0.13][i]
				var fitted := minf(scale,(low-float(hit.height)-lift-0.03)/plant_height)
				if fitted<0.25: continue
				var clear := true
				for offset: Vector2 in [Vector2(-1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,1)]:
					var edge := sea_surface(p+offset*radius)
					if edge.is_empty() or absf(float(edge.height)-float(hit.height))>0.12: clear=false; break
					if i==2:
						var n: Vector3 = hit.normal
						var plane: float = float(hit.height)-(n.x*offset.x-n.z*offset.y)*radius/n.y
						if absf(float(edge.height)-plane)>0.025: clear=false; break
				if not clear: continue
				for box: Dictionary in boxes:
					var inverse: Transform3D = box.inverse
					if (box.box as AABB).intersects_segment(inverse*Vector3(p.x,float(hit.height)-0.025,-p.y),inverse*Vector3(p.x,float(hit.height)+BANK_HEIGHT,-p.y)) != null:
						clear=false; break
				if not clear: continue
				result.append({"kind":kind,"p":p,"height":float(hit.height),"normal":hit.normal,"colour":hit.colour,
					"angle":angle,"scale":fitted,"seed":seed,"snow":false,"flower":0.0,"cold":false,"anchor":anchor,"underwater":true})
	return result


func build(key: Vector2i, boxes: Array, trees: Array, mound_boxes: Array = []) -> Dictionary:
	var placed := records(key,boxes,trees)
	var geometry := Geometry.new()
	var arrays := geometry.build(placed,key,sea if not sea.tiles.is_empty() else null,self if regions.cave else null)
	return {"records":placed,"arrays":arrays,"lods":geometry.lods(),"contacts":Contact.build(self,placed,key),
		"mounds":mounds.build(self,key,mound_boxes if not mound_boxes.is_empty() else boxes)}


class ChunkJob extends RefCounted:
	var grass: RefCounted
	var cover: RefCounted
	var key: Vector2i
	var boxes: Array
	var trees: Array
	var mound_boxes: Array
	var result := {}
	func run() -> void:
		if grass: grass.run(); result = grass.read_result()
		else:
			var transforms: Array[Transform3D] = []; var colours: Array[Color] = []; var custom: Array[Color] = []
			result = {"transforms":transforms,"colours":colours,"custom":custom}
		result.cover = cover.build(key,boxes,trees,mound_boxes)
	func read_result() -> Dictionary:
		return result
