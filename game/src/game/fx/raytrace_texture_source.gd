extends RefCounted
## CPU-authored unit textures already have exact pixels before upload. Retain
## a private snapshot so first PT admission need not synchronize with the GPU.
## Other textures, including GPU-upscaled scenery, keep their current getter.
const META := &"ei_cpu_raytrace_image"
const MAX_BYTES := 64*1024*1024
static var _owners := {} # texture ID -> weak owner and accounted packed bytes
static var _bytes := 0

static func _erase(key: int) -> void:
	if not _owners.has(key):return
	var entry: Dictionary=_owners[key]
	var texture: Resource=entry.source.get_ref()
	if texture!=null:
		var callback:=_erase.bind(key)
		if texture.changed.is_connected(callback):texture.changed.disconnect(callback)
		var record: Dictionary=texture.get_meta(META,{})
		if record.get("owner",0)==key:texture.remove_meta(META)
	_bytes-=int(entry.bytes);_owners.erase(key)

static func _prune() -> void:
	for key: int in _owners.keys():
		var texture: Resource=_owners[key].source.get_ref()
		if texture==null or not texture.has_meta(META):_erase(key)

static func remember(texture: ImageTexture,image: Image) -> void:
	if texture==null or image==null or image.is_empty():return
	_prune()
	var key:=texture.get_instance_id();_erase(key)
	var bytes:=image.get_data().size()
	if bytes>MAX_BYTES:return
	while _bytes+bytes>MAX_BYTES and not _owners.is_empty():_erase(_owners.keys()[0])
	# Image is mutable; retaining the caller's object could silently substitute
	# pixels that were never uploaded. duplicate() gives an independent COW image.
	texture.set_meta(META,{"owner":key,"image":image.duplicate(),"bytes":bytes})
	_owners[key]={"source":weakref(texture),"bytes":bytes};_bytes+=bytes
	# Both ImageTexture.update and set_image emit changed after queuing their
	# upload in the qualified engine. Their next admission uses current pixels.
	texture.changed.connect(_erase.bind(key),CONNECT_ONE_SHOT)

static func image(texture: Resource) -> Image:
	var key:=texture.get_instance_id()
	var entry: Dictionary=_owners.get(key,{})
	var record: Dictionary=texture.get_meta(META,{})
	# Resource.duplicate also duplicates metadata. It does not transfer this
	# owner's snapshot or its invalidation watch to the cloned texture.
	if entry.is_empty() or entry.source.get_ref()!=texture or record.get("owner",0)!=key:return null
	_owners.erase(key);_owners[key]=entry
	return record.get("image") as Image

static func memory_stats() -> Dictionary:
	_prune()
	return {"textures":_owners.size(),"packed_bytes":_bytes,"max_bytes":MAX_BYTES}

static func clear() -> void:
	for key: int in _owners.keys():_erase(key)
