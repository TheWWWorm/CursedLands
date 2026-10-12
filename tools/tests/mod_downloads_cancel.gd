extends Node
## Cancel real solid-archive extraction and destroy its owner while a worker is
## active. Supply --archive=<original HD Lands 1.4.0 7z> and private XDG dirs.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	var archive := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--archive="): archive = arg.trim_prefix("--archive=")
	var profile := ModStore.profile().duplicate(true)
	var revision := ModStore.data_revision
	for destroy in [false, true]:
		var owner := Node.new()
		add_child(owner)
		var d := ModDownload.new()
		owner.add_child(d)
		d.item = ModCatalog.entry("community.hd-lands-textures")
		d._work = "user://mods/.download-cancel-" + str(checks)
		DirAccess.make_dir_recursive_absolute(d._work)
		check(DirAccess.copy_absolute(archive, d._work.path_join("source.download")) == OK, "stage original archive")
		d.busy = true
		d._thread = Thread.new()
		check(d._thread.start(d._prepare) == OK, "start real extraction worker")
		var deadline := Time.get_ticks_msec() + 60000
		while d.busy and d.status != "Unpacking…" and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(d.busy and d.status == "Unpacking…", "cancel reaches the native extraction phase")
		var pending := d._work
		var began := Time.get_ticks_msec()
		if destroy:
			owner.queue_free()
			while is_instance_valid(owner): await get_tree().process_frame
		else:
			d.cancel()
			while d.busy and Time.get_ticks_msec() - began < 10000: await get_tree().process_frame
			check(not d.busy and d.status == "Download cancelled.", "worker cancellation completes")
			owner.free()
		check(Time.get_ticks_msec() - began < 10000, "cancellation/destruction joins promptly")
		check(not DirAccess.dir_exists_absolute(pending), "cancelled extraction is removed")
		check(not ModStore.catalog.has("community.hd-lands-textures@1.4.0"), "cancelled worker never publishes")
	check(ModStore.profile() == profile and ModStore.data_revision == revision, "cancellation preserves the active game configuration")
	print("MOD_DOWNLOADS_CANCEL ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
