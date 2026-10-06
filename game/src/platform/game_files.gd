class_name GameFiles
extends RefCounted
## Original data stays outside the engine package. Web reads bounded ranges
## from a local data worker, without mirroring the installation in WASM.

const WEB_ROOT := "user://browser-game"
const DATA_FOLDERS := ["res", "maps", "config", "stream", "movies", "camera"]
const CASE_CACHE_LIMIT := 1024
static var _case_cache: Dictionary = {}
static var _case_mutex := Mutex.new()
static var manifest: Dictionary = {}
static var library: Dictionary = {}
static var bridge: JavaScriptObject

static func initialize() -> void:
	if not OS.has_feature("web"):
		return
	bridge = JavaScriptBridge.get_interface("CursedFiles")
	if bridge:
		var parsed: Variant = JSON.parse_string(str(bridge.manifest_json()))
		if parsed is Dictionary:
			manifest = parsed
		var games: Variant = JSON.parse_string(str(bridge.library_json()))
		if games is Dictionary:
			library = games


static func active_root() -> String:
	var id := str(bridge.active_campaign()) if bridge else ""
	return WEB_ROOT + "-" + id if id else WEB_ROOT


static func _campaign(path: String) -> String:
	return path.trim_prefix(WEB_ROOT + "-").get_slice("/", 0) if path.begins_with(WEB_ROOT + "-") else ""


static func _manifest(path: String) -> Dictionary:
	var id := _campaign(path)
	return library.get(id, {}) if id else manifest

static func virtual_path(path: String) -> bool:
	return OS.has_feature("web") and (path == WEB_ROOT or path.begins_with(WEB_ROOT + "/") or path.begins_with(WEB_ROOT + "-"))

static func relative(path: String) -> String:
	var id := _campaign(path)
	var base := WEB_ROOT + "-" + id if id else WEB_ROOT
	return path.trim_prefix(base + "/").replace("\\", "/").to_lower()


## Windows installations are case-insensitive. Resolve their physical names
## without renaming source files; browser manifests are already canonical.
## Positive paths are bounded and guarded because archive/movie/hash readers
## also run on workers. Validation retires the mapping before a new import.
static func clear_path_cache() -> void:
	_case_mutex.lock()
	_case_cache.clear()
	_case_mutex.unlock()


static func resolve(path: String) -> String:
	if path.is_empty() or virtual_path(path):
		return path
	_case_mutex.lock()
	var cached: String = _case_cache.get(path, "")
	_case_mutex.unlock()
	if not cached.is_empty() and (FileAccess.file_exists(cached) or DirAccess.dir_exists_absolute(cached)):
		return cached
	var found := _resolve(path, 0)
	_case_mutex.lock()
	_case_cache.erase(path)
	if not found.is_empty():
		if _case_cache.size() >= CASE_CACHE_LIMIT:
			_case_cache.erase(_case_cache.keys()[0])
		_case_cache[path] = found
	_case_mutex.unlock()
	return found


static func _resolve(path: String, depth: int) -> String:
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		return path
	if depth >= 64:
		return ""
	var parent := path.get_base_dir()
	if parent == path:
		return ""
	if parent.is_empty():
		parent = "."
	var actual := _resolve(parent, depth + 1)
	var directory := DirAccess.open(actual) if not actual.is_empty() else null
	if directory == null:
		return ""
	var wanted := path.get_file().to_lower()
	var found := ""
	var names := directory.get_files()
	names.append_array(directory.get_directories())
	for name: String in names:
		if name.to_lower() == wanted:
			if not found.is_empty():
				return ""   # a missing exact path must never guess between aliases
			found = name
	return actual.path_join(found) if not found.is_empty() else ""


## Refuse conflicting spellings even when a lowercase exact path exists.
## Only the game's six data trees are considered; other install files stay
## untouched. Bounds also stop cyclic/deep directory links safely.
static func case_error(path: String) -> String:
	if virtual_path(path):
		return ""
	var root := resolve(path)
	var pending: Array[Dictionary] = [{"path": root, "rel": "", "depth": 0}]
	var count := 0
	while not pending.is_empty():
		var row: Dictionary = pending.pop_back()
		var directory := DirAccess.open(String(row.path))
		if directory == null or int(row.depth) > 64:
			return RemakeText.t("Could not inspect game-data folder: %s") % String(row.rel)
		directory.include_hidden = true
		var names := directory.get_files()
		var folders := directory.get_directories()
		names.append_array(folders)
		var spellings := {}
		for name: String in names:
			var key := name.to_lower()
			if int(row.depth) == 0 and key not in DATA_FOLDERS:
				continue
			count += 1
			if count > 20000:
				return RemakeText.t("Could not inspect game-data folder: %s") % String(row.rel)
			if spellings.has(key):
				return RemakeText.t("Ambiguous game-data names: %s") % String(row.rel).path_join(key)
			spellings[key] = name
		for name: String in folders:
			if int(row.depth) == 0 and name.to_lower() not in DATA_FOLDERS:
				continue
			pending.append({"path": String(row.path).path_join(name), "rel": String(row.rel).path_join(name), "depth": int(row.depth) + 1})
	return ""

static func exists(path: String) -> bool:
	return _manifest(path).has(relative(path)) if virtual_path(path) else FileAccess.file_exists(resolve(path))

static func directory_exists(path: String) -> bool:
	return not _manifest(path).is_empty() if virtual_path(path) else DirAccess.dir_exists_absolute(resolve(path))

static func files(path: String) -> PackedStringArray:
	if not virtual_path(path):
		var actual := resolve(path)
		return DirAccess.get_files_at(actual) if not actual.is_empty() else PackedStringArray()
	var prefix := relative(path).trim_suffix("/") + "/"
	var result := PackedStringArray()
	for key: String in _manifest(path):
		if key.begins_with(prefix) and not key.substr(prefix.length()).contains("/"):
			result.append(key.substr(prefix.length()))
	result.sort()
	return result

static func length(path: String) -> int:
	if virtual_path(path):
		return int(_manifest(path).get(relative(path), {}).get("size", 0))
	var actual := resolve(path)
	var file := FileAccess.open(actual, FileAccess.READ) if not actual.is_empty() else null
	return file.get_length() if file else 0

static func read(path: String, offset := 0, count := -1) -> PackedByteArray:
	if virtual_path(path):
		var total := length(path)
		if count < 0:
			count = total - offset
		if bridge == null or offset < 0 or count < 0 or offset + count > total:
			return PackedByteArray()
		var buffer: Variant = bridge.read(relative(path), offset, count, _campaign(path))
		if buffer == null:
			push_error("Local browser data unavailable: " + path)
			return PackedByteArray()
		return JavaScriptBridge.js_buffer_to_packed_byte_array(buffer)
	var actual := resolve(path)
	var file := FileAccess.open(actual, FileAccess.READ) if not actual.is_empty() else null
	if file == null:
		return PackedByteArray()
	file.seek(offset)
	return file.get_buffer(file.get_length() - offset if count < 0 else count)

static func text(path: String) -> String:
	return read(path).get_string_from_utf8()
