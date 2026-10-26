class_name ReleaseCheck
extends Node
## Read-only public release discovery. Only an explicit click opens a browser.
signal changed

enum State { IDLE, CHECKING, CURRENT, AVAILABLE, FAILED }
const API := "https://api.github.com/repos/TheWWWorm/CursedLands/releases/latest"
const RELEASES := "https://github.com/TheWWWorm/CursedLands/releases"
const CACHE := "user://release-check.cfg"
const CHECK_INTERVAL := 86400
const FAILURE_INTERVAL := 900
const BODY_LIMIT := 524288

var state := State.IDLE
var latest_tag := ""
var cache_path := CACHE
var _endpoint := API
var _request: HTTPRequest
var _last_attempt := 0
var _last_ok := false
var _retry_at := 0
var _loaded := false


static func version_parts(version: String) -> Dictionary:
	if version.length() > 128: return {}
	var pattern := RegEx.new()
	pattern.compile("^v?(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?(?:\\+[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?$")
	var match_version := pattern.search(version)
	if match_version == null or match_version.get_string() != version: return {}
	var preview := match_version.get_string(4)
	for part in preview.split("."):
		if part.is_valid_int() and part.length() > 1 and part.begins_with("0"): return {}
	return {"numbers": [match_version.get_string(1), match_version.get_string(2), match_version.get_string(3)], "preview": preview}


static func newer_stable(candidate: String, current: String) -> bool:
	var target := version_parts(candidate)
	var installed := version_parts(current)
	if target.is_empty() or installed.is_empty() or not target.preview.is_empty(): return false
	for i in 3:
		var a: String = target.numbers[i]
		var b: String = installed.numbers[i]
		# Compare decimal strings without integer overflow or lexical 1.9 > 1.10.
		if a.length() != b.length(): return a.length() > b.length()
		if a != b: return a > b
	return not installed.preview.is_empty()


func installed_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", ""))


func release_url() -> String:
	return RELEASES + "/tag/" + latest_tag.uri_encode() if state == State.AVAILABLE else RELEASES + "/latest"


func automatic() -> void:
	load_cache()
	# Tools, authority workers and editor runs never contact GitHub implicitly.
	if OS.has_feature("editor") or DisplayServer.get_name() == "headless": return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tool=") or arg.begins_with("--local-host-config=") or arg.begins_with("--autochess-host-config=") or arg == "--renderer-probe": return
	check_now(false)


func load_cache() -> void:
	if _loaded: return
	_loaded = true
	var cache := ConfigFile.new()
	if cache.load(cache_path) != OK: return
	var tag: Variant = cache.get_value("release", "tag", "")
	if tag is String and not version_parts(tag).is_empty() and version_parts(tag).preview.is_empty(): latest_tag = tag
	var attempt: Variant = cache.get_value("release", "attempt", 0)
	var retry_at: Variant = cache.get_value("release", "retry_at", 0)
	_last_attempt = attempt if attempt is int else 0
	_last_ok = cache.get_value("release", "ok", false) == true
	_retry_at = retry_at if retry_at is int else 0
	var now := int(Time.get_unix_time_from_system())
	if _last_attempt > now + 300 or _last_attempt < 0: _last_attempt = 0
	_retry_at = clampi(_retry_at, 0, now + CHECK_INTERVAL)
	_restore_state()


func _restore_state() -> void:
	state = State.AVAILABLE if newer_stable(latest_tag, installed_version()) else (State.CURRENT if _last_ok else State.IDLE)
	changed.emit()


func due(manual: bool, now: int) -> bool:
	if state == State.CHECKING or now < _retry_at: return false
	var interval := 60 if manual else (CHECK_INTERVAL if _last_ok else FAILURE_INTERVAL)
	return _last_attempt == 0 or now - _last_attempt >= interval


func check_now(manual := true) -> void:
	load_cache()
	var now := int(Time.get_unix_time_from_system())
	if not due(manual, now): return
	_last_attempt = now
	_last_ok = false
	_save_cache()
	state = State.CHECKING
	changed.emit()
	_request = HTTPRequest.new()
	_request.timeout = 8.0
	_request.body_size_limit = BODY_LIMIT
	_request.max_redirects = 0
	add_child(_request)
	_request.request_completed.connect(_completed)
	var error := _request.request(_endpoint, PackedStringArray(["Accept: application/vnd.github+json"]))
	if error != OK: _completed(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())


func _completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if _request:
		_request.queue_free()
		_request = null
	if code in [403, 429]:
		var now := int(Time.get_unix_time_from_system())
		_retry_at = now + FAILURE_INTERVAL
		for header in headers:
			var key := header.get_slice(":", 0).strip_edges().to_lower()
			var value := header.substr(header.find(":") + 1).strip_edges()
			if value.is_valid_int():
				if key == "retry-after": _retry_at = maxi(_retry_at, now + int(value))
				if key == "x-ratelimit-reset": _retry_at = maxi(_retry_at, int(value))
		_retry_at = mini(_retry_at, now + CHECK_INTERVAL)
	var data: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() <= BODY_LIMIT:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK: data = json.data
	if data is Dictionary and data.get("draft") is bool and data.get("prerelease") is bool and not data.draft and not data.prerelease:
		var tag: Variant = data.get("tag_name")
		if tag is String:
			var version := version_parts(tag)
			if not version.is_empty() and version.preview.is_empty():
				latest_tag = tag
				_last_ok = true
	_save_cache()
	_restore_state()
	if not _last_ok and state != State.AVAILABLE:
		state = State.FAILED
		changed.emit()


func _save_cache() -> void:
	var cache := ConfigFile.new()
	cache.set_value("release", "tag", latest_tag)
	cache.set_value("release", "attempt", _last_attempt)
	cache.set_value("release", "ok", _last_ok)
	cache.set_value("release", "retry_at", _retry_at)
	cache.save(cache_path)
