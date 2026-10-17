extends Node
const Refund := preload("res://src/game/training_refund.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func frames(n:=4) -> void:
	for i in n: await get_tree().process_frame
func allocation(h: Dictionary) -> Array:
	return [Skills.LIST.map(func(sk):return Skills.level(h,sk)),h.perks]
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"control_mode":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	var state:=CampaignState.new();state.ensure_hero(0,"Human Hero")
	var h: Dictionary=state.heroes[0][0]
	var initial:=allocation(h).duplicate(true);var original:=h.duplicate(true)
	check(Skills.level(h,"melee")==10 and Skills.level(h,"science")==3 and Skills.level(h,"sense")==12 and Skills.level(h,"astral")==9 and h.perks.has("bs1"),"original starting allocation matches Zak")
	h.exp=1000000.0
	check(not Refund.refund(h,false) and h.exp==1000000.0,"vanilla reset at baseline is an exact no-op")
	for i in 3: Skills.raise(h,"sense")
	Perks.learn(h,"sword1")
	check(Refund.refund(h,false) and h.exp==1000000.0 and allocation(h)==initial,"vanilla reset refunds only investment above original skills and backstab")
	var budget: float=h.exp+Refund.amount(h)
	for cycle in 4:
		check(Refund.refund(h) and h.perks.is_empty(),"full reset remains available after vanilla reset")
		check(Refund.refund(h,false) and allocation(h)==initial,"vanilla mode restores a previously fully reset hero")
		check(h.exp+Refund.amount(h)==budget,"alternating modes conserves total points")
	var legacy:=original.duplicate(true);legacy.erase(Refund.KEY);legacy.exp=1000.0;legacy.perks.append("sword1")
	var legacy_budget: float=legacy.exp+Refund.amount(legacy)
	check(Refund.refund(legacy,false) and allocation(legacy)==initial,"legacy allocation retains original abilities")
	check(legacy.exp+Refund.amount(legacy)==legacy_budget,"legacy overpayment credit is consumed only once")
	var missing:={"prototype":"missing-prototype","skills":{"melee":10},"perks":[],"exp":0.0}
	check(not Refund.reason(missing,false).is_empty() and not Refund.refund(missing,false),"unknown original allocation is never guessed")
	var poor:=original.duplicate(true);Refund.refund(poor);poor.exp=0.0;var copy:=poor.duplicate(true)
	check(not Refund.refund(poor,false) and poor==copy,"restoration cannot produce negative XP")
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=state
	await s.enter_zone("bz2g",1,false)
	s.set_physics_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	var u: GameUnit=s.party_units(0)[0];g.selected.assign([u]);u.blocked=false
	h=u.get_meta("hero");Skills.raise(h,"sense")
	var before:=h.duplicate(true)
	if DisplayServer.get_name() != "headless":
		await frames(24)
		GameData._window_gen += 1
		get_window().mode = Window.MODE_WINDOWED
		await frames(8) # let the window manager finish restoring the old frame
		var resolution := OS.get_environment("CHECK_SIZE").split("x")
		var wanted := Vector2i(int(resolution[0]), int(resolution[1])) if resolution.size() == 2 else Vector2i(1024,768)
		get_window().size = wanted
		get_window().position = DisplayServer.screen_get_usable_rect().position + Vector2i(100,100)
		await frames(6)
		print("UI_RESOLUTION wanted=",wanted," actual=",get_window().size," viewport=",get_viewport().get_visible_rect().size)
		check(get_window().size == wanted, "actual physical resolution matches requested UI check")
	else:
		get_window().size = Vector2i(1024,768)
		await frames(6)
	g.hud._inventory.open(false)
	var camp:=g.hud._inventory._camp
	camp.set_mode("spells");await frames(6)
	for label: String in ["Reset skills…"] + RemakeText.TEXTS["Reset skills…"]:
		check(Interface800.font().get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,camp._fpx(0)).x <= camp._r(CampView.REFUND_RECT).size.x - 4*camp._s(), "camp reset label fits: " + label)
	# Click the actual drawn reset row; no command should run before a choice.
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=camp._r(CampView.REFUND_RECT).get_center()
	camp._gui_input(click);await frames(6)
	check(is_instance_valid(camp._reset_dialog) and camp._reset_dialog.visible,"camp reset button opens the choice dialog")
	check(h==before,"opening the choice dialog does not change skills")
	var dialog=camp._reset_dialog
	if is_instance_valid(dialog):
		check(dialog._surface.get_global_rect().size.x<=get_viewport().get_visible_rect().size.x,"localized dialog fits viewport width")
		check(dialog._surface.get_global_rect().end.y<=get_viewport().get_visible_rect().end.y,"localized dialog fits viewport height")
		var bottom_padding: float = dialog._surface.get_global_rect().end.y - dialog.cancel_button.get_global_rect().end.y
		check(absf(bottom_padding - 24.0 * dialog._ui_scale) < 2.0, "dialog ends with normal padding below Cancel")
		for button in [dialog.original_button,dialog.full_button]:
			check(button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x<button.size.x,"localized choice label fits")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://training-reset-"+RemakeText.lang+".png")
		var esc:=InputEventKey.new();esc.pressed=true;esc.keycode=KEY_ESCAPE
		dialog._input(esc);await frames(3)
		check(h==before,"Escape cancels without refunding")
		camp._choose_training_reset();await frames(3)
		camp._reset_dialog.original_button.pressed.emit();await frames(3)
		check(allocation(h)==initial and float(u.stats.get("backstab",0.0))>0,"vanilla choice applies through camp authority and keeps live backstab")
		camp._choose_training_reset();await frames(3)
		camp._reset_dialog.full_button.pressed.emit();await frames(3)
		check(h.perks.is_empty() and Skills.LIST.all(func(sk):return Skills.level(h,sk)==0),"full choice applies through camp authority")
		check(s.save_game("reset_choices")==OK,"choice result saves")
		var loaded:=CampaignState.load_from(SaveInfo.path("reset_choices"))
		check(loaded!=null and allocation(loaded.heroes[0][0])==allocation(h),"chosen allocation survives save and reload")
		camp._choose_training_reset();await frames(3)
		camp.hide();await frames(3)
		check(not is_instance_valid(camp._reset_dialog),"closing camp disposes the reset dialog")
	g.queue_free();s.queue_free();await frames(8)
	print("TRAINING_RESET_CHOICE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
