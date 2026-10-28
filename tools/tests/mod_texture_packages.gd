extends "mod_profiles.gd"
## The release accepts only the texture/documentation subset of package API 2.

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	var m := manifest("texture.release")
	m.api = 2
	m.options = []
	m.overrides = [{"archive":"textures.res", "entry":"release-test.mmp", "file":"assets/test.mmp"}]
	m.attachments = ["documentation/readme.txt", "documentation/empty.txt"]
	check(ModSchema.manifest_error(m).is_empty(), "texture API 2 manifest accepted")
	var invalid := m.duplicate(true)
	for api in [0, 1.5, 3, 4, true, "2"]:
		invalid.api = api
		check(not ModSchema.manifest_error(invalid).is_empty(), "unsupported API rejected: " + str(api))
	for archive in ["figures.res", "database.res", "sfx.res"]:
		invalid = m.duplicate(true)
		invalid.overrides[0].archive = archive
		check(not ModSchema.manifest_error(invalid).is_empty(), "broader resource capability remains unavailable: " + archive)
	# menus.res signpost textures are texture-pack content; its models and menus.reg are not.
	invalid = m.duplicate(true)
	invalid.overrides[0].archive = "menus.res"
	check(ModSchema.manifest_error(invalid).is_empty(), "menus.res signpost texture accepted")
	for entry in ["menus.reg", "probe.mod", "probe.anm"]:
		invalid.overrides[0].entry = entry
		check(not ModSchema.manifest_error(invalid).is_empty(), "menus.res non-texture entry rejected: " + entry)
	for field in ["lua", "files", "force_script_tutorials", "skip_start_animation"]:
		invalid = m.duplicate(true)
		invalid[field] = []
		check(not ModSchema.manifest_error(invalid).is_empty(), "legacy capability is never silently accepted: " + field)
	invalid = m.duplicate(true)
	invalid.options = manifest().options
	check(not ModSchema.manifest_error(invalid).is_empty(), "API 2 cannot add gameplay options")
	invalid = m.duplicate(true)
	invalid.patches = [{"table":"perks", "record":"probe", "field":"cost", "value":1}]
	check(not ModSchema.manifest_error(invalid).is_empty(), "API 2 cannot add balance patches")
	for name in ["../readme.txt", "readme.exe", "readme.lua", "optional.zip"]:
		invalid = m.duplicate(true); invalid.attachments = [name]
		check(not ModSchema.manifest_error(invalid).is_empty(), "unsupported attachment rejected: " + name)
	var texture := GameData.textures.read("goblin00.mmp")
	var data := {"assets/test.mmp":texture, "documentation/readme.txt":"Original author credits".to_utf8_buffer(), "documentation/empty.txt":PackedByteArray()}
	var path := pack(m, data)
	check(ModStore.import_package(path).is_empty(), "textures and documentation import together")
	var installed: Dictionary = ModStore.catalog.get("texture.release@1.0", {})
	check(not installed.is_empty(), "API 2 appears in the installed catalogue")
	if installed.is_empty(): get_tree().quit(1); return
	check(FileAccess.get_file_as_string(installed._root.path_join(m.attachments[0])) == "Original author credits", "author credits preserved")
	check(not ModSchema.gameplay(installed), "texture package has no gameplay requirements")
	var fingerprint: String = installed._digest
	ModStore.rescan()
	check(ModStore.catalog["texture.release@1.0"]._digest == fingerprint, "package fingerprint stable after rescan")
	check(ModStore.create_profile("Texture release probe").is_empty(), "create texture profile")
	check(ModStore.set_packages(["texture.release@1.0"]).is_empty() and ModStore.mount().is_empty(), "activate texture profile")
	check(GameData.textures.read("release-test.mmp") == texture, "ordinary reader sees mounted texture")
	check("release-test.mmp" in GameData.textures.names_with_suffix(".mmp"), "new texture is included in resource enumeration")
	check(GameData.load_image("release-test") != null, "ordinary image decoder reads new texture")
	var snapshot := ModStore.snapshot()
	var plain := snapshot.duplicate(true); plain.packages = []
	check(ModStore.content_signature(snapshot) == ModStore.content_signature(plain), "HD and original textures share a gameplay signature")
	check(ModStore.configuration_error(plain).is_empty(), "unmodded peer configuration is compatible")
	check(ModStore.select_profile("default").is_empty() and ModStore.mount().is_empty(), "return to default profile")
	check(not GameData.textures.has("release-test.mmp") and "release-test.mmp" not in GameData.textures.names_with_suffix(".mmp"), "deactivation removes extra texture names")
	check(ModStore.configuration_error(snapshot).is_empty(), "texture peer configuration accepted without its local texture pack")
	# Inspect forged directory lengths without allocating oversized buffers.
	var bytes := FileAccess.get_file_as_bytes(path)
	for i in range(bytes.size() - 46):
		if bytes.decode_u32(i) == 0x02014b50 and bytes.decode_u32(i + 24) == texture.size():
			bytes.encode_u32(i + 24, ModStore.MAX_PACKAGE + 1)
			break
	check(ModStore.atomic_write("user://oversized-texture.zip", bytes).is_empty(), "write oversized member fixture")
	check(not ModZip.inspect("user://oversized-texture.zip", ModStore.MAX_EXTENDED_PACKAGE).error.is_empty(), "larger package allowance retains per-asset allocation bound")
	check(not ModStore.import_package("user://oversized-texture.zip").is_empty(), "oversized member fails import before inflation")
	var original := manifest("texture.api1")
	check(ModSchema.manifest_error(original).is_empty(), "existing API 1 gameplay contract remains accepted")
	original.attachments = ["readme.txt"]
	check(not ModSchema.manifest_error(original).is_empty(), "API 1 documentation contract remains unchanged")
	check(ModStore.package_limit(1) == 134217728 and ModStore.package_limit(2) == 1073741824, "only API 2 gains the larger total allowance")
	print("MOD_TEXTURE_PACKAGES ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
