class_name EIResArchive
extends RefCounted
## Reader for Evil Islands ".res" archives.
## The same container is used by .res, .mpr (maps), .mod (model packages)
## and multi-part .bon files, so it can be opened from a path or from bytes.

const MAGIC := 0x019CE23C
const ENTRY_SIZE := 22

var _file: FileAccess
var _bytes: PackedByteArray
## lowercase name -> Vector2i(offset, size)
var entries := {}


static func open_path(path: String) -> EIResArchive:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open archive: %s" % path)
		return null
	var a := EIResArchive.new()
	a._file = f
	return a if a._parse() else null


static func from_bytes(bytes: PackedByteArray) -> EIResArchive:
	var a := EIResArchive.new()
	a._bytes = bytes
	return a if a._parse() else null


static func is_archive(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 16 and bytes.decode_u32(0) == MAGIC


func has(name: String) -> bool:
	return entries.has(name.to_lower())


func read(name: String) -> PackedByteArray:
	var e: Variant = entries.get(name.to_lower())
	if e == null:
		return PackedByteArray()
	return _read_range(e.x, e.y)


func names_with_suffix(suffix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in entries:
		if n.ends_with(suffix):
			out.append(n)
	out.sort()
	return out


func _read_range(offset: int, size: int) -> PackedByteArray:
	if _file:
		_file.seek(offset)
		return _file.get_buffer(size)
	return _bytes.slice(offset, offset + size)


func _parse() -> bool:
	var h := _read_range(0, 16)
	if not is_archive(h):
		return false
	var count := h.decode_u32(4)
	var table_offset := h.decode_u32(8)
	var names_len := h.decode_u32(12)
	var names_base := count * ENTRY_SIZE
	var table := _read_range(table_offset, names_base + names_len)
	for i in count:
		var p := i * ENTRY_SIZE
		var size := table.decode_u32(p + 4)
		var offset := table.decode_u32(p + 8)
		var name_len := table.decode_u16(p + 16)
		var name_off := names_base + table.decode_u32(p + 18)
		var name := table.slice(name_off, name_off + name_len).get_string_from_ascii()
		entries[name.replace("\\", "/").to_lower()] = Vector2i(offset, size)
	return true
