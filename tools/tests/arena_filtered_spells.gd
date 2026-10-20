extends Node
## Native NPC perception uses instance IDs, including filtered/multiple targets.
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _ready()->void:
	var match_state:=ArenaMatch.new();add_child(match_state);match_state.set_process(false);match_state.create_world(self)
	var eye:=match_state._spawn({"id":"evileyesimplem5","team":0,"point":Vector2(13,16)})
	var a:=match_state._spawn({"id":"boarredf1","team":1,"point":Vector2(16,15)})
	var b:=match_state._spawn({"id":"wolfgreyf1","team":1,"point":Vector2(16,18)})
	var friend:=match_state._spawn({"id":"boarredf1","team":0,"point":Vector2(14,18)})
	match_state.start();match_state.world.set_process(false);match_state.world.set_physics_process(false)
	var prior:=[a.hp,b.hp,friend.hp]
	Spells.cast_unit(match_state.world,eye,"arrow {e2;t2;fe}",a,a.pos)
	var timers:=match_state.world.get_node("SpellTimers") as Spells.WorldTimers
	for i in 30:
		match_state.world.time+=GameUnit.TICK;match_state.world._logic_step+=1;timers._tick(GameUnit.TICK,true)
	check(a.hp < prior[0], "filtered spell damages primary enemy")
	check(b.hp < prior[1], "filtered spell damages additional enemy")
	check(friend.hp == prior[2], "filtered spell preserves allied health")
	print("ARENA_FILTERED_SPELLS ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
