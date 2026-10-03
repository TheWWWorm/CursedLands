class_name GameSound
extends Node
## All play-mode audio, played locally on every peer from replicated state and
## events, through SoundMixer (the original's 15-channel sound manager):
## ground ambience (AmbientSound), map and script sound objects, unit voices
## and steps from the animation (UnitSounds), weapon impacts, spells and magic
## effects (SpellSounds), acknowledgements, briefing voices, UI sounds and the
## music (MusicSystem). See.

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
var _early_music := ""
## Tests: print each acknowledgement's pick and outcome.
static var trace_acks := false
var _early_at := 0.0
var _early_world: GameWorld = null
var _bored := {}   # host: unit uid -> [idle counter (creature), gait]
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
## The global map is up (event "travel" until a zone starts or "Stay here").
var _on_map := false


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

## Attach before the new world's first physics event can reach the audio
## handlers. Waiting for _process can leave SpellSounds on the freed world.
func on_world(w: GameWorld) -> void:
	if w != _world:
		_zone_start(w)


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
	_bored.clear()
	_ticks = 0
	_tick_acc = 0.0
	combat_flag = 0
	_sent_flags.clear()
	_on_map = false
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
	if _zone_music(w):
		# A PlayMusic that reached this peer before the zone start (a client
		# gets the host's event, or a joiner its replay, in the frames between
		# the world's creation and this call) still applies.
		if _early_music != "" and _early_world == w:
			music.play_forced(_early_music, _early_at)
	_early_music = ""
	_update_listener()
	ambient = AmbientSound.new(mixer, w, dungeon)
	units = UnitSounds.new(mixer, w)
	# Remake: the zone's unit and ambient sounds decoded on a worker thread.
	EIAudio.prefetch(ambient.folders(w.session.state.world_time if w.session and w.session.state else 12.0)
		+ UnitSounds.zone_folders(w))
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


## The zone's music mode as at its load: a village (briefing
## zone) plays its Briefing track, any other zone gets
## SetZoneMode. True for the zone mode.
func _zone_music(w: GameWorld) -> bool:
	var dungeon := String(w.zone.get("sky", "")) == "cave"
	var allod := String(w.zone.get("allod", "gipat")).to_lower()
	if String(w.zone.get("id", "")) == Session.ENDING_ZONE or String(w.zone.get("mpr", "")) == Session.ENDING_ZONE:
		allod = "final"
	if allod.is_empty():
		allod = "gipat"
	if String(w.zone.get("type", "")) == "brief":
		music.allod = allod
		music.set_briefing()
		return false
	music.set_zone(allod, dungeon)
	return true


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
	on_world(w)
	if w == null or _on_map:
		# the original clears the world for the global map (
		# ): no world ticks, no combat flag, no zone music rules.
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
		_bored_tick()
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
	# One pass; only units with an attack / cast order can set a flag.
	var flags := {}
	for u: GameUnit in _world.units.values():
		if not is_instance_valid(u):
			continue
		if u.controller >= 0 and not flags.has(u.controller):
			flags[u.controller] = 0
		if u.dead:
			continue
		var ty = u.order.get("type")
		if ty != "attack" and ty != "cast":
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
		"travel":
			# The global map opens: no music
			# and the zone's combat state goes with the zone.
			on_world(game.world if game else null)
			_on_map = true
			combat_flag = 0
			music.set_none()
			# ... and no zone sound either (the original clears the world): every
			# sound stops, the loops wait for "Stay here" (SoundMixer.suspend).
			mixer.suspend()
			if MusicSystem.trace:
				print("music: global map, silence")
		"travel_close":
			# "Stay here" (remake-only; the original would load the zone again):
			# the zone's music mode as at a zone load, the combat flag sent
			# anew, the zone's loops start again.
			if _on_map and not e.has("go") and _world:
				_on_map = false
				combat_flag = 0
				_sent_flags.clear()
				_zone_music(_world)
				mixer.resume()
		"combat_flag":
			if _on_map:
				return
			if game and game.session and int(e.get("p", -1)) == game.session.my_index:
				combat_flag = int(e.get("v", 0))
				if MusicSystem.trace:
					print("music: combat flag %d (track '%s', mode %d, hold %s)" % [combat_flag, music._cur, music.mode, music.hold])
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
	# a named unit crawling or kneeling (unit
	#  < 2) answers quietly: its positive answers (0..5, 7..0xa) use
	# the 0x27 lines, its refusals (0xb..0x13, 0x1d) the 0x28 lines.
	if Combat.named(u) and u.stance != GameUnit.STANCE_NONE:
		if code in [0, 1, 2, 3, 4, 5, 7, 8, 9, 0xa]:
			code = EIAcks.SHOP_YES
		elif (code >= 0xb and code <= 0x13) or code == 0x1d:
			code = EIAcks.SHOP_NO
	var ls: Array = EIAcks.lines([u.info.get("voice", ""), u.proto.get("name", ""), u.proto.get("base_race", "")], code)
	var l := {}
	if code == EIAcks.BORED:
		# only while the figure's clip is a walk / run / idle one
		# the line
		#  with the context.
		if not (u.action in ["idle", "walk", "run", "crawl"]):
			return
		l = EIAcks.pick_masked(ls, instance.bored_context(u))
	else:
		# a random line among those whose chance ≥ rand % 100.
		l = EIAcks.pick(ls)
	if SoundMixer.trace or trace_acks:
		print("[ack] %s code 0x%x lines %d -> %s" % [u.display_name, code, ls.size(), l.get("wav", "-")])
	if l.is_empty():
		return
	instance._ack_queue(u, code, String(l.wav))


## the context a Bored line's mask must hold: the unit's gait
## (: crawl 8, kneel 4, walk 2, run 1), the allod (world: gipat
## 0x10, ingos 0x20, suslanger 0x40), the hour (: 6 ≤ h < 22
## 0x80, else 0x100), outdoors 0x200 / dungeon 0x400, and world
##  (1 0x800, 2 0x1000, else 0x2000; nothing writes it, so 0x2000).
func bored_context(u: GameUnit) -> int:
	var c: int = [8, 4, 2, 1, 0][clampi(u.gait(), 0, 4)]
	var allod := String(_world.zone.get("allod", "")).to_lower() if _world else ""
	c |= {"gipat": 0x10, "ingos": 0x20, "suslanger": 0x40}.get(allod, 0)
	var h: float = _world.session.state.world_time if _world and _world.session and _world.session.state else 12.0
	c |= 0x80 if h >= 6.0 and h < 22.0 else 0x100
	c |= 0x400 if _world and String(_world.zone.get("sky", "")) == "cave" else 0x200
	return c | 0x2000


## Host, every logic tick: the creature tick
## counts up for a unit with a player; past 500, one tick in 1001
## (table random % 1001 == 0) sends ack 0x29 when the player's combat flag
##  is 0 and sets 400, or else sets 0. The counter goes to 0 while
## the unit acts (when runs an order, same tick) and
## on a gait change. Approx.: "acts" = the remake unit is not
## idle (an order or a locked animation); the other reset, (net
## handler, unit), is not identified.
func _bored_tick() -> void:
	for u: GameUnit in _world.units.values():
		if not is_instance_valid(u) or u.dead or u.controller < 0 or not u.has_meta("hero"):
			continue
		var g := u.gait()
		var e: Array = _bored.get(u.uid, [0, g])
		if int(e[1]) != g:
			e = [0, g]
		e[0] = int(e[0]) + 1
		if int(e[0]) > 500 and randi() % 1001 == 0:
			if int(_sent_flags.get(u.controller, 0)) == 0:
				u.ack(EIAcks.BORED)
				e[0] = 400
			else:
				e[0] = 0
		if not u.is_idle():
			e[0] = 0
		_bored[u.uid] = e


## Script "say <id> <unit>" / "say_block <id> <unit>" (client string command
##  field screen = (unit, 0x2a / 0x2b)
## ): the unit's Scenario line with that id goes into its
## acknowledgement queue as code 0x2a (queued even behind a pending line),
## "say_block" as 0x2b (dropped while a line is pending; while it plays the
## unit takes no orders, unit flag). Returns the line ({} = none).
static func say(u: GameUnit, id: String, block: bool) -> Dictionary:
	if instance == null or u == null:
		return {}
	# The record is named by the unit's prototype entry (: unit
	#  in the 0x120-byte table) — "Human Hero" for Zak, but
	# "Cyclope", "Liz4", "GTDragon"… for map NPCs with their own stats, whose
	# acks.db records carry the unit's map name. Approx.: that entry's
	# naming is not traced; the prototype name is tried, then the map name.
	var l := EIAcks.scenario_line([u.proto.get("name", ""), u.info.get("name", "")], id)
	if SoundMixer.trace:
		print("[say] %s %s block %s -> %s (world tick %d)" % [u.display_name, id, block, l.get("wav", "-"), instance._ticks])
	if not l.is_empty():
		instance._ack_queue(u, 0x2b if block else EIAcks.SCENARIO, String(l.wav))
	return l


## pending lines that the new code supersedes
## and finished ones leave the queue; with a line still
## pending only the ACK_URGENT codes are queued, others dropped. An empty
## queue plays the line at once, else it waits for its turn (counter 3 ticks
## once it is first). A "say_block" line (0x2b) blocks the
## unit's orders from the moment it is queued first until it ends.
func _ack_queue(u: GameUnit, code: int, wav: String) -> void:
	var q: Array = _ack_q.get(u.uid, [])
	var drop: Array = ACK_REPLACES.get(code, [])
	q = q.filter(func(e): return not (int(e.code) in drop))
	# a finished say_block line clears the flag as it leaves.
	for e in q:
		if bool(e.block) and int(e.handle) >= 0 and not mixer.playing(int(e.handle)):
			u.blocked = false
	q = q.filter(func(e): return int(e.handle) < 0 or mixer.playing(int(e.handle)))
	if not q.is_empty() and not (code in ACK_URGENT):
		_ack_q[u.uid] = q
		if SoundMixer.trace or trace_acks:
			print("[ack] %s 0x%x dropped: a line is pending" % [u.display_name, code])
		return
	var e := {"u": u, "wav": wav, "code": code, "counter": 3, "handle": -1, "block": code == 0x2b}
	if q.is_empty():
		e.counter = 0
		if e.block:
			u.blocked = true
		_ack_play(e)
	q.append(e)
	_ack_q[u.uid] = q


## Unit flag (GameUnit.blocked: a say_block line or script
## BlockUnit): the order handlers (
## ) and the topic list skip the unit.
static func blocked(u: GameUnit) -> bool:
	return u != null and is_instance_valid(u) and u.blocked


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
			if e.block:
				e.u.blocked = true
			_ack_play(e)
		elif int(e.counter) < 0 and not mixer.playing(int(e.handle)):
			# The flag goes with the line, whoever set it (one bit).
			if e.block:
				e.u.blocked = false
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
		if trace_acks:
			print("[ack] %s 0x%x %s skipped: attack sound playing" % [u.display_name, code, e.wav])
		return
	var now := Time.get_ticks_msec()
	var last: Array = _acks.get(u.uid, ["", 0])
	if String(last[0]) == String(e.wav) and now - int(last[1]) < 5000:
		if trace_acks:
			print("[ack] %s 0x%x %s skipped: said within 5 s" % [u.display_name, code, e.wav])
		return
	e.handle = mixer.play2d(String(e.wav), 1, 100, 0, false, false, SoundMixer.CAT_SPEECH)
	if trace_acks:
		print("[ack] %s 0x%x plays %s (handle %d)" % [u.display_name, code, e.wav, int(e.handle)])
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
func force_music(name: String, at := 0.0) -> void:
	name = name.to_lower().get_file().trim_suffix(".mp3")
	var w := game.world if game else null
	if w != _world:
		_early_music = name
		_early_at = at
		_early_world = w
		return
	music.play_forced(name, at)
