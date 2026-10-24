extends Node
## Issue #105: the Options, Load and Save boards opened from the in-game Esc
## menu (GameHUD) must not show their previous opening's settled picture
## before the slide's first pose has rendered. Unlike board_slide_frames this
## goes through the HUD: the Esc signpost hides as a board opens, and
## closing a board closes the menu, so it is reopened with Esc again.
var checks := 0
var failures := 0
var delayed_viewport := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func draws(count: int) -> void:
	for i in count: await RenderingServer.frame_post_draw

## The highest row with board ink in the central columns (-1: none). The
## Esc frame behind the boards is black, so only the boards count.
func top_row(img: Image) -> int:
	for y in range(0, img.get_height(), 2):
		var n := 0
		for x in range(img.get_width() * 3 / 8, img.get_width() * 5 / 8, 4):
			var c := img.get_pixel(x, y)
			if c.r > 0.25 and c.g > 0.18: n += 1
		if n >= 6: return y
	return -1

## The top 60% of `a` matches `b`'s: the settled board and its heading.
func same_picture(a: Image, b: Image) -> bool:
	var lit := 0
	var differ := 0
	for y in range(0, a.get_height() * 3 / 5, 4):
		for x in range(0, a.get_width(), 4):
			var cb := b.get_pixel(x, y)
			if cb.r + cb.g + cb.b < 0.3: continue
			lit += 1
			var ca := a.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.15: differ += 1
	return lit > 200 and differ < lit / 10

func opening(hud: GameHUD, action: String, id: String, panel: Control, close: Callable, flip: bool) -> void:
	hud._on_esc_board(action)
	await get_tree().create_timer(1.0, true, false, true).timeout
	await draws(4)
	var shot := get_viewport().get_texture().get_image()
	if OS.get_environment("ESC_BOARD_SHOTS") != "":
		shot.save_png(OS.get_environment("ESC_BOARD_SHOTS") + "/%s-rest.png" % id.replace(" ", "-"))
	var rest := top_row(shot)
	check(rest >= 0, id + ": settled board is rendered")
	close.call()
	await get_tree().create_timer(0.5, true, false, true).timeout
	await draws(4)
	check(not panel.visible, id + ": the board closes")
	# Esc again, then the same board: its viewport still holds the settled
	# picture of the opening above.
	menu(hud)
	await draws(2)
	hud._on_esc_board(action)
	if flip:
		# An ancestor hidden and shown again in the same frame (the HUD layer's
		# sync_visibility, a relayout): its notifications reach the board too.
		hud.visible = false
		hud.visible = true
	# Simulate an old texture surviving more than the two draw notifications
	# used by the earlier reveal barrier. Screen-space movement must be safe
	# regardless of when this particular viewport gets its next render.
	var board: InterfaceBoard = panel._board if action == "options" else panel._boards[action == "save"]
	if delayed_viewport: board._vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var tops: Array = []
	var stale := -1
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 300000:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if OS.get_environment("ESC_BOARD_SHOTS") != "" and tops.size() < 4:
			img.save_png(OS.get_environment("ESC_BOARD_SHOTS") + "/%s-open%d.png" % [id.replace(" ", "-"), tops.size()])
		tops.append(top_row(img))
		if stale < 0 and same_picture(img, shot): stale = tops.size() - 1
	if delayed_viewport: board._vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	var h := get_viewport().get_visible_rect().size.y
	var first := -1
	for t: int in tops:
		if t >= 0: first = t; break
	print(id, " rest=", rest, " tops=", tops)
	check(stale < 0, id + ": no frame repeats the settled picture (frame %d)" % stale)
	check(first < 0 or first > rest + h * 0.1, id + ": no settled board flashes before the slide (first top %d, rest %d)" % [first, rest])
	close.call()
	await get_tree().create_timer(0.5, true, false, true).timeout
	await draws(4)

## Opens the Esc menu over a black frame, so only the boards show ink.
func menu(hud: GameHUD) -> void:
	hud._open_menu()
	var black := Image.create(800, 600, false, Image.FORMAT_RGB8)
	hud._esc_frame = black
	hud._esc_bg.use(black)
	hud._esc_bg.visible = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		printerr("Run with a rendering display"); get_tree().quit(2); return
	GameData.options.merge({"display_mode":0,"confine_mouse":0,"auto_graphics":0,"show_tutorial":0,"autosave":0,
		"net_upnp":0,"net_lan":0,"net_directory":0}, true)
	GameData.options.resolution = GameData.resolutions().find(Vector2i(800,600))
	GameData._apply_window()
	TutorialPanel.auto_show = false
	var session := Session.new(); add_child(session)
	var game := Game.new(); game.session = session; session.game = game; add_child(game)
	session.state.ensure_hero(0,"Human Hero")
	await session.enter_zone("gz1g",1,false)
	session.world.vm.instances.clear()
	var hud := game.hud
	hud._dialog.hide()
	await get_tree().create_timer(1.0).timeout
	menu(hud)
	await get_tree().create_timer(1.0, true, false, true).timeout
	await draws(4)
	check(hud.visible and hud._menu.visible, "the Esc menu is shown")
	for flip in [false, true]:
		for fps in [60, 20]:
			Engine.max_fps = fps
			for id in ["options", "load", "save"]:
				if not hud._esc_open: menu(hud)
				var panel: Control = hud._options if id == "options" else hud._save_load
				await opening(hud, id, id + (" flip" if flip else "") + " %d" % fps, panel, func(): panel._close(), flip)
	Engine.max_fps = 30
	hud._close_menu()
	print("ESC_BOARD_FRAMES ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
