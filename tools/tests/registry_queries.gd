extends Node
## Exact broadphase against exhaustive registry queries, including structural
## edits, same-key replacement, classification changes and a freed actor.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _ready() -> void:
	spatial_queries()
	party_membership()
	print("REGISTRY_QUERIES PASS=", checks - failures.size(), " FAIL=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

static func exhaustive(w: GameWorld, p: Vector2, radius: float, live := false) -> Array:
	var out := []
	for u in w.units.values():
		if is_instance_valid(u) and (not live or not u.dead) and u.pos.distance_squared_to(p) <= radius*radius:
			out.append(u)
	return out

func compare_queries(w: GameWorld, label: String) -> void:
	for p in [Vector2.ZERO,Vector2(16,16),Vector2(32,48),Vector2(-1,2),Vector2(200,200),Vector2(512,256)]:
		for radius in [0.0,0.0001,4.0,5.999999999,6.0,10.0,16.0,32.0,90.0,1e6,INF,-6.0,NAN]:
			check(w.units_near(p,radius) == exhaustive(w,p,radius), label+" all-unit exact boundaries/order")
			check(w.live_units_near(p,radius) == exhaustive(w,p,radius,true), label+" living exact boundaries/order")
	for p in [Vector2(16,16),Vector2(200,200)]:
		for radius in [0.0,6.0,10.0,90.0,1e6,INF]:
			var all := exhaustive(w,p,radius)
			var living := exhaustive(w,p,radius,true)
			check(w.nav.units_all_around(p,radius) == all, label+" nav all dictionary order")
			check(w.nav.units_around(p,radius) == living, label+" nav live dictionary order")

func spatial_queries() -> void:
	var w := GameWorld.new()
	w.nav.size = Vector2i(2048,2048)
	for i in 322:
		var u := GameUnit.new()
		u.uid = 1000+i
		u.world = w
		u.pos = Vector2(16.0+float(i%23)*9.0,16.0+float(i/23)*13.0)
		u.hidden = i%3 == 0
		u.dead = i%11 == 0
		w.set_unit(u.uid,u)
		u._seq = 10000-i   # deliberately opposite to Dictionary.values order
		w.nav.rebucket(u)
		w.add_child(u)
	compare_queries(w,"spawn")
	var first: GameUnit = w.units[1001]
	first.pos = Vector2(16,16) # same/fine/coarse bucket updates happen at once
	compare_queries(w,"script/snapshot placement")
	first.hidden = not first.hidden
	first.dead = true; w.nav.rebucket(first)
	compare_queries(w,"death")
	first.dead = false; w.nav.rebucket(first)
	compare_queries(w,"revive")
	w.erase_unit(first.uid);w.set_unit(first.uid,first)
	compare_queries(w,"erase/reinsert without changing_seq")
	# Identical cardinality/keys can also replace the actual object.
	var old: GameUnit = w.units[1002]
	old._seq = 0; w.nav.untrack_unit(old)
	var replacement := GameUnit.new()
	replacement.uid = old.uid;replacement.world = w;replacement.pos = Vector2(16,16)
	replacement._seq = 31;w.set_unit(old.uid,replacement);w.nav.rebucket(replacement);w.add_child(replacement)
	old.free()
	compare_queries(w,"same-key replacement")
	var removed: GameUnit = w.units[1003]
	removed._seq = 0;w.nav.untrack_unit(removed);w.erase_unit(removed.uid);removed.free()
	compare_queries(w,"remove")
	# Every World query falls back when a member is not registered.
	first._seq = 0;w.nav.untrack_unit(first)
	for p in [Vector2(16,16),Vector2(32,48)]:
		for r in [0.0,10.0,INF]:
			check(w.units_near(p,r) == exhaustive(w,p,r),"unregistered member uses exhaustive fallback")
	first._seq = 41;w.nav.rebucket(first)
	first.pos = Vector2(-0.1,0)
	for r in [0.0,2.0,6.0,INF]:
		check(w.units_near(first.pos,r) == exhaustive(w,first.pos,r),"negative-position sentinel uses exhaustive fallback")
	first.pos = Vector2(16,16)
	w.set_unit(9999,first)
	check(w.units_near(first.pos,0.0) == exhaustive(w,first.pos,0.0),"duplicate registry value retains duplicate copies")
	w.erase_unit(9999)
	w.authority = false
	check(w.units_near(first.pos,10.0) == exhaustive(w,first.pos,10.0),"client retains exhaustive query")
	w.authority = true
	var sum_reference := 0
	var sum_index := 0
	var started := Time.get_ticks_usec()
	for i in 2000:
		sum_reference += exhaustive(w,Vector2(16+i%23*9,16+i/23%14*13),10.0).size()
	var reference_us := Time.get_ticks_usec()-started
	started = Time.get_ticks_usec()
	for i in 2000:
		sum_index += w.units_near(Vector2(16+i%23*9,16+i/23%14*13),10.0).size()
	var indexed_us := Time.get_ticks_usec()-started
	check(sum_reference == sum_index,"timed322-unit broadphase checksum equals exhaustive query")
	print("SPATIAL_QUERY exhaustive_us=",reference_us," indexed_us=",indexed_us," queries=2000 units=",w.units.size()," checksum=",sum_index)
	var before := w.units_near(first.pos,10.0)
	before.erase(first)
	var plain: Node3D = first
	plain.set_script(null)
	check(w.units_near(Vector2(16,16),10.0) == before,"script replacement invalidates a registered row")
	w.free()

func party_membership() -> void:
	var w := GameWorld.new()
	var a := GameUnit.new(); a.uid = 1; a.controller = 0; a.world = w
	var b := GameUnit.new(); b.uid = 2; b.controller = 1; b.world = w
	w.units = {1:a, 2:b}
	check(w.units.is_read_only() and w.unit_rows().is_read_only(), "roster snapshots are read-only")
	var held_rows := w.unit_rows()
	check(w.party_units() == [a,b], "shared party follows registry order")
	b.controller = -1
	check(w.party_units() == [a], "departing controller immediately loses shared sight")
	b.controller = 1
	check(w.party_units() == [a,b], "rejoining controller immediately supplies shared sight")
	w.erase_unit(1); w.set_unit(1,a)
	check(w.party_units() == [b,a] and held_rows == [a,b], "new order leaves earlier query snapshot intact")
	a.free()
	check(w.party_units() == [b], "freed actor cannot remain in cached party")
	check(w.units_near(Vector2.ZERO,1.0) == [b], "freed actor cannot remain in cached spatial query")
	var c := GameUnit.new(); c.uid = 1; c.controller = 0; c.world = w
	w.set_unit(1,c)
	check(w.party_units() == [b,c] and w.units_near(Vector2.ZERO,1.0) == [b,c], "reused ID resolves only the new generation")
	var plain: Node3D = b
	plain.set_script(null)
	check(w.party_units() == [c] and w.units_near(Vector2.ZERO,1.0) == [c],"script replacement removes cached party eligibility")
	w.units = {}; plain.free(); c.free(); w.free()
