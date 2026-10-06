class_name EIAstralDiscImport
extends RefCounted
## Lost in Astral's two CDs: InstallShield 6 cabinets on the install disc,
## loose speech and movies on the play disc. Reads them without mounting,
## copying the cabinets, or running the original installer.
## Cabinet layout: Unshield (MIT), https://github.com/twogood/unshield;
## attribution and license are retained in unshield_license.txt.

const FORMAT_REFERENCE_LICENSE := """Copyright (c) 2003 David Eriksson <twogood@users.sourceforge.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

"""

const DATA_DIRS := ["camera", "config", "maps", "movies", "res", "stream"]
var error := ""
var files: Array[Dictionary] = []
var _thread: Thread
var _mutex := Mutex.new()
var _cancelled := false
var _failure := ""
var _written := 0
var _total := 0
var _current := ""


static func open(paths: PackedStringArray) -> EIAstralDiscImport:
	var job := EIAstralDiscImport.new()
	job.error = job._index(paths)
	return job


func _index(paths: PackedStringArray) -> String:
	if paths.size() != 2 or paths[0] == paths[1]:
		return "Select both Lost in Astral ISO images together."
	var install: EIISOArchive
	var play: EIISOArchive
	for path in paths:
		var disc := EIISOArchive.open(path)
		if disc.error:
			return disc.error
		if disc.files.has("data1.hdr") and disc.files.has("data2.cab"):
			if install != null:
				return "Select the install disc and the play disc, not two copies of the same disc."
			install = disc
		elif disc.files.has("res/speech.res") and disc.files.has("movies/intro.bik"):
			if play != null:
				return "Select the install disc and the play disc, not two copies of the same disc."
			play = disc
		else:
			return "These images are not the supported Lost in Astral discs."
	if install == null or play == null:
		return "Select the install disc and the play disc, not two copies of the same disc."
	var problem := _cabinet(install)
	if problem:
		return problem
	var names := {}
	for entry in files:
		names[entry.name] = true
	for name: String in play.files:
		if not (name.begins_with("movies/") or name == "res/speech.res"):
			continue
		if names.has(name):
			return "The discs contain conflicting game files."
		var entry: Dictionary = play.files[name]
		files.append({"name": name, "source": play.path, "offset": entry.offset, "size": entry.size, "packed": entry.size, "compressed": false})
	for entry in files:
		if entry.size < 0 or entry.size > 2147483648:
			return "The disc image contains an invalid file size."
		_total += int(entry.size)
	if _total > 8589934592:
		return "The disc image contains an invalid file size."
	return ""


func _cabinet(disc: EIISOArchive) -> String:
	var h := disc.read("data1.hdr")
	if h.size() < 512 or h.decode_u32(0) != 0x28635349 or (h.decode_u32(4) >> 12) & 15 != 6:
		return "The expansion installer format is not supported."
	var base := int(h.decode_u32(12))
	if base + 48 > h.size():
		return "The expansion installer header is damaged."
	var table := base + int(h.decode_u32(base + 12))
	var count := int(h.decode_u32(base + 40))
	var dirs := int(h.decode_u32(base + 28))
	var entries := table + int(h.decode_u32(base + 44))
	if count <= 0 or count > 20000 or dirs <= 0 or dirs > 2000 or table + dirs * 4 > h.size() or entries + count * 87 > h.size():
		return "The expansion installer header is damaged."
	var directories: Array[String] = []
	for i in dirs:
		directories.append(_string(h, table + int(h.decode_u32(table + i * 4))))
	var seen := {}
	var volumes := {}
	for i in count:
		var at := entries + i * 87
		var flags := int(h.decode_u16(at))
		var offset := int(h.decode_u64(at + 18))
		if flags & 8 or offset == 0:   # deleted entries and loose installer support
			continue
		var dir := int(h.decode_u16(at + 62))
		if dir >= dirs:
			return "The expansion installer header is damaged."
		var folder := directories[dir].replace("\\", "/").to_lower()
		if folder.get_slice("/", 0) not in DATA_DIRS:
			continue
		var name := folder.path_join(_string(h, table + int(h.decode_u32(at + 58))).to_lower())
		if not EIISOArchive.safe_path(name) or seen.has(name):
			return "The disc image contains an invalid file path."
		seen[name] = true
		if flags & ~4:   # v6 compressed or plain; split/obfuscated cabinets aren't these discs
			return "The expansion installer format is not supported."
		var volume := "data%d.cab" % h.decode_u16(at + 85)
		if not disc.files.has(volume):
			return "The expansion installer is missing a cabinet."
		var cabinet: Dictionary = disc.files[volume]
		if not volumes.has(volume):
			var source := FileAccess.open(disc.path, FileAccess.READ)
			if source == null:
				return "Cannot open the disc image."
			source.seek(cabinet.offset)
			var signature := source.get_buffer(8)
			if signature.size() != 8 or signature.decode_u32(0) != 0x28635349 or signature.decode_u32(4) != h.decode_u32(4):
				return "The expansion installer header is damaged."
			volumes[volume] = true
		var size := int(h.decode_u64(at + 2))
		var packed := int(h.decode_u64(at + 10)) if flags & 4 else size
		if offset < 0 or packed < 0 or offset + packed > int(cabinet.size):
			return "The disc image is incomplete."
		files.append({"name": name, "source": disc.path, "offset": int(cabinet.offset) + offset,
			"size": size, "packed": packed, "compressed": bool(flags & 4), "md5": h.slice(at + 26, at + 42)})
	for name: String in GameData.REQUIRED:
		if name != "res/speech.res" and not seen.has(name):
			return "These images are not the supported Lost in Astral discs."
	return ""


static func _string(data: PackedByteArray, at: int) -> String:
	if at < 0 or at >= data.size():
		return ""
	var end := data.find(0, at)
	if end < at or end - at > 1024:
		return ""
	return data.slice(at, end).get_string_from_ascii()


func extract(destination: String) -> Error:
	if error or _thread != null:
		return ERR_INVALID_PARAMETER
	_thread = Thread.new()
	var result := _thread.start(_work.bind(destination))
	if result != OK:
		_thread = null
	return result


func status() -> Dictionary:
	_mutex.lock()
	var result := {"fraction": float(_written) / maxi(_total, 1), "file": _current, "error": _failure}
	_mutex.unlock()
	return result


func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()


func _is_cancelled() -> bool:
	_mutex.lock()
	var result := _cancelled
	_mutex.unlock()
	return result


func finished() -> bool:
	if _thread != null and _thread.is_alive():
		return false
	wait_to_finish()
	return true


func wait_to_finish() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _work(destination: String) -> void:
	var sources := {}
	for entry in files:
		if _is_cancelled():
			break
		_mutex.lock()
		_current = entry.name
		_mutex.unlock()
		if not sources.has(entry.source):
			sources[entry.source] = FileAccess.open(entry.source, FileAccess.READ)
		var result := _extract_file(entry, sources[entry.source], destination)
		if result:
			_mutex.lock()
			_failure = result
			_mutex.unlock()
			break


func _extract_file(entry: Dictionary, source: FileAccess, destination: String) -> String:
	if source == null:
		return "Cannot open the disc image."
	var path := destination.path_join(entry.name)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return "Could not write imported game data."
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		return "Could not write imported game data."
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_MD5)
	source.seek(entry.offset)
	var left := int(entry.packed)
	var written := 0
	while left > 0:
		if _is_cancelled():
			return "Import cancelled."
		var bytes: PackedByteArray
		if entry.compressed:
			if left < 2:
				return "The expansion installer data is damaged."
			var size := source.get_16()
			left -= 2
			if size == 0 or size > left:
				return "The expansion installer data is damaged."
			var compressed := source.get_buffer(size)
			if compressed.size() != size:
				return "The disc image is incomplete."
			bytes = _inflate(compressed)
			if bytes.is_empty():
				return "The expansion installer data is damaged."
			left -= size
		else:
			var size := mini(left, 1048576)
			bytes = source.get_buffer(size)
			if bytes.size() != size:
				return "The disc image is incomplete."
			left -= size
		written += bytes.size()
		if written > int(entry.size):
			return "The expansion installer data is damaged."
		output.store_buffer(bytes)
		if output.get_error() != OK:
			return "Not enough space to import game data."
		hash.update(bytes)
		_mutex.lock()
		_written += bytes.size()
		_mutex.unlock()
	output.close()
	var digest := hash.finish()
	if written != int(entry.size) or (entry.has("md5") and digest != entry.md5):
		return "The expansion installer checksum failed."
	return ""


static func _inflate(bytes: PackedByteArray) -> PackedByteArray:
	# InstallShield stores independent raw DEFLATE blocks (up to 64 KiB),
	# without a zlib header/Adler checksum. Supply the header for Godot's
	# streaming inflater; the cabinet's MD5 validates the complete file.
	var stream := StreamPeerGZIP.new()
	if stream.start_decompression(true, 131072) != OK:
		return PackedByteArray()
	var wrapped := PackedByteArray([0x78, 0x9c])
	wrapped.append_array(bytes)
	wrapped.append(0)   # InstallShield omits a final padding byte in some blocks.
	var result := stream.put_partial_data(wrapped)
	var size := stream.get_available_bytes()
	if result[0] != OK or result[1] != wrapped.size() or size <= 0 or size > 65536:
		return PackedByteArray()
	return stream.get_data(size)[1]
