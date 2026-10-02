class_name UnitSounds
extends RefCounted
## Unit voices and footsteps from the animation clips, the original
## (figure update, every frame) (voice file) and
##  (step file). Each.adb clip record (database.res
## "<template>.adb", 88 bytes from 0x2c) names a sound frame and up to
## four sound numbers; its action bits
## choose the folder. Walk and run clips sound a step at each step frame
## (.., stored + 1). Played on every peer from the replicated
## animation, like the footprints (GroundMarks).

const ACT_SPECIAL := 1
const ACT_ATTACK := 2
const ACT_WALK := 4
const ACT_RUN := 5
const ACT_IDLE := 6
const ACT_DEATH := 7
const ACT_HIT := 8
## every unit sound is 3D with min 8 / max 40.
const MIN_D := 8.0
const MAX_D := 40.0
## Silence (magic effect 0x10, (0x10)) mutes the steps.
const SILENCE := "silence"

var mixer: SoundMixer
var world: GameWorld
var _adb := {}            # template -> {clip: record}
var _units := {}          # instance id -> {clip, frame, idle, attack}
var _stamp := 0
var _steps := {}          # steps path -> file count
static var _dbres: EIResArchive


func _init(m: SoundMixer, w: GameWorld) -> void:
	mixer = m
	world = w


func tick() -> void:
	if world == null:
		return
	# Every frame over every unit: no per-frame allocations (the clip name is
	# only rebuilt when the player's animation changes, units not seen this
	# frame are found by a stamp instead of a set).
	# A unit farther than MAX_D (2D) from the listener is skipped: each of its
	# sounds would get volume 0 and a silent one-shot is never started
	# (see SoundMixer._start); it re-syncs without a sound when
	# it comes back in range.
	_stamp += 1
	var n := 0
	var lis := Vector2(mixer.listener.x, mixer.listener.y)
	for u: GameUnit in world.units.values():
		if not is_instance_valid(u):
			continue
		var key := u.get_instance_id()
		var st: Dictionary = _units.get(key, {})
		if u.pos.distance_squared_to(lis) > MAX_D * MAX_D:
			if not st.is_empty():
				n += 1
				st.seen = _stamp
				st.far = true
			continue
		if u.model == null or u.model.player == null:
			continue
		n += 1
		var pl := u.model.player
		var anim: StringName = pl.current_animation
		var cur := pl.current_animation_position * EIAnim.FPS
		if st.is_empty() or st.get("far", false):   # first sight (a joiner's corpse, a new model) / back in range: no sound
			var c := String(anim).trim_prefix("ei/")
			if st.is_empty():
				_units[key] = {"clip": c, "anim": anim, "name": c, "frame": cur, "idle": -1, "attack": -1, "seen": _stamp}
			else:
				st.merge({"clip": c, "anim": anim, "name": c, "frame": cur, "seen": _stamp, "far": false}, true)
			continue
		st.seen = _stamp
		if anim != st.anim:
			st.anim = anim
			st.name = String(anim).trim_prefix("ei/")
		var clip: String = st.get("name", st.clip)
		if clip == "":
			continue
		var prev: float = st.frame
		if clip != st.clip:   # a new clip record: the previous frame restarts at 0
			st.clip = clip
			prev = 0.0
		elif cur < prev:      # the clip looped (the remake replays it in place)
			prev = 0.0
		st.frame = cur
		if cur == prev or not u.visible:
			continue
		var rec: Dictionary = _clips(u.model.template).get(clip, {})
		if not rec.is_empty():
			_frame(u, st, rec, prev, cur)
	if _units.size() > n:
		for k in _units.keys():
			if int(_units[k].seen) != _stamp:
				_units.erase(k)


## The unit's attack sound is still playing.
func attack_playing(u: GameUnit) -> bool:
	var st: Dictionary = _units.get(u.get_instance_id(), {})
	return not st.is_empty() and mixer.playing(int(st.attack))


## an attack acknowledgement takes the attack sound's place.
func set_attack(u: GameUnit, h: int) -> void:
	var st: Dictionary = _units.get(u.get_instance_id(), {})
	if not st.is_empty():
		st.attack = h


func _frame(u: GameUnit, st: Dictionary, rec: Dictionary, prev: float, cur: float) -> void:
	var act: int = rec.act
	match act:
		ACT_WALK, ACT_RUN:
			var steps: PackedInt32Array = rec.steps
			for i in steps.size():
				var f := steps[i] - 1
				if f == 0:
					break
				if prev < f and f <= cur:
					if not u.buffs.has(SILENCE):
						var path := _step_path(u)
						if path:
							mixer.play3d(path, 0, _at(u), MIN_D, MAX_D)
					break
			return
		ACT_ATTACK:
			# no attack sound at all while the client's screen
			# (world) is 3, a "brief" zone (village).
			if String(world.zone.get("type", "")) == "brief":
				return
			mixer.stop(int(st.idle))
			# A character's missed blow (unit, rolled at the strike's
			# start) sounds "weapons\miss.wav" at the clip's sound frame
			# (miss branch, 3D 1000), besides the attack voice.
			if u.strike_miss and int(u.race.get("type_id", 0)) == 0x32 \
					and rec.frame != 0 and prev <= float(rec.frame) and float(rec.frame) < cur:
				mixer.play3d("weapons\\miss.wav", 1000, _at(u), MIN_D, MAX_D)
			_voice(u, st, rec, prev, cur, 1000)
		ACT_DEATH:
			mixer.stop(int(st.idle))
			mixer.stop(int(st.attack))
			_voice(u, st, rec, prev, cur, 1000)
		ACT_SPECIAL:
			_voice(u, st, rec, prev, cur, 1000)
		ACT_IDLE, ACT_HIT:
			_voice(u, st, rec, prev, cur, 0)


## the clip's sound frame f (0 = none) sounds when
## prev ≤ f < cur; one of its non-zero sound numbers at random.
func _voice(u: GameUnit, st: Dictionary, rec: Dictionary, prev: float, cur: float, prio: int) -> void:
	var f := float(rec.frame)
	if rec.frame == 0 or f < prev or cur <= f:
		return
	var nums: PackedInt32Array = rec.sounds
	if nums.is_empty():
		return
	var n := nums[randi() % nums.size()]
	var act: int = rec.act
	var path := ""
	# The prototype's sound folder (monster_prototypes field 9, proto)
	# replaces the race's sfx path (race) when set.
	var dir := String(u.proto.get("unknown2", ""))
	if dir.is_empty():
		dir = String(u.race.get("sfx_path", ""))
	match act:
		ACT_IDLE:
			if randi() % 100 >= int(u.race.get("idle_sound_p", 0)):
				return
			path = "%s\\idle\\%d.wav" % [dir, n]
		ACT_SPECIAL:
			match (int(rec.code) >> 22) & 0xff:
				0x13: path = "heroes\\human\\skills\\tame.wav"
				0x14: path = "heroes\\human\\skills\\steal.wav"
				0x15: path = "heroes\\human\\skills\\science.wav"
				0x16, 0x30, 0x34, 0x35: path = "heroes\\human\\skills\\loot.wav"
		ACT_ATTACK:
			# A character (race type 0x32) with a bow or crossbow (weapon
			# type 5 / 6) sounds "weapons\<n>.wav" instead of its voice.
			var wt := GameSound.held_weapon_type(u)
			if int(u.race.get("type_id", 0)) == 0x32 and (wt == 5 or wt == 6):
				path = "weapons\\%d.wav" % n
			elif randi() % 100 >= int(u.race.get("attack_sound_p", 0)):
				return
			else:
				path = "%s\\attack\\%d.wav" % [dir, n]
			# Only one attack sound per unit at a time.
			if mixer.playing(int(st.attack)):
				return
			st.attack = mixer.play3d(path, prio, _at(u), MIN_D, MAX_D)
			return
		ACT_DEATH:
			path = "%s\\death\\%d.wav" % [dir, n]
		ACT_HIT:
			path = "%s\\hit\\%d.wav" % [dir, n]
	if path.is_empty():
		return
	var h := mixer.play3d(path, prio, _at(u), MIN_D, MAX_D)
	if act == ACT_IDLE:
		st.idle = h


## The sound folders the zone's units can play from (steps of every ground,
## crawling, the voice folders, bow / crossbow shots), for
## EIAudio.prefetch at the zone start (remake: no first-play stall).
static func zone_folders(w: GameWorld) -> PackedStringArray:
	var out := PackedStringArray(["steps\\human\\crawl", "weapons"])
	var seen := {}
	for u: GameUnit in w.units.values():
		var key := "%s|%s" % [u.race.get("sfx_path", ""), u.proto.get("unknown2", "")]
		if seen.has(key):
			continue
		seen[key] = true
		var paths = u.race.get("steps_path", [])
		if paths is Array or paths is PackedStringArray:
			for p in paths:
				if String(p) and not out.has(String(p)):
					out.append(String(p))
		var dir := String(u.proto.get("unknown2", ""))
		if dir.is_empty():
			dir = String(u.race.get("sfx_path", ""))
		if dir:
			for sub in ["idle", "attack", "death", "hit"]:
				out.append("%s\\%s" % [dir, sub])
	return out


## the step file for the ground under the unit
## (tile type; 2 = Stone when the unit stands off the terrain
## |ground − terrain| > 0.01, e.g. on a bridge). Crawling units (= 0)
## sound "steps\human\crawl\1..6" except in water (6) and swamp (14);
## otherwise race steps_path[type] (race) with its file count.
func _step_path(u: GameUnit) -> String:
	var paths = u.race.get("steps_path", [])
	if not (paths is Array or paths is PackedStringArray):
		return ""
	var t := world.terrain.ground_type(u.pos.x, u.pos.y) if world.terrain else 0
	if t >= paths.size() or _count(String(paths[t])) == 0:
		return ""
	if world.terrain and absf(world.ground_at(u.pos.x, u.pos.y) - world.terrain.height_at(u.pos.x, u.pos.y)) > 0.01:
		t = 2
	if u.stance == GameUnit.STANCE_CRAWL and t != 14 and t != 6:
		return "steps\\human\\crawl\\%d.wav" % (randi() % 6 + 1)
	if t >= paths.size():
		return ""
	var n := _count(String(paths[t]))
	if n == 0:
		return ""
	return "%s\\%d.wav" % [String(paths[t]), randi() % n + 1]


## the count = the sfx.res wavs under the path.
func _count(path: String) -> int:
	if not _steps.has(path):
		_steps[path] = EIAudio.sfx_dir(path).size() if path else 0
	return _steps[path]


static func _at(u: GameUnit) -> Vector3:
	return Vector3(u.pos.x, u.pos.y, u.global_position.y)


## The .adb clip records that make sound: {clip: {act, code, steps, frame, sounds}}.
func _clips(tmpl: String) -> Dictionary:
	if _adb.has(tmpl):
		return _adb[tmpl]
	var out := {}
	if _dbres == null and GameData.root != "":
		_dbres = EIResArchive.open_path(GameData.root.path_join("res/database.res"))
	var b := _dbres.read(tmpl + ".adb") if _dbres else PackedByteArray()
	if b.size() >= 0x2c and b.slice(0, 3).get_string_from_ascii() == "ADB":
		for i in b.decode_u32(4):
			var p := 0x2c + i * 88
			if p + 88 > b.size():
				break
			var code := b.decode_u32(p + 0x14)
			var act := (code >> 18) & 15
			if act not in [ACT_SPECIAL, ACT_ATTACK, ACT_WALK, ACT_RUN, ACT_IDLE, ACT_DEATH, ACT_HIT]:
				continue
			var steps := PackedInt32Array()
			for k in 4:
				steps.append(b.decode_s32(p + 0x30 + k * 4))
			var sounds := PackedInt32Array()
			for k in 4:   # the list ends at the first 0
				var n := b.decode_s32(p + 0x48 + k * 4)
				if n == 0:
					break
				sounds.append(n)
			out[b.slice(p, p + 16).get_string_from_ascii()] = {"act": act, "code": code, "steps": steps,
				"frame": b.decode_s32(p + 0x44), "sounds": sounds}
	_adb[tmpl] = out
	return out
