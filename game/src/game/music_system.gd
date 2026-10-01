class_name MusicSystem
extends Node
## Music, the original CMusicSystem over the
## stream player of the sound manager (thread
## requests, fades).
##
## Tracks come from res/music.reg (per allod: Briefing, Constructor, CalmOpen,
## CalmDungeon, Combat; "common": MainMenu, Credits) and play from
## stream/<name>.mp3. res/streamsn.reg gives per track Markers2 (the loop point,
## in samples: the stream jumps back to 0 there) or Markers1 (the points where
## a "switch at marker" request may cut over).

enum Mode { NONE, ZONE, BRIEFING, CONSTRUCTOR, MAIN_MENU, CREDITS }
##  request modes: 1 at the end of the track, 2 fade out first
## 3 at the next Markers1 point, 4 at once.
const AT_END := 1
const FADE := 2
const AT_MARKER := 3
const NOW := 4
## The fader moves 1/96 per 100 ms stream-thread step.
const FADE_STEP := 1.0 / 96.0
const FADE_TICK := 0.1

var player: AudioStreamPlayer
var mode := Mode.NONE
var allod := "gipat"
var dungeon := false
## set by SetZoneMode, cleared on world tick 90 (or
## earlier while the combat flag is 2).
var hold := false
var combat := false
var _last_combat := ""
var _forced := ""            # script PlayMusic
var _forced_on := false
var _next_calm := 0          # timeGetTime ms (0 = unset)

# Stream state (sound manager..).
var _cur := ""               # "" = silence
var _pending := ""
var _pending_mode := 0
var _switch_at := -1         # sample position (= at the end)
var _has_pending := false
var _wrap := false           # the switch point comes after the track restarts
var _fade := 1.0
var _fading := 0             # 1 , 2 out
var _fade_acc := 0.0
var _rate := 44100.0
var _markers1 := PackedInt32Array()
var _loop_at := -1
static var _streams := {}


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	player.finished.connect(_on_end)
	add_child(player)


## streamsn.reg record of a track.
static func markers(track: String) -> Dictionary:
	if _streams.is_empty() and GameData.root:
		var p := GameData.root.path_join("res/streamsn.reg")
		if FileAccess.file_exists(p):
			_streams = EIRegFile.parse(FileAccess.get_file_as_bytes(p))
	for k in _streams:
		if String(k).to_lower() == track.to_lower() + ".mp3":
			return _streams[k]
	return {}


func _table(section: String, key: String) -> PackedStringArray:
	var t := EIAudio.music_table()
	var sec: Dictionary = {}
	for k in t:
		if String(k).to_lower() == section:
			sec = t[k]
	var v = sec.get(key, "")
	var out := PackedStringArray()
	for x in (v if v is Array else [v]):
		if String(x) != "":
			out.append(String(x))
	return out


func _random(section: String, key: String) -> String:
	var l := _table(section, key)
	return l[randi() % l.size()] if not l.is_empty() else ""


# ------------------------------------------------------------------ modes

## a zone starts (allod "final" on gz20g; dungeon = world).
func set_zone(a: String, dun: bool) -> void:
	_cut()
	mode = Mode.ZONE
	allod = a
	dungeon = dun
	hold = true
	combat = false
	_forced_on = false
	_next_calm = 0


## the briefing track at once.
func set_briefing() -> void:
	_cut()
	mode = Mode.BRIEFING
	request(_random(allod, "Briefing"), NOW)


## the camp / trade screen (constructor) track at once.
func set_constructor() -> void:
	_cut()
	mode = Mode.CONSTRUCTOR
	request(_random(allod, "Constructor"), NOW)


## Back to the zone rules (the screen closed): the zone mode again, as
##  caller restores it with SetZoneMode.
func back_to_zone() -> void:
	if mode == Mode.ZONE:
		return
	_cut()
	mode = Mode.ZONE
	combat = false
	_next_calm = 0


## script PlayMusic: only in the zone mode; the track at once
## then silence at its end.
func play_forced(track: String) -> void:
	if mode != Mode.ZONE or EIAudio.music(track) == null:
		return
	_forced = track
	_forced_on = true
	request(track, NOW)
	request("", AT_END)


##  (conversation start / end
## ): fade the music out, or back .
func fade_out() -> void:
	if _cur != "":
		_fading = 2


func fade_in() -> void:
	if _fading == 2 or _fade < 1.0:
		_fading = 1


# ------------------------------------------------------------------ zone rules

## every world tick in the zone mode.
func tick(combat_flag: int) -> void:
	if mode != Mode.ZONE or hold:
		return
	var now := Time.get_ticks_msec()
	if _forced_on:
		if _cur == _forced:
			return
		_forced_on = false
		combat = false
		_next_calm = now + 120000 + randi() % 60001
	var c := combat_flag == 2
	if not combat:
		if c:
			if _cur != _last_combat or _last_combat == "":
				_last_combat = _random(allod, "Combat")
			request(_last_combat, AT_MARKER)
		elif _cur == "":
			if _next_calm == 0:
				_next_calm = now + 120000 + randi() % 60001
			if now >= _next_calm:
				_next_calm = 0
				var t := _random(allod, "CalmDungeon" if dungeon else "CalmOpen")
				if t:
					request(t, NOW)
					request("", AT_END)
	elif not c:
		request("", FADE)
		_next_calm = now + 120000 + randi() % 60001
	combat = c


# ------------------------------------------------------------------ stream player

func request(track: String, how: int) -> void:
	if _cur == "":
		how = NOW
	elif _cur == track and track != "":
		_has_pending = false   # keep playing; a fade-out turns back into a fade-in
		if _pending_mode == FADE or _fading == 2:
			_fading = 1
		return
	if _has_pending and _pending == track and how <= _pending_mode:
		return
	var at := -1
	match how:
		FADE:
			_fading = 2
			at = 0x7fffffff
		AT_MARKER:
			if _markers1.is_empty():
				how = AT_END
				at = 0x7fffffff
			else:
				var pos := _pos()
				at = -1
				for m in _markers1:
					if m >= pos:
						at = m
						break
				_wrap = at < 0
				if at < 0:   # past the last point: the first one, next time round
					at = _markers1[0]
		NOW:
			at = _pos()
		AT_END:
			at = 0x7fffffff
	if how != AT_MARKER:
		_wrap = false
	_has_pending = true
	_pending = track
	_pending_mode = how
	_switch_at = at
	if how == NOW:
		_switch()


## (4): stop at once (a mode change).
func _cut() -> void:
	player.stop()
	_cur = ""
	_has_pending = false
	_fading = 0
	_fade = 1.0
	_apply_volume()


func _pos() -> int:
	return int(player.get_playback_position() * _rate) if player.playing else 0


func _switch() -> void:
	_has_pending = false
	var track := _pending
	_cur = track
	_fading = 0
	_fade = 1.0
	_apply_volume()
	if track == "":
		player.stop()
		return
	var s := EIAudio.music(track)
	if s == null:
		_cur = ""
		player.stop()
		return
	_rate = _mp3_rate(s.data)
	var m := markers(track)
	_markers1 = PackedInt32Array()
	var m1 = m.get("Markers1", [])
	if m1 is Array or m1 is PackedInt32Array:
		for x in m1:
			_markers1.append(int(x))
	_markers1.sort()
	_loop_at = int(m.get("Markers2", -1)) if not (m.get("Markers2", -1) is Array) else -1
	player.stream = s
	player.play()


## The sample rate of the first MPEG audio frame.
static func _mp3_rate(d: PackedByteArray) -> float:
	var i := 0
	if d.size() > 10 and d.slice(0, 3).get_string_from_ascii() == "ID3":
		i = 10 + ((d[6] & 0x7f) << 21 | (d[7] & 0x7f) << 14 | (d[8] & 0x7f) << 7 | (d[9] & 0x7f))
	while i + 4 < d.size():
		if d[i] == 0xff and (d[i + 1] & 0xe0) == 0xe0:
			var ver := (d[i + 1] >> 3) & 3
			var ri := (d[i + 2] >> 2) & 3
			var base: float = [44100.0, 48000.0, 32000.0, 44100.0][ri]
			return base if ver == 3 else base / 2.0 if ver == 2 else base / 4.0
		i += 1
	return 44100.0


func _on_end() -> void:
	# The end of the data: a pending "at the end" switch happens, else the
	# track starts over.
	if _has_pending and _switch_at == 0x7fffffff and _pending_mode != FADE:
		_switch()
	elif _cur != "":
		_wrap = false
		player.play()


func _process(dt: float) -> void:
	if not player.playing:
		return
	var pos := _pos()
	if _has_pending and not _wrap and _pending_mode != FADE and _switch_at != 0x7fffffff and pos >= _switch_at:
		_switch()
		return
	if _loop_at > 0 and pos >= _loop_at:   # Markers2: back to the start
		if _has_pending and _switch_at == 0x7fffffff and _pending_mode != FADE:
			_switch()
			return
		_wrap = false
		player.seek(0.0)
	if _fading != 0:
		_fade_acc += dt
		while _fade_acc >= FADE_TICK:
			_fade_acc -= FADE_TICK
			if _fading == 2:
				_fade = maxf(_fade - FADE_STEP, 0.0)
				if _fade <= 0.0:
					_fading = 0
					if _has_pending and _pending_mode == FADE:
						_switch()
					return
			else:
				_fade = minf(_fade + FADE_STEP, 1.0)
				if _fade >= 1.0:
					_fading = 0
		_apply_volume()


func _apply_volume() -> void:
	if player:
		player.volume_db = linear_to_db(maxf(_fade, 0.00001))
