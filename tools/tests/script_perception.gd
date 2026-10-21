extends Node
## Script vision reads the AI's retained lists: UnitSee / GroupSee / PlayerSee
## (0x4b5b00, 0xa5) the noticed lists, IsUnitVisible (0xe5) also the player's
## corpse lists. The lists are supplied as the AI's state for this tick.
const P := preload("res://src/game/script/script_parser.gd")
var checks := 0
var failures := 0

class FlatWorld extends GameWorld:
	func ground_at(_x: float, _y: float) -> float:
		return 0.0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func unit(world: GameWorld, uid: int, at: Vector2, controller: int, dead := false) -> GameUnit:
	var u := GameUnit.new()
	u.world = world
	u.uid = uid
	u.pos = at
	u.max_hp = 10.0
	u.hp = 0.0 if dead else 10.0
	u.dead = dead
	u.controller = controller
	u.stats = {"sight": 10.0}
	world.adopt_prepared_unit(u)
	return u

## The AI's lists for this tick (UnitAI.player_perceive's retained state).
func retain(world: GameWorld, w: GameUnit, noticed: Array, corpses := []) -> void:
	var keep := {}
	for o: GameUnit in noticed: keep[o.get_instance_id()] = o
	var dead := {}
	for o: GameUnit in corpses: dead[o.get_instance_id()] = o
	w.set_meta("noticed", keep)
	w.set_meta("seen_corpses", dead)
	w.set_meta("perceived", world.time)

func query(vm: ScriptVM, inst: ScriptVM.Instance, name: String, args: Array):
	var nodes := []
	for a in args:
		nodes.append(a if a is Array else [P.N_NUM, float(a)])
	return vm._eval([P.N_CALL, name, nodes], inst)

func _ready() -> void:
	var world := FlatWorld.new()
	world.authority = false
	world.zone = {"type": "game"}
	var session := Session.new()
	session.state = CampaignState.new()
	session.coop = CoopProgress.new()
	session.coop.session = session
	session.add_child(session.coop)
	var vm := ScriptVM.new()
	vm.world = world
	vm.session = session
	vm.ast = ScriptParser.new()
	var hero := unit(world, 1, Vector2.ZERO, 0)
	var guard := unit(world, 2, Vector2(50, 0), -1)
	var corpse := unit(world, 3, Vector2(1, 0), -1, true)
	var bystander := unit(world, 4, Vector2(2, 0), -1)
	retain(world, guard, [hero])
	retain(world, hero, [bystander], [corpse])
	var inst := ScriptVM.Instance.new()
	inst.locals = {"guard": guard, "guards": [guard], "hero": hero, "corpse": corpse}
	var g := [P.N_VAR, "guard"]

	check(query(vm, inst, "UnitSee", [g]) == [hero], "a retained hero stays seen beyond sight range")
	check(query(vm, inst, "GroupHas", [[P.N_CALL, "UnitSee", [g]], [P.N_VAR, "hero"]]) == 1.0, "GroupHas(UnitSee) reads the same list")
	guard.dead = true
	check(query(vm, inst, "UnitSee", [g]) == [hero], "a dead watcher keeps the list it had")
	check(query(vm, inst, "GroupSee", [[P.N_VAR, "guards"]]) == [hero], "GroupSee reads dead watchers too")
	var seen: Array = query(vm, inst, "PlayerSee", [0])
	check(seen.has(hero) and seen.has(bystander) and not seen.has(corpse), "PlayerSee leaves out the corpse list")
	check(query(vm, inst, "IsUnitVisible", [[P.N_VAR, "corpse"]]) == 1.0, "IsUnitVisible includes the corpse list")
	check(query(vm, inst, "PlayerSee", [1]) == [], "single player has no player 1")

	session.free()
	for u: GameUnit in [hero, guard, corpse, bystander]:
		world.units.erase(u.uid)
		u.free()
	world.free()
	print("SCRIPT_PERCEPTION ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
