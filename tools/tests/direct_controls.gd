extends Node
## Loaded camp, native model/animations and real input routing. Run rendered
## for screenshots/capture checks, headless for command/camera assertions.
var checks := 0
var failures := 0
var game: Game
var session: Session

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame

func key(code: Key, down: bool) -> void:
	var e := InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down
	Input.parse_input_event(e)

func axis(which: JoyAxis, amount: float) -> void:
	var e := InputEventJoypadMotion.new();e.device=42;e.axis=which;e.axis_value=amount
	Input.parse_input_event(e)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":2,"enemy_hp_bars":0,"pad_glyphs":1},true)
	if OS.get_name()=="Android":
		GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
		GameData.options_changed.emit()
	session=Session.new();add_child(session)
	game=Game.new();game.session=session;session.game=game;add_child(game)
	session.set_physics_process(false)
	session.state=CampaignState.new();session.state.ensure_hero(0,"Human Hero")
	await session.enter_zone("bz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "bz1g",1,false)
	var world := session.world
	world.set_physics_process(false);world.set_process(false);world.vm.instances.clear()
	var hero: GameUnit=session.party_units(0)[0]
	hero.blocked=false;hero.order={};hero.orders.clear();hero._anim_lock=0.0
	game.selected.assign([hero]);game.rig.release()
	await frames(12)
	var direct := game.direct
	print("DIRECT_SCENE hero=",hero.pos," usable=",direct.usable()," bars=",EnemyBars.of(game).active())
	check(hero.direct_controlled,"idle combat AI is suspended for the controlled hero")
	check(direct.active() and direct.usable(),"experimental mode is active in a real camp")
	check(is_equal_approx(game.rig.camera.fov,65.0) and is_equal_approx(game.rig.camera.near,0.08),"shoulder camera uses its own lens")
	check(EnemyBars.of(game).active(),"experimental bars stay on even with classic enemy-bar option off")
	var entries := EnemyBars.of(game).entries()
	check(entries.any(func(row):return row[0]==hero and row[1]==1.0),"hero at full health has a persistent bar")
	var at := game.rig.camera.global_position
	var pivot := hero.global_position+Vector3.UP*clampf(hero.figure_half_z*1.6,0.6,2.8)
	check(at.distance_to(pivot)<=6.5 and at.distance_to(pivot)>0.1,"camera is behind the shoulder at close range")
	check(DirectCombat.point_clear(world,at),"actual camp camera does not sit in a solid span or floor")
	if DisplayServer.get_name()=="headless": direct._captured=true # route mouse events without OS capture
	var face := direct.heading
	var motion := InputEventMouseMotion.new();motion.relative=Vector2(60,-20)
	Input.parse_input_event(motion);await frames()
	check(not is_equal_approx(direct.heading,face),"mouse motion turns shoulder view")
	if DisplayServer.get_name()=="headless": direct._captured=false
	var d := direct.ground_direction(Vector2(0,-1))
	check(d.is_equal_approx(Vector2.from_angle(direct.heading)),"forward movement follows camera heading")
	GameData.options.pad_enabled=0
	key(KEY_W,true);await frames()
	check(hero.orders.size()>0 and hero.orders[-1].type=="direct_move" and hero.orders[-1].direction.is_equal_approx(d),"W sends camera-relative steering through the host")
	check(hero.orders[-1].get("village_limit",Vector3.ZERO)==session.village_move_limit(),"W retains the scripted camp boundary")
	key(KEY_W,false);await frames()
	check(hero.orders.is_empty() and hero.order.is_empty(),"releasing W stops steering without a return-to-position order")
	key(KEY_TAB,true);key(KEY_TAB,false);await frames()
	check(direct.pointer and not direct._captured,"Tab frees pointer for the HUD")
	key(KEY_TAB,true);key(KEY_TAB,false);await frames()
	check(not direct.pointer,"Tab returns to camera controls")
	# Input held across a loading overlay must not become a new-map movement.
	session.loading_game=true;key(KEY_W,true);await frames()
	session.loading_game=false;hero.orders.clear();hero.order={};await frames()
	check(hero.orders.is_empty() and direct._neutral,"held movement cannot cross a loading boundary")
	key(KEY_W,false);await frames()
	check(not direct._neutral,"releasing movement rearms direct controls")
	var held := Transform3D(Basis.IDENTITY,Vector3(4,9,5))
	game.rig.held=true;game.rig.camera.global_transform=held
	await frames()
	check(game.rig.camera.global_transform==held and not direct._captured,"dialogue/cutscene view owns the camera and pointer")
	game.rig.held=false;await frames()
	hero.orders.clear();hero.order={};hero._attack_cd=0;hero._anim_lock=0
	var click := InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	Input.parse_input_event(click);await frames()
	click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=false
	Input.parse_input_event(click);await frames()
	check(hero.orders.is_empty() and hero._pending_hit.is_empty(),"mouse attack cannot swing in the safe zone")
	GameData.options.pad_enabled=1
	axis(JOY_AXIS_TRIGGER_RIGHT,1.0);await frames()
	check(hero.orders.is_empty() and hero._pending_hit.is_empty(),"gamepad attack cannot swing in the safe zone")
	axis(JOY_AXIS_TRIGGER_RIGHT,0.0);PadInput.release_all();await frames()
	var spells: Array=hero.get_meta("hero").spells
	spells.append("healing{}");game.begin_cast(spells.size()-1)
	check(game.pending_spell.is_empty(),"third-person spell selection stays disabled in the safe zone")
	# Continue the positive combat checks in a real field area.
	await session.enter_zone("gz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "gz1g",1,false)
	world=session.world;world.set_physics_process(false);world.set_process(false);world.vm.instances.clear()
	hero=session.party_units(0)[0];hero.blocked=false
	game.selected.assign([hero]);game.rig.release();await frames(12)
	# Native attack animation schedules one actual impact without a target.
	hero.orders.clear();hero.order={};hero._attack_cd=0;hero._anim_lock=0;hero.alert=true
	hero.stance=GameUnit.STANCE_NONE;hero.facing=0;hero._update_pose();hero._anim_lock=0
	session.apply_command({"t":"direct_attack","units":[hero.uid],"direction":Vector3.RIGHT},0)
	for i in 80:
		hero._tick(GameUnit.TICK)
		if hero._pending_hit.has("direction"): break
	check(hero.action=="attack" and hero._pending_hit.has("direction"),"native model schedules a directional impact")
	check(hero.path.is_empty() and hero._goal==Vector2.INF,"swing never creates a pursuit route")
	var cooldown := hero._attack_cd
	session.apply_command({"t":"direct_attack","units":[hero.uid],"direction":Vector3.LEFT},0)
	check(hero.orders.is_empty() and hero._attack_cd==cooldown,"holding attack cannot reset a committed swing")
	hero._sync_transform(0.0);direct.heading=hero.facing
	if DisplayServer.get_name()!="headless":
		await frames(12);await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("user://third-person-field.png")==OK,"shoulder view screenshot saved")
		print("DIRECT_IMAGE ",ProjectSettings.globalize_path("user://third-person-field.png"))
	GameData.options.control_mode=1;await frames()
	check(not hero.direct_controlled,"classic switch restores ordinary idle combat AI")
	check(not direct.active() and not direct._captured,"classic switch releases captured mouse")
	check(game.rig.camera.fov==CameraRig.MODERN_FOV,"classic switch restores its lens")
	GameData.options.pad_enabled=1
	GameData.options.control_mode=0;PadInput._set_active("kbm");await frames()
	hero.order={};hero.orders.clear();hero._anim_lock=0;hero._pending_hit={};hero._attack_cd=0
	axis(JOY_AXIS_LEFT_Y,-0.8);await frames()
	check(direct.active(),"gamepad automatically activates the experimental mode")
	check(not hero.orders.is_empty() and hero.orders[-1].type=="direct_move","first gamepad stick input immediately steers")
	axis(JOY_AXIS_LEFT_Y,0);await frames()
	check(hero.orders.is_empty(),"releasing gamepad stick stops steering")
	var yaw := direct.heading
	direct.pad_step(Vector2.ZERO,Vector2(1,0.5),0.1)
	check(direct.heading!=yaw,"gamepad right stick looks rather than zooming")
	axis(JOY_AXIS_TRIGGER_RIGHT,1.0);await frames()
	check(direct._fire and hero.orders.size()==1 and hero.orders[0].type=="direct_attack","RT routes through real gamepad input to direct attack")
	axis(JOY_AXIS_TRIGGER_RIGHT,0.0);await frames()
	check(not direct._fire,"releasing RT ends repeat attacks")
	axis(JOY_AXIS_TRIGGER_LEFT,1.0);axis(JOY_AXIS_TRIGGER_RIGHT,1.0);await frames()
	check(direct.field().wheel.visible and direct.field().wheel_kind()=="system","LT plus RT retains the system wheel")
	axis(JOY_AXIS_TRIGGER_RIGHT,0.0);axis(JOY_AXIS_TRIGGER_LEFT,0.0)
	direct.field().close_wheel();PadInput.release_all();await frames()
	GameData.options.control_mode=1;await frames()
	check(not direct.active(),"classic mode remains available with a gamepad")
	PadInput.active="kbm"
	game.queue_free();session.queue_free();await frames()
	FileAccess.open("user://direct-controls.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"connected_gamepads":Input.get_connected_joypads().map(func(id):return {"id":id,"name":Input.get_joy_name(id),"guid":Input.get_joy_guid(id)})}))
	print("DIRECT_CONTROLS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
