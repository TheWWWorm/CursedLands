extends Node
## A blow cannot reach a high flyer. The original (554b30)
## refuses an attack on a living flyer whose altitude is 1.5 or more with
## ack 0xc unless a bow or crossbow is in hand; 54d960 ends
## such an order and the AI's reach test (54c800) leaves the target out.
## Real field zone, hero, prototypes and orders.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func given(u: GameUnit) -> Dictionary:
	return u.order if not u.order.is_empty() else u.orders.front() if not u.orders.is_empty() else {}

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("gz1g", 1, false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	var w := s.world
	var hero: GameUnit = s.party_units(0)[0]
	var side := 1
	while side == hero.faction: side += 1
	w.set_relation(hero.faction, side, 2); w.set_relation(side, hero.faction, 2)
	var at := w.nav.nearest_walkable(hero.pos + Vector2(5, 0))
	# A high flyer (altitude 1.5 or more) and a low one, from the prototypes.
	var high: GameUnit = null
	var low: GameUnit = null
	var nid := 990700
	for row: Dictionary in GameData.db.table("monster_prototypes"):
		if high and low: break
		nid += 1
		var u := w.spawn_unit({"nid":nid, "prototype":String(row.name), "player":1, "position":Vector3(at.x, at.y, 0)})
		if u == null: continue
		var alt := float(u.proto.get("altitude", 0.0))
		if u.move_class() == 0 and alt >= 1.5 and high == null: high = u
		elif u.move_class() == 0 and alt > 0.0 and alt < 1.5 and low == null: low = u
		else: w.remove_unit(u)
	check(high != null and low != null, "a high and a low flyer")
	if high == null or low == null:
		get_tree().quit(1); return
	print("HIGH_FLYER ", high.info.get("prototype"), " ", high.proto.get("altitude"), " LOW_FLYER ", low.info.get("prototype"), " ", low.proto.get("altitude"))
	for u in [high, low]:
		u.faction = side; u.ai_next = INF; u._perceive_next = INF
	var h: Dictionary = hero.get_meta("hero")
	var keep_weapons: Array = h.get("weapons", []).duplicate()
	h.weapons = []
	check(not (GameSound.held_weapon_type(hero) in [5, 6]), "the hero holds no bow")
	var from := hero.pos
	hero.attack(high)
	check(given(hero).is_empty(), "an attack on the high flyer is refused")
	for i in 40: w._tick(GameUnit.TICK)
	check(hero.pos.distance_to(from) < 0.1, "and the hero does not walk to it")
	hero.attack(low)
	check(given(hero).get("target") == low, "a low flyer can be attacked")
	hero.orders.clear(); hero.order = {}
	# An attack already running ends once the target counts as high.
	hero.order = {"type": "attack", "target": high, "aim": -1}
	w._tick(GameUnit.TICK)
	check(hero.order.is_empty(), "a running attack on a high flyer ends")
	# With a bow in hand the attack is allowed.
	var bow := ""
	for row: Dictionary in GameData.db.table("weapons"):
		if int(row.get("type_id", -1)) == 5:
			bow = String(row.name); break
	h.weapons = [bow]
	check(GameSound.held_weapon_type(hero) == 5, "the hero holds a bow (%s)" % bow)
	hero.attack(high)
	check(given(hero).get("target") == high, "a bowman may attack the high flyer")
	hero.orders.clear(); hero.order = {}
	h.weapons = keep_weapons
	# The AI's reach test leaves a high flyer out of a melee choice.
	var goblin := w.spawn_unit({"nid":990799, "prototype":"GoblinTutor", "player":1, "position":Vector3(at.x, at.y + 2.0, 0)})
	check(not w.ai._reachable(goblin, high), "a melee creature cannot reach the high flyer")
	check(w.ai._reachable(goblin, low) or goblin.pos.distance_to(low.pos) > 50.0, "but it can reach the low one")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("HIGH_FLYER_REFUSAL ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
