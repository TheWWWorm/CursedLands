extends Node
## Run through Main --tool in an isolated project/XDG directory, with --mod-tests,
## --package=<converted.eimod> and --expected=<fixture expectations.json>.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"):
		printerr("Use --mod-tests and disposable XDG directories.")
		get_tree().quit(2)
		return
	var package_path := ""
	var expected_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--package="): package_path = arg.trim_prefix("--package=")
		if arg.begins_with("--expected="): expected_path = arg.trim_prefix("--expected=")
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	var old_values := []
	for patch in expected.patches:
		old_values.append(GameData.db.find(patch.table, patch.record)[patch.field])
	var sound := EIResArchive.open_path(GameData.res_path("sfx.res"))
	var original_sound := sound.read(expected.sound_entry)
	var original_db_hash := FileAccess.get_sha256(GameData.res_path("database.res"))
	var zip := ZIPReader.new()
	check(zip.open(package_path) == OK, "converted archive opens")
	var manifest: Dictionary = JSON.parse_string(zip.read_file("mod.json").get_string_from_utf8())
	zip.close()
	check(ModSchema.manifest_error(manifest) == "", "manifest meets the actual API contract")
	check(ModStore.import_package(package_path) == "", "actual importer accepts converter output")
	check(ModStore.create_profile("Legacy conversion validation", false) == "", "create private profile")
	check(ModStore.set_packages([manifest.id + "@" + manifest.version]) == "", "select converted package")
	check(GameData.open(GameData.root) == "" and ModStore.startup_error == "", "mount and apply during normal data loading")
	for patch in expected.patches:
		check(is_equal_approx(float(GameData.db.find(patch.table, patch.record)[patch.field]), float(patch.value)),
			"converted " + patch.table + "/" + patch.field + " reaches the actual database")
	var bytes := sound.read(expected.sound_entry)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	check(hash.finish().hex_encode() == expected.sound_sha256, "archive resolver returns converted audio")
	check(EIAudio.decode_wav(bytes) != null, "game decoder accepts converted audio")
	check(ModStore.select_profile("default") == "" and GameData.open(GameData.root) == "", "restore the default profile")
	for i in expected.patches.size():
		var patch: Dictionary = expected.patches[i]
		check(GameData.db.find(patch.table, patch.record)[patch.field] == old_values[i], "default database value restored")
	check(sound.read(expected.sound_entry) == original_sound, "default audio restored")
	check(FileAccess.get_sha256(GameData.res_path("database.res")) == original_db_hash, "source database untouched")
	print("LEGACY_MOD_IMPORT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(1 if failures else 0)
