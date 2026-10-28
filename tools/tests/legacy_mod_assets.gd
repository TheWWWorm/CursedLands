extends Node
## Test a deliberately selected asset-only sample from real legacy mods.
## This does not certify the original full mod. Run in disposable XDG directories
## through Main --tool, with --mod-tests, --package= and --expected=.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func finish() -> void:
	print("LEGACY_MOD_ASSETS ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(1 if failures else 0)

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
	var archives := {}
	var original_hashes := {}
	var original_assets := {}
	for asset in expected.assets:
		if not archives.has(asset.archive):
			archives[asset.archive] = EIResArchive.open_path(GameData.res_path(asset.archive))
			original_hashes[asset.archive] = FileAccess.get_sha256(GameData.res_path(asset.archive))
		original_assets[asset.archive + "/" + asset.entry] = digest(archives[asset.archive].read(asset.entry))
	var zip := ZIPReader.new()
	check(zip.open(package_path) == OK, "converted sample archive opens")
	if failures: finish(); return
	var manifest: Dictionary = JSON.parse_string(zip.read_file("mod.json").get_string_from_utf8())
	zip.close()
	check(ModSchema.manifest_error(manifest) == "", "sample meets actual API contract")
	check(ModStore.import_package(package_path) == "", "actual importer accepts sample")
	if failures: finish(); return
	check(ModStore.create_profile("Real legacy asset sample", false) == "", "create private profile")
	check(ModStore.set_packages([manifest.id + "@" + manifest.version]) == "", "select converted sample")
	check(GameData.open(GameData.root) == "" and ModStore.startup_error == "", "activate through normal data loading")
	check(PackedByteArray([0xe9, 0x97]).get_string_from_ascii() == "\u00e9\u0097", "archive byte-name decoding matches converter")
	for asset in expected.assets:
		var bytes: PackedByteArray = archives[asset.archive].read(asset.entry)
		check(digest(bytes) == asset.sha256, "resolver preserves source bytes: " + asset.entry)
		if asset.archive in ["textures.res", "menus.res"]:
			var name: String = asset.entry.trim_suffix(".mmp")
			for mipmaps in [false, true]:
				var decoded := GameData.load_image(name, mipmaps)
				check(decoded != null, "game texture decoder: " + asset.entry + " mips=" + str(mipmaps))
				if decoded:
					check(decoded.get_width() == asset.width and decoded.get_height() == asset.height,
						"authored texture dimensions: " + asset.entry)
					if mipmaps: check(decoded.has_mipmaps(), "gameplay mip chain: " + asset.entry)
		elif asset.archive == "sfx.res":
			check(EIAudio.decode_wav(bytes) != null, "game sound decoder: " + asset.entry)
	check(ModStore.select_profile("default") == "" and GameData.open(GameData.root) == "", "restore default profile")
	for asset in expected.assets:
		check(digest(archives[asset.archive].read(asset.entry)) == original_assets[asset.archive + "/" + asset.entry],
			"default asset restored: " + asset.entry)
	for name in original_hashes:
		check(FileAccess.get_sha256(GameData.res_path(name)) == original_hashes[name], "original archive untouched: " + name)
	finish()
