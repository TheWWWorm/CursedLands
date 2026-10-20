extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func frames(n:=8)->void:
	for i in n:await get_tree().process_frame
func _ready()->void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"display_mode":0,"auto_graphics":0},true)
	await frames(24);GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;await frames();get_window().size=Vector2i(1280,800)
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g);s.set_physics_process(false)
	s.state.ensure_hero(0,"Human Hero")
	for key in s.campaign.zones:print("ZONE_TITLE ",key," ",s.campaign.zones[key].get("name",""))
	await s.enter_zone("gz19h",1,false)
	var w:=s.world;w.vm.instances.clear();g.hud.hide();g.rig.set_process(false);g.direct.set_process(false)
	var pool:Node3D=w.objects[44292]
	var waters:=pool.find_children("BasinWater","MeshInstance3D",true,false)
	check(waters.size()==1,"authored lion basin uses a separate water surface")
	var focus:=pool.global_position+Vector3(0,1,0)
	g.rig.hold_view(focus+Vector3(7,7,9),focus)
	if DisplayServer.get_name()!="headless":
		for enabled in [false,true]:
			GameData.options.gfx_water=int(enabled);GameData.options_changed.emit();await frames(30);await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://suslanger-pool-%s.png"%str(enabled))
		check(waters[0].material_override is ShaderMaterial,"basin follows new-water setting")
	await s.enter_zone("bz16h",1,false)
	w=s.world;w.set_process(false);w.set_physics_process(false);w.vm.instances.clear();g.hud.hide();g.rig.set_process(false);g.direct.set_process(false)
	var b:=w.vm.briefings;var parsed:=Briefings.parse(GameData.text("briefing jf67"));var cast:=b.cast(parsed.actors,null,0)
	b._face(cast,true)
	for key in ["a","b"]:
		var u:GameUnit=w.units[cast[key]]
		check(absf(cast.at_z[key]-w._stand_z(u.pos))<.0001,"dialogue uses logical ground height after instant placement")
		u._sync_transform()
	for n in [9,10]:
		var shot:=DialogCamera.shot(w,cast,{"camera":n},false)
		check(shot[0].z>w.ground_at(shot[0].x,shot[0].y),"conversation eye remains above terrain")
		g.rig.hold_view(EISpace.vec(shot[0]),EISpace.vec(shot[1]))
		if DisplayServer.get_name()!="headless":
			await frames(20);await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://baluddin-camera-%d.png"%n)
	print("SUSLANGER_VISUALS ",checks," checks ",failures," failures")
	g.queue_free();s.queue_free();await frames();TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
