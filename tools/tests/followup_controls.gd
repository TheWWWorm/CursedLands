extends "third_person_kbm.gd"
## Loaded campaign actors, real input dispatch and authority command handling.

func frames(n := 4) -> void:
	for i in n:
		await get_tree().process_frame
		if is_instance_valid(g) and is_instance_valid(g.rig):g.rig._window_focused=true

func press(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = down
	Input.parse_input_event(event)
	await frames(1)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0,"pad_wheel_pause":0,"blood":0},true)
	PadInput.active="kbm"; s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="follow-up controls"
	await s.enter_zone("gz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "gz1g",1,false)
	await prepare()
	var field := g.direct.field()
	var lang := RemakeText.lang
	for locale in ["ru","de"]:
		RemakeText.lang=locale
		check(RemakeText.t("Alt: aimed strike") != "Alt: aimed strike" and PadField.aim_entries().all(func(e):return e.caption != TouchActions.PARTS[e.id[1]]),"Alt controls and all body parts translated for "+locale)
	RemakeText.lang=lang
	for camera_mode in [1,2,3]:
		GameData.options.control_mode=camera_mode; reset();sky()
		await press(KEY_ALT,true)
		check(field.wheel.visible and field.wheel.entries.size()==6,"Alt opens six body parts without a gamepad in mode "+str(camera_mode))
		await frames(4) # consume the OS mouse warp generated when opening
		var point: Vector2 = field.wheel.get_global_transform_with_canvas() * field.wheel._cell_center(4)
		get_viewport().warp_mouse(point);await frames(4)
		var event:=InputEventMouseMotion.new();event.position=point
		Input.parse_input_event(event);await frames(2)
		if DisplayServer.get_name() != "headless" and camera_mode == 2:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://alt-body-parts.png")
		await press(KEY_ALT,false)
		check(not field.wheel.visible and g.held_aim()==4,"releasing Alt arms the chosen leg in mode "+str(camera_mode))
		await press(KEY_ALT,true); await press(KEY_ESCAPE,true); await press(KEY_ESCAPE,false); await press(KEY_ALT,false)
		check(not field.wheel.visible,"Escape cancels the Alt menu in mode "+str(camera_mode))
		g.cancel_touch_target()
	GameData.options.control_mode=2;reset();sky()
	g.touch_aim=3;g.direct.attack()
	check(hero.orders.size()==1 and hero.orders[0].get("aim")==3,"direct attack preserves body-part selection at authority")
	if not hero.orders.is_empty():hero.facing=Vector2(hero.orders[0].direction.x,-hero.orders[0].direction.z).angle()
	for i in 30:
		hero._tick(GameUnit.TICK)
		if hero.strike_aim==3:break
	check(hero.strike_aim==3,"committed direct strike retains aimed arm")
	reset()
	for camera_mode in [2,3]:
		GameData.options.control_mode=camera_mode
		g.direct._world=s.world;g.direct._hero=hero;g.direct._control_id=hero.uid
		s._remote_loading=true;g.direct._process(0.016)
		check(not g.direct.usable() and g.direct._control_id==-2,"remote transition defers direct registration in mode "+str(camera_mode))
		s._remote_loading=false;hero.direct_controlled=false
		await press(KEY_W,true);g.direct._process(0.016)
		check(hero.direct_controlled and not g.direct._neutral,"arrival registers control and accepts a held movement key in mode "+str(camera_mode))
		await press(KEY_W,false)
		var pos:=hero.position
		hero.position += Vector3(3,0,-2);g.direct.apply_camera()
		check(g.hud.minimap._center().distance_to(Vector2(hero.global_position.x,-hero.global_position.z))<0.001,"minimap follows direct character in mode "+str(camera_mode))
		hero.position=pos
	# Reliable event first, living snapshot later; then the local solo actor.
	reset();hero.dead=true;g.selected.clear();g.on_event({"t":"revived","uid":hero.uid})
	check(g.selected.is_empty(),"revival waits for its living snapshot")
	hero.dead=false;g._keep_selection()
	check(g.selected==[hero] and g.direct.leader()==hero,"solo revived actor regains control focus")
	var ally:=body(free_point(),0,false);ally.controller=s.my_index;ally.set_meta("hero",hero.get_meta("hero").duplicate(true))
	g.selected.assign([ally]);g.on_event({"t":"revived","uid":hero.uid})
	check(g.selected==[ally],"revival preserves another selected living actor")
	s.world.remove_unit(ally);g.selected.assign([hero])
	# Recharge is item state, and must not recreate the icon each tick.
	var icon:=ItemView.new();icon.size=Vector2(120,120);add_child(icon)
	icon.show_item("unique sword.steel|weak{it}")
	var original:=icon._model
	icon.show_item(Items.with_charge("unique sword.steel|weak{it}",20.0))
	check(icon._model==original and Items.charge(icon.item)==20.0,"charge update retains icon model and current item identity")
	icon.show_item("");check(icon._model==null,"unequipped icon is cleared")
	icon.free()
	var proto:=GameData.db.find("monster_prototypes","Human Gipath NPC Demon F7")
	if not proto.is_empty():
		var kit:=Items.info(proto.weapon)
		check(not kit.mat.is_empty(),"Demon's authored spaced material resolves")
		var demon:=EIUnitModel.create({"prototype":proto.name},true);add_child(demon)
		var club:=demon.find_child("rh3_club07",true,false)
		check(club!=null and club.find_children("*","MeshInstance3D",true,false).size()>0,"Demon carries its authored spiked club mesh")
		if club:
			var mesh:=club.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
			var mat:=mesh.get_active_material(0)
			var texture: Texture2D=mat.albedo_texture
			check(texture!=null and not texture.get_image().is_invisible(),"Demon weapon texture has visible pixels")
		demon.free()
		if DisplayServer.get_name() != "headless":
			var preview := Paperdoll.new();preview.view_size=Vector2i(500,700);preview.size=Vector2(500,700)
			add_child(preview);preview.show_info({"prototype":proto.name})
			await frames(8);await RenderingServer.frame_post_draw
			check(preview._vp.get_texture().get_image().save_png("user://demon-weapon.png")==OK,"capture original Demon equipment")
			preview.free()
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
	print("FOLLOWUP_CONTROLS ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
