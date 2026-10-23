extends "camp_inventory_ui.gd"
## Regressions for occupied/shop art, spell availability/filter meaning and HD
## item textures. Uses actual original items and the live camp input path.
class FixtureSession extends Session:
	var extra_members: Array[GameUnit] = []
	func party_units(player: int) -> Array:
		return super.party_units(player) + (extra_members if player == my_index else [])

func click_at(point: Vector2) -> void:
	TouchInput.motion(point, Vector2.ZERO)
	for down: bool in [true, false]:
		TouchInput.button(point, down); Input.flush_buffered_events(); await frame()

func filter_click(index: int) -> void:
	await click_at(camp._r(CampView.FILTER_RECTS[index]).get_center())
	camp._process(0.0)

func material_of(view: ItemView) -> StandardMaterial3D:
	if view._model:
		for mesh: MeshInstance3D in view._model.find_children("*", "MeshInstance3D", true, false):
			var mat := mesh.get_active_material(0) as StandardMaterial3D
			if mat and mat.albedo_texture: return mat
	return null

func image_error(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size(): return INF
	var error := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x,y); var q := b.get_pixel(x,y)
			error += absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)+absf(p.a-q.a)
	return error / (4.0 * a.get_width() * a.get_height())

func hd_item_uvs() -> void:
	for id: String in ["stone axe.rock", "gipat medium helm.thin", "gipat medium plate.thin", "bp:stone axe", "tiny potion 1", "keystone:fireball", "rune:e1"]:
		var look := Items.look(id)
		var layer := look.has("layer")
		var key := "unhuma|" + String(look.layer) if layer else String(look.texture)
		var baseline: Texture2D = EIUnitModel._compose("unhuma", [String(look.layer)] as Array[String]) if layer else GameData.get_texture(key)
		check(baseline != null, "real texture exists: " + id)
		if baseline == null: continue
		var original_material: Material = EIFigure._materials.get(key)
		var expected := 256.0 / baseline.get_width()
		var reference: Image
		for factor: int in [1, 4]:
			var replacement := baseline
			if factor > 1:
				var pixels := baseline.get_image(); pixels.clear_mipmaps()
				pixels.resize(pixels.get_width() * factor, pixels.get_height() * factor, Image.INTERPOLATE_NEAREST)
				replacement = ImageTexture.create_from_image(pixels)
			if layer: EIUnitModel._textures[key] = replacement
			else:
				var source := EIFigure.material_for(key).duplicate() as StandardMaterial3D
				source.albedo_texture = replacement; EIFigure._materials[key] = source
			var view := ItemView.new(); view.camp = true; view.size = Vector2(100,100)
			add_child(view); view.show_item(id)
			var mat := material_of(view)
			check(mat != null and mat.albedo_texture.get_width() == baseline.get_width() * factor,
				"actual item renderer uses replacement resolution: %s x%d" % [id,factor])
			check(mat != null and mat.uv1_scale.is_equal_approx(Vector3(expected,expected,1)) and mat.uv1_offset.is_equal_approx(Vector3(0,1.0-expected,0)),
				"logical UV canvas survives replacement: %s x%d" % [id,factor])
			if DisplayServer.get_name() != "headless":
				await frame(); await RenderingServer.frame_post_draw
				var pixels := view._vp.get_texture().get_image()
				check(not pixels.is_invisible(), "actual item icon renders visible pixels: %s x%d" % [id,factor])
				pixels.save_png("user://hd-item-%s-%d.png" % [id.replace(":","-").replace(" ","-"),factor])
				if factor == 1: reference = pixels
				else: check(image_error(reference,pixels) < 0.06,"HD replacement preserves rendered item mapping: " + id)
			view.free()
		if layer: EIUnitModel._textures[key] = baseline
		elif original_material: EIFigure._materials[key] = original_material
		else: EIFigure._materials.erase(key)

func atlas_error(image: Image, dest: Rect2, source: String, uv: Rect2) -> float:
	var texture := camp._tex[source] as Texture2D
	var pixels := texture.get_image()
	var total := 0.0
	# Sample the centres of the logical texels, so bilinear scaling does not
	# make an adjacent bevel look like a different source sprite.
	for y in range(4, int(dest.size.y)-4, 7):
		for x in range(4, int(dest.size.x)-4, 7):
			var at := Vector2(x+0.5,y+0.5)
			var screen := camp._o() + (dest.position + at) * camp._s()
			var original := (uv.position + at / dest.size * uv.size) * Vector2(pixels.get_size()) / 256.0
			var a := image.get_pixelv(Vector2i(screen))
			var b := pixels.get_pixelv(Vector2i(original))
			total += absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
	return total / (float(range(4,int(dest.size.x)-4,7).size() * range(4,int(dest.size.y)-4,7).size()) * 3.0)

func shop_art() -> void:
	camp.set_mode("itemtrade"); camp._process(0)
	# Preserve occupied state while isolating its backing from the 3D figure.
	for view: ItemView in camp._views.values(): view.hide()
	camp._overlay.hide(); camp.set_process(false); camp.queue_redraw(); await frame()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		for y in 4:
			for x in 4:
				var texture := "trade%d" % [(1 if x < 2 else 2) + (0 if y < 2 else 2)]
				var dest := Rect2(200+x*100,100+y*100,100,100)
				var uv := Rect2(28 if x%2 == 0 else 128,28 if y%2 == 0 else 128,100,100)
				check(atlas_error(image,dest,texture,uv) < 0.035,"rendered buy/sell atlas quadrant %d,%d" % [x,y])
		for key: String in ["shop0","bag0"]:
			check(not String(camp._content[key][0]).is_empty(), "occupied backing fixture: " + key)
			check(atlas_error(image,camp._slot_rect(key).grow(-15),"campslots",Rect2(157,157,70,70)) < 0.025,
				"occupied cell renders original patterned backing: " + key)
		image.save_png("user://shop-backgrounds.png")
	camp._overlay.show(); camp._sig = ""; camp.set_process(true); camp._process(0)

func _ready() -> void: _run.call_deferred()
func _run() -> void:
	GameData.options.merge(GfxPresets.values(GfxPresets.LOW), true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,
		"display_mode":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
	TutorialPanel.auto_show = false
	await hd_item_uvs()
	session = FixtureSession.new(); add_child(session)
	game = Game.new(); game.session = session; session.game = game; add_child(game)
	session.state.ensure_hero(0,"Human Hero")
	await session.enter_zone("bz1g",1,false)
	check(session.world != null,"enter actual Gipat camp")
	if session.world == null: get_tree().quit(1); return
	session.set_physics_process(false); session.world.set_physics_process(false); session.world.vm.instances.clear()
	session.world.hide()
	var hero: GameUnit = session.party_units(0)[0]
	game.selected.assign([hero])
	var h: Dictionary = hero.get_meta("hero")
	h.int = 25; h.skills = {}; h.spells = []; h.perks = []; hero.max_mana = 1000
	var st := session.state
	st.items = ["stone axe.rock","keystone:fireball","rune:e1","spell:fireball"]
	st.money = 100000
	var goods := {}; for id: String in st.items: goods[id] = 10
	var trader := 0
	for id: int in Shops.records():
		if Shops.sells_spells(id): trader = id; break
	check(trader > 0,"original spell trader exists")
	st.shops[trader] = {"restock":false,"goods":goods,"sold":{}}
	var panel: InventoryPanel = game.hud._inventory
	panel.open(true,trader); camp = panel._camp
	await frame(); await shop_art()
	camp.set_mode("spellconstr"); camp._process(0)
	check(camp.shop_items() == ["spell:fireball"],"ready-spells filter excludes runes and keystones")
	check(camp.bag_items().has("rune:e1") and camp.bag_items().has("keystone:fireball"),"bag constructor filter retains accessible components")
	await filter_click(0)
	check(camp.shop_items() == ["keystone:fireball"],"elemental button opens actual keystone stock")
	check(not camp._spell_accepts("keystone:fireball"),"untrained party cannot construct the original fireball template")
	var key := "shop0"
	check(camp._spell_art_tint(key).g < 0.5,"unavailable shop template uses red tint")
	for slot: String in camp._content:
		if camp._content[slot] == ["keystone:fireball","bag"]:
			check(camp._spell_art_tint(slot).g < 0.5,"bag template uses the same requirement tint")
	await snapshot("spell-unavailable")
	var helper := GameUnit.new(); helper.set_process(false); helper.set_physics_process(false); add_child(helper)
	helper.set_meta("hero",{"int":25,"skills":{"elemental":100},"perks":[]})
	helper.max_mana = 1000
	(session as FixtureSession).extra_members.append(helper)
	var old_sig := camp._sig; camp._process(0)
	check(camp._sig != old_sig,"other party member's training invalidates rendered availability")
	check(camp._spell_accepts("keystone:fireball") and camp._spell_art_tint(key) == Color.WHITE,"party-wide knowledge enables the untrained hero's template")
	await snapshot("spell-available")
	await click_item("keystone:fireball","shop"); await release()
	check(camp.s_spell == "fireball","accepted keystone stages through actual camp input")
	await filter_click(3)
	check(camp.shop_items() == ["rune:e1"],"rune filter exposes actual rune stock")
	check(camp._spell_accepts("rune:e1") and camp._spell_art_tint("shop0") == Color.WHITE,"compatible rune is visibly available")
	camp.s_runes.assign(["rune:e1","rune:e1","rune:e1","rune:e1","rune:e1","rune:e1","rune:e1","rune:e1"])
	camp.s_rune_from.assign(["shop","shop","shop","shop","shop","shop","shop","shop"])
	camp._sig = ""; camp._process(0)
	check(not camp._spell_accepts("rune:e1") and camp._spell_art_tint("shop0").g < 0.5,"full constructor visibly refuses a ninth rune")
	camp._on_cancel(); await filter_click(3)
	check(not camp._spell_accepts("rune:e1") and camp._spell_art_tint("shop0").g < 0.5,"rune stays unavailable until a compatible keystone exists")
	for slot: String in ["shop0","bag0","buy0","sell0","sready","skey","srune0","top0"]:
		var art := camp._spell_art_rect(slot)
		check(art.size == Vector2(70,70) and camp._slot_rect(slot).encloses(art),"spell artwork stays inside frame: " + slot)
	var archives := {RemakeText.lang:GameData.texts}
	for arg: String in OS.get_cmdline_user_args():
		for language: String in ["en","ru","de"]:
			if arg.begins_with("--" + language + "-texts="): archives[language] = EIResArchive.open_path(arg.get_slice("=",1))
	for language: String in archives:
		GameData.texts = archives[language]; EIText.code_page = EIText.detect_code_page(GameData.texts)
		RemakeText.lang = RemakeText.detect(GameData.texts); GameData._text_cache.clear()
		check(RemakeText.lang == language,"original translation loaded: " + language)
		for mode: String in ["spelltrade","spellconstr"]:
			camp.set_mode(mode); await filter_click(5)
			var tip := camp._get_tooltip(camp._r(CampView.FILTER_RECTS[5]).get_center())
			check(not tip.is_empty() and tip == RemakeText.t("Ready spells") and (language == "en" or tip != "Ready spells"),"ready-spell button keeps localized meaning: " + language + " " + mode)
			check(camp.shop_items() == ["spell:fireball"],"ready filter has only finished spells: " + language + " " + mode)
			await snapshot("ready-spells-" + language + "-" + mode)
	(session as FixtureSession).extra_members.clear(); helper.queue_free()
	game.queue_free(); session.queue_free(); await frame()
	print("CAMP_ART_REGRESSIONS ",checks," checks ",failures," failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
