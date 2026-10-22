extends Node
## Issue #20 (comment): the Options, Load and Save boards opened from the Esc
## menu slide up from below the screen. Their 3D board renders into its own
## SubViewport, which still holds the previous opening's settled picture; that
## picture must not show before the slide's first pose has been drawn.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func draws(count: int) -> void:
	for i in count: await RenderingServer.frame_post_draw

## The highest row with board ink in the central columns (-1: none). The
## backdrop is black, so only the board and the panel's own drawing count.
func top_row(img: Image) -> int:
	for y in range(0, img.get_height(), 2):
		var n := 0
		for x in range(img.get_width() * 3 / 8, img.get_width() * 5 / 8, 4):
			var c := img.get_pixel(x, y)
			if c.r > 0.25 and c.g > 0.18: n += 1
		if n >= 6: return y
	return -1

func opening(id: String, open: Callable, close: Callable, paused: bool, fps: int) -> void:
	get_tree().paused = paused
	Engine.max_fps = fps
	open.call()
	await get_tree().create_timer(1.0, true, false, true).timeout
	await draws(4)
	var rest := top_row(get_viewport().get_texture().get_image())
	check(rest >= 0, id + ": settled board is rendered")
	close.call()
	await draws(4)
	await get_tree().process_frame
	open.call()
	var tops: Array = []
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 300000:
		await RenderingServer.frame_post_draw
		tops.append(top_row(get_viewport().get_texture().get_image()))
	var h := get_viewport().get_visible_rect().size.y
	var first := -1
	for t: int in tops:
		if t >= 0: first = t; break
	print(id, " rest=", rest, " tops=", tops)
	check(first < 0 or first > rest + h * 0.1, id + ": no settled board flashes before the slide (first top %d, rest %d)" % [first, rest])
	close.call()
	await draws(4)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		printerr("Run with a rendering display"); get_tree().quit(2); return
	GameData.options.merge({"display_mode":0,"confine_mouse":0,"auto_graphics":0,"show_tutorial":0}, true)
	GameData.options.resolution = GameData.resolutions().find(Vector2i(800,600))
	GameData._apply_window()
	var black := Image.create(800, 600, false, Image.FORMAT_RGB8)
	var options := OptionsPanel.new()
	add_child(options)
	var load := LoadPanel.new()
	add_child(load)
	await draws(2)
	for paused in [false, true]:
		for fps in [60, 20]:
			var tag := "%s-%d" % ["paused" if paused else "running", fps]
			await opening("options " + tag, func(): options.open(black, true), func(): options._close(), paused, fps)
			await opening("load " + tag, func(): load.open(false, black, true), func(): load._close(), paused, fps)
			await opening("save " + tag, func(): load.open(true, black, true), func(): load._close(), paused, fps)
	get_tree().paused = false
	Engine.max_fps = 0
	print("BOARD_SLIDE_FRAMES ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
