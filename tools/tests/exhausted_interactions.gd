extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func frames(n:=4) -> void:
	for i in n:await get_tree().process_frame
func census() -> void:
	var campaign:=CampaignMap.load_from(GameData.texts);var count:=0;var once:=0;var repeat:=0;var single:=[];var lift:={}
	var w:=GameWorld.new()
	for zone:Dictionary in campaign.zones.values():
		var data:=GameData.read_file("maps/"+String(zone.get("mob",""))+".mob")
		if data.is_empty():continue
		var mob:=EIMob.load_bytes(data)
		for o:Dictionary in mob.objects:
			if o.kind!="LEVER":continue
			var row:={"state":o.get("lever_state",0),"states":maxi(1,int(o.get("lever_states",2))),"cycled":o.get("lever_cycled",0),"science":Array(o.get("lever_science",[]))}
			w.levers[int(o.nid)]=row
			count+=1
			if int(o.nid)==1369841:lift={"zone":zone.id,"lever":row.duplicate(true)}
			if row.states==1:single.append([zone.id,o.nid,o.template])
			if row.science.is_empty() or int(row.science[0])!=0:
				row.state=row.states-1
				if row.states>1 and int(row.cycled)!=0:
					repeat+=1;check(w.lever_sys.usable(int(o.nid)),"native repeatable mechanism remains usable")
				else:
					once+=1;check(not w.lever_sys.usable(int(o.nid)),"native terminal mechanism is exhausted")
	print("INTERACTION_CENSUS ",JSON.stringify({"campaign":GameData.campaign_id,"levers":count,"one_time":once,"repeatable":repeat,"single_state":single,"lift_call":lift}))
	w.free()
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0,"control_mode":1},true)
	census()
	if GameData.campaign_id==CampaignProfile.ASTRAL:
		await lift_case()
		print("EXHAUSTED_INTERACTIONS ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0);return
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");await s.enter_zone("gz15h",1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	g.rig.set_process(false);g.direct.set_process(false);g.get_node("UnitFog").set_process(false)
	var u:GameUnit=s.party_units(0)[0];var w:=s.world;var id:=-1
	for nid:int in w.levers:
		var l:Dictionary=w.levers[nid]
		if int(l.states)>1 and int(l.cycled)==0 and w.lever_sys.usable(nid):id=nid;break
	check(id>=0,"real map contains a usable one-time object")
	if id>=0:
		var l:Dictionary=w.levers[id];var obj:Node3D=w.objects[id]
		var at:=obj.global_position+Vector3.UP*.6
		g.rig.camera.global_position=at+Vector3(0,4,6);g.rig.camera.look_at(at);g.rig.release();await frames()
		var point:=g.rig.camera.unproject_position(at);g._lever_pick_key=[]
		check(g.pick_lever(point)==id,"unopened object offers the hand interaction")
		w.lever_sys.set_state(id,int(l.states)-1,0);g._lever_pick_key=[]
		check(not w.lever_sys.usable(id) and g.pick_lever(point)!=id,"terminal object loses hand interaction immediately")
		u.order={};u.orders.clear();u.remove_meta("interact")
		s.apply_command({"t":"use_lever","target":id,"units":[u.uid]},0)
		check(u.orders.is_empty() and not u.has_meta("interact"),"authority rejects a stale use command after exhaustion")
		w.lever_sys.restore(id,0,0);check(w.lever_sys.usable(id),"resetting a mechanism restores interaction")
		w.lever_sys.restore(id,int(l.states)-1,1);check(not w.lever_sys.usable(id),"loaded terminal state is exhausted without a new save field")
		l.cycled=1;check(w.lever_sys.usable(id),"cyclic gate or switch remains available at its last state")
		w.lever_sys.set_state(id,-1,0);check(int(l.state)==0,"cyclic object can wrap back to its first state")
	g.free();s.free();await frames(6);TexUpscale.shutdown()
	print("EXHAUSTED_INTERACTIONS ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)
func lift_case() -> void:
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");await s.enter_zone("gz1d2",1,false)
	s.set_physics_process(false);s.world.set_physics_process(false);s.world.set_process(false);s.world.vm.instances.clear()
	var w:=s.world;var call:Dictionary=w.levers[1369841]
	call.state=int(call.states)-1;w.levers[338779].state=0;w.levers[1357456].state=0
	var lift:Node3D=w.objects[2240358];var ei:Dictionary=lift.get_meta("ei");var original:Vector3=ei.position;ei.position=Vector3(original.x,original.y,-.3)
	check(w.lever_sys.usable(1369841),"exhausted call switch remains useful when native lift recall is available")
	var vm:=w.vm;w.vm=null;w.authority=false
	check(w.lever_sys.usable(1369841),"replica without a script VM also offers meaningful lift recall")
	ei.position=Vector3(original.x,original.y,31.1)
	check(not w.lever_sys.usable(1369841),"completed call switch is unavailable when lift recall has no work to do")
	w.vm=vm;w.authority=true
	g.free();s.free();await frames(6);TexUpscale.shutdown()
