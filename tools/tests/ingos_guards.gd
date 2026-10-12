extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _ready()->void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	var s:=Session.new();add_child(s);s.set_physics_process(false);s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	await s.enter_zone("bz8k",1,false)
	var w:=s.world;w.set_process(false);w.set_physics_process(false)
	var actors:Array[GameUnit]=[];var replicas:Array[GameUnit]=[];var dips:=0;var remote_dips:=0
	for u:GameUnit in w.units.values():
		if u.info.name not in ["AGuard1","AGuard2","Eda1","Eda2"]:continue
		actors.append(u)
		var r:=GameUnit.new();r.setup(w,u.info);add_child(r);replicas.append(r)
	check(actors.size()==4,"both authored Ingos gate guards and camp workers found")
	var serials:=[]
	for i in 400:
		w.time+=GameUnit.TICK;w.vm.tick(GameUnit.TICK)
		for n in actors.size():
			var u:GameUnit=actors[n];u.tick(GameUnit.TICK);u.model.player.advance(GameUnit.TICK)
			var r:GameUnit=replicas[n];r.apply_snapshot(u.snapshot());r.model.player.advance(GameUnit.TICK)
			if i>10:
				var expected := "anim:uspecial08" if u.info.name in ["Eda1","Eda2"] else "anim:uspecial10"
				if u.action!=expected:dips+=1
				if r.action!=expected:remote_dips+=1
		if i==10:
			for u:GameUnit in actors:serials.append(u._action_serial)
	check(dips==0,"no idle-pose interruption across repeated authored guard and work cycles")
	check(remote_dips==0,"co-op snapshots preserve the same uninterrupted pose")
	for n in actors.size():
		var u:GameUnit=actors[n]
		check(u._action_serial>int(serials[n])+4,"scripted animation keeps replaying rather than freezing")
		u.controller=0
		check(not u._ambient_story_pose(),"a player-controlled actor cannot retain the ambient hold")
		u.controller=-1;u._anim_lock=0;u.command({"type":"wait","t":1.0});u.tick(GameUnit.TICK)
		check(u.action=="idle" and u._story_clip.is_empty(),"a new command releases the guard pose")
	for r:GameUnit in replicas:r.queue_free()
	g.queue_free();s.queue_free()
	for i in 10:await get_tree().process_frame
	TexUpscale.shutdown()
	print("INGOS_GUARDS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
