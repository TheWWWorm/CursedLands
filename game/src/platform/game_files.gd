class_name GameFiles
extends RefCounted
## Original data stays outside the engine package. Web reads bounded ranges
## from a local data worker, without mirroring the installation in WASM.

const WEB_ROOT := "user://browser-game"
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

static func exists(path: String) -> bool:
	return _manifest(path).has(relative(path)) if virtual_path(path) else FileAccess.file_exists(path)

static func directory_exists(path: String) -> bool:
	return not _manifest(path).is_empty() if virtual_path(path) else DirAccess.dir_exists_absolute(path)

static func files(path: String) -> PackedStringArray:
	if not virtual_path(path):
		return DirAccess.get_files_at(path)
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
	var file := FileAccess.open(path, FileAccess.READ)
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
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	file.seek(offset)
	return file.get_buffer(file.get_length() - offset if count < 0 else count)

static func text(path: String) -> String:
	return read(path).get_string_from_utf8()
