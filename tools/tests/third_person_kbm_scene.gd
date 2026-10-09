extends "third_person_kbm.gd"
## Short rendered prompt/input pass, isolated from the full headless matrix.
func capture(name:String) -> void:
	g.direct._overlay.queue_redraw();await frames(8);await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("user://"+name+".png")==OK,"capture "+name)
func _ready() -> void:
	get_window().size=Vector2i(800,600)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0,"blood":0},true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="rendered campaign";await s.enter_zone("gz1g",1,false);await prepare()
	g.rig._window_focused=true;g.direct._capture(true)
	check(g.direct._captured and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"real display captures mouse for shoulder controls")
	var initial_heading:=g.direct.heading
	var motion:=InputEventMouseMotion.new();motion.relative=Vector2(32,0);Input.parse_input_event(motion);await frames(2)
	check(g.direct.heading!=initial_heading,"captured mouse motion turns shoulder view")
	g.direct.tilt=-0.12;g.direct.apply_camera();await key(KEY_1)
	await capture("third-person-self-cast")
	await key(KEY_E);check(order_target(hero),"rendered E queues self-cast")
	reset();var loot:=body(free_point());g.direct.tilt=-0.12;g.direct.apply_camera();g._pick_key=[]
	await capture("third-person-nearby-loot")
	await key(KEY_E);check(hero.has_meta("interact") and hero.get_meta("interact")[0]==loot,"rendered E queues nearby loot")
	reset();var ally:=body(free_point(2.2),0,false);ally.controller=1;ally._sync_transform(0);await aim(ally);await frames(2);await key(KEY_1)
	check(g.pick_unit(get_viewport().get_visible_rect().size*0.5,hero)==ally,"rendered native ally is under crosshair")
	await click();check(order_target(ally),"captured mouse click still heals aimed ally")
	reset();await key(KEY_TAB);g.direct._capture(false);await key(KEY_1);await key(KEY_E)
	check(g.direct.pointer and hero.orders.is_empty() and g.pending_spell=="healing{}","pointer/HUD mode prevents accidental E cast")
	await key(KEY_TAB);g.direct._neutral=false;g.direct._capture(true)
	var cancel:=InputEventMouseButton.new();cancel.button_index=MOUSE_BUTTON_RIGHT;cancel.pressed=true;Input.parse_input_event(cancel);await frames(2)
	check(g.pending_spell.is_empty(),"captured right mouse button cancels spell targeting")
	evidence.checks=checks;evidence.failures=failures;evidence.scope="Short rendered Linux 800x600 prompt and captured mouse test. Original campaign data; no Windows or ENet runtime claim."
	FileAccess.open("user://third-person-kbm-scene.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();print("THIRD_PERSON_KBM_SCENE ",checks," checks ",failures.size()," failures");get_tree().quit(0 if failures.is_empty() else 1)
