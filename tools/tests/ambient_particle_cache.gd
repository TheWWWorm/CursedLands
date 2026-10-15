extends Node
## Cached pans must produce the original ordered field, including after
## teleports, empty cells, invalidation and a replacement habitat source.
const Particles = preload("res://src/game/fx/ambient_particles.gd")
const Habitats = preload("res://src/game/fx/ambient_habitats.gd")
var checks := 0
var failures := 0

class Field extends Habitats:
	var queries := 0
	var revision := 0
	func habitat(p: Vector2, _scenery := true) -> Dictionary:
		queries += 1
		if posmod(floori(p.x+p.y),5)==0: return {}
		return {"height":p.x*0.03+p.y*0.07+revision,"area":"grass" if int(p.x)%3 else "bare",
			"leafy":int(p.y)%3==0,"clear":posmod(int(p.x-p.y),7)!=0}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

## Original uncached selection, independent of the new cell builder.
func original(field: Habitats, centre: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell := Vector2i((centre/Particles.SPACING).floor())
	for y in range(cell.y-3,cell.y+4):
		for x in range(cell.x-3,cell.x+4):
			var key := Vector2i(x,y)
			for lane in 4:
				var p := Vector2(key)*Particles.SPACING+Vector2(field.random(key,100+lane*5),field.random(key,101+lane*5))*Particles.SPACING
				if p.distance_to((Vector2(cell)+Vector2.ONE*0.5)*Particles.SPACING)>Particles.RANGE: continue
				var hit := field.habitat(p)
				var kinds := Habitats.particles(field.region,field.biome,hit,0.0)
				for kind in Habitats.particles(field.region,field.biome,hit,1.0):
					if not kind in kinds: kinds.append(kind)
				if kinds.is_empty(): continue
				var seed := field.random(key,102+lane*5)
				var kind := int(kinds[mini(int(seed*kinds.size()),kinds.size()-1)])
				out.append({"key":Vector3i(x,y,lane),"point":Vector3(p.x,float(hit.height),-p.y),"kind":kind,"seed":seed,"size":Particles.particle_size(kind)})
				if out.size()>=Particles.MAX_PARTICLES: break
			if out.size()>=Particles.MAX_PARTICLES: break
		if out.size()>=Particles.MAX_PARTICLES: break
	return out

func _ready() -> void:
	Gfx.ensure_globals()
	var terrain := EITerrain.new(); terrain.map_name="zone1"
	var field := Field.new(terrain,false); field.region="outdoor"; field.biome="gipat"
	var particles := Particles.new()
	var path := [Vector2(4,4),Vector2(4.1,4.1),Vector2(12,4),Vector2(20,12),Vector2(4,4),Vector2(-100,-200),Vector2(300,200),Vector2.ZERO]
	var costs := []
	for i in path.size():
		field.queries=0; particles.rebuild(field,path[i]); costs.append(field.queries)
		check(particles.records==original(field,path[i]),"exact original records on pan "+str(i))
		check(particles._cells.size()<=49,"cache bounded on pan "+str(i))
		check(particles.multimesh.visible_instance_count==particles.records.size(),"visible count on pan "+str(i))
	check(costs[0]==196 and costs[1]==0,"first field is bounded; movement inside a cell does no source work")
	check(costs[2]==28 and costs[3]==52,"horizontal and diagonal pans query only entering cells")
	check(costs[5]<=196 and costs[6]<=196,"teleports do not accumulate old cells")
	var before := particles.records.duplicate(true)
	field.revision=7; particles.rebuild(field,path.back(),true)
	check(particles.records==original(field,path.back()) and particles.records!=before,"source invalidation refreshes retained cells at the same camera position")
	var replacement := Field.new(terrain,false); replacement.region="desert"; replacement.biome="suslanger"
	particles.rebuild(replacement,path.back())
	check(particles.records==original(replacement,path.back()),"replacement field invalidates same-cell records")
	FileAccess.open("user://ambient-particle-cache.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"habitat_queries":costs},"\t"))
	particles.free();terrain.free()
	print("AMBIENT_PARTICLE_CACHE ",checks," checks ",failures," failures")
	get_tree().quit(int(failures>0))
