class_name SoftGroundField
extends RefCounted
## One world's footprint GPU storage. Terrain sectors and ground-contact
## materials share the same array, installed-tile table and clock. No readback.
## The array grows 1/2/4/8 layers; replacing its storage preserves its RID.
const SECTOR := 32
const RESOLUTION := 512
const MAX_LAYERS := 8

var texture := Texture2DArray.new()
var tiles: ImageTexture
var clock: ImageTexture
var _tile_image: Image
var _clock_image := Image.create(1, 1, false, Image.FORMAT_RF)
var _empty := Image.create(1, 1, false, Image.FORMAT_RGBAF)
var _slots := {} # sector key -> array layer
var _images: Array[Image] = [] # existing sector images, not extra CPU copies
var _dirty := false


func _init(width := 1, height := 1) -> void:
	_empty.fill(Color(0, 0, 0, 0))
	texture.create_from_images([_empty])
	_tile_image = Image.create(maxi(width, 1), maxi(height, 1), false, Image.FORMAT_RGF)
	_tile_image.fill(Color(0, 0, 0, 0))
	tiles = ImageTexture.create_from_image(_tile_image)
	_clock_image.fill(Color(0, 0, 0, 0))
	clock = ImageTexture.create_from_image(_clock_image)


func allocate(key: Vector2i, image: Image) -> int:
	if _slots.has(key):
		return _slots[key]
	assert(_slots.size() < MAX_LAYERS)
	var slot := _images.find(null)
	if slot < 0:
		slot = _images.size()
		_images.resize(mini(MAX_LAYERS, maxi(1, _images.size() * 2)))
		_images[slot] = image
		var upload: Array[Image] = []
		for existing in _images:
			# Unassigned layers cannot be sampled until install(). Reusing an
			# existing CPU image avoids retaining a second full-size blank.
			upload.append(existing if existing else image)
		texture.create_from_images(upload)
	else:
		_images[slot] = image
		texture.update_layer(image, slot)
	_slots[key] = slot
	return slot


func update(key: Vector2i) -> void:
	if _slots.has(key):
		var slot: int = _slots[key]
		texture.update_layer(_images[slot], slot)


func install(key: Vector2i, dense: Dictionary) -> void:
	assert(_slots.has(key))
	var slot: int = _slots[key]
	# R = layer + 1 only AFTER the sector installs its track material.
	# G distinguishes visible dense tiles from pending mesh jobs.
	var origin := key * 16
	_tile_image.fill_rect(Rect2i(origin, Vector2i(16, 16)), Color(slot + 1, 0, 0, 0))
	for id: int in dense:
		if dense[id] != null:
			_tile_image.set_pixel(origin.x + id % 16, origin.y + id / 16, Color(slot + 1, 1, 0, 0))
	_dirty = true


func uninstall(key: Vector2i) -> void:
	_tile_image.fill_rect(Rect2i(key * 16, Vector2i(16, 16)), Color(0, 0, 0, 0))
	_dirty = true


func release(key: Vector2i) -> void:
	uninstall(key)
	if _slots.has(key):
		_images[_slots[key]] = null
		_slots.erase(key)
	if _slots.is_empty():
		# Fully expired/cleared worlds release the peak allocation as before.
		_images.clear()
		texture.create_from_images([_empty])


func flush(time: float) -> void:
	if _dirty:
		tiles.update(_tile_image)
		_dirty = false
	if not _slots.is_empty():
		_clock_image.set_pixel(0, 0, Color(time, 0, 0, 0))
		clock.update(_clock_image)
