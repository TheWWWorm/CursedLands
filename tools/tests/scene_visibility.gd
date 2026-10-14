extends Node
## Actual authored decision trees through VM save/restore, including old saves.
const P=preload("res://src/game/script/script_parser.gd")
var checks:=0
var failures:=0
class ProbeSession extends Session:
 func sync_state()->void:pass
 func broadcast(_e:Dictionary)->void:pass
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func tick(w:GameWorld)->void:
 for i in 40:w.time+=GameUnit.TICK;w.vm.tick(GameUnit.TICK)
func dispose(w:GameWorld)->void:
 if w.vm:w.vm.briefings.vm=null;w.vm=null
func restore(w:GameWorld,s:Session,saved:Dictionary)->void:
 dispose(w);w.set_meta("restored_vm",saved.duplicate(true));w.vm=ScriptVM.create(w,s);tick(w)
func _ready()->void:
 for row:Array in [
  ["bz8k","Vor","VCheck#0#23","q.gz12k.q49k"],
  ["bz8k","mthief","VCheck#0#101","q.gz13k.q44k"],
  ["bz1g","NSheriff","VCheck#0#552","q.gz3g.q23g"],
  ["bz1g","Merc2","VCheck#0#552","q.gz3g.q23g"],
  ["bz3g","skelet","VCheck#0#17","b.SKD.Dr22"]]:
  var s:=ProbeSession.new();s.state=CampaignState.new();s.zone_id=row[0];add_child(s)
  var w:=GameWorld.new();w.zone={"id":row[0],"type":"brief"};w.session=s;s.world=w
  w.process_mode=Node.PROCESS_MODE_DISABLED;add_child(w)
  var zone:Dictionary=CampaignMap.load_from(GameData.texts).zones[row[0]]
  w.mob=EIMob.load_bytes(GameData.read_file("maps/"+str(zone.get("mob",zone.mpr))+".mob"))
  var u:GameUnit
  for rec:Dictionary in w.mob.objects:
   if str(rec.get("name","")).nocasecmp_to(row[1])==0:u=w.spawn_unit(rec);break
  check(u!=null,row[1]+" loads from original map/model")
  if not u:dispose(w);s.world=null;w.free();s.queue_free();continue
  w.vm=ScriptVM.create(w,s);w.vm.instances.clear();w.vm.globals[row[1]]=u
  w.vm.spawn(row[2],[null]);tick(w)
  check(u.hidden,row[1]+" starts hidden before its original quest gate")
  var saved:=w.vm.save_state()
  check(not saved.instances.any(func(i):return i.s==row[2]),row[1]+" startup check has completed and left saved VM")
  s.state.set_var(0,row[3],2);var vars:=s.state.vars.duplicate(true);var hp:=u.hp
  restore(w,s,saved)
  check(not u.hidden and u.visible,row[1]+" appears on revisit when original condition changes")
  check(s.state.vars==vars and u.hp==hp and w.unit_rows().size()==1,row[1]+" refresh preserves rewards, health and actor count")
  u.hidden=true;u.visible=false;s._restoring=true;restore(w,s,saved)
  check(not u.hidden,row[1]+" older explicit save repairs the stale hidden state")
  s._restoring=false
  u.dead=true;u.hidden=true;restore(w,s,saved)
  check(u.dead and u.hidden,row[1]+" dead actor is never revived or revealed")
  u.dead=false;u.set_meta("hero",{});u.controller=0;restore(w,s,saved)
  check(u.hidden,row[1]+" recruited actor remains controlled by party lifecycle")
  u.remove_meta("hero");u.controller=-1
  s.state.set_var(0,row[3],0);u.hidden=false;restore(w,s,saved)
  check(u.hidden,row[1]+" unfinished condition still hides actor")
  if row[1]=="Vor":
   s.state.set_var(0,row[3],2);s.state.set_var(0,"VorHide2",1);restore(w,s,saved)
   check(u.hidden,"Fleyn stays hidden after the authored departure flag")
   s.state.set_var(0,"VorHide2",0)
  w.erase_unit(u.uid);restore(w,s,saved)
  check(w.unit_rows().is_empty(),row[1]+" removed actor is not recreated")
  u.free();dispose(w);s.world=null;w.free();s.queue_free()
 await get_tree().process_frame;TexUpscale.shutdown()
 print("SCENE_VISIBILITY ",checks," checks ",failures," failures")
 get_tree().quit(1 if failures else 0)
