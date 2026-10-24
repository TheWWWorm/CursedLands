extends "arena_expansion_ui.gd"

class ReactionScreen extends ArenaPveScreen:
	var cues: Array[String] = []
	func _play_cue(kind: String) -> void:
		cues.append(kind)
		super._play_cue(kind)

func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	GameData.arena_mode = 1
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1600,900)
	get_window().position = Vector2i.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="): RemakeText.lang=arg.trim_prefix("--lang=")
	screen = ReactionScreen.new();add_child(screen)
	await frames(16)
	while ShaderCompilationScreen.active(): await frames(2)
	check(screen._character_picker.item_count==10,"ten native protagonist/companion choices")
	await shot("commander-"+RemakeText.lang+"-choose")
	await gallery()
	screen._character_picker.select(3);screen._character_picker.item_selected.emit(3)
	screen._seed_input.text="7191";screen._begin();screen.run.auto_save=false
	Fixture.buy_company(screen.run,1)
	await frames(18)
	while ShaderCompilationScreen.active(): await frames(2)
	check(screen.run.commander=="merc3","selected companion belongs to the run")
	var restored:=ArenaTournamentRun.new();restored.auto_save=false
	check(restored.restore(screen.run.snapshot()) and restored.commander=="merc3","commander persists through save/restore")
	bounded(screen._commander_portrait, "portrait and collarbones fit the viewport")
	check_layout()
	check(screen._commander_portrait.face != null and screen._commander_portrait._framed, "native face is lit and framed")
	await shot("commander-"+RemakeText.lang+"-board")
	for winner in [0,1,-1]:
		screen.run.last_result={"winner":winner,"wave":1}
		await frames(5)
		check(screen._commander_portrait.reaction==winner,"board expression follows its result")
		await shot("commander-"+RemakeText.lang+"-result-"+str(winner))
	await upgrade_reactions()
	for player in [1,6]:
		screen._show_player(player);await frames(12)
		check(screen._commander_portrait.commander==screen.run.company(player).commander,"scouting shows the viewed owner")
		check(screen._commander_portrait._upgrade_left == 0.0, "scouting does not replay old upgrades")
		await shot("commander-"+RemakeText.lang+"-scout-"+str(player))
	await rival_upgrade()
	screen._show_player(0)
	get_window().size = Vector2i(1280,720)
	await frames(12)
	check_layout()
	screen._select(int(screen.run.army[0].uid))
	bounded(screen._sell_target, "sell control at 720p")
	check(not screen._sell_target.get_global_rect().intersects(screen._commander_portrait.get_global_rect()), "sell control clears portrait")
	await shot("commander-"+RemakeText.lang+"-720")
	var inspected: Dictionary = screen.run.army[0]
	screen._inspected_unit = body(int(inspected.uid))
	screen._inspect(inspected.prototype, inspected)
	await move(screen._rail.get_global_rect().position + Vector2(24,24))
	await frames(4)
	bounded(screen._rail, "720p creature details")
	check(not screen._rail.get_global_rect().intersects(screen._commander_portrait.get_global_rect()), "creature details clear the enlarged bust")
	await shot("commander-"+RemakeText.lang+"-720-details")
	screen._hide_inspector(); await move(Vector2(600,400))
	screen._clear_selection()
	get_window().size = Vector2i(1600,900)
	await frames(12)
	screen.field.zoom=35;screen.field.yaw+=PI*.65;screen.field.pitch_offset=deg_to_rad(-16)
	screen.field.pan_offset=Vector2(16,-16);screen.field._update_camera()
	await shot("commander-"+RemakeText.lang+"-snow-edge")
	screen._show_boards();await frames(10)
	check(not screen._commander_portrait.visible,"overview hides the single-board portrait")
	await shot("commander-"+RemakeText.lang+"-overview")
	screen._show_player(0); await frames(4)
	await match_reactions()
	screen.queue_free();screen=null;await frames(8)
	check(errors.messages.is_empty(),"no runtime errors: "+JSON.stringify(errors.messages.slice(0,4)))
	print("ARENA_COMMANDER_UI ",checks," failures=",failures)
	OS.remove_logger(errors);TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)

func check_layout() -> void:
	var portrait := screen._commander_portrait.get_global_rect()
	check(is_equal_approx(portrait.end.y, get_viewport().get_visible_rect().end.y), "portrait reaches bottom edge")
	check(is_equal_approx(portrait.end.x, get_viewport().get_visible_rect().end.x), "portrait reaches right edge")
	check(is_equal_approx(portrait.size.y / screen._ui_scale, 200), "board bust uses two thirds of the previous size")
	check(screen._bench_scroll.get_global_rect().end.x < portrait.position.x, "shorter reserves leave room for bust")
	check(not screen._start.get_global_rect().intersects(portrait), "battle controls clear portrait")
	bounded(screen._actions_panel, "top economy and battle controls")
	check(screen._actions_panel.get_global_rect().end.x < screen._round_panel.get_global_rect().position.x, "top controls clear round status")
	check(screen._shop_panel.get_global_rect().end.x < screen._actions_panel.get_global_rect().position.x, "shop clears top controls")
	check(screen._actions_panel.position.y < 40, "economy and battle controls occupy upper free space")
	check(screen._bench_scroll.get_global_rect().end.y < screen._message.get_global_rect().position.y, "reserve strip clears the bottom hint")
	for slot: Control in screen._army_row.get_children(): bounded(slot, "reserve slot")

func upgrade_reactions() -> void:
	var portrait := screen._commander_portrait
	var entry: Dictionary = screen.run.army[0]
	var uid := int(entry.uid); var family := int(entry.family); var rank := int(entry.rank)
	screen.run.gold = 100
	for i in ArenaRules.evolution_copies(family, rank) - 1:
		screen.run.shop[0] = {"family": family, "rank": rank, "locked": false}
		screen._recruit_offer(0)
		await frames(2)
	check(int(screen.run.unit(uid).rank) > rank, "shop purchase completes a real evolution")
	check(portrait._upgrade_left > 0 and portrait.face.albedo_texture == GameData.get_texture(portrait.face_texture + "a"), "evolution smiles immediately")
	await shot("commander-"+RemakeText.lang+"-upgrade-nod")
	var head := portrait.model._head.transform
	await frames(10)
	check(not portrait.model._head.transform.is_equal_approx(head), "upgrade nod moves the full native head")
	await shot("commander-"+RemakeText.lang+"-upgrade-return")
	await frames(90)
	check(portrait._upgrade_left == 0 and portrait.face.albedo_texture == GameData.get_texture(portrait.face_texture), "upgrade expression expires without replay on refresh")
	var level := screen.run.capacity()
	while screen.run.capacity() == level: screen.run.train()
	await frames(2)
	check(portrait._upgrade_left > 0, "company level upgrade also celebrates")
	# A new result owns the expression even if an upgrade was still smiling.
	screen.run.last_result = {"winner": 1, "wave": 2}
	await frames(2)
	check(portrait._upgrade_left == 0 and portrait.reaction == 1, "battle loss replaces upgrade smile with frown")
	await shot("commander-"+RemakeText.lang+"-loss-shake")
	var motion_age := portrait._motion_age
	await frames(4)
	check(portrait._motion_age > motion_age, "repeated snapshots do not restart the head shake")

func match_reactions() -> void:
	var portrait := screen._commander_portrait
	screen.run.last_result = {"winner": 0, "wave": 2}
	await frames(60)
	screen.run.placements[0] = 1
	screen._refresh(); await frames(2)
	check(portrait.reaction == 0 and portrait._motion_age < 0.5, "match victory starts a fresh smile and nod after round victory")
	await shot("commander-"+RemakeText.lang+"-champion")
	screen.run.placements[0] = 0
	screen.run.rival_health[0] = 0
	var cues: Array[String] = screen.cues.duplicate()
	screen._refresh(); await frames(2)
	check(screen.cues == cues, "opponent elimination does not play local death sound")
	screen.run.lives = 0
	screen._refresh(); await frames(2)
	check(screen.cues == cues, "temporary zero health waits for confirmed placement before death cue")
	screen.run.lives = 0; screen.run.placements[0] = 3
	screen._refresh(); await frames(2)
	check(portrait.reaction == 1 and portrait.face.albedo_texture == GameData.get_texture(portrait.face_texture + "b"), "match elimination frowns and shakes even after a won board")
	check(screen.cues.count("lose") == cues.count("lose") + 1 and EIAudio.sfx(screen.CUES.lose) != null, "elimination plays the original hero-death cue")
	screen._refresh(); screen._round_finished(1); await frames(2)
	check(screen.cues.count("lose") == cues.count("lose") + 1, "refresh and late round result do not duplicate death cue")
	await shot("commander-"+RemakeText.lang+"-eliminated")
	screen.run.lives = 100; screen.run.placements[0] = 0; screen._refresh()
	screen._round_finished(1)
	var losses: int = screen.cues.count("lose")
	screen.run.lives = 0; screen.run.placements[0] = 3; screen._refresh()
	check(screen.cues.count("lose") == losses, "elimination arriving after the board result also avoids a duplicate death cue")

func rival_upgrade() -> void:
	screen._show_player(1); await frames(4)
	var company: ArenaRun = screen.run.company(1)
	screen.run.bot_plans[0].done = true
	var entry: Dictionary = company.army[0]
	var family := int(entry.family); var rank := int(entry.rank)
	company.gold = 100
	for i in ArenaRules.evolution_copies(family, rank) - company.copies(entry).size():
		company.shop[0] = {"family": family, "rank": rank, "locked": false}
		check(company.buy(0).is_empty(), "watched computer buys its upgrade copy")
		await frames(2)
	check(screen._commander_portrait._upgrade_left > 0, "watched computer owner smiles and nods for its evolution")

func gallery() -> void:
	var layer := CanvasLayer.new(); layer.layer = 80; add_child(layer)
	var background := ColorRect.new(); background.color = Color("18232b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); layer.add_child(background)
	var grid := GridContainer.new(); grid.columns = 5; grid.position = Vector2(160,140)
	grid.add_theme_constant_override("h_separation",16); grid.add_theme_constant_override("v_separation",20)
	layer.add_child(grid)
	var portraits: Array[ArenaCommanderPortrait] = []
	for id: String in ArenaCommanders.IDS:
		var column := VBoxContainer.new(); grid.add_child(column)
		var portrait := ArenaCommanderPortrait.new(); portrait.custom_minimum_size = Vector2(240,220)
		column.add_child(portrait); portrait.show_character(id); portraits.append(portrait)
		var title := Label.new(); title.text = ArenaCommanders.title(id); title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size",14);column.add_child(title)
	await frames(12)
	while ShaderCompilationScreen.active(): await frames(2)
	for portrait in portraits:
		check(portrait.face != null and portrait._framed, "native bust available: " + portrait.commander)
		check(GameData.get_texture(portrait.face_texture + "a") != null and GameData.get_texture(portrait.face_texture + "b") != null, "authored win and loss faces: " + portrait.commander)
		var pixels := portrait.view.get_texture().get_image()
		check(pixels.get_pixel(0,0).a == 0, "portrait has no background: " + portrait.commander)
	for result in [0,1]:
		for portrait in portraits: portrait.set_result(result)
		await shot("commander-"+RemakeText.lang+"-gallery-"+str(result))
	layer.queue_free();await frames(3)
