class_name DataReadCursor
extends RefCounted
## Seekable reader for a native file or a browser-local Blob. Small scalar
## reads share a 64 KiB window, avoiding a service-worker call per integer.
var path := ""
var _position := 0
var _size := 0
var _base := -1
var _buffer := PackedByteArray()
var _native: FileAccess

static func open(source: String) -> DataReadCursor:
	if not GameFiles.exists(source): return null
	var cursor := DataReadCursor.new()
	cursor.path = source
	cursor._size = GameFiles.length(source)
	if not GameFiles.virtual_path(source): cursor._native = FileAccess.open(source, FileAccess.READ)
	return cursor

func get_position() -> int:
	return _position

func seek(position: int) -> void:
	_position = clampi(position, 0, _size)

func get_buffer(length: int) -> PackedByteArray:
	length = mini(length, _size - _position)
	if length <= 0: return PackedByteArray()
	var result: PackedByteArray
	if _native:
		_native.seek(_position)
		result = _native.get_buffer(length)
	else:
		if _base < 0 or _position < _base or _position + length > _base + _buffer.size():
			_base = _position
			_buffer = GameFiles.read(path, _base, mini(maxi(length, 65536), _size - _base))
		result = _buffer.slice(_position - _base, _position - _base + length)
	_position += result.size()
	return result

func get_16() -> int:
	var bytes := get_buffer(2)
	return bytes.decode_u16(0) if bytes.size() == 2 else 0

func get_32() -> int:
	var bytes := get_buffer(4)
	return bytes.decode_u32(0) if bytes.size() == 4 else 0
