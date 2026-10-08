extends Node
## Geometry and authority checks for experimental direction attacks. The
## synthetic floor/obstacle isolates contact from animation and random damage.
var checks := 0
var failures := 0

class FloorWorld extends GameWorld:
	func ground_at(x: float, _y: float) -> float: return 8.0 if x >= 20.0 else 0.0

class Hits extends Combat:
	var victims: Array = []
	var records: Array = []
	func melee(_a: GameUnit, b: GameUnit, record := {}) -> void:
		victims.append(b); records.append(record)
	func weapon_spell(_a: GameUnit, _b: GameUnit) -> void: pass
	func strike_record(_a: GameUnit) -> Dictionary: return {"dmg":7.0,"aim":-1}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func actor(w: GameWorld, id: int, at: Vector2) -> GameUnit:
	var u := GameUnit.new();u.uid=id;u.world=w;u.pos=at;u._radius_base=0.3
	u.controller=0 if id==1 else -1;u.figure_half_z=0.9;u.stats={"range":0.0,"reach":20.0}
	w.add_child(u);w.set_unit(id,u)
	return u

func _ready() -> void:
	check(DirectControl.wants(0,true) and not DirectControl.wants(0,false),"automatic mode uses shoulder controls for gamepad only")
	check(not DirectControl.wants(1,true) and not DirectControl.wants(1,false),"classic selection overrides gamepad default")
	check(DirectControl.wants(2,true) and DirectControl.wants(2,false),"explicit shoulder mode also works with keyboard and mouse")
	var w := FloorWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false)
	var combat := Hits.new(w);w.combat=combat
	var a := actor(w,1,Vector2(5,5))
	var b := actor(w,2,Vector2(6,5))
	var c := actor(w,3,Vector2(6.3,5))
	check(DirectCombat.melee_target(a,Vector3.RIGHT)==b,"swing contacts nearest body in the weapon arc")
	check(DirectCombat.melee_target(a,Vector3.LEFT)==null,"swing away from nearby enemies misses")
	check(DirectCombat.melee_target(a,Vector3(1,-3,0).normalized())==null,"aim below a body misses")
	b.pos.y+=3;c.pos.y+=3
	check(DirectCombat.melee_target(a,Vector3.RIGHT)==null,"swing has no off-axis target magnetism")
	b.pos=Vector2(8,5);c.pos=Vector2(9,5)
	check(DirectCombat.melee_target(a,Vector3.RIGHT)==null,"distant enemies are not approached or hit")
	a.pos=Vector2(19.5,5);b.pos=Vector2(20.5,5)
	check(DirectCombat.melee_target(a,Vector3.RIGHT)==null,"separate storeys cannot be hit across planar overlap")
	a.pos=Vector2(5,5);b.pos=Vector2(6,5);c.hidden=true
	b.hidden=true
	check(DirectCombat.melee_target(a,Vector3.RIGHT)==null,"script-hidden actors are excluded")
	b.hidden=false
	# Use the actual navigation span representation, including a moving door.
	w.nav.size=Vector2i(64,64);w.nav._alt=10.0
	var cell := w.nav.cell(Vector2(5.7,5))
	var key := cell.y*w.nav.size.x+cell.x
	w.nav._spans[key]=[[0,30,1,123]]
	check(DirectCombat.melee_target(a,Vector3.RIGHT)==null,"solid door blocks contact")
	var pivot := Vector3(5,1.5,-5)
	var wanted := pivot+Vector3(4,0,0)
	var fraction := DirectCombat.scene_fraction(w,pivot,wanted,0.18)
	check(fraction<0.2,"camera sweep shortens before a wall")
	w.nav._spans.clear()
	check(DirectCombat.scene_fraction(w,pivot,wanted,0.18)==1.0,"opened door does not leave stale camera collision")
	check(DirectCombat.scene_fraction(w,pivot,Vector3(5,-1,-5))<1.0,"camera stays above floor")
	w.nav.size=Vector2i.ZERO
	var ray := DirectCombat.ray_body(w,a,Vector3(5,1,-5),Vector3(10,1,-5))
	check(ray.unit==b and float(ray.fraction)<0.3,"straight shot contacts nearest body")
	check(DirectCombat.ray_body(w,a,Vector3(5,3,-5),Vector3(10,3,-5)).unit==null,"shot above body misses")
	check(DirectCombat.body_fraction(Vector3(0,3,0),Vector3(0,-1,0),Vector3.ZERO,0.5,2.0)==0.25,"vertical shot intersects body cap")
	a._resolve_direct_hit(Vector3.RIGHT)
	check(combat.victims==[b] and bool(combat.records[0].hit),"actual swing impact invokes ordinary damage with geometric contact")
	b.pos.y+=2
	a._resolve_direct_hit(Vector3.RIGHT)
	check(combat.victims.size()==1,"victim moving away before impact avoids the blow")
	b.pos=Vector2(8,5)
	var arrow := Projectile.launch_direct(w,a,Vector3.RIGHT,true)
	arrow.set_physics_process(false)
	b.pos.y+=2
	arrow._tick_direct(0.2)
	check(combat.victims.size()==1,"arrow does not home after a target moves")
	arrow.free()
	b.pos=Vector2(8,5)
	arrow=Projectile.launch_direct(w,a,Vector3.RIGHT,true);arrow.set_physics_process(false)
	arrow._tick_direct(0.2)
	check(combat.victims.size()==2 and combat.records[-1].dmg==7.0,"arrow carries damage record and hits along its segment")
	arrow.free()
	var s := Session.new();s.world=w;s.state=CampaignState.new()
	w.zone={"type":"brief"}
	check(not s.command_allowed({"t":"attack"}) and not s.command_allowed({"t":"cast"}),"classic village combat stays restricted")
	check(not s.command_allowed({"t":"direct_cast"}),"third-person spells are also restricted in villages")
	s.apply_command({"t":"direct_attack","units":[a.uid],"direction":Vector3.RIGHT},0)
	check(a.orders.is_empty(),"authority refuses third-person attacks in a village")
	a.orders.clear()
	w.zone={"type":"game"}
	s.apply_command({"t":"direct_attack","units":[a.uid],"direction":Vector3.RIGHT},1)
	check(a.orders.is_empty(),"another player cannot issue a direction attack for this unit")
	s.apply_command({"t":"direct_attack","units":[a.uid],"direction":Vector3(NAN,0,0)},0)
	check(a.orders.is_empty(),"invalid direction is rejected")
	s.apply_command({"t":"direct_attack","units":[a.uid],"direction":Vector3(1e30,0,0)},0)
	check(a.orders.is_empty(),"overflowing finite direction is rejected")
	a.blocked=true
	s.apply_command({"t":"direct_attack","units":[a.uid],"direction":Vector3.RIGHT},0)
	check(a.orders.is_empty(),"script block still refuses direct combat")
	a.blocked=false
	s.apply_command({"t":"direct_attack","units":[a.uid],"direction":Vector3.RIGHT},0)
	check(a.orders.size()==1 and a.orders[0].type=="direct_attack","explicit direction attack is permitted in the field")
	a.orders.clear();a._attack_cd=1.0
	s.apply_command({"t":"direct_attack","units":[a.uid],"direction":Vector3.RIGHT},0)
	check(a.orders.is_empty(),"repeated requests cannot bypass weapon cooldown")
	s.world=null;s.free();w.free()
	print("DIRECT_COMBAT ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
