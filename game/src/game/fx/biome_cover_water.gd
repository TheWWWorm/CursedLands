extends RefCounted
## Immutable authored mean-water geometry for sea cover. No scene references,
## game-clock state, navigation changes or per-frame updates live here.
var tiles := {}
var chunks := {} # 8 m cover chunks intersecting the nominal authored surface.
var jittered := false


func add_tile(key: Vector2i, positions: PackedVector3Array, owner: int, material: Dictionary, offset: float) -> void:
	var points := positions.duplicate()
	var regular := true
	var low := INF
	var first := Vector2(INF,INF); var last := Vector2(-INF,-INF)
	for i in 9:
		points[i].y += offset
		var p := Vector2(points[i].x,-points[i].z)
		first=first.min(p); last=last.max(p)
		regular = regular and Vector2(points[i].x,-points[i].z).is_equal_approx(Vector2(key)*2+Vector2(i%3,i/3))
		low = minf(low,points[i].y)
	jittered = jittered or not regular
	for y in range(floori(first.y/8),floori(last.y/8)+1):
		for x in range(floori(first.x/8),floori(last.x/8)+1): chunks[Vector2i(x,y)]=true
	var wave := absf(float(material.get("wave",0.0)))*EIWaterWaves.AMPLITUDE
	var shore := int(material.get("type",0))==4
	tiles[key] = {"points":points,"owner":owner,"regular":regular,"low":low-(0.0 if shore else wave*0.25),
		"reach":128.0/252.0+wave if shore else wave*3.0,
		"coefficient":1.0/(15.0*maxf(1.0-(material.color as Color).a,0.001))}


static func plane(a: Vector3,b: Vector3,c: Vector3, coefficient: float) -> Vector4:
	var n := (b-a).cross(c-a)
	if absf(n.y)<0.000001: return Vector4.ZERO
	# Godot local X/Z, height = x*plane.x + z*plane.y + plane.z.
	return Vector4(-n.x/n.y,-n.z/n.y,a.y+(n.x*a.x+n.z*a.z)/n.y,coefficient)


func sample(p: Vector2) -> Vector4:
	var key := Vector2i((p/2.0).floor())
	var tile: Dictionary = tiles.get(key,{})
	if not jittered and not tile.is_empty() and tile.regular:
		var q := p-Vector2(key)*2.0
		var x := clampi(floori(q.x),0,1); var y := clampi(floori(q.y),0,1)
		var at := y*3+x; var points: PackedVector3Array = tile.points
		if q.x-x+q.y-y <= 1.0: return plane(points[at+3],points[at+1],points[at],tile.coefficient)
		return plane(points[at+1],points[at+3],points[at+4],tile.coefficient)
	if not jittered: return Vector4.ZERO
	# Type-4 liquid vertices can follow authored land XY. Retain exact
	# triangle containment for those maps instead of pretending they are a grid.
	var best := Vector4.ZERO; var height := -INF
	for dy in range(-1,2):
		for dx in range(-1,2):
			tile = tiles.get(key+Vector2i(dx,dy),{})
			if tile.is_empty(): continue
			var points: PackedVector3Array = tile.points
			for y in 2:
				for x in 2:
					var at := y*3+x
					for ids: Array in [[at+3,at+1,at],[at+1,at+3,at+4]]:
						var a := Vector2(points[ids[0]].x,-points[ids[0]].z)
						var b := Vector2(points[ids[1]].x,-points[ids[1]].z)
						var c := Vector2(points[ids[2]].x,-points[ids[2]].z)
						var det := (b-a).cross(c-a)
						if absf(det)<0.000001: continue
						var u := (p-a).cross(c-a)/det; var v := (b-a).cross(p-a)/det
						if u< -0.000001 or v< -0.000001 or u+v>1.000001: continue
						var found := plane(points[ids[0]],points[ids[1]],points[ids[2]],tile.coefficient)
						var h := found.x*p.x-found.y*p.y+found.z
						if h>height: height=h; best=found
	return best


func ceiling(p: Vector2, radius: float) -> float:
	var key := Vector2i((p/2.0).floor())
	var tile: Dictionary = tiles.get(key,{})
	if tile.is_empty(): return -INF
	# The whole leaf/wind footprint needs homogeneous water even after the
	# maximum authored horizontal wave displacement. Use every enclosed tile's
	# lowest vertex minus its vertical wave drop, not the gameplay max-corner.
	var reach := radius+float(tile.reach)
	var lo := Vector2i(((p-Vector2.ONE*reach)/2.0).floor())
	var hi := Vector2i(((p+Vector2.ONE*reach)/2.0).floor())
	var low := INF
	for y in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			var other: Dictionary = tiles.get(Vector2i(x,y),{})
			if other.is_empty() or other.owner != tile.owner: return -INF
			low = minf(low,other.low)
	return low
