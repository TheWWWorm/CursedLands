extends Node
## Being hit does not delay a fighter's next blow. The original's
## reaction check (549d00) refuses a hit reaction to a unit standing in an
## attack whose next strike comes before the reaction would end; otherwise
## the reaction plays as before. Real field zone, hero and damage.
class HitSession extends Session:
	var numbers: Array[Dictionary] = []
	func broadcast(event: Dictionary) -> void:
		if event.get("t") == "hitnum": numbers.append(event.duplicate())
		super.broadcast(event)

var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

## Reactions out of `n` blows taken with the next strike `cd` seconds away.
func reactions(hero: GameUnit, t: GameUnit, cd: float, n: int) -> int:
	var count := 0
	for i in n:
		hero._anim_lock = 0.0; hero.action = "idle"; hero._attack_cd = cd
		hero.take_damage(0.01, t)
		if hero.action == "hit": count += 1
	hero._anim_lock = 0.0; hero.action = "idle"
	return count

func reaction_seed(wanted: bool) -> void:
	# The non-weapon, null-source damage below reaches the campaign randf
	# without choosing a weapon impact sound.
	for sample in range(128):
		seed(sample)
		if (randf() < 0.5) == wanted:
			seed(sample)
			return
	assert(false, "expected a seed on each side of the reaction roll")


func ordered_move_reactions(hero: GameUnit, w: GameWorld) -> void:
	hero.order = {}
	hero.orders.clear()
	hero.path = PackedVector2Array()
	hero._anim_lock = 0.0
	hero._set_action("idle")
	hero.aggressive = false
	hero.ai_next = INF
	hero._perceive_next = INF
	var goal := w.nav.nearest_walkable(hero.pos + Vector2(-8.0, 0.0))

	# Standing still installs a lock that holds an ordinary move submitted
	# immediately after impact. Releasing all hit locks would fail this.
	reaction_seed(true)
	hero.take_damage(0.01, null)
	var standing := hero.pos
	hero.move_to(goal, true)
	w._tick(GameUnit.TICK)
	check(hero.action == "hit" and hero._anim_lock > 0.0 and hero.pos == standing,
		"an admitted standing reaction still holds a queued move")
	var warmup := 0
	while warmup < 60 and not (hero._moving and hero.order.get("type", "") == "move"):
		w._tick(GameUnit.TICK)
		warmup += 1
	check(hero._moving and hero.order.get("type", "") == "move" and hero.pos.distance_to(goal) > 2.0,
		"stock human has an active move with room for the reaction window")
	if not hero._moving or hero.order.get("type", "") != "move" or hero.pos.distance_to(goal) <= 2.0:
		return

	# On the same active path the complementary random roll has no hit clip
	# and still advances the order through the next simulation tick.
	reaction_seed(false)
	hero.take_damage(0.01, null)
	var before := hero.pos
	var missed := hero.action != "hit"
	w._tick(GameUnit.TICK)
	check(missed and hero.pos != before and hero.order.get("to") == goal,
		"a rejected moving reaction leaves the same move advancing")

	var motion_clip := hero.model._current
	reaction_seed(true)
	hero.take_damage(0.01, null)
	var hit_clip := hero.model._current
	check(hero.action == "hit" and not hit_clip.is_empty() and hit_clip != motion_clip,
		"an admitted moving hit starts the authored reaction clip")
	var advances: Array[float] = []
	var reaction_held := true
	for tick in 3:
		before = hero.pos
		w._tick(GameUnit.TICK)
		advances.append(hero.pos.distance_to(before))
		reaction_held = reaction_held and hero.model._current == hit_clip
	check(advances.all(func(distance): return distance > 0.0001) and hero.order.get("to") == goal,
		"the impact tick and next two reaction ticks advance the same move (%s)" % str(advances))
	check(reaction_held, "movement leaves the hit clip on the figure through those ticks")
	before = hero.pos
	hero.move_to(standing, false)
	w._tick(GameUnit.TICK)
	check(hero.pos == before and hero._anim_lock > 0.0 and hero.order.is_empty()
		and hero.orders.size() == 1 and hero.orders[0].get("to") == standing,
		"a replacement order waits for the hit reaction instead of inheriting its movement")




func absorbed_weapon_aftermath(hero: GameUnit, attacker: GameUnit, s: HitSession) -> void:
	var w := hero.world
	var gear: Dictionary = hero.get_meta("hero")
	var source_gear := {"weapons":["cheat dagger.bronze"], "armors":[]}
	attacker.set_meta("hero", source_gear)
	var healing := "uniquegipathadagan plate.steel|healing{it}"
	var protection := "uniquegipathadagan helm.iron|prot_fire{it}"
	var heal_cost := float(Spells.parse(Items.spell_of(healing)).mana)
	var pre_cost := float(Spells.parse(Items.spell_of(protection)).mana)
	check(heal_cost > 0.0 and Items.charge(healing) >= heal_cost
		and pre_cost > 0.0 and Items.charge(protection) >= pre_cost,
		"stock Healing and on-struck fire protection fit the armour charges")
	if heal_cost <= 0.0 or Items.charge(healing) < heal_cost or pre_cost <= 0.0 or Items.charge(protection) < pre_cost:
		return
	GameData.options["armor_formula"] = 0
	check(Combat.armor_minimum(hero, 6.0) == 0.0, "original armour formula allows total absorption")
	hero.order = {}
	hero.orders.clear()
	hero.path = PackedVector2Array()
	hero._anim_lock = 0.0
	hero._set_action("idle")
	hero.parts[1].cur = hero.parts[1].max * 0.75
	var prior_hp := hero.hp
	var types := PackedFloat32Array([0, 0, 0, 0, 0, 1, 0])
	var shot := {"hit":true, "backstab":false, "dmg":6.0, "aim":1, "types":types}
	gear.armors = [healing, protection]
	hero.stats.armor = PackedFloat32Array([0, 0, 0, 0, 0, 1000, 0])
	s.numbers.clear()
	reaction_seed(true)
	w.combat.melee(attacker, hero, shot)
	check(hero.hp == prior_hp and Items.spent(gear.armors[0]) == 0.0,
		"fully absorbed weapon leaves the prior wound and Healing charge intact")
	check(hero.action != "hit" and hero._anim_lock <= 0.0,
		"fully absorbed weapon cannot flinch even with the admitting roll")
	check(s.numbers.size() == 1 and s.numbers[0].n == 0 and s.numbers[0].f == 4,
		"fully absorbed weapon still sends one zero with its electrical flash")
	check(Items.spent(gear.armors[1]) == pre_cost and hero.buffs.has("prot_fire"),
		"the same struck contact still spends its pre-hit protection charge")
	check(Items.wear(source_gear.weapons[0]) > 0.0,
		"the attacker's weapon still wears on total absorption")
	check(hero.get_meta("attacker", [null])[0] == attacker,
		"the defender still notices the attacker")

	hero._anim_lock = 0.0
	hero._set_action("idle")
	gear.armors = [healing, protection]
	hero.buffs.erase("prot_fire")
	hero.stats.armor = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	var damaging := shot.duplicate()
	damaging.aim = 4  # The charged chest plate does not cover the legs.
	s.numbers.clear()
	reaction_seed(true)
	w.combat.melee(attacker, hero, damaging)
	check(w.combat.last_types[5] > 0.0 and Items.spent(gear.armors[0]) == heal_cost and hero.action == "hit",
		"a damaging landed weapon spends Healing and still flinches")
	check(s.numbers.size() == 1 and s.numbers[0].f == 4,
		"damaging electrical weapon still reports its contact once")

	hero._anim_lock = 0.0
	hero._set_action("idle")
	gear.armors = [healing, protection]
	hero.buffs.erase("prot_fire")
	var wear_before := Items.wear(source_gear.weapons[0])
	s.numbers.clear()
	w.combat.melee(attacker, hero, {"hit":false, "backstab":false})
	check(s.numbers.is_empty() and Items.spent(gear.armors[0]) == 0.0
		and Items.spent(gear.armors[1]) == 0.0 and Items.wear(source_gear.weapons[0]) == wear_before,
		"accuracy miss has no indicator, armour proc, or weapon wear")

	gear.armors = [healing, protection]
	hero.stats.armor = PackedFloat32Array([0, 0, 0, 0, 0, 1000, 0])
	var lightning := Spells.parse("lightning").duplicate()
	lightning.effect = 6.0
	lightning.duration = 1
	prior_hp = hero.hp
	s.numbers.clear()
	reaction_seed(true)
	Spells._spell_damage(w, attacker, lightning, hero)
	check(s.numbers.size() == 1 and s.numbers[0].n == 0 and s.numbers[0].f == 4
		and hero.hp == prior_hp and hero._anim_lock <= 0.0 and Items.spent(gear.armors[0]) == 0.0,
		"fully absorbed Lightning keeps its existing zero, flash, and quiet reaction")




func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s := HitSession.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("gz1g", 1, false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	var w := s.world
	var hero: GameUnit = s.party_units(0)[0]
	hero.max_hp = 100000.0; hero.hp = hero.max_hp
	for bp: UnitBodyPart in hero.parts:
		bp.max = 100000.0; bp.cur = bp.max
	var p := w.nav.nearest_walkable(hero.pos + Vector2(1.5, 0))
	var t := w.spawn_unit({"nid":991001, "prototype":"Human Hero", "player":1, "position":Vector3(p.x, p.y, 0)})
	var side := 1
	while side == hero.faction: side += 1
	t.faction = side; t.ai_next = INF; t._perceive_next = INF
	w.set_relation(hero.faction, side, 2); w.set_relation(side, hero.faction, 2)
	for bp: UnitBodyPart in t.parts:
		bp.max = 100000.0; bp.cur = bp.max
	hero.attack(t)
	var n := 0
	while n < 400 and (hero.order.get("type", "") != "attack" or hero._moving or hero._pending_hit.is_empty()):
		w._tick(GameUnit.TICK); n += 1
	while not hero._pending_hit.is_empty():
		w._tick(GameUnit.TICK)
	check(hero.order.get("type", "") == "attack" and not hero._moving, "the hero stands fighting (%d ticks)" % n)
	check(reactions(hero, t, 0.1, 40) == 0, "a blow taken just before its next strike plays no reaction")
	check(reactions(hero, t, 2.0, 40) > 0, "with its next strike far off it still reacts")
	var keep := hero.order
	hero.order = {}
	check(reactions(hero, t, 0.0, 40) > 0, "a unit not attacking reacts to blows")
	hero.order = keep
	ordered_move_reactions(hero, w)
	absorbed_weapon_aftermath(hero, t, s)
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("HIT_REACTION_TEMPO ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
