extends Node
## Underlords' published tier/star table, exercised through real resolution.
var checks := 0
var failures := 0
class CaptureRun extends ArenaRun:
	var survivors := []
	func resolve(_winner: int, _seconds: float, _damage: Array, remaining: Array = [0,0]) -> void:
		survivors = remaining.duplicate()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	var expected := [[1,2,2],[1,2,3],[2,2,3],[2,3,3],[2,3,4]]
	var battle := ArenaPveMatch.new(); battle.rendered = false; battle.drives_clock = false
	add_child(battle); battle.set_process(false); battle.set_physics_process(false)
	var recorder := CaptureRun.new(); recorder.auto_save = false; battle.run = recorder
	var world := GameWorld.new(); add_child(world)
	world.set_process(false); world.set_physics_process(false); battle.world = world
	var unit := world.spawn_unit({"prototype":"boarredf1", "position":Vector3(5,5,0)})
	unit.set_process(false); unit.set_physics_process(false)
	for tier in range(1,6):
		var family := -1
		for i in ArenaRules.FAMILIES.size():
			if ArenaRules.FAMILIES[i].tier == tier: family = i; break
		for rank in 3:
			unit.set_meta("arena_placement", {"team":1,"family":family,"rank":rank})
			battle._resolved(1)
			check(recorder.survivors == [0,expected[tier-1][rank]], "tier %d rank %d survivor bounty" % [tier,rank+1])
	unit.set_meta("arena_placement", {"team":1,"family":0,"rank":2,"echo":true})
	battle._resolved(1); check(recorder.survivors == [0,0], "summoned echo has no player damage")
	unit.remove_meta("arena_placement")
	battle._resolved(1); check(recorder.survivors == [0,0], "unplaced summon has no player damage")
	unit.set_meta("arena_placement", {"team":1,"family":0,"rank":2}); unit.dead = true
	battle._resolved(1); check(recorder.survivors == [0,0], "dead recruit has no player damage")
	var league := ArenaTournamentRun.new(); league.auto_save = false
	for row in [[4,0],[9,0],[11,1],[19,1],[21,2],[29,2],[31,3],[41,4],[99,9]]:
		league.wave = row[0]
		check(league.defeat_damage(7) == 7 + row[1], "round %d uses decade damage without sudden death" % row[0])
	for wave in [1,2,3,5,10,15,30]:
		league.wave = wave
		check(league.defeat_damage(7) == 0, "neutral round %d does not deal player damage" % wave)
	for live in [false,true]:
		league.begin(7191); league.wave = 11; league._choose_pairings(); league.stage = "fight"; league.live_boards = live
		if live: league.record_board(0,1,[0,7])
		else: league.record_duel(league.human_pair(),1,[0,7])
		check(league.lives == 92, "board/duel applies the same eight damage")
		if live: league.record_board(0,1,[0,7])
		else: league.record_duel(league.human_pair(),1,[0,7])
		check(league.lives == 92, "repeated result cannot charge twice")
		league.rollback_round_health(); check(league.lives == 100, "interrupted combat restores pre-round health")
	battle.world = null; world.free(); battle.free()
	print("ARENA_ROUND_DAMAGE ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
