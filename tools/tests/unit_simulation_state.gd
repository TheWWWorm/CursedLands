extends Node
var checks := 0
var failures := 0

class CustomUnit extends GameUnit:
	func _get_hp() -> float: return 3.0

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 16: printerr("FAIL ",label)

func compare(u: GameUnit,label: String) -> void:
	var row: Dictionary = u._sim_state.readback()
	check(row.size()==21,"all native input fields")
	for key in row: check(row[key]==u.get(key),label+" "+String(key))

func _ready() -> void:
	var u := GameUnit.new()
	check(u._sim_state != null,"owned state available")
	check(u._sim_state.matches(u,GameUnit),"identity and script match")
	compare(u,"initial defaults")
	var values := {
		"pos":Vector2(4.1,-8.2),"facing":1.73,"uid":817,"controller":2,"faction":5,
		"dead":true,"hidden":true,"alert":true,"mode":"guard","order_failed":true,"_anim_lock":.7,
		"_max_hp":27.0,"stance":2,"action":"cast:test","info":{"logic":[{"logic_model":2}]},
		"proto":{"name":"fixture"},"stats":{"sight":38.0},"buffs":{"speed":{"until":2.0}},
		"orders":[{"type":"move","to":Vector2.ONE}],"order":{"type":"wait","t":2.0},"_pending_hit":{"t":1.0}}
	for key in values:
		if key=="orders":u.orders.assign(values[key])
		else:u.set(key,values[key])
		compare(u,"published "+key)
	u.pos.x += 5.0
	u._anim_lock -= .1
	u.buffs.speed.until += 3.0
	u.info.logic[0].logic_model = 5
	u.orders[0].to = Vector2(4,7)
	u.orders.append({"type":"wait","t":.1})
	u.order.erase("t")
	compare(u,"in-place/nested writes")
	var old_info := u.info
	var old_orders := u.orders
	u.info = {"new":true}
	u.orders = [{"type":"rotate","angle":.5}]
	old_info["after_detach"]=true
	old_orders.clear()
	compare(u,"replacement detaches old containers")
	check(not u._sim_state.readback().info.has("after_detach"),"detached container is not retained as current")
	u.orders.clear(); u.buffs.clear(); u._pending_hit.clear();u.info.clear();u.order.clear()
	compare(u,"clear live collections")
	var rng := RandomNumberGenerator.new(); rng.seed=444081
	for i in 512:
		u.pos=Vector2(rng.randf_range(-100,100),rng.randf_range(-100,100)); u.facing=rng.randf_range(-PI,PI)
		u.controller=rng.randi_range(-1,3);u.faction=rng.randi_range(0,31);u.dead=i%2==0;u.hidden=i%3==0
		u.alert=i%5==0;u._anim_lock=rng.randf_range(-3,3);u._max_hp=rng.randf_range(0,100)
		u.stance=i%3;u.mode=["standard","guard","sentry","player"][i%4];u.order_failed=i%7==0
		u.stats.sight=rng.randf_range(0,100);u.info.logic=[{"logic_model":i%6}]
		u.orders=[{"type":"move","to":u.pos}];u.order={"type":"move","calm":true};u._pending_hit={"t":float(i)}
		compare(u,"random "+str(i))
	var other := GameUnit.new()
	check(not u._sim_state.matches(other,GameUnit),"another owner rejected")
	var owned := u._sim_state
	u.free()
	check(not owned.matches(other,GameUnit),"record survives owner deletion without retaining it")
	var custom := CustomUnit.new()
	check(not custom._sim_state.matches(custom,GameUnit),"custom script cannot use standard fast path")
	custom.free();other.free()
	var w := GameWorld.new(); w.time=1.0
	var actor := GameUnit.new(); actor.world=w;actor.uid=719
	actor.set_meta("calm",{"busy":true,"until":5.0})
	var kernel: RefCounted = ClassDB.instantiate("AIActivityKernel")
	check(kernel.can_defer_owned(actor,w.ai,w.time,GameUnit),"registered actor eligibility")
	var detached: RefCounted=actor._sim_state
	actor._sim_state=null
	detached.update(&"controller",2)
	check(kernel.can_defer_owned(actor,w.ai,w.time,GameUnit),"replaced state detaches registry before retained record edits")
	detached.capture(actor)
	actor._sim_state=detached
	actor._sim_lease=detached.attach()
	# Replacing a lease for the same record cannot let the old generation
	# unregister the new attachment when its last reference is released.
	var old_lease: RefCounted=actor._sim_lease
	actor._sim_lease=detached.attach()
	old_lease=null
	detached.update(&"controller",2)
	check(not kernel.can_defer_owned(actor,w.ai,w.time,GameUnit),"old lease does not remove new registration")
	detached.update(&"controller",-1)
	actor.set_script(CustomUnit)
	actor._max_hp=2.0
	detached.update(&"controller",2)
	check(kernel.can_defer_owned(actor,w.ai,w.time,GameUnit),"script replacement removes old registered fast state")
	actor.free();w.free()
	print("UNIT_SIMULATION_STATE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
