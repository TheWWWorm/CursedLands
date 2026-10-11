class_name ModStore
extends RefCounted
## Installed immutable packages, local profiles and effective session rules.
const CONFIG := "user://mod_settings.json"
const ROOT := "user://mods"
const MAX_MANIFEST := 1048576
const MAX_PACKAGE := 134217728
static var profiles: Dictionary = {}
static var selected: Dictionary = {}
static var catalog: Dictionary = {}
static var errors: Array[String] = []
static var startup_error := ""
static var _loaded := false
static var _session: WeakRef
static var _archives: Dictionary = {}
static var _mounted: Array = []
static var _config_bad := false

static func initialize() -> void:
	if _loaded: return
	_loaded = true
	var file := FileAccess.open(CONFIG, FileAccess.READ)
	if file and file.get_length() <= MAX_MANIFEST:
		var data: Variant = JSON.parse_string(file.get_as_text())
		if data is Dictionary and data.get("version") == 1 and data.get("profiles") is Dictionary and data.get("selected") is Dictionary:
			for id in data.profiles:
				var p: Variant = data.profiles[id]
				if ModSchema.identifier(id) and id != "default" and p is Dictionary and p.get("name") is String and p.name.length() <= 80 and p.get("packages") is Array and p.get("values") is Dictionary and p.get("rules") is Dictionary and p.get("sandbox", false) is bool:
					if rule_error(p.rules) == "":
						profiles[id] = p
					else: _config_bad = true
				else: _config_bad = true
			selected = data.selected
		else: _config_bad = true
	elif FileAccess.file_exists(CONFIG): _config_bad = true
	if _config_bad: errors.append("Could not read mod profiles. A recovery copy will be kept before saving changes.")
	rescan()

static func active_id() -> String:
	initialize()
	var id: String = str(selected.get(GameData.campaign_id, "default"))
	return id if profiles.has(id) else "default"

static func profile() -> Dictionary:
	var id := active_id()
	return profiles.get(id, {"name": "Current defaults", "packages": [], "rules": {}, "values": {}, "sandbox": false})

static func session() -> Node:
	return _session.get_ref() if _session != null else null

static func attach(s: Node) -> void:
	_session = weakref(s)

static func detach(s: Node) -> void:
	if session() == s:
		_session = null
		GameData.difficulty = GameData.option("difficulty")

static func snapshot() -> Dictionary:
	var p := profile()
	var rules := {}
	for key in ModSchema.RULES:
		rules[key] = int(p.rules.get(key, GameData.options.get(key, 0)))
	var packages := []
	for key in _mounted:
		var m: Dictionary = catalog[key]
		packages.append({"id": m.id, "version": m.version, "digest": m._digest, "gameplay": ModSchema.gameplay(m)})
	var values := {}
	for o in option_definitions(): values[o.key] = p.values.get(o.key, o.default)
	return {"api": ModSchema.API, "campaign": GameData.campaign_id, "profile": active_id(),
		"name": p.name, "rules": rules, "values": values, "packages": packages,
		"sandbox": bool(p.get("sandbox", false)), "revision": 0}

static func effective() -> Dictionary:
	var s := session()
	return s.mod_config if s != null and not s.mod_config.is_empty() else snapshot()

static func option(key: String, fallback: int) -> int:
	if not ModSchema.RULES.has(key) or not _loaded: return fallback
	var s := session()
	if s != null and not s.mod_config.is_empty(): return int(s.mod_config.rules.get(key, fallback))
	return int(profile().rules.get(key, fallback))

static func capability(binding: String) -> float:
	var values: Dictionary = effective().get("values", {})
	for key in _mounted:
		var m: Dictionary = catalog[key]
		for o in m.get("options", []):
			if o.binding == binding: return float(values.get(m.id + ":" + o.id, o.default))
	return float(ModSchema.CAPABILITIES.get(binding, {}).get("default", 0.0))

static func rule_error(values: Dictionary) -> String:
	for key in values:
		if not key is String or not ModSchema.RULES.has(key): return "Unknown game rule."
		if not ModSchema.finite_number(values[key]) or float(values[key]) != floorf(float(values[key])): return "Invalid game rule value."
		if values[key] < 0 or values[key] >= ModSchema.RULES[key][1].size(): return "Game rule is outside its allowed range."
	return ""

static func editable(key: String, s: Node = null) -> String:
	if key.begins_with("sandbox_") and not effective().get("sandbox", false): return "Available only in a sandbox profile."
	if s == null: s = session()
	if s == null: return ""
	if not s.can_manage_game(): return "Only the host can change this rule."
	if not s.lmp.is_empty() and key in ["revive", "sp_full_xp", "coop_full_xp", "coop_scale", "coop_share_loot", "coop_clock", "merc_travel", "start_zones"]: return "This rule applies to campaign play."
	if s.loading_game or s.movie_active(): return "Wait for loading or the scene to finish."
	if s.world == null: return ""
	var timing: String = str(ModSchema.RULES.get(key, ["", [], "camp"])[2])
	if timing == "new_game": return "Choose this rule before starting a game."
	if timing == "camp" and not s.shop_available(): return "Change this rule at camp."
	return ""

static func apply_rules(values: Dictionary, notify := true) -> String:
	return apply_settings(values, {}, notify)

static func apply_settings(rules: Dictionary, values: Dictionary, notify := true) -> String:
	var error := rule_error(rules)
	if error == "": error = values_error(values)
	if error != "": return error
	var s := session()
	for key in rules:
		error = editable(key, s)
		if error != "": return error
	if not values.is_empty():
		error = editable("revive", s)
		if error != "": return error
	if rules.is_empty() and values.is_empty(): return ""
	if s != null:
		s.request_mod_rules(rules, values)
		return ""
	var p := profile().duplicate(true)
	p.rules.merge(rules, true)
	p.values.merge(values, true)
	if active_id() == "default":
		# Current defaults retain their original settings.cfg representation.
		for key in rules: GameData.options[key] = int(rules[key])
		GameData.difficulty = int(GameData.options.get("difficulty", 0))
		GameData.save_settings()
	else:
		error = store_profile(active_id(), p)
		if error != "": return error
	GameData.difficulty = GameData.option("difficulty")
	if notify: GameData.options_changed.emit()
	return ""

static func option_definitions() -> Array:
	var out := []
	for key in _mounted:
		var m: Dictionary = catalog[key]
		for definition in m.get("options", []):
			var o: Dictionary = definition.duplicate(true)
			o.key = m.id + ":" + o.id
			o.mod_title = m.title
			out.append(o)
	return out

static func values_error(values: Dictionary) -> String:
	var definitions := {}
	for o in option_definitions(): definitions[o.key] = o
	for key in values:
		if not definitions.has(key): return "Unknown mod option: " + str(key)
		var error := ModSchema.value_error(definitions[key], values[key])
		if error != "": return str(key) + ": " + error
	return ""

static func apply_values(values: Dictionary) -> String:
	return apply_settings({}, values)

static func save_directory(base: String) -> String:
	var id := active_id()
	return base if id == "default" else base.path_join("mods/" + id)

static func restart(tree: SceneTree) -> void:
	if OS.has_feature("web"):
		# Reopen the same campaign without reloading the browser page while
		# Godot's persistent filesystem may still be flushing new packages.
		DataSwitch.clear_caches()
		tree.reload_current_scene()
	else: DataSwitch.restart(tree)

static func content_signature(config: Dictionary) -> String:
	var required := []
	for p in config.get("packages", []):
		if p.get("gameplay", true): required.append(p)
	return ModSchema.digest({"api": config.get("api", 1), "campaign": config.get("campaign", ""), "packages": required, "sandbox": config.get("sandbox", false)})

static func progress_signature(config: Dictionary) -> String:
	# Existing co-op host rules retain their established progression behavior.
	return ModSchema.digest({"content": content_signature(config), "values": config.get("values", {})})

static func required_summary(config: Dictionary) -> String:
	var labels := PackedStringArray()
	for p in config.get("packages", []):
		if p.get("gameplay", false): labels.append("%s %s [%s]" % [p.id, p.version, str(p.digest).left(8)])
	if config.get("sandbox", false): labels.append("Sandbox")
	return ", ".join(labels) if not labels.is_empty() else "Current defaults (no gameplay mods)"

static func configuration_error(config: Variant) -> String:
	if not config is Dictionary or config.get("api") != ModSchema.API: return "Unsupported saved mod configuration."
	if config.get("campaign") != GameData.campaign_id: return "The mod configuration belongs to another campaign."
	if not config.get("rules") is Dictionary or not config.get("values") is Dictionary or not config.get("packages") is Array: return "Invalid mod configuration."
	if var_to_bytes(config).size() > MAX_MANIFEST: return "Mod configuration is too large."
	if not config.get("name") is String or config.name.length() > 80 or not ModSchema.identifier(config.get("profile")): return "Invalid profile metadata."
	if not config.get("sandbox") is bool or not ModSchema.finite_number(config.get("revision")) or config.revision < 0 or config.revision != floorf(config.revision): return "Invalid mod configuration metadata."
	if config.rules.size() != ModSchema.RULES.size(): return "The shared rule list is incomplete."
	if config.values.size() != option_definitions().size(): return "The shared mod options are incomplete."
	var error := rule_error(config.rules)
	if error != "": return error
	if not config.sandbox and (config.rules.sandbox_invulnerable != 0 or config.rules.sandbox_mana != 0): return "Sandbox rules require a sandbox profile."
	var ids := {}
	for p in config.packages:
		if not p is Dictionary or not ModSchema.identifier(p.get("id")) or not ModSchema.identifier(p.get("version")) or not p.get("digest") is String or not p.get("gameplay") is bool: return "Invalid required package."
		if p.digest.length() != 64 or not p.digest.is_valid_hex_number() or ids.has(p.id): return "Invalid package fingerprint."
		ids[p.id] = true
	if content_signature(config) != content_signature(snapshot()): return "Required setup: " + required_summary(config) + ". Select a matching mod profile first."
	return values_error(config.values)

static func saved_error(config: Variant) -> String:
	if startup_error != "": return startup_error
	if config is Dictionary and config.is_empty():
		return "" if active_id() == "default" else "This legacy save belongs to Current defaults."
	return configuration_error(config)

static func mode_error(mode: String) -> String:
	if startup_error != "": return startup_error
	if mode == "original_multiplayer" and effective().get("sandbox", false): return "Sandbox profiles support single player and campaign co-op."
	for key in _mounted:
		if mode not in catalog[key].get("modes", ModSchema.MODES): return str(catalog[key].title) + " does not support this game mode."
	return ""

static func store_profile(id: String, p: Dictionary) -> String:
	var next := profiles.duplicate(true)
	next[id] = p
	var error := _write_config(next, selected)
	if error == "": profiles = next
	return error

static func create_profile(title: String, sandbox := false) -> String:
	if session() != null: return "Return to the main menu to create a profile."
	title = title.strip_edges().left(80)
	if title.is_empty(): return "Enter a profile name."
	var id := "p" + Crypto.new().generate_random_bytes(12).hex_encode()
	var p := profile().duplicate(true)
	p.name = title
	p.sandbox = sandbox
	p.rules = snapshot().rules
	if not sandbox:
		p.rules.sandbox_invulnerable = 0
		p.rules.sandbox_mana = 0
	var next := profiles.duplicate(true)
	next[id] = p
	var selection := selected.duplicate(true)
	selection[GameData.campaign_id] = id
	var error := _write_config(next, selection)
	if error == "":
		profiles = next
		selected = selection
	return error

static func select_profile(id: String) -> String:
	if session() != null: return "Return to the main menu to switch profiles."
	if id != "default" and not profiles.has(id): return "Profile not found."
	var selection := selected.duplicate(true)
	selection[GameData.campaign_id] = id
	var p: Dictionary = profiles.get(id, {"packages": [], "values": {}})
	var checked := resolve(p)
	if checked.error != "": return checked.error
	var error := _write_config(profiles, selection)
	if error == "": selected = selection
	return error

static func set_packages(keys: Array) -> String:
	if session() != null: return "Return to the main menu to change packages."
	if active_id() == "default": return "Create a named profile before enabling mods."
	var p := profile().duplicate(true)
	p.packages = keys
	# Disabled mod preferences may be retained locally but never in the run.
	var checked := resolve(p)
	if checked.error != "": return checked.error
	var valid_values := {}
	for key in checked.order:
		for o in catalog[key].get("options", []):
			var id: String = catalog[key].id + ":" + o.id
			valid_values[id] = p.values.get(id, o.default)
	p.values = valid_values
	return store_profile(active_id(), p)

static func _write_config(p: Dictionary, selection: Dictionary) -> String:
	var bytes := JSON.stringify({"version": 1, "profiles": p, "selected": selection}).to_utf8_buffer()
	if bytes.size() > MAX_MANIFEST: return "The mod profile file is too large."
	if _config_bad:
		var recovery := CONFIG + ".recovery-" + str(Time.get_unix_time_from_system())
		if DirAccess.copy_absolute(CONFIG, recovery) != OK: return "Could not preserve the unreadable profile file."
		_config_bad = false
	return atomic_write(CONFIG, bytes)

static func atomic_write(path: String, bytes: PackedByteArray) -> String:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return "Could not create the mod storage folder."
	var pending := path + ".pending"
	var f := FileAccess.open(pending, FileAccess.WRITE)
	if f == null: return "Could not write mod settings."
	f.store_buffer(bytes)
	f.flush()
	var error := f.get_error()
	f.close()
	if error != OK: return "Could not finish writing mod settings."
	if DirAccess.rename_absolute(pending, path) != OK: return "Could not replace mod settings."
	return ""

static func rescan() -> void:
	catalog.clear()
	if not DirAccess.dir_exists_absolute(ROOT): return
	for folder in DirAccess.get_directories_at(ROOT):
		if folder.begins_with("."): continue
		var base := ROOT.path_join(folder)
		var file := FileAccess.open(base.path_join("mod.json"), FileAccess.READ)
		if file == null or file.get_length() > MAX_MANIFEST: continue
		var m: Variant = JSON.parse_string(file.get_as_text())
		var error := ModSchema.manifest_error(m)
		if error != "":
			errors.append(folder + ": " + error)
			continue
		var key: String = m.id + "@" + m.version
		if folder != key or catalog.has(key):
			errors.append("Invalid installed package folder: " + folder)
			continue
		var hashes := {}
		for a in m.get("overrides", []):
			var path := base.path_join(a.file)
			var asset := FileAccess.open(path, FileAccess.READ)
			if asset == null or asset.get_length() > MAX_PACKAGE:
				error = "Missing or oversized asset: " + a.file
				break
			hashes[a.file] = FileAccess.get_sha256(path)
		if error != "":
			errors.append(key + ": " + error)
			continue
		m._digest = ModSchema.digest({"manifest": m, "files": hashes})
		m._root = base
		catalog[key] = m

static func resolve(p: Dictionary) -> Dictionary:
	var nodes := {}
	var order := []
	var ready: Array = p.get("packages", []).duplicate()
	for key in ready:
		if not key is String or not catalog.has(key): return {"error": "Missing package: " + str(key), "order": []}
		var m: Dictionary = catalog[key]
		if nodes.has(m.id): return {"error": "Choose one version of " + m.id, "order": []}
		if GameData.campaign_id not in m.campaigns: return {"error": m.title + " does not support this campaign.", "order": []}
		nodes[m.id] = key
	for key in ready:
		for id in catalog[key].get("requires", []):
			if not nodes.has(id): return {"error": catalog[key].title + " requires " + id, "order": []}
		for id in catalog[key].get("conflicts", []):
			if nodes.has(id): return {"error": catalog[key].title + " conflicts with " + id, "order": []}
	while not ready.is_empty():
		var advanced := false
		for key in ready.duplicate():
			var waits := false
			for id in catalog[key].get("requires", []) + catalog[key].get("after", []):
				if nodes.has(id) and nodes[id] not in order: waits = true
			if not waits:
				order.append(key)
				ready.erase(key)
				advanced = true
		if not advanced: return {"error": "The mod dependency order contains a cycle.", "order": []}
	var targets := {}
	for key in order:
		var m: Dictionary = catalog[key]
		var writes := []
		for a in m.get("overrides", []): writes.append("asset:" + a.archive + "/" + a.entry.to_lower())
		for patch in m.get("patches", []): writes.append("db:" + patch.get("database", "campaign") + "/" + patch.table + "/" + patch.record.to_lower() + "/" + patch.field)
		for o in m.get("options", []): writes.append("binding:" + o.binding)
		for target in writes:
			if targets.has(target): return {"error": "Conflict on " + target + " between " + targets[target] + " and " + m.title, "order": []}
			targets[target] = m.title
	return {"error": "", "order": order}

static func mount() -> String:
	initialize()
	_archives.clear()
	_mounted.clear()
	var checked := resolve(profile())
	startup_error = checked.error
	if startup_error != "": return startup_error
	_mounted = checked.order
	startup_error = rule_error(profile().rules)
	if startup_error == "": startup_error = values_error(profile().values)
	if startup_error != "":
		_mounted.clear()
		return startup_error
	for key in _mounted:
		var m: Dictionary = catalog[key]
		for a in m.get("overrides", []): _archives[a.archive + "/" + a.entry.to_lower()] = m._root.path_join(a.file)
	GameData.difficulty = GameData.option("difficulty")
	return startup_error

static func override_path(archive: String, entry: String) -> String:
	return str(_archives.get(archive.to_lower() + "/" + entry.to_lower(), ""))

static func patch_database(db: RefCounted, multiplayer_db: bool) -> String:
	var pending := []
	for key in _mounted:
		for p in catalog[key].get("patches", []):
			if (p.get("database", "campaign") == "multiplayer") != multiplayer_db: continue
			var found: Dictionary = {}
			for row in db.table(p.table):
				if str(row.get("name", "")).to_lower() == p.record.to_lower(): found = row; break
			if found.is_empty() or not found.has(p.field) or not ModSchema.finite_number(found[p.field]): return "Cannot patch " + key + ": " + p.table + "/" + p.record + "/" + p.field
			if found[p.field] is int and float(p.value) != floorf(float(p.value)): return "This database field requires a whole number: " + p.field
			pending.append([found, p.field, p.value])
	for edit in pending:
		edit[0][edit[1]] = int(edit[2]) if edit[0][edit[1]] is int else float(edit[2])
	return ""

static func import_package(path: String) -> String:
	initialize()
	if session() != null: return "Return to the main menu to import mods."
	var inspected := ModZip.inspect(path, MAX_PACKAGE)
	if inspected.error != "": return inspected.error
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_PACKAGE: return "Package cannot be read or is too large."
	file.close()
	var zip := ZIPReader.new()
	if zip.open(path) != OK: return "Choose a ZIP or .eimod package containing mod.json."
	var names := zip.get_files()
	if names.size() > 4096 or "mod.json" not in names: zip.close(); return "Missing mod.json or too many package files."
	var seen := {}
	for name in names:
		if name.ends_with("/"): continue
		if not ModSchema.safe_path(name) or seen.has(name.to_lower()): zip.close(); return "Unsafe or duplicate package path."
		seen[name.to_lower()] = true
	var bytes := zip.read_file("mod.json")
	if bytes.size() != inspected.sizes["mod.json"]: zip.close(); return "Damaged manifest."
	var m: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	var error := ModSchema.manifest_error(m)
	if error != "": zip.close(); return error
	var allowed := {"mod.json": true}
	for a in m.get("overrides", []): allowed[a.file] = true
	var payload := {"mod.json": bytes}
	var total := bytes.size()
	for name in names:
		if name.ends_with("/"): continue
		if not allowed.has(name): zip.close(); return "Undeclared file: " + name
		if name == "mod.json": continue
		var data := zip.read_file(name)
		if data.size() != inspected.sizes.get(name, -1): zip.close(); return "Damaged package member."
		total += data.size()
		if data.is_empty() or data.size() > MAX_PACKAGE or total > MAX_PACKAGE: zip.close(); return "Package assets are empty or too large."
		payload[name] = data
	zip.close()
	for name in allowed:
		if not payload.has(name): return "Missing asset: " + name
	var destination := ROOT.path_join(m.id + "@" + m.version)
	if DirAccess.dir_exists_absolute(destination): return "This version is already installed. Use a new version to preserve existing saves."
	var staging := ROOT.path_join(".import-" + Crypto.new().generate_random_bytes(8).hex_encode())
	for name in payload:
		error = atomic_write(staging.path_join(name), payload[name])
		if error != "": _remove_tree(staging); return error
	if DirAccess.rename_absolute(staging, destination) != OK: _remove_tree(staging); return "Could not install the package."
	rescan()
	return ""

static func _remove_tree(path: String) -> void:
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path): _remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)

static func copy_default_save(slot: String) -> String:
	if session() != null or active_id() == "default": return "Choose a named profile from the main menu first."
	if not ModSchema.identifier(slot): return "Invalid save name."
	if startup_error != "": return startup_error
	var base := CampaignProfile.save_directory(GameData.campaign_id)
	var data: Variant = CampaignState.read_data(base.path_join(slot + ".sav"))
	if not CampaignState.compatible_data(data): return "The source save cannot be read."
	var original: Variant = data.get("mod_config", {})
	if not original is Dictionary or original.get("sandbox", false) or not original.get("packages", []).is_empty(): return "Copy only an unmodded, non-sandbox save from Current defaults."
	data.mod_config = snapshot()
	var new_slot := "copy_" + Crypto.new().generate_random_bytes(6).hex_encode()
	var destination := save_directory(base).path_join(new_slot)
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var file := FileAccess.open(destination + ".sav", FileAccess.WRITE)
	if file == null: return "Could not create the save copy."
	file.store_var(data, false)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: DirAccess.remove_absolute(destination + ".sav"); return "Could not finish the save copy."
	for extension in [".info.sav", ".shot.png"]:
		if FileAccess.file_exists(base.path_join(slot + extension)):
			DirAccess.copy_absolute(base.path_join(slot + extension), destination + extension)
	return "Save copied to this profile: " + new_slot
