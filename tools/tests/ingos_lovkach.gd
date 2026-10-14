extends Node
## Original Ingos visibility scripts and the actual VM save/restore path.
## The quest flag is prepared; this is not a complete playthrough of q44k.
const Compat := preload("res://src/game/script/story_compat.gd")
const P := preload("res://src/game/script/script_parser.gd")
const FLAG := "q.gz13k.q44k"
var checks:=0
var failures:=[]
var s:Session
var w:GameWorld
var u:GameUnit
var saved:Dictionary

class ProbeSession extends Session:
	func sync_state()->void:pass
	func broadcast(_event:Dictionary)->void:pass

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
	print("PASS " if ok else "FAIL ",label)

func _ready()->void:
	s=ProbeSession.new();s.state=CampaignState.new();s.zone_id="bz8k";add_child(s)
	w=GameWorld.new();w.zone={"id":"bz8k","type":"brief"};w.session=s;s.world=w
	w.process_mode=Node.PROCESS_MODE_DISABLED;add_child(w)
	w.mob=EIMob.load_bytes(GameData.read_file("maps/bz8k.mob"))
	for rec:Dictionary in w.mob.objects:
		if rec.get("name","")=="mthief":u=w.spawn_unit(rec);break
	check(u!=null and String(u.proto.name)=="Human Kania NPC Lovkach A10","original mthief record identifies Lovkach")
	if not u:get_tree().quit(1);return
	u.set_process(false);u.set_physics_process(false)
	w.vm=ScriptVM.create(w,s);w.vm.instances.clear()
	w.vm.spawn("VCheck#0#101",[null]);tick()
	check(u.hidden,"unfinished q44k keeps Lovkach hidden on the first visit")
	saved=w.vm.save_state()
	check(not saved.instances.any(func(row):return row.s in ["VCheck#0#101","VTriger#0#102","VTriger#0#104"]),"one-shot visibility check is absent from the saved VM")
	# Finish the quest elsewhere and revisit the already-saved Ingos village.
	s.state.set_var(0,FLAG,2);var vars:=s.state.vars.duplicate(true);var hp:=u.hp
	restore()
	check(not u.hidden and u.visible,"revisited village reveals Lovkach once q44k is complete")
	check(s.state.vars==vars and u.hp==hp,"reveal does not repeat rewards or modify quest/body state")
	tick();check(w.unit_rows().size()==1,"reveal does not spawn a duplicate actor")
	s._restoring=true;u.hidden=true;u.visible=false;restore()
	check(not u.hidden,"loading an older save repairs the stale hidden actor")
	s._restoring=false
	for value:int in [0,1,3]:
		s.state.set_var(0,FLAG,value);u.hidden=true;u.visible=false;restore()
		check(u.hidden,"only the authored completed value reveals Lovkach: "+str(value))
	s.state.set_var(0,FLAG,2)
	for guard:String in ["dead","modified script","pending gate","pending world"]:
		w.set_meta("restored_vm",saved);dispose_vm();w.vm=ScriptVM.create(w,s)
		# Recovery is synchronous; arrange each guard after VM restoration.
		u.hidden=true;u.visible=false
		w.vm.instances.clear()
		match guard:
			"dead":u.dead=true
			"modified script":w.vm.ast.scripts["VTriger#0#102"].blocks[0].body.append([P.S_CALL,"GSSetVar",[[P.N_NUM,0.0],[P.N_STR,"custom"],[P.N_NUM,1.0]]])
			"pending gate":w.vm.spawn("VCheck#0#101",[null])
			"pending world":w.vm._start_world(w.vm.ast.world)
		var before:=w.vm.instances.size()
		Compat.recover(w.vm)
		check(u.hidden and w.vm.instances.size()==before,"recovery preserves "+guard)
		u.dead=false;u.info.name="mthief"
	w.erase_unit(u.uid);restore()
	check(w.unit_rows().is_empty(),"removed Lovkach is not recreated")
	u.free();dispose_vm();s.world=null;w.free();s.queue_free()
	await get_tree().process_frame;TexUpscale.shutdown()
	print("INGOS_LOVKACH ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func tick()->void:
	for i in 40:w.time+=GameUnit.TICK;w.vm.tick(GameUnit.TICK)

func dispose_vm()->void:
	if w.vm and w.vm.briefings:w.vm.briefings.vm=null
	w.vm=null

func restore()->void:
	w.set_meta("restored_vm",saved.duplicate(true));dispose_vm();w.vm=ScriptVM.create(w,s);tick()
