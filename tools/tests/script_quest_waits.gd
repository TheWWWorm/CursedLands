extends Node
## Save/load and parser integration for waits qualified against both native
## dispatchers. The native suite separately checks every tick's outputs.
var checks := 0
var failures := 0
const SOURCE := """
GlobalVars ( phase : float delay : float ready : float )
DeclareScript Waiter ()
Script Waiter (
    if () then (
        phase = 1
        Sleep(Add(delay, 0))
        phase = Add(phase, 1)
        SleepUntil(ready)
        KillScript()
        phase = Add(phase, 1)
    )
)
WorldScript ()
"""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func make_vm() -> ScriptVM:
	var vm := ScriptVM.new()
	vm.world = GameWorld.new()
	vm.session = Session.new()
	vm.session.state = CampaignState.new()
	vm.ast = ScriptParser.parse(SOURCE)
	vm.globals = {"phase": 0.0, "delay": 0.0, "ready": 1.0}
	return vm

func release(vm: ScriptVM) -> void:
	vm.session.free()
	vm.world.free()

func step(vm: ScriptVM) -> void:
	vm.time += ScriptVM.SLEEP_UNIT
	for inst: ScriptVM.Instance in vm.instances: vm._run(inst)

func restore(saved: Dictionary) -> ScriptVM:
	var result := make_vm()
	result.time = 1000.0
	result._restore(bytes_to_var(var_to_bytes(saved)))
	return result

func _ready() -> void:
	for delay in [-2.0, 0.0, 0.5, 1.0, 2.5, 3.5, 12.0]:
		var vm := make_vm()
		check(vm.ast.errors.is_empty(), "wait script parses")
		vm.globals.delay = delay
		vm.spawn("Waiter", [])
		step(vm)
		var duration := maxi(0, NavGrid.round_even(delay))
		check(vm.globals.phase == (3.0 if duration == 0 else 1.0), "initial wait boundary " + str(delay))
		if duration > 0:
			var saved := vm.save_state()
			check(saved.instances[0].has("sc") and saved.instances[0].st == 0, "save retains delay expression and elapsed runs")
			var loaded := restore(saved)
			check(loaded.instances.size() == 1, "waiting instance restored")
			for tick in duration:
				step(vm)
				step(loaded)
				check(vm.globals.phase == loaded.globals.phase, "reload preserves exact resume tick")
			check(loaded.globals.phase == 3 and loaded.instances[0].killed, "body continues after KillScript")
			check(loaded.instances[0].frames.is_empty(), "completed body leaves no waiting frame")
			release(loaded)
		release(vm)

	var dynamic := make_vm()
	dynamic.globals.delay = 12.0
	dynamic.spawn("Waiter", [])
	for i in 4: step(dynamic)
	var saved := dynamic.save_state()
	check(saved.instances[0].st == 3, "elapsed runs survive a mid-wait save")
	var loaded := restore(saved)
	loaded.globals.delay = 3.0
	step(loaded)
	check(loaded.globals.phase == 3.0, "changed delay is reevaluated after load")
	release(loaded)

	# Older saves have only a duration in seconds. Keep accepting that field.
	var legacy: Dictionary = saved.duplicate(true)
	legacy.instances[0].erase("sc")
	legacy.instances[0].erase("st")
	loaded = restore(legacy)
	check(loaded.instances.size() == 1 and loaded.globals.phase == 1, "older pending-wait save is accepted")
	for i in 12: step(loaded)
	check(loaded.globals.phase == 3, "older pending-wait save resumes")
	release(loaded)
	release(dynamic)

	var waiting := make_vm()
	waiting.globals.ready = 0.0
	waiting.spawn("Waiter", [])
	step(waiting)
	check(waiting.globals.phase == 2, "false SleepUntil pauses after zero-length Sleep")
	loaded = restore(waiting.save_state())
	step(loaded)
	check(loaded.globals.phase == 2, "restored false condition stays asleep")
	loaded.globals.ready = 1.0
	step(loaded)
	check(loaded.globals.phase == 3, "restored condition resumes on its first true poll")
	release(loaded)
	release(waiting)
	print("SCRIPT_QUEST_WAITS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
