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
	await key(KEY_F6)
	check(GameData.option("control_mode")==3 and is_equal_approx(g.direct.heading,0.8),"F6 switches third to first person and preserves look direction")
	check(hero.orders==orders and g.selected==selection,"perspective switch preserves selected hero and orders")
	await key(KEY_F6);g.direct._process(0.0)
	check(not g.direct.active() and hero.orders==orders and g.selected==selection,"tactical switch preserves selection and ordinary orders")
	await key(KEY_F6);g.direct._process(0.0)
	check(GameData.option("control_mode")==2 and hero.orders==orders,"F6 cycles from top-down to third person")
	await key(KEY_F6)
	check(g.direct.first_person(),"F6 completes the three-mode cycle")
	await key(KEY_V)
	check(g.direct.first_person() and EIKeymap.key_of("direct_perspective",2).is_empty(),"V no longer switches camera modes")
	g.hud._inventory.visible=true;await key(KEY_F6)
	check(g.direct.first_person(),"perspective binding cannot switch beneath inventory")
	g.hud._inventory.visible=false
	await posture_cases()
	GameData.options.control_mode=3
	var defaults:=EIKeymap.bindings(2);var classic:=EIKeymap.bindings(0)
	var panel:=OptionsPanel.new();add_child(panel);panel.open();panel._tutorial.visible=false
	panel._show_group(OptionsPanel.DIRECT_GROUP)
	check(panel._rows[0].name=="direct_fov_first" and panel._rows[11].to==26 and panel._rows[12].to==25,"direct settings page exposes camera, controller and key pages")
	check(panel._rows[7].name=="direct_first_person_actions" and panel._values.direct_first_person_actions==1,"first-person actions appear on the camera page and default to On")
	panel._set_value("direct_first_person_actions",0);panel._close()
	check(GameData.option("direct_first_person_actions")==1,"cancel leaves action perspective unchanged")
	panel.open();panel._tutorial.visible=false
	panel._set_value("direct_first_person_actions",0)
	panel._show_group(OptionsPanel.DIRECT_KEYS_GROUP)
	panel._assign("direct_forward",EIKeymap.scan_code(KEY_I))
	check(panel._key_profiles[0]==classic,"rebinding direct movement leaves tactical bindings unchanged")
	panel._values.direct_fov_first=8;panel._values.direct_fov_third=2
	panel._values.direct_mouse_first=75;panel._values.direct_mouse_third=25
	panel._apply();panel._close()
	EIKeymap._direct_loaded=false
	check(EIKeymap.bindings(2).get(EIKeymap.scan_code(KEY_I))=="direct_forward","direct binding survives reloading its separate file")
	var cfg:=ConfigFile.new();check(cfg.load(GameData.CONFIG_PATH)==OK and cfg.get_value("options","direct_fov_first")==8,"FOV settings are persisted")
	check(cfg.get_value("options","direct_first_person_actions")==0 and GameData.option("direct_first_person_actions")==0,"applying Off persists the action perspective preference")
	panel.open();panel._tutorial.visible=false;panel._set_value("direct_first_person_actions",1);panel._apply();panel._close()
	cfg.load(GameData.CONFIG_PATH)
	check(cfg.get_value("options","direct_first_person_actions")==1 and GameData.option("direct_first_person_actions")==1,"applying On persists the action perspective preference")
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
	for lang in ["en","ru","de"]:
		RemakeText.lang=lang;panel._show_group(OptionsPanel.DIRECT_GROUP)
		var row: Dictionary=panel._rows[7]
		check(row.label==RemakeText.t("First-person actions") and panel.text_width(row.label,1)<=260,"action label is localized and fits in "+lang)
		check(row.tip.contains(RemakeText.t(GameData.REMAKE_OPTIONS.direct_first_person_actions[1])),"action help is localized in "+lang)
		for value in [0,1]:
			panel._values.direct_first_person_actions=value
			check(panel._switch_text(row)==RemakeText.t("On" if value else "Off") and panel.text_width(panel._switch_text(row),1)<=160,"action choice %d is localized and fits in %s"%[value,lang])
	if DisplayServer.get_name()!="headless":
		PadInput.active="kbm";panel.open();panel._tutorial.visible=false
		g.hud.visible=false;g.hud._safe_root.visible=false;g.direct._overlay.visible=false
		GameData.options.display_mode=0;GameData._window_gen+=1
		get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1152,720)
		for lang in ["en","ru","de"]:
			RemakeText.lang=lang
			for group in [24,25,26]:
				panel._show_group(group)
				if group==24:panel._sel=7
				await frames(3);await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("user://direct-settings-%s-%d.png"%[lang,group])
		get_window().size=Vector2i(800,600);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		for lang in ["en","ru","de"]:
			RemakeText.lang=lang;panel._show_group(OptionsPanel.DIRECT_GROUP);panel._sel=7
			GameData._tips.delay=0.001
			await frames(3)
			Input.warp_mouse(panel.get_global_transform_with_canvas()*panel.p8(Vector2(400,panel._row_y(7)+10)))
			await frames(5);GameData._tips._since=0;GameData._tips._process(0)
			await RenderingServer.frame_post_draw
			var tip:=GameData._tips
			check(tip._panel.visible and tip._text==panel._rows[7].tip,"action tooltip is displayed in "+lang)
			check(get_viewport().get_visible_rect().encloses(tip._panel.get_rect()),"action tooltip fits the 800x600 viewport in "+lang)
			get_viewport().get_texture().get_image().save_png("user://direct-settings-help-%s.png"%lang)
	panel.queue_free();g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
	print("DIRECT_SETTINGS ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func posture_cases() -> void:
	hero.set_process(false);hero.set_physics_process(false)
	for camera_mode in [2,3]:
		GameData.options.control_mode=camera_mode
		for start in [2,1]:
			reset();hero.restore_gait(start);hero._anim_lock=0
			var e:=InputEventKey.new();e.physical_keycode=KEY_CTRL;e.keycode=KEY_CTRL;e.pressed=true
			Input.parse_input_event(e);await frames(1)
			g.direct._advance_posture(DirectControl.PRONE_HOLD+.01)
			check(hero.gait()==0,"held Ctrl lies down from posture %d in view %d"%[start,camera_mode])
			e=InputEventKey.new();e.physical_keycode=KEY_CTRL;e.keycode=KEY_CTRL
			Input.parse_input_event(e);await frames(1)
			check(hero.gait()==0,"release after hold preserves prone posture")
			hero._anim_lock=0;await key(KEY_CTRL)
			check(hero.gait()==2,"tap Ctrl stands up from prone")
			hero._anim_lock=0;await key(KEY_CTRL)
			check(hero.gait()==1,"tap Ctrl still crouches")
		reset();hero.restore_gait(2);hero._anim_lock=0
		var e:=InputEventKey.new();e.physical_keycode=KEY_CTRL;e.keycode=KEY_CTRL;e.pressed=true
		Input.parse_input_event(e);await frames(1)
		g.direct.pointer=true;g.direct._advance_posture(1.0)
		e=InputEventKey.new();e.physical_keycode=KEY_CTRL;e.keycode=KEY_CTRL
		Input.parse_input_event(e);await frames(1)
		check(hero.gait()==2,"releasing pointer cancels an unfinished posture hold")
		g.direct.pointer=false
	reset();hero.restore_gait(2)
