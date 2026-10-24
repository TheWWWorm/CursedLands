extends RefCounted
## Forward+ surface/texture getters read GPU buffers back. Keep CPU sources
## across neighboring snapshots, with weak watches and bounded memory.
const MAX_BYTES := 128*1024*1024
const MAX_ENTRIES := 4096
var _entries := {}
var _bytes := 0
var hits := 0
var misses := 0
var _enabled := not OS.get_cmdline_user_args().has("--ei-rt-no-source-cache")

func _erase(key: int) -> void:
	if not _entries.has(key):return
	var entry: Dictionary=_entries[key]
	var source: Resource=entry.source.get_ref()
	var callback:=_erase.bind(key)
	if source!=null and source.changed.is_connected(callback):source.changed.disconnect(callback)
	_bytes-=entry.bytes;_entries.erase(key)

func clear() -> void:
	for key: int in _entries.keys():_erase(key)

func _find(source: Resource,slot: Variant) -> Variant:
	var key:=source.get_instance_id()
	var entry: Dictionary=_entries.get(key,{})
	if _enabled and not entry.is_empty() and entry.items.has(slot):
		_entries.erase(key);_entries[key]=entry;hits+=1
		return entry.items[slot]
	misses+=1;return null

func _store(source: Resource,slot: Variant,result: Variant,bytes: int) -> void:
	if not _enabled or bytes>MAX_BYTES:return
	while (_bytes+bytes>MAX_BYTES or _entries.size()>=MAX_ENTRIES) and not _entries.is_empty():
		_erase(_entries.keys()[0])
	var key:=source.get_instance_id()
	var entry: Dictionary=_entries.get(key,{})
	if entry.is_empty():
		entry={"source":weakref(source),"items":{},"bytes":0}
		source.changed.connect(_erase.bind(key))
	entry.items[slot]=result;entry.bytes+=bytes;_bytes+=bytes
	_entries[key]=entry

func surface(mesh: Mesh,index: int) -> Dictionary:
	var cached: Variant=_find(mesh,index)
	if cached!=null:return cached
	var result:={"arrays":mesh.surface_get_arrays(index),"shapes":[]}
	if mesh is ArrayMesh and mesh.get_blend_shape_count()>0:
		result.shapes=mesh.surface_get_blend_shape_arrays(index)
	# Conservative packed-array estimate, including blend shapes. No extra
	# conversion/copy is needed simply to measure the cache's memory budget.
	var bytes:=0
	var groups: Array=[result.arrays];groups.append_array(result.shapes)
	for arrays: Array in groups:
		for array: Variant in arrays:
			if array!=null:bytes+=array.size()*16
	_store(mesh,index,result,bytes)
	return result

func image(texture: Resource,layer: int,size: int) -> Image:
	var slot:="image:%d:%d"%[layer,size]
	var cached: Variant=_find(texture,slot)
	if cached!=null:return cached
	var result: Image=texture.get_layer_data(layer) if layer>=0 else texture.get_image()
	if result==null or result.is_empty():return null
	result=result.duplicate()
	if result.is_compressed() and result.decompress()!=OK:return null
	result.clear_mipmaps();result.convert(Image.FORMAT_RGBA8)
	result.resize(size,size,Image.INTERPOLATE_BILINEAR);result.generate_mipmaps()
	_store(texture,slot,result,result.get_data().size())
	return result
