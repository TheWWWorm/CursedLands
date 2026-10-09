class_name UnitWounds
extends RefCounted
## Wound marks on damaged body parts (the original, figure):
## - (unit state update) calls figure = when a
##   part's health fraction changed: picks a level per part
##    and composes the wound layers "%s%sw%d.mmp" (unit =
##   the figure name, e.g. "unhuma" / "unmogo"; part code; level) into one
##   texture "mo<id>w" (: layers drawn over a transparent image
##   the layers' size, in part order); puts it on the figure as a
##   second texture stage blended SRCALPHA / INVSRCALPHA over the skin (same
##   UVs); no wounded part -> removes the stage.
## - Level of part i (cur / max = f): f == 1 or f >= 0.75 -> 0
##   0.33 < f < 0.75 -> 1, 1 / max < f <= 0.33 -> 2, f <= 1 / max -> 3; a part
##   that is absent (record = 0) or has max 0 -> 0.
## - Characters (race type 0x32): part codes hd bd lh rh ll rl; a worn helm
##   (armour slot 0) / plate (1) / leggings (2) whose armors "apply_wounds"
##   (record) is 0 hides the head / torso and arms / legs. Others: codes
##   hd bd h h l l, both arms take the worse arm level, both legs the worse leg
##   (each paired layer is listed twice, as in the original).
## The wound images live in redress.res (characters, 128²) or textures.res
## (creatures, 64²); a missing layer is skipped (the original logs it).
## Remake: shipped world/preview materials sample one shared native-size wound
## texture over their unchanged base. Its independent box mips intentionally
## replace the old blend-before-filter appearance (see EIUnitModel.WOUND_FETCH).
## Unsupported custom StandardMaterial3D keeps the legacy per-albedo bake below.
## The levels come from the part health, which co-op clients get
## in the unit snapshots, so every peer shows them. The unit panel figure
## (Paperdoll) gets the same layer. The composer (renderer
##  = 2dintmmx.dll) adds source bytes to destination bytes
## multiplied by (255 − source alpha) / 256, saturating at 255. Its PNT3
## block skips are retained, then the result is truncated to ARGB4444
## (renderer +8 =) before the skin-stage blend.

const HUMAN_CODES := ["hd", "bd", "lh", "rh", "ll", "rl"]
const OTHER_CODES := ["hd", "bd", "h", "h", "l", "l"]
## Optional immutable, mip-free RGBA8 source from an external texture producer.
## Only the custom-material legacy bake consumes it. Shipped wound shaders
## need no base pixels, so EIUnitModel does not retain this extra CPU copy.
const SOURCE_IMAGE := &"ei_wound_source"
## Native-size, mip-free wound layers are shared by all outfits and previews.
## Limit both entries (including failed decodes) and retained CPU pixel memory.
## Their cached RGBA8 GPU mip chains add at most 4/3 of this byte budget plus
## the final texel per entry. Active materials and in-flight jobs own their
## references independently of these cache limits.
const LAYER_CACHE_LIMIT := 64
const LAYER_CACHE_BYTES := 4 * 1024 * 1024

static var _images := {}      # layer file -> Image (or null)
static var _layer_data := {}  # layer file -> original bytes, including PNT3 block skips
static var _composites := {}  # "base instance id|mask|human|levels" -> Texture2D
static var _wound_layers := {} # "mask|human|levels" -> immutable Image (or null), LRU
static var _layer_textures := {} # same key -> shared GPU wound Texture2D (or null)
static var _wound_layer_bytes := 0
static var _layer_jobs := {}  # layer key -> first composite job producing that layer
## Base texture instance id -> its immutable RGBA8 image without mipmaps.
## Populated only for custom-material legacy bakes, from optional SOURCE_IMAGE
## metadata or one readback per cached base. Shipped shaders never enter here.
static var _bases := {}
## Remake (CPU): a new composite (layer decode, blends, mipmaps: 5–8 ms) is
## built on WorkerThreadPool; the texture is made and put on the materials
## on the main thread when it is done (a frame or two later). key -> job.
static var _jobs := {}
## [material, key] waiting for a job (the material's meta "wound_pend" names
## the newest request; an older job finishing late does not overwrite it).
static var _waiting := []
## [weak material, request identity, base, job]. The job owns its result even
## when a later completed layer evicts it from the bounded cache in this poll.
static var _overlay_waiting := []
static var _polling := false


## Wound level per body part, armour cover included.
static func levels(u: GameUnit) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(6)
	if u == null or u.parts.size() < 6:
		return out
	for i in 6:
		var p: UnitBodyPart = u.parts[i]
		var mx := float(p.max)
		if int(p.state) == 0 or mx <= 0.0:
			continue
		var f := float(p.cur) / mx
		if f == 1.0:
			continue
		if f <= 1.0 / mx:
			out[i] = 3
		elif f <= 0.33:
			out[i] = 2
		elif f < 0.75:
			out[i] = 1
	if int(u.race.get("type_id", 0)) == 0x32:
		for w in u.info.get("armors", []):
			var a := GameData.db.find("armors", String(w).get_slice("@", 0).get_slice("|", 0).get_slice(".", 0))
			if a.is_empty() or bool(a.get("apply_wounds", true)):
				continue
			match int(a.get("type_id", -1)):
				0: out[0] = 0
				1:
					out[1] = 0
					out[2] = 0
					out[3] = 0
				2:
					out[4] = 0
					out[5] = 0
	else:
		var arm := maxi(out[2], out[3])
		out[2] = arm
		out[3] = arm
		var leg := maxi(out[4], out[5])
		out[4] = leg
		out[5] = leg
	return out


## Keeps a unit's figure in step with its part health (called every frame;
## work is done only when the levels change).
static func update(u: GameUnit) -> void:
	if u.model == null or u.parts.size() < 6:
		return
	apply(u.model, levels(u), int(u.race.get("type_id", 0)) == 0x32)


## Shows wound levels `lv` on a unit figure (world model or a panel copy).
static func apply(model: EIUnitModel, lv: PackedByteArray, human: bool) -> void:
	if model == null:
		return
	var key := lv.hex_encode()
	if String(model.get_meta("wound_key", "000000000000")) == key:
		return
	model.set_meta("wound_key", key)
	var layers: Array = model.get_meta("layers", [])
	var mask := String(layers[0]) if layers.size() > 0 else model.template.to_lower()
	for m in _materials(model):
		if m.albedo_texture == null:
			continue
		if m is EIUnitModel.LitMaterial or m is EIUnitModel.PreviewMaterial:
			_apply_overlay(m, mask, lv, human)
			continue
		# Legacy/custom StandardMaterial3D has no wound shader contract. Keep
		# its prior bake rather than replacing an arbitrary custom material.
		# The unwounded texture; a material that already shows wounds keeps it.
		var base: Texture2D = m.albedo_texture
		if m.has_meta("wound_base") and m.has_meta("wound_tex") and m.albedo_texture == m.get_meta("wound_tex"):
			base = m.get_meta("wound_base")
		m.set_meta("wound_base", base)
		var key2 := _key(base, mask, lv, human)
		m.set_meta("wound_pend", key2)
		var tex := _wounded(base, mask, lv, human)
		if tex == null:
			_waiting.append([m, key2])
			_start_poll()
			continue
		_put(m, tex)


static func _apply_overlay(m, mask: String, lv: PackedByteArray, human: bool) -> void:
	var base: Texture2D = m.albedo_texture
	var request := _key(base, mask, lv, human)
	m.set_meta("wound_overlay_pend", request)
	if lv == PackedByteArray([0, 0, 0, 0, 0, 0]):
		m.wound_texture = null
		m.remove_meta("wound_overlay_pend")
		return
	var job := _overlay(mask, lv, human)
	if job.finished:
		m.wound_texture = job.tex
		m.remove_meta("wound_overlay_pend")
	else:
		_overlay_waiting.append([weakref(m), request, base, job])
		_start_poll()


## A native wound layer, independent of outfit identity and dimensions. The
## existing producer can be shared with a simultaneous legacy/custom bake.
static func _overlay(mask: String, lv: PackedByteArray, human: bool) -> Dictionary:
	var layer_key := _layer_key(mask, lv, human)
	if _layer_textures.has(layer_key):
		var image = _wound_layers[layer_key]
		_wound_layers.erase(layer_key)
		_wound_layers[layer_key] = image
		return {"finished": true, "tex": _layer_textures[layer_key]}
	var key := "gpu|" + layer_key
	if _jobs.has(key):
		return _jobs[key]
	var job := {"base": null, "src": null, "out": null, "wound": null,
			"decoded": {}, "task": -1, "finished": false, "tex": null,
			"overlay": true, "layer_key": layer_key}
	if _wound_layers.has(layer_key):
		job.wound = _wound_layers[layer_key]
		_wound_layers.erase(layer_key)
		_wound_layers[layer_key] = job.wound
		_launch(job)
	elif _layer_jobs.has(layer_key):
		job.layer_job = _layer_jobs[layer_key]
	else:
		var layers := []
		var codes: Array = HUMAN_CODES if human else OTHER_CODES
		for i in 6:
			if lv[i] == 0:
				continue
			var name := "%s%sw%d" % [mask, codes[i], lv[i]]
			if not _layer_data.has(name):
				_layer_data[name] = _layer_bytes(name)
			layers.append([name, _images.get(name), _layer_data[name]])
		job.layers = layers
		job.compose_layer = true
		_layer_jobs[layer_key] = job
		_launch(job)
	_jobs[key] = job
	return job


static func _put(m, tex: Texture2D) -> void:
	m.remove_meta("wound_pend")
	if m is StandardMaterial3D and m.emission_texture == m.albedo_texture and m.emission_texture != null:
		m.emission_texture = tex   # the selection highlight's copy (OrderMarks)
	m.albedo_texture = tex
	m.set_meta("wound_tex", tex)


static func _key(base: Texture2D, mask: String, lv: PackedByteArray, human := true) -> String:
	return "%d|%s" % [base.get_instance_id(), _layer_key(mask, lv, human)]


static func _layer_key(mask: String, lv: PackedByteArray, human: bool) -> String:
	return "%s|%d|%s" % [mask, int(human), lv.hex_encode()]


static func _start_poll() -> void:
	if _polling:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		flush()
		return
	_polling = true
	tree.process_frame.connect(_poll)


static func _poll(wait := false) -> void:
	for key in _jobs.keys():
		var job: Dictionary = _jobs[key]
		if job.has("layer_job"):
			# Followers never block a worker waiting for another pool task.
			# The first job also bakes its own outfit, avoiding an extra frame
			# for the first wound. Other outfits start once its layer is ready.
			if not job.layer_job.get("finished", false):
				continue
			job.wound = job.layer_job.wound
			job.erase("layer_job")
			_launch(job)
		if job.task >= 0 and not wait and not WorkerThreadPool.is_task_completed(job.task):
			continue
		if job.task >= 0:
			WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.erase(key)
		for n in job.decoded:
			_images[n] = job.decoded[n]
		if job.get("compose_layer", false):
			_layer_jobs.erase(job.layer_key)
			_cache_layer(job.layer_key, job.wound)
		job.finished = true
		var tex: Texture2D = job.base
		if job.out != null:
			tex = ImageTexture.create_from_image(job.out)
		if job.get("overlay", false):
			job.tex = tex
			# Oversized custom layers finish their consumers without retention.
			if _wound_layers.has(job.layer_key):
				_layer_textures[job.layer_key] = tex
		else:
			_composites[key] = tex
	var i := 0
	while i < _waiting.size():
		var w: Array = _waiting[i]
		if not _composites.has(w[1]) and _jobs.has(w[1]):
			i += 1
			continue
		_waiting.remove_at(i)
		var m = w[0]
		if is_instance_valid(m) and String(m.get_meta("wound_pend", "")) == w[1] and _composites.has(w[1]):
			_put(m, _composites[w[1]])
	i = 0
	while i < _overlay_waiting.size():
		var w: Array = _overlay_waiting[i]
		var job: Dictionary = w[3]
		if not job.finished:
			i += 1
			continue
		_overlay_waiting.remove_at(i)
		var m = (w[0] as WeakRef).get_ref()
		if m != null and String(m.get_meta("wound_overlay_pend", "")) == w[1] and m.albedo_texture == w[2]:
			m.wound_texture = job.tex
			m.remove_meta("wound_overlay_pend")
	if _jobs.is_empty() and _waiting.is_empty() and _overlay_waiting.is_empty() and _polling:
		_polling = false
		var tree := Engine.get_main_loop() as SceneTree
		if tree and tree.process_frame.is_connected(_poll):
			tree.process_frame.disconnect(_poll)


## Finishes every pending composite now (tests).
static func flush() -> void:
	_poll(true)
	while not _jobs.is_empty():
		_poll(true)


## At quit (Main._exit_tree): waits for the workers and drops the cached
## textures and images while the RenderingServer is still up.
static func shutdown() -> void:
	for key in _jobs:
		if _jobs[key].task >= 0:
			WorkerThreadPool.wait_for_task_completion(_jobs[key].task)
	_jobs.clear()
	_layer_jobs.clear()
	_wound_layers.clear()
	_layer_textures.clear()
	_wound_layer_bytes = 0
	_waiting.clear()
	_overlay_waiting.clear()
	_composites.clear()
	_bases.clear()
	_images.clear()
	_layer_data.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if _polling and tree and tree.process_frame.is_connected(_poll):
		tree.process_frame.disconnect(_poll)
	_polling = false


## The model's own materials, including the ones the selection highlight
## (OrderMarks._lighten) has swapped out and keeps in metadata.
static func _materials(model: Node) -> Array:
	var out := []
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.has_meta("detailed_head"):
			continue   # DetailedHead: its own face texture, not the body atlas
		var cands := [mi.material_override, mi.get_meta("unlit") if mi.has_meta("unlit") else null]
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				cands.append(mi.get_surface_override_material(i))
				cands.append(mi.get_meta("unlit%d" % i) if mi.has_meta("unlit%d" % i) else null)
		for c in cands:
			if (c is StandardMaterial3D or c is EIUnitModel.LitMaterial or c is EIUnitModel.PreviewMaterial) and not out.has(c):
				out.append(c)
	return out


## The composite texture, or null while a worker builds it (apply waits).
static func _wounded(base: Texture2D, mask: String, lv: PackedByteArray, human: bool) -> Texture2D:
	var key := _key(base, mask, lv, human)
	if _composites.has(key):
		return _composites[key]
	if _jobs.has(key):
		return null
	if _composites.size() > 512:   # instance ids are never reused; just bound the memory
		_composites.clear()
		_bases.clear()
	var layer_key := _layer_key(mask, lv, human)
	# Only a cold layer needs archive reads. Simultaneous outfit/preview
	# requests share its producer; later requests use the completed layer.
	var layers := []   # [name, Image or null, bytes to decode]
	if not _wound_layers.has(layer_key) and not _layer_jobs.has(layer_key):
		var codes: Array = HUMAN_CODES if human else OTHER_CODES
		var any := false
		for i in 6:
			if lv[i] == 0:
				continue
			var name := "%s%sw%d" % [mask, codes[i], lv[i]]
			if not _layer_data.has(name):
				_layer_data[name] = _layer_bytes(name)
			var d: PackedByteArray = _layer_data[name]
			if _images.has(name):
				layers.append([name, _images[name], d])
				any = any or _images[name] != null
			else:
				layers.append([name, null, d])
				any = any or not d.is_empty()
		if not any:
			_composites[key] = base
			return base
	var bid := base.get_instance_id()
	if not _bases.has(bid):
		var src: Image = base.get_meta(SOURCE_IMAGE) if base.has_meta(SOURCE_IMAGE) else null
		if src == null:
			src = base.get_image()
			if src:
				src = src.duplicate()
				if src.is_compressed():
					src.decompress()
				src.clear_mipmaps()
				src.convert(Image.FORMAT_RGBA8)
		if src:
			_bases[bid] = src
	# Populate worker-written slots before launch: a worker may replace values,
	# but must not resize this Dictionary while the main thread reads its task.
	var job := {"base": base, "src": _bases.get(bid), "out": null, "wound": null,
			"decoded": {}, "task": -1, "finished": false}
	if _wound_layers.has(layer_key):
		job.wound = _wound_layers[layer_key]
		# Dictionary insertion order supplies the LRU order without a second list.
		_wound_layers.erase(layer_key)
		_wound_layers[layer_key] = job.wound
		_launch(job)
	elif _layer_jobs.has(layer_key):
		job.layer_job = _layer_jobs[layer_key]
	else:
		job.layers = layers
		job.layer_key = layer_key
		job.compose_layer = true
		_layer_jobs[layer_key] = job
		_launch(job)
	_jobs[key] = job
	return null


static func _launch(job: Dictionary) -> void:
	if Portability.threads():
		job.task = WorkerThreadPool.add_task(_build.bind(job), false, "UnitWounds")
	else:
		_build(job)


static func _cache_layer(key: String, image: Image) -> void:
	var bytes := image.get_data_size() if image else 0
	if bytes > LAYER_CACHE_BYTES:
		return # An oversized custom asset may finish its requests without retention.
	if _wound_layers.has(key):
		var previous: Image = _wound_layers[key]
		_wound_layer_bytes -= previous.get_data_size() if previous else 0
		_wound_layers.erase(key)
		_layer_textures.erase(key)
	while _wound_layers.size() >= LAYER_CACHE_LIMIT or _wound_layer_bytes + bytes > LAYER_CACHE_BYTES:
		var oldest = _wound_layers.keys()[0]
		var previous: Image = _wound_layers[oldest]
		_wound_layer_bytes -= previous.get_data_size() if previous else 0
		_wound_layers.erase(oldest)
		_layer_textures.erase(oldest)
	_wound_layers[key] = image
	_wound_layer_bytes += bytes


## Worker: shipped shaders need only wound mips. The branch below that retains
## the legacy blend-before-filter result for unsupported custom materials.
## Shared source images stay immutable; all mip/resize/blend work is private.
static func _build(job: Dictionary) -> void:
	if job.has("layers"):
		job.wound = _compose_layer(job)
	var comp: Image = job.wound
	if job.get("overlay", false):
		if comp:
			var upload := comp.duplicate() as Image
			upload.generate_mipmaps()
			job.out = upload
		return
	var src: Image = job.src
	if comp == null or src == null:
		return
	var out := src.duplicate() as Image
	if comp.get_size() != out.get_size():
		comp = comp.duplicate()
		comp.resize(out.get_width(), out.get_height(), Image.INTERPOLATE_BILINEAR)
	out.blend_rect(comp, Rect2i(Vector2i.ZERO, comp.get_size()), Vector2i.ZERO)
	out.generate_mipmaps()
	job.out = out


static func _compose_layer(job: Dictionary) -> Image:
	var pixels := PackedByteArray()
	var dims := Vector2i.ZERO
	for l: Array in job.layers:
		var img: Image = l[1]
		if img == null and not (l[2] as PackedByteArray).is_empty():
			img = _decode(l[2])
			job.decoded[l[0]] = img
		elif img == null:
			job.decoded[l[0]] = null
		if img == null:
			continue
		if pixels.is_empty():
			dims = img.get_size()
			pixels.resize(dims.x * dims.y * 4)
		elif img.get_size() != dims:
			continue   # "dimensions are incorrect"
		var d: PackedByteArray = l[2]
		var pnt3 := d.size() >= EIMmp.DATA_OFFSET and d.decode_u32(16) == 0x33544e50
		pixels = _blend_native(pixels, d.slice(EIMmp.DATA_OFFSET) if pnt3 else img.get_data(), pnt3, pnt3)
	if pixels.is_empty():
		return null
	pixels = _argb4444(pixels)
	return Image.create_from_data(dims.x, dims.y, false, Image.FORMAT_RGBA8, pixels)


## Native MMX composer. Both branches work in four-pixel blocks. PNT3
## holds BGRA bytes, with a nonzero alpha-0 dword skipping that many bytes;
## a zero dword at the block start leaves just that first pixel untouched.
## The unpacked branch uses the second pixel's alpha for the first pixel,
## exactly as the DLL does. All shipped wound layers use the PNT3 branch.
static func _blend_native(dst: PackedByteArray, src: PackedByteArray, pnt3 := true, bgra := true) -> PackedByteArray:
	var at := 0
	var sp := 0
	while at + 16 <= dst.size() and sp + 4 <= src.size():
		if pnt3 and src[sp + 3] == 0:
			var skip := src.decode_u32(sp)
			if skip != 0:
				at += skip
				sp += 4
				continue
		if sp + 16 > src.size():
			break
		for pixel in 4:
			if pnt3 and pixel == 0 and src[sp + 3] == 0:
				continue
			var from := sp + pixel * 4
			var to := at + pixel * 4
			var alpha := int(src[sp + 7] if not pnt3 and pixel == 0 else src[from + 3])
			for c in 4:
				var channel := 2 - c if bgra and c < 3 else c
				dst[to + c] = mini(255, int(src[from + channel]) + ((int(dst[to + c]) * (255 - alpha)) >> 8))
		at += 16
		sp += 16
	return dst


static func _argb4444(pixels: PackedByteArray) -> PackedByteArray:
	for i in pixels.size():
		pixels[i] = (int(pixels[i]) >> 4) * 17
	return pixels


static func _layer_bytes(name: String) -> PackedByteArray:
	if GameData.redress and GameData.redress.has(name + ".mmp"):
		return GameData.redress.read(name + ".mmp")
	if GameData.textures and GameData.textures.has(name + ".mmp"):
		return GameData.textures.read(name + ".mmp")
	return PackedByteArray()


static func _decode(d: PackedByteArray) -> Image:
	var img: Image = EIMmp.decode(d)
	if img:
		img.convert(Image.FORMAT_RGBA8)
	return img
