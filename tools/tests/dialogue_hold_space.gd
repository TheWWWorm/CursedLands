extends Node
## Exercise keyboard repeats on the real exported dialogue panel (#108).
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func key(panel: DialogPanel, code: Key, repeated: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = repeated
	panel._unhandled_input(event)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	TutorialPanel.auto_show = false
	var session := Session.new(); add_child(session)
	var game := Game.new(); game.session = session; session.game = game; add_child(game)
	session.state.ensure_hero(0,"Human Hero")
	await session.enter_zone("gz1g",1,false)
	session.set_physics_process(false)
	session.world.set_process(false); session.world.set_physics_process(false)
	session.world.vm.instances.clear()
	# Let asynchronous material textures finish before exercising and
	# destroying the rendered scene.
	await get_tree().create_timer(2.0, true, false, true).timeout
	var panel: DialogPanel = game.hud._dialog
	panel.set_process(false)
	panel.show_briefing({"id":"hold-space-probe","phrases":[{"text":"First"},{"text":"Second"},{"text":"Last"}]})
	for i in 3: await get_tree().process_frame
	check(panel.visible and panel._i == 0 and panel._mode == DialogPanel.PLAYING, "first phrase opens")
	key(panel, KEY_ENTER, true)
	check(panel._i == 0, "repeated Enter cannot skip the conversation")
	key(panel, KEY_SPACE, true)
	check(panel._i == 1 and panel._mode == DialogPanel.PLAYING, "held Space advances one phrase")
	key(panel, KEY_SPACE, true)
	check(panel._i == 2 and panel._mode == DialogPanel.LAST, "held Space reaches the final phrase")
	for i in 12: key(panel, KEY_SPACE, true)
	check(panel.visible and panel._i == 2 and panel._mode == DialogPanel.LAST, "continued holding preserves the final phrase and rewards")
	key(panel, KEY_SPACE, false)
	check(not panel.visible and panel._mode == DialogPanel.HIDDEN, "a fresh Space press closes the final phrase")
	game.queue_free(); session.queue_free()
	for i in 6: await get_tree().process_frame
	# Release the fixture's static atlas textures before the GL server exits.
	DialogPanel._ui = null; DialogPanel._sb = null
	for i in 2: await get_tree().process_frame
	TexUpscale.shutdown()
	print("DIALOGUE_HOLD_SPACE ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
