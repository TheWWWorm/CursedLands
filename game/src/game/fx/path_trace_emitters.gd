extends RefCounted
## Render-thread snapshot of emissive triangles. No scene objects are retained.
## A bounded proposal is sufficient: omitted lights still have BSDF support.
const LIMIT := 4096
const HASH_SLOTS := 8192
const STRIDE := 64
const HEADER := 16
var records := PackedByteArray()
var lookup := PackedByteArray()
var count := 0
var candidates := 0
var revision := 0
var _meshes := {}
var _placements: Array = []
var _geometry: Array = []
var _opaque_fast_path := true

func setup(data: PackedByteArray, geometry: Array, placements: Array, opaque_fast_path := true) -> void:
	_geometry = geometry
	_placements = placements.duplicate(true)
	_opaque_fast_path = opaque_fast_path
	for i in geometry.size():
		_extract(i,data,geometry[i].offset*64)
	_rebuild()

func _position(data: PackedByteArray, offset: int) -> Vector3:
	return Vector3(data.decode_float(offset),data.decode_float(offset+4),data.decode_float(offset+8))

func _extract(index: int, data: PackedByteArray, offset: int) -> void:
	# The production gatherer knows emission is constant over each material.
	# Its pose updates change positions/normals only; material changes rebuild
	# the snapshot. Avoid scanning terrain or every non-emitting morph frame.
	# Generic callers without this guarantee still scan their supplied data.
	if not _geometry[index].get("emissive",true):
		_meshes.erase(index); return
	var triangles: Array = []
	for primitive in int(_geometry[index].count)/3:
		var start := offset+primitive*192
		var emission := _position(data,start+48).max(Vector3.ZERO)
		if not emission.is_finite() or emission == Vector3.ZERO: continue
		# Texture modulation is evaluated on the GPU. A conservative white-
		# texture power estimate changes variance only, never emitted energy.
		if not _geometry[index].get("standard",false):
			emission = Vector3(_linear(emission.x),_linear(emission.y),_linear(emission.z))
		var power := emission.dot(Vector3(0.2126,0.7152,0.0722))
		if not is_finite(power) or power <= 0.0: continue
		var a := _position(data,start); var b := _position(data,start+64); var c := _position(data,start+128)
		if not a.is_finite() or not b.is_finite() or not c.is_finite(): continue
		triangles.append({"a":a,"b":b,"c":c,"primitive":primitive,"power":power})
	if triangles.is_empty(): _meshes.erase(index)
	else: _meshes[index] = triangles

func _linear(value: float) -> float:
	return value/12.92 if value <= 0.04045 else pow((value+0.055)/1.055,2.4)

## Only emissive changes rebuild the proposal; ordinary actor animation does
## not upload a light table or invalidate lighting history.
func update(changes: Dictionary) -> bool:
	var changed := false
	var posed := {}
	for pose: Dictionary in changes.get("poses",[]):
		var was_emissive := _meshes.has(pose.geometry)
		_extract(pose.geometry,pose.data,0)
		if was_emissive or _meshes.has(pose.geometry): posed[pose.geometry] = true
	for placement: Dictionary in changes.get("instances",[]):
		var old: Dictionary = _placements[placement.index]
		var old_mask: int = old.get("mask",255)
		var indirect_changed: bool = ((old_mask ^ int(placement.mask)) & 4) != 0
		if (_meshes.has(old.geometry) or posed.has(old.geometry)) and ((old_mask | int(placement.mask)) & 4) != 0 \
			and (old.transform != placement.transform or indirect_changed):
			changed = true
		old.transform = placement.transform; old.mask = placement.mask
	# Hidden and camera-only glowing meshes cannot illuminate indirect paths.
	# Their animation must not continually discard the rest of the scene's
	# accumulation. Keep their local data current for a later reveal.
	if not posed.is_empty():
		for placement: Dictionary in _placements:
			if posed.has(placement.geometry) and (int(placement.get("mask",255)) & 4) != 0:
				changed = true; break
	if changed: _rebuild()
	return changed

## Keep the strongest area*power candidates in a min heap, bounding temporary
## memory even when one emitting mesh has many placements.
func _keep(heap: Array, item: Dictionary) -> void:
	var i: int
	if heap.size() < LIMIT:
		heap.append(item); i = heap.size()-1
		while i > 0:
			var parent := (i-1)/2
			if heap[parent].weight <= item.weight: break
			heap[i] = heap[parent]; i = parent
		heap[i] = item
	elif item.weight > heap[0].weight:
		i = 0
		while i*2+1 < heap.size():
			var child := i*2+1
			if child+1 < heap.size() and heap[child+1].weight < heap[child].weight: child += 1
			if heap[child].weight >= item.weight: break
			heap[i] = heap[child]; i = child
		heap[i] = item

func _rebuild() -> void:
	var selected: Array = []
	candidates = 0
	for instance in _placements.size():
		var placement: Dictionary = _placements[instance]
		if (int(placement.get("mask",255)) & 4) == 0 or not _meshes.has(placement.geometry): continue
		var transform: Transform3D = placement.transform
		for triangle: Dictionary in _meshes[placement.geometry]:
			var a: Vector3 = transform*triangle.a; var b: Vector3 = transform*triangle.b; var c: Vector3 = transform*triangle.c
			var area := (b-a).cross(c-a).length()*0.5
			var weight: float = area*triangle.power
			if area <= 1e-10 or not is_finite(weight) or weight <= 0.0: continue
			candidates += 1
			_keep(selected,{"a":a,"b":b,"c":c,"area":area,"weight":weight,"instance":instance,
				"primitive":triangle.primitive,"geometry":placement.geometry})
	# Ascending weights also preserve small CDF intervals in float precision.
	selected.sort_custom(func(a: Dictionary,b: Dictionary): return a.weight < b.weight)
	count = selected.size(); revision += 1
	records = PackedByteArray(); records.resize(HEADER+count*STRIDE)
	lookup = PackedByteArray(); lookup.resize(HASH_SLOTS*16)
	records.encode_u32(0,count); records.encode_u32(4,HASH_SLOTS-1)
	var total := 0.0
	for light: Dictionary in selected: total += light.weight
	var cumulative := 0.0; var previous := 0.0
	for i in count:
		var light: Dictionary = selected[i]
		cumulative += light.weight/total
		var cdf: float = 1.0 if i == count-1 else PackedFloat32Array([cumulative])[0]
		var offset := HEADER+i*STRIDE
		var values := PackedFloat32Array([light.a.x,light.a.y,light.a.z,light.area,
			light.b.x,light.b.y,light.b.z,cdf-previous,light.c.x,light.c.y,light.c.z,cdf])
		var bytes := values.to_byte_array()
		for j in bytes.size(): records[offset+j] = bytes[j]
		records.encode_u32(offset+48,light.instance); records.encode_u32(offset+52,light.primitive)
		records.encode_u32(offset+56,light.geometry)
		records.encode_u32(offset+60,1 if _opaque_fast_path and _geometry[light.geometry].get("opaque",false) else 0)
		previous = cdf
		var slot := hash_slot(light.instance,light.primitive)
		while lookup.decode_u32(slot*16) != 0: slot = (slot+1) & (HASH_SLOTS-1)
		lookup.encode_u32(slot*16,light.instance+1); lookup.encode_u32(slot*16+4,light.primitive); lookup.encode_u32(slot*16+8,i)

static func hash_slot(instance: int, primitive: int) -> int:
	var h := (((instance+1)*0x9e3779b9) ^ (primitive*0x85ebca6b)) & 0xffffffff
	return (h ^ (h>>16)) & (HASH_SLOTS-1)
