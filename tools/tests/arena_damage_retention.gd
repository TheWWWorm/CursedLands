extends Node
const Fixture := preload("arena_fixture.gd")
var checks := 0
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ", message)

func _ready() -> void:
	var run := ArenaRun.new(); run.auto_save = false
	Fixture.begin(run, 7191, 1)
	var battle := ArenaPveMatch.new(); battle.run = run; battle.rendered = false
	add_child(battle); battle.set_process(false); battle.set_physics_process(false)
	battle._world_parent = self; battle.prepare()
	var roster := battle.round_army.duplicate(true)
	var uid := int(roster[0].uid)
	check(battle.previous_damage.is_empty(), "first preparation has no previous battle")
	check(battle.start(), "native encounter starts")
	battle.world.set_process(false); battle.world.set_physics_process(false)
	var source: GameUnit = battle.world.unit_rows().filter(func(u):return int(u.get_meta("arena_placement",{}).get("run_uid",-1)) == uid)[0]
	var enemy: GameUnit = battle.world.unit_rows().filter(func(u):return int(u.get_meta("arena_placement",{}).get("team",-1)) == 1)[0]
	battle._combat_event("damage", source, enemy, 125.0)
	check(battle.damage_report(run.army).damage.get(uid) == 125.0, "live report follows actual combat attribution")
	battle.phase = ArenaMatch.Phase.FINISHED; battle._resolved(0)
	run.advance()
	run.army[0].deployed = false
	run._recruit(6, 0, 1)
	battle.prepare()
	var report := battle.damage_report(run.army).duplicate(true)
	check(report.army == roster and report.damage.get(uid) == 125.0, "next preparation retains the finished roster and damage")
	battle.prepare()
	check(battle.damage_report(run.army) == report, "rearranging or shopping cannot erase the previous battle")
	# The full board frame is also used by the local worker. A newly viewing
	# client must recover a report even if it missed the final combat frame.
	var authority := ArenaOnlineGame.new(); authority.home = battle
	var full := authority.board_frame(0, true)
	check(full.previous_damage == report, "full preparation snapshot carries the previous report")
	var replica := ArenaOnlineMatch.new(); replica.run = ArenaRun.new(); replica.run.auto_save = false; replica.rendered = false
	add_child(replica); replica._world_parent = self; replica.set_process(false); replica.set_physics_process(false)
	replica.apply_board(bytes_to_var(var_to_bytes(full)))
	check(replica.damage_report([]) == report, "replica recovers the report with numeric unit identities")
	full.serial += 1; full.previous_damage = {}
	replica.apply_board(full)
	check(replica.damage_report([]) == report, "fresh worker staging keeps the report until combat begins")
	full.serial += 1; full.phase = ArenaMatch.Phase.FIGHT
	replica.apply_board(full)
	check(replica.previous_damage.is_empty() and replica.damage_report([]).damage.is_empty(), "first combat frame clears the replica's previous report")
	check(battle.start(), "next native encounter starts")
	check(battle.previous_damage.is_empty() and battle.friendly_damage.is_empty(), "next combat resets the authority's report")
	battle.phase = ArenaMatch.Phase.FINISHED; battle._remember_damage()
	run.begin(7191); battle._round_key = ""; battle.prepare()
	check(battle.previous_damage.is_empty(), "new game with the same seed clears the old report")
	authority.free(); replica.queue_free(); battle.queue_free()
	await get_tree().process_frame; await get_tree().process_frame
	print("ARENA_DAMAGE_RETENTION ",checks," checks; failures=",JSON.stringify(failures))
	TexUpscale.shutdown(); get_tree().quit(0 if failures.is_empty() else 1)
