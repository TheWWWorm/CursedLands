extends Node
## Trials-only tuning: actual combat cadence, persistent wall damage, actor
## cache separation, repeated alliance application and old roster saves.
class Duel extends ArenaRun:
	var opposing: Array[Dictionary] = []
	func enemy_army() -> Array[Dictionary]: return opposing
	func enemy_formation() -> Array[Dictionary]: return ArenaTournamentRun.formation_for(opposing, 1)
	func resolve(_winner: int, _seconds: float, _damage: Array, _survivors: Array = [0,0]) -> void: stage = "result"

var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL ", message)

func encounter(family: int, rank: int) -> ArenaPveMatch:
	var run := Duel.new(); run.auto_save = false; run.begin(8415); run.army.clear()
	run._recruit(family, rank, 1); run.army[0].deployed = true; run.army[0].point = [29.0, 32.0]
	var enemy := ArenaRun.new(); enemy.auto_save = false; enemy.begin(8415); enemy.army.clear()
	enemy._recruit(7, 1, 1); enemy.army[0].deployed = true; enemy.army[0].point = [29.0, 32.0]
	run.opposing = enemy.army
	var arena := ArenaPveMatch.new(); arena.run = run; arena.rendered = false; arena.drives_clock = false
	add_child(arena); arena.set_process(false); arena.set_physics_process(false); arena._world_parent = arena
	arena.prepare()
	return arena

func _ready() -> void:
	var native := hash(GameData.db.tables)
	for rank in 3:
		var arena := encounter(15, rank)
		var banshee: GameUnit = arena.world.unit_rows()[0]
		var troll: GameUnit = arena.world.unit_rows()[1]
		var raw := GameData.db.find("monster_prototypes", banshee.info.prototype)
		check(banshee.max_hp == ArenaUnitInfo.values(banshee.info.prototype, null, 15, rank).max_hp, "banshee preview matches battle health")
		check(banshee.max_hp > float(raw.hp) if rank < 2 else banshee.max_hp == float(raw.hp), "only early banshees gain health")
		var health := banshee.max_hp
		ArenaAlliances.apply(arena.world, arena.run.army, arena.run.enemy_army())
		check(banshee.max_hp == health, "alliance reapplication does not compound tuning")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(arena.run.snapshot()))
		var restored := ArenaRun.new(); restored.auto_save = false
		check(restored.restore(saved) and restored.army == saved.army, "existing banshee roster survives save round trip")
		var starts: Array[float] = []
		arena.world.combat_event.connect(func(kind, a, _b, _amount):
			if kind == "attack" and a == banshee: starts.append(arena.world.time))
		banshee.stats.to_hit = 10000
		troll.stats.dmg_min = 0; troll.stats.dmg_max = 0
		arena.start()
		for tick in 600:
			if starts.size() >= 4 or arena.phase != ArenaMatch.Phase.FIGHT: break
			arena.simulate_tick()
		check(starts.size() >= 3, "banshee performs repeated real strikes")
		if starts.size() >= 3:
			var interval := starts[2] - starts[1]
			print("BALANCE_CADENCE rank=", rank, " interval=", interval)
			check(interval < 3.15 if rank < 2 else interval > 4.4, "early cadence improved, dark banshee cadence unchanged")
		arena.queue_free(); await get_tree().process_frame
	for rank in 3:
		var arena := encounter(22, rank)
		var harpy: GameUnit = arena.world.unit_rows()[0]
		var troll: GameUnit = arena.world.unit_rows()[1]
		var native_proto := GameData.db.find("monster_prototypes", harpy.info.prototype)
		var original := Spells.parse(native_proto.spells[0])
		var upgraded := Spells.parse(harpy.proto.spells[0])
		check(upgraded.effect > original.effect if rank > 0 else upgraded.effect == original.effect, "only upgraded harpies gain spell power")
		check(upgraded.duration == original.duration and upgraded.radius == original.radius, "wall geometry and duration preserved")
		var spell_list := Array(harpy.proto.get("spells", []))
		ArenaAlliances.apply(arena.world, arena.run.army, arena.run.enemy_army())
		check(Array(harpy.proto.spells) == spell_list, "spell upgrades do not accumulate")
		var campaign := arena.world.spawn_unit({"prototype": harpy.info.prototype, "player": 1, "position": Vector3(20, 20, 0)})
		var tuned_options := arena.world.ai.options(harpy)
		var campaign_options := arena.world.ai.options(campaign)
		check(tuned_options.a.any(func(o): return o.slot == spell_list[0]), "AI uses upgraded wall")
		check(campaign_options.a.any(func(o): return o.slot == native_proto.spells[0].strip_edges().to_lower()), "native and Trials spell caches remain separate")
		arena.world.remove_unit(campaign)
		arena.start(); harpy._anim_lock = 1000; troll._anim_lock = 1000
		var position := troll.pos
		Spells.apply(arena.world, harpy, spell_list[0], troll, troll.pos)
		# Advance the same world timers and regeneration as normal combat.
		for tick in 154: arena.simulate_tick()
		var lost := troll.max_hp - troll.hp
		print("BALANCE_WALL rank=", rank, " effect=", upgraded.effect, " troll_net_damage=", lost)
		check(lost > 60.0 if rank == 2 else lost >= 0.0, "final wall deals sustained damage through troll regeneration")
		check(troll.pos == position and harpy.hp == harpy.max_hp, "wall fixture measures one cast against a stationary regenerating troll")
		check(ArenaRules.evolution_copies(22, 0) * ArenaRules.evolution_copies(22, 1) == 6, "harpy final evolution still costs six recruits")
		ArenaAlliances.apply(arena.world, [])
		check(Array(harpy.proto.spells) == Array(native_proto.spells), "removing Trials bonuses restores native spells")
		arena.queue_free(); await get_tree().process_frame
	check(hash(GameData.db.tables) == native, "campaign database is unchanged")
	print("ARENA_REPORT_BALANCE checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
