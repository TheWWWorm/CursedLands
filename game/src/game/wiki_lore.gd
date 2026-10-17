class_name WikiLore
extends RefCounted
## Reviewed story articles tied to the installed campaign's original sources.
## Source matching prevents an edited mod scene from silently inheriting lore.
var records := {}
var sources := {}
var _script_cache := {}
var _catalog_ref: WeakRef
var catalog: RefCounted:
	get: return _catalog_ref.get_ref()

func build(owner: RefCounted) -> void:
	_catalog_ref = weakref(owner)
	_script_cache.clear()
	records = WikiLoreData.DATA.campaigns.get(GameData.campaign_id, {})
	sources = WikiLoreData.DATA.sources.get(GameData.campaign_id, {})
	for key: String in records:
		var row: Dictionary = records[key]
		if row.kind == "map": continue
		var title := character_name(row) if row.kind == "character" else WikiWorldText.text(row.name_key).get_slice("\n", 0).strip_edges()
		if title.is_empty(): continue
		catalog._add(key, title, "Characters" if row.kind == "character" else "Allods", row.kind, row.id)
		if row.kind == "character":
			catalog.entries[key].aliases = row.names.values() + row.get("alias_names", {}).values()

static func fingerprint(value: String) -> String:
	return value.replace("\r", "").strip_edges().sha256_text()

func character_name(row: Dictionary) -> String:
	var installed := GameData.text(row.name_key).strip_edges()
	if fingerprint(installed) in row.name_hashes:
		return row.names.get(RemakeText.lang, installed)
	# A localized edition or mod's own name takes precedence.
	return installed

func matches(section: Dictionary) -> bool:
	for key: String in section.sources:
		if not fingerprint(source_text(key)) in sources[key].hashes: return false
	return true

func source_text(key: String) -> String:
	if not sources[key].has("script"): return GameData.text(key)
	var name: String = sources[key].script
	if not _script_cache.has(name):
		_script_cache[name] = catalog.map_records(name).script_text
	return _script_cache[name]

func prose(text: String) -> String:
	var out := ""
	var cursor := 0
	for found: RegExMatch in RegEx.create_from_string("\\[\\[([^]]+)\\]\\]").search_all(text):
		out += WikiCatalog.esc(text.substr(cursor, found.get_start() - cursor))
		var reference := found.get_string(1)
		var key := reference.get_slice("|", 0)
		# References are validated at build time; missing mod content stays text.
		var label: String = reference.get_slice("|", 1) if "|" in reference else String(catalog.entries.get(key, {}).get("title", RemakeText.t("Page unavailable")))
		out += WikiCatalog.link(key, label) if catalog.entries.has(key) else WikiCatalog.esc(label)
		cursor = found.get_end()
	return out + WikiCatalog.esc(text.substr(cursor))

func html(key: String) -> String:
	if not records.has(key): return ""
	var row: Dictionary = records[key]
	var out := ""
	if row.has("alias_names"):
		out += WikiCatalog.paragraph(WikiCatalog.esc(RemakeText.t("Also known as")) + ": " + WikiCatalog.esc(row.alias_names.get(RemakeText.lang, "")), true)
	var used: Array[String] = []
	var omitted := false
	for section: Dictionary in row.sections:
		if not matches(section): omitted = true; continue
		var citations := PackedStringArray()
		for source: String in section.sources:
			if not source in used: used.append(source)
			citations.append(str(used.find(source) + 1))
		out += WikiCatalog.heading(RemakeText.t(section.heading))
		out += WikiCatalog.paragraph(prose(RemakeText.t(section.text)) + " [" + ", ".join(citations) + "]", true)
	if omitted:
		out += WikiCatalog.paragraph(RemakeText.t("Some story sections are unavailable because the installed sources differ from those used for this article."))
	if not used.is_empty():
		out += WikiCatalog.heading(RemakeText.t("Sources"))
		out += WikiCatalog.paragraph(RemakeText.t("Based on the original dialogue, quest journals, event scripts and world descriptions. Source numbers identify the evidence listed below."))
		var rows := []
		for i in used.size(): rows.append([str(i + 1), source_label(used[i])])
		out += WikiCatalog.table_html(["#", RemakeText.t("Sources")], rows)
	return out

func source_label(key: String) -> String:
	var source: Dictionary = sources[key]
	var names := PackedStringArray()
	if source.has("script"):
		for zone: String in source.zones:
			var target := "map/" + zone
			if catalog.entries.has(target): names.append(WikiCatalog.link(target, catalog.entries[target].title))
	elif source.has("actors"):
		for actor: String in source.actors:
			for target: String in records:
				if actor in records[target].get("actors", []) and catalog.entries.has(target):
					var name := WikiCatalog.link(target, catalog.entries[target].title)
					if not name in names: names.append(name)
	else:
		var title := WikiWorldText.text(key).get_slice("\n", 0).strip_edges()
		if title: names.append(WikiCatalog.esc(title))
	var label := "Event script" if source.has("script") else ("Dialogue" if source.has("actors") else ("Quest journal" if key.begins_with("quest ") else "World description"))
	return WikiCatalog.esc(RemakeText.t(label)) + " · " + ", ".join(names) + " (" + WikiCatalog.esc(key) + ")"

func model(key: String) -> Dictionary:
	var row: Dictionary = records.get(key, {})
	for prototype: String in row.get("prototypes", []):
		if not GameData.db.find("monster_prototypes", prototype).is_empty():
			return {"kind":"creature", "value":prototype}
	if row.get("kind", "") == "allod":
		return {"kind":"allod", "value":String(row.name_key).trim_prefix("allod ")}
	return {}

func connect_pages(graph: RefCounted) -> void:
	for key: String in records:
		if not catalog.entries.has(key): continue
		var row: Dictionary = records[key]
		if row.kind == "character":
			graph.subtitles[key] = RemakeText.t(row.get("role", "Characters"))
			for location: String in row.locations:
				var map_key := "map/" + location.uri_encode()
				graph.add(key, "location", map_key)
				graph.add(map_key, "people", key)
				var island := allod_key(catalog._campaign.zone(location).get("allod", ""))
				graph.add(island, "people", key)
			for prototype: String in row.prototypes:
				var creature := "creature/" + prototype.uri_encode()
				graph.add(key, "model", creature)
				graph.add(creature, "biography", key)
		# Cross-references belong to the verified prose, not unrelated actor IDs.
		for section: Dictionary in row.sections:
			if not matches(section): continue
			for found: RegExMatch in RegEx.create_from_string("\\[\\[(character/[^]|]+)(?:\\|[^]]+)?\\]\\]").search_all(section.text):
				var target := found.get_string(1)
				graph.add(key, "person", target)
				if row.kind == "character": graph.add(target, "person", key)
	for zone: Dictionary in catalog._campaign.zones.values():
		var map_key := "map/" + String(zone.id).uri_encode()
		graph.add(allod_key(zone.get("allod", "")), "region", map_key)

static func allod_key(id: String) -> String:
	return "allod/" + ("gipat" if id == "gipat2" else id).uri_encode()

func search_text(key: String) -> String:
	var row: Dictionary = records.get(key, {})
	var text := ""
	if row.has("alias_names"): text += " " + row.alias_names.get(RemakeText.lang, "")
	for section: Dictionary in row.get("sections", []):
		if matches(section): text += " " + RemakeText.t(section.text)
	return text
