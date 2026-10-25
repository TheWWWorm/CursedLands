extends Node
## A surviving target that retaliates is alert throughout its hit reaction.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr('FAIL ',label)
func _ready()->void:
	var w:=GameWorld.new();add_child(w);w.zone={'type':'game'};w.set_process(false);w.set_physics_process(false)
	var a:=w.spawn_unit({'prototype':'Human Hero','position':Vector3(5,5,0)})
	var b:=w.spawn_unit({'prototype':'Human Hero','position':Vector3(6,5,0)})
	for u:GameUnit in [a,b]:u.set_process(false);u.set_physics_process(false);u.ai_next=INF;u._perceive_next=INF
	a.set_meta('hero',{});a.controller=0;a.faction=0;b.faction=1;b.controller=-1;b.facing=0
	w.set_relation(0,1,2);w.set_relation(1,0,2)
	a.stats.dmg_min=1;a.stats.dmg_max=1;a.stats.dmg_types=PackedFloat32Array([0,0,1,0,0,0,0])
	b.stats.armor=PackedFloat32Array([0,0,0,0,0,0,0]);b.hp=b.max_hp;b._anim_lock=1.0;b.action='hit';b.alert=false
	check(w.combat.strike_roll(a,b).backstab,'unaware target admits first backstab')
	w.combat.melee(a,b,{'hit':true,'backstab':true,'aim':1,'dmg':1.0,'types':a.stats.dmg_types,'bs_mul':1.0})
	check(not b.dead and b.hp<b.max_hp,'first blow injures the surviving target')
	check(b.orders.any(func(o):return o.get('type')=='attack' and o.get('target')==a),'victim has selected retaliation during its hit animation')
	check(b.alert,'retaliation sets combat posture before hit animation releases')
	for tick in 10:
		w.time+=GameUnit.TICK;b._tick(GameUnit.TICK)
		check(not w.combat.strike_roll(a,b).backstab,'busy aware target rejects repeat backstab at tick '+str(tick))
	# A different unaware target remains eligible; ending combat can restore it.
	var other:=w.spawn_unit({'prototype':'Human Hero','position':Vector3(6,5,0)});other.facing=0
	check(w.combat.strike_roll(a,other).backstab,'another unaware target remains eligible')
	b.orders.clear();b.order={};b._anim_lock=0;b.alert=false;b.remove_meta('noticed');b.remove_meta('attacker');b.remove_meta('suspect')
	check(w.combat.strike_roll(a,b).backstab,'a target that has actually left combat can be backstabbed again')
	w.queue_free()
	for i in 6:await get_tree().process_frame
	print('BACKSTAB_HIT_REACTION ',checks,' checks ',failures,' failures')
	get_tree().quit(1 if failures else 0)
