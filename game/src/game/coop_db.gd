extends RefCounted
## Remake co-op: a joiner uses the host's database numbers while it plays.
## Editions ship different database.res files with the same rows (the Russian
## one gives 14 maces / spears attack 0 where the English one has 5–20); the
## host's numbers rule the game, so the joiner's tooltips, inventory and
## trader screens take them too. the original has no counterpart: each original draws
## from its own database (its network messages carry ids only, not numbers).
## The joiner sends a digest per table (NetStatus, after its hello); the host
## answers with the rows of the tables that differ; the joiner copies their
## non-text fields over its own rows (texts stay its language) and puts its
## own values back when the session ends.

## table -> row name -> {field: own value} (joiner, while host values apply)
static var _saved := {}
## table -> [row names the joiner did not have and took from the host]
static var _added := {}


## table -> MD5 of its rows (the "#index" tables are views of the same rows).
static func digests() -> Dictionary:
	var out := {}
	if GameData.db == null:
		return out
	for t: String in GameData.db.tables:
		if not t.ends_with("#index") and GameData.db.tables[t] is Array:
			out[t] = var_to_bytes(GameData.db.tables[t]).hex_encode().md5_text()
	return out


## Host: the rows of every table whose digest differs from the joiner's.
static func rows_for(theirs: Dictionary) -> Dictionary:
	var out := {}
	var mine := digests()
	for t: String in mine:
		if String(theirs.get(t, "")) != mine[t]:
			out[t] = GameData.db.tables[t]
	return out


## Joiner: the host's numbers over its own rows (matched by name).
static func apply(host_tables: Dictionary) -> int:
	var n := 0
	for t: String in host_tables:
		var idx: Dictionary = GameData.db.tables.get(t + "#index", {})
		var rows: Array = GameData.db.tables.get(t, [])
		for i in (host_tables[t] as Array).size():
			var hr: Dictionary = host_tables[t][i]
			var nm := String(hr.get("name", "")).to_lower()
			var row: Dictionary = idx.get(nm, {}) if nm != "" else ({} if i >= rows.size() else rows[i])
			if row.is_empty():
				if nm == "":
					continue
				rows.append(hr)
				idx[nm] = hr
				_added.get_or_add(t, []).append(nm)
				n += 1
				continue
			for k in hr:
				if hr[k] is String or hr[k] is StringName or not row.has(k) or row[k] == hr[k]:
					continue
				var saved: Dictionary = (_saved.get_or_add(t, {}) as Dictionary).get_or_add(nm if nm != "" else str(i), {})
				if not saved.has(k):
					saved[k] = row[k]
				row[k] = hr[k]
				n += 1
	_clear_caches()
	return n


## Joiner leaving the session: its own numbers back.
static func restore() -> void:
	if _saved.is_empty() and _added.is_empty():
		return
	for t: String in _saved:
		var idx: Dictionary = GameData.db.tables.get(t + "#index", {})
		var rows: Array = GameData.db.tables.get(t, [])
		for key: String in _saved[t]:
			var row: Dictionary = idx.get(key, {})
			if row.is_empty() and key.is_valid_int() and int(key) < rows.size():
				row = rows[int(key)]
			for k in _saved[t][key]:
				row[k] = _saved[t][key][k]
	for t: String in _added:
		var idx: Dictionary = GameData.db.tables.get(t + "#index", {})
		var rows: Array = GameData.db.tables.get(t, [])
		for nm: String in _added[t]:
			rows.erase(idx.get(nm))
			idx.erase(nm)
	_saved.clear()
	_added.clear()
	_clear_caches()


static func _clear_caches() -> void:
	Items._cache.clear()
	Spells._cache.clear()
