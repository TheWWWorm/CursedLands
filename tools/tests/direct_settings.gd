extends "third_person_kbm.gd"
func frames(n:=4) -> void:
	for i in n:
		await get_tree().process_frame
		if is_instance_valid(g):g.rig._window_focused=true

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0,"blood":0},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="direct settings";await s.enter_zone("gz1g",1,false);await prepare()
	hero.action="idle";hero._anim_lock=0;g.rig._window_focused=true
	hero.command({"type":"move","to":hero.pos+Vector2(2,0)})
	var orders:=hero.orders.duplicate(true)
	var selection:=g.selected.duplicate()
	g.direct.heading=0.8;g.direct.tilt=0.15
	await key(KEY_V)
	check(GameData.option("control_mode")==3 and is_equal_approx(g.direct.heading,0.8),"V switches perspective and preserves look direction")
	check(hero.orders==orders and g.selected==selection,"perspective switch preserves selected hero and orders")
	await key(KEY_F6);g.direct._process(0.0)
	check(not g.direct.active() and hero.orders==orders and g.selected==selection,"tactical switch preserves selection and ordinary orders")
	await key(KEY_F6);g.direct._process(0.0)
	check(g.direct.first_person() and hero.orders==orders,"tactical return restores the previous perspective")
	g.hud._inventory.visible=true;await key(KEY_V)
	check(g.direct.first_person(),"perspective binding cannot switch beneath inventory")
	g.hud._inventory.visible=false
	var defaults:=EIKeymap.bindings(2);var classic:=EIKeymap.bindings(0)
	var panel:=OptionsPanel.new();add_child(panel);panel.open();panel._tutorial.visible=false
	panel._show_group(OptionsPanel.DIRECT_GROUP)
	check(panel._rows[0].name=="direct_fov_first" and panel._rows[11].to==26 and panel._rows[12].to==25,"direct settings page exposes camera, controller and key pages")
	panel._show_group(OptionsPanel.DIRECT_KEYS_GROUP)
	panel._assign("direct_forward",EIKeymap.scan_code(KEY_I))
	check(panel._key_profiles[0]==classic,"rebinding direct movement leaves tactical bindings unchanged")
	panel._values.direct_fov_first=8;panel._values.direct_fov_third=2
	panel._values.direct_mouse_first=75;panel._values.direct_mouse_third=25
	panel._apply();panel._close()
	EIKeymap._direct_loaded=false
	check(EIKeymap.bindings(2).get(EIKeymap.scan_code(KEY_I))=="direct_forward","direct binding survives reloading its separate file")
	var cfg:=ConfigFile.new();check(cfg.load(GameData.CONFIG_PATH)==OK and cfg.get_value("options","direct_fov_first")==8,"FOV settings are persisted")
	g.direct.apply_camera()
	check(is_equal_approx(g.rig.camera.fov,90.0),"first-person FOV uses its own value")
	GameData.options.control_mode=2;g.direct.apply_camera()
	check(is_equal_approx(g.rig.camera.fov,60.0),"third-person FOV uses its own value")
	check(is_equal_approx(DirectControl.look_gain(75)/DirectControl.look_gain(25),4.0),"separate sensitivity values produce different look speeds")
	reset();hero.stop_steering();g.direct._world=s.world;g.direct._neutral=false
	var e:=InputEventKey.new();e.physical_keycode=KEY_I;e.keycode=KEY_I;e.pressed=true;Input.parse_input_event(e);await frames(1)
	g.direct._process(0.033)
	check(not hero.direct_steering.is_empty(),"rebound movement key reaches authority")
	e=InputEventKey.new();e.physical_keycode=KEY_I;e.keycode=KEY_I;Input.parse_input_event(e);await frames(1);g.direct._process(0.033)
	check(hero.direct_steering.is_empty(),"rebound movement release stops steering")
	check(g.direct.keyboard_hint().contains("I/"),"hint displays remapped movement")
	GameData.options.pad_enabled=1;PadInput.active="pad";PadInput._axes[JOY_AXIS_RIGHT_X]=0.18
	check(PadInput.stick(false,0.2)==Vector2.ZERO and PadInput.stick(false,0.1).x>0,"aim deadzone is independent and rescales stick travel")
	PadInput._axes.clear();g.direct._neutral=false;g.direct.heading=0;g.direct.tilt=0
	GameData.options.direct_pad_curve=0;GameData.options.direct_pad_x=50;GameData.options.direct_pad_y=25
	g.direct.pad_step(Vector2.ZERO,Vector2(0.5,0.5),0.1)
	check(is_equal_approx(absf(g.direct.heading),absf(g.direct.tilt)*2.0),"controller horizontal and vertical speeds are independent")
	# Simulate both short and held view chords, including modifier-first release.
	PadInput._down["mod"]=Time.get_ticks_msec()
	g.direct.pad_action("cursor","down");g.direct.pad_action("cursor","hold")
	PadInput._down.erase("mod");g.direct.pad_action("cursor","up")
	check(g.direct._pad_switch.is_empty(),"held perspective chord releases without trapping future pointer presses")
	PadInput._down["mod"]=Time.get_ticks_msec()
	g.direct.pad_action("view","down");PadInput._down.erase("mod")
	check(g.direct.pad_action("view","up") and g.direct.pad_action("view","tap"),"tactical chord consumes its tap even after modifier release")
	PadInput._down["mod"]=Time.get_ticks_msec();g.direct.pad_action("view","down");g.direct.pad_action("view","up");g.direct.pad_action("view","tap");PadInput._down.erase("mod")
	var linear:=absf(g.direct.heading);g.direct.heading=0;g.direct.tilt=0;GameData.options.direct_pad_curve=2
	g.direct.pad_step(Vector2.ZERO,Vector2(0.5,0.5),0.1)
	check(absf(g.direct.heading)<linear,"fine response reduces near-centre aiming speed")
	GameData.options.direct_pad_invert_x=1;g.direct.heading=0;g.direct.pad_step(Vector2.ZERO,Vector2.RIGHT,0.1)
	check(g.direct.heading>0,"controller horizontal inversion changes direction")
	g.direct._hit_unit=null;g.direct._update_feedback(1.0);hero.direct_hit_serial+=1;g.direct._update_feedback(0.01)
	check(g.direct._hit_until>Time.get_ticks_msec(),"confirmed hit sequence flashes the reticle")
	g.direct._hit_until=0;hero.hp-=1;g.direct._update_feedback(0.01)
	check(g.direct._hit_until==0,"unattributed HP changes never confirm a hit")
	if DisplayServer.get_name()!="headless":
		PadInput.active="kbm";panel.open();panel._tutorial.visible=false
		g.hud.visible=false;g.hud._safe_root.visible=false;g.direct._overlay.visible=false
		GameData.options.display_mode=0;GameData._window_gen+=1
		get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1152,720)
		for lang in ["en","ru","de"]:
			RemakeText.lang=lang
			for group in [24,25,26]:
				panel._show_group(group);await frames(3);await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("user://direct-settings-%s-%d.png"%[lang,group])
	panel.queue_free();g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
	print("DIRECT_SETTINGS ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
