extends Node
## External checkpoint regression: write kills four living Ingos animals; read
## runs in a fresh process and revisits the map. Input files are never modified.
var checks:=0
var failures:=0
var s:Session
var g:Game
var cfg:={"save":"","zone":"gz12k","mode":"write","output":""}
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:_run.call_deferred()
func freeze()->void:
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false)
func ticks(n:int)->void:
	for i in n:s.world._tick(GameUnit.TICK)
func verify(expected:Dictionary,stage:String)->void:
	for nid:String in expected:
		var id:=int(nid)
		var u:GameUnit=s.world.units.get(id)
		print("VERIFY ",stage," ",id," ","absent" if u==null else str([u.dead,u.hp,u.info.get("prototype")]))
		check(u==null if expected[nid]=="looted" else u!=null and u.dead,stage+" death "+nid)
		if expected[nid]=="looted":check(s.world.looted.has(id),stage+" looted tombstone "+nid)
func _run()->void:
	for a:String in OS.get_cmdline_user_args():
		for k:String in cfg:
			if a.begins_with("--"+k+"="):cfg[k]=a.trim_prefix("--"+k+"=")
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	s=Session.new();add_child(s);s.set_physics_process(false)
	g=Game.new();g.session=s;s.game=g;add_child(g);s.local_host.worker=true
	var st:=CampaignState.load_from(cfg.save)
	check(st!=null and s._load_state("input",st),"save loads")
	if failures:get_tree().quit(1);return
	freeze()
	if s.zone_id!=cfg.zone:await s.enter_zone(cfg.zone,1,false);freeze()
	var expected:={}
	if cfg.mode=="write":
		var animals:=s.world.units.values().filter(func(u):return not u.dead and (String(u.info.get("prototype","")).contains("Tiger") or String(u.info.get("prototype","")).contains("Dog")))
		check(animals.size()>=4,"at least four living animals in supplied map")
		for i in mini(4,animals.size()):
			var u:GameUnit=animals[i]
			print("KILL ",u.uid," ",u.info.get("prototype")," ",u.pos)
			u.hp=0;u.die();expected[str(u.uid)]="corpse"
			if i%2==1:
				s.take_loot(s.party_units(0)[0],u);expected[str(u.uid)]="looted"
		ticks(120)
		verify(expected,"after kill")
		s._capture_save_state()
		check(s.state.save(cfg.output)==OK,"checkpoint written")
		FileAccess.open(cfg.output+".expected.json",FileAccess.WRITE).store_string(JSON.stringify(expected))
	else:
		expected=JSON.parse_string(FileAccess.get_file_as_string(cfg.save+".expected.json"))
		verify(expected,"fresh process")
		ticks(600);verify(expected,"after 33 seconds of scripts and AI")
		await s.enter_zone("bz8k",1,false);freeze();ticks(20)
		await s.enter_zone(cfg.zone,1,false);freeze();ticks(120)
		verify(expected,"after village return")
	FileAccess.open("user://persistence.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"config":cfg,"expected":expected},"\t"))
	print("PERSISTENCE ",checks," checks ",failures," failures")
	s.local_host.worker=false;g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
