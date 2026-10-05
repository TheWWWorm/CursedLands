extends RefCounted
## Native GS variable iteration (460ba0/460bc0/461750/460ee0). Sparse buckets
## retain the native head chains without allocating a potentially large vector.
const PRIMES := [53, 97, 193, 389, 769, 1543, 3079, 6151, 12289, 24593,
	49157, 98317, 196613, 393241, 786433, 1572869, 3145739, 6291469,
	12582917, 25165843, 50331653, 100663319, 201326611, 402653189,
	805306457, 1610612741, 3221225473, 4294967291]
const INITIAL := 193   # 581790 requests 100, then 408a50 picks the next prime


static func create() -> Dictionary:
	return {"capacity": INITIAL, "count": 0, "buckets": {}}


static func hash_name(key: String) -> int:
	var h := 0
	# MOB scripts are decoded as Latin-1, preserving their native name bytes.
	# String.to_ascii_buffer rejects the high half; the decoded script keeps
	# those original bytes as Latin-1 code points instead.
	for i in key.length():
		var c := key.unicode_at(i) & 0xff
		h = (h * 5 + (c if c < 128 else c - 256)) & 0xffffffff
	return h


static func keys(table: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var buckets: Dictionary = table.buckets
	var indices := buckets.keys()
	indices.sort()
	for i in indices:
		for k in buckets[i]:
			out.append(String(k))
	return out


static func valid(table: Dictionary) -> bool:
	if not int(table.get("capacity", 0)) in PRIMES or not table.get("buckets") is Dictionary:
		return false
	var count := 0
	var seen := {}
	for i in table.buckets:
		if not (i is int) or not table.buckets[i] is Array:
			return false
		for key in table.buckets[i]:
			if not (key is String) or key.is_empty() or seen.has(key) \
					or hash_name(key) % int(table.capacity) != i:
				return false
			seen[key] = true
			count += 1
	return count == int(table.get("count", -1))


static func has(table: Dictionary, key: String) -> bool:
	var i := hash_name(key) % int(table.capacity)
	return key in table.buckets.get(i, [])


static func put(table: Dictionary, key: String) -> void:
	if key.is_empty():
		return
	# Native growth precedes even an update of an existing key.
	_grow(table, int(table.count) + 1)
	var i := hash_name(key) % int(table.capacity)
	var chain: Array = table.buckets.get(i, [])
	if not key in chain:
		chain.push_front(key)
		table.buckets[i] = chain
		table.count = int(table.count) + 1


static func erase(table: Dictionary, key: String) -> void:
	var i := hash_name(key) % int(table.capacity)
	var chain: Array = table.buckets.get(i, [])
	if key in chain:
		chain.erase(key)
		table.count = int(table.count) - 1
		if chain.is_empty():
			table.buckets.erase(i)


static func filtered(table: Dictionary, prefix: String) -> Dictionary:
	# 460ee0 copies source buckets in ascending order into a cleared 193-bucket
	# temporary store; head insertion reverses collisions again.
	var out := create()
	for key in keys(table):
		if key.begins_with(prefix):
			put(out, key)
	return out


static func _grow(table: Dictionary, need: int) -> void:
	if need <= int(table.capacity):
		return
	var capacity: int = PRIMES[-1]
	for p: int in PRIMES:
		if p >= need:
			capacity = p
			break
	if capacity <= int(table.capacity):
		return
	var old := keys(table)
	var buckets := {}
	for key in old:
		var i := hash_name(key) % capacity
		var chain: Array = buckets.get(i, [])
		chain.push_front(key)
		buckets[i] = chain
	table.capacity = capacity
	table.buckets = buckets
