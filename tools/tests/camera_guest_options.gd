extends Node
## Rendered option coverage and actual viewport hover ownership, in EN/RU/DE.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func frames(n := 6) -> void:
	for i in n: await get_tree().process_frame
func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://" + file + ".png")
func pointer(at: Vector2) -> void:
	Input.warp_mouse(at)
	var e := InputEventMouseMotion.new(); e.position = at; Input.parse_input_event(e)
	await frames()
func help_shot(options: OptionsPanel, row: int, file: String) -> void:
	get_window().grab_focus()
	await pointer(Vector2(20,20))
	GameData._tips.delay = .1
	await pointer(options._origin() + Vector2(400, options._row_y(row) + 12) * options.kv())
	await get_tree().create_timer(.3,true,false,true).timeout
	var entry: Dictionary = options._rows[row]
	check(GameData._tips._panel.visible and GameData._tips._text.contains(RemakeText.t(GameData.REMAKE_OPTIONS[entry.name][1])), "option help is displayed: " + entry.name)
	check(Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size).encloses(Rect2(GameData._tips._panel.position,GameData._tips._panel.size)), "option help fits: " + entry.name)
	await shot(file)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-lang="): RemakeText.lang = arg.get_slice("=", 1)
	check(GameData.option("power_mouse_y") == GameData.option("power_mouse"), "legacy settings preserve vertical sensitivity")
	GameData.options.merge({"auto_graphics":0,"show_tutorial":0,"autosave":0,"display_mode":0,"control_mode":0,
		"camera_style":1,"scroll_border":8,"pad_enabled":0,"cam_follow":0,"coop_clock":1,
		"net_upnp":0,"net_lan":0,"net_directory":0}, true)
	await frames(20)
	GameData._window_gen += 1
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(1280,800)
	# Wine on an isolated X server warps in desktop coordinates. An origin
	# window keeps real pointer polling aligned with injected client events.
	get_window().position = Vector2i.ZERO if OS.get_name() == "Windows" else Vector2i(70,50)
	get_window().grab_focus()
	var s := Session.new(); add_child(s)
	var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0,"Human Hero"); s._enter_zone("gz15h",1,false)
	s.set_physics_process(false); s.world.set_physics_process(false)
	s.world.vm.instances.clear(); s.world.vm.briefings._check = INF
	g.hud._tutorial.close(); g.rig.release(); g.rig.set_process(false); await frames()
	var rig := g.rig
	GameData.options.power_mouse = 50; GameData.options.power_mouse_y = 50
	var before := rig._original_mouse_targets(Vector2(2,10),Vector2(1280,800),false)
	var pan := rig._original_mouse_targets(Vector2(10,10),Vector2(1280,800),true)
	GameData.options.power_mouse_y = 10
	var after := rig._original_mouse_targets(Vector2(2,10),Vector2(1280,800),false)
	var pan_after := rig._original_mouse_targets(Vector2(10,10),Vector2(1280,800),true)
	check(is_equal_approx(before.yaw,after.yaw), "vertical slider leaves yaw unchanged")
	check(is_equal_approx(before.pitch * .2, after.pitch), "vertical tilt can be reduced independently")
	check(is_equal_approx(pan.pan.x, pan_after.pan.x) and is_equal_approx(pan.pan.y * .2, pan_after.pan.y), "modified drag has independent axes")
	GameData.options.power_mouse = 25
	after = rig._original_mouse_targets(Vector2(2,10),Vector2(1280,800),false)
	check(is_equal_approx(before.yaw * .5, after.yaw) and is_equal_approx(before.pitch * .2, after.pitch), "horizontal slider leaves vertical unchanged")
	# A real GUI control owns this edge; camera polling must still pan the world.
	var edge_panel := ColorRect.new(); edge_panel.color = Color(.1,.2,.15,.4)
	edge_panel.mouse_filter = Control.MOUSE_FILTER_STOP; edge_panel.position = Vector2(0,300)
	edge_panel.size = Vector2(80,160); g.hud.add_child(edge_panel)
	await pointer(Vector2(2,350))
	check(get_viewport().gui_get_hovered_control() == edge_panel, "interactive HUD owns the edge pointer")
	rig._pointer_inside = true; rig._window_focused = true
	check(rig._edge_scroll().x == -1, "modern edge scroll survives GUI hover")
	var start := rig.position
	for i in 20: rig._process_modern(1.0/60)
	check(rig.position.distance_to(start) > .01, "camera actually pans while hovering UI")
	GameData.options.camera_style = 0
	check(rig._edge_scroll() == Vector2i.ZERO, "classic GUI edge behavior retained")
	GameData.options.camera_style = 1
	rig._pointer_inside = false
	check(rig._edge_scroll() == Vector2i.ZERO, "pointer outside window cannot pan")
	rig._pointer_inside = true
	var focus := LineEdit.new(); g.hud.add_child(focus); focus.grab_focus()
	check(rig._input_blocked(), "typing prevents camera polling")
	focus.release_focus(); focus.free()
	g.hud._inventory.visible = true
	check(rig._input_blocked(), "full-screen inventory still owns camera input")
	g.hud._inventory.visible = false; edge_panel.free()
	g.queue_free(); s.queue_free(); await frames()
	var network := NetworkPanel.new(); add_child(network); network.open(); network.show_page(NetworkPanel.HOST_COOP)
	await frames(); await shot("coop-host-settings-link")
	check(network._targets.has("coop_settings"), "multiplayer host menu exposes settings")
	network.open_coop_settings(); await frames()
	check(network._coop_settings._group == OptionsPanel.COOP_GROUP and not network._save_choice.visible, "menu opens co-op settings without stray save selector")
	var options := network._coop_settings
	for row in [9,10]:
		var entry: Dictionary = options._rows[row]
		check(entry.name in GameData.OPTIONS_APPLIED, "guest option is active")
		for i in 4:
			options._values[entry.name] = i
			check(options._switch_text(entry) == GameData.option_choices(entry.name)[i], "localized guest permission choice")
		options._values[entry.name] = 0
	for viewport: Vector2i in [Vector2i(1280,800),Vector2i(720,1280)]:
		get_window().size = viewport; await frames()
		options._show_group(OptionsPanel.COOP_GROUP)
		options._values.coop_guest_clock = 3; options._values.coop_guest_saves = 3
		await frames(); await shot("guest-options-%dx%d" % [viewport.x,viewport.y])
		options._show_group(2); await frames(); await shot("camera-options-%dx%d" % [viewport.x,viewport.y])
		for row in [1,2]:
			var entry: Dictionary = options._rows[row]
			check(not entry.tip.is_empty() and entry.label == RemakeText.t(GameData.REMAKE_OPTIONS[entry.name][0]), "camera option label/help localized")
	get_window().size = Vector2i(1280,800); await frames()
	for row in [1,2]: await help_shot(options,row,"camera-help-%d" % row)
	options._show_group(OptionsPanel.COOP_GROUP)
	for row in [9,10]: await help_shot(options,row,"guest-help-%d" % row)
	await pointer(Vector2(20,20))
	network.queue_free(); await frames()
	var owner := Session.new(); add_child(owner); owner.online = true
	owner.set_process(false); owner.set_physics_process(false)
	owner.players = {1:{"index":0,"name":"Host","colour":1},2:{"index":1,"name":"Guest","colour":2}}
	var players := PlayersPanel.new(); players.session = owner; add_child(players); players.open()
	for bit: int in [CoopPermissions.PAUSE,CoopPermissions.SAVE]: owner.set_player_permission(2,bit,true)
	for viewport: Vector2i in [Vector2i(1280,800),Vector2i(720,1280)]:
		get_window().size = viewport; await frames(); await shot("player-permissions-%dx%d" % [viewport.x,viewport.y])
		var layout := players._layout()
		check(layout.panel.encloses(layout.btn["load:2"]), "permission controls fit panel")
		check(players._label("pause:2") == RemakeText.t("On") and players._label("speed:2") == RemakeText.t("Off"), "individual permissions visible")
	players.press("speed:2")
	check(CoopPermissions.allows(owner,1,CoopPermissions.SPEED), "player permission button grants access")
	players.press("speed:2")
	check(not CoopPermissions.allows(owner,1,CoopPermissions.SPEED), "player permission button revokes access")
	players.queue_free(); owner.online = false; owner.queue_free(); await frames()
	print("CAMERA_GUEST_OPTIONS ", JSON.stringify({"checks":checks,"failures":failures}))
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
