extends "coop_story.gd"
## Prepared native arrival, then the actual opening briefing on ENet peers.
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func frames(n:=4) -> void:
	for i in n:await get_tree().process_frame
func reachable(w: GameWorld,u: GameUnit,from: Vector2) -> bool:
	if u.pos.distance_to(from)<.25:return true
	var path:=w.nav.find_path(from,u.pos,w.unit_rows(),[],0.0,u.move_class(),true)
	return not path.is_empty() and path[-1].distance_to(u.pos)<.25
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"control_mode":1},true)
	var h:=branch("Host",true);host=h.s;hg=h.g
	var c:=branch("Client",false);client=c.s;cg=c.g
	check(host.host(29970,2)==OK,"open cage host");GameData.player_name="Cage Guest"
	check(client.join("127.0.0.1",29970)==OK,"connect cage guest")
	check(await until(func():return host.players.size()==2),"both peers registered")
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Cage Guest")
	host.state.create_party("HeroAlone");host.state.add_party_unit("HeroAlone","Hero","Human Hero Hadagan")
	host.state.copy_stats("Hero","HeroAlone::Hero");host.state.set_current_party("HeroAlone")
	await host.enter_zone("bz13h",1,false)
	check(await until(func():return client.world!=null and client.zone_id=="bz13h" and not client._remote_loading),"native prison loads on both peers")
	var hero:GameUnit=host.party_units(0)[0]
	for peer:Session in [host,client]:
		for actor:GameUnit in peer.world.party_units():
			if actor.has_meta("hero") and not actor.get_meta("hero").has("merc"):
				check(actor.model.get_meta("peaceful_gear",false),"protagonist has peaceful presentation on peer %d" % peer.my_index)
	check(absf(angle_difference(hero.facing,deg_to_rad(95)-GameUnit.MODEL_YAW_OFFSET))<.001,"native deployment quaternion uses #deployangle independently of camera")
	var original:={}
	for row:Dictionary in host.world.map.mob.objects:
		if row.kind=="UNIT" and row.name in ["Karh","IZ"]:original[int(row.nid)]=Vector2(row.position.x,row.position.y)
	check(original.size()==2,"both original outside speakers are present")
	host.state.set_var(0,"b.bz13h.Hns59",1)
	check(await until(func():return host.world.vm.briefings.active=="b.bz13h.Hns59" and cg.hud._dialog.visible),"authored introduction starts on both peers")
	host.world.set_process(false);host.world.set_physics_process(false)
	host._send_snapshot_records(host.world.unit_rows().map(func(u):return u.snapshot()),host.world.time)
	await frames(12)
	var trace:=[]
	for id:int in original:
		var u:GameUnit=host.world.units[id]
		check(reachable(host.world,u,original[id]),"outside speaker stays on accessible side of locked cage: "+String(u.info.name))
		var remote:GameUnit=client.world.units.get(id)
		check(remote!=null and remote.pos.distance_to(u.pos)<.1,"guest sees same speaker position: "+String(u.info.name))
		trace.append({"name":u.info.name,"from":str(original[id]),"to":str(u.pos)})
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://suslanger-opening.png")
	print("CAGE_PLACEMENTS ",JSON.stringify(trace))
	host.multiplayer.multiplayer_peer.close();client.multiplayer.multiplayer_peer.close()
	for root:Node in branches:root.queue_free()
	await frames(8);TexUpscale.shutdown()
	print("SUSLANGER_CAGE ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)
func _process(_dt:float) -> void:pass
