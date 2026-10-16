class_name ArenaCatalog
extends RefCounted
## The loaded campaign owns the roster and every appearance/statistic.
## No prototype IDs are displayed, including unnamed mod records.

var entries: Array[Dictionary] = []
var by_id := {}


func rebuild() -> void:
	entries.clear()
	by_id.clear()
	var families := {}
	for row: Dictionary in GameData.db.table("monster_prototypes"):
		var id := String(row.get("name", "")).to_lower()
		if id.is_empty() or by_id.has(id): continue
		var title := GameUnit.unit_title(id)
		if title.is_empty(): title = RemakeText.t("Creature")
		var entry := {"id": id, "title": title, "family": title, "row": row}
		families.get_or_add(title, []).append(entry)
		entries.append(entry)
		by_id[id] = entry
	for family: Array in families.values():
		if family.size() < 2: continue
		for i in family.size():
			family[i].title = RemakeText.t("%s (variant %d)") % [family[i].family, i + 1]
	entries.sort_custom(func(a, b): return String(a.title).naturalnocasecmp_to(b.title) < 0)


func search(query: String) -> Array[Dictionary]:
	var words := query.strip_edges().to_lower().split(" ", false)
	return entries.filter(func(e):
		for word: String in words:
			if not word in String(e.title).to_lower(): return false
		return true)
