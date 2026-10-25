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

func compare(expression: Array, label: String) -> void:
	var before_locals := inst.locals.duplicate(true)
	var before_globals := vm.globals.duplicate(true)
	var before_vars := vm.session.state.vars.duplicate(true)
	vm._expression_kernel = null
	seed(81479)
	var expected = vm._eval(expression,inst)
	var expected_rng := randi()
	var expected_locals := var_to_bytes(inst.locals)
	var expected_globals := var_to_bytes(vm.globals)
	var expected_vars := var_to_bytes(vm.session.state.vars)
	inst.locals = before_locals
	vm.globals = before_globals
	vm.session.state.vars = before_vars
	vm._expression_kernel = kernel
	seed(81479)
	var actual = vm._eval(expression,inst)
	check(same(actual,expected),label+" value")
	check(randi()==expected_rng,label+" RNG consumption")
	check(var_to_bytes(inst.locals)==expected_locals,label+" local writes")
	check(var_to_bytes(vm.globals)==expected_globals,label+" global writes")
	check(var_to_bytes(vm.session.state.vars)==expected_vars,label+" campaign writes")

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
