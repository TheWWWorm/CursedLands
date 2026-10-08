extends Node
## Boundary cases for the frozen batching planner. Rendered-map comparisons
## remain the independent check against actual Godot light selection.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func member(id: int, x: float, layers := 1) -> Dictionary:
	return {"item":id, "bounds":AABB(Vector3(x - 0.5, -0.5, -0.5), Vector3.ONE), "layers":layers}

func light(id: int, bounds: AABB, kind := 0, mask := 1) -> Dictionary:
	return {"id":id, "bounds":bounds, "kind":kind, "mask":mask, "range":20.0, "energy":1.0}

func _ready() -> void:
	var plan: Script = load(get_script().resource_path.get_base_dir().get_base_dir().path_join("benchmarks/scenery_batch_lights.gd"))
	var members := [member(1, -4), member(2, 4)]
	var broad := AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	check(plan.partition(members, [], 8, 256) == [[1, 2]], "unlit members group")
	check(plan.partition(members, [light(1, broad)], 8, 256) == [[1, 2]], "shared complete light set groups")
	var between := [light(2, AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)))]
	check(plan.signature(members[0].bounds, 1, between, 8, 256) == [], "first object excludes middle light")
	check(plan.signature(members[1].bounds, 1, between, 8, 256) == [], "second object excludes middle light")
	check(plan.partition(members, between, 8, 256) == [[1], [2]], "union acquiring an extra light splits the group")
	var crowded := []
	for i in 9:
		crowded.append(light(i + 1, AABB(broad.position + Vector3(0, i, 0), broad.size)))
	check(plan.partition(members, crowded, 8, 256) == [[1], [2]], "truncated engine lists keep original meshes")
	check(plan.partition(members, crowded.slice(0, 4), 4, 256) == [[1, 2]], "four-light mobile budget can group complete sets")
	check(plan.partition(members, crowded.slice(0, 5), 4, 256) == [[1], [2]], "five lights exceed four-light budget")
	check(plan.partition(members, crowded, 0, 256) == [[1, 2]], "disabled light budget has empty selection")
	var mixed := [light(1, broad), light(2, broad), light(3, broad, 1), light(4, broad, 1)]
	check(plan.partition(members, mixed, 2, 256) == [[1, 2]], "light budget applies separately per type")
	check(plan.signature(broad, 1, [light(1, broad, 0, 2)], 8, 256) == [], "light mask excludes unrelated geometry")
	check(plan.partition([member(1, -4, 1), member(2, 4, 2)], [], 8, 256) == [[1], [2]], "geometry masks stay distinct")
	check(plan.partition(members, mixed, 2, 1) == [[1], [2]], "global truncation is not guessed")
	check(plan.signature(broad, 1, [light(1, broad), light(2, broad)], 1, 256, true) == null, "ranked diagnostic does not resolve ambiguous cutoff ties")
	var before := crowded.duplicate(true)
	plan.partition(members, crowded, 8, 256, true)
	check(crowded == before, "planning preserves caller light records")
	print("SCENERY_BATCH_LIGHTS checks=", checks, " failures=", failures)
	get_tree().quit(1 if failures else 0)
