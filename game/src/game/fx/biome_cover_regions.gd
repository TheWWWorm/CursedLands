extends RefCounted
## Immutable regional habitats, populated on the loading thread. Workers read
## authored liquid meshes, solid scenery and MOB sites, never live creatures.
enum Kind { ASH=14, SCORIA, OBSIDIAN, CRUST, MOSS, LICHEN, FERN, ROOTS, MUSHROOM, WET, SLAB, RUBBLE, BONES, SKULL, WEB, CRYSTAL }
const FIRST := Kind.ASH
const COUNT := 16
const RANGE := 6.0
const SITE_RANGE := 20.0
const RADII := [0.50,0.12,0.18,0.50,0.50,0.50,0.45,0.50,0.30,0.50,0.50,0.20,0.42,0.18,0.50,0.24]
const SCALES := [Vector2(0.24,0.64),Vector2(0.3,0.6),Vector2(0.5,0.9),Vector2(0.36,0.8),
	Vector2(0.36,1.0),Vector2(0.2,0.64),Vector2(0.4,0.8),Vector2(0.4,0.9),
	Vector2(0.4,0.8),Vector2(0.44,1.2),Vector2(0.2,0.5),Vector2(0.3,0.6),
	Vector2(0.4,0.8),Vector2(0.6,0.9),Vector2(0.5,1.3),Vector2(0.3,0.7)]
var cave := false
var dead_city := false
var liquids := {} # Chunk -> Vector4(x, mean level, EI y, 1 water / 2 lava).
var sites := {} # Chunk -> original undead-site XY, independent of live units.
var walls := {} # Chunk -> unexpanded solid mesh boxes, in terrain coordinates.


static func undead(model: String) -> bool:
	model = model.to_lower()
	while not model.is_empty() and model.unicode_at(model.length()-1)==0: model=model.left(-1)
	for i in model.length():
		if model.unicode_at(i)==0 or model.unicode_at(i)>127: return false
	if model in ["unhusk","unhuzm","unhuzf"]: return true
	return model.left(6) in ["unmoba","unmosh","unmosk","unmozo","unmocu"]


func add_site(p: Vector2) -> void:
	var lo := Vector2i(((p-Vector2.ONE*SITE_RANGE)/8.0).floor())
	var hi := Vector2i(((p+Vector2.ONE*SITE_RANGE)/8.0).floor())
	for y in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			var key := Vector2i(x,y)
			if not sites.has(key): sites[key] = PackedVector2Array()
			sites[key].append(p)


func configure(terrain: EITerrain, field: RefCounted, scenery: Dictionary) -> void:
	cave = field.biome=="cave"; dead_city = field.biome=="dead_city"
	if not cave and not dead_city: return
	var map := terrain.get_parent() as EIMapScene
	if map and map.mob:
		for record: Dictionary in map.mob.objects:
			if record.get("kind","")!="UNIT" or not undead(record.get("template","")): continue
			var p: Vector3 = record.get("position",Vector3.INF)
			if p.is_finite() and p.x>=0 and p.y>=0 and p.x<field.size.x and p.y<field.size.y: add_site(Vector2(p.x,p.y))
	if not cave: return
	for key: Vector2i in scenery:
		var boxes := []
		for record: Dictionary in scenery[key]:
			# Exclusion boxes have plant clearance added. Habitat walls use the
			# original solid bounds so pressure options cannot move a wall.
			if record.has("solid"): boxes.append({"inverse":record.inverse,"box":record.solid})
		walls[key] = boxes
	for node in terrain.get_children():
		if not node is MeshInstance3D or not String(node.name).begins_with("Water_") or node.mesh==null: continue
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var owners: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for first in range(0,vertices.size(),9):
			var m := int(owners[first+4].y+0.5)%64
			if m>=terrain.materials.size(): continue
			var tile := Vector2i(roundi(vertices[first].x/2.0),roundi(-vertices[first].z/2.0))
			var type: int = terrain.liquid_ground[tile.y*2*field.size.x+tile.x*2]
			if not type in [6,13,14]: continue
			var same := true
			for i in 9:
				if int(owners[first+i].y+0.5)%64!=m: same=false; break
			if not same: continue
			var centre := vertices[first+4]; var p := Vector2(centre.x,-centre.z)
			var hit: Dictionary = field.sample(p)
			var level := centre.y+float(terrain.water_offsets.get(m,0.0))
			if hit.is_empty() or level<=float(hit.height)+0.10: continue
			if field.surface[int(p.y)*field.size.x+int(p.x)]>level: continue
			var e := terrain.material_e(m)
			var lava := type==13 or e.r+e.g+e.b>0.0
			var point := Vector4(p.x,level,p.y,2 if lava else 1)
			var lo := Vector2i(((p-Vector2.ONE*RANGE)/8.0).floor())
			var hi := Vector2i(((p+Vector2.ONE*RANGE)/8.0).floor())
			for y in range(lo.y,hi.y+1):
				for x in range(lo.x,hi.x+1):
					var key := Vector2i(x,y)
					if not liquids.has(key): liquids[key] = PackedVector4Array()
					liquids[key].append(point)


func wall(field: RefCounted, p: Vector2, height: float) -> Vector2:
	var distance := 5.0; var first := Vector2.ZERO; var corner := 0.0
	for i in 8:
		var direction := Vector2.from_angle(i*TAU/8.0)
		for radius: float in [0.5,1.0,2.0,4.0]:
			var q := p+direction*radius
			var hit: Dictionary = field.sample(q)
			var solid := not hit.is_empty() and float(hit.height)>height+radius*0.8
			if not solid:
				for box: Dictionary in walls.get(Vector2i((q/8.0).floor()),[]):
					var inverse: Transform3D = box.inverse
					if (box.box as AABB).intersects_segment(inverse*Vector3(q.x,height+0.2,-q.y),inverse*Vector3(q.x,height+maxf(1.0,radius*0.8),-q.y))!=null:
						solid=true; break
			if not solid: continue
			distance = minf(distance,radius)
			if first==Vector2.ZERO: first=direction
			elif absf(first.dot(direction))<0.3: corner=1.0
			break
	return Vector2(distance,corner)


func habitat(field: RefCounted, p: Vector2, hit: Dictionary) -> Vector4:
	var site := 0.0
	for q: Vector2 in sites.get(Vector2i((p/8.0).floor()),PackedVector2Array()):
		site=maxf(site,1.0-p.distance_to(q)/SITE_RANGE)
	if not cave: return Vector4(INF,5.0,0.0,maxf(site,0.0))
	var lava := INF; var water := INF
	for q: Vector4 in liquids.get(Vector2i((p/8.0).floor()),PackedVector4Array()):
		# Approximate bands from authored 2 m centres, not the gameplay
		# maximum-corner water grid. Floors far above a pool are not shores.
		# Authored lava sits roughly 1.5–3 m below walkable cave lips;
		# water plants still need the much tighter damp-bank height band.
		if absf(float(hit.height)-q.y)>(3.0 if q.w==2 else 1.2): continue
		var distance := maxf(p.distance_to(Vector2(q.x,q.z))-1.0,0.0)
		if q.w==2: lava=minf(lava,distance)
		else: water=minf(water,distance)
	var edge := wall(field,p,float(hit.height))
	var c: Color = hit.colour
	var dark := 1.0-clampf(c.r*0.2126+c.g*0.7152+c.b*0.0722,0,1)
	var damp := maxf(1.0-smoothstep(0.0,5.0,water),(1.0-smoothstep(0.0,3.0,edge.x))*(0.35+0.65*dark))
	damp=maxf(damp,clampf((c.g-maxf(c.r,c.b))*8.0,0,1))
	if lava<2.0: damp=0.0
	# Corner uses the sign of wall distance; all physical distances remain
	# explicit, with no live-state or global random-number dependency.
	return Vector4(lava,-edge.x if edge.y>0 else edge.x,damp,maxf(site,0.0))


func weights(hit: Dictionary, habitat: Vector4, patch: float) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(COUNT)
	var type := int(hit.type)
	var bare := type in [1,2,4]; var dry := type in [5,11]
	if (cave or dead_city) and (bare or dry):
		out[Kind.BONES-FIRST]=0.025*habitat.w; out[Kind.SKULL-FIRST]=0.009*habitat.w
	if not cave: return out
	var wall_distance := absf(habitat.y); var damp := habitat.z
	if bare or dry:
		out[Kind.ASH-FIRST]=0.65*(1.0-smoothstep(0,4,habitat.x))
		out[Kind.SCORIA-FIRST]=0.5*(1.0-smoothstep(0,5,habitat.x))
		out[Kind.OBSIDIAN-FIRST]=0.12*(1.0-smoothstep(0,3,habitat.x))
		out[Kind.CRUST-FIRST]=0.35*(1.0-smoothstep(0,1.8,habitat.x))
	if bare or type in [0,3]:
		out[Kind.MOSS-FIRST]=1.2*damp*patch
		out[Kind.FERN-FIRST]=0.24*damp
		out[Kind.ROOTS-FIRST]=0.04*(1.0-smoothstep(0.15,1.2,wall_distance))
		out[Kind.MUSHROOM-FIRST]=0.14*damp
	if bare:
		out[Kind.WET-FIRST]=0.045*damp
		out[Kind.WEB-FIRST]=0.018*(1.0-smoothstep(0,2,wall_distance)) if habitat.y<0 else 0.0
	if type in [2,4]:
		out[Kind.LICHEN-FIRST]=0.18*(1.0-smoothstep(0,2,wall_distance))
		out[Kind.SLAB-FIRST]=0.08; out[Kind.RUBBLE-FIRST]=0.2; out[Kind.CRYSTAL-FIRST]=0.065
	return out


static func material(kind: int) -> int:
	if kind==Kind.MUSHROOM: return 3 # Dim green material emission, no new light.
	if kind==Kind.WET: return 5 # Ground-art patch, dark centre fading into its rim.
	if kind in [Kind.ASH,Kind.MOSS,Kind.LICHEN]: return 4
	if kind in [Kind.SCORIA,Kind.OBSIDIAN,Kind.CRUST,Kind.SLAB,Kind.RUBBLE]: return 1
	return 0


func records(field: RefCounted, key: Vector2i, boxes: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not cave and not dead_city: return out
	var rng := RandomNumberGenerator.new(); rng.seed=hash("%s:regional-cover:%d:%d"%[field.map_name,key.x,key.y])
	for y in 10:
		for x in 10:
			var p := Vector2(key)*8.0+Vector2(x+rng.randf_range(0.15,0.85),y+rng.randf_range(0.15,0.85))*0.8
			var rolls := PackedFloat32Array()
			for i in COUNT: rolls.append(rng.randf())
			var angle := rng.randf()*TAU; var size_roll := rng.randf(); var seed := rng.randf()
			var hit: Dictionary = field.dry_surface(p)
			if hit.is_empty() or not int(hit.type) in [0,1,2,3,4,5,11]: continue
			var blocked := false
			for box: Dictionary in boxes:
				var inverse: Transform3D = box.inverse
				if (box.box as AABB).intersects_segment(inverse*Vector3(p.x,float(hit.height)-0.025,-p.y),inverse*Vector3(p.x,float(hit.height)+0.9,-p.y))!=null: blocked=true; break
			if blocked: continue
			var habitat := habitat(field,p,hit)
			var patch := 0.2+0.8*(0.5+0.5*sin(p.x*1.7+sin(p.y*0.7)))
			var density := weights(hit,habitat,patch)
			var anchor := Vector4(-2,0,0,0)
			for i in COUNT:
				if rolls[i]>=density[i]*0.64: continue
				var kind := FIRST+i; var scale := lerpf(SCALES[i].x,SCALES[i].y,size_roll)
				var radius: float = RADII[i]*scale
				if not field.footprint(p,hit,kind,radius): continue
				# One ground-art tile per small primitive. Avoid interpolating
				# unrelated array layers/UV seams across a textured triangle.
				var clear := true
				for j in 8:
					var edge: Dictionary = field.dry_surface(p+Vector2.from_angle(j*TAU/8)*radius)
					if edge.is_empty(): clear=false; break
					if material(kind) in [1,4,5] and (edge.code!=hit.code or (edge.uv as Vector2).distance_to(hit.uv)>0.05): clear=false; break
					if cave and radius>0.5:
						var q := p+Vector2.from_angle(j*TAU/8)*radius
						for box: Dictionary in walls.get(Vector2i((q/8.0).floor()),[]):
							var inverse: Transform3D=box.inverse
							if (box.box as AABB).intersects_segment(inverse*Vector3(q.x,float(hit.height)-0.025,-q.y),inverse*Vector3(q.x,float(hit.height)+0.9,-q.y))!=null: clear=false; break
						if not clear: break
				if not clear: continue
				if anchor.x==-2: anchor=field.surface_anchor(p)
				if not anchor.is_finite(): break
				out.append({"kind":kind,"p":p,"height":float(hit.height),"normal":hit.normal,"colour":hit.colour,
					"angle":angle,"scale":scale,"seed":seed,"snow":false,"flower":0.0,"cold":false,"anchor":anchor,"regional_material":material(kind)})
	return out
