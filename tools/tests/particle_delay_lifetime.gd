extends Node
## Spell ending bursts must follow their world, including pause, 2x and teardown.
var checks := 0
var failures := []
var calls := 0

class RecordingFx extends ParticleFx:
	var bursts := []
	func spawn(type: int, at: Vector3, size: float, carrier: Object = null, _opt := {}) -> Effect:
		bursts.append([type, at, size, carrier])
		return null
	func ground(_x: float, _y: float) -> float: return 0.0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func wall(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func called() -> void:
	calls += 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 120
	await frames(24)
	var baseline := Performance.get_monitor(Performance.OBJECT_COUNT)
	var retained := []
	for cycle in 3:
		var old := ParticleFx.new()
		add_child(old)
		old.set_process(false)
		for i in 100: old._later(3600.0, called)
		var owner: WeakRef = weakref(old)
		old.free()
		await frames(4)
		var count := Performance.get_monitor(Performance.OBJECT_COUNT) - baseline
		retained.append(count)
		check(owner.get_ref() == null, "world effects are released on exit %d" % cycle)
		check(count < 20, "long delays leave no global timers after exit %d" % cycle)
	check(calls == 0, "unloaded worlds never run ending bursts")
	var fx := ParticleFx.new()
	fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fx)
	fx.set_process(false)
	fx._later(0.0, called)
	check(calls == 0, "zero-duration ending is deferred")
	await frames(4)
	check(calls == 1, "zero-duration ending runs once")
	await wall(0.1)
	check(calls == 1 and fx.get_child_count() == 0, "completed ending releases its timer")
	fx._later(0.1, called)
	fx.process_mode = Node.PROCESS_MODE_DISABLED
	await wall(0.2)
	check(calls == 1, "paused world suspends ending bursts")
	fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	await wall(0.2)
	check(calls == 2, "world resume completes the pending ending")
	fx._later(0.1, called)
	get_tree().paused = true
	await wall(0.2)
	check(calls == 2, "scene pause suspends ending bursts")
	get_tree().paused = false
	await wall(0.2)
	check(calls == 3, "scene resume completes the pending ending")
	Engine.time_scale = 1.0
	fx._later(0.3, called)
	await wall(0.18)
	check(calls == 3, "normal speed retains a longer delay")
	await wall(0.18)
	check(calls == 4, "normal speed expires after its duration")
	Engine.time_scale = 2.0
	fx._later(0.3, called)
	await wall(0.18)
	check(calls == 5, "2x speed advances the ending twice as quickly")
	fx._later(0.1, called)
	fx.finish_emitters()
	await wall(0.2)
	check(calls == 5 and fx.get_child_count() == 0, "round settlement cancels pending ending bursts")
	fx._later(0.1, called)
	remove_child(fx)
	add_child(fx)
	await wall(0.2)
	check(calls == 5, "detaching a world cancels its old ending bursts")
	fx.free()
	Engine.time_scale = 1.0
	var world := GameWorld.new()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(world)
	var unit := GameUnit.new()
	unit.world = world
	world.add_child(unit)
	world.set_unit(17, unit)
	var recorder := RecordingFx.new()
	recorder.process_mode = Node.PROCESS_MODE_PAUSABLE
	recorder.world = world
	world.add_child(recorder)
	recorder.set_process(false)
	for code: String in ["weak", "strength", "lichdom"]:
		var type := 0x2018 if code == "lichdom" else 0x201b
		var amount := -2.0 if code == "weak" else 2.0
		recorder.bursts.clear()
		recorder.magic_fx({"uid":17, "code":code, "secs":0.05, "s":2.0})
		check(recorder.bursts == [[type, Vector3.ZERO, amount, unit]], code + " retains its starting burst")
		await wall(0.12)
		check(recorder.bursts == [[type, Vector3.ZERO, amount, unit], [type, Vector3.ZERO, -amount, unit]], code + " ends once on the original carrier")
		recorder.bursts.clear()
		recorder.magic_fx({"uid":17, "code":code, "secs":0.05, "s":2.0, "replay":true})
		check(recorder.bursts.is_empty(), code + " replay skips the starting burst")
		await wall(0.12)
		check(recorder.bursts == [[type, Vector3.ZERO, -amount, unit]], code + " replay retains the remaining ending")
	# Recasting refreshes one active gameplay effect. Its visual ending must
	# not retain one long-lived timer per cast or fire at the old deadline.
	var refresh_counts := []
	for code: String in ["weak", "strength", "lichdom"]:
		recorder.bursts.clear()
		for i in 256:
			recorder.magic_fx({"uid":17, "code":code, "secs":3600.0, "s":2.0})
		await frames(2)
		refresh_counts.append(recorder._delayed.size())
		check(recorder._delayed.size() == 1 and recorder.get_child_count() == 1,
			code + " refreshes retain one timer regardless of cast count")
		check(recorder.bursts.size() == 1, code + " same-power refresh does not restart its burst")
		recorder.finish_emitters()
		await frames(2)
	recorder.bursts.clear()
	recorder.magic_fx({"uid":17, "code":"weak", "secs":0.1, "s":2.0})
	await wall(0.05)
	recorder.magic_fx({"uid":17, "code":"weak", "secs":0.25, "s":2.0})
	await wall(0.12)
	check(recorder.bursts == [[0x201b, Vector3.ZERO, -2.0, unit]], "refresh cancels the old ending deadline")
	await wall(0.2)
	check(recorder.bursts == [[0x201b, Vector3.ZERO, -2.0, unit], [0x201b, Vector3.ZERO, 2.0, unit]],
		"refreshed weakness ends once at its new deadline")
	recorder.bursts.clear()
	recorder.magic_fx({"uid":17, "code":"weak", "secs":3600.0, "s":2.0})
	recorder.magic_fx({"uid":17, "code":"weak", "secs":0.05, "s":3.0})
	check(recorder.bursts == [[0x201b, Vector3.ZERO, -2.0, unit], [0x201b, Vector3.ZERO, -3.0, unit],
		[0x201b, Vector3.ZERO, 2.0, unit]], "power change replaces the old burst as in the native effect list")
	check(recorder._delayed.size() == 1, "power change reuses the same ending timer")
	await wall(0.12)
	check(recorder.bursts[-1] == [0x201b, Vector3.ZERO, 3.0, unit] and recorder.bursts.size() == 4,
		"power change ends with the latest strength")
	recorder.bursts.clear()
	recorder.magic_fx({"uid":17, "code":"weak", "secs":3600.0, "s":2.0})
	recorder.magic_fx({"uid":17, "code":"strength", "secs":3600.0, "s":2.0})
	recorder.magic_fx({"uid":17, "code":"lichdom", "secs":3600.0, "s":2.0})
	check(recorder._delayed.size() == 3, "different effects retain independent endings")
	unit.dead = true
	recorder._tick()
	await frames(2)
	check(recorder._delayed.is_empty() and recorder.get_child_count() == 0,
		"death releases long-lived effect timers on the next visual tick")
	check(recorder.bursts.size() == 3, "death does not create ending bursts on a corpse")
	recorder.finish_emitters()
	unit.dead = false
	var other := GameUnit.new()
	other.world = world
	world.add_child(other)
	world.set_unit(18, other)
	recorder.magic_fx({"uid":17, "code":"weak", "secs":3600.0, "s":2.0, "replay":true})
	recorder.magic_fx({"uid":18, "code":"weak", "secs":3600.0, "s":2.0, "replay":true})
	check(recorder._delayed.size() == 2, "different units keep independent same-type effects")
	world.erase_unit(18)
	world.remove_child(other)
	recorder._tick()
	await frames(2)
	check(recorder._delayed.size() == 1, "detaching a carrier promptly releases its timer")
	other.free()
	recorder.finish_emitters()
	recorder.bursts.clear()
	recorder.magic_fx({"uid":17, "code":"weak", "secs":0.05, "s":2.0, "replay":true})
	unit.dead = true
	await wall(0.12)
	check(recorder.bursts.is_empty(), "timer expiry cannot create an ending burst on a corpse")
	unit.dead = false
	recorder.bursts.clear()
	recorder.magic_fx({"uid":17, "code":"weak", "secs":0.05, "s":2.0, "replay":true})
	world.erase_unit(17)
	unit.free()
	await wall(0.12)
	check(recorder.bursts.is_empty(), "freed carrier cannot receive a delayed burst")
	recorder.spell_cast({"code":"clairvoyence", "x":14, "y":22, "left":0.66})
	check(recorder.bursts.size() == 1 and recorder.bursts[0][0] == 0x2018, "clairvoyance starts its original point burst")
	await wall(0.2)
	check(recorder.bursts.size() == 2 and recorder.bursts[0][1] == recorder.bursts[1][1] and recorder.bursts[0][2] == -recorder.bursts[1][2], "clairvoyance ends at the original point with reversed size")
	world.free()
	await frames(2)
	var before_magic_worlds := Performance.get_monitor(Performance.OBJECT_COUNT)
	for cycle in 3:
		var w := GameWorld.new()
		w.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(w)
		var u := GameUnit.new()
		u.world = w
		w.add_child(u)
		w.set_unit(17, u)
		var owned := RecordingFx.new()
		owned.world = w
		w.add_child(owned)
		for code: String in ["weak", "strength", "lichdom"]:
			owned.magic_fx({"uid":17, "code":code, "secs":3600.0, "replay":true})
		var wr: WeakRef = weakref(w)
		var fr: WeakRef = weakref(owned)
		w.free()
		await frames(3)
		check(wr.get_ref() == null and fr.get_ref() == null, "active magic endings release with their world %d" % cycle)
		check(Performance.get_monitor(Performance.OBJECT_COUNT) - before_magic_worlds < 20,
			"active magic endings leave no retained callbacks %d" % cycle)
	print("PARTICLE_DELAY_LIFETIME ", JSON.stringify({"checks":checks,"failures":failures,"retained_objects":retained,"refresh_timers":refresh_counts}))
	get_tree().quit(0 if failures.is_empty() else 1)
