extends "third_person_kbm.gd"
## Actual installed HD package, HUD/tutorial and direct-control camera render.
func shot(label: String) -> Image:
	await frames(3);await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://"+label+".png")
	return img
func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":3,"pad_enabled":0,"confine_mouse":0,"blood":0,"gfx_detailed_heads":1},true)
	mode="HD interface and camera"
	check(ModStore.create_profile("HD visual check",false,["community.hd-lands-textures@1.4.0"]).is_empty(),"activate existing installed package")
	check(GameData.open(GameData.root).is_empty(),"mount original data and HD overrides")
	RenderingServer.set_render_loop_enabled(true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1g",1,false);await prepare()
	hero.set_process(false);hero.set_physics_process(false);hero.pos=Vector2(69.82051,128);hero.facing=0;hero._sync_transform(0);hero._anim_lock=0
	hero.direct_controlled=true;hero._direct_joints=true;hero.refresh_figure(true)
	g.direct.heading=0;g.direct.tilt=-0.1;hero.action="idle";hero.model.act("idle",1,0)
	GameData.options.control_mode=2;g.direct.apply_camera(1.0/60)
	check(hero.model._detail!=null and hero.model.detailed_head_shown(),"smoothed model retains configured portrait head")
	check(hero.model._welded_head==null,"face and hair are rigid attachments rather than different skinning paths")
	check(g.hud.unit_panel._atlas.get_width()==2048,"HUD uses full authored HD texture")
	var image:=await shot("hd-hud")
	# Sample the panel's right frame above its bars. A 256px lookup in the
	# 2048px image sampled the bright green health bar instead of the frame.
	var k:=g.hud.unit_panel._k();var green:=0
	for y in range(int(20*k),int(180*k)):
		var c:=image.get_pixel(int(182*k),y)
		if c.g > 0.5 and c.g > c.r*2 and c.g > c.b*2:green+=1
	check(green<5,"HD panel border does not sample the green health-bar region")
	g.hud._tutorial.show_screen("options",true)
	check(g.hud._tutorial.visible,"actual tutorial is visible for button inspection")
	await shot("hd-tutorial")
	check(g.hud._tutorial._atlas.get_width()==1024,"tutorial keeps HD atlas")
	g.hud._tutorial.close()
	for act:String in ["walk","attack"]:
		hero.action=act;hero.model.act(act,1,0)
		var clip:=hero.model.player.get_animation(hero.model.player.current_animation)
		for i in [0,3,6]:
			hero.model.player.seek(clip.length*i/8.0,true);hero.model.flush_pending_pose()
			GameData.options.control_mode=3
			for tilt:float in [0.0,-1.15]:
				g.direct.tilt=tilt
				for f in 45:g.direct.apply_camera(1.0/60)
				var body:=hero.model.get_node("Skeleton/Body") as MeshInstance3D
				check(float((body.get_active_material(0) as ShaderMaterial).get_shader_parameter("ei_first_person_radius"))>0,"first-person clips only nearby controlled body")
				check(hero.model._head_hidden,"head remains hidden through moving pose")
				if i==3:await shot("first-person-%s-%s"%[act,"down" if tilt<0 else "level"])
	GameData.options.control_mode=2;g.direct.apply_camera(1.0/60)
	check(not hero.model._head_hidden,"third person restores head and hair")
	var body:=hero.model.get_node("Skeleton/Body") as MeshInstance3D
	check(float((body.get_active_material(0) as ShaderMaterial).get_shader_parameter("ei_first_person_radius"))==0,"third person removes body clipping")
	g.direct.tilt=-0.1;hero.action="walk";hero.model.act("walk",1,0);g.direct.apply_camera(1.0/60)
	await shot("third-person-walk")
	g.queue_free();s.queue_free();await frames(10)
	print("HD_INTERFACE_VIEWS ",JSON.stringify({"checks":checks,"failures":failures}));TexUpscale.shutdown();get_tree().quit(0 if failures.is_empty() else 1)
