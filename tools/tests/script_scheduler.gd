extends Node
## The original script scheduler (0x4bf000) through the production parser
## and ScriptVM.tick: every true block fires in one pass, bodies run
## concurrently on copies of the locals, new scripts are polled in the same
## or the next pass depending on who started them, and briefing handlers are
## polled in the pass after the completion.
var checks := 0
var failures := 0

class QuietBriefings extends Briefings:
	func tick() -> void:
		pass

const PROGRAM := """
GlobalVars ( light : float, particle : float, n : float, p : float, seen : float,
	worldchild : float, child : float, handled : float, slept : float )
DeclareScript Point ( lit : float )
DeclareScript Repeat ( )
DeclareScript Local ( v : float )
DeclareScript FromWorld ( )
DeclareScript Parent ( )
DeclareScript Child ( )
DeclareScript Sleeper ( )
DeclareScript #OnBriefingComplete ( nPlayer : float, szComplete : string )
Script Point
(
	if ( IsEqual( lit, 1 ) ) then ( light = Add( light, 1 ) )
	if ( ) then ( KillScript( ) particle = Add( particle, 1 ) )
)
Script Repeat
(
	if ( IsLess( n, 3 ) ) then ( n = Add( n, 1 ) Sleep( 5 ) p = Add( p, 1 ) )
)
Script Local
(
	if ( IsEqual( v, 0 ) ) then ( v = 1 seen = Add( seen, 1 ) )
)
Script FromWorld
(
	if ( ) then ( KillScript( ) worldchild = 1 )
)
Script Parent
(
	if ( ) then ( KillScript( ) Child( ) )
)
Script Child
(
	if ( ) then ( KillScript( ) child = 1 )
)
Script Sleeper
(
	if ( ) then ( KillScript( ) Sleep( 3 ) slept = 1 )
)
Script #OnBriefingComplete
(
	if ( ) then ( KillScript( ) handled = Add( handled, 1 ) )
)
WorldScript
(
	Point( 1 )
	Point( 0 )
	Repeat( )
	Local( 0 )
	FromWorld( )
	Parent( )
	Sleeper( )
)
"""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func make_vm(session: Session, world: GameWorld) -> ScriptVM:
	var vm := ScriptVM.new()
	vm.world = world
	vm.session = session
	vm.briefings = QuietBriefings.new(vm)
	vm.ast = ScriptParser.parse(PROGRAM)
	for g in vm.ast.globals:
		vm.globals[g] = 0.0
	return vm

func alive(vm: ScriptVM, sname: String) -> int:
	return vm.instances.filter(func(i: ScriptVM.Instance): return i.sname == sname and not i.killed).size()

func running(vm: ScriptVM, sname: String) -> int:
	return vm.instances.filter(func(i: ScriptVM.Instance): return i.sname == sname and not i.frames.is_empty()).size()

func _ready() -> void:
	var world := GameWorld.new()
	var session := Session.new()
	session.state = CampaignState.new()
	session.coop = CoopProgress.new()
	session.coop.session = session
	session.add_child(session.coop)
	var vm := make_vm(session, world)
	check(vm.ast.errors.is_empty(), "production parser accepts the scheduler program")
	vm._start_world(vm.ast.world)

	vm.tick(ScriptVM.SLEEP_UNIT)
	# zone19 CreateRunPoint1: the light block and the KillScript block both
	# fire in the first pass; the instance is gone afterwards.
	check(vm.globals.light == 1.0 and vm.globals.particle == 2.0, "every true block of an instance fires in one pass")
	check(alive(vm, "Point") == 0, "a first-slice KillScript disposes the instance")
	check(vm.globals.worldchild == 1.0, "a script WorldScript starts is polled in the same pass")
	check(vm.globals.child == 0.0, "a script a first slice starts waits for the next pass")
	check(alive(vm, "Sleeper") == 0 and running(vm, "Sleeper") == 1, "KillScript ends the trigger, not its sleeping body")
	vm.tick(ScriptVM.SLEEP_UNIT)
	check(vm.globals.child == 1.0, "the started script is polled in the next pass")
	vm.tick(ScriptVM.SLEEP_UNIT)
	check(vm.globals.light == 1.0 and vm.globals.particle == 2.0, "a disposed instance never fires again")
	check(vm.globals.n == 3.0 and vm.globals.p == 0.0 and running(vm, "Repeat") == 3,
		"a block fires again while its earlier body sleeps")
	check(vm.globals.seen == 3.0, "a body's assignment to a parameter changes its own copy only")

	# Save while Sleeper's body sleeps, then restore into a fresh VM.
	var restored := make_vm(session, world)
	restored._restore(bytes_to_var(var_to_bytes(vm.save_state())))
	check(running(restored, "Sleeper") == 1 and alive(restored, "Sleeper") == 0, "a sleeping body thread survives save/load")
	for i in 3:
		restored.tick(ScriptVM.SLEEP_UNIT)
	check(restored.globals.slept == 1.0, "the restored body finishes its Sleep")

	var events := make_vm(session, world)
	events.fire_event("#OnBriefingComplete", [0.0, "b.test"])
	check(events.globals.handled == 0.0, "a briefing handler does not run inside the completion")
	events.tick(ScriptVM.SLEEP_UNIT)
	check(events.globals.handled == 1.0, "the handler is polled once in the next pass")
	events.tick(ScriptVM.SLEEP_UNIT)
	check(events.globals.handled == 1.0 and alive(events, "#OnBriefingComplete") == 0, "the handler ends with its KillScript")

	session.free()
	world.free()
	print("SCRIPT_SCHEDULER ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
