extends "story_coop_traps_net.gd"
## Issue #2: original Ingos scripts and figures, real ENet commands/events,
## near-object use, pose completion, reload and late join. Combat is held.
const Rects = preload("res://src/ui/mesh_screen_rect.gd")
var zone := "gz11k"
var report := {"cases": []}

func loaded() -> bool:
	return client.world != null and client.zone_id == zone and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game \
		and client._pool_epoch == host._load_serial

func connect_guest() -> bool:
	client = branch(true); GameData.player_name = "Ingos Guest"
	check(client.join("127.0.0.1",29949)==OK,"connect Ingos guest")
	var ready := await until(loaded)
	check(ready,"guest receives " + zone)
	if ready: freeze(client)
	return ready

func aim(s: Session, nid: int) -> void:
	var cam := s.game.rig.camera
	var obj: Node3D = s.world.objects[nid]
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE; cam.fov=45
	cam.global_position = obj.global_position + Vector3(9,10,12)
	cam.look_at(obj.global_position + Vector3.UP,Vector3.UP)
	cam.reset_physics_interpolation()

func pick_case(s: Session, nid: int) -> void:
	aim(s,nid); await frames(2)
	var cam := s.game.rig.camera
	var obj: Node3D = s.world.objects[nid]
	var origin := cam.unproject_position(obj.global_position + Vector3.UP*0.6)
	var candidates := 0; var hits := 0
	for part in obj.find_children("*","MeshInstance3D",true,false):
		var rect := Rects.of(part,cam)
		if rect.size.x < 4 or rect.size.y < 4: continue
		var point := Vector2(rect.position)+Vector2(rect.size)*0.5
		if point.distance_to(origin)<=45: continue
		candidates+=1
		if s.game.pick_lever(point)==nid: hits+=1
	report.cases.append({"zone":zone,"nid":nid,"part_targets":candidates,"picked":hits})
	check(candidates>0,"actual figure has visible parts outside old 40-pixel origin target: "+str(nid))
	check(candidates==hits,"visible mechanism parts accept selection: "+str(nid))
	obj.hide()
	check(s.game.pick_lever(origin)!=nid,"hidden mechanism cannot be selected: "+str(nid))
	obj.show()
	var start := Time.get_ticks_usec()
	for i in 100:s.game.pick_lever(origin+Vector2(i%20-10,i%13-6))
	print("PICK_COST ",nid," mean_us=",(Time.get_ticks_usec()-start)/100.0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		s.game.get_viewport().get_texture().get_image().save_png("user://ingos-"+str(nid)+".png")

func place_near(u: GameUnit, nid: int) -> bool:
	var w := host.world
	var obj: Node3D = w.objects[nid]
	var p: Vector3 = obj.get_meta("ei").position
	var at := Vector2(p.x,p.y)
	var reach := w.vm._interact_reach(u,obj)
	for i in 32:
		var q := at+Vector2.from_angle(float(i)*TAU/32.0)*(reach-0.05)
		if not w.nav.cell_open(q,u.move_class()): continue
		u.pos=q;u.resync_drawn();u.blocked=false;u._anim_lock=0;u.command({"type":"wait","t":0.0});u.order={};u.orders.clear()
		w.nav.track_unit(u)
		return true
	return false

func use_case(nid: int) -> void:
	var u := visitor()
	check(place_near(u,nid),"walkable in-reach approach exists: "+str(nid))
	var point := u.pos
	check(await sync_visitor(u),"guest receives operator placement: "+str(nid))
	client.submit({"t":"use_lever","target":nid,"units":[u.uid]})
	check(await until(func():return u.has_meta("interact"),2),"real guest command reaches authority: "+str(nid))
	var actions := []
	for i in 160:
		host.world.time+=GameUnit.TICK;u.tick(GameUnit.TICK);host.world.vm.tick(GameUnit.TICK)
		if not actions.has(u.action):actions.append(u.action)
		if host.world.levers[nid].state==1:break
	check(host.world.levers[nid].state==1,"normal approach/use opens original mechanism: "+str(nid))
	check(actions.any(func(a):return a.begins_with("anim:")),"operator plays native use clips: "+str(nid))
	check(await until(func():return client.world.levers[nid].state==1,2),"guest receives mechanism opening: "+str(nid))
	check(await until(func():return is_equal_approx(host.world.lever_sys.figure_t(nid),1.0) and is_equal_approx(client.world.lever_sys.figure_t(nid),1.0),4),"both figures finish opening without reload: "+str(nid))
	report.cases.append({"zone":zone,"nid":nid,"start":str(point),"actions":actions,"host_t":host.world.lever_sys.figure_t(nid),"guest_t":client.world.lever_sys.figure_t(nid)})


func corpse_case() -> void:
	var u := visitor()
	var rec := u.info.duplicate(true);rec.nid=0;rec.name="Ingos loot regression";rec.erase("controller")
	var body := host.world.spawn_unit(rec);body.controller=-1;body.pos=u.pos+Vector2(0.6,0);body.lie_dead();body.set_meta("loot",["money[7]"])
	host.announce_unit(body)
	check(await until(func():return client.world.units.has(body.uid),2),"guest receives lootable body")
	u.blocked=false;u._anim_lock=0;u.order={};u.orders.clear()
	client.submit({"t":"loot","target":body.uid,"units":[u.uid]})
	check(await until(func():return u.has_meta("interact"),2),"guest loot command reaches authority")
	var animated := false
	for i in 160:
		host.world.time+=GameUnit.TICK;u.tick(GameUnit.TICK);host.world.vm._check_interactions()
		animated=animated or u.action.begins_with("anim:")
		if host.world.looted.has(body.uid):break
	check(animated,"loot executes native pickup animation")
	check(host.world.looted.has(body.uid),"loot completes through its animation callback")
	check(await until(func():return not client.world.units.has(body.uid),2),"completed pickup removes body on guest")

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for opt in GameData.OPTIONS:
		if String(opt[0]).begins_with("gfx_"):GameData.options[opt[0]]=0
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":1,"scroll_border":0,"confine_mouse":0},true)
	TutorialPanel.auto_show=false
	GameData.resolution_size="1280x800";GameData.options.display_mode=0;GameData._apply_window()
	host=branch(false);check(host.host(29949,2)==OK,"open Ingos host")
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.set_physics_process(false)
	host.state.set_var(0,"q.gz11k.q50ak",1)
	await host.enter_zone(zone,1,false);freeze(host);ticks(6)
	check(not host.world.lever_sys.usable(3705),"labyrinth entrance starts locked by its authored script")
	if not await connect_guest():await finish();return
	check(not client.world.lever_sys.usable(3705),"guest initially sees the locked entrance")
	host.state.set_var(0,"b.YCF.Yc47",2);ticks(6)
	check(host.world.lever_sys.usable(3705),"original briefing-complete script unlocks labyrinth entrance")
	check(await until(func():return client.world.lever_sys.usable(3705),1),"script unlock reaches current guest without reload")
	await pick_case(client,3705);await pick_case(client,3706)
	await use_case(3705);await use_case(3706);await use_case(4044)
	await corpse_case()
	check(host.state.get_var(0,"q.gz11k.q50ak")==2,"original two-gate labyrinth objective completes")
	check(host.save_game("ingos-open")==OK,"save opened Ingos mechanisms")
	check(await host.load_game_shown("ingos-open"),"reload Ingos mechanisms")
	freeze(host);check(await until(loaded),"guest receives reloaded Ingos mechanisms");freeze(client)
	check(client.world.lever_sys.usable(3705),"reloaded zone snapshot carries changed interaction lock")
	check(client.world.levers[4044].state==1 and is_equal_approx(client.world.lever_sys.figure_t(4044),1.0),"opened chest retains logical and visual state after reload")
	client.multiplayer.multiplayer_peer.close()
	var old: Node=branches.back();branches.erase(old);old.queue_free()
	check(await until(func():return host.players.size()==1),"host observes guest disconnect")
	if not await connect_guest():await finish();return
	check(client.world.lever_sys.usable(3705),"late join receives the already-unlocked labyrinth gate")
	# The honorary elder's actual locked prison and key use a separate map.
	zone="gz13k";host.state.set_var(0,"q.gz13k.q46k",1)
	await host.enter_zone(zone,1,false);freeze(host);check(await until(loaded),"guest follows host to elder's map");freeze(client);ticks(6)
	var u := visitor()
	check(not host.world.vm._lever_science_ok(u,4216),"elder's prison refuses use without its key")
	for row in GameData.db.table("quest_items"):
		if int(row.get("script_id",0))==32:host.state.quest_items[String(row.name).to_lower()]=true
	check(host.world.vm._lever_science_ok(u,4216),"authored key 32 opens elder's prison")
	await pick_case(client,4216);await use_case(4216);ticks(6)
	check(host.state.get_var(0,"q.gz13k.q46k")==2,"original elder-release objective completes")
	FileAccess.open("user://ingos-interactions.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("INGOS_INTERACTIONS ",checks," checks ",failures," failures")
	await finish()
