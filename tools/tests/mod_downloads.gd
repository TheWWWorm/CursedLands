extends Node
## Deterministic download failure, staging and native extraction checks.
## Use a private runtime/XDG profile, --mod-tests and --fixture=<7z fixtures>.
var checks := 0
var failures := 0

class RecordedDownload extends ModDownload:
	var requests: Array[String] = []
	func _request(url: String) -> void:
		requests.append(url)
		_last_progress = Time.get_ticks_msec()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func package() -> String:
	var path := "user://fixture.eimod"
	var zip := ZIPPacker.new()
	zip.open(path)
	zip.start_file("mod.json")
	zip.write_file(JSON.stringify({"api": 1, "id": "download.test", "version": "1", "title": "Download test", "campaigns": ["cursed_lands"]}).to_utf8_buffer())
	zip.close_file(); zip.close()
	return path

func prepare_job(d: ModDownload, path: String) -> void:
	d.item = {"id": "download.test", "version": "1", "format": "eimod", "bytes": FileAccess.open(path, FileAccess.READ).get_length(), "sha256": FileAccess.get_sha256(path)}
	d._source = d.item
	d._work = "user://mods/.download-test-" + str(checks)
	DirAccess.make_dir_recursive_absolute(d._work)
	DirAccess.copy_absolute(path, d._work.path_join("source.download"))
	d.busy = true
	d._cancelled = false

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	var fixtures := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="): fixtures = arg.trim_prefix("--fixture=")
	check(ClassDB.class_exists("ModArchiveExtractor"), "native installer present")
	if failures: get_tree().quit(1); return
	for name: String in ["valid", "traversal", "case", "reserved", "symlink", "invalid"]:
		var extractor: RefCounted = ClassDB.instantiate("ModArchiveExtractor")
		var destination := "user://extract-" + name
		DirAccess.make_dir_recursive_absolute(destination)
		var error: String = extractor.call("extract", fixtures.path_join(name + ".7z"), destination)
		check(error.is_empty() == (name == "valid"), "native archive case: " + name + " " + error)
		if name == "valid":
			check(FileAccess.get_file_as_string(destination.path_join("pack/текст.txt")) == "download fixture\n", "Unicode filename and payload preserved")
		else:
			check(DirAccess.get_files_at(destination).is_empty() and DirAccess.get_directories_at(destination).is_empty(), "invalid archive never writes: " + name)
		ModStore._remove_tree(destination)
	check(not FileAccess.file_exists("user://escaped.txt"), "archive cannot escape staging")
	var extractor: RefCounted = ClassDB.instantiate("ModArchiveExtractor")
	extractor.call("cancel")
	DirAccess.make_dir_recursive_absolute("user://extract-cancel")
	check(not str(extractor.call("extract", fixtures.path_join("valid.7z"), "user://extract-cancel")).is_empty(), "native extraction honours pre-start cancellation")
	var hosts := ["hd-lands.gipat.ru"]
	for url in ["http://hd-lands.gipat.ru/a", "https://hd-lands.gipat.ru.evil/a", "https://evil@hd-lands.gipat.ru/a", "file:///tmp/a", "https://hd-lands.gipat.ru/a#b"]:
		check(not ModCatalog.allowed_url(url, hosts), "reject source: " + url)
	check(ModCatalog.allowed_url("https://hd-lands.gipat.ru/a", hosts), "allow reviewed HTTPS host")
	var reviewed := ModCatalog.entry("community.hd-lands-textures")
	for url in ["https://storage.yandex.net/a", "https://s1.storage.yandex.net.evil/a", "https://evilstorage.yandex.net/a", "https://user@s1.storage.yandex.net/a", "https://s1.storage.yandex.net:443/a", "http://s1.storage.yandex.net/a"]:
		check(not ModCatalog.allowed_url(url, reviewed.fallback.hosts), "reject backup source: " + url)
	check(ModCatalog.allowed_url("https://s384klg.storage.yandex.net/a", reviewed.fallback.hosts), "allow rotating Yandex storage node")
	check(not ModCatalog.allowed_url("https://evil.invalid?host=s1.storage.yandex.net", reviewed.fallback.hosts), "query text cannot impersonate a backup host")
	check(not ModCatalog.allowed_url("https://s1%2F.storage.yandex.net/a", reviewed.fallback.hosts), "encoded authority is rejected")
	var transfer := RecordedDownload.new()
	add_child(transfer)
	check(transfer.start(reviewed.id).is_empty() and transfer.requests == [reviewed.url], "public download action accepts the supported platform")
	transfer.cancel()
	transfer.requests.clear()
	var campaign := GameData.campaign_id
	GameData.campaign_id = "lost_in_astral"
	check(transfer.start(reviewed.id) == "This download is for Cursed Lands." and not transfer.busy and transfer.requests.is_empty(), "unsupported campaign cannot start a download")
	GameData.campaign_id = campaign
	check(transfer._begin(reviewed).is_empty() and transfer.requests == [reviewed.url], "Gipat is requested first")
	check(not transfer._resolving and transfer._http.download_file.ends_with("source.download"), "primary download streams to disk")
	ModStore.atomic_write(transfer._work.path_join("source.download"), "partial primary".to_utf8_buffer())
	var retired_request := transfer._http
	transfer._downloaded(HTTPRequest.RESULT_SUCCESS, 503, [], PackedByteArray())
	check(transfer.busy and transfer.requests == [reviewed.url, reviewed.fallback.url], "primary HTTP failure starts the Yandex resolver")
	retired_request.request_completed.emit(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	check(transfer.busy and transfer.requests.size() == 2, "retired primary completion cannot fail its backup")
	check(not FileAccess.file_exists(transfer._work.path_join("source.download")), "fallback removes partial primary bytes")
	check(transfer._resolving and transfer._http.download_file.is_empty() and transfer._http.body_size_limit == ModDownload.MAX_LINK_RESPONSE, "resolver response stays bounded in memory")
	var resolved := "https://downloader.disk.yandex.ru/disk/test"
	transfer._downloaded(HTTPRequest.RESULT_SUCCESS, 200, [], JSON.stringify({"href": resolved, "method": "GET", "templated": false}).to_utf8_buffer())
	check(transfer.requests.back() == resolved and not transfer._resolving, "resolver follows the HTTPS download link")
	check(transfer._http.body_size_limit == reviewed.bytes and transfer._http.download_file.ends_with("source.download"), "resolved archive streams with the pinned size limit")
	transfer._downloaded(HTTPRequest.RESULT_SUCCESS, 302, ["Location: https://s384klg.storage.yandex.net/file"], PackedByteArray())
	check(transfer.requests.back() == "https://s384klg.storage.yandex.net/file", "backup follows a reviewed storage redirect")
	transfer._downloaded(HTTPRequest.RESULT_SUCCESS, 503, [], PackedByteArray())
	check(not transfer.busy and transfer.requests.size() == 4, "backup failure terminates without looping")
	transfer.requests.clear()
	transfer._begin(reviewed)
	ModStore.atomic_write(transfer._work.path_join("source.download"), "invalid primary".to_utf8_buffer())
	transfer._http.queue_free(); transfer._http = null
	transfer._thread = Thread.new()
	check(transfer._thread.start(transfer._prepare) == OK, "verify invalid primary on the real worker")
	while transfer._thread != null: await get_tree().process_frame
	check(transfer._resolving and transfer._fallback_used, "worker verification failure retries from the backup")
	transfer.cancel()
	check(not transfer.busy and transfer.requests.size() == 2, "cancelling the resolver does not restart the download")
	transfer.requests.clear()
	transfer._begin(reviewed)
	transfer.cancel()
	check(transfer.requests == [reviewed.url], "cancelling the primary never starts the backup")
	transfer.requests.clear()
	transfer._begin(reviewed)
	transfer._last_bytes = transfer._http.get_downloaded_bytes()
	transfer._last_progress = Time.get_ticks_msec() - ModDownload.IDLE_TIMEOUT - 1
	transfer._process(0.0)
	check(transfer._fallback_used and transfer._resolving, "stalled primary transfer tries the backup")
	transfer.cancel()
	for body: String in ["invalid", "[]", '{"href":12}', '{"href":"http://downloader.disk.yandex.ru/a","method":"GET","templated":false}', '{"href":"https://evil.invalid/a","method":"GET","templated":false}', '{"href":"https://downloader.disk.yandex.ru/a","method":"POST","templated":false}', '{"href":"https://downloader.disk.yandex.ru/a","method":"GET","templated":true}', " ".repeat(ModDownload.MAX_LINK_RESPONSE + 1)]:
		transfer.requests.clear()
		transfer._begin(reviewed)
		transfer._downloaded(HTTPRequest.RESULT_CANT_CONNECT, 0, [], PackedByteArray())
		transfer._downloaded(HTTPRequest.RESULT_SUCCESS, 200, [], body.to_utf8_buffer())
		check(not transfer.busy and transfer.requests.size() == 2, "invalid resolver response never starts an archive request")
	transfer.free()
	var d := ModDownload.new()
	add_child(d)
	var profile := ModStore.profile().duplicate(true)
	var revision := ModStore.data_revision
	check(not d.start("not.in.catalog").is_empty() and not d.busy, "unknown download does not start network")
	var p := package()
	prepare_job(d, p)
	d.item.sha256 = "0".repeat(64)
	var result := d._prepare()
	check(result.error.contains("verified version"), "same-size corrupted download fails checksum")
	check(not DirAccess.dir_exists_absolute(d._work.path_join("package")), "checksum rejection happens before extraction")
	d._finish(result.error)
	prepare_job(d, p)
	d.item.bytes += 1
	check(d._prepare().error.contains("incomplete"), "truncated download rejected")
	d._finish("test cleanup")
	prepare_job(d, p)
	d._cancelled = true
	check(d._prepare().error == "Download cancelled.", "cancel before verification")
	d._finish("test cleanup")
	prepare_job(d, p)
	result = d._prepare()
	check(result.error.is_empty() and FileAccess.file_exists(d._work.path_join("package/mod.json")), "native package staging succeeds")
	check(not ModStore.catalog.has("download.test@1"), "staging does not publish the package")
	check(ModStore.profile() == profile and ModStore.data_revision == revision, "preparation leaves profile and mounted state untouched")
	d.item.id = "wrong.identity"
	check(not d._publish(result.manifest).is_empty(), "catalog/package identity mismatch rejected")
	d.item.id = "download.test"
	check(d._publish(result.manifest).is_empty() and ModStore.catalog.has("download.test@1"), "verified package publishes into normal catalog")
	check(not d._publish(result.manifest).is_empty(), "immutable version cannot be overwritten")
	d._finish("")
	var stage := "user://mods/.stage-cancel"
	ModStore._remove_tree(ModStore.ROOT.path_join("download.test@1")); ModStore.rescan()
	check(ModStore.stage_package(p, stage, func(): return true).error == "Download cancelled.", "package extraction supports cancellation")
	check(not DirAccess.dir_exists_absolute(stage), "cancelled package extraction cleans staging")
	for code in [404, 500]:
		prepare_job(d, p)
		d._downloaded(HTTPRequest.RESULT_SUCCESS, code, [], PackedByteArray())
		check(not d.busy and d.status.begins_with("Download failed"), "HTTP failure " + str(code))
	prepare_job(d, p)
	d.item.hosts = hosts
	d._downloaded(HTTPRequest.RESULT_SUCCESS, 302, ["Location: https://elsewhere.invalid/mod.zip"], PackedByteArray())
	check(not d.busy and d.status.contains("unapproved"), "redirect cannot leave approved HTTPS sources")
	# Exercise the actual worker completion path (no server needed for fixtures).
	prepare_job(d, p)
	d._thread = Thread.new()
	check(d._thread.start(d._prepare) == OK, "start package worker")
	while d.busy: await get_tree().process_frame
	check(ModStore.catalog.has("download.test@1"), "worker completion publishes verified package")
	check(ModStore.profile() == profile and ModStore.data_revision == revision, "all install paths leave gameplay state unchanged")
	check(Array(DirAccess.get_directories_at(ModStore.ROOT)).all(func(n): return not n.begins_with(".download-")), "all terminal paths remove temporary downloads")
	# Destroying a UI owner must cancel/clean without callbacks into a dying UI.
	prepare_job(d, p)
	d._http = HTTPRequest.new()
	d.add_child(d._http)
	var callbacks := [0]
	d.completed.connect(func(_error): callbacks[0] += 1)
	var pending := d._work
	d.free()
	check(callbacks[0] == 0 and not DirAccess.dir_exists_absolute(pending), "owner destruction cleans download without UI callbacks")
	print("MOD_DOWNLOADS ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(1 if failures else 0)
