extends Node
## Use the authored Portal spell and actual GameUnit cast scheduling.
var checks:=0
var failures:=0
var serial:=666666

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL ",label)

func actor(w:GameWorld,caster:bool)->GameUnit:
	serial+=1
	var u:=GameUnit.new()
	var record:={"prototype":"zone1 JunEvil" if caster else "zone1 Human Fighter3 M","nid":serial,"player":6 if caster else 3}
	if caster:record.template="unmocu"
	check(u.setup(w,record),"authored actor loads")
	w.add_child(u);w.set_unit(u.uid,u)
	u.mana=10000.0;u.facing=0.0
	return u

func _ready()->void:
	for scenario in ["live","dead","removed","target_removed","different_world"]:
		var w:=GameWorld.new();w.process_mode=Node.PROCESS_MODE_DISABLED;add_child(w)
		var c:=actor(w,true);var t:=actor(w,false)
		var spell:=String(c.proto.spells[0])
		var before:=t.hp
		c.order={"type":"cast","spell":spell,"target":t}
		c._do_cast(GameUnit.TICK)
		var timers:=w.get_node_or_null("SpellTimers") as Spells.WorldTimers
		check(timers!=null and timers.pending.size()==1,"real cast queues one callback")
		if timers==null:w.free();continue
		var delay:=float(timers.pending[0].left)
		check(delay>0.0 and t.hp==before,"effect waits for its cast delay")
		var other:GameWorld
		match scenario:
			"dead":c.dead=true
			"removed":
				w.erase_unit(c.uid);c.free()
			"target_removed":
				w.erase_unit(t.uid);t.free()
			"different_world":
				other=GameWorld.new();other.process_mode=Node.PROCESS_MODE_DISABLED;add_child(other)
				w.erase_unit(c.uid);w.remove_child(c);other.add_child(c);c.world=other;other.set_unit(c.uid,c)
		for i in ceili(delay/GameUnit.TICK)+2:
			w._logic_step+=1;w.time+=GameUnit.TICK;timers._tick(GameUnit.TICK,true)
		check(timers.pending.is_empty(),"callback completes once: "+scenario)
		if is_instance_valid(t):
			check(t.dead and t.hp<before if scenario=="live" else t.hp==before,"delayed result: "+scenario)
		w.free()
		if other:other.free()
	# A destroyed world's child timer must not keep an actor or fire later.
	var w:=GameWorld.new();w.process_mode=Node.PROCESS_MODE_DISABLED;add_child(w)
	var c:=actor(w,true);var t:=actor(w,false);var ref:WeakRef=weakref(c)
	Spells.cast_after(w,c,String(c.proto.spells[0]),t,t.pos,GameUnit.TICK)
	w.free()
	check(ref.get_ref()==null,"timer does not retain a removed world/caster")
	await get_tree().process_frame
	print("DELAYED_CAST_LIFETIME checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
