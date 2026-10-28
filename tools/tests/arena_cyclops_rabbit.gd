extends "arena_combat_effects.gd"
## Trials feedback: a cyclops' long native throw must land, and every exploding
## hare must sense, reach and visibly blast large or promoted enemies.
const CYCLOPS := 27
const TROLL := 14
const WOLF := 1

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="): GameData.campaign_roots[CampaignProfile.ASTRAL] = arg.trim_prefix("--astral-path=")
	check(ArenaExpansion.mount(), "Astral creatures mounted")
	if not ArenaExpansion.mounted(): get_tree().quit(1); return
	var native := hash(GameData.db.tables)
	cyclops_native_timing()
	cyclops_hits_do_not_cancel()
	for stopped in [false, true]: cyclops_lost_victim(stopped)
	for rank_value in 3:
		for foe in [CYCLOPS, TROLL]: hare_large_body(foe, rank_value)
	for rank_value in 3: hares_in_battle(rank_value)
	blast_survives_battle_end()
	check(hash(GameData.db.tables) == native, "Trials fixes leave original campaign records intact")
	print("ARENA_CYCLOPS_RABBIT ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _wind_up(c: GameUnit, limit := 400) -> bool:
	for i in limit:
		if not c._pending_hit.is_empty(): return true
		if battle.phase != ArenaMatch.Phase.FIGHT or c.dead: return false
		battle.simulate_tick()
	return not c._pending_hit.is_empty()

func _thrown_at(c: GameUnit) -> Array:
	var targets := []
	for node in battle.world.get_children():
		if node is Projectile and node.source == c and not node.is_queued_for_deletion(): targets.append(node.target)
	return targets

## Original data: CyclopsA16 strikes every 130 native ticks; uattack01 releases
## at frame 65 of 105 and uattack02 at frame 17 of 26 (unmocy.adb).
func cyclops_native_timing() -> void:
	setup([CYCLOPS], [WOLF])
	var c := own[0]
	check(float(c.proto.tuning_actions) == 130.0, "cyclops keeps its native 130-tick strike delay")
	check(c._clip_hit_ticks("uattack01") == 65.0 and c._clip_hit_ticks("uattack02") == 17.0, "native throw release frames are used")

func cyclops_hits_do_not_cancel() -> void:
	setup([CYCLOPS], [WOLF, WOLF])
	var c := own[0]
	c.pos = Vector2(28, 30); enemies[0].pos = Vector2(33, 30); enemies[1].pos = Vector2(33, 32)
	check(_wind_up(c), "cyclops begins a throw")
	var lock := c._anim_lock; var left := float(c._pending_hit.t)
	for i in 6: hit(enemies[0], c, 2.0)
	check(c.action == "attack" and c._anim_lock == lock and float(c._pending_hit.t) == left, "hits do not interrupt a committed swing")

func cyclops_lost_victim(stopped: bool) -> void:
	setup([CYCLOPS], [WOLF, WOLF])
	var c := own[0]
	c.pos = Vector2(28, 30); enemies[0].pos = Vector2(33, 30); enemies[1].pos = Vector2(33, 31.5)
	if not _wind_up(c): check(false, "cyclops begins a throw before its victim falls"); return
	var victim: GameUnit = c._pending_hit.target
	var other: GameUnit = enemies[1] if victim == enemies[0] else enemies[0]
	if stopped: battle.world.arena_effects.active = false
	victim.die(null)
	var thrown := []
	for i in 120:
		battle.simulate_tick()
		thrown.append_array(_thrown_at(c))
		if c._pending_hit.is_empty(): break
	if stopped:
		check(thrown.is_empty(), "without Trials effects a lost victim still discards the blow (campaign rule)")
	else:
		check(other in thrown, "a throw whose victim fell mid wind-up reaches another enemy in range")

func hare_large_body(foe: int, rank_value: int) -> void:
	setup([32], [foe], [], [], rank_value)
	var rabbit := own[0]; var big := enemies[0]
	var label := " vs %s star %d" % [ArenaRules.FAMILIES[foe].name, rank_value + 1]
	rabbit.pos = big.pos + Vector2(rabbit.melee_reach(big) - 0.05, 0.0)
	var fx := battle.world.arena_effects
	var hp := big.hp
	fx.tick()
	check(fx.rows[rabbit.uid].has("fuse"), "hare in melee contact arms its fuse" + label)
	battle.world.time += ArenaExpansion.POPPER_FUSE + 0.01; fx.tick()
	check(rabbit.dead and fx.rows[rabbit.uid].get("exploded", false), "armed hare detonates" + label)
	check(big.hp < hp, "blast reaches the large body" + label)

func hares_in_battle(rank_value: int) -> void:
	setup([32, 32, 32], [TROLL, TROLL], [], [], rank_value)
	for i in own.size(): own[i].pos = Vector2(26, 28 + i * 1.5)
	for i in enemies.size(): enemies[i].pos = Vector2(34, 28 + i * 2.0)
	var blasts := {}; var hits := {}
	battle.visual_event.connect(func(e):
		if String(e.get("t", "")) == "arena_proc" and String(e.get("effect", "")) == "popper_blast":
			blasts[int(e.uid)] = int(blasts.get(int(e.uid), 0)) + 1)
	battle.world.combat_event.connect(func(kind, a, b, amount):
		if kind == "damage" and is_instance_valid(a) and a.dead and amount > 0.0: hits[a.uid] = true)
	var rabbits := own.duplicate()
	for tick in 1800:
		if battle.phase != ArenaMatch.Phase.FIGHT: break
		battle.simulate_tick()
	var label := " at star %d" % (rank_value + 1)
	var foes_left := enemies.filter(func(e): return not e.dead).size()
	for r: GameUnit in rabbits:
		if not r.dead:
			check(foes_left == 0, "a hare survives only when no troll remains" + label)
			continue
		check(int(blasts.get(r.uid, 0)) == 1, "every fallen hare shows exactly one blast" + label)
		check(hits.has(r.uid), "every fallen hare damages a nearby troll" + label)

## A blast on the battle's final tick keeps its explosion particles.
func blast_survives_battle_end() -> void:
	setup([32], [WOLF])
	var counts := []
	for finish in [false, true]:
		var fx := ParticleFx.new(); fx.world = battle.world; battle.world.add_child(fx)
		var blast := fx.spawn(0x2002, Vector3(30, 30, 0), 2.5)
		var flame := fx.spawn(0x2003, Vector3(32, 30, 0), 1.0)
		check(blast != null and flame != null, "blast and flame emitters exist")
		if blast == null or flame == null: return
		if finish: fx.finish_emitters()
		var most := 0
		for i in 12:
			fx._tick(false)
			most = maxi(most, blast.e.live())
		counts.append(most)
		if finish: check(flame.e.flags & FxEmitter.F_EMIT == 0, "finished battles still stop continuous emitters")
		check(not blast.deleted, "explosion is still drawn after the battle ends")
		fx.free()
	check(counts[0] > 0 and counts[1] >= counts[0] * 0.8, "battle end does not erase a final explosion " + str(counts))
