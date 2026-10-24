extends "arena_expansion_ui.gd"
## Historical versus live portrait events, smooth native faces, and real peers.

var expansion := false
var host_commander := "hero"
var guest_commander := "merc3"

class OnlineScreen extends ArenaOnlineScreen:
	var cues: Array[String] = []
	func _play_cue(kind: String) -> void:
		cues.append(kind)
		super._play_cue(kind)

func until(predicate: Callable, seconds := 12.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < end: await frames(1)
	return predicate.call()

func neutral(label: String) -> void:
	var portrait := screen._commander_portrait
	check(portrait._reaction_left == 0 and portrait._upgrade_left == 0 and portrait._motion_age >= portrait.GESTURE_SECONDS, label+" does not replay a gesture")
	check(portrait._expression_mix.is_zero_approx(), label+" starts with a neutral face")

func _ready() -> void:
	OS.add_logger(errors); await frames(24)
	GameData._window_gen += 1
	GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,"auto_graphics":0,"net_upnp":0}, true)
	get_window().mode = Window.MODE_WINDOWED; get_window().size = Vector2i(1600,900); get_window().position = Vector2i.ZERO
	await solo_switches()
	hold_preparation = false
	await peers(false)
	await peers(true)
	check(errors.messages.filter(func(message): return not message.begins_with("NO GRAB")).is_empty(), "no runtime/render errors: "+str(errors.messages))
	print("ARENA_COMMANDER_EVENTS_UI checks=",checks," failures=",JSON.stringify(failures))
	OS.remove_logger(errors); TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)

func solo_switches() -> void:
	GameData.arena_mode = 2 if expansion else 1
	screen = ArenaPveScreen.new(); add_child(screen); await frames(16)
	screen._seed_input.text = "7191"; screen._begin(); screen.run.auto_save = false
	Fixture.buy_company(screen.run,1); await frames(20)
	while ShaderCompilationScreen.active(): await frames(2)
	for plan: Dictionary in screen.run.bot_plans: plan.done = true
	for player in 9: screen.run.company(player).last_result = {"winner":player % 2,"wave":1}
	for player in [1,2,3,0,1,0]:
		screen._show_player(player); await frames(3)
		neutral("solo scouting "+str(player))
	screen._show_boards(); await frames(3); screen._show_player(0); await frames(3)
	neutral("return from overview")
	var old_character := screen.run.commander
	screen.run.commander = "merc6"; await frames(5); neutral("same-board character change")
	screen.run.commander = old_character; await frames(5)
	# Separate owners may choose the same character in multiplayer.
	screen.run.company(2).commander = screen.run.company(1).commander
	screen._show_player(1); await frames(4)
	screen.run.company(1).last_result = {"winner":0,"wave":2}; await frames(3)
	check(screen._commander_portrait._reaction_left > 0,"new watched result still reacts")
	screen._show_player(2); await frames(3); neutral("different owner with identical model")
	screen._show_player(0); await frames(5)
	await blend_frames()
	screen.queue_free(); screen = null; await frames(8)

func blend_frames() -> void:
	screen.set_process(false)
	var portrait := screen._commander_portrait
	portrait.set_process(false)
	portrait.set_result(-2,"blend:neutral",false)
	portrait.set_result(0,"blend:smile")
	check(portrait._expression_mix.is_zero_approx(),"smile starts from current neutral pixels")
	await frames(3); await RenderingServer.frame_post_draw
	var neutral_pixels := portrait.view.get_texture().get_image()
	neutral_pixels.save_png("user://commander-face-neutral.png")
	portrait._advance_expression(portrait.EXPRESSION_SECONDS * 0.5)
	check(portrait._expression_mix.is_equal_approx(Vector2(0.5,0)),"expression eases through an intermediate blend")
	await frames(3); await RenderingServer.frame_post_draw
	var middle := portrait.view.get_texture().get_image()
	middle.save_png("user://commander-face-blend.png")
	portrait._advance_expression(portrait.EXPRESSION_SECONDS * 0.5)
	await frames(3); await RenderingServer.frame_post_draw
	var smiling := portrait.view.get_texture().get_image()
	smiling.save_png("user://commander-face-smile.png")
	check(middle.get_data() != neutral_pixels.get_data() and middle.get_data() != smiling.get_data(),"rendered intermediate face differs from both endpoints")
	check(portrait.face.get_shader_parameter("expression_weights") == Vector2.RIGHT,"material reaches the full native smile")
	portrait.set_result(1,"blend:frown")
	check(portrait._expression_mix == Vector2.RIGHT,"a new loss does not snap away from a smile")
	portrait._advance_expression(portrait.EXPRESSION_SECONDS * 0.5)
	check(portrait._expression_mix.is_equal_approx(Vector2(0.5,0.5)),"smile blends continuously into frown")
	portrait.set_result(-2,"blend:reset")
	check(portrait._expression_mix.is_equal_approx(Vector2(0.5,0.5)),"return to neutral starts from interrupted blend")
	portrait._advance_expression(portrait.EXPRESSION_SECONDS)
	check(portrait._expression_mix.is_zero_approx(),"return blend reaches neutral exactly")
	var unrelated := EIUnitModel.PreviewMaterial.new()
	check(unrelated.get_shader_parameter("expression_weights") in [null,Vector2.ZERO],"other preview materials retain zero expression weights")
	portrait.set_process(true); screen.set_process(true)

func peers(websocket: bool) -> void:
	var tag := "websocket" if websocket else "enet"
	var port := 29862 if websocket else 29861
	GameData.arena_character = host_commander
	var host := ArenaOnlineSession.new(); host.player_name = "Portrait host"; host.expansion = expansion; add_child(host)
	check(host.host(port,websocket) == OK,tag+" host listens")
	GameData.arena_character = guest_commander
	var guest := ArenaOnlineSession.new(); guest.player_name = "Portrait guest"; guest.expansion = expansion; add_child(guest)
	check(guest.join(("ws://" if websocket else "")+"127.0.0.1:"+str(port)) == OK,tag+" guest connects")
	check(await until(func(): return guest.my_seat == 1),tag+" guest gets its own seat")
	guest.request("ready")
	check(await until(func(): return host.members.values().all(func(member): return member.ready)),tag+" ready acknowledged")
	check(host.start_game(7191).is_empty(),tag+" game starts")
	host.game.set_process(false)
	check(await until(func(): return guest.started),tag+" initial state arrives")
	check(host.game.run.commander == host_commander and host.game.run.company(1).commander == guest_commander,tag+" lobby character choices survive handshake")
	for company_id in 9: host.game.run.company(company_id).last_result = {"winner":company_id % 2,"wave":1}
	host._dirty = true
	check(await until(func(): return guest.view.last_result.get("wave",0) == 1),tag+" historical results arrive before opening board")
	for connection: ArenaOnlineSession in [host,guest]:
		var role := tag+(" host" if connection == host else " guest")
		var online := OnlineScreen.new(); online.connection = connection; add_child(online); screen = online
		await frames(20)
		while ShaderCompilationScreen.active(): await frames(2)
		neutral(role+" initial state")
		check(screen._commander_portrait.commander == (host_commander if connection == host else guest_commander),role+" portrait belongs to local seat")
		for player in [1,2,0,1,0]:
			screen._show_player(player); await frames(4)
			neutral(role+" switch "+str(player))
			check(screen._commander_portrait.commander == host.game.run.company(connection.view.seats[player]).commander,role+" scouted face matches authority")
		var authority := host.game.run.company(connection.my_seat)
		authority.last_result = {"winner":1,"wave":10+connection.my_seat}; host._dirty = true
		check(await until(func(): return screen._commander_portrait._reaction_left > 0),role+" fresh loss starts a reaction")
		var portrait := screen._commander_portrait
		check(portrait._expression_target == Vector2.DOWN,role+" fresh loss targets frown")
		var age := portrait._motion_age
		for repeat in 3: host._dirty = true; await frames(4)
		check(portrait._motion_age > age,role+" repeated snapshots never restart gesture")
		await get_tree().create_timer(2.2).timeout
		neutral(role+" expired loss")
		screen._show_player(1); await frames(4); screen._show_player(0); await frames(4)
		neutral(role+" revisit old loss")
		# Actual purchases and training are host-authorized, including guest input.
		authority.army.clear(); authority.gold = 100; authority.training = 0
		var uid := int(authority._recruit(0,0,1).uid); authority._recruit(0,0,1)
		authority.arrange(); authority.shop.assign([{"family":0,"rank":0,"locked":false}])
		if connection.my_seat == 0: host.game.home.prepare()
		else: host.game.boards._sync_board(connection.my_seat)
		host._dirty = true
		check(await until(func(): return screen.run.gold == 100 and screen.run.army.size() == 2),role+" purchase fixture arrives")
		connection.request("buy",[0])
		check(await until(func(): return screen.run.unit(uid).get("rank",0) == 1 and portrait._upgrade_left > 0),role+" acknowledged evolution smiles and nods")
		check(portrait._expression_target == Vector2.RIGHT,role+" evolution targets smile")
		await get_tree().create_timer(2.2).timeout; neutral(role+" expired upgrade")
		for training in 2:
			var before := authority.training; connection.request("train")
			check(await until(func(): return screen.run.training > before),role+" training acknowledgement")
		check(portrait._upgrade_left > 0,role+" new company level reacts")
		# The watched opponent arrives as newly allocated company objects each
		# snapshot. Their persistent seat identity must still detect live changes.
		screen._show_player(1); await frames(4); neutral(role+" scout after upgrade")
		var other := host.game.run.company(connection.view.seats[1])
		other.gold = 100; var level := other.capacity()
		while other.capacity() == level: other.train()
		host._dirty = true
		check(await until(func(): return portrait._upgrade_left > 0),role+" observed opponent level reacts across snapshots")
		screen._show_player(0); await frames(4); neutral(role+" return after opponent upgrade")
		host.game.run.placements[connection.my_seat] = 1; host._dirty = true
		check(await until(func(): return portrait._result_event == "match:won" and portrait._reaction_left > 0),role+" match victory reacts")
		host.game.run.placements[connection.my_seat] = 3
		if connection.my_seat == 0: host.game.run.lives = 0
		else: host.game.run.rival_health[connection.my_seat-1] = 0
		var losses := online.cues.count("lose"); host._dirty = true
		check(await until(func(): return portrait._result_event == "match:lost" and portrait._reaction_left > 0),role+" match elimination reacts")
		check(online.cues.count("lose") == losses+1,role+" own elimination plays death cue once")
		for repeat in 3: host._dirty = true; await frames(4)
		check(online.cues.count("lose") == losses+1,role+" repeated elimination cannot repeat death cue")
		await shot("commander-events-"+role.replace(" ","-"))
		host.game.run.placements[connection.my_seat] = 0
		if connection.my_seat == 0: host.game.run.lives = 100
		else: host.game.run.rival_health[connection.my_seat-1] = 100
		host._dirty = true
		screen.queue_free(); screen = null; await frames(8)
	guest.close(); host.close(); guest.queue_free(); host.queue_free(); await frames(8)
