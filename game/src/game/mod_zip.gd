class_name ModZip
extends RefCounted
## Inspect classic ZIP central-directory sizes before ZIPReader allocates an
## inflated member. Reject encrypted, multi-disk, ZIP64 and symlink packages.
static func inspect(path: String, limit: int) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 22 or file.get_length() > limit: return {"error":"Package cannot be read or is too large."}
	var length := file.get_length()
	var tail_at := maxi(0, length - 65557)
	file.seek(tail_at)
	var tail := file.get_buffer(length - tail_at)
	var end := -1
	for i in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(i) == 0x06054b50 and i + 22 + tail.decode_u16(i + 20) == tail.size(): end = i; break
	if end < 0: return {"error":"Invalid ZIP directory."}
	var count := tail.decode_u16(end + 10)
	var start := tail.decode_u32(end + 16)
	var size := tail.decode_u32(end + 12)
	if tail.decode_u16(end + 4) != 0 or tail.decode_u16(end + 6) != 0 or tail.decode_u16(end + 8) != count or count > 4096 or start + size > tail_at + end:
		return {"error":"Unsupported ZIP directory."}
	file.seek(start)
	var sizes := {}
	var seen := {}
	var total := 0
	for i in count:
		var header := file.get_buffer(46)
		if header.size() != 46 or header.decode_u32(0) != 0x02014b50: return {"error":"Damaged ZIP directory."}
		var flags := header.decode_u16(8)
		var method := header.decode_u16(10)
		var compressed := header.decode_u32(20)
		var unpacked := header.decode_u32(24)
		var name_size := header.decode_u16(28)
		var extra := header.decode_u16(30) + header.decode_u16(32)
		var mode := (header.decode_u32(38) >> 16) & 0xf000
		if flags & 1 or method not in [0, 8] or mode == 0xa000 or header.decode_u16(34) != 0 or header.decode_u32(42) >= start or compressed > limit or unpacked > limit:
			return {"error":"Encrypted, linked or oversized ZIP entry."}
		var name := file.get_buffer(name_size).get_string_from_utf8()
		if not ModSchema.safe_path(name.trim_suffix("/")) or seen.has(name.trim_suffix("/").to_lower()): return {"error":"Unsafe or duplicate ZIP path."}
		seen[name.trim_suffix("/").to_lower()] = true
		total += unpacked
		if total > limit or file.get_position() + extra > start + size: return {"error":"Unpacked package exceeds the size limit."}
		if not name.ends_with("/"): sizes[name] = unpacked
		file.seek(file.get_position() + extra)
	if file.get_position() != start + size: return {"error":"Invalid ZIP directory length."}
	if not sizes.has("mod.json") or sizes["mod.json"] > 1048576: return {"error":"Missing or oversized mod.json."}
	return {"error":"", "sizes":sizes}
