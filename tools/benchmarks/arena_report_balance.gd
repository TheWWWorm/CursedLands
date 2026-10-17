extends Node
## Reproduce issue #15 with the shipped combat simulation and paired sides.
class Duel extends ArenaRun:
	var opposing: Array[Dictionary] = []
	func enemy_army() -> Array[Dictionary]: return opposing
	func enemy_formation() -> Array[Dictionary]: return ArenaTournamentRun.formation_for(opposing, 1)
	func resolve(_winner: int, _seconds: float, _damage: Array, _survivors: Array = [0,0]) -> void: stage = "result"

var rows: Array = []
func _ready() -> void:
	var native := hash(GameData.db.tables)
	var samples := 4
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="): samples = int(arg.get_slice("=", 1))
	for family in [12, 15, 22, 7]:
		for rank in 3:
			var id := ArenaRules.prototype(family, rank)
			var proto := GameData.db.find("monster_prototypes", id)
			var race := GameData.db.find("race_models", proto.base_race)
			var spells := []
			for spell in proto.spells:
				if not String(spell).is_empty(): spells.append(Spells.parse(spell))
			print("REPORT_STATS ", JSON.stringify({"family": family, "rank": rank, "id": id, "values": ArenaUnitInfo.values(id, null, family, rank), "actions": proto.get("tuning_actions"), "race": race, "spells": spells}))
	for pair in [[12,15], [15,0], [12,0], [15,14], [12,14], [22,7], [22,6], [8,7], [11,7]]:
		for rank in 3:
			var row := {"pair": pair, "rank": rank, "samples": samples * 2, "wins": 0, "draws": 0, "damage": [0.0, 0.0], "seconds": 0.0, "bouts": []}
			for number in samples:
				for side in 2:
					var run := Duel.new(); run.auto_save = false; run.begin(8415 + number)
					var rival := ArenaRun.new(); rival.auto_save = false; rival.begin(run.run_seed)
					run.army.clear(); rival.army.clear()
					run._recruit(pair[side], rank, 1); rival._recruit(pair[1-side], rank, 1)
					for company in [run, rival]:
						company.army[0].deployed = true; company.army[0].point = [27.0, 32.0]
					run.opposing = rival.army
					var battle := ArenaPveMatch.new(); battle.rendered = false; battle.drives_clock = false; battle.run = run
					add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent = battle
					battle.prepare(); battle.start()
					var actors := battle.world.unit_rows()
					var attacks := {}; var last_serial := {}; var casts := {}; var hits := {}
					battle.world.combat_event.connect(func(kind, a, _b, amount):
						if kind == "attack" and is_instance_valid(a):
							if not attacks.has(a.uid): attacks[a.uid] = []
							attacks[a.uid].append(snappedf(battle.world.time, .01))
						if kind == "damage" and is_instance_valid(a):
							if not hits.has(a.uid): hits[a.uid] = []
							hits[a.uid].append([snappedf(battle.world.time, .01), snappedf(amount, .01)]))
					for tick in 2500:
						if battle.phase != ArenaMatch.Phase.FIGHT: break
						battle.simulate_tick()
						for unit in actors:
							if unit._action_serial == last_serial.get(unit.uid, -1): continue
							last_serial[unit.uid] = unit._action_serial
							if not unit.action.begins_with("cast"): continue
							var events: Dictionary = casts
							if not events.has(unit.uid): events[unit.uid] = []
							events[unit.uid].append(snappedf(battle.world.time, .01))
					if battle.winner == side: row.wins += 1
					if battle.winner < 0: row.draws += 1
					row.damage[0] += battle.damage[side]; row.damage[1] += battle.damage[1-side]; row.seconds += battle.world.time
					var detail := {"side": side, "seed": run.run_seed, "winner": battle.winner, "seconds": battle.world.time, "units": []}
					for unit in actors:
						detail.units.append({"id":unit.info.prototype,"hp":unit.hp,"max_hp":unit.max_hp,"attacks": attacks.get(unit.uid, []),"casts":casts.get(unit.uid, []),"hits":hits.get(unit.uid, [])})
					row.bouts.append(detail)
					if battle.phase != ArenaMatch.Phase.FINISHED: printerr("FAIL unfinished duel"); get_tree().quit(1); return
					battle.queue_free(); await get_tree().process_frame
			rows.append(row)
			var compact := row.duplicate(); compact.erase("bouts"); print("REPORT_MATCHUP ", JSON.stringify(compact))
			var file := FileAccess.open("user://report-balance.json", FileAccess.WRITE); file.store_string(JSON.stringify(rows, "\t")); file.close()
	get_tree().quit(0 if hash(GameData.db.tables) == native else 1)
