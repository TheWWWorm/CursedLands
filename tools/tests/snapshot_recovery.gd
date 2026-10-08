extends Node
## Loss/reordering semantics without network timing or rendering noise.
var checks:=0
var failures:=0
class Capture extends Session:
	var sent: Array=[]
	func _send_snapshot_records(snaps: Array,_time: float,_recipient:=0) -> void:
		sent.append(snaps)
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func actor(w: GameWorld,id: int,owner: int) -> GameUnit:
	var u:=GameUnit.new();u.uid=id;u.world=w;u.controller=owner
	w.add_child(u);w.set_unit(id,u);return u
func _ready() -> void:
	var sender:=Capture.new();add_child(sender);sender.set_physics_process(false)
	var w:=GameWorld.new();w.authority=false;w.process_mode=Node.PROCESS_MODE_DISABLED;add_child(w)
	sender.world=w;sender.online=true;sender.is_host=true
	var a:=actor(w,1,0);var b:=actor(w,2,-1)
	a.action="walk";a.pos=Vector2(10,20)
	sender._tick_world_session(.2)
	a.action="idle"
	# Force one real cadence opportunity, then discard its simulated packet.
	sender._snap_at_ms=0;sender._tick_world_session(.2);sender.sent.clear()
	sender._snap_at_ms=0;sender._tick_world_session(.2)
	check(sender.sent.size()==1 and sender.sent[0].any(func(s):return int(s[0])==a.uid and s[4]=="idle"),"lost final stop is repeated at the very next update")
	sender.sent.clear();sender._snap_at_ms=0
	for i in 8:sender._tick_world_session(.05)
	check(sender.sent.size()==1,"2x/catch-up physics cannot burst multiple snapshots in one wall-time frame")
	var receiver:=Session.new();add_child(receiver);receiver.set_physics_process(false);receiver.world=w
	receiver._pool_epoch=4
	var newer:=a.snapshot();newer[1]=12.0
	var other:=b.snapshot();other[1]=30.0
	receiver._apply_snap([newer],2.0,20)
	receiver._apply_snap([other],1.9,19)
	check(a.pos.x==12.0 and b.pos.x==30.0,"older chunk for another actor is still applied")
	check(w.time==2.0,"reordered chunk cannot rewind shared world clock")
	var stale:=a.snapshot();stale[1]=1.0
	receiver._apply_snap([stale],1.8,18)
	check(a.pos.x==12.0,"older packet cannot rewind the same actor")
	receiver._apply_snap([stale],2.0,20)
	check(a.pos.x==12.0,"duplicate packet is ignored")
	receiver._rpc_snap([stale],4.0,3,99)
	check(a.pos.x==12.0,"previous map generation cannot overwrite current actor")
	receiver._apply_snap([stale],2.0,21)
	check(a.pos.x==1.0,"paused same-time state changes use sequence rather than simulation timestamp")
	receiver.lmp={"base":"bz1mpg"};receiver.zone_id="gz1h";receiver.lmp_generation=4
	newer[1]=15.0
	receiver._rpc_lmp_snap("gz2h",4,[newer],3.0,22)
	check(a.pos.x==1.0,"LMP rejects snapshots from another location")
	receiver._rpc_lmp_snap("gz1h",3,[newer],3.0,22)
	check(a.pos.x==1.0,"LMP rejects an earlier owner generation")
	receiver._rpc_lmp_snap("gz1h",4,[newer],3.0,22)
	check(a.pos.x==15.0,"LMP accepts current scoped snapshot with per-actor sequencing")
	receiver.lmp={}
	var notice:={};var expected: Array[int]=[]
	for i in 420:
		var u:=actor(w,10000+i*3,-1);notice[u.uid]=u;expected.append(u.uid)
	a.set_meta("noticed",notice);a.set_meta("seen_corpses",{b.uid:b})
	var packed:=a._perception_snapshot()
	b._apply_perception_snapshot(packed)
	var received: Array=b.get_meta("net_noticed",[]);received.sort();expected.append(b.uid);expected.sort()
	check(received==expected,"packed/delta visibility preserves every noticed actor and corpse")
	check(var_to_bytes(a.snapshot()).size()<Session.SNAP_BYTES,"large retained visibility record fits one packet")
	a.set_meta("noticed",{a.uid:a});a.set_meta("seen_corpses",{})
	b._apply_perception_snapshot(a._perception_snapshot())
	check(b.get_meta("net_noticed")==[a.uid],"visibility cache invalidates when the list changes")
	b._apply_perception_snapshot([[a.uid],[b.uid]])
	check(b.get_meta("net_noticed")==[a.uid,b.uid],"legacy join/save array visibility remains readable")
	b._apply_perception_snapshot([1048577,PackedByteArray([1]),1])
	check(b.get_meta("net_noticed").is_empty(),"oversized compressed visibility is refused")
	sender.online=false;sender.world=null;receiver.world=null
	notice.clear();a.set_meta("noticed",{});w.free();sender.queue_free();receiver.queue_free()
	for i in 6:await get_tree().process_frame
	print("SNAPSHOT_RECOVERY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
