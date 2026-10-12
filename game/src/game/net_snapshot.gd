class_name NetSnapshot
extends RefCounted
## Compress each existing MTU-bounded chunk independently. Actor records,
## chunk membership, sequence numbers and update cadence remain unchanged.
const MAX_BYTES := 65536


static func pack(records: Array) -> Array:
	var raw := var_to_bytes(records)
	if raw.size() < 256 or raw.size() > MAX_BYTES: return records
	var wire := [raw.size(),raw.compress(FileAccess.COMPRESSION_ZSTD)]
	return wire if var_to_bytes(wire).size()+16 < raw.size() else records


static func unpack(wire: Array) -> Array:
	if wire.is_empty() or wire[0] is Array: return wire
	if wire.size() != 2 or not wire[0] is int or not wire[1] is PackedByteArray: return []
	var size: int = wire[0]
	var payload: PackedByteArray = wire[1]
	if size <= 0 or size > MAX_BYTES or payload.is_empty() or payload.size() > MAX_BYTES: return []
	var raw := payload.decompress(size,FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size: return []
	var records = bytes_to_var(raw)
	if not records is Array or not records.all(func(row):return row is Array): return []
	return records
