extends Node
## Differential spatial safety and live capture/invalidation coverage.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _ready() -> void:
	var kernel: RefCounted = ClassDB.instantiate("AIActivityKernel")
	var rng := RandomNumberGenerator.new()
	rng.seed = 461926
	for trial in 400:
		var positions := PackedVector2Array()
		var terms := PackedFloat64Array()
		var factions := PackedInt64Array()
		var flags := PackedByteArray()
		var masks := PackedInt64Array()
		for i in rng.randi_range(0, 100):
			positions.append(Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200)))
			terms.append_array(PackedFloat64Array([rng.randf_range(0, 60), rng.randf_range(0, 40),
				rng.randf_range(0, 10), rng.randf_range(0, 3), rng.randf_range(0, 2)]))
			factions.append(rng.randi_range(0, 31))
			flags.append(rng.randi_range(0, 7) if i % 3 == 0 else 0)
			masks.append(rng.randi())
		var expected := AIActivity.evaluate_senses_script(positions, terms, factions, flags, masks, 16.0)
		check(kernel.evaluate_senses(positions, terms, factions, flags, masks, 16.0) == expected, "independent all-pairs oracle %d" % trial)
	var positions := PackedVector2Array([Vector2.ZERO, Vector2(50, 0)])
	var terms := PackedFloat64Array([5, 0, 0, 1.5, 1, 5, 0, 0, 1.5, 1])
	var factions := PackedInt64Array([1, 2])
	var flags := PackedByteArray([0, 0])
	var masks := PackedInt64Array([4, 2])
	check(kernel.evaluate_senses(positions, terms, factions, flags, masks, 16.0) == PackedByteArray([0, 0]), "far hostile candidate cells stay quiet")
	positions[1] = Vector2(23.5, 0)
	check(kernel.evaluate_senses(positions, terms, factions, flags, masks, 16.0) == PackedByteArray([1, 1]), "exact movement-envelope boundary wakes")
	for bad in [NAN, INF, -1.0]:
		terms[3] = bad
		check(kernel.evaluate_senses(positions, terms, factions, flags, masks, 16.0) == PackedByteArray([1, 1]), "unknown detectability fails open")
	terms[3] = 1.5
	check(kernel.evaluate_senses(positions, terms, factions, PackedByteArray(), masks, 16.0) == PackedByteArray([1, 1]), "malformed rows fail open")
	_live_capture(kernel, rng)
	print("AI_SENSES_CHECKS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)

func _live_capture(kernel: RefCounted, rng: RandomNumberGenerator) -> void:
	var w := GameWorld.new()
	w.time = 1.0
	var units := {}
	for i in 60:
		var u := GameUnit.new()
		u.uid = i + 1; u.world = w; u.faction = i % 5
		u.pos = Vector2(rng.randf_range(-150,150), rng.randf_range(-150,150))
		u.proto = {"name":"senses-%d" % i, "senses":PackedFloat32Array([8, 60, 3]),
			"detection":PackedFloat32Array([1,1,0.7]), "peripheral_skills":2.0}
		u.stats.sight = 8.0
		u.set_meta("calm", {"busy":true, "until":100.0})
		units[u.uid] = u
	w.units = units
	for trial in 40:
		for u: GameUnit in w.unit_rows():
			u.faction = rng.randi_range(0,4)
			u.controller = 1 if u.uid % 19 == 0 else -1
			u.hidden = u.uid % 17 == 0
			u.dead = u.uid % 13 == 0
			u.proto.senses = PackedFloat32Array([8,rng.randf_range(0,150),rng.randf_range(0,15)])
			u.buffs = {"sense": {"sense":[rng.randi_range(0,2),rng.randf_range(0,20)]},
				"detect": {"detect":[rng.randi_range(0,2),rng.randf_range(-2,2)]}}
		w.ai.activity.begin_tick(GameUnit.TICK)
		var expected := w.ai.activity._capture_script(w.unit_rows())
		check(kernel.evaluate_world(w.unit_rows(),w.ai.activity._side_masks,w.darkness(),w.weather_sight_factor(),16.0) == expected, "live capture matches script senses %d" % trial)
		check(w.ai.activity._owned_batch,"native world activity batch")
		var rows := w.unit_rows()
		for i in rows.size():
			check(w.ai.activity._kernel.is_quiet(rows[i]) == (expected[i] == 0),"owned capture matches script senses %d/%d" % [trial,i])
			check(not w.ai.activity._kernel.moved_beyond(rows[i],rows[i].pos,64.0),"origin captured in same native pass")
	var u: GameUnit = units[1]
	w.ai.activity.begin_tick(GameUnit.TICK)
	var origin := u.pos
	u.pos += Vector2(8,0)
	w.ai.activity.moved(u)
	check(w.ai.activity._valid,"exact half-margin stays valid")
	u.pos = origin + Vector2(8.1,0)
	w.ai.activity.moved(u)
	check(not w.ai.activity._valid,"larger same-tick move invalidates")
	u.pos = origin
	for other: GameUnit in units.values(): other.buffs.clear()
	w.ai.activity.begin_tick(GameUnit.TICK)
	check(w.ai.activity._valid, "batch active before a new effect")
	Spells._buff(u,"probe",10,{"detect":[0,4.0]})
	check(not w.ai.activity._valid, "new effect immediately invalidates batch")
	# Removing only a negative effect mid-tick exposes the positive effect.
	var observer: GameUnit = units[1]
	var target: GameUnit = units[2]
	for other: GameUnit in units.values():
		other.hidden = other != observer and other != target
	observer.hidden = false; observer.dead = false; observer.controller = -1
	observer.pos = Vector2.ZERO; observer.stats.sight = 8.0
	observer.proto.senses = PackedFloat32Array([8, 100, 0])
	target.hidden = false; target.dead = false; target.controller = 0
	target.pos = Vector2(45, 0)
	target.buffs = {"minus": {"detect":[0, -3.0]}, "plus": {"detect":[0, 3.0]}}
	w.ai.activity.begin_tick(GameUnit.TICK)
	var active: PackedByteArray = kernel.evaluate_world(w.unit_rows(),w.ai.activity._side_masks,0.0,1.0,16.0)
	check(active[0] == 1, "negative expiry cannot hide a remaining positive detection effect")
	w.units = {}
	for other: GameUnit in units.values(): other.free()
	w.free()
