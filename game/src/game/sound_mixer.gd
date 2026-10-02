class_name SoundMixer
extends Node
## the original's sound manager (object, Miles 2D samples), ported:
## 15 sample channels with priorities, 3D sounds whose volume and pan the game
## computes itself from the listener, 2D sounds with a given volume and pan,
## looping sounds that survive losing their channel ("virtual" sounds), the
## randomized sound sources and the dungeon reverb. Every peer mixes its own
## sounds; nothing here is replicated.
##
## Functions:
##    channel allocation, 3D play, 2D play
##    3D volume / pan, 2D update, 3D move
##    stop, listener, 100 ms service
##   (random sources, virtual sounds), reverb parameters.

const CHANNELS := 15
const CAT_SFX := 0
const CAT_SPEECH := 1
##  runs the random sources and restores virtual loops every 100 ms.
const SERVICE := 0.1

class Chan:
	var player: AudioStreamPlayer
	var bus := ""
	var panner: AudioEffectPanner
	var reverb: AudioEffectReverb
	var handle := -1
	var snd: Dictionary = {}

var _chans: Array[Chan] = []
## Looping sounds without a channel: handle -> sound record (with "at", the
## playback position in seconds when the channel was taken).
var _virtual := {}
var _next_handle := 1
## Listener (sound manager..): EI position and the view
## direction and screen-right direction in EI xy (unit vectors).
var listener := Vector3.ZERO
var view_dir := Vector2(0, 1)
var right_dir := Vector2(1, 0)
## Category volume factor (0 or 1): sets the SFX volume to 0 for
## a zone load and restores it on world tick 10.
var sfx_on := true
## Dungeon reverb ((0.3, 1.0, 3.0) when world == 1).
var reverb := false
## Random sources (16 slots of 0x38 bytes).
var _random: Array = []
var _service := 0.0
## Remake: the zone's loops set aside while the global map is up (suspend /
## resume): handle -> sound record, and the random sources.
var suspended := false
var _held := {}
var _held_random: Array = []
## Test hook (tools): print every request with its outcome ("[snd] ...").
static var trace := false


func _ready() -> void:
	for i in CHANNELS:
		var c := Chan.new()
		c.bus = "EISample%d" % i
		var bi := AudioServer.get_bus_index(c.bus)
		if bi < 0:
			AudioServer.add_bus()
			bi = AudioServer.bus_count - 1
			AudioServer.set_bus_name(bi, c.bus)
			AudioServer.add_bus_effect(bi, AudioEffectPanner.new())
			var rv := AudioEffectReverb.new()
			AudioServer.add_bus_effect(bi, rv)
		c.panner = AudioServer.get_bus_effect(bi, 0) as AudioEffectPanner
		c.reverb = AudioServer.get_bus_effect(bi, 1) as AudioEffectReverb
		_set_reverb_params(c.reverb)
		AudioServer.set_bus_effect_enabled(bi, 1, false)
		c.player = AudioStreamPlayer.new()
		c.player.bus = c.bus
		c.player.finished.connect(_on_finished.bind(c))
		add_child(c.player)
		_chans.append(c)


## Miles AIL_set_sample_reverb(level 0.3, reflect time 1.0 s, decay 3.0 s).
## Approx.: Godot's reverb has no reflect / decay times; wet = the level,
## a large room for the 3 s decay, 100 ms pre-delay for the first reflections.
func _set_reverb_params(rv: AudioEffectReverb) -> void:
	rv.wet = 0.3
	rv.dry = 1.0
	rv.room_size = 0.9
	rv.damping = 0.5
	rv.predelay_msec = 100.0
	rv.predelay_feedback = 0.4


func set_reverb(on: bool) -> void:
	reverb = on
	for c in _chans:
		AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(c.bus), 1, on)


# ------------------------------------------------------------------ playing

## a sound at EI position `pos`, full volume within `min_d`
## silent beyond `max_d` (2D distance). Returns a handle, or -1 when it got
## no channel (a loop is then kept virtual and starts when one frees).
func play3d(path: String, prio: int, pos: Vector3, min_d: float, max_d: float, loop := false, cat := CAT_SFX) -> int:
	var s := {"path": path, "prio": prio, "is3d": true, "pos": pos, "min": min_d, "max": max_d,
		"loop": loop, "cat": cat, "vol": 100, "pan": 0, "cam": true}
	return _start(s)


## a 2D sound, `vol` 0..100, `pan` −100..100 (the original's sign:
## Miles gets −pan unless "reverse stereo" is on), `cam` = the camera-height
## fade (listener z 30 .. 70).
func play2d(path: String, prio: int, vol: float, pan: float, loop := false, cam := false, cat := CAT_SFX) -> int:
	var s := {"path": path, "prio": prio, "is3d": false, "pos": Vector3.ZERO, "min": 0.0, "max": 0.0,
		"loop": loop, "cat": cat, "vol": vol, "pan": pan, "cam": cam}
	return _start(s)


## A 2D sound from a stream that is not in sfx.res (briefing voices,
## speech.res), as.
func play_stream2d(stream: AudioStream, prio: int, vol: float, pan: float, cat := CAT_SFX) -> int:
	if stream == null:
		return -1
	var s := {"path": "", "stream": stream, "prio": prio, "is3d": false, "pos": Vector3.ZERO, "min": 0.0,
		"max": 0.0, "loop": false, "cat": cat, "vol": vol, "pan": pan, "cam": false}
	return _start(s)


func _start(s: Dictionary) -> int:
	if not s.has("stream"):
		var stream := EIAudio.sfx(String(s.path))
		if stream == null:
			if trace:
				print("[snd] %.2f %s -> NO FILE" % [Time.get_ticks_msec() / 1000.0, s.path])
			return -1
		if s.loop:
			stream = _looped(stream)
		s.stream = stream
	var h := _next_handle
	_next_handle += 1
	s.handle = h
	if suspended and s.loop:   # starts with the zone's other loops on resume()
		_held[h] = s
		return h
	var ci := _alloc(int(s.prio))
	# the channel is taken first (a lower
	# priority sound may lose it), then a one-shot that would be silent is
	# not started at all: a 3D one whose Miles volume (: distance
	# camera height, category volume) is 0, a 2D one asked for at volume 0.
	# The channel stays free for the next sound.
	if ci >= 0 and not s.loop and (_miles(s) == 0 if s.is3d else float(s.vol) == 0.0):
		if trace:
			print("[snd] %.2f %s prio %d -> SILENT, not started" % [Time.get_ticks_msec() / 1000.0, s.path, int(s.prio)])
		return -1
	if trace:
		_trace(s, ci)
	if ci < 0:
		if s.loop:   # a loop with no channel waits as a virtual sound
			s.at = 0.0
			_virtual[h] = s
			return h
		return -1
	_bind(_chans[ci], s, 0.0)
	return h


func _trace(s: Dictionary, ci: int) -> void:
	var busy := 0
	for c in _chans:
		if c.handle >= 0:
			busy += 1
	var vol := volume_pan(s).x if s.is3d else float(s.vol)
	print("[snd] %.2f %s prio %d vol %d cat %d -> %s (busy %d)" % [Time.get_ticks_msec() / 1000.0,
		String(s.path) if s.path else "<stream>", int(s.prio), int(vol), int(s.cat),
		("chan %d" % ci) if ci >= 0 else "DROPPED", busy])
	if ci < 0:
		for c in _chans:
			if c.handle >= 0:
				print("[snd]     holds %s prio %d vol %d loop %s" % [c.snd.path, int(c.snd.prio),
					int(volume_pan(c.snd).x if c.snd.is3d else float(c.snd.vol)), c.snd.loop])


## Looping copy of a decoded wav (Miles loop count 0 = forever).
func _looped(st: AudioStreamWAV) -> AudioStreamWAV:
	var key := "_loop"
	if st.has_meta(key):
		return st.get_meta(key)
	var l := st.duplicate() as AudioStreamWAV
	l.loop_mode = AudioStreamWAV.LOOP_FORWARD
	l.loop_begin = 0
	var frame := (2 if l.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if l.stereo else 1)
	l.loop_end = l.data.size() / frame
	st.set_meta(key, l)
	return l


## a free channel, else the lowest-priority one if `prio` is
## higher (a looping sound there becomes virtual), else −1.
func _alloc(prio: int) -> int:
	var low := 0x7fffffff
	var li := 0
	# _chans is empty until _ready (a sound requested before the mixer is in
	# the tree): no channel then.
	for i in _chans.size():
		var c := _chans[i]
		if c.handle < 0:
			return i
		if int(c.snd.prio) < low:
			low = int(c.snd.prio)
			li = i
	if prio <= low:
		return -1
	var c := _chans[li]
	if c.snd.loop:
		var v: Dictionary = c.snd
		v.at = c.player.get_playback_position()
		_virtual[c.handle] = v
	c.player.stop()
	c.handle = -1
	c.snd = {}
	return li


func _bind(c: Chan, s: Dictionary, at: float) -> void:
	c.handle = int(s.handle)
	c.snd = s
	c.player.stream = s.stream
	AudioServer.set_bus_send(AudioServer.get_bus_index(c.bus), "Voice" if int(s.cat) == CAT_SPEECH else "SFX")
	_apply(c)
	c.player.play(at)


func _on_finished(c: Chan) -> void:
	if c.snd.get("loop", false):
		return
	c.handle = -1
	c.snd = {}


func stop(h: int) -> void:
	if h < 0:
		return
	_virtual.erase(h)
	_held.erase(h)
	for c in _chans:
		if c.handle == h:
			c.player.stop()
			c.handle = -1
			c.snd = {}


## everything off (zone load).
func stop_all() -> void:
	_virtual.clear()
	_random.clear()
	suspended = false
	_held.clear()
	_held_random.clear()
	for c in _chans:
		c.player.stop()
		c.handle = -1
		c.snd = {}


## True while the sound is on a channel or waiting virtual
func playing(h: int) -> bool:
	if h < 0:
		return false
	if _virtual.has(h) or _held.has(h):
		return true
	for c in _chans:
		if c.handle == h:
			return true
	return false


func _rec(h: int) -> Dictionary:
	if h < 0:
		return {}
	if _virtual.has(h):
		return _virtual[h]
	if _held.has(h):
		return _held[h]
	for c in _chans:
		if c.handle == h:
			return c.snd
	return {}


## Remake: the global map. the original clears the world before the map loads
## so no zone sound plays on it; the remake
## keeps the zone frozen for "Stay here". Every sound stops; the looping ones
## (ambience, rain, torches, .mob sources, spell loops) and the random sources
## are kept under their handles, so their owners still move / update / stop
## them, and resume() starts them again from their beginning, as a zone load
## starts its standing sounds.
func suspend() -> void:
	if suspended:
		return
	suspended = true
	for c in _chans:
		if c.handle < 0:
			continue
		if c.snd.get("loop", false):
			_held[c.handle] = c.snd
		c.player.stop()
		c.handle = -1
		c.snd = {}
	for h in _virtual:
		_held[h] = _virtual[h]
	_virtual.clear()
	_held_random = _random
	_random = []


func resume() -> void:
	if not suspended:
		return
	suspended = false
	var now := Time.get_ticks_msec()
	for h in _held:
		var v: Dictionary = _held[h]
		v.at = 0.0
		_virtual[h] = v
	_held.clear()
	for r: Dictionary in _held_random:
		r.last = now
	_random.append_array(_held_random)
	_held_random = []
	_restore_virtual()


## Looping sounds on a channel or waiting for one (tests).
func loops_playing() -> int:
	var n := _virtual.size()
	for c in _chans:
		if c.handle >= 0 and c.snd.get("loop", false) and c.player.playing:
			n += 1
	return n


## Any channel sounding (tests).
func channels_playing() -> int:
	var n := 0
	for c in _chans:
		if c.handle >= 0 and c.player.playing:
			n += 1
	return n


## new volume / pan of a 2D sound.
func update2d(h: int, vol: float, pan: float) -> void:
	var s := _rec(h)
	if s.is_empty():
		return
	s.vol = vol
	s.pan = pan


## a 3D sound moves.
func move(h: int, pos: Vector3) -> void:
	var s := _rec(h)
	if not s.is_empty():
		s.pos = pos


# ------------------------------------------------------------------ volume

## Camera-height fade on the listener z (sound manager).
func _cam_fade() -> float:
	if listener.z >= 70.0:
		return 0.0
	if listener.z > 30.0:
		return 1.0 - (listener.z - 30.0) / 40.0
	return 1.0


##  for a 3D sound: [volume 0..100, original pan −100..100].
func volume_pan(s: Dictionary) -> Vector2:
	var p: Vector3 = s.pos
	var d := Vector2(p.x - listener.x, p.y - listener.y)
	var dist := d.length()
	if dist > float(s.max):
		return Vector2.ZERO
	var v := 100.0
	if dist >= float(s.min) and float(s.max) > float(s.min):
		v = 100.0 - roundf((dist - float(s.min)) / (float(s.max) - float(s.min)) * 100.0)
	v *= _cam_fade()
	return Vector2(v, screen_pan(d))


## The original's pan: the angle between the sound and the view axis (folded to
## 0 .. π/2) scaled to 0 .. 100. Its sign is taken from the side of the screen
## the sound is on (right = +) and the result is returned in the original's
## convention (Miles gets −pan when reverse stereo is off).
func screen_pan(d: Vector2) -> float:
	var dist := d.length()
	if dist == 0.0 or dist < absf(d.dot(view_dir)):
		return 0.0
	var a := acos(clampf(d.dot(view_dir) / dist, -1.0, 1.0))
	if a > PI / 2.0:
		a = PI - a
	var mag := roundf(100.0 / (PI / 2.0) * a)
	return -mag if d.dot(right_dir) >= 0.0 else mag


##  Miles volume of a 3D sound: round(volume × the
## category volume (sound manager SFX / speech, the Options
## volumes; SFX 0 during a zone load) × 0.0127), 0..127.
func _miles(s: Dictionary) -> int:
	var cat := 0.0
	if int(s.cat) == CAT_SPEECH:
		cat = GameData.option("volume_voice")
	elif sfx_on:
		cat = GameData.option("volume_sfx")
	return clampi(roundi(volume_pan(s).x * cat * 0.0127), 0, 127)


func _apply(c: Chan) -> void:
	var s := c.snd
	var v := 0.0
	var pan := 0.0
	if s.is3d:
		var vp := volume_pan(s)
		v = vp.x
		pan = vp.y
	else:
		v = float(s.vol) * (_cam_fade() if s.cam else 1.0)
		pan = float(s.pan)
	if int(s.cat) == CAT_SFX and not sfx_on:
		v = 0.0
	# Miles volume 0..127 = round(v × category volume × 0.0127); the category
	# volume is the SFX / Voice bus. Approx.: Miles' volume is taken as linear.
	c.player.volume_db = linear_to_db(maxf(roundf(v * 1.27) / 127.0, 0.00001))
	# Miles pan = (−pan + 100) × 127 / 200; reverse stereo is the SFX bus's
	# channel swap (GameData._apply_audio). Approx.: Godot's panner law.
	c.panner.pan = clampf(-pan / 100.0, -1.0, 1.0)


# ------------------------------------------------------------------ per frame

func set_listener(pos: Vector3, forward: Vector2, right: Vector2) -> void:
	listener = pos
	if forward.length_squared() > 0.0:
		view_dir = forward.normalized()
	if right.length_squared() > 0.0:
		right_dir = right.normalized()


func _process(dt: float) -> void:
	for c in _chans:
		if c.handle >= 0:
			_apply(c)
	_service -= dt
	if _service > 0.0:
		return
	_service += SERVICE
	if _service < 0.0:
		_service = SERVICE
	_restore_virtual()
	_random_tick()


## virtual loops get the free channels back, highest priority
## first, at the position they had reached.
func _restore_virtual() -> void:
	if _virtual.is_empty():
		return
	var order := _virtual.values()
	order.sort_custom(func(a, b): return int(a.prio) > int(b.prio))
	for s: Dictionary in order:
		var free := -1
		for i in _chans.size():
			if _chans[i].handle < 0:
				free = i
				break
		if free < 0:
			return
		_virtual.erase(int(s.handle))
		var st: AudioStream = s.stream
		var at := fmod(float(s.get("at", 0.0)), maxf(st.get_length(), 0.001))
		_bind(_chans[free], s, at)


# ------------------------------------------------------------------ random sources

## A randomized source (.mob SOUND record with the random flag, class 0x49;
## script CreateRandomizedFXSource): `names` played at random intervals.
func add_random(names: PackedStringArray, pos: Vector3, inner: float, outer: float, min_ms: int, max_ms: int) -> void:
	if _random.size() >= 16 or names.is_empty():
		return
	_random.append({"names": names, "pos": pos, "inner": inner, "outer": outer,
		"min": float(min_ms), "max": float(max_ms), "last": Time.get_ticks_msec()})


## every 100 ms: outside the inner radius both intervals grow
## (outer − inner) / (outer − d); beyond the outer radius nothing plays. Once
## the minimum has passed a sound plays with chance 1 / ((max − min) / 100) per
## check, and always once the maximum has passed: a random name, 2D, priority
## 1, volume 50 + rand % 51, pan rand % 101.
func _random_tick() -> void:
	var now := Time.get_ticks_msec()
	for r: Dictionary in _random:
		var p: Vector3 = r.pos
		var d := Vector2(p.x - listener.x, p.y - listener.y).length()
		if d > float(r.outer):
			continue
		var lo: float = r.min
		var hi: float = r.max
		if d > float(r.inner) and float(r.outer) > d:
			var k := (float(r.outer) - float(r.inner)) / (float(r.outer) - d)
			lo *= k
			hi *= k
		var el := float(now - int(r.last))
		if el < lo:
			continue
		var go := el >= hi
		if not go:
			var n := int((hi - lo) / 100.0)
			go = n <= 1 or randi() % n == 0
		if go:
			r.last = now
			var names: PackedStringArray = r.names
			play2d(names[randi() % names.size()], 1, 50 + randi() % 51, randi() % 101)
