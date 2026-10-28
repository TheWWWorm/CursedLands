extends Node
## Feeblemind refuses spell casting, except on weapon type 16: the creatures
## whose only attacks are spells (bats, evil eyes, dragons). The original's
## code (553220) leaves those able to cast, so a feebleminded one
## still attacks. Real field zone, prototypes, AI and spell casting.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s := Session.new(); add_child(s); var g := Game.new(); g.session = s; s.game = g; add_child(g)
	s.state.ensure_hero(0, s._hero_proto(0))
	await s.enter_zone("gz1g", 1, false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false)
	var w := s.world
	var hero: GameUnit = s.party_units(0)[0]
	hero.max_hp = 100000.0; hero.hp = hero.max_hp; hero.aggressive = false
	var side := 1
	while side == hero.faction: side += 1
	w.set_relation(hero.faction, side, 2); w.set_relation(side, hero.faction, 2)
	var at := w.nav.nearest_walkable(hero.pos + Vector2(4, 0))
	# The first weapon-type-16 prototype whose AI has an attack spell.
	var caster: GameUnit = null
	var nid := 990600
	for row: Dictionary in GameData.db.table("monster_prototypes"):
		nid += 1
		var u := w.spawn_unit({"nid":nid, "prototype":String(row.name), "player":1, "position":Vector3(at.x, at.y, 0)})
		if u == null:
			continue
		if int(u.proto.get("weapon_type_id", -1)) == 16 and not (w.ai.options(u).a as Array).is_empty():
			caster = u
			break
		w.remove_unit(u)
	check(caster != null, "a spell-only creature (weapon type 16) with an attack spell")
	if caster == null:
		get_tree().quit(1); return
	print("FEEBLEMIND_PROTOTYPE ", caster.info.get("prototype"))
	caster.faction = side; caster.visible = true; caster.fogged = false
	var normal := w.spawn_unit({"nid":990699, "prototype":"Human Hero", "player":1, "position":Vector3(at.x, at.y + 3.0, 0)})
	normal.faction = side; normal.ai_next = INF; normal._perceive_next = INF
	Spells.apply(w, null, "feeblemind", normal, normal.pos)
	check(normal.buffs.has("feeblemind") and normal.cannot_cast(), "Feeblemind stops an ordinary unit casting")
	Spells.apply(w, null, "feeblemind", caster, caster.pos)
	check(caster.buffs.has("feeblemind"), "the spell-only creature is feebleminded")
	check(not caster.cannot_cast(), "but it can still cast")
	# Kept feebleminded, it still attacks the hero with its spells.
	var hp := hero.hp
	var n := 0
	while n < 600 and hero.hp >= hp:
		if n % 10 == 0: Spells.apply(w, null, "feeblemind", caster, caster.pos)
		w._tick(GameUnit.TICK); n += 1
		if n % 50 == 0: await get_tree().process_frame
	check(hero.hp < hp, "the feebleminded creature still hurts the hero (%d ticks)" % n)
	check(caster.buffs.has("feeblemind"), "while feebleminded")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("FEEBLEMIND_SPELL_CREATURES ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
