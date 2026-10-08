extends Node
## Optional remake directory. No built-in service or background lookup: the
## join screen refreshes the chosen URL; only an opted-in host renews a lease.

signal changed

const SETTINGS := "user://internet_directory.cfg"
const REFRESH_SECONDS := 20.0
const BODY_LIMIT := 524288
static var _settings: Dictionary = {}

var session: Node
var games: Array = []
var status := ""
var busy := false
var _http: HTTPRequest
var _publish: HTTPRequest
var _url := ""
var _id := ""
var _token := ""
var _next := 0.0
var _publishing := false


static func settings() -> Dictionary:
	if _settings.is_empty():
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		_settings = {"url": String(cfg.get_value("directory", "url", "")),
			"public": bool(cfg.get_value("directory", "public", false)),
			"address": String(cfg.get_value("directory", "address", ""))}
	return _settings.duplicate()


static func save_settings(values: Dictionary, tree: SceneTree) -> void:
	var updated := {"url": clean_url(String(values.get("url", ""))),
		"public": bool(values.get("public", false)),
		"address": String(values.get("address", "")).strip_edges().left(256)}
	if updated == settings():
		return
	_settings = updated
	var cfg := ConfigFile.new()
	for k: String in _settings:
		cfg.set_value("directory", k, _settings[k])
	cfg.save(SETTINGS)
	if tree:
		tree.call_group("internet_publishers", "reload_settings")


static func clean_url(raw: String) -> String:
	var url := raw.strip_edges().trim_suffix("/")
	if not (url.begins_with("https://") or url.begins_with("http://")) or url.length() > 256:
		return ""
	var host := url.substr(url.find("://") + 3).get_slice("/", 0)
	if host.is_empty() or url.contains("@") or url.contains("?") or url.contains("#"):
		return ""
	for c in url:
		if c.unicode_at(0) <= 32:
			return ""
	return url


static func can_join(g: Dictionary, web := false) -> bool:
	return int(g.get("protocol", 0)) == NetStatus.PROTOCOL \
		and (not web or String(g.get("address", "")).begins_with("wss://") \
			or String(g.get("address", "")).begins_with("ws://localhost:") \
			or String(g.get("address", "")).begins_with("ws://127.0.0.1:"))


static func _json(bytes: PackedByteArray) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(bytes.get_string_from_utf8()) == OK else null


static func _game(record: Variant) -> Dictionary:
	if not record is Dictionary:
		return {}
	for key: String in ["address", "name", "mode", "base", "quest"]:
		if not record.get(key, "") is String:
			return {}
	for key: String in ["players", "max", "protocol"]:
		var value: Variant = record.get(key, 0)
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 65535:
			return {}
	var addr := String(record.get("address", "")).strip_edges().left(256)
	if addr.is_empty() or addr.contains("@") or (addr.contains("://") and not (addr.begins_with("ws://") or addr.begins_with("wss://"))):
		return {}
	for c in addr:
		if c.unicode_at(0) <= 32:
			return {}
	return {"address": addr, "name": NetStatus.clean(String(record.get("name", ""))).left(24),
		"mode": "lmp" if String(record.get("mode", "")) == "lmp" else "coop",
		"base": String(record.get("base", "")).left(16), "quest": String(record.get("quest", "")).left(32),
		"players": clampi(int(record.get("players", 0)), 0, 99), "max": clampi(int(record.get("max", 0)), 0, 99),
		"pw": bool(record.get("pw", false)), "protocol": int(record.get("protocol", 0))}


func _ready() -> void:
	_http = _request_node()
	_http.request_completed.connect(_listed)
	_publish = _request_node()
	_publish.request_completed.connect(_published)
	if session:
		add_to_group("internet_publishers")
		reload_settings()


func _request_node() -> HTTPRequest:
	var h := HTTPRequest.new()
	h.timeout = 8.0
	h.body_size_limit = BODY_LIMIT
	h.max_redirects = 0
	add_child(h)
	return h


func refresh(url: String) -> Error:
	url = clean_url(url)
	_http.cancel_request()
	games.clear()
	busy = false
	if url.is_empty():
		status = RemakeText.t("Enter a directory URL first.")
		changed.emit()
		return ERR_INVALID_PARAMETER
	status = RemakeText.t("Looking for internet games…")
	busy = true
	var err := _http.request(url + "/v1/games")
	if err != OK:
		busy = false
		status = RemakeText.t("Could not reach the game directory.")
	changed.emit()
	return err


func _listed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	games.clear()
	var data: Variant = _json(body) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if not data is Dictionary or data.get("version") != 1 or not data.get("games") is Array:
		status = RemakeText.t("Could not reach the game directory.")
	else:
		for record: Variant in data.games.slice(0, 512):
			var g := _game(record)
			if not g.is_empty():
				games.append(g)
		games.sort_custom(func(a, b): return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
		status = RemakeText.t("Internet games: %d") % games.size()
	changed.emit()


func reload_settings() -> void:
	if not session:
		return
	_release()
	_publish.cancel_request()
	_publishing = false
	_url = ""
	_next = 0.0
	var cfg := settings()
	if bool(cfg.public):
		_url = clean_url(String(cfg.url))


func _release() -> void:
	if _id and _url:
		# A separate request lets the host change directory / stop listing
		# without a renewal in flight overwriting the removal. On tree exit
		# the short server lease expires even if removal cannot be delivered.
		var remove := _request_node()
		remove.request_completed.connect(func(_a, _b, _c, _d): remove.queue_free())
		var err := remove.request(_url + "/v1/games/" + _id,
			PackedStringArray(["Authorization: Bearer " + _token]), HTTPClient.METHOD_DELETE)
		if err != OK:
			remove.queue_free()
	_id = ""
	_token = ""


func _process(dt: float) -> void:
	if not session or _url.is_empty():
		return
	if not session.multiplayer_game or not session.is_host:
		_release()
		_url = ""
		return
	_next -= dt
	if _next > 0.0 or _publishing:
		return
	_next = REFRESH_SECONDS
	var info: Dictionary = session.lan_info()
	info["protocol"] = NetStatus.PROTOCOL
	info["address"] = String(settings().address)
	if _id:
		info["id"] = _id
		info["token"] = _token
	var err := _publish.request(_url + "/v1/games", PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(info))
	_publishing = err == OK
	if err != OK:
		status = RemakeText.t("Could not reach the game directory.")
		changed.emit()


func _published(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_publishing = false
	var data: Variant = _json(body) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if data is Dictionary and data.get("id") is String and data.get("token") is String \
			and RegEx.create_from_string("^[0-9a-f]{32}$").search(data.id) \
			and RegEx.create_from_string("^[0-9a-f]{64}$").search(data.token):
		_id = data.id
		_token = data.token
		status = RemakeText.t("Your game is listed on the internet.")
	else:
		if code in [403, 404]:
			_id = ""
			_token = ""
		status = RemakeText.t("Could not list your game. Check the directory and public address.")
	changed.emit()


func _exit_tree() -> void:
	if _http:
		_http.cancel_request()
	if _publish:
		_publish.cancel_request()
