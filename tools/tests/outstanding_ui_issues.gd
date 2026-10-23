extends "local_host_campaign.gd"
## Real campaign UI, authority commands and independent presentation clocks.
class CaptureSession extends Session:
	var acks: Array = []
	func broadcast(e: Dictionary) -> void:
		if e.get("t", "") == "ack": acks.append(e.code)
		super.broadcast(e)

class ProbeMixer extends SoundMixer:
	var active := {}
	var stopped: Array = []
	var serial := 0
	func play2d(path: String, _prio: int, _vol: float, _pan: float, _loop := false, _cam := false, _cat := CAT_SFX) -> int:
		serial += 1; active[serial] = path; return serial
	func playing(h: int) -> bool: return active.has(h)
	func stop(h: int) -> void: stopped.append(h); active.erase(h)

var observations: Array = []

func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge(GfxPresets.values(GfxPresets.LOW), true)
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,
		"net_lan":0,"net_directory":0,"control_mode":0,"camera_style":1,"cam_follow":1,
		"village_start_view":0,"scroll_border":0,"pad_enabled":0,"show_path":1}, true)
	TutorialPanel.auto_show = false
	var s := CaptureSession.new(); add_child(s)
	var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, "Human Hero")
	await s.enter_zone("gz1g", 1, false)
	s.set_physics_process(false); s.world.set_physics_process(false); s.world.set_process(false)
	s.world.vm.instances.clear()
	var hero: GameUnit = s.party_units(0)[0]
	hero.blocked = false; hero.stop_steering(); hero.orders.clear(); hero.order = {}
	g.rig.release(); g.selected.assign([hero]); g.rig.set_process(false)
	s.acks.clear(); hero.mana = 0
	hero.command({"type":"cast","spell":"heal","target":hero,"known_spell":true})
	check(s.acks == [EIAcks.CANT_CAST], "insufficient stamina emits only the authority refusal")
	s.acks.clear(); hero.mana = 100000
	hero.command({"type":"cast","spell":"heal","target":hero,"known_spell":true})
	check(s.acks == [EIAcks.CAST], "sufficient stamina emits one authority acceptance")
	hero.orders.clear(); hero.order = {}; hero.mana = hero.max_mana
	var sound := GameSound.new(); sound.game = g
	var mixer := ProbeMixer.new(); sound.mixer = mixer
	for quiet in [false,true]:
		sound._ack_q.clear(); sound._acks.clear(); mixer.active.clear(); mixer.stopped.clear()
		sound._ack_queue(hero, EIAcks.SHOP_YES if quiet else EIAcks.CAST, "accept.wav", EIAcks.CAST)
		sound._ack_queue(hero, EIAcks.SHOP_NO if quiet else EIAcks.CANT_CAST, "refuse.wav", EIAcks.CANT_CAST)
		check(mixer.active.values() == ["refuse.wav"] and mixer.stopped.size() == 1,
			"replacement stops the playing acceptance, quiet=" + str(quiet))
	# A menu pauses the simulation, but a new order's indicators expire in wall time.
	var fx := ParticleFx.for_order_marks(s.world)
	var sim_fx := ParticleFx.of(s.world)
	for speed in [1.0, 55.0/27.0]:
		Engine.time_scale = speed; get_tree().paused = true
		var ticks := sim_fx.tick; var audio_ticks := g.sound._ticks
		g.marks._show(hero, hero.pos + Vector2(2,0), 0, 0,
			PackedVector3Array([Vector3(hero.pos.x,hero.pos.y,0),Vector3(hero.pos.x+2,hero.pos.y,0)]))
		check(not fx.effects.is_empty(), "paused command immediately creates indicators")
		var expire_at := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < expire_at: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		check(fx.effects.is_empty(), "paused indicators expire at wall time, speed=" + str(speed))
		check(sim_fx.tick == ticks and g.sound._ticks == audio_ticks,
			"world particles and weather audio stay paused, speed=" + str(speed))
		get_tree().paused = false
	# Both mouse buttons provide the same two-axis orbit; Shift-middle pans.
	Engine.time_scale = 1.0
	var outcomes: Array = []
	for button in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		g.rig.yaw = 0; g.rig._pitch_ofs = 0; g.rig._drag_button = button
		var motion := InputEventMouseMotion.new(); motion.relative = Vector2(20,15)
		g.rig._input_modern(motion)
		outcomes.append(Vector2(g.rig.yaw, g.rig._pitch_ofs))
	check(outcomes[0].is_equal_approx(outcomes[1]) and outcomes[0].x != 0 and outcomes[0].y != 0,
		"middle and right drag rotate and tilt identically")
	g.rig._drag_button = 0
	# The campaign difficulty affects the current world's combat without travel.
	check(ModStore.editable("difficulty", s).is_empty(), "difficulty is editable in the field")
	check(s.apply_mod_rules({"difficulty":1}, {}).is_empty() and GameData.difficulty == 1,
		"live difficulty reaches combat settings")
	check(s.state.mod_config.rules.difficulty == 1, "live difficulty is part of saved campaign rules")
	var enemy: GameUnit = s.world.unit_rows().filter(func(u): return not Combat.named(u))[0]
	var easy_damage := s.world.combat.difficulty(enemy, "Attack")
	check(easy_damage != 1.0, "live Easy difficulty changes the combat multiplier immediately")
	s.apply_mod_rules({"difficulty":0}, {})
	await s.enter_zone("bz1g", 1, false)
	s.world.set_process(false); s.world.set_physics_process(false); s.world.vm.instances.clear()
	s.world.vm.briefings.active = ""; s.world.vm.briefings._pending_dialog = {}
	g.hud._dialog.hide(); hero = s.party_units(0)[0]; hero.blocked = false
	var camp: CampView = g.hud._inventory._camp
	s.state.shops[1] = {"restock":false,"goods":{"material.bronze":5},"sold":{}}
	s.state.items = ["material.bronze","material.bronze","material.bronze","white wolf hide"]
	g.hud._inventory.open(true, 1); camp.set_mode("itemtrade")
	camp.press_sounds.clear()
	camp._move("material.bronze", "bag", true)
	check(camp.sell_pile.count("material.bronze") == 3 and camp.press_sounds == ["put_on.wav"],
		"whole stack enters sale pile with one put-on sound")
	camp._move("material.bronze", "sell", true)
	check(camp.sell_pile.is_empty() and camp.press_sounds.back() == "put_off.wav",
		"whole stack returns from sale pile with put-off sound")
	camp._move("material.bronze", "bag")
	check(camp.sell_pile.size() == 1, "ordinary click still moves one copy")
	camp._move("white wolf hide", "bag", true)
	check(not camp.sell_pile.has("white wolf hide"), "stack transfer cannot sell quest items")
	camp.trade_wait = true; camp._move("material.bronze", "bag", true)
	check(camp.sell_pile.size() == 1, "outstanding transaction locks stack transfers")
	camp.trade_wait = false
	camp.sell_pile.clear()
	s.state.items.assign(Array(range(Session.MAX_TRADE_ITEMS + 8)).map(func(_i): return "material.bronze"))
	camp._move("material.bronze", "bag", true)
	check(camp.sell_pile.size() == Session.MAX_TRADE_ITEMS and camp.bag_count("material.bronze") == 8, "whole-stack trade respects the transaction cap")
	camp._move("material.bronze", "sell", true)
	check(camp.sell_pile.is_empty(), "full capped stack returns intact")
	camp._move("material.bronze", "shop", true)
	check(camp.buy_pile.size() == 5 and camp.shop_left("material.bronze") == 0, "whole-stack purchase cannot exceed stock")
	sound._ack_q.clear(); mixer.active.clear()
	sound._ack_queue(hero, EIAcks.BORED, "bored.wav")
	check(mixer.active.is_empty(), "late companion chatter is suppressed inside shop")
	sound._ack_queue(hero, EIAcks.SCENARIO, "scenario.wav")
	check(mixer.active.values() == ["scenario.wav"], "scripted dialogue remains available")
	g.hud._inventory.hide()
	# The real mixer keeps shop UI audible and world loops available for return.
	g.sound._screens()
	var mix := g.sound.mixer
	var silent := AudioStreamWAV.new(); silent.data = PackedByteArray([0,0,0,0]); silent.mix_rate = 22050; silent.loop_mode = AudioStreamWAV.LOOP_FORWARD; silent.loop_end = 3
	var base := {"path":"", "stream":silent, "prio":1, "is3d":false, "pos":Vector3.ZERO, "min":0.0,"max":0.0,"loop":true,"cat":SoundMixer.CAT_SFX,"vol":100.0,"pan":0.0,"cam":false}
	var loop_handle := mix._start(base.duplicate())
	g.hud._inventory.open(true,1); g.sound._screens()
	check(mix.world_muted and mix.playing(loop_handle), "shop immediately mutes world mix while retaining an existing loop")
	check(mix.play_stream2d(silent,1,100,0) < 0 and mix.play_stream2d(silent,1,100,0,SoundMixer.CAT_SPEECH) < 0, "shop suppresses new ambience, creature sounds and voices")
	check(mix.play_stream2d(silent,1000,100,0,SoundMixer.CAT_UI) >= 0, "shop interface sound still gets a real mixer channel")
	var parked := mix._start(base.duplicate())
	check(mix._virtual.has(parked), "a loop starting inside the shop waits without taking a UI channel")
	g.hud._inventory.hide(); g.sound._screens(); mix._restore_virtual()
	check(not mix.world_muted and mix.playing(loop_handle) and mix.playing(parked), "leaving the shop restores retained world loops")
	mix.stop(loop_handle); mix.stop(parked)
	# Opening a conversation cancels tactical pause and acceleration, including in camp.
	for paused in [false,true]:
		get_tree().paused = paused; Engine.time_scale = 55.0/27.0; g.speed = 1; s.field_speed = 1
		g.hud._dialog.show_briefing({"id":"test","phrases":[{}],"staging":true})
		check(not get_tree().paused and Engine.time_scale == 1.0 and g.speed == 0 and s.field_speed == 0,
			"dialogue starts at normal speed from pause=" + str(paused))
		g.hud._dialog.hide()
	g.set_speed(0); check(get_tree().paused, "manual camp pause remains available"); get_tree().paused = false
	for lang in ["en","ru","de"]:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--" + lang + "-texts="):
				GameData.texts = EIResArchive.open_path(arg.get_slice("=",1))
				EIText.code_page = EIText.detect_code_page(GameData.texts)
		GameData._text_cache.clear()
		RemakeText.lang = RemakeText.detect(GameData.texts)
		check(RemakeText.lang == lang, "original localized archive loaded: " + lang)
		var name := g.hud._dialog._item_name("white wolf hide")
		var original := EIText.ansi(GameData.texts.read("questitem white_wolf_hide")).get_slice("\n",0).strip_edges()
		check(name == original and not name.is_empty() and name != "white wolf hide",
			"quest reward uses original localized title: " + lang)
		observations.append({"language":lang,"quest_reward":name})
		for key in ["camera_style","village_start_view"]:
			var help: String = GameData.REMAKE_OPTIONS[key][1]
			check(lang == "en" or RemakeText.t(help) != help, "camera help translated: " + lang + " " + key)
	sound.mixer = null; sound.free(); mixer.free()
	g.queue_free(); s.queue_free(); await frames()
	FileAccess.open("user://outstanding-ui-issues.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations}, "\t"))
	print("OUTSTANDING_UI_ISSUES ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
