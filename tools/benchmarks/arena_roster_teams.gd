extends Node
## Paired three-unit teams test ranged/caster recruits behind a shared front.
## Every candidate faces its shop-tier peers with native spells and alliances.
class Duel extends ArenaRun:
	var opposing: Array[Dictionary] = []
	func enemy_army() -> Array[Dictionary]: return opposing
	func enemy_formation() -> Array[Dictionary]: return ArenaTournamentRun.formation_for(opposing, 1)
	func resolve(_winner: int, _seconds: float, _damage: Array, _survivors: Array = [0,0]) -> void: stage = "result"

const FRONTS := [[0,2], [12,14], [15,25], [26,27], [28,29]]
var rows := []

func army(run: ArenaRun, family: int, rank: int, front: Array) -> void:
	run.army.clear()
	for index in 2:
		var unit := run._recruit(front[index], rank, 1)
		unit.deployed = true; unit.point = [27.0, 29.5 + index * 5.0]
	var recruit := run._recruit(family, rank, 1)
	recruit.deployed = true; recruit.point = [23.0, 32.0]

func _ready() -> void:
	var native := hash(GameData.db.tables)
	var rank := 0
	var first := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rank="): rank = int(arg.get_slice("=", 1))
		elif arg.begins_with("--from="): first = int(arg.get_slice("=",1))
	for candidate in range(first, ArenaRules.FAMILIES.size()):
		var tier := int(ArenaRules.FAMILIES[candidate].tier)
		var row := {"family":candidate, "name":ArenaRules.FAMILIES[candidate].name, "rank":rank, "opponents":[]}
		for baseline in ArenaRules.FAMILIES.size():
			if baseline == candidate or int(ArenaRules.FAMILIES[baseline].tier) != tier: continue
			var wins := 0; var draws := 0; var seconds := 0.0
			for side in 2:
				var run := Duel.new(); run.auto_save = false; run.begin(8519 + baseline)
				var rival := ArenaRun.new(); rival.auto_save = false; rival.begin(8519 + baseline)
				army(run, candidate if side == 0 else baseline, rank, FRONTS[tier-1])
				army(rival, baseline if side == 0 else candidate, rank, FRONTS[tier-1])
				run.opposing = rival.army
				var battle := ArenaPveMatch.new(); battle.rendered = false; battle.drives_clock = false; battle.run = run
				add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent = self
				battle.prepare(); battle.start()
				for tick in 2200:
					if battle.phase != ArenaMatch.Phase.FIGHT: break
					battle.simulate_tick()
				if battle.winner == side: wins += 1
				if battle.winner < 0: draws += 1
				seconds += battle.world.time
				if battle.phase != ArenaMatch.Phase.FINISHED:
					printerr("FAIL unfinished team fight"); get_tree().quit(1); return
				battle.queue_free(); await get_tree().process_frame
			row.opponents.append({"family":baseline, "wins":wins, "draws":draws, "seconds":seconds/2})
		rows.append(row); print("ROSTER_TEAM ", JSON.stringify(row))
		FileAccess.open("user://roster-teams-%d.json" % rank, FileAccess.WRITE).store_string(JSON.stringify(rows, "\t"))
	get_tree().quit(0 if not rows.is_empty() and hash(GameData.db.tables) == native else 1)
