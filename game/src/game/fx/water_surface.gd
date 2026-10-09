extends RefCounted
## Visual water query only. Navigation keeps its original cell-height rules.
## Read the existing water mesh lazily, index its triangles, and evaluate the
## same authored wave state/SetWaterLevel as EITerrain's vertex shader.
const BUCKET := 2.0
const CACHE_SECTORS := 16
const WaveState = preload("res://src/ei/water_waves.gd")
var terrain: EITerrain
var _sectors := {}
var _stamp := 0
var _frame := 0
var _phase := WaveState.phase_grid()
var _waves := true
var _margin := 0.0


func _init(t: EITerrain) -> void:
	terrain = t
	for material: Dictionary in terrain.materials:
		# Wind is clamped to [0,1]; non-type-4 waves move horizontally by
		# at most amplitude * wave * 3. Index the entire possible envelope.
		_margin = maxf(_margin, absf(float(material.get("wave", 0.0))) * WaveState.AMPLITUDE * 3.0)


func clear() -> void:
	_sectors.clear()


func begin_frame() -> void:
	_frame += 1
	var value: Variant = terrain._water_mat.get_shader_parameter("waves") if terrain._water_mat else null
	_waves = value == null or float(value) > 0.5


func _sector(key: Vector2i) -> Dictionary:
	_stamp += 1
	if _sectors.has(key):
		var previous: Dictionary = _sectors[key]
		var saved := (previous.node as WeakRef).get_ref() as MeshInstance3D
		if saved and saved.mesh != null and saved.mesh == (previous.mesh as WeakRef).get_ref():
			previous.stamp = _stamp
			return previous
		_sectors.erase(key)
	var node := terrain.get_node_or_null("Water_%d_%d" % [key.x,key.y]) as MeshInstance3D
	if node == null or node.mesh == null or node.mesh.get_surface_count() != 1:
		return {}
	var arrays := node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	if vertices.is_empty() or uv2.size() != vertices.size():
		return {}
	var buckets := {}
	for at in range(0,indices.size(),3):
		var a := vertices[indices[at]]; var b := vertices[indices[at+1]]; var c := vertices[indices[at+2]]
		var lo := a.min(b).min(c); var hi := a.max(b).max(c)
		var first := Vector2i(floori((lo.x-_margin)/BUCKET),floori((-hi.z-_margin)/BUCKET))
		var last := Vector2i(floori((hi.x+_margin)/BUCKET),floori((-lo.z+_margin)/BUCKET))
		for y in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var bucket := Vector2i(x,y)
				if not buckets.has(bucket): buckets[bucket] = PackedInt32Array()
				buckets[bucket].append(at)
	var record := {"node":weakref(node),"mesh":weakref(node.mesh),"vertices":vertices,"indices":indices,
		"uv2":uv2,"buckets":buckets,"stamp":_stamp,"frame":-1,"posed":PackedVector3Array(),"ready":PackedByteArray()}
	record.posed.resize(vertices.size()); record.ready.resize(vertices.size())
	if _sectors.size() >= CACHE_SECTORS:
		var oldest: Vector2i = _sectors.keys()[0]
		for other: Vector2i in _sectors:
			if int(_sectors[other].stamp) < int(_sectors[oldest].stamp): oldest = other
		_sectors.erase(oldest)
	_sectors[key] = record
	return record


func _vertex(record: Dictionary, index: int, transform: Transform3D) -> Vector3:
	if int(record.frame) != _frame:
		record.ready.fill(0); record.frame = _frame
	if record.ready[index] != 0: return record.posed[index]
	var encoded := int(record.uv2[index].y+0.5)
	var material := clampi(encoded%64,0,63)
	var p: Vector3 = record.vertices[index]
	p.y += float(terrain.water_offsets.get(material,0.0))
	var world := transform*p
	if _waves and material < terrain.materials.size():
		var authored: Dictionary = terrain.materials[material]
		var ei := Vector3(world.x,-world.z,world.y)
		var cell := Vector2i(posmod(floori(ei.x+0.5),32),posmod(floori(ei.y+0.5),32))
		var moved := terrain._waves.vertex(ei,cell,int(authored.get("type",0)),
			float(authored.get("wave",0.0)),_phase[cell.y*33+cell.x],encoded >= 64)
		# The shader evaluates phase in world coordinates but adds displacement
		# in local coordinates, before MODEL_MATRIX. Preserve that order.
		var delta := moved-ei
		world = transform*(p+Vector3(delta.x,delta.z,-delta.y))
	record.posed[index] = world; record.ready[index] = 1
	return world


## x/z in Godot world space. Pick the highest containing rendered triangle,
## not a bilinear plane or the first owner at an overlapping tile edge.
## Result: world height, material owner and local slope (rise per x/z metre).
func sample(point: Vector2) -> Dictionary:
	if not is_instance_valid(terrain) or not point.is_finite(): return {}
	var local := terrain.to_local(Vector3(point.x,terrain.global_position.y,point.y))
	# A deformed edge can cross a sector boundary. Authored water currently
	# uses axis-aligned map transforms; the triangle test itself is in world.
	# Tight candidate bounds avoid loading nine full sectors for a query well
	# inside one sector. Type-4 vertices can inherit up to 128/252 m land XY.
	var reach := _margin+128.0/252.0
	var first := Vector2i(floori((local.x-reach)/32.0),floori((-local.z-reach)/32.0))
	var last := Vector2i(floori((local.x+reach)/32.0),floori((-local.z+reach)/32.0))
	var best := {}
	for sy in range(maxi(0,first.y),mini(terrain.sectors_y,last.y+1)):
		for sx in range(maxi(0,first.x),mini(terrain.sectors_x,last.x+1)):
			var key := Vector2i(sx,sy)
			var record := _sector(key)
			if record.is_empty(): continue
			var node := (record.node as WeakRef).get_ref() as MeshInstance3D
			if node == null or node.mesh == null or node.mesh != (record.mesh as WeakRef).get_ref():
				_sectors.erase(key); continue
			var xf := node.global_transform
			var p := node.to_local(Vector3(point.x,node.global_position.y,point.y))
			var bucket := Vector2i(floori(p.x/BUCKET),floori(-p.z/BUCKET))
			for at: int in record.buckets.get(bucket,PackedInt32Array()):
				var ia: int = record.indices[at]; var ib: int = record.indices[at+1]; var ic: int = record.indices[at+2]
				var a := _vertex(record,ia,xf); var b := _vertex(record,ib,xf); var c := _vertex(record,ic,xf)
				var ab := Vector2(b.x-a.x,b.z-a.z); var ac := Vector2(c.x-a.x,c.z-a.z)
				var ap := point-Vector2(a.x,a.z)
				var det := ab.cross(ac)
				if absf(det) < 1e-8: continue
				var v := ap.cross(ac)/det; var w := ab.cross(ap)/det
				if v < -0.000001 or w < -0.000001 or v+w > 1.000001: continue
				var height := a.y+v*(b.y-a.y)+w*(c.y-a.y)
				if not best.is_empty() and height <= float(best.height): continue
				var ma := clampi(int(record.uv2[ia].y+0.5)%64,0,63)
				var mb := clampi(int(record.uv2[ib].y+0.5)%64,0,63)
				var mc := clampi(int(record.uv2[ic].y+0.5)%64,0,63)
				var lava := false
				for m: int in [ma,mb,mc]:
					lava = lava or (m < terrain._lava.size() and terrain._lava[m] > 0.0)
				best = {"height":height,"lava":lava,"material":ma,
					"slope":Vector2(((b.y-a.y)*ac.y-(c.y-a.y)*ab.y)/det,
						(ab.x*(c.y-a.y)-ac.x*(b.y-a.y))/det)}
	return best
