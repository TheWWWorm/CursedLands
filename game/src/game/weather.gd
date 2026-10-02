class_name Weather
extends RefCounted
## Zone weather, the original. The zone record's weather (map.txt "#weather"
## "none" 0, "snow" 2, "tornado" 3, anything else and the
## default 1 = rain) goes to the world (on zone load).
##
## Host (server, run every 64 world ticks when (tick & 0x3f) == 3
## only in a game zone, world mode 1): rain / snow starts
## when a random number % 101 == 0 and stops when % 31 == 0, at most every
## 10 runs (countdown); the change goes to every client with its
## fade time (: 20 for rain, 40 for snow). While it rains each run
## (at least 20 ticks apart) strikes a lightning.
##
## Client (precipitation object "RainSnow"):
## rain loops "nature\rain\circle.wav" (2D, priority 1000), faded in or out
## by (1 − cos(t·π)) / 2 over the fade time.

const TICK := 0.055
const RUN_MASK := 0x3f
const RUN_AT := 3

var mixer: SoundMixer
var world: GameWorld
## World weather type: 0 none, 1 rain, 2 snow, 3 tornado.
var type := 1
## Host: precipitation 0 / 1 rain / 2 snow, last strike tick.
var state := 0
var _last_strike := -1000
## a global, kept across zones as in the original.
static var _countdown := 0
## Client RainSnow: shown, target, start tick, fade.
var _shown := 0
var _target := 0
var _start := 0.0
var _fade := 0.0
var _handle := -1


func _init(m: SoundMixer, w: GameWorld) -> void:
	mixer = m
	world = w
	if w == null:
		return   # client side only (the main menu's rain, MenuScene): type stays rain
	match String(w.zone.get("weather", "")).to_lower():
		"none": type = 0
		"snow": type = 2
		"tornado": type = 3
		_: type = 1


func stop() -> void:
	mixer.stop(_handle)
	_handle = -1
	for id in _tornado:
		mixer.stop(int(_tornado[id].h))
	_tornado.clear()


## Host, every world tick (`tick` = GameSound's world tick counter).
func host_tick(tick: int) -> void:
	if (tick & RUN_MASK) != RUN_AT or String(world.zone.get("type", "")) != "game":
		return
	if type != 0 and type != 3:
		_countdown -= 1
		if _countdown < 1:
			if state == 0:
				if randi() % 0x65 == 0:
					_countdown = 10
					state = 1 if type == 1 else 2
					_send(20.0 if type == 1 else 40.0)
			elif randi() % 0x1f == 0:
				_countdown = 10
				state = 0
				_send(20.0 if type == 1 else 40.0)
	# (type 3: the tornado objects, CEffectTornado, are world gameplay:
	# Tornadoes, game/tornado.gd; their sound is on_tornado below.)
	if state == 1 and _last_strike + 0x14 < tick:
		_last_strike = tick
		_strike()


func _send(fade: float) -> void:
	if world.session:
		world.session.broadcast({"t": "weather", "w": state, "fade": fade})


## a point x, y in [2, 510) (random × 508
## 2³² + 2), the ground there − 5, a top 40 m above it within ±2 m; one time in
## four only thunder ("nature\thunder\1..4", 60 / 150, at the top), otherwise
## the WorldScript string: a point light (id 1, radius 80, white)
## the middle, "nature\lightning\1..3" (60 / 150) at the top and two bolts
## (ids 1, 2, param −7) one script tick apart.
## Remake: the strike light's own expiry (ParticleFx._flash_light), past the
## script's three Sleep(1) ticks.
const FLASH_TICKS := 6


func _strike() -> void:
	_strike_at(randf() * 508.0 + 2.0, randf() * 508.0 + 2.0)


func _strike_at(x: float, y: float) -> void:
	var z := world.ground_at(x, y) - 5.0
	var tx := x + randf() * 4.0 - 2.0
	var ty := y + randf() * 4.0 - 2.0
	var tz := z + 40.0
	if randi() & 3 == 0:
		_fx("CreateFX", [tx, ty, tz, 60.0, 150.0, "nature\\thunder\\%d.wav" % (randi() % 4 + 1)])
		return
	var mid := [(tx + x) * 0.5, (ty + y) * 0.5, (tz + z) * 0.5]
	_fx("CreatePointLight", [1, mid[0], mid[1], mid[2], 80.0, 255, 255, 255, FLASH_TICKS])
	_fx("CreateFX", [tx, ty, tz, 60.0, 150.0, "nature\\lightning\\%d.wav" % (randi() % 3 + 1)])
	_fx("CreateLightning", [1, tx, ty, tz, x, y, z, -7])
	var tree := world.get_tree() if world.is_inside_tree() else null
	if tree == null:
		return
	# Sleep(1) between the steps (the script's tick, ScriptVM.SLEEP_UNIT).
	await tree.create_timer(ScriptVM.SLEEP_UNIT).timeout
	_fx("DeleteLightning", [1])
	await tree.create_timer(ScriptVM.SLEEP_UNIT).timeout
	_fx("CreateLightning", [2, tx, ty, tz, x, y, z, -7])
	await tree.create_timer(ScriptVM.SLEEP_UNIT).timeout
	_fx("DeleteLightning", [2])
	_fx("DeletePointLight", [1])


func _fx(f: String, a: Array) -> void:
	if is_instance_valid(world) and world.session:
		world.session.broadcast({"t": "fxcmd", "f": f, "a": a})


## Client: event "weather" ((type, fade)), `now` in world ticks.
func on_event(e: Dictionary, now: float) -> void:
	var w := int(e.get("w", 0))
	if _handle >= 0 and w != 0:
		mixer.stop(_handle)
		_handle = -1
	if w == 1:
		_handle = mixer.play2d("nature\\rain\\circle.wav", 1000, 0, 0, true)
	_target = w
	if _shown == 0:
		_shown = w
	_start = now
	_fade = float(e.get("fade", 0.0))


## Client: a tornado (event "tornado" from Tornadoes, the original's stream
## ): "nature\tornado\circle.wav" looped at it
## (3D, priority 0, min 10 / max 40), moved with it by its step
## each tick and stopped when its life runs
## out. Its particle 0x200a is drawn by ParticleFx.tornado from the same event.
var _tornado := {}   # id -> {p, v, life, t0, h}

func on_tornado(e: Dictionary, now: float) -> void:
	var id := int(e.get("id", 0))
	if _tornado.has(id):
		mixer.stop(int(_tornado[id].h))
	var p := Vector3(float(e.x), float(e.y), 0.0)
	_tornado[id] = {"p": p, "v": Vector3(float(e.vx), float(e.vy), 0.0), "life": float(e.life), "t0": now,
		"h": mixer.play3d("nature\\tornado\\circle.wav", 0, p, 10.0, 40.0, true)}


func _tornado_tick(now: float) -> void:
	for id in _tornado.keys():
		var t: Dictionary = _tornado[id]
		var k := now - float(t.t0)
		if k > float(t.life):
			mixer.stop(int(t.h))
			_tornado.erase(id)
		else:
			mixer.move(int(t.h), t.p + t.v * floorf(k))


## Client, every frame:.
func tick(now: float) -> void:
	if not _tornado.is_empty():
		_tornado_tick(now)
	if _shown == 0:
		return
	if _fade != 0.0:
		var f := (now - _start) / _fade
		if f <= 1.0:
			var c := cos(f * PI)
			c = c + 1.0 if _target == 0 else 1.0 - c
			if _handle >= 0:
				mixer.update2d(_handle, roundf(c * 0.5 * 100.0), 0)
			return
	_shown = _target
	if _target == 1 and _handle >= 0:
		mixer.update2d(_handle, 100, 0)
	if _shown == 0 and _handle >= 0:
		mixer.stop(_handle)
		_handle = -1
	_fade = 0.0
