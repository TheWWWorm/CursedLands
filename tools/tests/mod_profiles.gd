extends Node
## Run through Main --tool with --mod-tests and disposable XDG directories.
var checks := 0
var failures := 0
var details: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
		details.append(label)

func pack(m: Dictionary, extra: Dictionary = {}) -> String:
	var path := "user://fixture-" + str(checks) + ".zip"
	var zip := ZIPPacker.new()
	zip.open(path)
	zip.start_file("mod.json")
	zip.write_file(JSON.stringify(m).to_utf8_buffer())
	zip.close_file()
	for key in extra:
		zip.start_file(key)
		zip.write_file(extra[key])
		zip.close_file()
	zip.close()
	return path

func manifest(id := "example.revival") -> Dictionary:
	return {"api": 1, "id": id, "version": "1.0", "title": "Camp revival", "description": "Configurable recovery.",
		"campaigns": [GameData.campaign_id], "modes": ["single_player", "campaign_coop"],
		"options": [{"id":"seconds", "label":"Revive time", "help":"Time spent helping a fallen party member.", "type":"number", "min":1.0, "max":15.0, "step":0.5, "default":5.0, "binding":"revival.seconds"}]}

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"):
		printerr("Use disposable XDG directories and --mod-tests.")
		get_tree().quit(2)
		return
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
	TutorialPanel.auto_show = false
	await get_tree().process_frame
	check(ModStore.active_id() == "default", "fresh profile retains current defaults")
	check(SaveInfo.directory() == CampaignProfile.save_directory(GameData.campaign_id), "legacy save directory unchanged")
	check(MpCharacter.dir_path() == "user://mp/", "legacy network characters unchanged")
	var legacy := CampaignState.new()
	legacy.ensure_hero(0, "Human Hero")
	legacy.current_zone = "gz1g"
	check(legacy.save(SaveInfo.path("legacy")) == OK, "create representative legacy state")
	var original_hash := FileAccess.get_sha256(SaveInfo.path("legacy"))
	check(CampaignState.load_from(SaveInfo.path("legacy")) != null, "old save still loads")
	var m := manifest()
	check(ModSchema.manifest_error(m) == "", "valid supported capability accepted")
	var wrong := m.duplicate(true)
	wrong.options[0].binding = "arbitrary.execute"
	check(ModSchema.manifest_error(wrong) != "", "unsupported execution capability rejected")
	wrong = m.duplicate(true)
	wrong.options[0].default = 0.25
	check(ModSchema.manifest_error(wrong) != "", "out of range default rejected")
	wrong = m.duplicate(true)
	wrong.options.append(wrong.options[0].duplicate(true))
	check(ModSchema.manifest_error(wrong) != "", "duplicate option rejected")
	check(ModStore.import_package(pack(m, {"../outside.gd":"bad".to_utf8_buffer()})) != "", "archive path traversal rejected")
	check(not FileAccess.file_exists("user://outside.gd"), "no traversal file written")
	check(ModStore.import_package(pack(m, {"execute.gd":"bad".to_utf8_buffer()})) != "", "undeclared executable rejected")
	var malformed := pack(m)
	var bytes := FileAccess.get_file_as_bytes(malformed)
	for i in range(bytes.size() - 46):
		if bytes.decode_u32(i) == 0x02014b50:
			bytes.encode_u32(i + 24, ModStore.MAX_PACKAGE + 1)
			break
	ModStore.atomic_write(malformed, bytes)
	check(ModStore.import_package(malformed) != "", "oversized inflated member rejected before decompression")
	malformed = pack(m)
	bytes = FileAccess.get_file_as_bytes(malformed)
	for i in range(bytes.size() - 46):
		if bytes.decode_u32(i) == 0x02014b50:
			bytes.encode_u32(i + 38, 0xa000 << 16)
			break
	ModStore.atomic_write(malformed, bytes)
	check(ModStore.import_package(malformed) != "", "ZIP symbolic link rejected")
	check(ModStore.import_package(pack(m)) == "", "package imports")
	check(ModStore.catalog.has("example.revival@1.0"), "installed manifest is discoverable")
	check(ModStore.import_package(pack(m)) != "", "installed version cannot be overwritten")
	check(ModStore.set_packages(["example.revival@1.0"]) != "", "default profile stays unmodded")
	check(ModStore.create_profile("Recovery") == "", "create named profile")
	var profile_id := ModStore.active_id()
	check(SaveInfo.directory().ends_with("/mods/" + profile_id), "named saves have a stable namespace")
	check(MpCharacter.dir_path().ends_with("/mods/" + profile_id + "/"), "network character files use profile namespace")
	check(ModStore.set_packages(["example.revival@1.0"]) == "", "activate supported package")
	check(ModStore.mount() == "", "mount package")
	var difficulty := GameData.option("difficulty")
	check(ModStore.apply_rules({"difficulty":1-difficulty}) == "" and GameData.difficulty == 1-difficulty, "named profile updates inline simulation difficulty")
	ModStore.apply_rules({"difficulty":difficulty})
	check(ModStore.capability("revival.seconds") == 5.0, "new options get declared defaults")
	check(ModStore.apply_values({"example.revival:seconds":7.5}) == "", "validated numeric setting persists")
	check(ModStore.capability("revival.seconds") == 7.5, "effective setting reaches gameplay capability")
	check(ModStore.apply_values({"example.revival:seconds":7.2}) != "", "off-step value rejected")
	check(ModStore.apply_values({"example.revival:seconds":INF}) != "", "nonfinite value rejected")
	check(ModStore.apply_values({"unknown":2}) != "", "unknown option cannot enter a save")
	check(ModStore.capability("revival.seconds") == 7.5, "failed edits preserve old value")
	check(ModStore.mode_error("original_multiplayer") != "", "campaign-only package blocked in original multiplayer")
	var conflict := manifest("example.conflict")
	check(ModStore.import_package(pack(conflict)) == "", "second independently valid package imports")
	check(ModStore.set_packages(["example.revival@1.0","example.conflict@1.0"]) != "", "overlapping capabilities conflict")
	check(ModStore.profile().packages == ["example.revival@1.0"], "conflict preserves working profile")
	var cycle_a := manifest("example.cycle_a")
	cycle_a.options = []
	cycle_a.requires = ["example.cycle_b"]
	var cycle_b := cycle_a.duplicate(true)
	cycle_b.id = "example.cycle_b"
	cycle_b.requires = ["example.cycle_a"]
	check(ModStore.import_package(pack(cycle_a)) == "" and ModStore.import_package(pack(cycle_b)) == "", "dependency fixtures import without activation")
	check(ModStore.set_packages(["example.cycle_a@1.0"]) != "", "missing dependency rejected")
	check(ModStore.set_packages(["example.cycle_a@1.0", "example.cycle_b@1.0"]) != "", "cyclic dependencies rejected")
	check(ModSchema.digest({"a":1,"b":2.0}) == ModSchema.digest({"b":2,"a":1.0}), "signature independent of dictionary order and JSON integer conversion")
	check(ModSchema.digest({"a":0.000000001}) != ModSchema.digest({"a":0.000000002}), "small distinct database values retain distinct fingerprints")
	var signature := ModStore.progress_signature(ModStore.snapshot())
	var invalid := ModStore.snapshot()
	invalid.rules.erase("revive")
	check(ModStore.configuration_error(invalid) != "", "missing shared rule cannot fall back to client defaults")
	invalid = ModStore.snapshot()
	invalid.values.clear()
	check(ModStore.configuration_error(invalid) != "", "missing option cannot fall back to client defaults")
	invalid = ModStore.snapshot()
	invalid.rules.sandbox_mana = 1
	check(ModStore.configuration_error(invalid) != "", "ordinary save cannot hide a sandbox rule")
	ModStore.startup_error = "Fixture package could not be mounted."
	check(ModStore.saved_error(ModStore.snapshot()) != "", "a failed package mount blocks saved runs too")
	ModStore.startup_error = ""
	var first_save := CampaignState.new()
	first_save.ensure_hero(0, "Human Hero")
	first_save.current_zone = "gz1g"
	first_save.mod_config = ModStore.snapshot()
	check(first_save.save(SaveInfo.path("modded")) == OK, "mod state saves")
	check(CampaignState.load_from(SaveInfo.path("modded")).mod_config.values["example.revival:seconds"] == 7.5, "saved mod options round trip")
	check(ModStore.apply_values({"example.revival:seconds":9.0}) == "", "next-run defaults can change")
	var restored := CampaignState.load_from(SaveInfo.path("modded"))
	check(restored != null and restored.mod_config.values["example.revival:seconds"] == 7.5, "old run retains its rules when global defaults change")
	var save_path := SaveInfo.path("modded")
	check(ModStore.select_profile("default") == "" and ModStore.mount() == "", "return to default profile")
	check(CampaignState.load_from(save_path) == null, "required gameplay mod cannot be silently removed")
	check(FileAccess.get_sha256(SaveInfo.path("legacy")) == original_hash, "profile changes leave source save unchanged")
	check(ModStore.create_profile("Sandbox", true) == "", "sandbox has its own profile")
	check(ModStore.copy_default_save("legacy").begins_with("Save copied"), "explicit sandbox copy of existing campaign succeeds")
	var sandbox_files := SaveInfo.files()
	var copied := ""
	for name in sandbox_files:
		if name.ends_with(".sav"): copied = SaveInfo.directory().path_join(name)
	var copied_state := CampaignState.load_from(copied)
	check(copied_state != null and copied_state.mod_config.sandbox, "copied campaign is classified as sandbox")
	var sandbox_backup := SaveTransfer.backup()
	check(ModStore.select_profile("default") == "" and ModStore.mount() == "", "switch out of sandbox")
	var transfer := SaveTransfer.new()
	check(not transfer.restore(sandbox_backup).contains("saves imported"), "backup import cannot launder sandbox progress")
	transfer.free()
	check(CampaignState.load_from(copied) == null, "direct copied sandbox save also rejected in default profile")
	check(not MpCharacter.save_file("999.mp", {"heroes":[{}], "mod_config": copied_state.mod_config}), "network character return cannot launder sandbox metadata")
	check(ModStore.editable("sandbox_invulnerable") != "", "sandbox rules locked in ordinary runs")
	check(ModStore.select_profile(profile_id) == "" and ModStore.mount() == "", "original mod profile remains available")
	check(ModStore.apply_values({"example.revival:seconds":7.5}) == "", "restore test profile values")
	var s := Session.new()
	add_child(s)
	check(ModStore.progress_signature(s.mod_config) == signature, "session starts with selected profile rules")
	var default_xp := int(GameData.options.coop_full_xp)
	check(s.apply_mod_rules({"coop_full_xp":1-default_xp}, {}) == "", "host can change lobby rules")
	check(GameData.option("coop_full_xp") == 1-default_xp and int(GameData.options.coop_full_xp) == default_xp, "session rules override without overwriting local defaults")
	var local_difficulty := int(GameData.options.difficulty)
	check(s.apply_mod_rules({"difficulty":1-local_difficulty}, {}) == "", "lobby difficulty can change")
	GameData.save_settings()
	var preferences := ConfigFile.new()
	preferences.load(GameData.CONFIG_PATH)
	check(preferences.get_value("game", "difficulty") == local_difficulty, "saving presentation preferences cannot persist the host's difficulty")
	s.is_host = false
	check(s.apply_mod_rules({"coop_full_xp":default_xp}, {}) != "", "client authority cannot change shared settings")
	s.is_host = true
	check(s.sandbox_action("gold") != "", "ordinary host cannot run sandbox commands")
	s.free()
	check(ModStore.session() == null and GameData.option("coop_full_xp") == default_xp, "session teardown restores local defaults")
	check(GameData.difficulty == local_difficulty, "teardown restores cached difficulty")
	# Database changes validate the whole batch before writing any record.
	var database := EIDatabase.new()
	database.tables = {"monster_prototypes":[{"name":"Probe", "hp":100.0}]}
	var patch := manifest("example.balance")
	patch.options = []
	patch.patches = [{"table":"monster_prototypes", "record":"Probe", "field":"hp", "value":200.0}]
	check(ModStore.import_package(pack(patch)) == "", "numeric patch package imports")
	check(ModStore.set_packages(["example.balance@1.0"]) == "" and ModStore.mount() == "", "numeric patch resolves")
	check(ModStore.patch_database(database, false) == "" and database.tables.monster_prototypes[0].hp == 200.0, "named-record patch reaches parsed database")
	database.tables.monster_prototypes[0].hp = 100.0
	check(ModStore.patch_database(database, true) == "" and database.tables.monster_prototypes[0].hp == 100.0, "campaign patch leaves multiplayer database alone")
	ModStore.catalog["example.balance@1.0"].patches.append({"table":"monster_prototypes", "record":"Missing", "field":"hp", "value":300})
	check(ModStore.patch_database(database, false) != "" and database.tables.monster_prototypes[0].hp == 100.0, "invalid patch batch leaves every original record intact")
	var cosmetic := manifest("example.cosmetic")
	cosmetic.options = []
	cosmetic.overrides = [{"archive":"sfx.res", "entry":"mod-tests/probe.wav", "file":"audio/probe.wav"}]
	var wav := PackedByteArray()
	wav.resize(60)
	for offset in {0:"RIFF",8:"WAVE",12:"fmt ",36:"data"}:
		var word: String = {0:"RIFF",8:"WAVE",12:"fmt ",36:"data"}[offset]
		for i in 4: wav[offset+i] = word.unicode_at(i)
	wav.encode_u32(4,52); wav.encode_u32(16,16); wav.encode_u16(20,1); wav.encode_u16(22,1)
	wav.encode_u32(24,8000); wav.encode_u32(28,16000); wav.encode_u16(32,2); wav.encode_u16(34,16); wav.encode_u32(40,16)
	check(ModStore.import_package(pack(cosmetic, {"audio/probe.wav":wav})) == "", "declared asset imports")
	check(ModStore.set_packages(["example.cosmetic@1.0"]) == "" and ModStore.mount() == "", "local asset pack activates")
	var archive := EIResArchive.new()
	archive._archive_name = "sfx.res"
	check(archive.read("mod-tests/probe.wav") == wav, "archive consumer receives replacement bytes")
	var sound := EIAudio.sfx("mod-tests/probe.wav")
	check(sound != null and sound.mix_rate == 8000 and sound.data.size() == 16, "actual sound loader decodes the installed replacement")
	var with_cosmetic := ModStore.snapshot()
	var without_cosmetic := with_cosmetic.duplicate(true)
	without_cosmetic.packages = []
	check(ModStore.content_signature(with_cosmetic) == ModStore.content_signature(without_cosmetic), "cosmetic choices do not change required gameplay fingerprint")
	var corrupt := {"version":1,"profiles":{"broken":{"name":"Broken","packages":[],"values":{},"rules":{"difficulty":{}},"sandbox":false}},"selected":{GameData.campaign_id:"broken"}}
	var corrupt_bytes := JSON.stringify(corrupt).to_utf8_buffer()
	ModStore.atomic_write(ModStore.CONFIG,corrupt_bytes)
	ModStore.profiles.clear(); ModStore.selected.clear(); ModStore._loaded = false
	ModStore.initialize(); ModStore.mount()
	check(ModStore.active_id() == "default" and ModStore._config_bad, "invalid profile values recover to a usable manager")
	check(ModStore.create_profile("Recovered") == "", "new valid profile can be saved after recovery")
	var retained := false
	for filename in DirAccess.get_files_at("user://"):
		if filename.begins_with("mod_settings.json.recovery-") and FileAccess.get_file_as_bytes("user://"+filename) == corrupt_bytes: retained = true
	check(retained, "unreadable configuration is preserved before replacement")
	var result := {"checks":checks,"failures":failures,"details":details}
	ModStore.atomic_write("user://mod-profiles-result.json", JSON.stringify(result).to_utf8_buffer())
	print("MOD_PROFILES ", JSON.stringify(result))
	get_tree().quit(0 if failures == 0 else 1)
