extends RefCounted
## Original map evidence for local decoration. No navigation, gameplay unit
## or random global state is created. Liquid queries use the drawn triangles;
## the navigation water grid can be wet beneath a visibly dry bank.
const Cover = preload("res://src/game/fx/biome_cover.gd")
const Wind = preload("res://src/game/fx/weather_wind.gd")
const Water = preload("res://src/game/fx/water_surface.gd")
const DrawnGround = preload("res://src/game/fx/ambient_ground.gd")
const BUCKET := 8.0
const CELL := 32.0
var terrain: EITerrain
var biome := "unknown"
var region := "unknown"
var seed_value := 0
var trees := {}
var boxes := {}
var _signature := []
var _water: Water


func _init(t: EITerrain) -> void:
	terrain = t; biome = Cover.region(t); seed_value = Wind.map_seed(t.map_name)
	region = region_of(biome)
	_water = Water.new(t)
	refresh()


static func region_of(value: String) -> String:
	if value in ["cave","dead_city","unknown"]: return value
	if value == "ingos": return "snow"
	if value == "suslanger": return "desert"
	# LiA's second Gipat is not the base campaign's Dead City.
	if value in ["gipat","gipat2"]: return "outdoor"
	return "unknown"


static func area(type: int) -> String:
	if type==0: return "grass"
	if type in [1,2,4,7,15]: return "bare"
	if type==3: return "sand"
	if type in [5,11]: return "dry"
	if type in [9,10,12]: return "snow"
	if type==6: return "water"
	if type==13: return "lava"
	if type==14: return "swamp"
	return "unknown"


func random(key: Vector2i, salt: int) -> float:
	return Wind.lattice(seed_value ^ Wind.mul32(key.x&0xffffffff,0x85ebca77) ^ Wind.mul32(key.y&0xffffffff,0xc2b2ae3d),salt)


func anchor(key: Vector2i) -> Vector2:
	return Vector2(key)*CELL+Vector2(4.0+24.0*random(key,1),4.0+24.0*random(key,2))


func refresh() -> bool:
	_water.begin_frame()
	# Birth positions must not move with a water wave. Scripted offsets still
	# apply, and each refresh invalidates the query's posed vertex cache.
	_water._waves = false
	var map := terrain.get_parent() as EIMapScene
	var root := map.get_node_or_null("Objects") as Node3D if map else null
	var world := terrain.game_world()
	var signature := [root.get_instance_id() if root else 0,root.get_child_count() if root else 0,
		world.nav.map_rev if world else 0,terrain.surface_rev,terrain.water_offsets.duplicate()]
	if signature==_signature: return false
	_signature = signature; trees.clear(); boxes.clear()
	if root==null: return true
	var inverse := terrain.global_transform.affine_inverse()
	for object: Node3D in root.get_children():
		var info: Dictionary = object.get_meta("ei",{})
		if info.get("kind","")=="UNIT" or String(info.get("template","")).to_lower().begins_with("ef"): continue
		var shown := false
		for mesh: MeshInstance3D in object.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh==null or not mesh.is_visible_in_tree(): continue
			shown = true
			var xf := inverse*mesh.global_transform
			var local := mesh.get_aabb()
			var bounds := xf*local
			var lo := Vector2i((Vector2(bounds.position.x,-bounds.end.z)/BUCKET).floor())
			var hi := Vector2i((Vector2(bounds.end.x,-bounds.position.z)/BUCKET).floor())
			var record := {"inverse":xf.affine_inverse(),"box":local}
			for y in range(lo.y,hi.y+1):
				for x in range(lo.x,hi.x+1):
					var key := Vector2i(x,y)
					if not boxes.has(key): boxes[key] = []
					boxes[key].append(record)
		if not shown or Cover.tree_kind(info)!=1: continue
		var p := inverse*object.global_position
		var point := Vector2(p.x,-p.z)
		var lo := Vector2i(((point-Vector2.ONE*6.0)/BUCKET).floor())
		var hi := Vector2i(((point+Vector2.ONE*6.0)/BUCKET).floor())
		for y in range(lo.y,hi.y+1):
			for x in range(lo.x,hi.x+1):
				var key := Vector2i(x,y)
				if not trees.has(key): trees[key] = PackedVector2Array()
				trees[key].append(point)
	return true


func leafy(p: Vector2) -> bool:
	for point: Vector2 in trees.get(Vector2i((p/BUCKET).floor()),PackedVector2Array()):
		if point.distance_squared_to(p)<36.0: return true
	return false


func clear_at(p: Vector2, height: float) -> bool:
	for record: Dictionary in boxes.get(Vector2i((p/BUCKET).floor()),[]):
		var inverse: Transform3D = record.inverse
		if (record.box as AABB).grow(0.12).intersects_segment(inverse*Vector3(p.x,height+0.05,-p.y),inverse*Vector3(p.x,height+0.40,-p.y))!=null: return false
	return true


## Highest authored land triangle, including the terrain's XY jitter. No
## copy of the map or optional ground-cover field is needed for a few roots.
func ground(p: Vector2, drawn := false) -> Dictionary:
	var size := Vector2i(terrain.size_ei())
	if p.x<0 or p.y<0 or p.x>=size.x or p.y>=size.y: return {}
	var best := {}; var cell := Vector2i(p.floor())
	for dy in range(-1,2):
		for dx in range(-1,2):
			var q := cell+Vector2i(dx,dy)
			if q.x<0 or q.y<0 or q.x>=size.x or q.y>=size.y: continue
			var points: Array[Vector3] = []
			for c: Vector2i in [q,q+Vector2i(1,0),q+Vector2i(0,1),q+Vector2i.ONE]:
				var i := c.y*terrain.grid_w+c.x
				points.append(Vector3(c.x+terrain.land_xy[i].x,terrain.heights[i],-c.y-terrain.land_xy[i].y))
			for tri: Array in [[2,1,0],[1,2,3]]:
				var a: Vector3 = points[tri[0]]; var b: Vector3 = points[tri[1]]; var c: Vector3 = points[tri[2]]
				var ab := Vector2(b.x-a.x,-b.z+a.z); var ac := Vector2(c.x-a.x,-c.z+a.z)
				var det := ab.cross(ac)
				if absf(det)<0.000001: continue
				var ap := p-Vector2(a.x,-a.z); var u := ap.cross(ac)/det; var v := ab.cross(ap)/det
				if u< -0.00001 or v< -0.00001 or u+v>1.00001: continue
				var height := a.y+(b.y-a.y)*u+(c.y-a.y)*v
				if drawn: height=DrawnGround.elevation(terrain,a,b,c,Vector3(1.0-u-v,u,v),q)
				if best.is_empty() or height>float(best.height):
					var code := int(terrain.land_tile[(q.y/2)*(size.x/2)+q.x/2])
					var per_atlas := int(terrain.texture_size/terrain.tile_size)
					var type_index := ((code>>6)&255)*per_atlas*per_atlas+(code&63)
					best = {"height":height,"normal":(c-a).cross(b-a).normalized(),
						"type":int(terrain.tile_types[type_index]) if type_index<terrain.tile_types.size() else 8,"code":code}
	return best


func liquid(p: Vector2) -> Dictionary:
	if p.x<0 or p.y<0 or p.x>=terrain.size_ei().x or p.y>=terrain.size_ei().y: return {}
	var world := terrain.to_global(Vector3(p.x,0,-p.y))
	var hit := _water.sample(Vector2(world.x,world.z))
	if hit.is_empty(): return {}
	var mat := int(hit.material)
	var local := terrain.to_local(Vector3(world.x,float(hit.height),world.z))
	var at := int(p.y)*int(terrain.size_ei().x)+int(p.x)
	var type := int(terrain.liquid_ground[at]) if at>=0 and at<terrain.liquid_ground.size() else 255
	var emission := terrain.material_e(mat)
	return {"height":local.y,"type":13 if hit.lava or emission.r+emission.g+emission.b>0.0 else type,"material":mat}


func habitat(p: Vector2, scenery := true) -> Dictionary:
	var hit := ground(p)
	if hit.is_empty(): return {}
	var at := int(p.y)*int(terrain.size_ei().x)+int(p.x)
	if terrain.surface[at]>float(hit.height)+0.10: return {} # no creatures/dust under floors
	var wet := liquid(p)
	if not wet.is_empty() and float(wet.height)>float(hit.height)+0.06:
		hit.height = wet.height; hit.type = wet.type; hit.wet = true
	else: hit.wet = false
	hit.area = area(int(hit.type)); hit.leafy = leafy(p)
	hit.clear = not scenery or clear_at(p,float(hit.height))
	return hit


func shore(p: Vector2, height: float) -> bool:
	for i in 8:
		var q := p+Vector2.from_angle(i*TAU/8.0)*2.0
		var hit := habitat(q,false)
		if not hit.is_empty() and hit.wet and int(hit.type) in [6,14] and absf(float(hit.height)-height)<0.8: return true
	return false


func species(p: Vector2, hit: Dictionary, roll: float, _night: float) -> String:
	if hit.is_empty() or hit.wet or not hit.clear or absf((hit.normal as Vector3).y)<0.94: return ""
	var cover := String(hit.area)
	if region=="cave" and cover=="bare": return "rat" if roll<0.60 else "spider"
	if region=="dead_city" and cover=="bare": return "spider"
	if region=="snow" and cover=="snow": return "snowmouse"
	if region=="outdoor" and cover in ["grass","bare"] and shore(p,float(hit.height)): return "frog"
	return ""


static func particles(context: String, biome_name: String, hit: Dictionary, night: float) -> PackedInt32Array:
	# Kinds match AmbientParticles: pollen, leaves, motes, cave dust, embers,
	# blown dust, snow glitter, fireflies. Unknown maps opt out conservatively.
	var result := PackedInt32Array()
	if hit.is_empty() or context=="unknown" or not hit.get("clear",true): return result
	var cover := String(hit.area)
	if cover=="lava": return PackedInt32Array([4])
	if context=="cave": return PackedInt32Array([3])
	if context=="dead_city": result.append(2)
	if context=="outdoor" and cover in ["grass","dry"] and night<0.75: result.append(0)
	if hit.get("leafy",false) and context in ["outdoor","dead_city"] and cover not in ["snow","water","swamp"]: result.append(1)
	if context=="desert" and cover in ["sand","bare","dry"]: result.append(5)
	if cover=="snow" and context!="cave": result.append(6)
	if biome_name=="gipat" and context=="outdoor" and night>0.3 and cover in ["grass","swamp"]: result.append(7)
	return result
