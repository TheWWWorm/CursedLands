extends Node
## Native expression traversal must preserve the interpreter's values, reads,
## argument order and float32 boundary at every nested expression.
const P = preload("res://src/game/script/script_parser.gd")
var checks := 0
var failures := 0
var vm: ScriptVM
var inst: ScriptVM.Instance
var kernel: RefCounted

class DerivedVM extends ScriptVM:
	func _get_var(_name: String, _inst: Instance):
		return 123.0

class DerivedUnit extends GameUnit:
	pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func n(value) -> Array:
	return [P.N_NUM,value]
func v(name: String) -> Array:
	return [P.N_VAR,name]
func c(name: String, args: Array) -> Array:
	return [P.N_CALL,name,args]
func same(a, b) -> bool:
	if a is float and b is float and is_nan(a) and is_nan(b): return true
	return is_same(a,b) if a is Object or b is Object else var_to_bytes(a) == var_to_bytes(b)

func compare(expression: Array, label: String, prepare := Callable()) -> void:
	var before_locals := inst.locals.duplicate(true)
	var before_globals := vm.globals.duplicate(true)
	var before_vars := vm.session.state.vars.duplicate(true)
	var native := kernel
	vm._expression_kernel = null
	if prepare.is_valid(): prepare.call()
	seed(81479)
	var expected = vm._eval(expression,inst)
	var expected_rng := randi()
	var expected_locals := var_to_bytes(inst.locals)
	var expected_globals := var_to_bytes(vm.globals)
	var expected_vars := var_to_bytes(vm.session.state.vars)
	inst.locals = before_locals
	vm.globals = before_globals
	vm.session.state.vars = before_vars
	vm._expression_kernel = native
	if prepare.is_valid(): prepare.call()
	seed(81479)
	var actual = vm._eval(expression,inst)
	check(same(actual,expected),label+" value")
	check(randi()==expected_rng,label+" RNG consumption")
	check(var_to_bytes(inst.locals)==expected_locals,label+" local writes")
	check(var_to_bytes(vm.globals)==expected_globals,label+" global writes")
	check(var_to_bytes(vm.session.state.vars)==expected_vars,label+" campaign writes")

## Watchers' noticed lists: living ones from the tick memo (ScriptVM._noticed),
## so no AI refresh runs; a dead one from its retained "noticed" record.
var seen := {}
func seed_seen() -> void:
	vm._in_tick = true
	vm._seen_memo = seen.duplicate()

func perception_cases(world: GameWorld, scenery: Node3D) -> void:
	var names: PackedStringArray = kernel.native_calls() if kernel.has_method("native_calls") else PackedStringArray()
	for name in ["GroupSize","IsDead","UnitSee","GroupSee","GroupHas","GroupCross"]:
		check(names.has(name),"native "+name)
	var units := {}
	for row in [["alive",101,1,false],["dead",102,2,true],["unseen",103,0,false],["looted",104,4,false],
			["w1",111,11,false],["w2",112,12,false],["w3",113,13,true],["derived",120,20,true],["gone",130,30,false]]:
		var u: GameUnit = DerivedUnit.new() if row[0] == "derived" else GameUnit.new()
		u.uid = row[1];u._seq = row[2];u.world = world;world.set_unit(row[1],u)
		u.dead = row[3]
		units[row[0]] = u
	world.looted[104] = units.looted
	var heroes := [units.alive,units.dead,units.unseen]
	seen = {units.w1:[units.alive,units.dead,units.unseen,units.looted],units.w2:[units.dead,units.w1,units.derived],
		units.looted:[units.alive],units.alive:[units.w1],units.unseen:[]}
	units.w3.set_meta("noticed",{1:units.alive,2:units.w3,3:units.derived})
	var group := [units.w1,units.w2,units.w3,units.alive,null,units.gone,4.0,scenery,units.looted]
	units.gone.free()
	inst.locals.heroes = heroes
	inst.locals.g = group
	inst.locals.watchers = [units.w1,units.w3,units.looted,units.w2]
	var values := [units.alive,units.dead,units.unseen,units.looted,units.derived,units.w1,units.w3,scenery,
		null,0.0,3.0,"unit",[],group,heroes,{},PackedInt32Array([1]),Vector2.ONE]
	for i in values.size():
		inst.locals.x = values[i]
		var label := " value %d" % i
		compare(c("GroupSize",[v("x")]),"group size"+label,seed_seen)
		compare(c("IsDead",[v("x")]),"dead"+label,seed_seen)
		compare(c("UnitSee",[v("x")]),"unit sees"+label,seed_seen)
		compare(c("GroupSee",[v("x")]),"group sees"+label,seed_seen)
		compare(c("GroupHas",[v("g"),v("x")]),"group has"+label,seed_seen)
		compare(c("GroupHas",[c("UnitSee",[v("x")]),v("alive")]),"lazy unit sight has"+label,seed_seen)
		compare(c("GroupHas",[c("GroupSee",[v("watchers")]),v("x")]),"lazy group sight has"+label,seed_seen)
		compare(c("GroupCross",[v("x"),v("heroes")]),"cross"+label,seed_seen)
		compare(c("GroupCross",[v("heroes"),c("UnitSee",[v("x")])]),"lazy unit sight cross"+label,seed_seen)
		compare(c("GroupCross",[v("x"),c("GroupSee",[v("watchers")])]),"lazy group sight cross"+label,seed_seen)
		compare(c("GroupSize",[c("GroupCross",[c("UnitSee",[v("x")]),v("heroes")])]),"Foothills watcher"+label,seed_seen)
	inst.locals.alive = units.alive
	for w in ["w1","w2","w3","looted","derived"]:
		inst.locals.w = units[w]
		compare(c("GroupSize",[c("GroupCross",[c("UnitSee",[v("w")]),v("heroes")])]),"watcher sees heroes "+w,seed_seen)
		compare(c("GroupCross",[v("g"),c("UnitSee",[v("w")])]),"watcher among candidates "+w,seed_seen)
		compare(c("GroupHas",[c("UnitSee",[v("w")]),v("w")]),"watcher sees itself "+w,seed_seen)
	compare(c("GroupSize",[c("GroupCross",[c("GroupSee",[v("watchers")]),v("heroes")])]),"group watchers see heroes",seed_seen)
	# Argument order, single evaluation and RNG of nested interpreter calls.
	var write := c("GSSetVar",[n(0),[P.N_STR,"seen"],n(5)])
	inst.locals.w = units.w3
	compare(c("GroupCross",[write,c("UnitSee",[v("w")])]),"lazy cross evaluates the group first",seed_seen)
	compare(c("GroupCross",[c("UnitSee",[v("w")]),write]),"cross evaluates left to right",seed_seen)
	compare(c("GroupHas",[c("UnitSee",[v("w")]),write]),"lazy has evaluates the watcher first",seed_seen)
	compare(c("GroupHas",[v("g"),c("Random",[n(3)])]),"group has random target",seed_seen)
	compare(c("IsDead",[c("GetObject",[c("Add",[n(101),c("Random",[n(2)])])])]),"dead random object",seed_seen)
	compare(c("GroupSize",[c("GSGetVar",[n(0),[P.N_STR,"seen"]])]),"group size of a variable",seed_seen)
	# Shapes the interpreter judges: arity, two-argument sight, empty calls.
	compare(c("GroupSize",[v("g"),v("heroes")]),"group size extra argument",seed_seen)
	compare(c("GroupHas",[v("g"),v("x"),v("x")]),"group has extra argument",seed_seen)
	compare(c("GroupCross",[v("heroes"),c("UnitSee",[v("w"),v("w")])]),"two-argument sight",seed_seen)
	compare(c("GroupCross",[v("heroes"),[P.N_CALL,"GroupSee",[v("watchers")],0]]),"sight call with an extra field",seed_seen)
	compare(c("GroupCross",[v("heroes"),[P.N_VAR,"UnitSee"]]),"variable named UnitSee",seed_seen)
	# Libraries with the operations but no configured unit class.
	var bare: RefCounted = ClassDB.instantiate("ScriptExpressionKernel")
	var configured := kernel
	kernel = bare
	inst.locals.w = units.w1
	compare(c("GroupSize",[c("GroupCross",[c("UnitSee",[v("w")]),v("heroes")])]),"unconfigured unit queries",seed_seen)
	compare(c("IsDead",[v("alive")]),"unconfigured death query",seed_seen)
	kernel = configured
	# Live state: a later death and a removed watcher are seen at once.
	compare(c("IsDead",[v("alive")]),"alive before death",seed_seen)
	units.alive.dead = true
	compare(c("IsDead",[v("alive")]),"death changed in place",seed_seen)
	inst.locals.w = units.w2
	seen.erase(units.w2)
	units.w2.dead = true;units.w2.set_meta("noticed",{})
	compare(c("GroupCross",[v("heroes"),c("UnitSee",[v("w")])]),"watcher died",seed_seen)
	vm._in_tick = false;vm._seen_memo.clear()
	for key in ["x","w","g","watchers","heroes","alive"]: inst.locals.erase(key)
	world.looted.clear()
	for name in units:
		if is_instance_valid(units[name]):
			world.erase_unit(units[name].uid);units[name].free()

func _ready() -> void:
	check(ClassDB.class_exists("ScriptExpressionKernel"),"native expression implementation is present")
	if failures:
		print("SCRIPT_EXPRESSION_NATIVE ",checks," checks ",failures," failures")
		get_tree().quit(1);return
	vm=ScriptVM.new();inst=ScriptVM.Instance.new();kernel=vm._expression_kernel
	check(kernel!=null,"production VM selects native expressions")
	var world:=GameWorld.new();vm.world=world
	var session:=Session.new();session.state=CampaignState.new();vm.session=session
	for value in [0.0,-0.0,1.0,-1.0,16777217.0,1.0e-40,1.0e39,INF,-INF,NAN,42,true,false,"12.5","",null,[],[1],{},Vector2.ZERO]:
		inst.locals.x=value
		compare(v("x"),"local "+str(value))
		compare(c("Not",[v("x")]),"truth "+str(value))
		compare(c("IsEqual",[v("x"),n(0)]),"numeric conversion "+str(value))
		compare(c("IsEqualString",[v("x"),[P.N_STR,str(value)]]),"string conversion "+str(value))
	vm.globals.x=2.0;inst.locals.x=3.0
	compare(v("x"),"local shadows global")
	inst.locals.erase("x");compare(v("x"),"live global")
	vm.globals.x=4.0;compare(v("x"),"global mutation")
	compare(v("absent"),"missing variable")
	compare(v("NULL"),"NULL literal")
	inst.locals.NULL=7.0;compare(v("NULL"),"local NULL shadows literal")
	compare(c("Add",[n(16777217),n(-16777216)]),"nested float32 before addition")
	# Original game 1.06 under Wine: GiveMoney displays Money (17).
	var original := c("Add",[c("Sub",[c("Mul",[n(7),n(3)]),c("Div",[n(8),n(2)])]),c("Add",[n(16777217),n(-16777216)])])
	check(vm._eval(original,inst)==17.0,"original Wine arithmetic fixture")
	var rng:=RandomNumberGenerator.new();rng.seed=44261
	for i in 600:
		var a:=rng.randf_range(-100000000.0,100000000.0)
		var b:=rng.randf_range(0.125,1000000.0)
		for op in ["Add","Sub","Mul","Div","IsLess","IsGreater","IsEqual"]:
			compare(c(op,[c("Add",[n(a),n(.0625)]),n(b)]),"nested "+op+str(i))
	for name in ["Random","GetWorldTime","GSGetVar"]:
		var args:= [n(17)] if name=="Random" else ([n(0),[P.N_STR,"probe"]] if name=="GSGetVar" else [])
		compare(c("Add",[c(name,args),n(2)]),"fallback "+name)
	# Changing arguments must not leave a compiled/cached answer behind.
	var expression:=c("Add",[n(1),n(2)])
	compare(expression,"initial AST");expression[2][1][1]=9;compare(expression,"edited AST")
	var unit:=GameUnit.new();unit.uid=77;unit.world=world;world.set_unit(77,unit)
	var obj:=Node3D.new();obj.set_meta("ei",{"nid":88});world.objects[88]=obj
	world.levers[88]={"state":3};world.levers[77]={"state":2}
	for id in [77,88,999]:
		compare(c("GetObject",[n(id)]),"object lookup "+str(id))
		compare(c("GetLeverState",[c("GetObject",[n(id)])]),"Portal lever condition "+str(id))
	var lever:=c("IsEqual",[c("GetLeverState",[c("GetObject",[n(88)])]),n(3)])
	compare(lever,"lever comparison")
	world.levers[88].state=4;compare(lever,"lever changed in place")
	world.levers={88:{"state":3}};compare(lever,"lever dictionary replaced")
	inst.locals.x=unit;compare(c("IsEqual",[v("x"),c("GetObject",[n(77)])]),"same object")
	compare(c("IsEqual",[v("x"),c("GetObject",[n(88)])]),"different objects")
	perception_cases(world,obj)
	world.erase_unit(77);unit.free()
	compare(c("Not",[v("x")]),"freed local object")
	obj.free();compare(lever,"freed scenery")
	# Special forms retain lazy evaluation, iteration and writes.
	inst.locals.items=[1.0,2.0,3.0];inst.locals.i=0.0
	compare(c("Any",[v("i"),v("items"),c("IsGreater",[v("i"),n(1)])]),"Any fallback")
	compare(c("Every",[v("i"),v("items"),c("IsLess",[v("i"),n(5)])]),"Every fallback")
	inst.locals.erase("x")
	var side_effect:=c("Add",[c("GSSetVar",[n(0),[P.N_STR,"probe"],n(19)]),c("GSGetVar",[n(0),[P.N_STR,"probe"]])])
	compare(side_effect,"left-to-right mutating fallback")
	var read := c("GSGetVar",[n(0),[P.N_STR,"probe"]])
	var increment := c("GSSetVar",[n(0),[P.N_STR,"probe"],c("Add",[read,n(1)])])
	compare(c("Add",[increment,read]),"mutating fallback executes exactly once")
	for divisor in [0.0,-0.0,INF,-INF,NAN]:
		compare(c("Div",[n(1),n(divisor)]),"division boundary "+str(divisor))
	var derived:=DerivedVM.new()
	check(derived._eval(v("x"),inst)==123.0,"derived VMs preserve overrides")
	vm._expression_kernel=null
	check(vm._eval(c("Add",[n(2),n(3)]),inst)==5.0,"missing helper fallback")
	vm.world=null;vm.session=null;world.free();session.free()
	print("SCRIPT_EXPRESSION_NATIVE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
