extends Node
## Opt-in real publisher download, installation, mounting and restoration.
## Run through Main --tool with --mod-tests --download-real and private XDG dirs.
var checks := 0
var failures := 0
var result := "pending"

class BackupDownload extends ModDownload:
	func _request(url: String) -> void:
		print("BACKUP_REQUEST ", url.get_slice("/", 2))
		if url == item.url:
			# Force only the preferred transport to fail; backup HTTPS is real.
			_downloaded.call_deferred(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
		else:
			super._request(url)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty(): hash.update(bytes)
	return hash.finish().hex_encode()

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--download-real"):
		get_tree().quit(2); return
	var backup := OS.get_cmdline_user_args().has("--download-backup")
	var downloader: ModDownload = BackupDownload.new() if backup else ModDownload.new()
	add_child(downloader)
	downloader.completed.connect(func(error): result = error)
	var id := "community.hd-lands-textures"
	var key := ModCatalog.key(ModCatalog.entry(id))
	var original := GameData.textures.read("basegipat000.mmp")
	var profile := ModStore.profile().duplicate(true)
	var revision := ModStore.data_revision
	var baseline := digest(original)
	check(not original.is_empty(), "baseline texture exists")
	check(downloader.start(id) == "", "start cancellation probe")
	var cancel_deadline := Time.get_ticks_msec() + 120000
	while downloader.busy and downloader.fraction == 0.0 and Time.get_ticks_msec() < cancel_deadline: await get_tree().process_frame
	check(downloader.fraction > 0.0, "real archive transfer starts before cancellation: " + downloader.status)
	downloader.cancel()
	check(not downloader.busy and result == "Download cancelled.", "cancel a real HTTPS transfer")
	check(not ModStore.catalog.has(key), "cancelled download is not installed")
	check(downloader.start(id) == "", "start original publisher HTTPS download")
	var timer := Time.get_ticks_msec()
	var frames := 0
	var last_frame := Time.get_ticks_usec()
	var max_frame_ms := 0.0
	var prior := ""
	while downloader.busy and Time.get_ticks_msec() - timer < 900000:
		frames += 1
		if downloader.status != prior:
			prior = downloader.status
			print("DOWNLOAD_PHASE ", prior)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		max_frame_ms = maxf(max_frame_ms, (now - last_frame) / 1000.0)
		last_frame = now
	check(not downloader.busy and result.is_empty(), "download and install complete: " + result)
	check(frames > 30, "UI keeps processing during download and extraction")
	check(ModStore.catalog.has(key), "installed catalog entry exists")
	check(ModStore.active_id() == "default" and ModStore.profile() == profile, "installation preserves the active profile")
	check(ModStore.data_revision == revision and digest(GameData.textures.read("basegipat000.mmp")) == baseline, "installation does not mount or change base textures")
	check(not downloader.start(id).is_empty(), "reinstall cannot replace immutable version")
	if ModStore.catalog.has(key):
		var m: Dictionary = ModStore.catalog[key]
		check(not ModSchema.gameplay(m) and not m.has("lua") and m.get("patches", []).is_empty(), "download changes presentation only")
		check(m.version == "1.5.0" and m.overrides.size() == 390, "complete HD Lands 1.5.0 texture recipe installed")
		check(downloader._fallback_used == backup, "expected preferred or backup transport was used")
		for document: String in ["readme.txt", "changelog.txt", "dev.txt", "zones_completion_stage.md"]:
			check(FileAccess.file_exists(m._root.path_join("documentation/" + document)), "original documentation preserved: " + document)
		for asset in m.overrides:
			var path: String = m._root.path_join(asset.file)
			check(FileAccess.file_exists(path), "texture present: " + asset.entry)
			var image := EIMmp.decode(FileAccess.get_file_as_bytes(path))
			check(image != null and not image.is_empty(), "texture decodes: " + asset.entry)
		check(ModStore.create_profile("Downloaded HD textures", false).is_empty(), "create separate texture profile")
		check(ModStore.set_packages([key]).is_empty() and ModStore.mount().is_empty(), "enable installed pack through normal mod system")
		check(not ModStore.override_path("textures.res", "basegipat000.mmp").is_empty(), "terrain override is mounted")
		check(digest(GameData.textures.read("basegipat000.mmp")) != baseline, "normal resource reader loads the downloaded terrain")
		var digest: String = m._digest
		ModStore.rescan()
		check(ModStore.catalog[key]._digest == digest, "installed package fingerprint survives rescan")
		check(ModStore.select_profile("default").is_empty() and ModStore.mount().is_empty(), "restore defaults")
		check(digest(GameData.textures.read("basegipat000.mmp")) == baseline, "default terrain bytes restored")
	check(Array(DirAccess.get_directories_at(ModStore.ROOT)).all(func(n): return not n.begins_with(".download-")), "temporary downloads are removed")
	print("MOD_DOWNLOADS_LIVE ", JSON.stringify({"checks": checks, "failures": failures, "frames": frames, "backup": backup, "max_installer_frame_ms": max_frame_ms, "seconds": (Time.get_ticks_msec()-timer)/1000.0}))
	get_tree().quit(1 if failures else 0)
