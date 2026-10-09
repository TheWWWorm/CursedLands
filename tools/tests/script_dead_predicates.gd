extends Node
## IsDead's native null boundary and the remake's retained looted corpses.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func _ready() -> void:
	var vm := ScriptVM.new()
	var w := GameWorld.new(); vm.world = w
	var inst := ScriptVM.Instance.new()
	var args := [[ScriptParser.N_VAR,"target"]]
	inst.locals.target = null
	check(vm._call("IsDead",args,inst)==0.0,"missing actor is not a death")
	check(vm._call("IsAlive",args,inst)==0.0,"missing actor is not alive")
	var u := GameUnit.new(); u.uid = 44; u.world = w; inst.locals.target = u
	check(vm._call("IsDead",args,inst)==0.0,"living actor is not dead")
	check(vm._call("IsAlive",args,inst)==1.0,"living actor is alive")
	u.dead = true
	check(vm._call("IsDead",args,inst)==1.0,"dead actor satisfies death predicate")
	check(vm._call("IsAlive",args,inst)==0.0,"dead actor is not alive")
	w.looted[u.uid] = u
	check(vm._call("IsDead",args,inst)==1.0,"retained looted corpse remains dead")
	check(vm._call("IsAlive",args,inst)==0.0,"retained looted corpse is not alive")
	w.looted.clear(); u.free()
	check(vm._call("IsDead",args,inst)==0.0,"freed actor does not become a kill")
	check(vm._call("IsAlive",args,inst)==0.0,"freed actor is not alive")
	var obj := Node3D.new(); inst.locals.target = obj
	check(vm._call("IsDead",args,inst)==0.0,"map object without a unit body is not dead")
	obj.free(); inst.locals.target = 7.0
	check(vm._call("IsDead",args,inst)==0.0,"non-object argument is not a death")
	vm.world = null; w.free()
	print("SCRIPT_DEAD_PREDICATES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
