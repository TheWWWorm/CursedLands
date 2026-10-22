extends Node
## Issue #20: open the Esc menu over a running region, as the player does, and
## check every composited frame of the opening. The signpost rises from below;
## no frame before the slide may show the settled signpost.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func until(p: Callable, seconds := 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if p.call(): return true
		await get_tree().process_frame
	return bool(p.call())

## Pixels of the central columns that differ from the frozen backdrop.
func ink(img: Image, base: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(img.get_width() * 3 / 8, img.get_width() * 5 / 8, 4):
			var a := img.get_pixel(x, y)
			var b := base.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.25: n += 1
	return n

## The brightness of the world beside the signpost (the right side),
## relative to the frozen dimmed backdrop: about 1 once the menu is open.
var _base_side := 0.0
func dimmed(img: Image) -> float:
	var sum := 0.0
	for y in range(img.get_height() / 4, img.get_height() * 3 / 4, 6):
		for x in range(img.get_width() * 7 / 10, img.get_width() * 9 / 10, 6):
			sum += img.get_pixel(x, y).get_luminance()
	return sum / maxf(_base_side, 0.001) - 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		printerr("Run with a rendering display"); get_tree().quit(2); return
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,
		"ssao":0,"volumetric":0,"water_reflections":0,"grass":0,"bloom":0,"far_view":0,"q_shadows":0,"contact_shadows":0,"heat_haze":0,"sky":0}, true)
	var s := Session.new(); get_parent().add_child(s)
	var g := Game.new(); g.session = s; s.game = g; get_parent().add_child(g)
	await s.local_host.start(0, 1, true)
	await s.new_campaign(false)
	await until(func(): return s.world != null and not s._remote_loading and not s.movie_active() and s.world.time > 2.0 and LoadingScreen._current == null, 240)
	await get_tree().create_timer(4.0, true, false, true).timeout
	var hud := g.hud
	var menu := hud._menu
	# The backdrop alone: open, hide the signpost, read the frozen picture.
	hud.toggle_menu()
	await get_tree().create_timer(4.0, true, false, true).timeout
	var rest_img := get_viewport().get_texture().get_image()
	menu.visible = false
	for i in 4: await RenderingServer.frame_post_draw
	var base := get_viewport().get_texture().get_image()
	var rest := ink(rest_img, base)
	_base_side = 1.0   # dimmed() then returns the raw sum - 1
	_base_side = dimmed(base) + 1.0
	check(rest > 200, "settled signpost differs from the backdrop (%d)" % rest)
	hud.toggle_menu()
	var flashes := 0
	for trial in 10:
		await get_tree().create_timer(1.0 + 0.137 * trial, true, false, true).timeout
		hud.toggle_menu()
		var seq: Array = []
		var live: Array = []
		var start := Time.get_ticks_usec()
		while Time.get_ticks_usec() - start < 2500000:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			seq.append(snappedf(float(ink(img, base)) / rest, 0.01))
			live.append(dimmed(img) > 0.6)
		# Skip frames drawn before the menu existed (the live, undimmed world),
		# then flag a settled signpost that is followed by a lower one.
		var opened: Array = []
		for k in seq.size():
			if live[k] == false: opened.append(seq[k])
		var first: float = opened[0] if opened.size() > 0 else -1.0
		var peak := 0.0
		var flashed := false
		for r: float in opened:
			if peak > 0.75 and r < 0.35: flashed = true
			peak = maxf(peak, r)
		if flashed: flashes += 1
		print("open %d first=%.2f seq=%s live=%s" % [trial, first, str(seq.slice(0, 8)), str(live.slice(0, 8))])
		hud.toggle_menu()
	check(flashes == 0, "no opening shows the settled signpost before its slide (%d of 10)" % flashes)
	print("PAUSE_MENU_INGAME ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
