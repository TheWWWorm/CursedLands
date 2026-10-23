extends Node
const Duel = preload("../benchmarks/arena_roster_matchups.gd").Duel
var checks := 0
var failures: Array[String] = []
var battle: ArenaPveMatch
var own: Array[GameUnit] = []
var enemies: Array[GameUnit] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func setup(families: Array, foes: Array, items: Array = [], enemy_items: Array = [], rank_value := 0) -> void:
	if is_instance_valid(battle):
		battle.world.free(); battle.free()
	var run := Duel.new(); run.auto_save = false; run.begin(15877)
	var other := ArenaRun.new(); other.auto_save = false; other.begin(15877)
	for team in 2:
		var company: ArenaRun = run if team == 0 else other
		var kinds: Array = items if team == 0 else enemy_items
		var index := 0
		for family: int in (families if team == 0 else foes):
			var entry := company._recruit(family, rank_value, 1)
			entry.deployed = true; entry.point = [27.0, 24.0 + index * 3.0]
			if kinds.size() > index and not String(kinds[index]).is_empty():
				company.items.append({"uid": index + 1, "kind": kinds[index], "unit_uid": entry.uid})
				company.next_item_uid = index + 2
			index += 1
		company._sync_items()
	run.opposing.assign(other.army.duplicate(true))
	battle = ArenaPveMatch.new(); battle.run = run; battle.rendered = false; battle.drives_clock = false
	add_child(battle); battle.set_process(false); battle.set_physics_process(false); battle._world_parent = self
	battle.prepare(); battle.start()
	own.assign(battle.world.unit_rows().filter(func(u): return u.faction == 1))
	enemies.assign(battle.world.unit_rows().filter(func(u): return u.faction == 2))
	for team in [own, enemies]:
		for i in team.size(): team[i].pos = Vector2(31 + (0 if team == own else 1), 29 + i * 1.2)

func hit(a: GameUnit, b: GameUnit, power := 8.0, landed := true) -> void:
	battle.world.combat.melee(a, b, {"hit": landed, "backstab": false, "aim": 1,
		"dmg": power, "types": PackedFloat32Array([0,0,1,0,0,0,0]), "bs_mul": 1.0})

func _ready() -> void:
	var original := hash(GameData.db.tables)
	setup([0], [0], ["fang"])
	own[0].hp = own[0].max_hp * 0.4
	var before := own[0].hp
	hit(own[0], enemies[0], 8.0, false)
	check(is_equal_approx(own[0].hp, before), "miss cannot steal life")
	hit(own[0], enemies[0])
	check(own[0].hp > before and own[0].hp - before <= own[0].max_hp * 0.0201, "native landed hit steals bounded life")
	setup([0], [0,0], ["storm"])
	before = enemies[1].hp
	hit(own[0], enemies[0]); hit(own[0], enemies[0])
	check(is_equal_approx(enemies[1].hp, before), "storm waits for third successful hit")
	hit(own[0], enemies[0])
	check(enemies[1].hp < before and battle.world.arena_effects.rows[own[0].uid].hits == 3, "third hit chains without counting its own lightning")
	setup([0], [0], ["venom"])
	hit(own[0], enemies[0]); enemies[0].hp = enemies[0].max_hp * 0.5; before = enemies[0].hp
	enemies[0].heal(4.0)
	check(is_equal_approx(enemies[0].hp - before, 2.0), "venom halves real healing")
	battle.world.time += 5.1; before = enemies[0].hp; enemies[0].heal(4.0)
	check(is_equal_approx(enemies[0].hp - before, 4.0), "venom expires on simulation time")
	setup([0], [0], ["ward"])
	own[0].hp = own[0].max_hp * 0.36; before = own[0].hp
	hit(enemies[0], own[0], 8.0)
	check(battle.world.arena_effects.rows[own[0].uid].used and is_equal_approx(own[0].hp, before), "ward absorbs the threshold-crossing hit")
	battle.world.time += 5.1; hit(enemies[0], own[0], 8.0)
	check(own[0].hp < before and battle.world.arena_effects.totals.ward == 1, "ward expires and cannot refresh")
	setup([0,0], [0], ["guardian", ""])
	own[1].hp = own[1].max_hp * 0.36; before = own[1].hp
	hit(enemies[0], own[1], 8.0)
	check(is_equal_approx(own[1].hp, before) and battle.world.arena_effects.rows[own[0].uid].used, "guardian protects another nearby carrier")
	setup([0,0], [0], ["guardian", "ward"])
	own[1].hp = own[1].max_hp * 0.36; hit(enemies[0], own[1], 8.0)
	check(not battle.world.arena_effects.rows[own[0].uid].used and battle.world.arena_effects.rows[own[1].uid].used, "a sufficient Ward preserves the nearby Guardian for a later danger")
	setup([0], [0], ["thorn"], ["thorn"])
	hit(own[0], enemies[0], 8.0)
	check(battle.world.arena_effects.totals.get("thorn",0) == 1, "two thorn shells cannot recurse")
	hit(own[0], enemies[0], 8.0)
	check(battle.world.arena_effects.totals.get("thorn",0) == 1, "thorn cooldown blocks simultaneous retaliations")
	setup([3], [24], ["echo"], [], 1)
	for i in 3:
		Spells.cast_after(battle.world, own[0], "arrow{t2}", enemies[0], enemies[0].pos, 0.0)
		var timers := battle.world.get_node("SpellTimers") as Spells.WorldTimers
		timers._tick(0.055, false)
	check(battle.world.arena_effects.rows[own[0].uid].casts == 3 and battle.world.arena_effects.totals.get("echo",0) == 1, "three multi-target spell dispatches produce exactly one echo")
	setup([3], [0], ["berserker"])
	check(own[0].cannot_cast() and own[0].actions() > float(own[0].stats.actions), "berserker trades native casting for faster actions")
	battle.world.arena_effects.stop()
	check(not own[0].cannot_cast() and is_equal_approx(own[0].actions(), own[0].stats.actions), "battle stop removes berserker effects")
	setup([0,1], [24])
	hit(own[0], enemies[0]); hit(own[0], enemies[0])
	check(battle.world.arena_effects.totals.get("pack",0) == 0, "one Beast cannot trigger a pack alone")
	hit(own[1], enemies[0])
	check(battle.world.arena_effects.totals.get("pack",0) == 1, "different Beast families combine native landed attacks")
	setup([4,28], [0])
	own[0].die(enemies[0])
	check(battle.world.arena_effects.totals.get("rally",0) == 1, "Horde death causes reachable retaliation")
	setup([0,6], [0])
	var guard := own[1]
	hit(enemies[0], own[0], 20.0)
	check(battle.world.arena_effects.totals.get("guard",0) == 1 and battle.world.arena_effects.rows[guard.uid].guard < guard.max_hp * 0.12, "Warrior spends finite pool guarding an ally")
	setup([1,4], [3])
	Spells.cast_after(battle.world, enemies[0], "arrow{}", own[0], own[0].pos, 0.0)
	(battle.world.get_node("SpellTimers") as Spells.WorldTimers)._tick(0.055, false)
	check(battle.world.arena_effects.target_bonus(own[1], enemies[0], {"range": 10.0}) > 0.0, "Hunters respond to a native completed spell")
	enemies[0].pos = own[1].pos + Vector2(float(own[1].stats.reach) * 0.8, 0)
	var weapon: Dictionary = battle.world.ai.options(own[1]).a.filter(func(o):return int(o.type)==0)[0]
	check(battle.world.arena_effects.target_bonus(own[1], enemies[0], weapon) > 0.0, "ranged Hunter uses native weapon reach when its AI option range is zero")
	enemies[0].pos += Vector2(20, 0)
	check(battle.world.arena_effects.target_bonus(own[1], enemies[0], {"range": 10.0}) == 0.0, "Hunter mark does not grant out-of-range attacks")
	setup([3,5], [24], [], [], 1)
	for caster: GameUnit in own:
		Spells.cast_after(battle.world, caster, "arrow{}", enemies[0], enemies[0].pos, 0.0)
		(battle.world.get_node("SpellTimers") as Spells.WorldTimers)._tick(0.055, false)
	check(battle.world.arena_effects.totals.get("reaction",0) == 1, "two real Mage casts produce one bounded reaction")
	setup([0,6], [3])
	before = own[0].hp
	own[0].take_damage(10, enemies[0], -1, PackedFloat32Array(), 0, Callable(), false, {"kind":"spell"})
	check(absf(before - own[0].hp - 10.0) < 0.001, "two Warriors cannot guard spell damage")
	own[1].pos += Vector2(10,0); before = own[0].hp
	own[0].take_damage(10, enemies[0], -1, PackedFloat32Array(), 0, Callable(), false, {"kind":"attack"})
	check(absf(before - own[0].hp - 10.0) < 0.001, "guard has a real proximity limit")
	setup([0,6,12,14], [3])
	before = own[0].hp
	own[0].take_damage(10, enemies[0], -1, PackedFloat32Array(), 0, Callable(), false, {"kind":"spell"})
	check(absf(before - own[0].hp - 6.0) < 0.001, "four Warriors block spell damage once, without stacking guards")
	setup([4,10,14,15], [24])
	for i in 3: own[i].die(enemies[0])
	check(battle.world.arena_effects.rallies[0].size() == 2, "deep Horde stops after two distinct family casualties")
	setup([0,1,2,3,5,7], [24,24])
	hit(own[0], enemies[0]); hit(own[1], enemies[0])
	check(battle.world.arena_effects.totals.get("pack",0) == 2, "six Beasts strike one additional nearby enemy")
	enemies[0].hp = 1.0; hit(own[0], enemies[0])
	check(battle.world.arena_effects.target_bonus(own[0], enemies[1], {"range":10.0}) > 0.0, "deep pack pursues a nearby survivor after a kill")
	setup([0,1,2,3], [24,24])
	hit(own[0], enemies[0]); battle.world.time += 2.1; enemies[0].die(own[0])
	check(battle.world.arena_effects.target_bonus(own[0], enemies[1], {"type":1,"range":10.0}) == 0.0, "an expired prey mark cannot start a new pursuit")
	setup([1,4,7,10,0], [3])
	enemies[0].pos = own[4].pos + Vector2(1,0)
	Spells.cast_after(battle.world, enemies[0], "prot_fire{}", enemies[0], enemies[0].pos, 0.0)
	(battle.world.get_node("SpellTimers") as Spells.WorldTimers)._tick(0.055, false)
	check(battle.world.arena_effects.target_bonus(own[4], enemies[0], {"range":10.0}) > 0.0, "deep Hunters direct other allies even after an enemy support cast")
	setup([3,5,13,19], [24,24], [], [], 1)
	for i in 2:
		Spells.cast_after(battle.world, own[i], "arrow{}", enemies[0], enemies[0].pos, 0.0)
		(battle.world.get_node("SpellTimers") as Spells.WorldTimers)._tick(0.055, false)
	check(battle.world.arena_effects.totals.get("reaction",0) == 2, "deep Mage reaction hits just one additional nearby enemy")
	setup([0], [0], ["ward"])
	own[0].hp = own[0].max_hp * 0.36
	var head: UnitBodyPart = own[0].parts[0]
	var scale := head.lethal * own[0].max_hp / head.max
	var incoming := own[0].max_hp * 0.10 / scale
	before = own[0].hp
	own[0].take_damage(incoming, enemies[0], 0, PackedFloat32Array(), 0, Callable(), false, {"kind":"attack"})
	check(absf(before - own[0].hp) < 0.001 and absf(float(battle.world.arena_effects.shields[own[0].uid].amount) - own[0].max_hp * 0.15) < 0.001,
		"a head impact spends shield strength in whole HP rather than raw part damage")
	setup([6,11,12,19], [24])
	own[1].hp *= 0.5; own[2].hp *= 0.5; before = own[1].hp
	own[0].die(enemies[0])
	var fx := battle.world.arena_effects
	check(own[1].hp > before and fx.echoes.size() == 1, "deep Spirits heal nearby wounded allies and create one echo")
	var echo: GameUnit = battle.world.units.get(fx.echoes.keys()[0])
	check(not fx.rows.has(echo.uid) and echo.get_meta("arena_placement").echo, "temporary echo has no item or alliance membership")
	check(not echo.is_processing() and not echo.model.is_processing(), "headless echo follows the recruit simulation clock")
	own[2].die(enemies[0]); check(fx.echoes.size() == 1, "further Spirit deaths cannot multiply echoes")
	battle.world.time += 6.1; fx.tick(); check(echo.dead, "temporary echo expires on simulation time")
	# Reproducibility through actual simulation, including all native AI and projectiles.
	var signatures := []
	for repeat in 2:
		setup([3,5,6,11,19,21], [3,5,6,11,19,21], ["fang","echo","storm","thorn","guardian","ward"], ["fang","echo","storm","thorn","guardian","ward"])
		for tick in 1700:
			if battle.phase != ArenaMatch.Phase.FIGHT: break
			battle.simulate_tick()
		signatures.append([battle.winner, battle.world.time, battle.damage.duplicate(), battle.world.arena_effects.totals.duplicate()])
	check(signatures[0] == signatures[1], "matched native battles reproduce with items, alliances and summons")
	check(hash(GameData.db.tables) == original, "all effects preserve campaign prototype data")
	print("ARENA_COMBAT_EFFECTS checks=",checks," failures=",JSON.stringify(failures)," battle=",JSON.stringify(signatures[0]))
	get_tree().quit(0 if failures.is_empty() else 1)
