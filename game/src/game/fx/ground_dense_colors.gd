class_name GroundDenseColors
extends RefCounted
## Exact COLOR of installed dense terrain. One layer retains every original
## parent triangle's 153 native vertices, including distinct shared-edge bytes.
## Created lazily for contact consumers; the field holds only a weak reference.
const VERTICES := 153
const PARENTS := 8
const MAX_TILES := 128 # Same global installed-tile cap as SoftGroundDeform.
var texture := Texture2DArray.new()
var tiles: ImageTexture
var _tile_image: Image
var _empty := Image.create(VERTICES,PARENTS,false,Image.FORMAT_RGBA8)
var _images: Array[Image] = []
var _slots := {} # global tile -> texture layer
var _sources := {} # retained immutable PackedColorArray handles, not copies


func _init(width: int, height: int) -> void:
	_empty.fill(Color(0,0,0,0))
	texture.create_from_images([_empty])
	_tile_image = Image.create(width,height,false,Image.FORMAT_RF)
	_tile_image.fill(Color(0,0,0,0))
	tiles = ImageTexture.create_from_image(_tile_image)


static func packed_image(colors: PackedColorArray) -> Image:
	assert(colors.size() == VERTICES*PARENTS)
	var image := Image.create(VERTICES,PARENTS,false,Image.FORMAT_RGBA8)
	for parent in PARENTS:
		for vertex in VERTICES:
			# Same Color-float -> uint8 truncation as ArrayMesh upload. Inputs
			# are already returned by the accepted native/script dense job.
			image.set_pixel(vertex,parent,colors[parent*VERTICES+vertex])
	return image


func _remove(tile: Vector2i) -> void:
	_images[_slots[tile]] = null
	_slots.erase(tile)
	_sources.erase(tile)
	_tile_image.set_pixelv(tile,Color(0,0,0,0))


func _put(tile: Vector2i, colors: PackedColorArray) -> void:
	if _sources.has(tile) and _sources[tile] == colors: return
	var image := packed_image(colors)
	var slot: int = _slots.get(tile,-1)
	if slot < 0:
		assert(_slots.size() < MAX_TILES)
		slot = _images.find(null)
		if slot < 0:
			slot = _images.size()
			_images.resize(mini(MAX_TILES,maxi(1,_images.size()*2)))
			_images[slot] = image
			var upload: Array[Image] = []
			for existing in _images: upload.append(existing if existing else _empty)
			texture.create_from_images(upload)
		else:
			_images[slot] = image
			texture.update_layer(image,slot)
		_slots[tile] = slot
	else:
		_images[slot] = image
		texture.update_layer(image,slot)
	_sources[tile] = colors
	_tile_image.set_pixelv(tile,Color(slot+1,0,0,0))


func install(key: Vector2i, colors: Dictionary) -> void:
	var origin := key*16
	for tile: Vector2i in _slots.keys():
		if tile/16 == key:
			var local := tile-origin
			if not colors.has(local.y*16+local.x): _remove(tile)
	for id: int in colors:
		_put(origin+Vector2i(id%16,id/16),colors[id])
	# Publish addresses only after the complete color upload. The field's
	# ordinary dense-visibility table is published later by its flush().
	tiles.update(_tile_image)
	if _slots.is_empty():
		_images.clear()
		texture.create_from_images([_empty])


func uninstall(key: Vector2i) -> void:
	install(key,{})
