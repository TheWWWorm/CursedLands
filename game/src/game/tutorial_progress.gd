class_name TutorialProgress
extends RefCounted
## Local, per-campaign learning history. Never sent in a save or network packet.
const FILE := "user://tutorial_progress.cfg"
static var persist := true
static var _loaded := false
static var _data := {}

static func _load() -> void:
	if _loaded: return
	_loaded = true
	var file := ConfigFile.new()
	if file.load(FILE) == OK:
		for campaign in file.get_sections():
			_data[campaign] = file.get_value(campaign, "topics", {})

static func records() -> Dictionary:
	_load()
	var campaign := GameData.campaign_id
	if not _data.has(campaign):
		_data[campaign] = {}
		# Old seen entries mean encountered, never acted-on. Do not replay them.
		if FileAccess.file_exists("user://tutorial.ini"):
			for line in FileAccess.get_file_as_string("user://tutorial.ini").split("\n"):
				var fields := line.strip_edges().split(" ", false)
				if fields.size() >= 2:
					_data[campaign][TutorialGuide.canonical(fields[0])] = {"encountered": 0, "shown": true}
	return _data[campaign]

static func has(id: String, flag := "encountered") -> bool:
	return records().get(id, {}).has(flag)

static func record(id: String, flag := "encountered") -> void:
	var topics := records()
	if not topics.has(id): topics[id] = {"encountered": int(Time.get_unix_time_from_system())}
	if topics[id].has(flag): return
	topics[id][flag] = int(Time.get_unix_time_from_system())
	_save()

static func encounter(id: String) -> void:
	if has(id): return
	records()[id] = {"encountered": int(Time.get_unix_time_from_system())}
	_save()

static func recent() -> Array:
	var topics := records()
	var ids := topics.keys()
	ids.sort_custom(func(a, b): return int(topics[a].encountered) > int(topics[b].encountered))
	return ids

static func _save() -> void:
	if not persist: return
	var file := ConfigFile.new()
	for campaign in _data: file.set_value(campaign, "topics", _data[campaign])
	file.save(FILE)
