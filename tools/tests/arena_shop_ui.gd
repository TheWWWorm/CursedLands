extends Node
## Real pointer interaction and rendered layouts for the compact Trials HUD.
var screen: ArenaPveScreen
var checks := 0
var failures: Array[String] = []
var captured: Array[String] = []

class SoundScreen extends ArenaPveScreen:
	var cues: Array[String] = []
	func _play_cue(kind: String) -> void:
		cues.append(kind)
		super._play_cue(kind)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func _process(_dt: float) -> void:
	if is_instance_valid(screen):
		if screen.run.stage == "prepare": screen.run.preparation_left = 60
		if screen.run.stage == "result": screen._result_remaining = 4

func frames(n := 6) -> void:
	for i in n: await get_tree().process_frame

func move(at: Vector2) -> void:
	Input.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await frames(3)

func click(button: Control) -> void:
	var at := button.get_global_rect().get_center()
	await move(at)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		Input.parse_input_event(event)
		await frames(3)

func shot(label: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	var path := "user://shop-" + label + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	captured.append(path)

func inspector_fits(label: String) -> void:
	await frames(8)
	var bar := screen._inspect_scroll.get_v_scroll_bar()
	check(bar.max_value <= bar.page + 1, label + " fits without vertical scrolling (%s/%s)" % [bar.max_value, bar.page])
	check(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(screen._rail.get_global_rect()), label + " inside viewport")

func body(uid: int) -> GameUnit:
	for unit: GameUnit in screen.battle.world.unit_rows():
		if int(unit.get_meta("arena_placement", {}).get("run_uid", 0)) == uid: return unit
	return null

func _ready() -> void:
	await frames(24)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED
	await frames(8)
	var requested := Vector2i(1280, 800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-size="):
			var parts := arg.get_slice("=", 1).split(",")
			requested = Vector2i(int(parts[0]), int(parts[1]))
	get_window().size = requested
	get_window().position = DisplayServer.screen_get_usable_rect().position + Vector2i(100, 100)
	await frames(8)
	check(get_window().size == requested, "physical window size")
	screen = SoundScreen.new()
	add_child(screen)
	await frames(12)
	screen.run.auto_save = false
	screen.landing = false
	screen.run.begin(915)
	screen.run.gold = 80
	var first := screen.run._recruit(5, 0, 2)
	screen.run._recruit(5, 0, 2)
	screen.run._recruit(0, 0, 1)
	screen.run._recruit(2, 0, 1)
	screen.run._recruit(4, 0, 2)
	screen.run.training = 18
	for i in screen.run.army.size():
		if i == 1: continue
		screen.run.deploy(int(screen.run.army[i].uid), Vector2(24, 22 + i * 4))
	screen.run.shop = [{"family": 5, "rank": 0, "locked": false}, {"family": 0, "locked": false}, {"family": 2, "locked": false}, {"family": 3, "locked": false}, {"family": 4, "locked": false}, {"family": 1, "locked": false}]
	screen.run._touch()
	await frames(20)
	check(screen._train_button.get_parent() == screen._refresh_button.get_parent(), "level and reroll share shop controls")
	check(screen._level_label.text == str(screen.run.capacity()), "level is a compact number")
	check(screen._train_button.find_children("*", "ProgressBar", true, false).is_empty(), "XP has no underline or progress meter")
	check(screen._train_button.get_theme_stylebox("normal").bg_color.a > 0.5, "upgrade has persistent button surface")
	check(screen._refresh_button.get_theme_stylebox("normal").bg_color.a > 0.5, "reroll has persistent button surface")
	var card := screen._shop.get_child(0).get_child(0) as ArenaCreatureCard
	check(card.upgrade_ready and card.preview.creature.material != null, "completing copy glows")
	check(not (screen._shop.get_child(1).get_child(0) as ArenaCreatureCard).upgrade_ready, "incomplete copy does not glow")
	await shot("offers")
	await move(screen._train_button.get_global_rect().get_center())
	await move(screen._train_button.get_global_rect().get_center())
	screen._hover_inspector(0.4)
	check(screen._rail.visible and screen._showing_company, "level hover opens details")
	await inspector_fits("company")
	await shot("company")
	screen.set_process(false)
	for key in ArenaAlliances.RULES:
		screen._show_alliance(key)
		await inspector_fits("alliance " + key)
		if key == "beast": await shot("alliance")
	for family in ArenaRules.FAMILIES.size():
		screen._inspected_unit = null
		var id: String = ArenaRules.FAMILIES[family].forms[0]
		screen._inspect(id, {"family": family, "rank": 0, "offer": 0})
		await inspector_fits("creature " + id)
		if family == 5: await shot("creature")
		screen._inspect(ArenaRules.prototype(family, 2), {"family": family, "rank": 2})
		await inspector_fits("three-star " + str(family))
	screen._hide_inspector()
	screen.set_process(true)
	var xp := screen.run.experience()
	await click(screen._train_button)
	check(screen.run.experience() == xp + 5, "click level buys XP")
	for i in 6:
		var lock: Button = screen._shop.get_child(i).get_child(1)
		check(lock.icon == preload("res://assets/arena/unlock.svg"), "unlocked offer shows open padlock %d" % i)
		await click(lock)
		check(lock.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER and is_equal_approx(lock.size.x, lock.size.y), "centered square lock %d" % i)
		check(lock.icon == preload("res://assets/arena/lock.svg") and lock.get_theme_stylebox("pressed").border_color.a > 0.9, "locked offer has closed padlock and border %d" % i)
		check(lock.get_theme_stylebox("disabled").border_color.a > 0.9, "locked state remains outlined when shopping is disabled %d" % i)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			check(is_zero_approx(lock.get_theme_stylebox(state).bg_color.a), "lock has no background %d %s" % [i, state])
	check(screen.run.shop.all(func(offer): return offer.locked), "all six offers lock independently")
	var locked := screen.run.shop.duplicate(true)
	await click(screen._refresh_button)
	check(screen.run.shop == locked, "refresh preserves all six locks")
	await shot("locked")
	screen._confirm_new_run()
	await frames()
	var close: Button = screen._modal_box.get_child(0).get_child(1)
	check(close.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER, "modal close glyph centered")
	await shot("close")
	screen._close_modal()
	for wait in 200:
		if screen.battle.formation_motion.movers.is_empty(): break
		await frames(2)
	check(screen.battle.start(), "start real battle")
	await frames()
	check(screen.run.stage == "fight" and not screen._shop_panel.visible and screen._shop_toggle.visible, "battle exposes shop toggle")
	screen.battle.toggle_pause()
	var live := body(int(first.uid))
	var original_model := live.model
	var original_id: String = live.info.prototype
	var original_hp := live.hp
	var original_alliances := ArenaAlliances.counts(screen.battle.round_army)
	await click(screen._shop_toggle)
	check(screen._shop_panel.visible, "shop opens during combat")
	await click(screen._shop.get_child(0).get_child(0))
	check(screen.run.unit(int(first.uid)).rank == 1, "combat purchase auto evolves roster")
	check(live.model == original_model and live.info.prototype == original_id and live.hp == original_hp, "live fighter unchanged by roster evolution")
	check(ArenaAlliances.counts(screen.battle.round_army) == original_alliances, "current round alliances remain frozen")
	check(screen._evolution_notice.current.get("next_round", false), "deferred evolution explains next round")
	check(not screen.run.sell(int(first.uid)).is_empty(), "deployed unit cannot be sold mid combat")
	var next := screen.run.next_uid
	await click(screen._shop.get_child(1).get_child(0))
	check(not screen.run.unit(next).is_empty() and not screen.run.unit(next).deployed, "new recruit waits on bench during fight")
	screen._select(next)
	check(screen._sell_target.visible, "benched recruit exposes sell while fighting")
	await click(screen._sell_target)
	check(screen.run.unit(next).is_empty(), "bench sale commits while fighting")
	check(not screen.run.can_undo(), "battle transactions cannot be undone")
	await shot("combat-shop")
	# Freeze actual combat but exercise its real completion signal/presentation.
	screen.battle.winner = 0
	screen.battle.phase = ArenaMatch.Phase.FINISHED
	screen.battle.world.process_mode = Node.PROCESS_MODE_DISABLED
	screen.battle.finished.emit(0)
	await frames()
	check(screen._shop_panel.visible and screen._bench_panel.visible and screen._alliance_panel.visible and screen.field.show_markers, "victory preserves the HUD and markers")
	check(not screen._outcome.visible and not screen._outcome_shade.visible, "victory only uses top notification")
	await get_tree().create_timer(1.8).timeout
	var at := live.model.player.current_animation_position
	var world_time := screen.battle.world.time
	var gold := screen.run.gold
	await get_tree().create_timer(0.2).timeout
	check(not is_equal_approx(at, live.model.player.current_animation_position), "idle animation continues after settle")
	check(live.hp == original_hp and screen.battle.world.time == world_time and screen.run.gold == gold, "presentation does not advance combat or rewards")
	check(screen._clock.text == screen._result_countdown(), "round countdown is in top badge")
	await shot("victory")
	var spy := screen as SoundScreen
	check(spy.cues.count("buy") == 2 and spy.cues.count("sell") == 1 and spy.cues.count("upgrade") == 2 and spy.cues.count("win") == 1, "one original sound per successful action/result: " + str(spy.cues))
	screen._refresh(); screen._refresh()
	check(spy.cues.count("win") == 1, "refresh does not replay victory sound")
	screen.run.advance()
	await frames(10)
	check(body(int(first.uid)).info.prototype == screen.run.unit(int(first.uid)).prototype, "upgraded figure appears next round")
	# Camp cards: one whole button, native art, and no separate action row.
	screen.run.wave = 5
	screen.run.stage = "reward"
	screen.run.rewards = [{"kind": "experience"}, {"kind": "scout"}, {"kind": "purse"}]
	screen._refresh()
	await frames(20)
	var reward_row := screen._dock.get_child(2)
	for reward: ArenaRewardCard in reward_row.get_children():
		check(reward.preview.item != null and reward.preview.item._model != null, "native reward item " + String(reward.reward.kind))
		check(reward.find_children("*", "Button", true, false).is_empty(), "reward card has no redundant nested button")
	check(screen._outcome.size.y < 420, "camp reward dialog compact")
	await shot("rewards")
	gold = screen.run.gold
	await click(reward_row.get_child(2))
	check(screen.run.stage == "prepare" and screen.run.gold == gold + 8, "whole reward card selects reward")
	for cue in ArenaPveScreen.CUES.values(): check(EIAudio.sfx(cue) != null, "original sound exists " + cue)
	var f := FileAccess.open("user://shop-ui.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failures": failures, "language": RemakeText.lang, "size": str(requested), "captures": captured}))
	print("ARENA_SHOP_UI ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
