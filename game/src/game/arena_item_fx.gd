class_name ArenaItemFx
extends RefCounted
## Presentation only: reuse the original healing, protection, poison and spell
## emitters. Combat events carry their source so bolts also work on replicas.
## No particle/random state can feed back into the combat simulation.

static func play(fx: ParticleFx, event: Dictionary) -> void:
	var unit: GameUnit = fx.world.units.get(int(event.get("uid", 0)))
	if not is_instance_valid(unit): return
	var key := String(event.get("effect", ""))
	var source: GameUnit = fx.world.units.get(int(event.get("source", 0)))
	match key:
		"fang", "spirit":
			if float(event.get("amount", 0.0)) > 0.0:
				_burst(fx, unit, "heal", 0x2006, 0.4, 2.4)
		"ward", "guardian":
			var previous: ParticleFx.Effect = unit.get_meta("arena_shield_fx") if unit.has_meta("arena_shield_fx") else null
			if previous: fx.delete(previous)
			var shield := fx.spawn(0x2016, Vector3.ZERO, 0.7, unit, {"secs":float(event.get("secs", 5.0)), "prewarm":8})
			unit.set_meta("arena_shield_fx", shield)
		"shield_end":
			var shield: ParticleFx.Effect = unit.get_meta("arena_shield_fx") if unit.has_meta("arena_shield_fx") else null
			if shield: fx.delete(shield)
			unit.remove_meta("arena_shield_fx")
			if bool(event.get("broken", false)):
				_burst(fx, unit, "shield_hit", 0x2028, 0.6, 0.4)
		"storm":
			if is_instance_valid(source):
				fx.add_bolt(fx.cast_point(source), fx.unit_point(unit, 0), 2.5, 0.3, source, unit)
		"echo":
			_burst(fx, unit, "echo", 0x202d, 0.7, 0.7)
			if is_instance_valid(source):
				var origin := fx.cast_point(source)
				fx.spawn(0x2014, origin, 0.35, null, {"v130":fx.unit_point(unit, 0) - origin, "secs":0.35})
		"venom": _burst(fx, unit, "venom", 0x2013, 0.45, 1.2)
		"thorn": _burst(fx, unit, "thorn", 0x2033, 0.45, 0.6)
		"berserker": _burst(fx, unit, "berserker", 0x204b, 0.65, 1.6)
		"marked": _burst(fx, unit, "marked", 0x2044, 0.4, 1.2)
		"spirit_echo": fx.spawn(0x2019, fx.unit_point(unit, 0), 0.55, null, {"secs":1.2})

static func _burst(fx: ParticleFx, unit: GameUnit, key: String, type: int, strength: float, seconds: float) -> void:
	var metadata := "arena_fx_" + key
	var previous: ParticleFx.Effect = unit.get_meta(metadata) if unit.has_meta(metadata) else null
	# Rapid attacks refresh gameplay, but cannot pile up identical emitters.
	if previous and not previous.deleted and previous.until > fx.tick: return
	unit.set_meta(metadata, fx.spawn(type, Vector3.ZERO, strength, unit, {"secs":seconds}))

static func sync_shields(world: GameWorld, state: Array) -> void:
	if not world.presentation: return
	var alive := {}
	for row: Dictionary in state:
		if float(row.get("secs", 0.0)) <= 0.0: continue
		alive[int(row.uid)] = true
		play(ParticleFx.of(world), {"uid":row.uid, "effect":"ward", "secs":row.secs})
	for unit: GameUnit in world.unit_rows():
		if unit.has_meta("arena_shield_fx") and not alive.has(unit.uid):
			play(ParticleFx.of(world), {"uid":unit.uid, "effect":"shield_end"})
