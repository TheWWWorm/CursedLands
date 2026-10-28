extends Node
## Issues #107 and #108. The game speed option speeds up only the original's
## server tick; the interface keeps real time, so the animated cursor turns at
## 8 frames a second at either speed. A held Space fast-forwards the dialogue
## phrases by the keyboard's auto-repeat and stops at the last phrase.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func space(echo: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.pressed = true
	e.echo = echo
	return e

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	TutorialPanel.auto_show = false
	var session := Session.new(); add_child(session)
	var game := Game.new(); game.session = session; session.game = game; add_child(game)
	session.state.ensure_hero(0,"Human Hero")
	await session.enter_zone("gz1g",1,false)
	session.world.set_process(false); session.world.set_physics_process(false)
	session.world.vm.instances.clear()
	game.hud._dialog.hide()
	# The cursor: one frame per 0.125 s of real time on Fast.
	var fast := 55.0 / 27.0
	Engine.time_scale = fast
	check(is_equal_approx(UiTime.real(0.25 * fast), 0.25), "UiTime.real undoes the game speed")
	var cursor := game.cursor
	cursor.set_kind("cursor_use")
	var n := GameCursor.scaled("cursor_use", GameCursor.size_px()).size()
	check(n > 2, "the use cursor is animated (%d frames)" % n)
	cursor.set_process(false)
	cursor._process(0.0)
	var start := int(cursor._frame.get("cursor_use", 0))
	# Two frames of real time, as Godot's scaled deltas on Fast.
	for i in 10: cursor._process(0.025 * fast)
	check((int(cursor._frame["cursor_use"]) - start + n) % n == 2, "on Fast the cursor moves 2 frames in 0.25 s")
	Engine.time_scale = 1.0
	start = int(cursor._frame["cursor_use"])
	for i in 10: cursor._process(0.025)
	check((int(cursor._frame["cursor_use"]) - start + n) % n == 2, "on Normal the cursor moves 2 frames in 0.25 s")
	# Held Space in a briefing.
	var dialog: DialogPanel = game.hud._dialog
	var phrases: Array = []
	for i in 4: phrases.append({"speaker":"Zak", "text":"Phrase %d" % (i + 1), "n":i + 1})
	dialog.show_briefing({"id":"test", "phrases":phrases})
	check(dialog.visible and dialog._mode == DialogPanel.PLAYING and dialog._i == 0, "the briefing plays its first phrase")
	dialog._unhandled_input(space(false))
	check(dialog._i == 1, "Space advances one phrase")
	dialog._unhandled_input(space(true))
	check(dialog._i == 2, "a held Space's repeat advances the next phrase")
	for i in phrases.size() + 3: dialog._unhandled_input(space(true))
	check(dialog._i == phrases.size() - 1 and dialog.visible, "the repeat stops at the last phrase (%d/%d)" % [dialog._i, phrases.size()])
	dialog._unhandled_input(space(false))
	check(not dialog.visible or dialog._mode != DialogPanel.PLAYING, "a new press goes past the last phrase")
	game.queue_free(); session.queue_free()
	await get_tree().process_frame
	print("UI_REAL_TIME ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
