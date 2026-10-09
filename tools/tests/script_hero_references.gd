extends Node
## A saved stable hero identity must never select an unrelated actor whose
## current deployment happens to reuse the old numeric unit id.
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ", label)
	else:
		failures += 1
		printerr("FAIL ", label)


func _ready() -> void:
	var session := Session.new()
	session.state = CampaignState.new()
	var record := {"name":"Personal hero", "prototype":"Human Hero"}
	session.state.heroes = {0:[record]}
	var world := GameWorld.new()
	world.session = session
	var vm := ScriptVM.new()
	vm.session = session
	vm.world = world
	var hero := GameUnit.new()
	hero.uid = 1500000001
	hero.controller = 0
	hero.set_meta("hero", record)
	world.set_unit(hero.uid, hero)
	var npc := GameUnit.new()
	npc.uid = 1500000002
	world.set_unit(npc.uid, npc)
	var corpse := GameUnit.new()
	corpse.uid = 77
	corpse.dead = true
	world.looted[corpse.uid] = corpse
	check(vm._ser(hero) == {"u":hero.uid,"h":[0,0]}, "deployed hero saves its stable roster identity")
	check(vm._deser({"u":npc.uid,"h":[0,0]}) == hero, "valid stable hero identity wins over a reused numeric id")
	check(vm._deser({"u":npc.uid,"h":[1,0]}) == null, "absent guest never resolves to an unrelated live actor")
	check(vm._deser({"u":corpse.uid,"h":[1,0]}) == null, "absent guest never resolves to a looted corpse")
	check(vm._deser({"u":hero.uid,"h":[0,4]}) == null, "missing roster member never resolves to another hero")
	check(vm._deser({"u":npc.uid,"h":"invalid"}) == null, "invalid stable key cannot enable a numeric fallback")
	check(vm._deser({"u":npc.uid}) == npc, "original nonhero numeric references still resolve")
	check(vm._deser({"u":corpse.uid}) == corpse, "looted nonhero identities remain available to death predicates")
	check(vm._deser({"u":-999}) == null, "removed numeric reference stays absent")
	var restored: Array = vm._deser([{ "u":npc.uid,"h":[1,0]},[{"u":npc.uid},{"u":hero.uid,"h":[0,0]}]])
	check(restored[0] == null and restored[1][0] == npc and restored[1][1] == hero,
		"nested saved groups preserve actor identity and absent entries")
	var object := Node3D.new()
	world.objects[42] = object
	check(vm._deser({"o":42}) == object, "nonunit object references remain unchanged")
	object.free()
	world.units = {}
	world.looted.clear()
	world.objects.clear()
	hero.free()
	npc.free()
	corpse.free()
	vm = null
	world.free()
	session.free()
	print("SCRIPT_HERO_REFERENCES %d checks %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
