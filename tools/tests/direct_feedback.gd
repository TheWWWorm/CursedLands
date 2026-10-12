extends "direct_combat.gd"
## Preview is checked against real impact geometry, not UI colour alone.
func _ready() -> void:
	var w := FloorWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false)
	w.combat=Hits.new(w)
	var a:=actor(w,1,Vector2(5,5));var b:=actor(w,2,Vector2(6,5))
	b.faction=1;a.set_meta("hate",{"w":w.get_instance_id(),"f":[1]})
	var eye:=DirectCombat.origin(a)
	check(DirectCombat.preview(a,eye,Vector3.RIGHT).kind=="reach","melee preview agrees with reachable enemy")
	b.pos.x=8
	check(DirectCombat.preview(a,eye,Vector3.RIGHT).kind=="far","distant melee target is out of reach")
	b.fogged=true
	check(DirectCombat.preview(a,eye,Vector3.RIGHT).kind=="neutral","preview never identifies a fogged actor")
	b.fogged=false;b.pos.x=6;b.faction=0
	check(DirectCombat.preview(a,eye,Vector3.RIGHT).kind=="friendly","melee warns for a friendly body in its actual arc")
	a.stats.ranged=true;b.pos.x=8
	var c:=actor(w,3,Vector2(9,5));c.faction=1
	check(DirectCombat.preview(a,eye,Vector3.RIGHT).kind=="friendly","ranged warning follows the first friendly body before the enemy")
	b.pos.y+=3
	check(DirectCombat.preview(a,eye,Vector3.RIGHT).kind=="reach","ranged preview clears once the ally leaves the shot")
	w.nav.size=Vector2i(64,64);w.nav._alt=10.0
	var cell:=w.nav.cell(Vector2(6,5));w.nav._spans[cell.y*w.nav.size.x+cell.x]=[[0,30,1,123]]
	check(DirectCombat.preview(a,eye,Vector3.RIGHT).kind=="blocked","solid scenery obstructs the muzzle ray")
	w.nav._spans.clear()
	check(DirectCombat.preview(a,eye,Vector3.RIGHT).kind=="reach","opening a door clears obstruction without a stale cache")
	var seq:=a.direct_hit_serial
	DirectCombat.preview(a,eye,Vector3.RIGHT)
	check(a.direct_hit_serial==seq,"preview never confirms a hit")
	var arrow:=Projectile.launch_direct(w,a,Vector3.RIGHT,true);arrow.set_physics_process(false)
	arrow._tick_direct(0.3)
	check(a.direct_hit_serial==seq+1,"actual projectile contact confirms one hit")
	arrow.free();a.stats.ranged=false;c.pos=Vector2(6,5)
	a._resolve_direct_hit(Vector3.RIGHT)
	check(a.direct_hit_serial==seq+2,"actual melee contact confirms one hit")
	a._resolve_direct_hit(Vector3.LEFT)
	check(a.direct_hit_serial==seq+2,"missed swing does not flash a hit")
	w.queue_free();await get_tree().process_frame
	print("DIRECT_FEEDBACK ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
