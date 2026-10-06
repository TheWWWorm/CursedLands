class_name EIISOArchive
extends RefCounted
## Bounded ISO 9660 reader. The expansion CDs use 2048-byte sectors and the
## primary (ASCII) directory tree; no mounting or executable code is needed.

const SECTOR := 2048
var path := ""
var error := ""
var files: Dictionary = {}
var _length := 0
var _visited: Dictionary = {}


static func open(source: String) -> EIISOArchive:
	var archive := EIISOArchive.new()
	archive.path = source
	archive.error = archive._index()
	return archive


static func safe_path(name: String) -> bool:
	if name.is_empty() or name.is_absolute_path() or name.contains(":") or name.contains("\\"):
		return false
	for part in name.split("/"):
		if part in ["", ".", ".."]:
			return false
	for ch in name.to_utf8_buffer():
		if ch < 32 or ch == 127:
			return false
	return true


func _index() -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Cannot open the disc image."
	_length = file.get_length()
	for sector in range(16, 80):
		file.seek(sector * SECTOR)
		var header := file.get_buffer(SECTOR)
		if header.size() != SECTOR or header.slice(1, 6).get_string_from_ascii() != "CD001" or header[6] != 1:
			return "This is not a supported ISO disc image."
		if header[0] == 255:
			break
		if header[0] != 1:
			continue
		if header.decode_u16(128) != SECTOR or header[156] < 34:
			return "This is not a supported ISO disc image."
		return _directory(file, header.decode_u32(158) * SECTOR, header.decode_u32(166), "", 0)
	return "This is not a supported ISO disc image."


func _directory(file: FileAccess, offset: int, length: int, prefix: String, depth: int) -> String:
	if depth > 16 or length <= 0 or length > 8388608 or offset < 0 or offset + length > _length or _visited.has(offset):
		return "The disc image has a damaged directory."
	_visited[offset] = true
	file.seek(offset)
	var data := file.get_buffer(length)
	if data.size() != length:
		return "The disc image is incomplete."
	var at := 0
	while at < length:
		var size := int(data[at])
		if size == 0:
			at = (at / SECTOR + 1) * SECTOR
			continue
		if size < 34 or at + size > length or at % SECTOR + size > SECTOR or data[at + 32] + 33 > size:
			return "The disc image has a damaged directory."
		var id := data.slice(at + 33, at + 33 + data[at + 32])
		if not (id.size() == 1 and id[0] in [0, 1]):
			var name := id.get_string_from_ascii().get_slice(";", 0).trim_suffix(".").to_lower()
			if not safe_path(name) or name.contains("/"):
				return "The disc image contains an invalid file path."
			name = prefix.path_join(name) if prefix else name
			var pos := int(data.decode_u32(at + 2)) * SECTOR
			var bytes := int(data.decode_u32(at + 10))
			if pos + bytes > _length or data[at + 1] != 0 or data[at + 26] != 0 or data[at + 27] != 0 or data[at + 25] & 0x80:
				return "The disc image is incomplete or uses an unsupported layout."
			if data[at + 25] & 2:
				var problem := _directory(file, pos, bytes, name, depth + 1)
				if problem:
					return problem
			else:
				if files.has(name) or files.size() >= 20000:
					return "The disc image has a damaged directory."
				files[name] = {"offset": pos, "size": bytes}
		at += size
	return ""


func read(name: String, limit: int = 16777216) -> PackedByteArray:
	var entry: Dictionary = files.get(name, {})
	if entry.is_empty() or int(entry.size) > limit:
		return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	file.seek(entry.offset)
	return file.get_buffer(entry.size)
