extends "arena_expansion_ui.gd"
## Native preparation paths and opening composition, using actual pointer input.

func settle() -> void:
	for i in 160:
		if screen.battle.formation_motion.movers.is_empty(): return
		await get_tree().create_timer(0.05).timeout
	check(false, "formation reaches its destination without teleporting")

func _ready() -> void:
	OS.add_logger(errors)
	await frames(24)
	GameData._window_gen += 1
	GameData.options.merge(GfxPresets.values(GfxPresets.ORIGINAL),true)
	GameData.options.merge({"gfx_hd_textures":0,"gfx_sharp_units":0,"gfx_materials":0,"q_aa":0,"q_shadows":0},true)
	GameData.options.merge({"gfx_soft_ground":1,"footprints":1,"marks":1,"auto_graphics":0,"confine_mouse":0},true)
	get_tree().root.mode = Window.MODE_WINDOWED
	var lang := "en"; var dimensions := Vector2i(1280,800)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arena-resolution="):
			var spec:=arg.get_slice("=",1).split(",")
			lang=spec[0];dimensions=Vector2i(int(spec[1]),int(spec[2]))
	get_tree().root.size=dimensions;get_tree().root.position=Vector2i.ZERO
	RemakeText.lang=lang;await frames(8)
	screen=ArenaPveScreen.new();add_child(screen);await frames(24)
	var tag:="formation-%s-%d"%[lang,dimensions.x]
	bounded(screen._landing_panel,"opening composition")
	bounded(screen._landing_start,"opening action")
	check(not screen._seed_input.visible,"optional seed stays out of the primary flow")
	for preview in screen._landing_layer.find_children("*","WikiPreview",true,false):preview_fits(preview,"opening native model")
	await shot(tag+"-landing")
	screen._saved=true;screen._refresh();await frames(12)
	bounded(screen._landing_panel,"saved expedition composition")
	bounded(screen._landing_start,"new expedition beside resume")
	screen._seed_input.show();screen._layout_landing();await frames(8)
	bounded(screen._landing_panel,"saved expedition with expanded seed")
	screen._saved=false;screen._refresh();await frames(12)
	for button:Button in screen._landing_panel.find_children("*","Button",true,false):
		if button.text==RemakeText.t("Set seed"): await click(button.get_global_rect().get_center());break
	check(screen._seed_input.visible,"seed can be expanded")
	bounded(screen._landing_panel,"expanded seed composition")
	screen._seed_input.text="1741";screen._begin();screen.run.auto_save=false
	Fixture.buy_company(screen.run,1);await frames(2)
	check(not screen.battle.formation_motion.movers.is_empty(),"both teams enter with movement orders")
	check(screen.battle.world.time==0 and screen.battle.damage==[0.0,0.0],"entrance cannot start combat or age the round")
	await settle()
	var uid:=int(screen.run.army[0].uid)
	var unit:=body(uid);var actor:=unit.get_instance_id();var model:=unit.model.get_instance_id()
	var origin:=unit.pos
	await click(point(unit))
	var commanded := {}
	var capture := func(): commanded.position = unit.pos
	screen.run.changed.connect(capture, CONNECT_ONE_SHOT)
	# Fixed presentation time keeps this assertion meaningful on slow renderers:
	# the faster walk may finish during the input helper's awaited draw frames.
	screen.battle.set_physics_process(false)
	await click(screen.field.screen_point(Vector2(29,24)))
	if screen.run.changed.is_connected(capture): screen.run.changed.disconnect(capture)
	var target:=Vector2(screen.run.unit(uid).point[0],screen.run.unit(uid).point[1])
	check(screen.selected_uid==0,"move command releases selection")
	check(commanded.get("position",Vector2.INF).distance_to(origin)<0.01 and unit.pos.distance_to(target)>0.1,"click starts travel instead of teleporting")
	screen.battle._physics_process(0.1)
	check(unit.pos.distance_to(origin)>0.1 and unit.pos.distance_to(target)>0.1,"native movement advances across intermediate positions")
	check(unit.action in ["run","walk"],"travel plays native locomotion")
	await shot(tag+"-moving")
	screen.battle.set_physics_process(true)
	screen._show_menu();var paused:=unit.pos
	await get_tree().create_timer(0.25).timeout
	check(unit.pos==paused,"menu pauses formation travel")
	screen._close_modal();await settle()
	check(unit.pos.distance_to(target)<0.05 and unit.action=="idle","creature stops at the requested destination")
	check(unit.get_instance_id()==actor and unit.model.get_instance_id()==model,"moving retains the actor and model")
	check(not screen.battle.world.ground_marks.foot_marks.is_empty(),"preparation movement leaves native snow footprints")
	# Returning to reserves removes the actual actor; deploying runs back in.
	await click(point(unit));await click(screen._army_row.get_child(0).get_global_rect().get_center())
	check(body(uid)==null and not screen.run.unit(uid).deployed,"return to reserves removes the field creature")
	await click(screen._army_row.get_child(0).get_global_rect().get_center())
	await click(screen.field.screen_point(Vector2(27,39)))
	check(body(uid)!=null and screen.battle.formation_motion.movers.has(body(uid)),"reserve deployment runs onto the battlefield")
	# Starting early must wait for the field formation, with no free attacks.
	screen._fight();check(screen.battle._start_pending and screen.run.stage=="fight","early start waits for moving creatures")
	check(screen.battle.world.time==0 and screen.battle.damage==[0.0,0.0],"neither team attacks during assembly")
	await settle();await frames(2)
	check(screen.battle.phase==ArenaMatch.Phase.FIGHT,"combat starts when the formation is ready")
	screen.battle.set_process(false);screen.battle.world.set_process(false);screen.battle.world.set_physics_process(false)
	for tick in 1800:
		if screen.battle.phase!=ArenaMatch.Phase.FIGHT:break
		screen.battle.simulate_tick()
	check(screen.battle.phase==ArenaMatch.Phase.FINISHED,"assembled teams finish a native battle")
	screen.battle._process(1.6);screen.run.advance()
	check(not screen.battle.formation_motion.movers.is_empty(),"next round sends creatures into formation again")
	await settle()
	check(screen.battle.world.time==0,"round entrance does not advance the combat clock")
	check(errors.messages.is_empty(),"no scene or script errors")
	print("ARENA_FORMATION_UI ",checks," checks; failures=",JSON.stringify(failures)," errors=",JSON.stringify(errors.messages))
	get_tree().quit(0 if failures.is_empty() else 1)
