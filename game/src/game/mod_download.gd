class_name ModDownload
extends Node
## Download into private staging, verify the pinned source, then prepare assets
## on a worker. Only the main thread publishes a complete, immutable package.
## This code never mounts mods, changes profiles or touches original game files.
signal changed
signal completed(error: String)
var busy := false
var item: Dictionary = {}
var status := ""
var fraction := 0.0
var _http: HTTPRequest
var _thread: Thread
var _extractor: RefCounted
var _work := ""
var _cancelled := false
var _mutex := Mutex.new()
var _worker_status := ""
var _worker_fraction := 0.0
var _redirects := 0
var _last_bytes := -1
var _last_progress := 0
var _exiting := false
const IDLE_TIMEOUT := 60000

func start(id: String) -> String:
	if busy: return "A mod download is already running."
	ModStore.initialize()
	if ModStore.session() != null: return "Return to the main menu to import mods."
	var selected := ModCatalog.entry(id)
	if selected.is_empty(): return "Unknown download."
	var error := ModCatalog.unavailable(selected)
	if not error.is_empty(): return error
	if DirAccess.dir_exists_absolute(ModStore.ROOT.path_join(ModCatalog.key(selected))): return "This version is already installed. Use a new version to preserve existing saves."
	return _begin(selected)

func _begin(selected: Dictionary) -> String:
	if busy: return "A mod download is already running."
	if not ModCatalog.allowed_url(selected.url, selected.hosts): return "The download source is not allowed."
	item = selected.duplicate(true)
	_work = ModStore.ROOT.path_join(".download-" + Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.make_dir_recursive_absolute(_work) != OK: return "Could not create the mod storage folder."
	var space := DirAccess.open(_work).get_space_left()
	if space > 0 and space < int(item.get("space_bytes", int(item.bytes) * 3)):
		ModStore._remove_tree(_work)
		_work = ""
		return "Not enough free space for this download."
	_cancelled = false
	_redirects = 0
	busy = true
	status = "Downloading…"
	fraction = 0.0
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.accept_gzip = false
	_http.max_redirects = 0 # Validate every redirected host and require HTTPS.
	_http.body_size_limit = int(item.bytes)
	_http.download_chunk_size = 262144
	_http.timeout = 1800.0
	_http.download_file = _work.path_join("source.download")
	add_child(_http)
	_http.request_completed.connect(_downloaded)
	_request(item.url)
	changed.emit()
	return ""

func _request(url: String) -> void:
	_last_bytes = -1
	_last_progress = Time.get_ticks_msec()
	if _http.request(url) != OK: _finish("Could not start the download. Please try again.")

func cancel() -> void:
	if not busy: return
	_mutex.lock()
	_cancelled = true
	if _extractor != null: _extractor.call("cancel")
	_mutex.unlock()
	if _http != null:
		_http.cancel_request()
		_finish("Download cancelled.")
	else:
		status = "Cancelling…"
		if not _exiting: changed.emit()

func _stopped() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value

func _progress(text: String, value: float) -> void:
	_mutex.lock()
	_worker_status = text
	_worker_fraction = value
	_mutex.unlock()

func _process(_delta: float) -> void:
	if not busy: return
	if _http != null:
		var count := _http.get_downloaded_bytes()
		fraction = clampf(float(count) / float(item.bytes), 0.0, 1.0)
		if count != _last_bytes:
			_last_bytes = count
			_last_progress = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _last_progress > IDLE_TIMEOUT:
			_http.cancel_request()
			_finish("The download stalled. Please try again.")
			return
	elif _thread != null:
		if not _thread.is_alive():
			var result: Dictionary = _thread.wait_to_finish()
			_thread = null
			var error: String = result.get("error", "")
			if _stopped(): error = "Download cancelled."
			if error.is_empty(): error = _publish(result.manifest, result.inspected)
			_finish(error)
			return
		_mutex.lock()
		status = "Cancelling…" if _cancelled else _worker_status
		fraction = _worker_fraction
		if _extractor != null and status == "Unpacking…": fraction = float(_extractor.call("progress"))
		_mutex.unlock()
	changed.emit()

func _downloaded(result: int, code: int, headers: PackedStringArray, _body: PackedByteArray) -> void:
	if not busy: return
	if code in [301, 302, 303, 307, 308]:
		var target := ""
		for header in headers:
			if header.to_lower().begins_with("location:"): target = header.substr(9).strip_edges()
		if _redirects >= 3 or not ModCatalog.allowed_url(target, item.hosts):
			_finish("The download redirected to an unapproved source.")
			return
		_redirects += 1
		_request(target)
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish("Download failed. Please try again or visit the source page.")
		return
	_http.queue_free()
	_http = null
	status = "Verifying download…"
	fraction = 0.0
	_worker_status = status
	_worker_fraction = 0.0
	_thread = Thread.new()
	if _thread.start(_prepare) != OK:
		_thread = null
		_finish("Could not start the mod installer.")

func _verify(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != int(item.bytes): return "The download is incomplete. Please try again."
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		if _stopped(): return "Download cancelled."
		var bytes := file.get_buffer(mini(1048576, file.get_length() - file.get_position()))
		if bytes.is_empty(): return "Could not read the download."
		hash.update(bytes)
		_progress("Verifying download…", float(file.get_position()) / float(item.bytes))
	if hash.finish().hex_encode() != item.sha256: return "The download does not match the verified version. Nothing was installed."
	return ""

func _prepare() -> Dictionary:
	var result := _stage()
	if not result.get("error", "").is_empty(): return result
	if _stopped(): return {"error": "Download cancelled."}
	_progress("Verifying installed textures…", 1.0)
	result.inspected = ModStore.inspect_package(_work.path_join("package"), result.manifest, _stopped)
	result.error = result.inspected.error
	return result

func _stage() -> Dictionary:
	var path := _work.path_join("source.download")
	var error := _verify(path)
	if not error.is_empty(): return {"error": error}
	var stage := _work.path_join("package")
	if item.format == "eimod":
		_progress("Installing…", 0.0)
		return ModStore.stage_package(path, stage, _stopped)
	if item.format != "resource-7z": return {"error": "Unsupported download format."}
	var unpacked := _work.path_join("unpacked")
	if DirAccess.make_dir_recursive_absolute(unpacked) != OK: return {"error": "Could not create the extraction folder."}
	_mutex.lock()
	_extractor = ClassDB.instantiate("ModArchiveExtractor")
	if _cancelled: _extractor.call("cancel")
	_mutex.unlock()
	_progress("Unpacking…", 0.0)
	error = str(_extractor.call("extract", path, unpacked))
	_mutex.lock()
	_extractor = null
	_mutex.unlock()
	if not error.is_empty(): return {"error": error}
	DirAccess.remove_absolute(path)
	if _stopped(): return {"error": "Download cancelled."}
	return _resources(unpacked.path_join(item.folder), stage)

func _resources(source: String, stage: String) -> Dictionary:
	var manifest := {"api": 2, "id": item.id, "version": item.version, "title": item.title,
		"description": item.description, "campaigns": item.campaigns.duplicate(),
		"overrides": [], "attachments": [], "conflicts": item.get("conflicts", []).duplicate()}
	var written := {}
	var total := 0
	for definition in item.resources:
		if not ModSchema.safe_path(definition.source) or definition.archive not in ModSchema.RESOURCE_ARCHIVES: return {"error": "Invalid resource recipe."}
		# Read raw source bytes, never currently mounted resource overrides.
		var archive := EIResArchive.new()
		archive._file = FileAccess.open(source.path_join(definition.source), FileAccess.READ)
		if archive._file == null or not archive._parse(): return {"error": "Could not read the downloaded resources."}
		var names := archive.entries.keys()
		names.sort()
		for name: String in names:
			if _stopped(): return {"error": "Download cancelled."}
			var target: String = definition.archive + "/" + name
			if target in item.get("exclude", []): continue
			if not ModSchema.safe_path(name) or not ModSchema.resource_entry(definition.archive, name): return {"error": "Unsupported entry in the resource download."}
			if written.has(target): return {"error": "Conflicting entries in the resource download."}
			var entry: Vector2i = archive.entries[name]
			if entry.y <= 0 or entry.y > ModStore.MAX_PACKAGE: return {"error": "Missing or oversized downloaded asset."}
			total += entry.y
			if total > ModStore.MAX_EXTENDED_PACKAGE: return {"error": "The installed download exceeds its size limit."}
			var data := archive._read_range(entry.x, entry.y)
			if data.size() != entry.y: return {"error": "Incomplete downloaded resource."}
			var file := "assets/" + target
			var error := ModStore.atomic_write(stage.path_join(file), data)
			if not error.is_empty(): return {"error": error}
			written[target] = true
			manifest.overrides.append({"archive": definition.archive, "entry": name, "file": file})
			_progress("Installing…", float(total) / float(ModStore.MAX_EXTENDED_PACKAGE))
	for name: String in item.get("attachments", []):
		if not ModSchema.safe_path(name): return {"error": "Invalid documentation path."}
		var file := "documentation/" + name
		var input := FileAccess.open(source.path_join(name), FileAccess.READ)
		if input == null or input.get_length() > ModStore.MAX_MANIFEST: return {"error": "Missing or oversized download documentation."}
		var error := ModStore.atomic_write(stage.path_join(file), input.get_buffer(input.get_length()))
		if not error.is_empty(): return {"error": error}
		manifest.attachments.append(file)
	var error := ModSchema.manifest_error(manifest)
	if error.is_empty(): error = ModStore.atomic_write(stage.path_join("mod.json"), JSON.stringify(manifest, "\t").to_utf8_buffer())
	return {"error": error, "manifest": manifest}

func _publish(manifest: Dictionary, inspected: Dictionary = {}) -> String:
	if ModStore.session() != null: return "Return to the main menu to import mods."
	if manifest.id != item.id or manifest.version != item.version: return "The package does not match this catalog entry."
	return ModStore.publish_package(_work.path_join("package"), manifest, inspected)

func _finish(error: String) -> void:
	if _http != null:
		_http.queue_free()
		_http = null
	ModStore._remove_tree(_work)
	_work = ""
	busy = false
	status = error if not error.is_empty() else "Mod installed. Enable it in a named profile when ready."
	fraction = 1.0 if error.is_empty() else 0.0
	if not _exiting:
		changed.emit()
		completed.emit(error)

func _exit_tree() -> void:
	_exiting = true
	if busy: cancel()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	if not _work.is_empty(): ModStore._remove_tree(_work)
