extends "scene_visibility.gd"
func _ready() -> void:
	var s:=ProbeSession.new();s.state=CampaignState.new();s.zone_id="bz1g";add_child(s)
	var w:=GameWorld.new();w.zone={"id":"bz1g","type":"brief"};w.session=s;s.world=w
	w.process_mode=Node.PROCESS_MODE_DISABLED;add_child(w)
	var zone:Dictionary=CampaignMap.load_from(GameData.texts).zones.bz1g
	w.mob=EIMob.load_bytes(GameData.read_file("maps/"+str(zone.mob)+".mob"))
	var ids:=[]
	for rec:Dictionary in w.mob.objects:
		if rec.get("name","")=="Elder" or int(rec.get("nid",0)) in [341484,85297]:
			var u:=w.spawn_unit(rec);ids.append(u.uid)
	check(ids.size()==3,"original elder and both guards load")
	w.vm=ScriptVM.create(w,s);w.vm.instances.clear()
	w.vm.spawn("VCheck#0#575",[null]);tick(w)
	var saved:=w.vm.save_state()
	restore(w,s,saved)
	check(w.unit_rows().size()==3,"revisit before departure preserves all three actors")
	s.state.set_var(0,"ElderEscape",1)
	restore(w,s,saved)
	check(w.unit_rows().is_empty(),"revisit removes the elder and both guards through the original script")
	check(s.state.get_var(0,"ElderRemoved")==1 and s.state.get_var(0,"b.NSheriff.nv26")==2 and s.state.get_var(0,"b.NSheriff.nv27_1")==1,"departure completes original Revar topic changes")
	var vars:=s.state.vars.duplicate(true);restore(w,s,saved)
	check(s.state.vars==vars and w.unit_rows().is_empty(),"repeat restore is idempotent")
	# Explicit old saves and changed mod content use the same signature gate.
	s.state.set_var(0,"ElderRemoved",0);s._restoring=true
	w.mob.script_text=w.mob.script_text.replace("RemoveUnitFromServer( SG1 )","HideObject( SG1, 1 )")
	restore(w,s,saved)
	check(s.state.get_var(0,"ElderRemoved")==0,"changed mod departure family is not replayed")
	dispose(w);s.world=null;w.free();s.queue_free();await get_tree().process_frame
	TexUpscale.shutdown();print("ELDER_DEPARTURE ", JSON.stringify({"checks":checks,"failures":failures}));get_tree().quit(1 if failures else 0)
