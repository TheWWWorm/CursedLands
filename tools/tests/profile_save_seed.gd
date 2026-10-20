extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func _ready() -> void:
	var base := SaveInfo.directory()
	var state := CampaignState.new()
	state.ensure_hero(0, "Human Hero")
	state.current_zone = "gz1g"
	state.money = 4321
	state.save(SaveInfo.path("quick"))
	SaveInfo.write("quick", 15.5, "gipat", "gz1g", "Original adventure")
	var shot := Image.create(16,16,false,Image.FORMAT_RGB8)
	shot.fill(Color.RED)
	SaveInfo.write_shot_image("quick", shot)
	var hashes := {}
	for ext in ["sav", "info.sav", "shot.png"]: hashes[ext] = FileAccess.get_sha256(SaveInfo.path("quick", ext))
	var bad := FileAccess.open(SaveInfo.path("broken"), FileAccess.WRITE)
	bad.store_var({"version":999}); bad.close()
	var wrong := state.to_dict(); wrong.campaign = "other"
	# A valid save from another campaign must never appear in the new profile.
	wrong.campaign_id = CampaignProfile.ASTRAL if GameData.campaign_id == CampaignProfile.ORIGINAL else CampaignProfile.ORIGINAL
	var file := FileAccess.open(SaveInfo.path("other"), FileAccess.WRITE)
	file.store_var(wrong); file.close()
	check(ModStore.create_profile("Copied story", true).is_empty(), "new sandbox profile created")
	ModStore.mount()
	var id := ModStore.active_id()
	check(FileAccess.file_exists(SaveInfo.path("quick")), "base quicksave copied automatically")
	var copied := CampaignState.load_from(SaveInfo.path("quick"))
	check(copied != null and copied.money == 4321, "copied adventure loads with its progress")
	check(copied != null and copied.mod_config.profile == id and copied.mod_config.sandbox, "copy uses new profile and sandbox classification")
	check(not FileAccess.file_exists(SaveInfo.path("broken")), "malformed save skipped")
	check(not FileAccess.file_exists(SaveInfo.path("other")), "other campaign skipped")
	for ext in ["info.sav", "shot.png"]:
		check(FileAccess.get_sha256(SaveInfo.path("quick", ext)) == hashes[ext], "copied sidecar unchanged: " + ext)
	copied.money = 9999; copied.save(SaveInfo.path("quick"))
	ModStore.select_profile("default"); ModStore.mount()
	for ext in hashes:
		check(FileAccess.get_sha256(SaveInfo.path("quick", ext)) == hashes[ext], "source untouched: " + ext)
	ModStore.select_profile(id); ModStore.mount()
	check(CampaignState.load_from(SaveInfo.path("quick")).money == 9999, "profile switching preserves later progress")
	ModStore.select_profile("default"); ModStore.mount()
	# Read-only destination/config failures must not select a partial profile.
	var config_path := ProjectSettings.globalize_path(ModStore.CONFIG + ".pending")
	DirAccess.make_dir_absolute(config_path)
	var previous := ModStore.profiles.size()
	check(not ModStore.create_profile("Cannot commit").is_empty(), "config write failure reported")
	check(ModStore.active_id() == "default" and ModStore.profiles.size() == previous, "failed profile leaves selection intact")
	check(DirAccess.get_directories_at(base.path_join("mods")).size() == 1, "failed creation removes only its new save folder")
	DirAccess.remove_absolute(config_path)
	print("PROFILE_SAVE_SEED ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
