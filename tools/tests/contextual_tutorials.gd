extends Node
## Real game/HUD with installed campaign data. Context is prepared explicitly;
## this is an input and rendering regression, not a novice playthrough.
var s: Session
var g: Game
var hero: GameUnit
var hint: TutorialPanel
var checks := 0
var failures: Array[String] = []
var captures := []
var visual := false

class CueSound extends GameSound:
	var cues: Array[String] = []
	func ui(path: String) -> void: cues.append(path)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)

func frames(n := 3) -> void:
	for i in n: await get_tree().process_frame

func advance(seconds: float) -> void:
	for i in ceili(seconds / 0.1): hint._process(0.1)

func fresh() -> void:
	hint.reset_context()
	hint._quiet = 0.0
	TutorialProgress._data.clear()
	TutorialPanel._seen.clear()
	TutorialPanel.auto_show = true
	GameData.options.show_tutorial = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visual = DisplayServer.get_name() != "headless"
	TutorialPanel.persist = false
	TutorialProgress.persist = false
	GameData.options.merge({"autosave":0,"show_tutorial":1,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":0,"pad_enabled":1,"pad_wheel_pause":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0}, true)
	# The guide must cover the original localized source without bundling it.
	var count := 0
	for id in TutorialGuide.TOPICS:
		check(TutorialGuide.available(id), "topic available: " + id)
		count += TutorialGuide.pages(id).size()
		for key in [TutorialGuide.TOPICS[id].title, TutorialGuide.TOPICS[id].brief, TutorialGuide.TOPICS[id].detail]:
			check(RemakeText.TEXTS.has(key) and RemakeText.TEXTS[key].size() == 2, "EN/RU/DE: " + key)
	check(count == 78, "all 78 original pages retained")
	check(not TutorialGuide.available("lmp"), "placeholder is excluded")
	check(not TutorialGuide.available("missing_mod_tutorial"), "missing mod text never exposes an internal ID")
	GameData._text_cache["tutorial fixture_hint"] = "fixture_title\n#screen\nfixture_head\n#text\nfixture_body"
	GameData._text_cache["tutor fixture_title"] = "Installed hint"
	GameData._text_cache["tutor fixture_head"] = "Installed heading"
	GameData._text_cache["tutor fixture_body"] = "Installed reference."
	check(TutorialGuide.available("fixture_hint") and TutorialGuide.title("fixture_hint") == "Installed hint", "unknown installed tutorial remains readable")
	RenderingServer.set_render_loop_enabled(visual)
	s = Session.new(); add_child(s)
	g = Game.new(); g.session = s; s.game = g; add_child(g)
	s.state = CampaignState.new(); s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1g",1,false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false); s.world.vm.instances.clear()
	g.get_node("UnitFog").set_process(false)
	hero = s.party_units(0)[0]; hero.blocked = false
	g.selected.assign([hero]); g.rig.release()
	var h: Dictionary = hero.get_meta("hero")
	h.skills = {"astral":100,"fire":100}; h.spells = ["healing{}", "arrow{}"]
	Combat.hero_stats(hero,h); hero.mana = hero.max_mana
	await frames(8)
	g.rig.set_process(false); g.direct.set_process(false)
	hint = g.hud._tutorial; hint.set_process(false)
	fresh()
	hint.show_tutorial("zt3"); advance(0.2); await frames()
	check(hint.visible and hint.current_id == "zt3", "eligible hint appears")
	check(not get_tree().paused and not g.hud.blocks_camera(), "hint neither pauses nor blocks camera")
	check(not hint.is_in_group("pad_dismiss") and not hint.is_in_group("pad_panel"), "automatic hint does not capture controller route")
	check(hint._card.mouse_filter == Control.MOUSE_FILTER_IGNORE and hint._body.mouse_filter == Control.MOUSE_FILTER_IGNORE, "card body passes world clicks")
	check(hint._help.focus_mode == Control.FOCUS_NONE, "automatic hint never takes focus")
	check(g.hud._quest_field_top(), "quest notifications remain eligible")
	check(PadInput.field.takes_input(), "gamepad field input remains available")
	var was := hero.pos
	g.issue({"t":"move","units":[hero.uid],"x":was.x+1,"y":was.y})
	check(not hero.orders.is_empty() or not hero.order.is_empty(), "move order accepted while hint is visible")
	hero.orders.clear(); hero.order = {}
	advance(9.2)
	check(not hint.visible and hint.last_id == "zt3", "hint expires, retaining help recovery")
	hint.show_last(); advance(0.1)
	check(hint.visible and hint.expanded, "help reopens optional detail")
	advance(12)
	check(hint.visible, "explicit reading has no time limit")
	hint.close(); check(not get_tree().paused, "dismissal does not alter running clock")
	get_tree().paused = true
	hint.show_last(); hint.close()
	check(get_tree().paused, "dismissal preserves a pre-existing pause")
	get_tree().paused = false
	fresh(); hint.show_tutorial("zt1"); advance(0.4)
	hero.order_failed = false
	# A real local position change is action evidence; another player's is not.
	hero.pos += Vector2(0.8,0); advance(0.5)
	check(not hint.visible and TutorialProgress.has("zt1","acted"), "movement retires hint after local movement")
	fresh(); hint.show_tutorial("zt3"); hint.show_tutorial("zt8"); hint.show_tutorial("zt10"); advance(0.2)
	check(hint.current_id == "zt10" and TutorialProgress.has("zt3") and TutorialProgress.has("zt8"), "burst coalesces to one hint, archiving all topics")
	advance(22)
	check(not hint.visible and hint._pending == "", "no backlog slideshow")
	fresh(); g.hud._dialog.show(); hint.show_tutorial("zt11"); advance(25)
	check(not hint.visible and hint._pending == "", "stale requests expire during conversations")
	g.hud._dialog.hide()
	fresh(); GameData.options.show_tutorial = 0; hint.show_tutorial("zt11"); advance(1)
	check(not hint.visible and TutorialProgress.has("zt11"), "hints-off preference retains guide history")
	hint.show_last(); check(hint.visible and hint.expanded, "manual help works with hints off")
	fresh(); hint.show_tutorial("zt7"); advance(1)
	check(not hint.visible, "script healing trigger alone is not enough")
	var old_sound := GameSound.instance
	var cue_sound := CueSound.new()
	GameSound.instance = cue_sound
	hint._present("zt10"); hint.show_last(); hint.close()
	GameSound.instance = old_sound
	check(cue_sound.cues == [TutorialPanel.CUE_SOUND], "one automatic sound; optional reading stays silent")
	cue_sound.free()
	check(EIAudio.sfx(TutorialPanel.CUE_SOUND) != null, "tutorial cue sound exists in installed game")
	await combat_cases()
	await controller_cases()
	await guide_cases()
	await cue_cases()
	await screen_cases()
	if visual: await layout_cases()
	var result := {"checks":checks,"failures":failures,"captures":captures,"scope":"Prepared native game contexts and synthetic input; no physical controller or novice playtest."}
	var file := FileAccess.open("user://contextual-tutorials.json", FileAccess.WRITE); file.store_string(JSON.stringify(result,"  "))
	print("CONTEXTUAL_TUTORIALS ", JSON.stringify(result))
	g.queue_free(); s.queue_free(); await frames(6)
	TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)

func combat_cases() -> void:
	fresh()
	var enemy := GameUnit.new(); enemy.uid = 900001; enemy.world = s.world; enemy.faction = 1; enemy.controller = -1
	# Register an enemy with no render/model dependency for deterministic combat.
	s.world.add_child(enemy); s.world.set_unit(enemy.uid, enemy)
	var own_faction := hero.faction
	hero.faction = 0
	var old_dip = s.world.diplomacy.duplicate()
	s.world.set_relation(0, 1, 2)
	# Use the world's actual diplomacy API below if a source schema changes.
	check(s.world.is_enemy(hero,enemy), "combat fixture is hostile")
	hero.hp = hero.max_hp; hero.mana = hero.max_mana
	hero.order = {"type":"attack","target":enemy}
	hint._observer.reset(); advance(0.4)
	hero.hp = hero.max_hp * 0.65; advance(0.4)
	check(hint._context.get("combat",false) and not hint.visible, "no healing popup during combat")
	enemy.dead = true; hero.order = {}; advance(3.0)
	check(hint.visible and hint.current_id == "zt7", "victory plus newly suffered damage and usable spell triggers healing")
	check(hint.cue_rect().has_area(), "healing cue follows the real spell slot")
	hero.hp = hero.max_hp; advance(0.4)
	check(not hint.visible, "health recovery retires healing hint")
	fresh(); hero.hp = hero.max_hp * 0.6; enemy.dead = false
	hero.order = {"type":"attack", "target":enemy}; advance(0.4)
	enemy.dead = true; hero.order = {}; advance(3.0)
	check(not hint.visible and not hint._context.get("battle_damage", true), "old wounds without damage in this fight do not trigger healing")
	fresh(); hero.hp = hero.max_hp * 0.6; hero.mana = 0
	hint._observer.sample(g, 0.25); hint._observer._battle_damage[hero.uid] = true
	hint._observer._victory = true; advance(3.5)
	check(not hint.visible, "no healing instruction without stamina")
	hero.mana = hero.max_mana; var spells = hero.get_meta("hero").spells
	hero.get_meta("hero").spells = []; advance(3.5)
	check(not hint.visible, "no healing instruction without equipped healing")
	hero.get_meta("hero").spells = spells
	hero.controller = 1; advance(3.5)
	check(not hint.visible, "another player's wounds do not trigger local healing")
	hero.controller = 0; hero.faction = own_faction; hero.hp = hero.max_hp
	s.world.diplomacy = old_dip; s.world.erase_unit(enemy.uid); enemy.queue_free()
	fresh()

func cue_cases() -> void:
	for id in ["zt1", "zt4", "zt9", "zt10", "zt11", "zt12", "zt13", "zt14", "zt17", "zt18", "zt20", "zt22"]:
		hint._present(id, true); await frames(); hint._process(0.1)
		var rect := hint.cue_rect()
		check(rect.has_area() and rect.size.x < hint.size.x * 0.8 and rect.size.y < hint.size.y * 0.8, "cue bounds target the taught control " + id)
	var map_open := g.hud.minimap.open
	var log_open := g.hud.text_window.open
	var unit_open := g.hud.unit_panel.open
	g.hud.minimap.open = false; g.hud.text_window.open = false; g.hud.unit_panel.open = false
	for id in ["zt10", "zt11", "zt12"]:
		hint._present(id, true); await frames(); hint._process(0.1)
		check(hint.cue_rect().has_area() and hint.cue_rect().size.x < hint.size.x * 0.2, "closed panel cue targets its toggle " + id)
	g.hud.minimap.open = map_open; g.hud.text_window.open = log_open; g.hud.unit_panel.open = unit_open
	fresh()

func controller_cases() -> void:
	PadInput.active = "pad"
	hint.show_tutorial("zt3"); advance(0.2)
	var field: PadField = PadInput.field
	check(field.takes_input(), "pad retains gameplay while hint is shown")
	PadInput._press("mod"); PadInput._press("system")
	check(field.wheel_kind() == "system", "actual pad chord opens game wheel")
	field.close_wheel(); PadInput._release("system"); PadInput._release("mod")
	field._system("tutorial"); advance(0.1)
	check(hint.expanded and field.takes_input(), "wheel Help expands without changing field input")
	var entries := field._system_entries()
	check(entries.any(func(e): return e.id == ["sys","guide"]) and entries.any(func(e): return e.id == ["sys","hide_hint"]), "wheel offers guide and dismissal")
	field._system("hide_hint"); check(not hint.visible, "wheel dismisses hint")
	var binding = PadInput.bindings.duplicate()
	PadInput.bindings = {"RB":"system","LB":"mod","X":"interact","Y":"actions"}
	check("RB" in TutorialGuide.help_binding() and "LB+RB" in TutorialGuide.help_binding(true), "help follows pad remapping and direct-mode chord")
	check("Y" in TutorialGuide.prompt("zt7"), "healing teaches actual rebound actions wheel")
	PadInput.bindings = binding
	PadInput.active = "kbm"
	fresh()

func guide_cases() -> void:
	hint.show_tutorial("zt7"); hint.open_guide(); await frames(5)
	check(g.hud._wiki.visible and g.hud._wiki.current == "guide/zt7", "explicit guide opens matching article")
	check(get_tree().paused, "full guide uses intentional single-player menu pause")
	g.hud._wiki.navigate("guide/recent")
	check("Healing" in g.hud._wiki.html, "recent hints links to encountered topic")
	g.hud._wiki.close(); check(not get_tree().paused, "guide restores previous clock state")
	var catalog := g.hud._wiki.catalog
	check(catalog.entries.has("guide/zt1") and not catalog.entries.has("guide/zt21"), "general help available without encounter spoilers")
	TutorialProgress.encounter("zt21"); catalog.refresh_guides()
	check(catalog.entries.has("guide/zt21"), "context-specific reference unlocks on encounter")
	catalog.public_export = true
	check(not "Recent hints" in TutorialGuide.article("zt1",true), "public articles contain no private history")
	var saved := GameData.campaign_id
	GameData.campaign_id = "fixture_other_campaign"
	check(not TutorialProgress.has("zt21"), "progress is local to campaign")
	GameData.campaign_id = saved
	fresh()

func layout_cases() -> void:
	for language in ["en","ru","de"]:
		RemakeText.lang = language
		check(TutorialGuide.title("zt7") == {"en":"Healing", "ru":"Лечение", "de":"Heilung"}[language], "healing heading language " + language)
		for resolution in [Vector2i(800,600), Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1080), Vector2i(600,960)]:
			DisplayServer.window_set_size(resolution); get_window().size = resolution
			await frames(5)
			for pad in [false,true]:
				PadInput.active = "pad" if pad else "kbm"
				fresh(); hero.hp = hero.max_hp * 0.65; hero.mana = hero.max_mana
				hint._observer.sample(g, 0.25); hint._observer._battle_damage[hero.uid] = true
				hint._present("zt7"); advance(0.4); await frames(4); advance(0.1)
				check(hint.visible and hint._card.is_visible_in_tree(), "hint is rendered %s %s" % [language,resolution])
				var rect := hint._card.get_global_rect()
				check(rect.end.x <= g.hud.ui_size().x+1 and rect.end.y <= g.hud.ui_size().y+1 and rect.position.x >= 0 and rect.position.y >= 0, "hint fits %s %s pad=%s" % [language,resolution,pad])
				check(hint._body.get_visible_line_count() == hint._body.get_line_count(), "hint text not clipped %s %s" % [language,resolution])
				check(hint._heading.text == TutorialGuide.title("zt7"), "translated heading reaches card " + language)
				if resolution in [Vector2i(800,600),Vector2i(1920,1080),Vector2i(600,960)]: await capture("hint-%s-%sx%s-%s" % [language,resolution.x,resolution.y,"pad" if pad else "mouse"])
				hint.show_last(); advance(0.1); await frames(3); advance(0.1)
				check(hint._card.get_global_rect().end.y <= g.hud.ui_size().y+1, "expanded fits %s %s" % [language,resolution])
				hint.close()
				if pad:
					check(rect.end.y < resolution.y * (1.0 - 154.0/600.0), "hint clears controller strip")
	RemakeText.lang = "en"; PadInput.active = "kbm"

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "user://" + label + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	captures.append(ProjectSettings.globalize_path(path))

func screen_cases() -> void:
	GameData.options.show_tutorial = 1
	g.hud._inventory.open(true, 1)
	var camp := g.hud._inventory._camp
	var screen := camp._tutorial
	screen.set_process(false)
	for language in ["en", "ru", "de"]:
		RemakeText.lang = language
		TutorialPanel.forget("camp_item_constr")
		camp.set_mode("itemconstr")
		camp._hover_item = ""; camp._hover_desc = []
		screen._quiet = 0.0
		screen.show_tutorial("camp_item_constr")
		screen._process(0.1); await frames(); screen._process(0.1)
		check(screen.visible and not camp.tutorial_visible(), "inline shop help remains nonblocking " + language)
		check(not get_tree().paused, "inline shop hint owns no pause " + language)
		check(screen.cue_rect().has_area() and screen.cue_rect().size.x < camp.size.x * 0.2, "construction cue targets blueprint slot " + language)
		check(screen._card.get_global_rect().end.x <= camp.size.x and screen._card.get_global_rect().position.y >= 0, "shop hint fits " + language)
		if visual: await capture("shop-hint-" + language)
		screen.close(false)
	PadInput.active = "pad"
	PadInput._route["system"] = "ui"
	PadInput.ui._on_action("system", "down")
	await frames()
	check(g.hud._wiki.visible and g.hud._wiki.current == "guide/camp_item_constr", "gamepad opens contextual help from shop")
	if visual: await capture("guide-de-pad")
	check(PadInput.ui.top_panel() == g.hud._wiki and not g.hud._wiki.pad_targets().is_empty(), "guide has navigable controller targets")
	g.hud._wiki.close()
	PadInput._route.erase("system"); PadInput.active = "kbm"
	g.hud._inventory.hide()
	RemakeText.lang = "en"
	fresh()
