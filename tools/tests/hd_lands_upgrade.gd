extends Node
## Opt-in integration check with both real downloaded texture packages installed
## in a disposable profile. Run again with --upgrade-readback after process exit.
const OLD := "community.hd-lands-textures@1.4.0"
const NEW := "community.hd-lands-textures@1.5.0"
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func toggle(panel: ModPanel, version: String) -> CheckButton:
	for control in panel._controls:
		if not control is CheckButton: continue
		for sibling in control.get_parent().get_children():
			if sibling is Label and sibling.text == RemakeText.t("HD Lands textures") + "  " + version:
				return control
	return null

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0},true)
	TutorialPanel.auto_show = false
	check(ModStore.catalog.has(OLD) and ModStore.catalog.has(NEW), "both real package versions are installed")
	if failures: get_tree().quit(1); return
	if OS.get_cmdline_user_args().has("--upgrade-readback"):
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://upgrade-proof.json"))
		check(ModStore.active_id() == expected.profile, "restart keeps the existing profile")
		check(ModStore.profile().packages == [NEW], "restart loads only 1.5.0")
		check(SaveInfo.path("upgrade") == expected.save, "restart keeps the same save directory")
		check(FileAccess.get_sha256(expected.save) == expected.sha256, "restart leaves the old save bytes intact")
		var state := CampaignState.load_from(expected.save)
		check(state != null and state.money == 4321 and state.items == ["tiny potion 1"], "old campaign progress loads after restart")
		check(FileAccess.get_sha256(ModStore.catalog[OLD]._root.path_join("mod.json")) == expected.old_manifest, "1.4.0 remains installed unchanged")
	else:
		check(ModStore.create_profile("Existing HD Lands adventure",false,[OLD]).is_empty(), "create representative existing 1.4.0 profile")
		check(GameData.open(GameData.root).is_empty(), "activate old textures")
		var profile := ModStore.active_id()
		var state := CampaignState.new()
		state.ensure_hero(0,"Human Hero")
		state.current_zone = "gz1g"
		state.money = 4321
		state.items = ["tiny potion 1"]
		state.mod_config = ModStore.snapshot()
		check(state.mod_config.packages[0].version == "1.4.0", "save records old texture version")
		var path := SaveInfo.path("upgrade")
		check(state.save(path) == OK, "save existing campaign progress")
		var digest := FileAccess.get_sha256(path)
		var panel := ModPanel.new(); add_child(panel); panel.open("mods")
		var old := toggle(panel,"1.4.0")
		var newer := toggle(panel,"1.5.0")
		check(old != null and newer != null, "both versions have visible menu switches")
		if old != null and newer != null:
			check(old.button_pressed and not newer.button_pressed, "existing version starts enabled")
			old.button_pressed = false
			newer.button_pressed = true
			check(panel._save_packages().is_empty(), "normal Apply path accepts Off/On version switch")
		panel.free()
		check(ModStore.active_id() == profile and SaveInfo.path("upgrade") == path, "update keeps profile and save location")
		check(ModStore.profile().packages == [NEW], "only the new version is enabled")
		check(GameData.open(GameData.root).is_empty(), "mount the new texture version")
		check(FileAccess.get_sha256(path) == digest, "update does not rewrite the saved campaign")
		var restored := CampaignState.load_from(path)
		check(restored != null and restored.money == 4321 and restored.items == state.items, "1.4.0 campaign loads with 1.5.0 enabled")
		check(ModStore.catalog.has(OLD), "old package remains available for rollback")
		var proof := {"profile":profile,"save":path,"sha256":digest,"old_manifest":FileAccess.get_sha256(ModStore.catalog[OLD]._root.path_join("mod.json"))}
		check(proof.old_manifest.length() == 64, "old manifest has a real SHA-256")
		ModStore.atomic_write("user://upgrade-proof.json",JSON.stringify(proof).to_utf8_buffer())
	print("HD_LANDS_UPGRADE ",JSON.stringify({"checks":checks,"failures":failures,"restart":OS.get_cmdline_user_args().has("--upgrade-readback")}))
	get_tree().quit(1 if failures else 0)
