extends "mod_profiles.gd"
## Clothing/weapon overlays through the real package reader and character
## material composer. Run only with --mod-tests and a disposable profile.
var observations := {}
var previews: Array[Paperdoll] = []
var proof: SubViewport

func pnt3(size: int, color: Color, transparent_top := false) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(76 + size * size * 4)
	data.encode_u32(0, EIMmp.MAGIC)
	data.encode_u32(4, size); data.encode_u32(8, size)
	data.encode_u32(12, size * size * 4)
	data.encode_u32(16, 0x33544e50)
	var pixel := color.b8 | (color.g8 << 8) | (color.r8 << 16) | (color.a8 << 24)
	for i in size * size:
		# PNT3 zero-alpha words encode the number of transparent bytes.
		data.encode_u32(76 + i * 4, 4 if transparent_top and i < size * size / 2 else pixel)
	return data

func image_digest(texture: Texture2D) -> String:
	if texture == null: return ""
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(texture.get_image().get_data())
	return hash.finish().hex_encode()

func preview(record: Dictionary) -> Paperdoll:
	if proof == null:
		proof = SubViewport.new(); proof.size = Vector2i(960, 500)
		proof.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(proof)
		var background := ColorRect.new(); background.size = Vector2(960, 500)
		background.color = Color(0.09, 0.11, 0.14); proof.add_child(background)
	var label := Label.new(); label.text = ["Original", "Texture mod enabled", "Original restored"][previews.size()]
	label.position = Vector2(15 + previews.size() * 310, 8)
	label.size = Vector2(300, 30); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	proof.add_child(label)
	var doll := Paperdoll.new()
	doll.view_size = Vector2i(300, 450)
	doll.position = Vector2(15 + previews.size() * 310, 40)
	doll.size = Vector2(300, 450)
	proof.add_child(doll); doll.show_info(record); previews.append(doll)
	return doll

func finish() -> void:
	if DisplayServer.get_name() != "headless" and not previews.is_empty():
		for i in 15: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		proof.get_texture().get_image().save_png("user://mod-redress-profiles.png")
	for doll in previews: doll.queue_free()
	await get_tree().process_frame
	var result := {"checks":checks, "failures":failures, "details":details, "observations":observations}
	ModStore.atomic_write("user://mod-redress.json", JSON.stringify(result, "\t").to_utf8_buffer())
	print("MOD_REDRESS ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown(); get_tree().quit(int(failures > 0))

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"show_tutorial":0}, true)
	TutorialPanel.auto_show = false
	if DisplayServer.get_name() != "headless":
		GameData._window_gen += 1; get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(960, 500)
		RenderingServer.set_render_loop_enabled(true)
	var proto := GameData.db.find("monster_prototypes", "Human Hero")
	var race := GameData.db.find("race_models", proto.base_race)
	var mask := String(race.mask).to_lower()
	var skin := "skin_%02d" % int(proto.get("skin", 0))
	var entry := mask + skin + ".mmp"
	var weapon := "unhufeax_01.gr.0.mmp"
	check(GameData.redress.has(entry) and GameData.redress.has(weapon), "original hero skin and reported weapon entry exist")
	observations.merge({"campaign":GameData.campaign_id,"skin":entry,"weapon":weapon})
	var m := manifest("redress.fixture")
	m.api = 2; m.options = []
	m.overrides = [
		{"archive":"redress.res","entry":entry,"file":"assets/skin.mmp"},
		{"archive":"redress.res","entry":weapon,"file":"assets/weapon.mmp"},
		{"archive":"redress.res","entry":mask+"redress-test.mmp","file":"assets/overlay.mmp"},
		{"archive":"textures.res","entry":"redress-fallback.mmp","file":"assets/fallback.mmp"}]
	for api in [1, 2, 3]:
		var valid := m.duplicate(true); valid.api = api
		if api == 3:
			valid.translations = {"ru":{"title":"Проверка текстур","description":"Тест замены текстур."},"de":{"title":"Texturprüfung","description":"Test für Texturersatz."}}
		check(ModSchema.manifest_error(valid).is_empty(), "redress MMP accepted by package API %d" % api)
	# A baseline build exits here with actual validation failures.
	if failures: await finish(); return
	for archive in ["redress.res", "textures.res", "menus.res"]:
		var invalid := m.duplicate(true)
		invalid.overrides = [{"archive":archive,"entry":"probe.wav","file":"assets/probe.wav"}]
		for lang in ["en", "ru", "de"]:
			RemakeText.lang = lang
			var error := ModSchema.manifest_error(invalid)
			check(not error.is_empty() and (lang == "en" or error != "Texture overrides must be MMP files."), "non-MMP rejected with translated message: " + archive + "/" + lang)
			observations["error_"+lang] = error
	RemakeText.lang = "en"
	for archive in ["figures.res", "database.res"]:
		var invalid := m.duplicate(true); invalid.overrides[0].archive = archive
		check(not ModSchema.manifest_error(invalid).is_empty(), "unrelated archive still rejected: " + archive)
	var original_hash := FileAccess.get_sha256(GameData.res_path("redress.res"))
	var original_skin := GameData.redress.read(entry)
	var original_weapon := GameData.redress.read(weapon)
	var layers: Array[String] = [skin]
	var original := EIUnitModel._compose(mask, layers)
	var original_pixels := image_digest(original)
	check(not original_pixels.is_empty(), "original character texture composes")
	var record := {"prototype":"Human Hero","armors":[],"weapons":[]}
	if DisplayServer.get_name() != "headless": preview(record)
	var red := Color8(210, 25, 45, 255)
	var blue := Color8(20, 45, 220, 255)
	var assets := {"assets/skin.mmp":pnt3(512, red),"assets/weapon.mmp":pnt3(64, blue),
		"assets/overlay.mmp":pnt3(512, blue, true),"assets/fallback.mmp":pnt3(32, Color.GREEN)}
	check(ModStore.import_package(pack(m, assets)).is_empty(), "mixed clothing/world texture package imports")
	check(ModStore.create_profile("Clothing texture test").is_empty(), "create isolated texture profile")
	check(ModStore.set_packages(["redress.fixture@1.0"]).is_empty(), "select imported clothing package")
	# This is the same-process restart boundary used by web/Android.
	DataSwitch.clear_caches()
	check(GameData.open(GameData.root).is_empty() and ModStore.startup_error.is_empty(), "normal game loading mounts the clothing profile")
	check(GameData.redress.read(entry) == assets["assets/skin.mmp"], "ordinary redress reader returns replacement")
	check(GameData.redress.read(weapon.to_upper()) == assets["assets/weapon.mmp"], "reported weapon entry resolves case-insensitively")
	check(GameData.redress.read_original(entry) == original_skin, "original entry remains independently readable")
	check(GameData.redress.has(mask+"redress-test.mmp") and mask+"redress-test.mmp" in GameData.redress.names_with_suffix(".mmp"), "new clothing layer is enumerated")
	check(not GameData.textures.has(mask+"redress-test.mmp"), "clothing override does not leak into another archive")
	var composed := EIUnitModel._compose(mask, layers)
	check(composed != null and composed.get_width() == 512 and composed.get_image().has_mipmaps(), "high-resolution PNT3 skin reaches composed material with mipmaps")
	if composed:
		check(composed.get_image().get_pixel(0,0).is_equal_approx(red), "composed skin contains replacement pixels")
		composed.get_image().save_png("user://mod-redress-skin.png")
	var clothes := EIUnitModel._compose(mask, [skin,"redress-test"] as Array[String])
	check(clothes != null and clothes.get_image().get_pixel(0,0).is_equal_approx(red) and clothes.get_image().get_pixel(0,511).is_equal_approx(blue), "transparent clothing preserves underlying skin and blends opaque pixels")
	var fallback := EIUnitModel._load_layer(mask, "redress-fallback")
	check(fallback != null and fallback.get_pixel(0,0).is_equal_approx(Color.GREEN), "missing redress entry retains ordinary texture fallback")
	var held := EIUnitModel._compose("unhufe", ["ax_01.gr.0"] as Array[String])
	check(held != null and held.get_image().get_pixel(0,0).is_equal_approx(blue), "reported weapon uses the replacement through the material composer")
	var model := EIUnitModel.create(record, true, false)
	check(model != null, "actual character model is constructed")
	if model:
		var used := false
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var material := mesh.get_active_material(0)
			if material != null and material.get("albedo_texture") == composed: used = true
		check(used, "actual character mesh is bound to replacement texture")
		model.free()
	if DisplayServer.get_name() != "headless": preview(record)
	var snapshot := ModStore.snapshot()
	var plain := snapshot.duplicate(true); plain.packages = []
	check(not ModSchema.gameplay(m) and ModStore.content_signature(snapshot) == ModStore.content_signature(plain), "clothing texture choices remain cosmetic for co-op")
	check(ModStore.configuration_error(plain).is_empty(), "unmodded peer configuration remains compatible")
	var conflict := m.duplicate(true); conflict.id = "redress.conflict"
	conflict.overrides = [{"archive":"redress.res","entry":entry.trim_suffix(".mmp").to_upper()+".mmp","file":"assets/skin.mmp"}]
	check(ModStore.import_package(pack(conflict, {"assets/skin.mmp":assets["assets/skin.mmp"]})).is_empty(), "second texture package imports independently")
	check(not ModStore.set_packages(["redress.fixture@1.0","redress.conflict@1.0"]).is_empty(), "overlapping clothing replacements are rejected case-insensitively")
	check(ModStore.profile().packages == ["redress.fixture@1.0"], "rejected conflict leaves selected profile intact")
	check(ModStore.select_profile("default").is_empty(), "disable clothing package")
	DataSwitch.clear_caches()
	check(GameData.open(GameData.root).is_empty(), "reload unmodded data")
	check(GameData.redress.read(entry) == original_skin and GameData.redress.read(weapon) == original_weapon, "original skin and weapon restored")
	check(image_digest(EIUnitModel._compose(mask, layers)) == original_pixels, "same-process restart discards cached modded appearance")
	check(not GameData.redress.has(mask+"redress-test.mmp") and mask+"redress-test.mmp" not in GameData.redress.names_with_suffix(".mmp"), "disabled package removes its extra layer")
	check(ModStore.configuration_error(snapshot).is_empty(), "unmodded profile accepts cosmetic peer configuration")
	check(FileAccess.get_sha256(GameData.res_path("redress.res")) == original_hash, "source redress archive is unchanged")
	if DisplayServer.get_name() != "headless": preview(record)
	await finish()
