extends Node
## Read-only U25 source/checkpoint inventory, not a played-route test.
## --harpy-manifest=<JSON dictionary of labels: {copy, sha256, original?}>
## Run with original base assets and an isolated user profile. Reads save copies
## directly; never creates a Game/Session or changes quest, actor or VM state.

const ACTORS := [1155, 1163, 1164, 1165, 1390]
const BRIEFINGS := ["s12_4", "z13_1", "z14", "z14_1", "z15"]
const SOURCES := {
	"zone6.mob": ["VCheck#0#310", "VTriger#0#312", "VTriger#0#328", "VCheck#0#330", "VCheck#0#334",
		"VCheck#0#337", "VTriger#0#338", "VTriger#0#341", "VCheck#0#342",
		"VCheck#0#362", "VTriger#0#366", "VCheck#0#376", "VTriger#0#377",
		"VCheck#0#390", "VCheck#0#393",
		"VTriger#0#394", "VCheck#0#396", "VTriger#0#398", "VTriger#0#401",
		"VCheck#0#402", "VCheck#0#404", "VTriger#0#406"],
	"zone6dkin.mob": ["VCheck#5#1", "VCheck#5#4", "VCheck#5#7", "VTriger#5#8"],
	"basecam.mob": ["VCheck#0#539", "VTriger#0#543"],
	"bz2g.mob": ["VCheck#0#59", "VTriger#0#60"],
}

var errors: Array[String] = []
var reads := 0

func require(ok: bool, label: String) -> bool:
	reads += 1
	if not ok: errors.append(label)
	print("PASS " if ok else "FAIL ", label)
	return ok

func script_body(source: String, name: String) -> String:
	var start := source.find("\nScript " + name + "\n")
	if start < 0: return ""
	var end := source.find("\nScript ", start + 1)
	if end < 0: end = source.find("\nWorldScript", start + 1)
	return source.substr(start + 1, end - start - 1 if end >= 0 else -1)

func selected(data: Dictionary, keys: Array) -> Dictionary:
	var out := {}
	for key: String in keys:
		if data.has(key): out[key] = data[key]
	return out

func checkpoint(data: Dictionary) -> Dictionary:
	var vars := {}
	for key: String in data.get("vars", {}):
		var low := key.to_lower()
		if low.begins_with("0:q.") or low.begins_with("0:z.") or low.contains("witch") \
				or low in ["0:gfol", "0:dfol", "0:dcword", "0:frozen"]:
			vars[key] = data.vars[key]
	var zone: Dictionary = data.get("zones", {}).get("gz6g", {})
	var actors := {}
	for uid: int in ACTORS:
		actors[uid] = {"unit": zone.get("units", {}).get(uid),
			"dead": uid in zone.get("dead", []), "removed": uid in zone.get("removed", []),
			"looted": uid in zone.get("looted", []), "lever": zone.get("levers", {}).get(uid)}
	var heroes := {}
	for owner in data.get("heroes", {}):
		heroes[owner] = []
		for hero: Dictionary in data.heroes[owner]:
			heroes[owner].append(selected(hero, ["name", "pos", "hp", "dead", "merc", "exp",
				"exp_total", "weapons", "armors", "spells", "skills", "perks"]))
	var pending := []
	for instance: Dictionary in zone.get("vm", {}).get("instances", []):
		pending.append(selected(instance, ["s", "w", "l", "f", "i", "b", "k"]))
	return {"zone": data.get("current_zone"), "vars": vars,
		"quest_items": data.get("quest_items", {}), "quests": data.get("quests", {}),
		"visited_zones": data.get("zones", {}).keys(), "heroes": heroes,
		"gz6g_actors": actors, "gz6g_pending_instances": pending}

func _ready() -> void:
	var manifest_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--harpy-manifest="):
			manifest_path = arg.trim_prefix("--harpy-manifest=")
	var result := {"scope": "Read-only source/checkpoint audit; zero played-route checks.",
		"campaign": GameData.campaign_id, "sources": {}, "briefings": {}, "saves": {}}
	if not require(GameData.campaign_id == CampaignProfile.ORIGINAL, "original base campaign selected"):
		finish(result); return
	if not require(FileAccess.file_exists(manifest_path), "explicit checkpoint manifest exists"):
		finish(result); return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not require(manifest is Dictionary and not manifest.is_empty(), "checkpoint manifest is a nonempty dictionary"):
		finish(result); return
	result.manifest_sha256 = FileAccess.get_sha256(manifest_path)
	for label: String in manifest:
		var row: Dictionary = manifest[label]
		var path := String(row.get("copy", ""))
		if not require(FileAccess.file_exists(path), label + " disposable copy exists"): continue
		var before := FileAccess.get_sha256(path)
		if not require(before == row.get("sha256"), label + " copy matches recorded source SHA-256"): continue
		var original := String(row.get("original", ""))
		if not original.is_empty():
			require(FileAccess.file_exists(original) and FileAccess.get_sha256(original) == before,
				label + " original source remains unchanged")
		var data = CampaignState.read_data(path)
		if not require(data is Dictionary and data.has("zones"), label + " save decodes"): continue
		result.saves[label] = checkpoint(data)
		result.saves[label].path = path
		result.saves[label].sha256 = before
		require(FileAccess.get_sha256(path) == before, label + " audit leaves copy unchanged")
	for file: String in SOURCES:
		var mob := EIMob.load_bytes(GameData.read_file("maps/" + file))
		if not require(mob != null and not mob.script_text.is_empty(), file + " original script exists"): continue
		var source: String = mob.script_text
		var parsed := ScriptParser.parse(source)
		require(parsed.errors.is_empty(), file + " original source parses")
		var blocks := {}
		for name: String in SOURCES[file]:
			var body := script_body(source, name)
			require(not body.is_empty(), file + " contains " + name)
			blocks[name] = body
		result.sources[file] = {"script_sha256": source.sha256_text(), "blocks": blocks}
	for name: String in BRIEFINGS:
		var row: Dictionary = GameData.db.find("briefings", name)
		require(not row.is_empty(), name + " original briefing row exists")
		result.briefings[name] = row
	finish(result)

func finish(result: Dictionary) -> void:
	result.read_checks = reads
	result.errors = errors
	result.played_route_checks = 0
	FileAccess.open("user://harpy-route-audit.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("HARPY_ROUTE_AUDIT ", reads, " read checks, ", errors.size(), " failures; no route completion claim")
	get_tree().quit(0 if errors.is_empty() else 1)
