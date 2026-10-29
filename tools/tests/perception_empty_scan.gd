extends Node
## A perception scan whose notice cells hold nobody must not call the
## perception kernels: the Foothills' per-NPC sighting triggers force about
## sixty such scans a tick, and the kernel calls were their whole cost. The
## drop pass (retained units leaving, corpses) still runs on an empty scan,
## and a scan with somebody near still calls the kernel once and notices the
## same units as the script path.
var checks := 0
var failures := 0

class CountingKernel extends RefCounted:
	var inner: RefCounted
	var calls := 0
	func new_visible(candidates: Array, unit_script: Script, observer: Object, world: Object, ai: Object,
			terms: PackedFloat64Array, noticed: Dictionary, corpses: Dictionary, radius: float) -> Variant:
		calls += 1
		return inner.new_visible(candidates, unit_script, observer, world, ai, terms, noticed, corpses, radius)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func unit(w: GameWorld, uid: int, at: Vector2, faction: int, controller := -1) -> GameUnit:
	var u := GameUnit.new()
	u.world = w; u.uid = uid; u.pos = at; u.faction = faction; u.controller = controller
	u.stats = {"sight": 15.0}
	u.proto = {"senses": [15.0, 100.0, 5.0], "peripheral_skills": 3.0, "detection": [1.0, 1.0, 1.0]}
	w.set_unit(uid, u)
	return u

## A fresh scan: past the per-tick memo and the 8–11 tick candidate cache.
func scan(w: GameWorld, u: GameUnit) -> Dictionary:
	w.time += 1.0
	u.remove_meta("ai_near_t")
	return w.ai.player_perceive(u, true).duplicate()

func _ready() -> void:
	check(ClassDB.class_exists("PerceptionKernel"), "native perception kernel present")
	var w := GameWorld.new(); w.zone = {"type": "game"}
	var counting := CountingKernel.new(); counting.inner = w.ai._perception; w.ai._perception = counting
	var u := unit(w, 1, Vector2.ZERO, 1, 0)   # a party observer scans everyone
	# Nobody around.
	var noticed := scan(w, u)
	check(noticed.is_empty(), "a lone observer notices nobody")
	check(counting.calls == 0, "an empty scan calls no perception kernel (%d calls)" % counting.calls)
	# Somebody in front: the kernel runs once and agrees with the script path.
	var t := unit(w, 2, Vector2(5.0, 0.0), 2)
	noticed = scan(w, u)
	check(noticed.size() == 1 and noticed.has(t.get_instance_id()), "a target in front is noticed")
	check(counting.calls == 1, "a scan with a candidate calls the kernel once (%d calls)" % counting.calls)
	var before := counting.calls
	w.ai._perception = null
	u.remove_meta("noticed")
	var scripted := scan(w, u)
	w.ai._perception = counting
	check(scripted.keys() == noticed.keys(), "the script path notices the same target")
	# The retained target walks out of the notice cells: the empty scan still
	# runs the drop pass and the target leaves the list, without a kernel call.
	t.pos = Vector2(600.0, 0.0)
	noticed = scan(w, u)
	check(noticed.is_empty() and not u.has_meta("noticed"), "a retained target beyond every notice cell is dropped by an empty scan")
	check(counting.calls == before, "the dropping scan calls no kernel (%d calls)" % (counting.calls - before))
	# A retained target that dies moves to the corpse list on an empty scan too.
	t.pos = Vector2(5.0, 0.0)
	noticed = scan(w, u)
	check(noticed.has(t.get_instance_id()), "the returning target is noticed again")
	t.dead = true; t.pos = Vector2(600.0, 0.0)
	noticed = scan(w, u)
	check(noticed.is_empty() and u.get_meta("seen_corpses", {}).has(t.get_instance_id()), "a retained target that died is remembered as a corpse by an empty scan")
	check(counting.calls == before + 1, "only the scan that had a candidate called the kernel (%d calls)" % counting.calls)
	t.free(); u.free(); w.free()
	print("PERCEPTION_EMPTY_SCAN ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
