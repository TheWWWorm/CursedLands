class_name SpellSounds
extends RefCounted
## Spell and magic-effect sounds (every peer, from the "spellfx" and
## "magicfx" events).
##
## Spells, the original (the spell object's start, = cast
## origin, = target point), (missile hits) and
## (lasting spells ending): one-shots through sound objects (class 0x48,
## ) and loops through class 99 (: a start wav, then a
## looped list, stopped when the spell drops it). All priority 1000,
## min 10 / max 50 unless noted.
##
## Magic effects on units,: "<folder>\start.wav"
## at the unit when the effect is added, "<folder>\end.wav" when it ends
## (10 / 50, priority 0); FeebleMind also loops "circle.wav" on the unit
## Stench sounds "Stench\1..3" every 16 ticks
##  warns with "magic\end1.wav" (8 / 20) at a named unit while one
## of its effects has under 30 ticks left, again each time it finishes.

const TICK := 0.055
const PRIO := 1000
const MIN_D := 10.0
const MAX_D := 50.0
## Magic effect types (cases) by the remake's spell code.
const EFFECT_DIRS := {"prot_fire": "Fireshield", "prot_electro": "Lightsheild", "prot_acid": "PoisonShield",
	"eagle_sight": "Eaglesight", "infravision": "Infravision", "detect_life": "Detectlife",
	"invisibility": "Invisibility", "silence": "Silence", "lichdom": "Lichdom", "stun": "Stun",
	"antimagic": "Antimagic", "strength": "Strengthen", "weak": "Weaken", "regeneration": "Regeneration",
	"feeblemind": "FeebleMind", "speed": "Speed", "slow": "Slow", "enlarge": "Enlarge", "shrink": "Shrink"}

var mixer: SoundMixer
var world: GameWorld
## Timed actions: {at (seconds of _clock), f: Callable}.
var _later: Array = []
## Moving loops: {h, pos, target (GameUnit|null), point, step, ticks, kind, acc, end}.
var _movers: Array = []
## Effects on units: "uid:code" -> {u, code, until, loop, next_stench, warn}.
var _effects := {}
var _clock := 0.0


func _init(m: SoundMixer, w: GameWorld) -> void:
	mixer = m
	world = w


func _after(secs: float, f: Callable) -> void:
	_later.append({"at": _clock + maxf(secs, 0.0), "f": f})


func _ground(x: float, y: float) -> Vector3:
	return Vector3(x, y, world.ground_at(x, y))


func _unit(id) -> GameUnit:
	var u: GameUnit = world.units.get(int(id)) if id != null else null
	return u if u and is_instance_valid(u) else null


static func _at(u: GameUnit) -> Vector3:
	return Vector3(u.pos.x, u.pos.y, u.global_position.y)


func _one(path: String, p: Vector3, min_d := MIN_D, max_d := MAX_D) -> void:
	mixer.play3d(path, PRIO, p, min_d, max_d)


## Event "spellfx": a, tu, x, y, fx / fy (a cast without a caster), spell,
## replay (a lasting spell replayed for a joiner: only its loop).
func spell(ev: Dictionary) -> void:
	var sp := Spells.parse(String(ev.get("spell", ev.get("code", ""))))
	var code := String(sp.code)
	var caster := _unit(ev.get("a"))
	var target := _unit(ev.get("tu"))
	var point := _ground(float(ev.get("x", 0.0)), float(ev.get("y", 0.0)))
	var origin := point
	if caster:
		origin = _at(caster)
	elif ev.has("fx"):
		origin = _ground(float(ev.fx), float(ev.fy))
	var replay: bool = ev.get("replay", false)
	var dur := float(sp.duration) * TICK
	if replay:
		dur = float(ev.get("left", dur))
	match code:
		"arrow", "acid_ray", "rick_magic":
			# rick_magic (0x28) shares Firearrow's case.
			var dir := "Acidray" if code == "acid_ray" else "Firearrow"
			if replay:
				return
			_one("magic\\%s\\start.wav" % dir, origin)
			var h := mixer.play3d("magic\\%s\\circle.wav" % dir, PRIO, origin, MIN_D, MAX_D, true)
			_movers.append({"h": h, "pos": origin + Vector3(0, 0, 1), "target": target, "point": point + Vector3(0, 0, 1),
				"kind": "missile", "end": "magic\\%s\\end.wav" % dir, "ticks": 0, "acc": 0.0})
		"lightning", "curse_magic":   # curse_magic (0x29) shares lightning's case
			if not replay:
				_one("magic\\lightning\\start.wav", origin)
		"fireball":
			if replay:
				return
			# The ball flies level toward the point at range × 0.0667 m per
			# tick for n = round(d / range × 15) − 2 ticks.
			var rng := maxf(float(sp.range), 1.0)
			var d := Vector2(point.x - origin.x, point.y - origin.y)
			var n := maxi(1, roundi(d.length() / rng * 15.0) - 2)
			var speed := rng * 0.0667
			_one("magic\\Fireball\\start.wav", origin)
			if d.length() >= 1.25 * speed:
				var h := mixer.play3d("magic\\Fireball\\circle.wav", PRIO, origin, MIN_D, MAX_D, true)
				var step := d / float(n)
				_movers.append({"h": h, "pos": origin, "step": Vector3(step.x, step.y, 0.0), "ticks": n,
					"kind": "line", "acc": 0.0})
			_after(n * TICK, func(): _one("magic\\fireball\\end.wav", point))
		"inv_lit":
			if not replay:   # heard everywhere: min / max 1000
				_one("magic\\InvokeLight\\start.wav", point, 1000.0, 1000.0)
		"acid_column":
			if not replay:
				_one("magic\\Acidcolumn\\start.wav", point)
		"firewall", "litnwall", "acid_fog":
			var dir: String = {"firewall": "Firewall", "litnwall": "Lightwall", "acid_fog": "poison"}[code]
			if not replay and code != "litnwall":
				_one("magic\\%s\\start.wav" % dir, point)
			var h := mixer.play3d("magic\\%s\\circle.wav" % dir, PRIO, point, MIN_D, MAX_D, true)
			_after(dur, func():
				mixer.stop(h)
				if code != "litnwall":
					_one("magic\\%s\\end.wav" % dir, point))
		"fireworks":
			# A list of five loops (order not traced: played in turn).
			var st := {"i": 0, "h": -1, "until": _clock + dur, "p": point}
			_fireworks(st)
			_after(dur, func(): _one("magic\\Firework\\end.wav", point))
		"clairvoyence":
			if not replay:
				_one("magic\\Clairvoyence\\start.wav", point)
			_after(dur - 10.0 * TICK, func(): _one("magic\\Clairvoyence\\end.wav", point))
		"possession", "vision_fog":
			if not replay and target:
				_one("magic\\%s\\start.wav" % ("Possession" if code == "possession" else "VisionFog"), _at(target))
		"healing":
			if not replay:
				_one("magic\\Healing\\start.wav", _at(target) if target else point)
		"link":
			if caster and not replay:
				_one("magic\\Link\\start.wav", origin)
			var hl := mixer.play3d("magic\\Link\\circle.wav", PRIO, origin, MIN_D, MAX_D, true)
			_after(maxf(dur, 10.0 * TICK), func():
				mixer.stop(hl)
				_one("magic\\Link\\end.wav", origin))
		"teleport":
			if not replay:
				_one("magic\\Teleport\\start.wav", point)
		"charm":
			if not replay and target:
				_one("magic\\Charm\\start.wav", _at(target))


func _fireworks(st: Dictionary) -> void:
	if _clock >= float(st.until):
		return
	st.i = int(st.i) % 5 + 1
	st.h = mixer.play3d("magic\\Firework\\%d.wav" % int(st.i), PRIO, st.p, MIN_D, MAX_D)
	var s := EIAudio.sfx("magic\\Firework\\%d.wav" % int(st.i))
	_after(s.get_length() if s else 1.0, func(): _fireworks(st))


## Event "magicfx": uid, code, secs.
func effect(ev: Dictionary) -> void:
	var u := _unit(ev.get("uid"))
	var code := String(ev.get("code", ""))
	if u == null:
		return
	var key := "%d:%s" % [u.uid, code]
	var old: Dictionary = _effects.get(key, {})
	if not old.is_empty():
		mixer.stop(int(old.get("loop", -1)))
	var e := {"u": u, "code": code, "until": _clock + float(ev.get("secs", 0.0)), "loop": -1,
		"stench": _clock, "warn": -1}
	if code == "stench":
		_effects[key] = e
		return
	if not EFFECT_DIRS.has(code):
		return
	var dir: String = EFFECT_DIRS[code]
	if not ev.get("replay", false):   # a joiner's replay: already running, no start
		mixer.play3d("magic\\%s\\start.wav" % dir, 0, _at(u), MIN_D, MAX_D)
	if code == "feeblemind":
		e.loop = mixer.play3d("magic\\FeebleMind\\circle.wav", 0, _at(u), MIN_D, MAX_D, true)
	_effects[key] = e


func tick(dt: float) -> void:
	_clock += dt
	if not _later.is_empty():
		var due := _later.filter(func(l): return float(l.at) <= _clock)
		if not due.is_empty():
			_later = _later.filter(func(l): return float(l.at) > _clock)
			for l: Dictionary in due:
				(l.f as Callable).call()
	for m: Dictionary in _movers.duplicate():
		m.acc = float(m.acc) + dt
		while float(m.acc) >= TICK and _movers.has(m):
			m.acc = float(m.acc) - TICK
			_move(m)
	for key in _effects.keys():
		var e: Dictionary = _effects[key]
		if not is_instance_valid(e.u):   # (checked before the typed assignment: freed units)
			mixer.stop(int(e.loop))
			_effects.erase(key)
			continue
		var u: GameUnit = e.u
		if u.dead:
			mixer.stop(int(e.loop))
			_effects.erase(key)
			continue
		var p := _at(u)
		if int(e.loop) >= 0:
			mixer.move(int(e.loop), p)
		if _clock >= float(e.until):
			mixer.stop(int(e.loop))
			if EFFECT_DIRS.has(e.code):
				mixer.play3d("magic\\%s\\end.wav" % EFFECT_DIRS[e.code], 0, p, MIN_D, MAX_D)
			_effects.erase(key)
			continue
		if e.code == "stench" and _clock >= float(e.stench):
			e.stench = float(e.stench) + 16.0 * TICK
			mixer.play3d("magic\\Stench\\%d.wav" % (randi() % 3 + 1), 0, p, MIN_D, MAX_D)
		# The end warning at a party unit (approx. for "named units").
		if float(e.until) - _clock < 30.0 * TICK and u.controller >= 0 and not mixer.playing(int(e.warn)):
			e.warn = mixer.play3d("magic\\end1.wav", 0, p, 8.0, 20.0)


func _move(m: Dictionary) -> void:
	var pos: Vector3 = m.pos
	if m.kind == "line":
		pos += m.step as Vector3
		m.ticks = int(m.ticks) - 1
		m.pos = pos
		mixer.move(int(m.h), pos)
		if int(m.ticks) <= 0:
			mixer.stop(int(m.h))
			_movers.erase(m)
		return
	# A homing spell missile: 0.6667 m per tick (CEffectArrow).
	var t: GameUnit = m.target if is_instance_valid(m.target) else null
	var dest: Vector3 = m.point
	if t:
		dest = _at(t) + Vector3(0, 0, 0.5)
	var d := dest - pos
	m.ticks = int(m.ticks) + 1
	var arrived: bool = Vector2(d.x, d.y).length() < 0.6667 or int(m.ticks) > 400
	pos = dest if arrived else pos + d.normalized() * 0.6667
	m.pos = pos
	mixer.move(int(m.h), pos)
	if arrived:
		mixer.stop(int(m.h))
		_movers.erase(m)
		mixer.play3d(String(m.end), PRIO, pos, MIN_D, MAX_D)   # at the hit unit
