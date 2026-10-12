class_name NetState
extends RefCounted
## Campaign/UI state stays on the gameplay event's reliable channel, retaining
## ordering with inventory, quest and zone events. Compress the whole document
## before ENet fragments it; per-datagram range coding misses repeated keys
## across the large LiA party/quest/variable tables.
const MAX_BYTES := 16 * 1024 * 1024


static func pack(event: Dictionary) -> Dictionary:
	var raw := var_to_bytes(event)
	if raw.size() < 512 or raw.size() > MAX_BYTES:
		return event
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.size() + 64 >= raw.size():
		return event
	return {"t":"state_zip", "bytes":raw.size(), "data":compressed}


static func unpack(event: Dictionary) -> Dictionary:
	var size: Variant = event.get("bytes")
	var payload: Variant = event.get("data")
	if not size is int or size <= 0 or size > MAX_BYTES or not payload is PackedByteArray \
			or payload.is_empty() or payload.size() > MAX_BYTES:
		return {}
	var raw: PackedByteArray = payload.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size: return {}
	var decoded: Variant = bytes_to_var(raw) # peer data never instantiates objects
	if not decoded is Dictionary or decoded.get("t") != "state": return {}
	return decoded
