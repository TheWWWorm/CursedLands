class_name GameSound
extends Node
## All play-mode audio, played locally on every peer from replicated state and
## events, through SoundMixer (the original's 15-channel sound manager):
## ground ambience (AmbientSound), map and script sound objects, unit voices
## and steps from the animation (UnitSounds), weapon impacts, spells and magic
## effects (SpellSounds), acknowledgements, briefing voices, UI sounds and the
## music (MusicSystem). See docs/original_reference.md, "Audio".

## the original logic tick (= 55 ms): the zone-load counters
## the ambience and the music rules.
const TICK := 0.055
## world tick 10 restores the SFX volume, tick 0x5a (90) lets
## the music start (or the combat flag 2 earlier).
const SFX_TICK := 10
const MUSIC_TICK := 90
## the struck body part's armour slots (16 bytes
## per part: three item slots, 7 = none; tried in the order +8, +0, +4).
const HIT_SLOTS := [[7, 7, 0], [3, 7, 1], [3, 6, 1], [3, 6, 1], [4, 5, 2], [4, 5, 2]]
## casting is hostile for spells 0..8 and 0x1a.
const HOSTILE_SPELLS := ["arrow", "lightning", "acid_ray", "fireball", "inv_lit", "acid_column", "firewall",
	"litnwall", "acid_fog", "antimagic"]

static var instance: GameSound

var game: Game
var mixer: SoundMixer
var music: MusicSystem
var ambient: AmbientSound
var units: UnitSounds
var spells: SpellSounds
var weather: Weather
var _world: GameWorld
var _ticks := 0
var _tick_acc := 0.0
var _map_sounds: Array[int] = []
## Torch fire loops: [{node, wav, radius, handle, shown}] (CTorchObjectClientSpecific).
var _torches: Array = []
var _fx_sources := {}          # script FX source id -> handle
var _fx_auto := -1             # ids for CreateFXSource(-1,...) (counting down)
var _speech_h := -1
var _acks := {}                # uid -> [wav, msec] (figure)
## Per-unit acknowledgement queues (figure): uid -> [{u, wav, code
## counter, handle}],.
var _ack_q := {}
## these codes are queued even while another line is pending
## any other code is dropped then.
const ACK_URGENT := [0x1d, 0x1e, 0x1f, 0x23, 0x24, 0x25, 0x26, 0x2a]
## a new code removes the pending lines of these codes.
const ACK_REPLACES := {0xd: [9], 0xe: [1], 0xf: [3], 0x10: [3], 0x11: [5, 6], 0x13: [3]}
## This peer's combat-music flag (world =, from the
## server's message 0x60).
var combat_flag := 0
var _sent_flags := {}          # host: player index -> value sent
var _dialog_was := false
var _shop_was := false


func _ready() -> void:
	instance = self
	mixer = SoundMixer.new()
	add_child(mixer)
	music = MusicSystem.new()
	add_child(music)


func _exit_tree() -> void:
	if instance == self:
		instance = null


# ------------------------------------------------------------------ zone

##  (zone load): all sounds stop, the SFX volume goes to 0 until
## world tick 10, the reverb follows the dungeon flag, the music gets
## SetZoneMode and the ambience its set.
func _zone_start(w: GameWorld) -> void:
	_world = w
	mixer.stop_all()
	_map_sounds.clear()
	_torches.clear()
	_fx_sources.clear()
	_fx_auto = -1
	_ack_q.clear()
	_ticks = 0
	_tick_acc = 0.0
	combat_flag = 0
	_sent_flags.clear()
	if ambient:
		ambient.stop()
	ambient = null
	units = null
	spells = null
	if weather:
		weather.stop()
	weather = null
	if w == null:
		return
	mixer.sfx_on = false
	var dungeon := String(w.zone.get("sky", "")) == "cave"
	mixer.set_reverb(dungeon)
	var allod := String(w.zone.get("allod", "gipat")).to_lower()
	if String(w.zone.get("id", "")) == Session.ENDING_ZONE or String(w.zone.get("mpr", "")) == Session.ENDING_ZONE:
		allod = "final"
	if allod.is_empty():
		allod = "gipat"
	if String(w.zone.get("type", "")) == "brief":
		music.allod = allod
		music.set_briefing()
	else:
		music.set_zone(allod, dungeon)
	_update_listener()
	ambient = AmbientSound.new(mixer, w, dungeon)
	units = UnitSounds.new(mixer, w)
	spells = SpellSounds.new(mixer, w)
	weather = Weather.new(mixer, w)
	if w.authority and not w.item_worn.is_connected(_on_item_worn):
		w.item_worn.connect(_on_item_worn)
	# .mob SOUND objects (case 3): a looping sound object
	# (class 0x48, client: the first wave, min = inner radius
	# max = outer radius, priority 0, looped), or with the random flag a
	# randomized source (class 0x49) of all waves.
	if w.mob:
		for s: Dictionary in w.mob.sounds:
			var waves: PackedStringArray = s.waves
			if waves.is_empty():
				continue
			var p: Vector3 = s.position
			if int(s.random):
				mixer.add_random(waves, p, float(s.inner), float(s.outer), int(s.min_ms), int(s.max_ms))
			else:
				_map_sounds.append(mixer.play3d(waves[0], 0, p, float(s.inner), float(s.outer), true))
	# .mob TORCH objects (case 6): the client object
	# (CTorchObjectClientSpecific) gets its sound name (field
	# ) through =, which loops it at the
	# object: priority 0, min 1, max = light radius (size × 10) × 5. Hidden
	#  it stops; shown again
	# it restarts with max = radius × 3.
	for node in w.objects.values():
		if not is_instance_valid(node) or not node.has_meta("ei"):
			continue
		var o: Dictionary = node.get_meta("ei")
		if String(o.get("kind", "")) != "TORCH" or String(o.get("torch_sound", "")).is_empty():
			continue
		var t := {"node": node, "wav": String(o.torch_sound), "radius": float(o.get("torch_strength", 0.0)) * 10.0,
			"handle": -1, "shown": node.visible}
		if t.shown:
			t.handle = mixer.play3d(t.wav, 0, _ei(node.global_position), 1.0, t.radius * 5.0, true)
		_torches.append(t)


static func _ei(g: Vector3) -> Vector3:
	return Vector3(g.x, -g.z, g.y)


## Torches hidden / shown by scripts (HideObject):.
func _torch_tick() -> void:
	for t: Dictionary in _torches:
		var n: Node3D = t.node
		var vis := is_instance_valid(n) and n.is_visible_in_tree()
		if vis == bool(t.shown):
			continue
		t.shown = vis
		mixer.stop(int(t.handle))
		t.handle = -1
		if vis:
			t.handle = mixer.play3d(String(t.wav), 0, _ei(n.global_position), 1.0, float(t.radius) * 3.0, true)


func _update_listener() -> void:
	var rig: CameraRig = game.rig if game else null
	if rig == null or rig.camera == null or _world == null:
		return
	# the camera's look-at point at ground
	# height + 2 (camera), or its eye while a script holds the camera
	# the direction is the camera's view axis.
	var p: Vector3
	if rig.held:
		var e := rig.camera.global_position
		p = Vector3(e.x, -e.z, e.y)
	else:
		var x := rig.global_position.x
		var y := -rig.global_position.z
		p = Vector3(x, y, _world.ground_at(x, y) + 2.0)
	var b := rig.camera.global_transform.basis
	var f := -b.z
	var r := b.x
	mixer.set_listener(p, Vector2(f.x, -f.z), Vector2(r.x, -r.z))


func _process(dt: float) -> void:
	var w := game.world if game else null
	if w != _world:
		_zone_start(w)
	if w == null:
		return
	_update_listener()
	if units:
		units.tick()
	if spells:
		spells.tick(dt)
	if weather:
		weather.tick(_ticks + _tick_acc / TICK)
	_screens()
	_tick_acc += dt
	while _tick_acc >= TICK:
		_tick_acc -= TICK
		_world_tick()


func _world_tick() -> void:
	_ticks += 1
	if _ticks == SFX_TICK:
		mixer.sfx_on = true
	if _ticks >= MUSIC_TICK or combat_flag == 2:
		music.hold = false
	if ambient:
		ambient.tick()
	_ack_tick()
	_torch_tick()
	if _world.authority and weather:
		weather.host_tick(_ticks)
	if _world.authority:
		_send_combat_flags()
	music.tick(combat_flag)


## The trade / camp screen plays the Constructor music (
## ); a conversation fades the music out and back
func _screens() -> void:
	var hud := game.hud if game else null
	if hud == null:
		return
	var shop: bool = hud._inventory != null and hud._inventory.visible and hud._inventory.shop_mode
	if shop != _shop_was:
		_shop_was = shop
		if shop:
			music.set_constructor()
		else:
			music.back_to_zone()
	# Only a running conversation (the dialog box's modes 3 / 4), not its
	# topic list: starts it, ends it.
	var talk: bool = hud._dialog != null and hud._dialog.visible \
		and hud._dialog._mode in [DialogPanel.PLAYING, DialogPanel.LAST]
	if talk != _dialog_was:
		_dialog_was = talk
		if talk:
			music.fade_out()
		else:
			music.fade_in()


# ------------------------------------------------------------------ combat flag

## Host, every tick: the combat flag of each player (sent as
## message 0x60). 2 when one of the player's units attacks or casts a hostile
## spell, or a unit hostile to it has one of its units as its
## attack target. Approx.: the original also counts the units the party knows
## (ai lists) and gives 1 for "near but unseen" (not used by music).
func _send_combat_flags() -> void:
	var flags := {}
	for u: GameUnit in _world.units.values():
		if u.controller >= 0 and not flags.has(u.controller):
			flags[u.controller] = 0
	for u: GameUnit in _world.units.values():
		if not is_instance_valid(u) or u.dead:
			continue
		if u.controller >= 0 and _hostile_act(u):
			flags[u.controller] = 2
		var t := _act_target(u)
		if t and t.controller >= 0 and not t.dead and _world.is_enemy(u, t):
			flags[t.controller] = 2
	for p in flags:
		if int(_sent_flags.get(p, -1)) != int(flags[p]):
			_sent_flags[p] = flags[p]
			if _world.session:
				_world.session.broadcast({"t": "combat_flag", "p": p, "v": flags[p]})


static func _act_target(u: GameUnit) -> GameUnit:
	var ty := String(u.order.get("type", ""))
	if ty != "attack" and ty != "cast":
		return null
	var t = u.order.get("target")
	return t if t is GameUnit and is_instance_valid(t) else null


static func _hostile_act(u: GameUnit) -> bool:
	match String(u.order.get("type", "")):
		"attack":
			return _act_target(u) != null
		"cast":
			return String(Spells.parse(String(u.order.get("spell", ""))).code) in HOSTILE_SPELLS
	return false


# ------------------------------------------------------------------ events

## Broadcast events (Game.on_event, every peer).
func on_event(e: Dictionary) -> void:
	match String(e.get("t", "")):
		"spellfx":
			if spells:
				spells.spell(e)
		"magicfx":
			if spells:
				spells.effect(e)
		"impact":
			var u: GameUnit = _world.units.get(int(e.get("uid", -1))) if _world else null
			if u and is_instance_valid(u):
				mixer.play3d(String(e.get("path", "")), 1000, UnitSounds._at(u), 8.0, 40.0)
		"combat_flag":
			if game and game.session and int(e.get("p", -1)) == game.session.my_index:
				combat_flag = int(e.get("v", 0))
		"weather":
			if weather:
				weather.on_event(e, _ticks + _tick_acc / TICK)
		"tornado":
			if weather:
				weather.on_tornado(e, _ticks + _tick_acc / TICK)
		"fxcmd":
			_script_fx(String(e.get("f", "")), Array(e.get("a", [])))


## Script sound builtins (vm.gd broadcasts them as "fxcmd"):
## CreateFX(x, y, z, min, max, wav) →: a one-shot sound object
## (class 0x48, loop 0); CreateFXSource(id, x, y, z, min, max, wav) →
## a looping one (id −1 = the next free negative id)
## DeleteFXSource(id). Sound objects play with priority 0 (unset).
func _script_fx(f: String, a: Array) -> void:
	match f:
		"CreateFX":
			if a.size() >= 6:
				mixer.play3d(String(a[5]), 0, Vector3(float(a[0]), float(a[1]), float(a[2])), float(a[3]), float(a[4]))
		"CreateFXSource":
			if a.size() >= 7:
				var id := roundi(float(a[0]))
				if id < 0:
					id = _fx_auto
					_fx_auto -= 1
				mixer.stop(int(_fx_sources.get(id, -1)))
				_fx_sources[id] = mixer.play3d(String(a[6]), 0, Vector3(float(a[1]), float(a[2]), float(a[3])),
					float(a[4]), float(a[5]), true)
		"DeleteFXSource":
			if a.size() >= 1:
				var id := roundi(float(a[0]))
				mixer.stop(int(_fx_sources.get(id, -1)))
				_fx_sources.erase(id)


# ------------------------------------------------------------------ one-shots

## A UI sound: (wav, priority 1000, volume 100
## pan 0, no loop, no camera fade, category 0).
func ui(path: String) -> void:
	mixer.play2d(path, 1000, 100, 0)


## Unit voices and steps come from the animation clips (UnitSounds); these
## calls from GameUnit are kept as no-ops.
static func unit(_u: GameUnit, _kind: String) -> void:
	pass


static func step(_u: GameUnit) -> void:
	pass


## Spell sounds come from the "spellfx" / "magicfx" events (SpellSounds).
static func spell(_code: String, _at: Vector3, _phase: String) -> void:
	pass


## A sound object at a Godot-space point (levers:, min 8
## max 40, priority 1000).
static func at(path: String, pos: Vector3) -> void:
	if instance and path:
		instance.mixer.play3d(path, 1000, Vector3(pos.x, -pos.z, pos.y), 8.0, 40.0)


## Acknowledgement voice `code` (EIAcks) of `u` for its own player. The
## line is picked here (with its chance) and queued per unit
## pending lines that the new code supersedes
##  and finished ones leave the queue; with a
## line still pending only the ACK_URGENT codes are queued, others dropped.
## An empty queue plays the line at once, else it waits for its turn
## (counter 3 ticks once it is first). Playing is
## 2D, priority 1, volume 100, pan 0, speech category; the same
## line from the same unit is not repeated within 5000 ms. Codes 2 (attack)
## and 0x1c play only while the unit's attack sound is free and then take its
## place.
static func ack(u: GameUnit, code: int) -> void:
	if instance == null or u == null:
		return
	#  (client, ack message handler): a broken
	# armour / weapon (0x23 / 0x24) sounds "weapons\crash.wav", a critical one
	# (0x25 / 0x26, no lines) "weapons\timecrash.wav", at the unit: 3D,
	# priority 0, min 8 / max 20.
	if code == 0x23 or code == 0x24:
		instance.mixer.play3d("weapons\\crash.wav", 0, UnitSounds._at(u), 8.0, 20.0)
	elif code == 0x25 or code == 0x26:
		instance.mixer.play3d("weapons\\timecrash.wav", 0, UnitSounds._at(u), 8.0, 20.0)
		return
	var ls: Array = EIAcks.lines([u.proto.get("name", ""), u.proto.get("base_race", "")], code)
	if ls.is_empty():
		return
	var l: Dictionary = ls[randi() % ls.size()]
	if randf() * 100.0 >= float(l.chance):
		return
	var q: Array = instance._ack_q.get(u.uid, [])
	var drop: Array = ACK_REPLACES.get(code, [])
	q = q.filter(func(e): return not (int(e.code) in drop))
	q = q.filter(func(e): return int(e.handle) < 0 or instance.mixer.playing(int(e.handle)))
	if not q.is_empty() and not (code in ACK_URGENT):
		instance._ack_q[u.uid] = q
		return
	var e := {"u": u, "wav": String(l.wav), "code": code, "counter": 3, "handle": -1}
	if q.is_empty():
		e.counter = 0
		instance._ack_play(e)
	q.append(e)
	instance._ack_q[u.uid] = q


## each world tick: the first pending line counts down and
## plays at 0; once its counter is below 0 it leaves when its sound ends.
func _ack_tick() -> void:
	for uid in _ack_q.keys():
		var q: Array = _ack_q[uid]
		if q.is_empty() or not is_instance_valid(q[0].u):
			_ack_q.erase(uid)
			continue
		var e: Dictionary = q[0]
		e.counter = int(e.counter) - 1
		if int(e.counter) == 0:
			_ack_play(e)
		elif int(e.counter) < 0 and not mixer.playing(int(e.handle)):
			q.pop_front()


## Host: sends a hero's item crossing the durability-critical
## level as ack 0x25 (armour) / 0x26 (weapon)
## Session sends the broken ones (0x23 / 0x24).
func _on_item_worn(u: GameUnit, _item: String, kind: String) -> void:
	if is_instance_valid(u) and kind.begins_with("critical"):
		u.ack(0x26 if kind == "critical_weapon" else 0x25)


##  with the attack-channel rule of its callers.
func _ack_play(e: Dictionary) -> void:
	var u: GameUnit = e.u
	var code := int(e.code)
	if (code == 2 or code == 0x1c) and units and units.attack_playing(u):
		return
	var now := Time.get_ticks_msec()
	var last: Array = _acks.get(u.uid, ["", 0])
	if String(last[0]) == String(e.wav) and now - int(last[1]) < 5000:
		return
	e.handle = mixer.play2d(String(e.wav), 1, 100, 0, false, false, SoundMixer.CAT_SPEECH)
	_acks[u.uid] = [String(e.wav), now]
	if (code == 2 or code == 0x1c) and units:
		units.set_attack(u, int(e.handle))


## Host: a weapon blow's impact, sent to
## every peer as an "impact" event. `weapon` = a weapon blow (combat), else a
## spell or script damage (weapon type 7: no sound). Calls without a source
## (clients' health drops) do nothing: the event brings the sound.
static func impact(target: GameUnit, source: GameUnit = null, part := -1, amount := 0.0, weapon := false) -> void:
	if instance == null or target == null or source == null or not weapon or amount <= 0.0001:
		return
	var w := target.world
	if w == null or w.session == null:
		return
	var path := impact_path(target, source, part)
	if path:
		w.session.broadcast({"t": "impact", "uid": target.uid, "path": path})


## A missed blow of a character (unit, rolled when the strike starts)
## sounds "weapons\miss.wav" at the attack clip's sound frame: UnitSounds.


## The weapon type of a character's weapon in hand, −1 if none.
static func held_weapon_type(u: GameUnit) -> int:
	var ws: Array = u.get_meta("hero").get("weapons", []) if u.has_meta("hero") else Array(u.info.get("weapons", []))
	for id in ws:
		if String(id) == "":
			continue
		var it := Items.info(String(id))
		if it.table == "weapons":
			return int(it.row.get("type_id", -1))
		break
	return -1


## "weapons\<kind>\<material>\1.wav". The attacker's weapon type
## (victim): a character's weapon in hand, else its
## unarmed type (ai, taken as the prototype's weapon_type_id); for other
## units the prototype's byte (index). The material:
## the victim race's skin, or for a character the material type of the first
## armour worn in the struck part's slots: Crystal / Bone / Stone → "stone",
## Metal → "Metal", anything else → "leather".
static func impact_path(target: GameUnit, source: GameUnit, part: int) -> String:
	var wt := -1
	if int(source.race.get("type_id", 0)) == 0x32:
		wt = held_weapon_type(source)
		if wt < 0:
			wt = int(source.proto.get("weapon_type_id", 8))
	else:
		wt = natural_weapon_type(source)
	var kind := ""
	match wt:
		0, 1, 0xd: kind = "slash"
		2, 3, 5, 6, 10: kind = "pierce"
		4, 0xb: kind = "crash"
		9: kind = "hands1"
		0xc: kind = "hands4"
		0xe: kind = "hands6"
		0xf: kind = "hands7"
		_: return ""
	var mat := String(target.race.get("skin_type", "Leather"))
	if int(target.race.get("type_id", 0)) == 0x32:
		var found := ""
		if part >= 0 and part < HIT_SLOTS.size():
			var worn := {}
			var arm: Array = target.get_meta("hero").get("armors", []) if target.has_meta("hero") else Array(target.info.get("armors", []))
			for id in arm:
				var it := Items.info(String(id))
				if it.table == "armors" and not it.mat.is_empty():
					worn[int(it.row.get("type_id", -1))] = String(it.mat.get("type", ""))
			var slots: Array = HIT_SLOTS[part]
			for k in [2, 0, 1]:
				var sl := int(slots[k])
				if sl != 7 and worn.has(sl):
					found = worn[sl]
					break
		if found:
			mat = found
		if mat in ["Crystal", "Bone", "Stone"]:
			mat = "stone"
		elif mat != "Metal":
			mat = "leather"
	return "weapons\\%s\\%s\\1.wav" % [kind, mat]


## The prototype byte of a non-character attacker. Inferred (not
## traced): 9 + the index of the race's attack type (race_models "attack",
## one-hot over 7), mapping the 7 attack kinds onto the switch's codes 9..0xf
## (hands1, pierce, crash, hands4, slash, hands6, hands7; no race uses the
## 7th, whose folder sfx.res lacks).
static func natural_weapon_type(u: GameUnit) -> int:
	var a = u.race.get("attack", [])
	if not (a is Array or a is PackedFloat32Array) or a.is_empty():
		return -1
	var best := -1
	var bv := 0.0
	for i in a.size():
		if float(a[i]) > bv:
			bv = float(a[i])
			best = i
	return 9 + best if best >= 0 else -1


# ------------------------------------------------------------------ speech

## Phrase n of a briefing: speech.res
## "briefing\<id>\<n>.mp3", 2D, priority 256, volume 100, speech category;
## the previous phrase's voice stops first. False when it has no file.
func speech(brief: String, n: int) -> bool:
	stop_speech()
	var s := EIAudio.speech(brief, n)
	if s:
		_speech_h = mixer.play_stream2d(s, 256, 100, 0, SoundMixer.CAT_SPEECH)
	return s != null


func speaking() -> bool:
	return mixer.playing(_speech_h)


func stop_speech() -> void:
	mixer.stop(_speech_h)
	_speech_h = -1


# ------------------------------------------------------------------ music

## Script PlayMusic.
func force_music(name: String) -> void:
	name = name.to_lower().get_file().trim_suffix(".mp3")
	music.play_forced(name)
