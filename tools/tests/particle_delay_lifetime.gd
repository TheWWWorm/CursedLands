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
	print("PARTICLE_DELAY_LIFETIME ", JSON.stringify({"checks":checks,"failures":failures,"retained_objects":retained}))
	get_tree().quit(0 if failures.is_empty() else 1)
