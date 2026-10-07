extends Node
## Run with the Lost in Astral installation. The Portal Terror uses the
## domination-school Curse Magic: native 683910 gives it electrical damage.
var checks := 0
var failures := 0
var w: GameWorld
var serial := 500000

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func guard() -> GameUnit:
	serial += 1
	var u := GameUnit.new()
	u.setup(w, {"prototype":"zone1 Human Fighter3 M", "nid":serial, "player":3})
	w.add_child(u)
	w.set_unit(u.uid, u)
	u._anim_lock = 20.0
	return u

func animate(u: GameUnit, frames: int) -> void:
	# Cross-fade weights settle over rendered frames, including after a
	# restart seek. A single oversized advance is not a rendered animation.
	for i in frames:
		u.model.player.advance(1.0 / 60.0)

func _ready() -> void:
	w = GameWorld.new()
	w.authority = false
	w.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(w)
	var caster := GameUnit.new()
	check(caster.setup(w, {"prototype":"zone1 JunEvil", "template":"unmocu", "nid":666666, "player":6}), "Terror loads")
	w.add_child(caster)
	w.set_unit(caster.uid, caster)
	var curse := String(caster.proto.spells[0])
	check(Spells.parse(curse).subtype == "domination", "knowledge school stays domination")
	check(Spells.is_hostile(curse), "curse is an offensive spell")
	var u := guard()
	check(u.hp > 0.0 and not u.dead, "guard starts alive")
	Spells.cast_unit(w, caster, curse, u, u.pos)
	check(u.dead and u.hp <= 0.0, "authored Terror attack kills the Portal guard")

	# Distinct armour values detect accidentally selecting general or fire
	# damage from the knowledge school. Actual body health is the observation.
	u = guard()
	u.max_hp = 4000.0
	u.restore_parts()
	u.stats.armor = PackedFloat32Array([1000,1000,1000,1000,1000,37,1000])
	u.buffs.protection = {"resist":"lightning", "armor":11.0}
	var before := u.hp
	Spells.cast_unit(w, caster, curse, u, u.pos)
	check(is_equal_approx(before-u.hp, 636.0), "curse uses electrical armour and protection")
	check(not u.dead, "strong guard survives partial damage")
	u.buffs.clear()
	u.stats.armor = PackedFloat32Array([1000,1000,1000,1000,1000,900,1000])
	before = u.hp
	Spells.cast_unit(w, caster, curse, u, u.pos)
	check(u.hp == before, "sufficient electrical armour blocks curse")

	# Rick's special projectile has the same database-school trap. Direct
	# effect creation without a source point is its arrival/hit path.
	u.stats.armor = PackedFloat32Array([1000,1000,1000,3,1000,1000,1000])
	u.buffs.protection = {"resist":"fire", "armor":2.0}
	before = u.hp
	var rick := Spells.parse("rick_magic")
	check(Spells.is_hostile("rick_magic"), "Rick's attack is offensive")
	Spells.apply(w, null, "rick_magic", u, u.pos)
	check(is_equal_approx(before-u.hp, maxf(float(rick.effect)-5.0, 0.0)), "Rick's projectile uses fire armour and protection")
	u.buffs.clear()
	u.stats.armor = PackedFloat32Array([1000,1000,1000,1000,1000,1,1000])
	before = u.hp
	Spells.apply(w, null, "lightning", u, u.pos)
	check(is_equal_approx(before-u.hp, maxf(float(Spells.parse("lightning").effect)-1.0, 0.0)), "ordinary lightning retains its damage")
	before = u.hp
	Spells.apply(w, null, "feeblemind", u, u.pos)
	check(u.hp == before and not Spells.is_hostile("eagle_sight"), "non-damage school spells stay non-damaging")

	# Exercise actual cast starts and wire snapshots. The client must replay
	# a second cast even when no intervening idle state reached the network.
	var replica := GameUnit.new()
	check(replica.setup(w, {"prototype":"zone1 JunEvil", "template":"unmocu", "nid":666667, "player":6}), "Terror replica loads")
	w.add_child(replica)
	caster.order = {"type":"cast", "spell":curse, "point":Vector2.ZERO}
	caster.facing = 0.0
	caster._do_cast(GameUnit.TICK)
	var first := caster.snapshot()
	check(first[4] == "cast", "first real cast starts")
	replica.apply_snapshot(first)
	var wing: EIAnimPart = replica.model.find_child("r_wingbone1", true, false)
	var start := wing.quaternion
	animate(replica, 33)
	check(wing.quaternion.angle_to(start) > 0.2, "replicated cast moves the wing")
	animate(replica, 180)
	check(not replica.model.player.is_playing(), "first cast reaches its end")
	var end := replica.model.player.current_animation_position
	replica.apply_snapshot(first)
	check(not replica.model.player.is_playing() and replica.model.player.current_animation_position == end, "duplicate packet does not restart cast")
	caster.order = {"type":"cast", "spell":curse, "point":Vector2.ZERO}
	caster._do_cast(GameUnit.TICK)
	var second := caster.snapshot()
	check(second[4] == first[4] and second[14] != first[14], "consecutive identical casts have different generations")
	replica.apply_snapshot(second)
	check(replica.model.player.is_playing() and replica.model.player.current_animation_position < 0.01, "second cast restarts on the client")
	start = wing.quaternion
	animate(replica, 33)
	check(wing.quaternion.angle_to(start) > 0.2, "second replicated cast also moves the wing")
	replica.apply_snapshot(second)
	check(is_equal_approx(replica.model.player.current_animation_position, 0.55), "duplicate active snapshot preserves clip time")
	var legacy := second.slice(0, 14)
	replica.apply_snapshot(legacy)
	check(is_equal_approx(replica.model.player.current_animation_position, 0.55), "legacy save snapshot stays readable")
	w.queue_free()
	await get_tree().process_frame
	print("CREATURE_DAMAGE checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
