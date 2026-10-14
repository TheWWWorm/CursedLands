extends "third_person_kbm.gd"
## Rendered production-engine lifecycle probe with actual campaign scenery.
var captures:=[]
func frames(n:=4) -> void:
	for i in n:
		await get_tree().process_frame
		if is_instance_valid(g) and is_instance_valid(g.rig):g.rig._window_focused=true
func capture(label:String) -> void:
	await frames(8);await RenderingServer.frame_post_draw
	var path:="user://shadow-lifecycle-"+label+".png"
	check(get_viewport().get_texture().get_image().save_png(path)==OK,"capture "+label)
	captures.append(path)
func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	var enhanced := "--enhanced" in OS.get_cmdline_user_args()
	if enhanced:
		GameData.options.merge({"gfx_water":1,"gfx_water_reflections":2,"gfx_soft_ground":1,"gfx_terrain":1,"gfx_detailed_heads":1,"gfx_materials":1,"gfx_sharp_units":1,"gfx_far_view":1,"q_shadow_fit":1,"q_shadows":2},true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":3,"pad_enabled":0,"blood":0,"display_mode":0,"q_aa":2,"shadow_units":1,"shadow_buildings":1,"shadow_flora":1},true)
	GameData.resolution_size="1200x800";GameData.options.resolution=GameData.resolutions().find(Vector2i(1200,800));GameData._apply_window()
	get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1200,800);Engine.max_fps=60
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	if enhanced:
		await s.enter_zone("gz11k",1,false);await prepare()
		var terrain := s.world.terrain
		g.rig.camera.global_position=Vector3(173,maxf(terrain.height_at(173,267),6.4)+2.5,-267)
		g.rig.camera.look_at(Vector3(255,terrain.height_at(255,184)+1,-184))
		await frames(30)
		check(terrain._reflection and terrain._reflection.viewport and is_finite(terrain._reflection.plane),"lake establishes a reflection plane before the village transfers")
	for zone:String in ["bz8k","bz1g","bz8k"]:
		g.set_process(true);await s.enter_zone(zone,1,false);await prepare();g.set_process(false);g.hud.visible=false
		GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1200,800)
		mode=zone+" visit "+str(captures.size())
		for u:GameUnit in s.world.unit_rows():
			u.set_process(false);u.set_physics_process(false)
			if u.model:u.model.set_process(false)
		var npc:GameUnit=s.world.vm._by_name("PoorMan" if zone=="bz8k" else "Elder")
		check(npc!=null,"original scene actor exists")
		if not npc:continue
		npc.hidden=false;npc.fogged=false;npc.visible=true;npc.action="idle";npc.model.act("idle",1,0);npc.model.player.seek(0,true);npc.model.flush_pending_pose()
		hero.pos=npc.pos+Vector2(-3,2);hero._sync_transform(0);hero._anim_lock=0;hero.action="idle";hero.model.act("idle",1,0)
		g.rig.held=false;g.direct._update_view_model(hero.model);g.direct.heading=(npc.pos-hero.pos).angle();g.direct.tilt=-.22;g.direct.apply_camera(0)
		g._sun.rotation_degrees=Vector3(-40,-30,0)
		for u:GameUnit in [hero,npc]:
			for mi:GeometryInstance3D in u.model.find_children("*","GeometryInstance3D",true,false):mi.layers=1
		var origin:=hero.pos
		await capture(zone+"-"+str(captures.size())+"-before")
		for cycle in 4:
			for camera_mode:int in [2,1,3]:
				GameData.options.control_mode=camera_mode;g.direct._process(.016);g.direct.apply_camera(.016);await frames(3)
			var doll:=Paperdoll.new();doll.view_size=Vector2i(200,300);doll.size=Vector2(200,300);add_child(doll);doll.show_unit(npc)
			await frames(6);doll.free()
			for i in 20:
				hero.pos=origin+Vector2.from_angle(g.direct.heading)*sin(i*TAU/20)*1.5;hero._sync_transform(0);g.direct.apply_camera(.016);await frames(1)
		hero.pos=origin;hero._sync_transform(0);g.direct.heading=(npc.pos-hero.pos).angle();g.direct.tilt=-.22;g.direct.apply_camera(0)
		await capture(zone+"-"+str(captures.size())+"-after")
		for u:GameUnit in [npc]:
			var meshes:=u.model.find_children("*","MeshInstance3D",true,false)
			check(meshes.all(func(mi):return mi.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON and mi.layers==1),"every NPC body part retains sun casting after camera/preview cycles")
		var torso:=hero.model._view_shadows.filter(func(row):return row.source==hero.model._view_torso)
		var heads:=hero.model._view_shadows.filter(func(row):return hero.model._head.is_ancestor_of(row.source) and row.shadow.visible)
		check(torso.size()==1 and torso[0].shadow.visible and not heads.is_empty(),"local first-person torso and head both cast after camera/preview cycles")
		g.direct._update_view_model(null)
		check(hero.model._view_shadows.all(func(row):return not row.shadow.visible and row.source.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON),"leaving first person restores each source and hides every proxy")
	print("SHADOW_LIFECYCLE ",checks," checks ",failures.size()," failures ",failures," captures=",captures)
	FileAccess.open("user://shadow-lifecycle.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"assertions":evidence.assertions},"\t"))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
