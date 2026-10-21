extends Node
const TrainingRefund = preload("res://src/game/training_refund.gd")
var checks := 0
var failures := []
var camp: CampView
var hero: GameUnit
var physical := InputEventMouseButton.new()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)

func frames(n := 5) -> void:
	for i in n: await get_tree().process_frame

func press(kind: String, name: String) -> void:
	camp.queue_redraw(); await frames()
	var rows := camp._skill_rows.filter(func(r): return r.size()>4 and r[3]==kind and r[4].get("stat" if kind=="skill" else "perk","")==name)
	check(rows.size()==1,"refund row available "+name)
	if rows.is_empty(): return
	physical.button_index = MOUSE_BUTTON_RIGHT; physical.pressed = true; physical.position = Vector2(-100,-100)
	Input.parse_input_event(physical.duplicate()); Input.flush_buffered_events()
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_RIGHT; click.pressed = true
	click.position = camp._r(Rect2(350,rows[0][0].position.y,40,15)).get_center()
	camp._gui_input(click)
	await frames()

func release() -> void:
	physical.pressed = false; Input.parse_input_event(physical.duplicate()); Input.flush_buffered_events(); camp._input(physical)

func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
	var s := Session.new(); add_child(s)
	var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	var h: Dictionary = s.state.heroes[0][0]
	h.exp = 1000000.0; h.exp_total = 1000000.0; h.skills = {}
	for skill: String in Skills.LIST: h.skills[skill] = 2
	h.perks = ["sword1","sword2","sword3","bs1","bs2","bs3"]
	h.erase(TrainingRefund.KEY)
	await s.enter_zone("bz2g",1,false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false); s.world.vm.instances.clear()
	hero = s.party_units(0)[0]; h = hero.get_meta("hero")
	var panel := g.hud._inventory; panel.open(false); camp = panel._camp; camp.set_mode("spells"); camp.set_process(false)
	await frames(15)
	var budget := float(h.exp)+TrainingRefund.amount(h)
	for skill: String in Skills.LIST:
		await press("skill",skill)
		check(Skills.level(h,skill)==1,"one immediate refund "+skill)
		camp._process_training_hold(.74); await frames()
		check(Skills.level(h,skill)==1,"delay before repeat "+skill)
		camp._process_training_hold(.02); await frames()
		check(Skills.level(h,skill)==0,"held button reaches zero "+skill)
		var exp: float = h.exp
		camp._process_training_hold(.1); camp._process_training_hold(1.0); await frames()
		check(Skills.level(h,skill)==0 and h.exp==exp and camp._hold_cmd.is_empty(),"zero stops without extra refund "+skill)
		release()
	for family in ["sword","bs"]:
		await press("perk",family+"3")
		check(not Perks.has(h,family+"3") and Perks.has(h,family+"2"),"top rank removed "+family)
		camp._process_training_hold(.76); await frames()
		check(not Perks.has(h,family+"2") and Perks.has(h,family+"1"),"repeat follows family to second rank "+family)
		camp._process_training_hold(.1); await frames()
		check(not Perks.has(h,family+"1"),"repeat follows family to last rank "+family)
		var exp: float = h.exp
		camp._process_training_hold(.1); await frames()
		check(h.exp==exp and camp._hold_cmd.is_empty(),"empty family stops after list reflow "+family)
		if family=="sword": check(Perks.has(h,"bs3"),"reflow does not refund the next ability")
		release()
	check(is_equal_approx(float(h.exp)+TrainingRefund.amount(h),budget),"rank refunds plus retained legacy credit conserve the point budget")
	for stop in ["hidden","mode","unit","dead","released","focus"]:
		h.skills.melee=2 # every cancellation must work before the zero-rank guard
		camp._hold_cmd = {"t":"untrain","unit":hero.uid,"stat":"melee"}; camp._hold_t = 1.0
		physical.pressed = true; Input.parse_input_event(physical.duplicate()); Input.flush_buffered_events()
		match stop:
			"hidden": panel.hide()
			"mode": camp.mode = "weapons"
			"unit": camp._hold_cmd.unit = hero.uid+1
			"dead": hero.dead = true
			"released": release()
			"focus": camp._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		camp._process_training_hold(.1)
		check(camp._hold_cmd.is_empty(),"hold cancelled when "+stop)
		hero.dead = false; panel.show(); camp.mode = "spells"; release()
	g.queue_free(); s.queue_free(); await frames(10); TexUpscale.shutdown()
	print("TRAINING_HOLD %d checks %d failures" % [checks,failures.size()])
	get_tree().quit(1 if not failures.is_empty() else 0)
