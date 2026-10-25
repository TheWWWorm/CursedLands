extends "res://tools/tests/path_trace_camera_routes.gd"
## Original animated hero seen from behind at 4K, 50% raster, 50% PT.
## Readbacks are outside the motion sequence; this is a visual check, not FPS.
func run() -> void:
	seed(7321);map_name="zone1";resolution=Vector2i(3840,2160)
	var dlss:=OS.get_cmdline_user_args().has("--pt-dlss")
	var context:=await setup_route()
	if context.is_empty():get_tree().quit(1);return
	var game: Game=context[1];var session: Session=context[0]
	var hero: GameUnit=session.party_heroes()[0]
	for unit: GameUnit in game.world.units.values():
		unit.process_mode=Node.PROCESS_MODE_DISABLED
		if unit!=hero:unit.hide()
	hero.show();hero.rotation=Vector3(0,PI,0)
	var torso: MeshInstance3D
	for mesh: MeshInstance3D in hero.model.find_children("*","MeshInstance3D",true,false):
		if mesh.get_parent().name=="bd":torso=mesh;break
	check(torso!=null,"authored hero torso exists")
	if torso==null:get_tree().quit(1);return
	GameData.options.merge({"gfx_sharp_units":1,"character_light":1,"rtx_upscaling":4 if dlss else 0},true)
	game._apply_options();session.state.world_time=17.75;game._update_daylight(false)
	get_viewport().scaling_3d_scale=0.5
	if dlss:
		RtxGraphics.apply_upscaling(get_viewport())
		check(RtxGraphics.sr_active(),"DLSS Performance is available")
	var rt: Node=game.get_node("SceneRaytrace")
	var origin:=hero.global_position
	var focus:=origin+Vector3.UP
	camera.global_position=focus+Vector3(0,1,4);camera.look_at(focus)
	check(await ready_scene(rt),"third-person dusk scene prepares PT")
	check(rt.stats.get("size",[])==[960,540],"character trace lattice matches low/Performance")
	if not rt.stats.get("active",false):get_tree().quit(1);return
	hero.model.act("walk",1,0.0)
	var inactive:=0;var rejected_history:=0;var animated_updates:=0
	var sdk_start:=int(RtxGraphics.bridge().call("get_status").get("dlss_evaluations",0)) if dlss else 0
	for mode: String in ["held","walk","pan"]:
		for i in 48:
			if mode=="walk":
				hero.global_position=origin+Vector3(float(i)*0.01,0,0)
				hero.model.player.advance(1.0/30.0);hero.model.flush_pending_pose()
			focus=hero.global_position+Vector3.UP
			camera.global_position=focus+Vector3(sin(i*0.04)*0.3 if mode=="pan" else 0.0,1,4);camera.look_at(focus)
			session.state.world_time+=1.0/30.0/CampaignState.HOUR_SECONDS;game._update_daylight(false)
			await frames(1)
			if not rt.stats.get("active",false) or not rt.device.nrd_active:inactive+=1
			if not rt.stats.get("history_reused",false):rejected_history+=1
			if mode=="walk" and rt.stats.get("updated_instances",0)>0:animated_updates+=1
		await save_buffers(rt,mode)
	check(inactive==0,"PT and NRD remain active through held, walking and panning views")
	check(animated_updates>=46,"actual articulated geometry updates during walking")
	check(rejected_history==0,"ordinary dusk clock and character movement retain lighting history")
	var status: Dictionary=RtxGraphics.bridge().call("get_status") if dlss else {}
	if dlss:
		check(int(status.get("dlss_evaluations",0))-sdk_start>=144,"SDK evaluates DLSS throughout character motion")
		check(int(status.get("last_error",-1))==0 and RtxGraphics.sr_active(),"DLSS remains active without SDK errors")
	# Instrument the production receiver after its normal material evaluation.
	# AgX desaturates primaries: compare channel dominance, not exact RGB bytes.
	var original:=torso.material_override
	var material:=torso.get_active_material(0).duplicate() as ShaderMaterial
	var shader:=Shader.new()
	shader.code=Gfx._function_tail(material.shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment","ALBEDO=vec3(1.0-ei_pt_blend,ei_pt_blend,1.0-ei_pt_blend);EMISSION=vec3(0);FOG=vec4(0);")
	material.shader=shader;torso.material_override=material
	await ready_scene(rt);await frames(20)
	var coverage:=[]
	for i in 8:
		hero.model.player.advance(1.0/30.0);hero.model.flush_pending_pose();await frames(2);await RenderingServer.frame_post_draw
		var screen:=get_viewport().get_texture().get_image()
		var point:=Vector2i(camera.unproject_position(torso.global_transform*torso.get_aabb().get_center()))
		var matched:=0;var missed:=0
		for y in range(point.y-90,point.y+90,2):
			for x in range(point.x-90,point.x+90,2):
				var c:=screen.get_pixel(x,y)
				if c.g>c.r+0.15 and c.g>c.b+0.15:matched+=1
				# Magenta distinguishes a rejected torso from warm skin/cloth.
				if c.r>c.g+0.15 and c.b>c.g+0.15:missed+=1
		coverage.append({"matched":matched,"missed":missed})
		if i==7:screen.save_png(out.path_join("back-receiver-coverage.png"))
	check(coverage.all(func(row: Dictionary):return row.matched>100 and float(row.missed)/maxi(row.matched+row.missed,1)<0.01),"animated back consistently receives PT lighting")
	torso.material_override=original
	FileAccess.open(out.path_join("character-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"stats":rt.stats,"dlss":status,"receiver_coverage":coverage,"inactive":inactive,"history_resets":rejected_history,"animated_updates":animated_updates},"\t"))
	game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
	print("CHARACTER_LIVE ",checks," checks ",failures.size()," failures");get_tree().quit(0 if failures.is_empty() else 1)
