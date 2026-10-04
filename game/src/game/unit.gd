class_name GameUnit
extends Node3D
## A creature/character in the world. Simulation runs in EI coordinates (xy plane,
## z up) at a fixed tick on the host; clients only receive snapshots.

signal died(unit: GameUnit)

## Models face EI -Y at rest; facing angle 0 means looking along EI +X.
const MODEL_YAW_OFFSET := PI * 0.5
const TURN_SPEED := 9.0         # rad/s
const TICK := 0.055            # the original logic tick, seconds (= 55 ms)
## Path node speeds are in 0.5 m AI cells per logic tick (: one
## tick advances v cells), so a speed value v is v x 0.5 / TICK metres per second.
const SPEED_SCALE := 0.5 / TICK
const ARRIVE := 0.15

var world: GameWorld
var uid := 0
var info := {}          # map record (EIMob object) or synthetic spawn data
var proto := {}         # monster_prototypes row
var race := {}          # race_models row
var faction := 0        # diplomacy index (OBJ_PLAYER)
var controller := -1    # player index controlling this unit, -1 = AI
var display_name := ""

## Setting it keeps the unit's spatial bucket (NavGrid.rebucket) exact, so
## nearby-unit queries see a unit moved outside its own tick (scripts,
## teleports, snapshots, placement) at once, as a scan of every unit would.
var pos := Vector2.ZERO:
	set(v):
		pos = v
		if _seq != 0:
			world.nav.rebucket(self)
## Order of registration in GameWorld.units (0 = not in it): nearby-unit
## queries return units in this order, the order of a scan of `units`.
var _seq := 0
## Co-op client: where the unit is drawn between the host's snapshots.
var net_view := NetSmooth.new()
var facing := 0.0
var model: EIUnitModel

# --- stats
## Health is kept per body part as in the original (see _init_parts); `hp` is derived.
var hp: float:
	get: return _get_hp()
	set(v): _set_hp(v)
## Base maximum (prototype / skills); the effective maximum also carries the
## strength / weakness effects (: x (1 + 0.005 s) / (1 + 0.005 w)).
var max_hp: float:
	get: return _max_hp
	set(v):
		_base_max_hp = v
		_set_max_hp(v * _hp_mul())
var _base_max_hp := 10.0
var _hp := 10.0
var _max_hp := 10.0
## head, torso, right arm, left arm, right leg, left leg (race_models columns):
## {type: 0 skull / 1 torso / 2 arm / 3 leg, size, lethal, cur, max, state:
## 0 absent / 1 severed / 2 destroyed / 3 intact}.
var parts: Array[Dictionary] = []
var mana := 0.0
var max_mana := 0.0
var stats := {}         # to_hit, parry, dmg_min, dmg_max, absorption, reach, attack_time
var dead := false
var hidden := false
var fogged := false   # out of this player's sight (UnitFog, client-side only)

# --- orders
var orders: Array[Dictionary] = []
var order := {}
var path := PackedVector2Array()
var running := true
## Gait run, the original unit == 3 (0 crawl, 1 kneel, 2 walk, 3 run; the
## crawl / kneel values are `stance`). Per unit: the HUD dial and keys send it
## for each selected unit (net message 0x35). A new unit walks
## (= 2); it is part of the unit's save record
## . Every command tick a party
## unit runs when it stands and its gait is run, or its order has the
## double-click run flag (command); a unit outside a party also runs
## while its combat flag is set.
var gait_run := false
var _regen_t := 0.0
## Stealth stance (original movement modes: run / walk / sneak on knees / crawl).
const STANCE_NONE := 0
const STANCE_KNEEL := 1
const STANCE_CRAWL := 2
var stance := STANCE_NONE
var sneaking: bool:
	get: return stance != STANCE_NONE
var mode := "standard"      # AI mode: standard / sentry / guard / follow / fear / aggression / player
## Player units' Aggressive (true) / Defensive (false) mode: the original unit
## 1 by default, set; read by the Player
## motivation (UnitAI.think). Toggled from the HUD dial / keyboard "swarm".
var aggressive := true
var mode_data := {}
var target: GameUnit
var strike_aim := -1        # aimed part of the last strike (the original order)
## The strike in progress misses (unit, set with the strike's animation
## command): its clip sounds "weapons\miss.wav"
## at the sound frame (UnitSounds). Sent to clients in the snapshot (bit 24).
var strike_miss := false
var _attack_cd := 0.0
var _repath := 0.0
var _anim_lock := 0.0
var _pending_hit := {}
var _step_dist := 0.0
var _last_pos := Vector2.ZERO
var action := "idle"        # replicated visual state
## Combat stance (the original unit): set by an attack command
## (command 3). Humans then stand, walk and idle in the
## combat clips instead of the relaxed ones.
## run on every command tick: command 3 (attack) sets it, any
## other command clears it for a party unit (unit, the party, set)
## units outside a party keep it once set.
var alert := false
var ai_next := 0.0      # world time of the unit's next AI tick (UnitAI)
var _perceive_next := 0.0   # next noticed-list update of a Player-motivation unit
var order_failed := false   # the last order ended unsuccessfully (creature)
var limp := 0               # walk modifier 0-2 (replicated to clients, which have no body parts)
## Unit flag (unit +8): set / cleared by script BlockUnit and by a
## "say_block" line (GameSound), read by IsUnitBlocked; player orders skip the
## unit, script
## orders and the AI do not look at it. Not saved (clears it on load).
var blocked := false
## The Rest order (the original order 0xb, case 0xb sets
## the posture to 4, whose animation state is rest 0x8000):
## a calm glance with the rest flag (UnitAI._calm_busy). Any next order ends it.
var resting := false:
	set(v):
		if v != resting:
			resting = v
			_pose_dirty = true
var buffs := {}             # name -> {until, dmg_mul?, hp_mul?, actions_add?, regen_mul?, no_cast?, detect?, sense?, resist?, armor?}

# --- body and movement (the original unit radius; NavGrid stamps)
## 0.9 x the larger horizontal half-extent of the figure's bounding box
## (over figure, set).
var figure_radius := 0.5
## Half the figure's z extent (figure; idle pose).
var figure_half_z := 0.9
## Movement classes crawling / kneeling / standing (figure).
var _classes := [1, 2, 3]
var _moving := false        # stepped this tick (the original)
var _occ_cell := Vector2i(-1, -1)
var _occ_r := 0.0
var _bucket := -1
var _abucket := -1          # NavGrid._all_buckets key (dead units too)
var _cbucket := -1          # NavGrid._cbuckets / _call_buckets keys (16 m grid)
var _cabucket := -1
var _trk_pos := Vector2.INF  # NavGrid.track_unit's last call: position, (_seq, dead, standing), radius
var _trk_key := -1
var _trk_r := 0.0
var _avoid: GameUnit         # slower mover to path round
var _fresh_path := false     # a path planned round a blocker (_avoid), no step taken on it yet
var _arrive_t := 0.0         # estimated arrival at the attack target (unit-AI)
var _goal := Vector2.INF     # where the current attack path leads (unit-AI)
var _follow_n := 0           # Follow check counter (AI; 0 at AI init)

# --- animation level of detail (remake rendering only, no game state)
## Units standing still out of view advance their animation in steps of this
## many seconds instead of every frame (the pose is only seen on screen; clip
## lengths, not playback, drive the simulation). Posing a few hundred units
## every frame cost more than everything else in a 200+ unit zone.
const ANIM_OFFSCREEN_STEP := 0.2
## On screen but farther than ANIM_NEAR metres from the camera: 30 poses a
## second (the clips have 18.2 keys a second); only the shadow reach in view:
## 20 a second.
const ANIM_NEAR := 70.0
const ANIM_FAR_STEP := 1.0 / 30.0
const ANIM_SHADOW_STEP := 1.0 / 20.0
## Walking out of view and beyond the unit sounds' reach (UnitSounds.MAX_D
## + 8 m from the listener): 10 poses a second. Its footprints are still
## placed at the clips' step frames, from the pose up to 0.1 s later (the
## planted foot has hardly moved); nearer, steps and voices keep exact timing.
const ANIM_FAR_MOVE_STEP := 0.1
const ANIM_HEAR := UnitSounds.MAX_D + 8.0
var _body: VisibleOnScreenNotifier3D
var _screen: VisibleOnScreenNotifier3D
static var _headless := DisplayServer.get_name() == "headless"
var _wounds_dirty := true   # part health / armour / figure changed (UnitWounds)
var _pose_dirty := true     # part health / figure changed (_set_action's idle skip)
var _idle_key := []
var _anim_acc := 0.0
var _anim_due := 0.0
## The figure's animation runs on the game clock (the physics steps that move
## the unit and count its _anim_lock), not on the frame clock: when frames
## take longer than the engine catches up with (max_physics_steps_per_frame),
## the game runs slower than real time, and a clip played by frame time ended
## on screen while its lock still held the unit's orders (the web build's
## first zone: Zak stood up, then ignored orders for many seconds).
var _game_clock := 0.0
var _anim_clock := -1.0
## The cast clip's hold (_cast_anim): clip "ei/<name>", stopped at _hold_pos
## seconds into it for _hold_left more seconds of game time; a flier's cast
## clip waits _pre_left seconds instead.
var _hold_clip := ""
var _hold_pos := 0.0
var _hold_left := 0.0
var _pre_left := 0.0
var _pre_clip := ""
var _anim_pos := Vector2.INF
var _anim_moving := 0.0
## Ground speed (m/s) over the last physics step, of the drawn position on a
## co-op client: the walk / run clips' playback rate follows it (_anim_rate).
var _move_speed := 0.0
var _speed_from := Vector2.INF
var _drawn := Vector2.ZERO
## Shown in the unit panel, whose figure mirrors this pose: full animation rate.
var anim_watched := false
var _anim_roots: Array[EIAnimPart] = []
## Render layer of out-of-view figures; the sun's shadow_caster_mask leaves it out.
const OFFSCREEN_LAYER := 1 << 19
var _geoms: Array[GeometryInstance3D] = []
var _far := false


func setup(w: GameWorld, record: Dictionary) -> bool:
	world = w
	info = record
	uid = int(record.get("nid", 0))
	var db := GameData.db
	proto = db.find("monster_prototypes", record.get("prototype", record.get("parent_template", "")))
	race = db.find("race_models", proto.get("base_race", ""))
	# an imported.mob record's own stats over the prototype's.
	var imported: Variant = Combat.mob_import(record, proto, race)
	if imported != null:
		proto = imported[0]
		race = imported[1]
	faction = int(record.get("player", 1))
	display_name = unit_title(String(proto.get("name", "")))
	if display_name.is_empty():
		display_name = String(record.get("name", proto.get("name", "unit")))
	var p: Vector3 = record.get("position", Vector3.ZERO)
	pos = Vector2(p.x, p.y)
	var q: Quaternion = record.get("rotation", Quaternion.IDENTITY)
	facing = q.get_euler().y - MODEL_YAW_OFFSET
	model = EIUnitModel.create(record)
	if model == null:
		return false
	add_child(model)
	# Physics interpolation (option phys_interp): the unit node moves on the
	# physics step and is drawn interpolated; its figure is posed every frame
	# in _process, so it is not interpolated itself (drawn under the unit's
	# interpolated transform).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Measured in the idle pose (Approx.: the pose of the original's box is not known
	# the rest pose holds the arms out).
	model.act("idle", 1, 0.0)
	if model.player:
		model.player.advance(0.0)
	_measure_figure()
	_anim_lod_setup()
	_init_stats()
	Combat.mob_import_pools(self)
	name = ("U%d" % uid)
	_sync_transform()
	visibility_changed.connect(_on_visibility_changed)
	return true


## The figure's box (figure..) and what the original
## derives from it: the radius (: 0.9 x the larger horizontal
## half-extent) and the three movement classes. A character
## (race type 0x32) gets the horizontal half-extents 0.5 / 0.5 whatever its
## parts, so its radius is 0.45. Approx.: the box is measured
## over the meshes in the idle pose (the original sums the parts' boxes and offsets
## as loaded; the pose is not known; the rest pose holds the arms out).
func _measure_figure() -> void:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.visible:
			continue
		var b := NavGrid._local_xf(mi, model) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var character := int(race.get("type_id", 0)) == 0x32
	if character:
		figure_radius = 0.45
	else:
		figure_radius = 0.5 if first else maxf(box.size.x, box.size.z) * 0.5 * 0.9
	# width = |(x, y)| of the max corner of the "bd" (else
	# "chest") part's box, x 2 for the spider (type 0x33
	# "unmosp"); height = the figure box's height x race field 0x2e (
	# the database's "head_height"), at most 1.89 for characters.
	var width := 0.0
	var part: Node3D = model.find_child("bd", true, false)
	if part == null:
		part = model.find_child("chest", true, false)
	if part:
		var pb := AABB()
		var pfirst := true
		for mi: MeshInstance3D in part.find_children("*", "MeshInstance3D", false, false):
			if mi.mesh == null:
				continue
			var b := mi.transform * mi.mesh.get_aabb()
			pb = b if pfirst else pb.merge(b)
			pfirst = false
		if not pfirst:
			# EI x = Godot x, EI y = -Godot z: the max corner is (end.x, -position.z).
			width = Vector2(pb.end.x, -pb.position.z).length()
			if int(race.get("type_id", 0)) == 0x33 and model.template.to_lower() == "unmosp":
				width *= 2.0
	figure_half_z = box.size.y * 0.5 if not first else 0.9
	var height := (box.size.y if not first else 1.8) * float(race.get("head_height", 1.0))
	if character:
		height = minf(height, 1.89)
	_classes = [_class_of(width, height * 0.2), _class_of(width, height * 0.6), _class_of(width, height)]


## Movement class of a body: width <= 0.85: height < 0.6 -> 1
## < 1.2 -> 2, < 1.9 -> 3, else 4; width <= 1.5: height <= 1.7 -> 5, else 6;
## wider 7.
static func _class_of(width: float, height: float) -> int:
	if width > 1.5:
		return 7
	if width > 0.85:
		return 5 if height <= 1.7 else 6
	if height < 0.6:
		return 1
	if height < 1.2:
		return 2
	return 3 if height < 1.9 else 4


## The unit's movement class, unit: by posture
## the crawling, kneeling or standing class of its
## figure. The class picks the nav grid (NavGrid.layer).
func move_class() -> int:
	return _classes[0] if stance == STANCE_CRAWL else (_classes[1] if stance == STANCE_KNEEL else _classes[2])


## The order's target unit, null once it was freed (a typed read of a freed
## instance is an error).
func _order_target() -> GameUnit:
	var t = order.get("target")
	return t if is_instance_valid(t) and t is GameUnit else null


## Body radius, the original unit: the figure radius, + 0.2
## for a player's unit (set), at most 2. Units keep the centres
## others this far plus their own radius apart (NavGrid.step_blocker).
func body_radius() -> float:
	return minf(2.0, figure_radius + (0.2 if controller >= 0 else 0.0))


## Melee striking distance to `t`, centre to centre in the ground plane
## (attack orders): both radii + max(weapon range, 0.6), the
## floor 0.2 between two player units. The weapon range is the item's (all
## melee weapons 0); unarmed the creature's, which is
## the prototype's field 14 "attack range" (copied to stats block
## the block sits):
## 0 for the melee monsters, so their floor 0.6 applies.
func melee_reach(t: GameUnit) -> float:
	var floor_ := 0.2 if controller >= 0 and t.controller >= 0 else 0.6
	return body_radius() + t.body_radius() + maxf(float(stats.get("range", 0.0)), floor_)


## Player-facing name of a prototype from texts.res ("unit human_gipath_npc_elder_f1").
static func unit_title(proto_name: String) -> String:
	if proto_name.is_empty():
		return ""
	var t := GameData.text("unit " + proto_name.to_lower().replace(" ", "_"))
	return t.get_slice("\n", 0).strip_edges()


## A prototype's body build in the remake's (fat, muscle, height) order:
## monster_prototypes stores (muscle, fat, height) — the original puts
## fields 5 / 6 / 7 copies them to the
## figure's (muscle) / (fat) / (height).
static func proto_complexion(proto: Dictionary) -> Vector3:
	return Vector3(float(proto.get("complexion_y", 0.5)), float(proto.get("complexion_x", 0.5)),
		float(proto.get("complexion_z", 0.5)))


func _init_stats() -> void:
	_max_hp = maxf(1.0, float(proto.get("hp", 10.0)))
	_base_max_hp = _max_hp
	_hp = _max_hp
	_init_parts()
	max_mana = float(proto.get("mana", 0.0))
	mana = max_mana
	stats = {
		"to_hit": float(proto.get("to_hit", 5.0)),
		"parry": float(proto.get("parry", 5.0)),
		# units.udb "damage max" is a range: the original rolls min + random(0..range).
		"dmg_min": float(proto.get("damage_min", 1.0)),
		"dmg_max": float(proto.get("damage_min", 1.0)) + float(proto.get("damage_max", 1.0)),
		# "Tuning To hit Random" (40 in every prototype): spread of the attack roll.
		"hit_random": float(proto.get("random_hit", 40.0)),
		"absorption": float(proto.get("absorption", 0.0)),
		# the original: natural armour per damage type = prototype
		# "absorbtion" x race "def <type>"; attack types = race "atk <type>".
		"armor": race_factors("defence", float(proto.get("absorption", 0.0))),
		"dmg_types": race_factors("attack", 1.0),
		"part_armor": {},
		"reach": maxf(float(race.get("attack_distance", 0.4)) + 0.9, float(proto.get("attack_range", 0.0))),
		# Melee weapon / natural range (see melee_reach): prototype "attack range".
		"range": float(proto.get("attack_range", 0.0)),
		"sight": float((proto.get("senses", [15.0]) as Array)[0]) if proto.has("senses") else 15.0,
		# Archers and casters of the monster tables shoot from their attack range.
		"ranged": float(proto.get("attack_range", 0.0)) > 3.0,
	}


# ------------------------------------------------------------------ body parts
# the original keeps six body parts per unit (stats, 0xf4 bytes each). From
# race_models "<part>" = [hit location, -, size, lethality]:
#   part max HP = unit max x size / torso size
#   unit HP = max - sum(max x lethality x damage fraction), fraction capped at 1
# so a destroyed head or torso (lethality 1.01) kills
#   healing is spread over damaged parts by lethality.

## the original numbering: 0 head, 1 body, 2 left arm, 3 right arm, 4 left leg
## 5 right leg (hit-effect node per part: hd, bd, lh2, rh2
## ll2, rl2; the wound codes hd bd lh rh ll rl).
const PART_KEYS := ["head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"]
const PART_TYPES := {"skull": 0, "torso": 1, "arm": 2, "leg": 3}
## Random hit location of a strike: 20 slots, head 2, torso 6
## every limb 3.
const HIT_TABLE := [0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5]


func _init_parts() -> void:
	parts.clear()
	_limbs.clear()
	var torso: Array = Array(race.get("torso", []))
	if torso.size() < 4 or float(torso[2]) <= 0.0:
		return
	for k: String in PART_KEYS:
		var r: Array = Array(race.get(k, []))
		var size := float(r[2]) if r.size() >= 4 else 0.0
		var t: int = PART_TYPES.get(String(r[0]) if r.size() else "none", -1)
		var m := _max_hp * size / float(torso[2])
		parts.append({"type": t, "size": size, "lethal": float(r[3]) if r.size() >= 4 else 0.0,
			"sever": int(r[1]) if r.size() >= 4 else 0,
			"cur": m, "max": m, "state": 3 if size > 0.0 and t >= 0 else 0})


func _part_frac(p: Dictionary) -> float:
	if p.cur < 0.0:
		return 1.0
	return (p.max - p.cur) / p.max


func _get_hp() -> float:
	if parts.is_empty():
		return _hp
	var lost := 0.0
	for p in parts:
		if p.state > 0:
			lost += _max_hp * p.lethal * _part_frac(p)
	return _max_hp - lost


func _set_hp(v: float) -> void:
	if parts.is_empty():
		_hp = v
		return
	var d := v - _get_hp()
	if d < 0.0:
		body_damage(-d)
		return
	# One heal pass caps parts that fill up; repeat until the value is reached.
	for i in 8:
		if d <= 0.0001:
			break
		heal(d)
		d = v - _get_hp()


func _set_max_hp(v: float) -> void:
	# part maxima follow the unit maximum, current values keep
	# their ratio.
	var old := _max_hp
	_max_hp = v
	if parts.is_empty():
		return
	var torso_size: float = parts[1].size
	for p in parts:
		if p.state > 0:
			var m: float = v * p.size / torso_size
			p.cur = minf(p.cur * m / p.max, m) if p.max > 0.0 else m
			p.max = m
	_wounds_dirty = true
	_pose_dirty = true
	if old <= 0.0:
		restore_parts()


func _hp_mul() -> float:
	var m := float(get_meta("coop_hp_mul", 1.0))   # remake co-op MobScaling
	for b in buffs.values():
		m *= float(b.get("hp_mul", 1.0))
	return m


## Re-applies the strength / weakness HP factor after buffs change.
func refresh_max_hp() -> void:
	var m := _base_max_hp * _hp_mul()
	if not is_equal_approx(m, _max_hp):
		_set_max_hp(m)


## health spread over the damaged, attached parts by lethality
## destroyed parts that climb above 0 work again.
func heal(amount: float) -> void:
	if parts.is_empty():
		_hp = minf(_max_hp, _hp + amount)
		return
	var w := 0.0
	for p in parts:
		if p.state > 1 and p.cur < p.max:
			w += p.lethal
	if w <= 0.0:
		return
	for p in parts:
		if p.state > 1 and p.cur < p.max:
			p.cur = minf(p.max, p.cur + amount / (w * _max_hp) * p.max)
			_wounds_dirty = true
			_pose_dirty = true
			if p.cur >= 0.001:
				p.state = 3


##  (respawn / resurrection): every attached part intact and full.
func restore_parts() -> void:
	for p in parts:
		if p.state > 0:
			p.state = 3
			p.cur = p.max
	_wounds_dirty = true
	_pose_dirty = true
	_show_severed(0)


## Bit i set = body part i severed.
func severed_mask() -> int:
	var m := 0
	for i in parts.size():
		if parts[i].state == 1:
			m |= 1 << i
	return m


## Model part chains of head, torso, left / right arm, left / right leg
## (part order above; node list hd / bd / lh1–3 / rh1–3
## ll1–3 / rl1–3).
const SEVER_NODES := ["hd", "", "lh1", "rh1", "ll1", "rl1"]
var _severed_shown := 0
var _severed_want := 0

## Severed limbs on the model. the original keeps a severed part on the figure:
## no client code reads the part state to hide or remove a node (the figure's
## part add / remove serve armour and weapons
## only), there is no limb object, and figures.res has no limb meshes. At the
## blow the client shows what any big health drop shows:
##  blood (its intensity, the part's health-fraction drop
## clamped to 1 since the part falls to −5 × max), the impact sound and the
## ground blood mark, and the part takes wound level 3 (
## fraction ≤ 1 / max). See.md "Severed limbs".
## Remake option gfx_severed_limbs (default on): the chain is hidden and,
## when it happens in view (`fly`), a copy of it is thrown off
## (`SeveredLimb`); off = the original. `mask` is the true severed mask.
func _show_severed(mask: int, fly := false) -> void:
	_severed_want = mask
	if mask != 0:
		add_to_group(&"severed_units")
	elif is_in_group(&"severed_units"):
		remove_from_group(&"severed_units")
	var show := mask if Gfx.on("gfx_severed_limbs") else 0
	if show == _severed_shown or model == null:
		return
	var added := show & ~_severed_shown
	_severed_shown = show
	for i in SEVER_NODES.size():
		if SEVER_NODES[i] == "":
			continue
		if fly and added & (1 << i) and visible and is_inside_tree():
			SeveredLimb.throw(self, SEVER_NODES[i])
		model.set_part_visible(SEVER_NODES[i], not (show & (1 << i)))


## Option gfx_severed_limbs switched (Gfx.apply): show or restore the chains.
func refresh_severed() -> void:
	_show_severed(_severed_want)


## Host: the unit's player hears it say ack `code` (acks.db
## speaks for heroes only). The path failures follow: NoWayAtt
## for an attack order, NoPath for the others.
func ack(code: int) -> void:
	if has_meta("hero") and controller >= 0 and world and world.session:
		world.session.broadcast({"t": "ack", "uid": uid, "to": controller, "code": code})


## Damage to one part. The part is severed when one damage
## type alone reaches the part's maximum and the race lets that type sever it
## (bit t of the part's "sever" mask, race_models part field 2), or when its
## health falls below -5 x max; at 0 it is destroyed. A hero losing an arm or a
## leg says so (ack 0x1e / 0x1f).
func _hurt_part(i: int, dmg: float, types := PackedFloat32Array()) -> void:
	var p: Dictionary = parts[i]
	if p.state < 2:
		return
	p.cur -= dmg
	_wounds_dirty = true
	_pose_dirty = true
	var sever: bool = p.cur < -5.0 * p.max
	for t in types.size():
		if types[t] >= p.max and int(p.get("sever", 0)) & (1 << t):
			sever = true
	if sever:
		p.state = 1
		p.cur = -5.0 * p.max
		_show_severed(severed_mask(), true)
		if p.type in [2, 3]:
			ack(EIAcks.ARM_CRIPPLED if p.type == 2 else EIAcks.LEG_CRIPPLED)
	elif p.cur <= 0.0:
		p.state = 2


## Whole-body damage (spells, scripts; part 6): split over the
## attached parts so the unit loses `amount` health.
## `layers` (optional, spells: on each part's share) maps
## (part index, amount) to the amount left after that part's worn layers.
func body_damage(amount: float, layers := Callable()) -> void:
	if parts.is_empty():
		_hp -= amount
		return
	var w := 0.0
	for p in parts:
		if p.state > 1:
			w += p.lethal
	if w <= 0.0:
		return
	for i in parts.size():
		if parts[i].state > 1:
			var a := amount if not layers.is_valid() else float(layers.call(i, amount))
			if a > 0.0:
				_hurt_part(i, a / (w * _max_hp) * parts[i].max)


## The part a strike lands on: the aimed part (called shot, 0..5) or a random
## one from HIT_TABLE, moved to an intact neighbour when it is gone.
func hit_part(aim := -1) -> int:
	if parts.is_empty():
		return 1
	var want: int = aim if aim >= 0 and aim < 6 else HIT_TABLE[randi() % HIT_TABLE.size()]
	if parts[want].state == 3:
		return want
	var near: Array = {0: [1, 2, 3], 1: [0, 2, 3, 4, 5], 2: [3, 1], 3: [2, 1], 4: [5, 1], 5: [4, 1]}[want]
	for j: int in near:
		if parts[j].state == 3:
			return j
	var alive := []
	for j in 6:
		if parts[j].state == 3:
			alive.append(j)
	return alive[randi() % alive.size()] if alive else 1


## Body-part group used for armour (Combat.PART_SLOTS) of part index i.
func part_group(i: int) -> String:
	return ["head", "torso", "arms", "arms", "legs", "legs"][clampi(i, 0, 5)]


## Wound factor of the worst limb of a type (legs = 3
##  arms = 2): ratio <= DamageLevel2 -> DamageLevel2Value
## <= DamageLevel1 -> DamageLevel1Value, else 1 (ai.reg [RPG]).
## (Remake speed: it runs for every unit several times a physics step, so
## the parts of each type and the ai.reg levels are looked up once.)
func wound_factor(type: int) -> float:
	var r := 1.0
	for p: Dictionary in _limbs_of(type):
		if p.state != 0 and p.cur != p.max:
			r = minf(r, p.cur / p.max)
	var lv := _wound_levels()
	if r <= lv[0]:
		return lv[1]
	if r <= lv[2]:
		return lv[3]
	return 1.0


var _limbs := {}   # part type -> its part dictionaries (wound_factor; reset by _init_parts)


## The parts of one type in `parts` order (remembered until _init_parts).
func _limbs_of(type: int) -> Array:
	var of_type = _limbs.get(type)
	if of_type == null:
		of_type = []
		for p in parts:
			if p.type == type:
				of_type.append(p)
		_limbs[type] = of_type
	return of_type

static var _wl_reg := {}
static var _wl := PackedFloat64Array()


## ai.reg [RPG] DamageLevel2, DamageLevel2Value, DamageLevel1, DamageLevel1Value,
## DamageLevelRunLimit
## (re-read when GameData loads another ai.reg).
static func _wound_levels() -> PackedFloat64Array:
	if _wl.is_empty() or not is_same(_wl_reg, GameData.ai_reg):
		_wl_reg = GameData.ai_reg
		_wl = PackedFloat64Array([GameData.ai_value("RPG", "DamageLevel2", 0.0),
			GameData.ai_value("RPG", "DamageLevel2Value", 0.33), GameData.ai_value("RPG", "DamageLevel1", 0.5),
			GameData.ai_value("RPG", "DamageLevel1Value", 0.5),
			GameData.ai_value("RPG", "DamageLevelRunLimit", 0.5)])
	return _wl


## Worst leg ratio (blocks running below DamageLevelRunLimit).
func _legs_ratio() -> float:
	var r := 1.0
	for p: Dictionary in _limbs_of(3):
		if p.state != 0:
			r = minf(r, p.cur / p.max)
	return r


# ------------------------------------------------------------------ orders API

func command(o: Dictionary, queue := false) -> void:
	if dead:
		return
	if not queue:
		_keep_path(o)
		orders.clear()
		order = {}
		path = PackedVector2Array()
	if o.get("type", "") != "wait":
		order_failed = false   # cleared by a new order
	orders.append(o)


## The current order ends unsuccessfully: creature = 1 with the
## unit's ack (0xb no way to attack, 0xe no path, 0x11, 0x12;
## ). An AI cast ending so leaves its target out
## of the AI's choices for 15 ticks (state 4
## (target, 0xf)).
func _fail_order(code: int) -> void:
	var was := order
	order = {}
	order_failed = true
	ack(code)
	if controller < 0 and was.get("type", "") == "cast" and was.get("ai", false):
		var t = was.get("target")
		if t is GameUnit and is_instance_valid(t):
			world.ai.ignore(self, t, 0xf)


func move_to(p: Vector2, run := true, queue := false) -> void:
	command({"type": "move", "to": p, "run": run}, queue)


## `aim` = body part for an aimed strike (0 head .. 5 left leg), -1 = random.
## `run`: the double-click flag (see Session._double_stand).
func attack(t: GameUnit, queue := false, aim := -1, run := false) -> void:
	command({"type": "attack", "target": t, "aim": aim, "run": run}, queue)


func is_idle() -> bool:
	return order.is_empty() and orders.is_empty() and _anim_lock <= 0.0


## Metres per second (moves along the path spline at the node
## speeds): base x the step's terrain factor.
## base (unit) = speed byte of the posture (: run
## walk, kneel, crawl) x 2/255 x factor byte
##  25.5, the bytes packed (race speed x 255/2
## tuning_move x the legs' wound factor x 25.5). The terrain
## factor: NavGrid.step_factor into the next cell. No spell
## enters it. Approx.: sampled each frame from the unit's cell to the next
## along its heading (the original stores one value per path node); the turning
## cap (rate scale unknown) is not applied.
func speed() -> float:
	var s: Array = race.get("speeds", [0.4, 0.16])
	# race speeds: run, walk, sneak, crawl
	# no running while carrying more than the maximum load.
	var v: float = s[0] if running and not cannot_run() else s[1]
	if stance != STANCE_NONE and s.size() >= 4:
		v = s[2] if stance == STANCE_KNEEL else s[3]
	var sb := mini(255, _fistp(v * 255.0 / 2.0))
	var fb := mini(255, _fistp(float(proto.get("tuning_move", 1.0)) * wound_factor(3) * 25.5))
	var base := sb * 2.0 / 255.0 * fb / 25.5
	var mul := 1.0
	if world and world.nav and not has_meta("flying") and not path.is_empty():
		var d := path[0] - pos
		if d.length() > 0.001:
			mul = world.nav.step_factor(pos, pos + d.normalized() * NavGrid.CELL, move_class())
	return base * SPEED_SCALE * mul


## x87 FISTP in its default mode: to the nearest integer, ties to even.
static func _fistp(x: float) -> int:
	var f := floorf(x)
	var d := x - f
	if d > 0.5 or (d == 0.5 and int(f) % 2 != 0):
		return int(f) + 1
	return int(f)


## A race_models 7-float column (piercing .. general) times `k`.
func race_factors(col: String, k: float) -> PackedFloat32Array:
	var src: Array = Array(race.get(col, []))
	var out := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	for t in 7:
		out[t] = k * (float(src[t]) if t < src.size() else (1.0 if col == "defence" else 0.0))
	return out


func cannot_run() -> bool:
	return run_refusal() != 0 or (has_meta("hero") and max_mana > 0.0 and mana <= 0.0)


## (1): 2 = carrying more than the maximum load, 1 = a leg below
## DamageLevelRunLimit, else 0.
func run_refusal() -> int:
	if float(stats.get("load", 0.0)) > float(stats.get("max_load", INF)):
		return 2
	return 1 if _legs_ratio() < _wound_levels()[4] else 0


## The gait value of the original unit: 0 crawl, 1 kneel, 2 walk, 3 run.
func gait() -> int:
	return 0 if stance == STANCE_CRAWL else 1 if stance == STANCE_KNEEL else (3 if gait_run else 2)


## Posture and gait from a save record (: set
## directly, no acknowledgement). The figure is put straight into the held
## posture (then, see `_pose_snap`), not crossed into it.
func restore_gait(g: int) -> void:
	stance = STANCE_CRAWL if g == 0 else STANCE_KNEEL if g == 1 else STANCE_NONE
	gait_run = g == 3
	_pose_snap = true
	_update_pose()


## Host: the HUD dial / movement keys for this unit (net message 0x35, server
## handler (g)). The gait is stored at once; when the
## new posture's movement class is open at the unit's cell (
## the same posture always is) a party unit says "change
## position" (ack 9) — except for run while it cannot run ((1))
## which is silent. Crawl / kneel drop the order's double-click run.
## The posture itself then changes as rules (`change_posture`).
func set_gait(g: int) -> void:
	g = clampi(g, 0, 3)
	var st := STANCE_CRAWL if g == 0 else STANCE_KNEEL if g == 1 else STANCE_NONE
	var ok := st == stance or _posture_open(st, false)
	gait_run = g == 3
	if ok and not (g == 3 and run_refusal() != 0):
		ack(EIAcks.CHANGE_POSITION)
	if g < 2:
		order.erase("run")
		for o: Dictionary in orders:
			o.erase("run")
	change_posture(st)


##  passability test of a posture change: with the unit's cell
## open to its present class the cell must be open to the new
## posture's class, else (a unit already standing on a closed cell) the cell
## or one of its neighbours within the slope limit.
func _posture_open(st: int, allow_neighbours := true) -> bool:
	if world == null or world.nav == null or world.nav.size.x == 0:
		return true
	var was_open := world.nav.cell_open(pos, move_class())
	var old := stance
	stance = st
	var cls := move_class()
	stance = old
	if was_open or not allow_neighbours:
		return world.nav.cell_open(pos, cls)
	return world.nav.cell_or_neighbour_open(pos, cls)


## Host: a posture change (the original, run on the command tick).
## Refused when the new posture's movement class does not fit where the unit
## stands (`_posture_open`): the posture stays, the gait falls back to it
## (= the old posture, walk when it stands: the refused request
## carried no run bit) and a
## party unit says "can't change position" (ack 0xd).
func change_posture(st: int) -> bool:
	if st == stance:
		return true
	if not _posture_open(st):
		gait_run = false
		ack(EIAcks.CANT_CHANGE_POSITION)
		return false
	stance = st
	if st != STANCE_NONE:
		gait_run = false
	return true


func damage_mul() -> float:
	var mul := 1.0
	for b in buffs.values():
		mul *= float(b.get("dmg_mul", 1.0))
	return mul


# ------------------------------------------------------------------ perception
# the original keeps six senses and six matching detectabilities per unit (stats
# from the prototype "senses" / "detection"): 0 sight, 1 night
# sight (%), 2 life, 3 hearing, 4 smell, 5 unused here. Magic effects fold in
# per type (the strongest effect of each type counts).

func sense(i: int) -> float:
	var src: Array = Array(proto.get("senses", []))
	var v := float(src[i]) if i < src.size() else (15.0 if i == 0 else 100.0 if i == 1 else 0.0)
	if i == 1 and has_meta("hero"):   # night-vision perk: + perk % of night sight
		v *= 1.0 + Perks.best(get_meta("hero"), "night") / 100.0
	return v + sense_bonus(i)


## Magic-effect bonus on sense i (eagle sight, infravision, detect life).
func sense_bonus(i: int) -> float:
	var add := 0.0
	for b in buffs.values():
		if b.has("sense") and int(b.sense[0]) == i:
			add = maxf(add, float(b.sense[1]))
	return add


func detect(i: int) -> float:
	var src: Array = Array(proto.get("detection", []))
	var v := float(src[i]) if i < src.size() else 1.0
	var lo := 0.0
	var hi := 0.0
	for b in buffs.values():
		if b.has("detect") and int(b.detect[0]) == i:
			lo = minf(lo, float(b.detect[1]))
			hi = maxf(hi, float(b.detect[1]))
	return maxf(0.0, v + lo + hi)


## Own visibility factor (stats): crawling 0.5, kneeling
## 0.75, x1.5 while casting.
func vis_factor() -> float:
	var f := 0.5 if stance == STANCE_CRAWL else 0.75 if stance == STANCE_KNEEL else 1.0
	return f * (1.5 if action.begins_with("cast") else 1.0)


## Noise of the own movement: 0 standing, crawling 0.4, kneeling 0.2
## walking 1, running 2; times the ground's StepSound.
func noise() -> float:
	if not action in ["walk", "run", "crawl"]:
		return 0.0
	var n := 2.0 if action == "run" else 1.0
	if stance == STANCE_CRAWL:
		n = 0.4
	elif stance == STANCE_KNEEL:
		n = 0.2
	if world and world.terrain:
		n *= world.terrain.step_sound_at(pos.x, pos.y)
	return n


## Own hearing factor: a running unit hears half as far.
func hear_factor() -> float:
	return 0.5 if action == "run" and stance == STANCE_NONE else 1.0


## Own sight factor: 1 - dark + dark x night sight / 100, where dark is
## the world's darkness (0 by day). Units with night sight 100 see as by day.
func sight_factor() -> float:
	var dark := 1.0 - world.daylight() if world else 0.0
	return 1.0 - dark + dark * sense(1) / 100.0


## Feeblemind refuses spell-casting orders.
func cannot_cast() -> bool:
	for b in buffs.values():
		if b.get("no_cast", false):
			return true
	return false


func is_invisible() -> bool:
	return detect(0) <= 0.0


## Actions (Dex * 0.2 + 10, quickness perk) plus speed - slow effects, min 1.
func actions() -> float:
	# actions x wound factor of the worst arm.
	var a := float(stats.get("actions", 15.0)) * wound_factor(2)
	for b in buffs.values():
		a += float(b.get("actions_add", 0.0))
	return maxf(1.0, a)


# ------------------------------------------------------------------ simulation

func tick(dt: float) -> void:
	_moving = false
	if not dead:
		_tick(dt)
	world.nav.track_unit(self)


func _tick(dt: float) -> void:
	# the original runs its logic in 55 ms ticks. Every 15 ticks
	#  health gains max x race "health regen" x (1 + vitality/100)
	# and stamina max x race "mana regen" x (1 + spirit/100), stamina only while
	# the unit is idle.
	_regen_t += dt
	while _regen_t >= TICK * 15.0:
		_regen_t -= TICK * 15.0
		var rm := 1.0
		for b in buffs.values():
			rm *= float(b.get("regen_mul", 1.0))
		heal(max_hp * float(race.get("health_regen", 0.0)) * (1.0 + float(stats.get("regen_hp", 0.0)) / 100.0) * rm)
		if is_idle():
			mana = minf(max_mana, mana + max_mana * float(race.get("mana_regen", 0.0)) * (1.0 + float(stats.get("regen_mana", 0.0)) / 100.0))
	# Running characters lose max stamina / 150 per tick and
	# walk once it is gone.
	if has_meta("hero") and action == "run":
		mana = maxf(0.0, mana - max_mana / 150.0 * dt / TICK)
	_attack_cd -= dt
	if not buffs.is_empty():
		for b in buffs.keys():
			if world.time >= float(buffs[b].until):
				var had_hp: bool = buffs[b].has("hp_mul")
				buffs.erase(b)
				if had_hp:
					refresh_max_hp()
		# Stun (spell 25, magic effect 0x19) does not hold the unit: no game
		# code reads effect 0x19 — not the stat folds
		#  (asked for 0x1d–0x1f)
		# (0x10, 0x20 and the AI's "already has it"), the
		# command / AI code, nor any effect switch but the visuals
		# . Like enlarge / shrink it only shows.
	if not _pending_hit.is_empty():
		_pending_hit.t -= dt
		if _pending_hit.t <= 0.0:
			_resolve_hit(_pending_hit.target, _pending_hit.get("roll", {}))
			_pending_hit = {}
	# The perception of a Player-motivation unit runs on every AI tick, busy,
	# walking or in a clip: the noticed list the
	# engage check reads (UnitAI.player_perceive).
	if (controller >= 0 or mode == "player") and world.time >= _perceive_next:
		_perceive_next = world.time + TICK - 0.0001
		world.ai.player_perceive(self)
	if _anim_lock > 0.0:
		_anim_lock -= dt
		return
	if resting and not (order.is_empty() and orders.is_empty()):
		resting = false   # a new order ends the Rest order (0xb)
	if order.is_empty():
		if orders.is_empty():
			if world.time >= ai_next:
				world.ai.think(self)
			if orders.is_empty():
				_set_action("idle")
				return
		order = orders.pop_front()
		path = PackedVector2Array()
	elif controller < 0 and world.time >= ai_next and order.get("calm", false):
		world.ai.think(self)   # a calm motivation's walk: the AI keeps choosing
		if order.is_empty() and not orders.is_empty():
			order = orders.pop_front()
			path = PackedVector2Array()
	elif controller < 0 and world.time >= ai_next and not order.get("ai", false) and world.ai.calm_tick(self):
		return   #  cast a buff / heal over the calm walk
	elif controller >= 0 and order.has("swarm") and world.ai.swarm_tick(self):
		return   # Ctrl / aimed-key ground click (packet 0x3a): engages on the way
	elif controller >= 0 and order.get("type", "") == "follow" and not order.get("once", false) \
			and world.ai.follow_engage(self):
		return   # F order (Player motivation state 6): engages while following
	match order.type:
		"move": _do_move(dt)
		"attack": _do_attack(dt)
		"follow": _do_follow(dt)
		"wait":
			_set_action("idle")
			if order.has("face") and not _turn_to(float(order.face), dt):
				return
			order.t = float(order.get("t", 1.0)) - dt
			if order.t <= 0.0:
				order = {}
		"anim":
			_anim_lock = model.act(order.name, int(order.get("variant", 1)), 0.1) if not model.has_anim(order.name) \
				else _play_clip(order.name)
			action = "anim:" + String(order.name)
			order = {}
		"rotate":
			if _turn_to(float(order.angle), dt):
				order = {}
		"cast": _do_cast(dt)
		"use": _do_use(dt)
		_: order = {}


## The use action, order type 6 (the original
##  case 6): `order.sub` is the
## action sub-code — "science" (0, a lever or switch), "steal" (1)
## "tame" (2), "loot" (a corpse or chest). The unit first turns to
## face `order.at`, then plays:
##   loot, standing: AC_SPECIAL modifier 48 (bow / crossbow 52), no cross;
##   loot, kneeling / crawling: modifier 53 (bow / crossbow 22), crawling
##     units cross to kneeling first and back after;
##   science 21, steal 20, tame 19: no weapon bits; a unit not kneeling
##     crosses to kneeling first and back after.
## (Human Hero: uspecial22 / 23 / 24 / 07, uspecial06 / 05 / 04.) The action
## itself (`order.done`) runs at the clip's hit frame: end tick =
## start + cross-in length + the clip's hit frame (.adb, at the race's
## animation speed); the rest of the clip and the cross back still play.
## Clients see each clip through the snapshot action "anim:<clip>".
const USE_MOD := {"science": 21, "steal": 20, "tame": 19}


func _do_use(dt: float) -> void:
	var ph := int(order.get("phase", 0))
	if ph == 0:
		var at: Vector2 = order.at
		if at.distance_to(pos) > 0.01 and not _turn_to((at - pos).angle(), dt):
			_set_action("idle")
			return
		var sub := String(order.sub)
		var bowish := model != null and model.weapon_type in ["bow", "crossbow"]
		var md := 0
		var kneel := false
		if sub == "loot":
			if stance == STANCE_NONE:
				md = 52 if bowish else 48
			else:
				md = 22 if bowish else 53
				kneel = stance != STANCE_KNEEL
		else:
			md = USE_MOD.get(sub, 21)
			kneel = stance != STANCE_KNEEL
		var clip := ""
		if model and not model.adb.is_empty():
			var wb := model.weapon_bit() if sub == "loot" else 0
			clip = model.pick(EIUnitModel.AC_SPECIAL | md * EIUnitModel.MOD_1 | wb)
		order.clip = clip
		order.kneel = kneel and clip != ""
		order.from_st = model.pose_state if model else 0
		order.phase = 1
		if order.kneel:
			var c := _cross_clip(int(order.from_st), EIUnitModel.ST_WARRY)
			if c != "":
				_anim_lock = _play_clip(c)
				action = "anim:" + c
				return
		ph = 1
	if ph == 1 and order.has("hold"):
		# Remake option "revive" (Revive.begin): the clip is held (replayed)
		# for `hold` seconds and the action runs at the end, not at the hit
		# frame; the action string carries the progress to every peer.
		order.phase = 5
		order.t0 = world.time
		ph = 5
	if ph == 5:
		var chk = order.get("check")
		if chk is Callable and (chk as Callable).is_valid() and not bool((chk as Callable).call()):
			order = {}
			_pose_dirty = true
			_set_action("idle")
			return
		var hold := float(order.hold)
		var el := world.time - float(order.t0)
		if el < hold:
			var clip := String(order.clip)
			_keep_clip(clip)
			action = "revive:%s:%d" % [clip, int(el / hold * Revive.PROGRESS_STEPS)]
			return
		_use_done()
		ph = 3
	if ph == 1:
		var clip := String(order.clip)
		order.phase = 2
		if clip == "":
			_use_done()
			order = {}
			_set_action("idle")
			return
		var len := _play_clip(clip)
		action = "anim:" + clip
		var hit := _clip_hit_ticks(clip) * TICK
		if hit < 0.0 or hit > len:
			hit = len
		order.rest = len - hit
		_anim_lock = hit
		return
	if ph == 2:
		_use_done()
		order.phase = 3
		_anim_lock = float(order.rest)
		if _anim_lock > 0.0:
			return
		ph = 3
	if ph == 3:
		order.phase = 4
		if order.kneel:
			var c := _cross_clip(EIUnitModel.ST_WARRY, int(order.from_st))
			if c != "":
				_anim_lock = _play_clip(c)
				action = "anim:" + c
				return
	order = {}
	_pose_dirty = true
	_set_action("idle")


## Keeps `clip` playing: started again once it has ended or something else
## (a hit) took over (Revive's held use action; co-op clients alike).
func _keep_clip(clip: String) -> void:
	if clip != "" and model and model.player and model.player.current_animation != "ei/" + clip:
		model.play(clip, 0.1, true)


func _use_done() -> void:
	var cb = order.get("done")
	order.erase("done")
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()


## The stance change clip from one animation state to another (as
## EIUnitModel.cross picks it), "" when the database has none.
func _cross_clip(from_st: int, to_st: int) -> String:
	if model == null or not EIUnitModel._CROSS_TO.has(to_st):
		return ""
	return model.pick(model.weapon_bit() | from_st | EIUnitModel.AC_CROSS | EIUnitModel._CROSS_TO[to_st] * EIUnitModel.MOD_1)


## A clip's hit frame in logic ticks (.adb / the race's animation
## speed, as `_hit_ticks`), -1 when unknown.
func _clip_hit_ticks(clip: String) -> float:
	var f := _clip_hit_frame(String(model.template).to_lower() if model else "", clip)
	if f < 0:
		return -1.0
	var sp: Array = Array(race.get("anim_speeds", [1.0]))
	var k := float(sp[0]) if not sp.is_empty() and float(sp[0]) != 0.0 else 1.0
	return float(maxi(1, int(float(f) / k)))


func _play_clip(clip: String) -> float:
	model.play(clip, 0.1)
	return model.player.get_animation("ei/" + clip).length


func _do_move(dt: float) -> void:
	# A player's move order runs by the unit's gait (: == 3)
	# or its double-click flag (standing only); script / AI moves
	# carry their own run flag.
	if order.get("gait", false):
		running = stance == STANCE_NONE and (gait_run or bool(order.get("run", false)))
	else:
		running = bool(order.get("run", true))
	if path.is_empty():
		var replan := _avoid != null and is_instance_valid(_avoid)
		# The stick's moves ("line", remake): the straight line when it can
		# be walked as it is (NavGrid.direct_line), else the path search.
		if order.get("line", false) and not replan and world.nav.direct_line(self, order.to):
			path = PackedVector2Array([order.to])
			_kept = {}
		else:
			path = _kept_path(order.to)
		if path.is_empty():
			path = _path_to(order.to)
		if path.is_empty():
			_fail_order(EIAcks.NO_PATH)
			return
		_fresh_path = replan
	if _step_along_path(dt):
		order = {}


## A move order given again while the unit walks the same one (a script
## re-issuing UMSentry / MoveToPoint to the spot every few ticks — gz19h's
## guards march 200 m that way) keeps the path being walked instead of
## searching the map anew: the original plans again (
## ), but from a spot on an optimal path to the same goal that
## search finds the rest of the same path. **Approx.** (remake speed: such a
## search costs ~0.1 s here): kept only while the AI map is unchanged
## (NavGrid.map_rev), for the same movement class and water state, not after
## a blocked step (a plan round a blocker is searched as before); units that
## came to stand on it since block the walk and make it plan then.
var _kept := {}


func _keep_path(o: Dictionary) -> void:
	# The same order given more than once before the unit ticks (several
	# script threads): the path kept by the first stays kept.
	if not _kept.is_empty() and order.is_empty() and orders.size() == 1 and String(o.get("type", "")) == "move" \
			and String(orders[0].get("type", "")) == "move" and orders[0].get("to") == o.get("to") and _kept.to == o.get("to"):
		return
	_kept = {}
	if path.is_empty() or _fresh_path or world == null or not world.authority or world.nav == null \
			or String(o.get("type", "")) != "move" or String(order.get("type", "")) != "move" \
			or order.get("to") != o.get("to") or (_avoid != null and is_instance_valid(_avoid)):
		return
	_kept = {"to": o.to, "path": path, "pos": pos, "rev": world.nav.map_rev, "cls": move_class(),
		"wet": world.nav.cell_wet(pos)}


func _kept_path(to: Vector2) -> PackedVector2Array:
	var k := _kept
	_kept = {}
	if k.is_empty() or k.to != to or k.pos != pos or (_avoid != null and is_instance_valid(_avoid)) \
			or int(k.rev) != world.nav.map_rev or int(k.cls) != move_class() or bool(k.wet) != world.nav.cell_wet(pos):
		return PackedVector2Array()
	return k.path


## A path to `to` for this unit: its own stamp and that of `t` (an attack
## target) lifted, and a unit it bumped into stamped (see NavGrid.find_path).
## The search prices every open cell alike (the flat table, unit) for
## an attack approach and for a unit standing
## in water.
## Approx.: is worked out per search, not kept from the last order.
func _path_to(to: Vector2, t: GameUnit = null) -> PackedVector2Array:
	var avoid := [_avoid] if _avoid and is_instance_valid(_avoid) else []
	_avoid = null
	return world.nav.find_path(pos, to, [self, t] if t else [self], avoid,
		maxf(0.0, body_radius() - NavGrid.R_REF), move_class(),
		t != null or world.nav.cell_wet(pos))


## Returns true when the path end is reached. Every step is first checked
## against the other units (NavGrid.step_blocker, the original): a
## standing blocker makes the unit plan anew round it; a moving one makes it
## wait (stand) this tick — it then counts as standing to the other, which
## goes round — unless this unit is the faster: it then plans round the
## blocker's spot. Two attackers of one target, this one more
## than sqrt(60) m from it, queue instead (unit-AI).
## Units never push each other.
func _step_along_path(dt: float) -> bool:
	var budget := speed() * dt
	var from := pos
	while budget > 0.0 and not path.is_empty():
		var tgt := path[0]
		var d := pos.distance_to(tgt)
		if d > 0.001:
			var ang := (tgt - pos).angle()
			_turn_to(ang, dt)
		var q := tgt if d <= budget else pos + (tgt - pos) / d * budget
		var res := {}
		var b := world.nav.step_blocker(self, q, res)
		if b:
			_blocked_by(b, bool(res.standing))
			return false
		_moving = true
		_fresh_path = false
		pos = q
		if d <= budget:
			budget -= d
			path.remove_at(0)
		else:
			budget = 0.0
	var arrived := path.is_empty()
	if arrived and pos.distance_to(from) < 0.01:
		return true   # already there: no walk clip for an order that ends at once
	# a party unit asked to run that cannot ((1))
	# says "overloaded" (ack 0x14) or "injured" (0x15); its run request, the
	# double-click flag and the run gait are dropped (= walk).
	if running and controller >= 0 and stance == STANCE_NONE:
		var r := run_refusal()
		if r != 0:
			ack(EIAcks.OVERLOAD if r == 2 else EIAcks.INJURED)
			gait_run = false
			order.erase("run")
			running = false
	if stance == STANCE_CRAWL and model and model.resolve("crawl") != "":
		_set_action("crawl")
	else:
		_set_action("run" if running and not cannot_run() else "walk")
	return arrived


func _blocked_by(b: GameUnit, standing: bool) -> void:
	var t: GameUnit = _order_target() if order.get("type", "") == "attack" else null
	# a step blocked by a standing unit plans anew
	# no path ends the order (stops the unit, move mode 6). The
	# original's search only enters cells its step test accepts, so a path it finds
	# can be walked; a remake path planned round the blocker (a coarser grid)
	# whose very first step is refused again counts as no path — the unit used
	# to stand for ever with a live order, planning the same path each tick.
	# **Approx.**
	if standing and _fresh_path and order.get("type", "") in ["move", "attack"]:
		_fresh_path = false
		path = PackedVector2Array()
		if order.type == "move":
			_fail_order(EIAcks.NO_PATH)
		else:
			_fail_order(EIAcks.NO_WAY_TO_ATTACK)
			target = null
			_goal = Vector2.INF
		_set_action("idle")
		return
	var queue: bool = t != null and b.order.get("type", "") == "attack" and b.order.get("target") == t \
		and b.faction == faction and pos.distance_squared_to(t.pos) > 60.0
	if not queue and (standing or speed() > b.speed()):
		_avoid = b
		path = PackedVector2Array()
		_arrive_t = 0.0
	_set_action("idle")


## Where the unit will be `dist` metres further along its path.
func pos_ahead(dist: float) -> Vector2:
	var p := pos
	for q in path:
		var l := p.distance_to(q)
		if l >= dist:
			return p + (q - p) / l * dist if l > 0.0 else p
		dist -= l
		p = q
	return p


func _turn_to(ang: float, dt: float) -> bool:
	var diff := wrapf(ang - facing, -PI, PI)
	var step := TURN_SPEED * dt
	if absf(diff) <= step:
		facing = ang
		return true
	facing += signf(diff) * step
	return false


func _do_follow(dt: float) -> void:
	var t: GameUnit = _order_target()
	# A loot approach goes to a body (order.corpse, wants it dead).
	if t == null or not is_instance_valid(t) or t.dead != bool(order.get("corpse", false)):
		order = {}
		return
	if not order.get("once", false):
		_follow_order(t, dt)
		return
	var dist := float(order.get("dist", 2.0))
	if pos.distance_to(t.pos) <= dist:
		path = PackedVector2Array()
		_set_action("idle")
		if order.get("once", false):
			order = {}
		return
	_repath -= dt
	if path.is_empty() or _repath <= 0.0:
		path = _path_to(t.pos, t)
		_repath = 0.5
	if controller >= 0:
		# A party unit goes at its gait on every command, an
		# interact / loot / steal approach (order type 6) too.
		# A double-clicked order runs while standing (run bit 2).
		running = stance == STANCE_NONE and (gait_run or bool(order.get("run", false)))
	else:
		running = pos.distance_to(t.pos) > dist + 3.0
	_step_along_path(dt)


## The F / Follow order (Player motivation state 6, its tick run
##  on every 55 ms AI tick). The check itself is
## `_follow_tick`; what it starts is a plain move, kept here as
## order.walk (the unit's move goal) and walked until reached or
## replaced. Nothing else moves the follower: between checks it stands.
func _follow_order(t: GameUnit, dt: float) -> void:
	order.acc = float(order.get("acc", 0.0)) + dt
	while float(order.acc) >= TICK:
		order.acc = float(order.acc) - TICK
		_follow_tick(t)
	if not order.has("walk"):
		path = PackedVector2Array()
		_set_action("idle")
		return
	if controller >= 0:
		# A party unit goes at its gait on every command.
		running = stance == STANCE_NONE and gait_run
	else:
		running = false   #  run byte 0
	if path.is_empty():
		path = _path_to(order.walk)
		if path.is_empty():
			order.erase("walk")
			_set_action("idle")
			return
	if _step_along_path(dt):
		order.erase("walk")
		path = PackedVector2Array()


## one AI tick of the Follow state. The counter counts
## every call; the check runs only once it was 8 or more, and a move it starts
## sets it to 6 (checked again 2 ticks later) or 0 (8 ticks later). Target dead
## the state ends ((0), AI +4 = 0; `_do_follow`). d = 3D distance
## to the target, Min / Max = ai.reg [Logic] FollowMinDist / FollowMaxDist
## (2 / 4), goal = the follower's move goal or its
## own position when it has none.
## - Target walking (its current or next command is 1, a move):
##   P5 = its position 5 ticks ahead, e = |self − P5|² (ground
##   plane). If e ≥ d² (the target walks away) or e ≥ Min²: move to P5 when P5 is
##   more than Max from the goal (search limit 3d + 10; counter 6). Else (it comes
##   towards the follower, the prediction within Min) its predicted spots at
##   ticks 6..99 are scanned while they keep getting closer: one within
##   sqrt(1.3) m means it would walk into the follower, which steps aside — to
##   the point 1.365 m from its spot 40 ticks ahead (P40), square to its heading
##   (target → P40) on the follower's side; when the path search (limit 10)
##   cannot end within sqrt(0.1) m of that point, to P40 itself (limit 20)
##   unless the goal is already within sqrt(0.5) m of it (counter 6).
## - Target standing: d < Min → stop; else when the goal is more
##   than Max from the target, move to the target's position (limit 3d + 10;
##   counter 0). So a follower stops within 2 m and sets off again only once the
##   target is more than 4 m from where it stands.
## Approx.: the search limit is only applied to the step-aside point (path_fits);
## the original compares the search's end cell (× 0.5 m) with the point.
func _follow_tick(t: GameUnit) -> void:
	var n := _follow_n
	_follow_n += 1
	if n < 8:
		return
	var lo := float(GameData.ai_value("Logic", "FollowMinDist", 2.0))
	var hi := float(GameData.ai_value("Logic", "FollowMaxDist", 4.0))
	var d := dist3(t)
	var goal: Vector2 = order.get("walk", pos)
	if t.follow_walking():
		var p5 := t.future_pos(5)
		var e := pos.distance_squared_to(p5)
		if e >= d * d or e >= lo * lo:
			if p5.distance_squared_to(goal) > hi * hi:
				_follow_walk(p5)
				_follow_n = 6
			return
		var prev := e
		for i in range(6, 100):
			var q := t.future_pos(i)
			var di := pos.distance_squared_to(q)
			if di > prev:
				return
			if di < 1.3:
				_follow_step_aside(t, goal)
				return
			prev = di
		return
	if d * d < lo * lo:
		order.erase("walk")
		path = PackedVector2Array()
		return
	if goal.distance_squared_to(t.pos) > hi * hi:
		_follow_walk(t.pos)
		_follow_n = 0


##  step aside from a target walking into the follower.
func _follow_step_aside(t: GameUnit, goal: Vector2) -> void:
	var p40 := t.future_pos(40)
	var dv := p40 - t.pos
	var l2 := dv.length_squared()
	if l2 <= 0.0:
		return
	var side := Vector2(-dv.y, dv.x) * (1.365 / sqrt(l2))
	if (pos - t.pos).dot(side) < 0.0:
		side = -side
	var c := p40 + side
	var p := _path_to(c)   # (unit, c, …, 10)
	if not p.is_empty() and p[-1].distance_squared_to(c) < 0.1 and path_fits(p, c, 10.0):
		_follow_walk(c, p)
	elif goal.distance_squared_to(p40) > 0.5:
		_follow_walk(p40)
	else:
		return
	_follow_n = 6


## The follower's move: a new goal, planned afresh.
func _follow_walk(to: Vector2, p := PackedVector2Array()) -> void:
	order.walk = to
	path = p


## Whether the unit's current or next command is a move (== 1)
## as asks of the followed unit: a move order, or a follower's
## own move.
func follow_walking() -> bool:
	if order.get("type", "") == "move" or (order.get("type", "") == "follow" and order.has("walk")):
		return true
	return not orders.is_empty() and orders[0].get("type", "") == "move"


## The unit's position `ticks` logic ticks ahead: along its path
## at its current speed; where it stands when it has none.
func future_pos(ticks: int) -> Vector2:
	if path.is_empty():
		return pos
	return pos_ahead(speed() * ticks * TICK)


func _do_attack(dt: float) -> void:
	alert = true
	var t: GameUnit = _order_target()
	if t == null or not is_instance_valid(t) or t.dead or t.hidden:
		order = {}
		target = null
		return
	# an AI unit keeps attacking a target it has noticed; a
	# live hostile never leaves an NPC's noticed list, so only
	# a target of another side that is not hostile (a revenge target) is
	# dropped once out of notice (k = 1.05), the unit becoming suspicious of
	# its spot (level 1000, -2 a tick).
	if controller < 0 and t.faction != faction and not world.is_enemy(self, t) \
			and not world.ai.can_notice(self, t, stats.sight * 1.05):
		order = {}
		target = null
		world.ai.suspect(self, t.pos, 1000.0)
		return
	target = t
	if world.ai.rechoose(self):   # the AI may switch to a spell or another target
		return
	var ranged: bool = stats.get("ranged", false)
	var reach: float = stats.reach if ranged else melee_reach(t)
	var d := pos.distance_to(t.pos)
	#  hands the tick to while the strike delay
	#  runs or the target is out of reach; that one only stands
	# still next to a target that is not moving — one that
	# moves is followed (see _approach).
	if d > reach or (not ranged and not _strike_clear(t, d)) or (_attack_cd > 0.0 and t._moving):
		_approach(t, d, reach, dt)
		return
	_goal = Vector2.INF
	path = PackedVector2Array()
	# the original (order tick): only once the strike can be made
	# (the strike delay passed and finds the target
	# reach; else keeps closing in at the unit's gait) does an
	# order other than types 4 / 5 / 6 (an attack) set the gait to 2
	# (walk) while the posture is not standing — a kneeling or crawling
	# unit sneaks up and stands up to strike (the change itself is
	# `change_posture`). Every strike clip of the human
	# databases is a standing combat-state one (state 2).
	if stance != STANCE_NONE and _attack_cd <= 0.0:
		gait_run = false
		change_posture(STANCE_NONE)
	if not _turn_to((t.pos - pos).angle(), dt):
		return
	if _attack_cd > 0.0:
		_set_action("idle")
		return
	# The strike is queried in the combat state (alert)
	# a unit that was idle in the relaxed state first plays its cross clip.
	if _update_pose():
		return
	var len := model.act("attack", randi_range(1, 3), 0.05)
	len = maxf(len, 0.6)
	action = "attack"
	_anim_lock = len
	# the original: the next strike may start round(A x 15 / actions)
	# ticks after this one, A = the weapon's "actions" (unarmed: the prototype's
	# "tuning actions", inferred), actions = Dex * 0.2 + 10 (x quickness, x arm
	# wounds; monsters 15). The strike animation still has to finish.
	var a_w := float(stats.get("weapon_actions", proto.get("tuning_actions", 50.0)))
	_attack_cd = maxf(roundf(a_w * 15.0 / actions()) * TICK, len)
	# The outcome is rolled now, the blow lands later. The hit
	# record takes this order's aim before the roll (
	# then reads its).
	strike_aim = int(order.get("aim", -1))
	var roll := world.combat.strike_roll(self, t)
	strike_miss = not roll.hit
	_pending_hit = {"t": _hit_ticks() * TICK, "target": t, "roll": roll}
	GameSound.unit(self, "attack")
	world.on_attack(self, t)


## Closing in on an attack target (the original). The unit heads for
## where the target will be on arrival: round((d - reach) / closing speed)
## ticks ahead, 2 .. 64, closing speed = own speed + the target's speed along
## its heading . the line to it (per 55 ms tick, at least 0.1). It plans again
## once that estimate is within 16 ticks, unless its path already ends within
## (d + 1) x 0.1 m of the new spot. A path ending farther than the reach from
## it means no way to the target (ack NoWayAtt, the order ends).
func _approach(t: GameUnit, d: float, reach: float, dt: float) -> void:
	# a party unit approaches at its gait, any other one runs
	# (its combat flag is set by the attack command); only standing.
	# A double-clicked attack runs while standing (run bit 2).
	running = not sneaking and (gait_run or controller < 0 \
		or (bool(order.get("run", false)) and stance == STANCE_NONE))
	# a moving target: w = the ticks
	# left of the strike delay + 16; while w > 0 and the unit could
	# reach the spot the target will be at in w ticks within
	# w ticks — (distance − reach) / v < w, v = 0.5 x
	# (: the gait speed in 0.5 m cells a tick, no terrain
	# factor) = metres a tick — it stands (idle
	# (2)) and lets the target come; otherwise it keeps closing
	# in, so a fleeing target is chased at a run, not in stop-and-go.
	if t._moving:
		var w := roundi(_attack_cd / TICK) + 16
		if w > 0:
			var p := path
			path = PackedVector2Array()
			var v := speed() * TICK
			if v > 0.0 and (pos.distance_to(t.pos_ahead(t.speed() * TICK * w)) - reach) / v < w:
				_goal = Vector2.INF
				_set_action("idle")
				return
			path = p
	if path.is_empty() or world.time >= _arrive_t - 16.0 * TICK:
		var tv := t.speed() * TICK if t._moving else 0.0
		var closing := speed() * TICK + tv * Vector2.from_angle(t.facing).dot((t.pos - pos) / maxf(d, 0.001))
		var ticks := clampi(roundi((d - reach) / maxf(closing, 0.1)), 2, 64)
		var at := t.pos_ahead(tv * ticks)
		if path.is_empty() or _goal.distance_to(at) >= (d + 1.0) * 0.1:
			_fresh_path = _avoid != null and is_instance_valid(_avoid)
			path = _path_to(at, t)
			_goal = at
			_arrive_t = world.time + ticks * TICK
			if path.is_empty() or path[-1].distance_to(at) > reach or _path_too_long(t):
				_fail_order(EIAcks.NO_WAY_TO_ATTACK)
				target = null
				_goal = Vector2.INF
				return
	_step_along_path(dt)


## The attack path's length limit (passed + 5 to
## the search): 3 d + 10 for a unit outside the players'
## parties (unit = 0), d = the distance to the target. A party unit has
## none here (3 min(d, 10) + 10 only while unit flag is set, which
##  does around its target choice, see GameAI._reachable).
func _path_too_long(t: GameUnit) -> bool:
	if controller >= 0 or path.is_empty():
		return false
	return not path_fits(path, t.pos, 3.0 * dist3(t) + 10.0 + 5.0)


## Distance to `o` in 3D (ground heights), as the original measures unit centres.
func dist3(o: GameUnit) -> float:
	return Vector3(o.pos.x - pos.x, o.pos.y - pos.y,
		world.ground_at(o.pos.x, o.pos.y) - world.ground_at(pos.x, pos.y)).length()


## Whether a path from here to `to` keeps within a search length limit
## a goal under 25 cells away (octile) is searched directly
##  without it; else the block route (8-cell
## blocks) must be at most round(2 limit - 0.5) cells long. Approx.: the
## remake counts its own path's length in whole 4 m blocks.
func path_fits(p: PackedVector2Array, to: Vector2, limit: float) -> bool:
	var dc := (NavGrid.cell(to) - NavGrid.cell(pos)).abs()
	if maxi(dc.x, dc.y) - mini(dc.x, dc.y) + ((mini(dc.x, dc.y) * 0x5a8) >> 10) < 25:
		return true
	var length := 0.0
	var q0 := pos
	for q in p:
		length += q0.distance_to(q)
		q0 = q
	return ceili(length / 4.0) * 8 <= roundi(limit * 2.0 - 0.5)


## Nothing stands in a melee strike's way: no other unit
## 10 - 90 % of the way to the target within 0.3 m of the line.
func _strike_clear(t: GameUnit, d: float) -> bool:
	if d < 0.01:
		return true
	var dir := (t.pos - pos) / d
	for o: GameUnit in world.nav.units_around(pos.lerp(t.pos, 0.5), d * 0.5 + 0.5, false):
		if o == self or o == t or o.dead:
			continue
		var rel := o.pos - pos
		var along := rel.dot(dir) / d
		if along > 0.1 and along < 0.9 and absf(rel.cross(dir)) < 0.3:
			return false
	return true


## The stamina a cast costs. Only the players' units pay it or need it
## (test unit, the owning party): AI
## units cast for free.
func _spell_cost(sp: Dictionary) -> float:
	return float(sp.mana) if controller >= 0 else 0.0


func _do_cast(dt: float) -> void:
	var t: GameUnit = _order_target()
	if (t != null and (not is_instance_valid(t) or t.dead)) or cannot_cast():
		if cannot_cast() and world.session:
			world.session.failed(self, 9)   # "Can't cast spells"
		order = order.get("then", {}) if cannot_cast() else {}
		return
	var at: Vector2 = t.pos if t else order.point
	var sp := Spells.parse(order.spell)
	# An AI cast reaches its option's range (the prototype's attack range on
	# a weapon-type-16 unit).
	if pos.distance_to(at) > float(order.get("range", sp.range)):
		if path.is_empty():
			path = _path_to(at, t)
			if path.is_empty():
				_fail_order(EIAcks.NO_PATH)
				return
		# A party unit walks to the cast at its gait.
		running = not sneaking and gait_run if controller >= 0 else true
		_step_along_path(dt)
		return
	path = PackedVector2Array()
	if not _turn_to((at - pos).angle(), dt):
		return
	if order.has("item"):
		# A belt item's spell costs no stamina; the item is used up instead.
		if world.session == null or not world.session.consume_quick(self, String(order.item)):
			order = {}
			return
	elif mana < _spell_cost(sp):
		order = order.get("then", {})
		return
	else:
		mana -= _spell_cost(sp)
	var clip := _cast_clip()
	var plan := _cast_plan(sp, clip)
	var hold := int(plan.hold)
	var len := maxf(_cast_anim(clip, hold), 0.6)
	# Clients replay the hold from the action ("cast:<hold ticks>").
	action = "cast" if hold == 0 else "cast:%d" % hold
	var cast_t := float(plan.fire) * TICK
	_anim_lock = maxf(len + hold * TICK, cast_t)
	var spell: String = order.spell
	order = order.get("then", {})   # monsters go back to fighting
	GameSound.spell(Spells.parse(spell).code, global_position, "start")
	# Casting particles by school (visual only): made at the
	# action's start tick, removed at its end tick (the spell's effect
	#  is 5 for the whole action).
	if world.session:
		world.session.broadcast({"t": "castfx", "uid": uid, "spell": spell, "secs": cast_t})
	var tref: WeakRef = weakref(t) if t else null   # the target may leave the world first
	get_tree().create_timer(cast_t).timeout.connect(func():
		if not dead and is_instance_valid(world):
			var tu: GameUnit = tref.get_ref() if tref else null
			Spells.apply(world, self, spell, tu, at)
			# the cast is heard (the caster's hearing
			# detectability × 2, 26 ticks) unless the spell record's is 1.
			if int(Spells.parse(spell).proto.get("type_id", 0)) != 1:
				world.ai.noise_event(self, detect(3) * 2.0)
			if world.session:
				world.session.broadcast({"t": "spellfx", "code": Spells.parse(spell).code, "sub": Spells.parse(spell).subtype,
					"x": at.x, "y": at.y, "a": uid, "tu": tu.uid if tu else -1, "spell": spell,
					"hold": Spells.light_time(spell)}))


## The cast clip (query, cast action), else an attack
## clip for a figure without one.
func _cast_clip() -> String:
	if model == null:
		return ""
	var clip := model.action_clip("cast")
	return clip if clip != "" else model.action_clip("attack")


## When a cast takes effect and how its clip is held (the original
## ): the cast time C = round(spell actions (sdb field 14
## prototype -> spell) x 15 / the caster's actions (worse
## with wounded arms)); the clip's length L = trunc(.adb
## speed) and hit frame H = trunc(speed), speed = the race's cast
## animation speed (creature; 1 for every race).
## C <= L: the clip alone, the effect at H. L < C: the action
## lasts C ticks and the effect comes at H + (C - L) — the clip stops on its
## hit frame for the C - L ticks between (hold, see _cast_anim). Returns
## {fire: effect ticks, hold: C - L or 0}.
func _cast_plan(sp: Dictionary, clip: String) -> Dictionary:
	var fr := _clip_frames(String(model.template).to_lower() if model else "", clip)
	var c := roundi(float(sp.proto.get("actions", 0)) * 15.0 / actions())
	if fr.y < 0:
		var len := model.player.get_animation("ei/" + clip).length if model and model.has_anim(clip) else 1.2
		return {"fire": maxf(1.0, roundf(len * 0.5 / TICK)), "hold": 0}
	var k := _cast_anim_speed()
	var l := int(float(fr.x) / k)
	var h := int(float(fr.y) / k)
	if l < c:
		return {"fire": float(maxi(1, h + c - l)), "hold": c - l}
	return {"fire": float(maxi(1, h)), "hold": 0}


## The race's cast animation speed (units.udb "anm cast speed", creature
## for a clip of action).
func _cast_anim_speed() -> float:
	var spd: Array = Array(race.get("anim_speeds", [1.0]))
	var k := float(spd[1]) if spd.size() > 1 else float(spd[0]) if not spd.is_empty() else 1.0
	return k if k != 0.0 else 1.0


## Plays the cast clip with its hold of `hold` ticks, as the original's segment
## queue does (builds it, copies it to the unit's
## queue at the start tick, step it each
## tick): a walking unit (logic = units.udb race "locomotion" 1) gets
## [clip for H ticks][no clip, C - L ticks, flag 1][no clip, L - H ticks]:
## a "no clip" entry keeps the clip, and the flag puts the figure's mode
##  to 1, in which does not advance its
## animation (skipped) — the clip stands on its hit frame until
## the spell goes off, then plays to its end. A flier (locomotion 2) gets
## [no clip, C - L ticks][clip, L ticks]: the clip that was playing goes on
## and the cast clip starts C - L ticks late. Returns the clip's length.
func _cast_anim(clip: String, hold: int) -> float:
	_hold_left = 0.0
	_pre_left = 0.0
	_hold_clip = ""
	if model == null or not model.has_anim(clip):
		return 0.0
	var len := model.player.get_animation("ei/" + clip).length
	if hold > 0 and int(race.get("locomotion", 1)) == 2:
		_pre_left = hold * TICK
		_pre_clip = clip
		return len
	model.play(clip, 0.05, true)
	if hold > 0:
		var f := _clip_hit_frame(String(model.template).to_lower(), clip)
		_hold_clip = "ei/" + clip
		_hold_pos = float(f) / EIAnim.FPS if f >= 0 else len * 0.5
		_hold_left = hold * TICK
	return len


## When the blow lands: the strike action ends local_14 ticks
## after it starts, adding trunc(clip / the race's attack
## animation speed) — the.adb record's hit frame over creature
## (race_models anim_speeds[0], 1 for every race) — at least 1
## at the end -> the blow.
## Approx.: a cross clip played first (stance change) would add
## its ticks; no clip record -> half the clip as before.
func _hit_ticks() -> float:
	var clip := String(model.player.current_animation).trim_prefix("ei/") if model and model.player else ""
	var f := _clip_hit_frame(String(model.template).to_lower() if model else "", clip)
	if f < 0:
		var len := model.player.current_animation_length if model and model.player and clip != "" else 1.2
		return maxf(1.0, roundf(len * 0.5 / TICK))
	var sp: Array = Array(race.get("anim_speeds", [1.0]))
	var k := float(sp[0]) if not sp.is_empty() and float(sp[0]) != 0.0 else 1.0
	return float(maxi(1, int(float(f) / k)))


static var _hit_frames := {}


## The.adb clip record's hit frame (records of 88 bytes from 0x2c
## name in the first 16), -1 when unknown.
static func _clip_hit_frame(tmpl: String, clip: String) -> int:
	if tmpl == "" or clip == "":
		return -1
	if not _hit_frames.has(tmpl):
		var out := {}
		var arc := EIResArchive.open_path(GameData.root.path_join("res/database.res")) if GameData.root != "" else null
		var b := arc.read(tmpl + ".adb") if arc else PackedByteArray()
		if b.size() >= 0x2c and b.slice(0, 3).get_string_from_ascii() == "ADB":
			for i in b.decode_u32(4):
				var p := 0x2c + i * 88
				if p + 88 > b.size():
					break
				out[b.slice(p, p + 16).get_string_from_ascii()] = Vector2i(b.decode_s32(p + 0x20), b.decode_s32(p + 0x40))
		_hit_frames[tmpl] = out
	return _hit_frames[tmpl].get(clip, Vector2i(-1, -1)).y


## The.adb clip record's length and hit frame, -1 when unknown.
static func _clip_frames(tmpl: String, clip: String) -> Vector2i:
	if _clip_hit_frame(tmpl, clip) < 0:
		return Vector2i(-1, -1)
	return _hit_frames[tmpl][clip]


func _resolve_hit(t: GameUnit, roll := {}) -> void:
	if t == null or not is_instance_valid(t) or t.dead:
		return
	# No range check: the blow fires at the strike's end tick wherever the
	# target now stands (case 3
	# the target's with the stored roll).
	if stats.get("ranged", false):
		Projectile.launch(world, self, t, true).roll = roll
		if world.session:
			world.session.broadcast({"t": "arrow", "a": uid, "b": t.uid})
		world.combat.weapon_spell(self, t)
		return
	world.combat.melee(self, t, roll)
	world.combat.weapon_spell(self, t)
	stance = STANCE_NONE


## the original death rule. After a blow refolds the stats
## (: HP = max − Σ max × lethality × part damage fraction
## ) and, which kills when the stats
##   = says so: FISTP of the current HP (stats
## x87 round to nearest, ties to even) as a short, ≤ 0. So a unit dies
## below 0.5 HP (0.5 itself rounds to 0). There is no separate vital-part
## test: a destroyed head or torso (lethality 1.01) alone takes more than the
## whole maximum.
static func is_dying_hp(v: float) -> bool:
	return v <= 0.5


## `part` = body part index struck (hit_part()), -1 = whole body.
## `types`: the damage per type after armour (severing).
## `hit_flags`: hit-number labels (FlyingHP): 1 backstab.
func take_damage(amount: float, source: GameUnit, part := -1, types := PackedFloat32Array(), hit_flags := 0, layers := Callable(), owner_only := false) -> void:
	if dead:
		return
	if source and is_instance_valid(source):
		amount *= float(source.get_meta("coop_dmg_mul", 1.0))   # remake co-op MobScaling
	var hp_before := hp
	if part >= 0 and not parts.is_empty():
		var before := float(parts[part].cur)
		_hurt_part(part, amount, types)
		# blood from the struck part (visual only).
		var lost := before - float(parts[part].cur)
		if lost > 0.0 and world.session:
			world.session.broadcast({"t": "blood", "uid": uid, "part": part,
				"frac": lost / maxf(float(parts[part].max), 0.001)})
	else:
		body_damage(amount, layers)
	GameSound.impact(self, source, part, amount, not types.is_empty())
	# the hit number = health lost, truncated ("0" for a blow
	# that takes none); flag 2 for a strike on the head (FlyingHP).
	if world.session:
		world.session.broadcast({"t": "hitnum", "uid": uid, "n": int(maxf(hp_before - hp, 0.0)),
			"f": hit_flags | (2 if part == 0 else 0)})
	world.on_damage(self, amount, source)
	if is_dying_hp(hp):
		die(source)
		return
	if _anim_lock <= 0.0 and randf() < 0.5:
		_anim_lock = minf(model.act("hit", 1, 0.05), 0.6)
		action = "hit"
		GameSound.unit(self, "hit")
	# `owner_only`: a lasting spell's later ticks pass no attacker, only the
	# owner (with effect flag bit 0): the
	# experience still goes to the owner's party (param 3
	# ), but no hit hook / reaction runs.
	if owner_only:
		return
	# a blow that does not kill: a creature attacker's side goes
	# into this unit's own hostility mask ((attacker, victim)) unless
	# the diplomacy already makes it hostile — then the hit hook.
	if source and is_instance_valid(source) and source != self and source.faction != faction \
			and world.relation(faction, source.faction) != 2:
		world.ai._hate(self, source.faction)
	if controller < 0:
		world.ai.on_attacked(self, source)
	else:
		world.ai.on_player_attacked(self, source)


func die(killer: GameUnit = null) -> void:
	if dead:
		return
	dead = true
	orders.clear()
	order = {}
	path = PackedVector2Array()
	var len := model.act("death", 1, 0.05)
	action = "death"
	GameSound.unit(self, "death")
	if len > 0.0:
		var m := model
		get_tree().create_timer(len - 0.05).timeout.connect(func():
			if is_instance_valid(m) and m == model and dead:
				freeze_pose())
	died.emit(self)
	world.on_death(self, killer)


## Holds a corpse in its current (death) pose. The clip stays the player's
## current animation at speed 0 instead of being paused: a paused or finished
## AnimationPlayer reports no current_animation, and the unit panel's figure
## (Paperdoll.follow_pose, mirroring the hovered unit) then replayed the
## death clip from its start every time the corpse was hovered. `at_end`: the
## clip's last frame (corpses of a restored zone / a late joiner).
func freeze_pose(at_end := false) -> void:
	if model == null or model.player == null:
		return
	var p := model.player
	if at_end and p.assigned_animation != "":
		if not p.is_playing():
			p.play(p.assigned_animation, 0.0)
		# Just short of the end: reaching it would finish (stop) the clip.
		p.seek(maxf(p.current_animation_length - 0.001, 0.0), true)
	else:
		anim_flush()
		if not p.is_playing() and p.assigned_animation != "":
			var at := p.current_animation_position
			p.play(p.assigned_animation, 0.0)
			p.seek(at, true)
	p.speed_scale = 0.0
	_anim_acc = 0.0


func is_frozen() -> bool:
	return model != null and model.player != null and model.player.speed_scale == 0.0


## Back to life with full health (respawn, + full HP).
func revive() -> void:
	dead = false
	if _seq != 0:
		world.nav.rebucket(self)
	restore_parts()
	_hp = _max_hp
	mana = max_mana
	orders.clear()
	order = {}
	path = PackedVector2Array()
	buffs.clear()
	refresh_max_hp()
	if model:
		if model.player:
			model.player.speed_scale = 1.0
			model.player.play()
		model.act("idle", 1, 0.1)
	action = "idle"


## A unit put back dead from a save (CampaignState.restore_party_positions):
## its parts as they were, the death clip's last frame, no death sound.
func lie_dead() -> void:
	dead = true
	orders.clear()
	order = {}
	path = PackedVector2Array()
	action = "death"
	if model:
		model.act("death", 1, 0.0)
		freeze_pose(true)


## Remake option "revive" (Revive): back to life with `total` health. Every
## attached part gets the same damage fraction, so the unit's health
## (`_get_hp`: max − Σ max × lethality × fraction) is `total`; destroyed parts
## work again (state 3, a small positive health) and severed ones are put back
## the same way, as the only resurrection of the original does (the
## network respawn) — a severed head alone would otherwise keep the unit dead.
## Effects end and orders are dropped as at death; stamina stays as it was.
## The body gets up with the crawl-to-stand change clip when the figure has
## one (AC_CROSS from ST_LIE to ST_NEUTRAL), else it returns to its idle pose.
func rise(total := 1.0) -> void:
	dead = false
	if _seq != 0:
		world.nav.rebucket(self)
	orders.clear()
	order = {}
	path = PackedVector2Array()
	buffs.clear()
	refresh_max_hp()
	_anim_lock = 0.0
	total = minf(total, _max_hp)
	_hp = total
	if not parts.is_empty():
		var l := 0.0
		for p in parts:
			if p.state > 0:
				l += float(p.lethal)
		var f := clampf((_max_hp - total) / (_max_hp * l), 0.0, 0.999) if l > 0.0 and _max_hp > 0.0 else 0.0
		for p in parts:
			if p.state > 0:
				p.state = 3
				p.cur = float(p.max) * (1.0 - f)
		_wounds_dirty = true
		_pose_dirty = true
		_show_severed(0)
	action = "idle"
	if model:
		if model.player:
			model.player.speed_scale = 1.0
		var c := _cross_clip(EIUnitModel.ST_LIE, EIUnitModel.ST_NEUTRAL)
		if c != "":
			_anim_lock = _play_clip(c)
			action = "anim:" + c
		else:
			model.act("idle", 1, 0.2)


## Rebuilds the model with new armor/weapons (appearance follows equipment).
func set_equipment(armors: PackedStringArray, weapons: PackedStringArray) -> void:
	info.armors = armors
	info.weapons = weapons
	var m := EIUnitModel.create(info)
	if m == null:
		return
	if model:
		m.pose_state = model.pose_state
		m.pose_mod = model.pose_mod
		model.queue_free()
	model = m
	_wounds_dirty = true
	_pose_dirty = true
	add_child(model)
	model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	model.act_with_start("death" if dead else action.get_slice(":", 0) if not action.begins_with("anim:") else "idle", 1, 0.0)
	_anim_lod_setup()
	if dead:   # a re-dressed corpse lies as it was, without a second death
		freeze_pose(true)


## The model's AnimationPlayer is advanced from `_process` (manual mode), at
## the rates above; out-of-view steps are staggered between units.
func _anim_lod_setup() -> void:
	if model == null or model.player == null:
		return
	model.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_anim_roots.clear()
	for n in model.find_children("*", "BoneAttachment3D", true, false):
		if n is EIAnimPart and n.animation_parent == null:
			_anim_roots.append(n)
	_anim_acc = 0.0
	_anim_due = fposmod(uid * 0.0137, ANIM_OFFSCREEN_STEP)   # (not randf: the game's RNG)
	_geoms.clear()
	for g in model.find_children("*", "GeometryInstance3D", true, false):
		_geoms.append(g)
	_far = false
	if _screen == null:
		# The figure plus room for its shadow: 2.75 x its height at the lowest
		# sun (20 degrees, Game._update_daylight).
		_screen = VisibleOnScreenNotifier3D.new()
		_screen.name = "OnScreen"
		var h := maxf(2.5, 4.0 * figure_radius)
		var r := figure_radius + 2.75 * h + 1.0
		_screen.aabb = AABB(Vector3(-r, -1.0, -r), Vector3(2.0 * r, h + 2.0, 2.0 * r))
		add_child(_screen)
		# The figure itself (with a metre round it).
		_body = VisibleOnScreenNotifier3D.new()
		_body.name = "BodyOnScreen"
		var b := figure_radius + 1.0
		_body.aabb = AABB(Vector3(-b, -0.5, -b), Vector3(2.0 * b, h + 1.0, 2.0 * b))
		add_child(_body)


func _process(dt: float) -> void:
	if _screen == null:
		return
	# Wound layers from part health (every peer), redone when part health,
	# armour or the figure changed (_wounds_dirty).
	if _wounds_dirty:
		_wounds_dirty = false
		UnitWounds.update(self)
	# Out of view (box and shadow reach), the figure leaves the sun's shadow
	# casters (Game sets the sun's caster mask): neither it nor its shadow can
	# be seen, and a few hundred figures in the shadow splits cost more than
	# everything on screen.
	var far := not _screen.is_on_screen() and not _headless
	if far != _far:
		_far = far
		for g in _geoms:
			if is_instance_valid(g):
				g.layers = OFFSCREEN_LAYER if far else 1
	var now := _game_clock + Engine.get_physics_interpolation_fraction() * get_physics_process_delta_time()
	var game_dt := 0.0
	if _anim_clock < 0.0:
		_anim_clock = now
	elif now > _anim_clock:
		game_dt = now - _anim_clock
		_anim_clock = now
	game_dt = _pre_cast(game_dt)
	if model == null or model.player == null or not model.player.is_playing() or model.player.speed_scale == 0.0:
		_anim_acc = 0.0
		return
	_anim_acc += _held(game_dt * _anim_rate())
	# Walking units keep the full rate everywhere: GroundMarks places their
	# footprints at the clips' step frames from the posed feet.
	if pos != _anim_pos:
		_anim_pos = pos
		_anim_moving = 0.5
	else:
		_anim_moving -= dt
	var step := ANIM_OFFSCREEN_STEP
	if anim_watched:
		step = 0.0
	elif _anim_moving > 0.0:
		step = 0.0
		if not _screen.is_on_screen() and not _body.is_on_screen():
			var gs := GameSound.instance
			if gs and gs.mixer and Vector2(gs.mixer.listener.x, gs.mixer.listener.y).distance_squared_to(pos) \
					> ANIM_HEAR * ANIM_HEAR:
				step = ANIM_FAR_MOVE_STEP
	elif _body.is_on_screen():
		var cam := get_viewport().get_camera_3d()
		step = ANIM_FAR_STEP if cam and global_position.distance_squared_to(cam.global_position) \
			> ANIM_NEAR * ANIM_NEAR else 0.0
	elif _screen.is_on_screen():
		step = ANIM_SHADOW_STEP
	if step == 0.0:
		anim_flush()
		return
	_anim_due -= dt
	if _anim_due <= 0.0:
		_anim_due = maxf(_anim_due + step, 0.0)
		anim_flush()


## The playback factor of the playing clip: a walk / run / crawl clip runs at
## the unit's ground speed (the original, EIUnitModel.move_rate), so
## its feet keep to the ground; any other clip at the normal rate.
func _anim_rate() -> float:
	if model == null or not action in ["walk", "run", "crawl"]:
		return 1.0
	return model.move_rate(_move_speed)


## The cast clip's hold (_cast_anim): of `adv` seconds of clip time, the part
## that would carry the clip past its hold position is eaten by the hold
## until it is used up (the original skips the figure's advance
## while is 1).
func _held(adv: float) -> float:
	if _hold_left <= 0.0:
		return adv
	if String(model.player.current_animation) != _hold_clip:
		_hold_left = 0.0   # another clip took over (death, a new order)
		return adv
	var before := maxf(0.0, _hold_pos - (model.player.current_animation_position + _anim_acc))
	if adv <= before:
		return adv
	var eat := minf(adv - before, _hold_left)
	_hold_left -= eat
	return adv - eat


## A flier's cast clip starts after its hold (_cast_anim); the clip time
## past the start is returned.
func _pre_cast(game_dt: float) -> float:
	if _pre_left <= 0.0:
		return game_dt
	if not action.begins_with("cast") or dead:
		_pre_left = 0.0
		return game_dt
	_pre_left -= game_dt
	if _pre_left > 0.0:
		return game_dt
	var over := -_pre_left
	_pre_left = 0.0
	if model and model.has_anim(_pre_clip):
		model.play(_pre_clip, 0.05, true)
		_anim_acc = 0.0
	return over


## Cheap pre-test for picking: whether `p` can be on the figure at all (the
## screen box of a cube round the unit that holds it standing or lying).
func may_cover(cam: Camera3D, p: Vector2) -> bool:
	if _body == null:
		return true
	var h := _body.aabb.size.y
	var r := maxf(figure_radius, h) + 0.5
	var box := AABB(Vector3(-r, -0.5, -r), Vector3(2.0 * r, h + 0.5, 2.0 * r))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var gx := get_global_transform_interpolated()   # as drawn (phys_interp)
	for c in 8:
		var wp := gx * box.get_endpoint(c)
		if cam.is_position_behind(wp):
			return true
		var sp := cam.unproject_position(wp)
		lo = lo.min(sp)
		hi = hi.max(sp)
	return p.x >= lo.x and p.y >= lo.y and p.x <= hi.x and p.y <= hi.y


## Screen rectangles of the figure as drawn (the original
## Game.pick_unit): [union, part 1, part 2, ...], integer pixels; empty when
## nothing is drawn or a part is behind the camera.
func screen_rects(cam: Camera3D) -> Array:
	var out: Array = []
	if model == null or cam == null:
		return out
	var union := Rect2i()
	for g in _geoms:
		if not is_instance_valid(g) or not (g is MeshInstance3D) or not g.is_visible_in_tree():
			continue
		var mi: MeshInstance3D = g
		if mi.mesh == null:
			continue
		var box := mi.get_aabb()
		var xf := mi.get_global_transform_interpolated()   # as drawn (phys_interp)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in 8:
			var wp := xf * box.get_endpoint(c)
			if cam.is_position_behind(wp):
				return []
			var sp := cam.unproject_position(wp)
			lo = lo.min(sp)
			hi = hi.max(sp)
		# __ftol truncation of the min / max (SetRect).
		var r := Rect2i(Vector2i(int(lo.x), int(lo.y)), Vector2i(int(hi.x) - int(lo.x), int(hi.y) - int(lo.y)))
		if r.size.x <= 0 or r.size.y <= 0:
			continue   # UnionRect skips empty rectangles
		out.append(r)
		union = r if union.size == Vector2i.ZERO else union.merge(r)
	if out.is_empty():
		return out
	out.push_front(union)
	return out


## False only when the unit's box with a few metres round it is out of view
## (as of the last drawn frame); always true without a display.
func near_screen() -> bool:
	return _screen == null or _screen.is_on_screen() or _headless


## Applies the animation time not shown yet (before a pose is frozen).
func anim_flush() -> void:
	if _anim_acc > 0.0 and model and model.player:
		var a := _anim_acc
		_anim_acc = 0.0
		if _anim_roots.is_empty():
			model.player.advance(a)
			return
		EIAnimPart.batch = true
		model.player.advance(a)
		EIAnimPart.batch = false
		for r: EIAnimPart in _anim_roots:
			if is_instance_valid(r):
				r._apply_key()


func _set_action(a: String) -> void:
	# A unit that stays idle asks for the same pose every frame: when nothing
	# it depends on changed (stance, combat flag, part health, the figure and
	# its playing clip), the call would change nothing and is skipped. The
	# same for a unit that keeps walking / running / crawling (every physics
	# step of a move; EIUnitModel keeps a repeated cycle request as it is).
	if a == action and a in _STEADY and model and model.player and not _pose_dirty:
		if _idle_key.size() == 6 and _idle_key[0] == stance and _idle_key[1] == alert \
				and _idle_key[2] == model.get_instance_id() and _idle_key[3] == model.player.current_animation \
				and _idle_key[4] == model.pose_state and _idle_key[5] == model.pose_mod:
			return
	_pose_dirty = false
	action = a
	if model and not _update_pose():
		model.act_with_start(a)
	_idle_key = [stance, alert, model.get_instance_id(), model.player.current_animation, model.pose_state, model.pose_mod] \
		if a == action and a in _STEADY and model and model.player else []


const _STEADY := ["idle", "walk", "run", "crawl"]
## The next `_update_pose` puts the figure straight into its posture (no
## cross clip): a new unit, `restore_gait`, a quiet (joining) snapshot.
var _pose_snap := true


## The animation query of the stance: crawl = lie, kneel =
## warry, standing = attack when in combat stance (or for monsters, which
## have no relaxed clips), else neutral; walking with a wounded leg limps
## (: leg level DamageLevel2Value -> modifier 2, DamageLevel1Value -> 1).
## Returns true while a stance change clip plays (: standing
## still, the unit first plays the "cross" clip between the two stances).
func _update_pose() -> bool:
	if model == null or model.adb.is_empty():
		return false
	var st := EIUnitModel.ST_ATTACK
	if stance == STANCE_CRAWL:
		st = EIUnitModel.ST_LIE
	elif stance == STANCE_KNEEL:
		st = EIUnitModel.ST_WARRY
	elif resting and not alert:
		st = EIUnitModel.ST_REST
	elif not alert and model.neutral:
		st = EIUnitModel.ST_NEUTRAL
	if model.neutral and not parts.is_empty():
		var f := wound_factor(3)
		limp = 0 if f >= 1.0 else 2 if is_equal_approx(f, _wound_levels()[1]) else 1
	var md := EIUnitModel.MOD_1 * limp
	if _pose_snap:
		# A fresh figure, a load or zone entry, a late joiner's view: the
		# held posture's clip at once, no cross or movement start (the original
		#  sets the AI's posture and request
		# the unit's, so sees no change, and
		# plays the state's idle itself).
		_pose_snap = false
		if st != model.pose_state or md != model.pose_mod:
			model.pose_state = st
			model.pose_mod = md
			if not dead and action in _STEADY:
				model.act(action, 1, 0.0)
				if model.player:   # posed now, not at the figure's next (staggered) step
					model.player.advance(0.0)
		return false
	if st == model.pose_state and md == model.pose_mod:
		return false
	var old := model.pose_state
	model.pose_state = st
	model.pose_mod = md
	if dead or not action in ["idle", "walk", "run", "crawl"]:
		return false
	if st != old and action == "idle":
		var l := model.cross(old, st, "idle")
		if l > 0.0:
			if world and world.authority:
				_anim_lock = maxf(_anim_lock, l)
			return true
	# A posture change while moving (the original, the move mode
	#  == 0 and the posture int changed): the path is cut and the unit
	# stops where it is ((6)), then, unless the
	# order is an attack, the cross clip from the old posture to the new one
	# plays standing (mode 3); when it ends the
	# order is ticked again (case 3) and the move
	# re-plans from there. A combat-flag change alone (neutral ↔ attack) or a
	# gait change (walk ↔ run) neither stops nor crosses.
	if st != old and action in ["walk", "run", "crawl"] and _posture_of(st) != _posture_of(old):
		path = PackedVector2Array()
		_moving = false
		if order.get("type", "") != "attack":
			var l := model.cross(old, st, "idle")
			if l > 0.0:
				action = "idle"
				if world and world.authority:
					_anim_lock = maxf(_anim_lock, l)
				return true
	model.act_with_start(action)
	return false


## The posture of an animation state: lying (crawl), kneeling, standing
## (neutral and attack are one posture, int).
static func _posture_of(st: int) -> int:
	return 0 if st == EIUnitModel.ST_LIE else 1 if st == EIUnitModel.ST_WARRY else 4 if st == EIUnitModel.ST_REST else 2


## Shown again (UnitFog, a script's Hide / Show, a co-op snapshot, its world
## shown): the figure is re-placed where the unit stands now. While hidden,
## Godot's physics interpolation (SceneTreeFTI, Godot 4.7) does not carry the
## unit node's moves on to the figure's mesh nodes (interpolation off under
## the unit's on): their drawn transforms stayed where the unit was last
## shown, also after reset_physics_interpolation(), until the unit moved again.
## A boar that wandered in the fog was drawn at its old spot, an attack path
## led to where it really was, and it jumped there when it set off (user
## report, Retroid Pocket 5). Touching the figure's transform marks the whole
## subtree changed, so every mesh is drawn at the unit's current placement.
## (A signal, not _notification: that would be a script call per unit for
## every process / physics notification, in big fights too.)
func _on_visibility_changed() -> void:
	if is_inside_tree() and is_visible_in_tree():
		resync_drawn()


## The figure drawn where the unit stands, at once (no interpolation from an
## older placement): after a hide, a load, a placement.
func resync_drawn() -> void:
	if world and world.authority:   # (a co-op client's NetSmooth glide is left alone)
		_xf_pos = Vector2(INF, INF)   # _sync_transform's cache: place it again
		_sync_transform()
	if model:
		model.transform = model.transform   # re-places every part / mesh below
	reset_physics_interpolation()


func _sync_transform() -> void:
	if world == null:
		return
	# Only on change: a moved node re-places its whole part / mesh subtree.
	# Host: the same position, facing and ground as the last placement (and
	# the node still there) give the same transform; the ground lookup is
	# skipped (most units stand still).
	var t := world.terrain
	if world.authority and pos == _xf_pos and facing == _xf_facing and (t.get_instance_id() if t else 0) == _xf_tid \
			and (t == null or t.surface_rev == _xf_rev) and transform == _xf:
		return
	var p := pos if world.authority else net_view.step(pos, get_physics_process_delta_time())
	_drawn = p
	# Co-op client: the facing too is drawn turning between snapshots (NetSmooth).
	var yaw := facing if world.authority else net_view.step_yaw(facing, get_physics_process_delta_time())
	var xf := Transform3D(Basis(Vector3.UP, yaw + MODEL_YAW_OFFSET),
		EISpace.pos(p.x, p.y, world.ground_at(p.x, p.y)))
	if transform != xf:
		# A jump (placement, teleport, revive, a snapshot far off): drawn there
		# at once, not slid there over a physics step.
		var jump := transform.origin.distance_squared_to(xf.origin) > 4.0
		transform = xf
		if jump:
			reset_physics_interpolation()
	if world.authority:
		_xf_pos = pos
		_xf_facing = facing
		_xf_tid = t.get_instance_id() if t else 0
		_xf_rev = t.surface_rev if t else 0
		_xf = transform
	else:
		_xf_tid = -1
		_xf_pos = Vector2(INF, INF)


# _sync_transform's last host placement (pos, facing, terrain and its surface
# revision, the transform set).
var _xf_pos := Vector2(INF, INF)
var _xf_facing := 0.0
var _xf_tid := -1   # the terrain's instance id
var _xf_rev := 0
var _xf := Transform3D()


func _physics_process(_dt: float) -> void:
	_game_clock += _dt
	_sync_transform()
	#  takes the speed along the path spline where the unit is
	# drawn; here the distance covered in the step (a jump of more than 2 m,
	# a placement or teleport, counts as standing).
	var cur := pos if world == null or world.authority else _drawn
	var moved := cur.distance_to(_speed_from) if _speed_from != Vector2.INF else 0.0
	_move_speed = moved / _dt if _dt > 0.0 and moved <= 2.0 else 0.0
	_speed_from = cur
	#  sets / clears the combat flag by the command
	# force (== 3). A new command replaces the old one at once there
	# here it waits in `orders` while a clip runs (`order` empty), and an
	# attack waiting so is the command in force: clearing the flag in that
	# gap played the attack -> neutral cross clip and back on every repeated
	# attack click, and clicks a second apart kept the strike from starting.
	var cmd := order if not order.is_empty() or orders.is_empty() else orders[0]
	if alert and controller >= 0 and world and world.authority and cmd.get("type", "") != "attack":
		alert = false
	_update_pose()
	if not dead:
		_step_dist += pos.distance_to(_last_pos)
		if _step_dist > 1.6:
			_step_dist = 0.0
			GameSound.step(self)
	_last_pos = pos


## Compact replicated state for network snapshots: ..., mana (0.1 steps),
## each body part's HP as a byte (cur / max x 255), and the effective maximum
## HP and mana (clients build units from the prototype, without the host's
## hero stats and effects). Flags bits 14-18 carry the diplomacy faction
## (script SetPlayer), bits 19-22 the controlling player + 1 (orphaned heroes
## of a player who left are AI, -1), bit 23 the run gait, bit 24 the strike's miss. Element 11 lists the magic effects
## (buffs) as [name, until] or [name, until, sense, detect]: the unit panel's
## effect list and the client's own vision (eagle eye) need them. Remake-only
## wire format.
func snapshot() -> Array:
	var ph := PackedByteArray()
	for p: Dictionary in parts:
		ph.append(clampi(roundi(float(p.get("cur", 0.0)) / maxf(float(p.get("max", 1.0)), 0.001) * 255.0), 0, 255))
	# Co-op bandwidth: values on a binary grid fit 4-byte floats in var_to_bytes.
	return [uid, snappedf(pos.x, 1.0 / 64.0), snappedf(pos.y, 1.0 / 64.0), snappedf(facing, 1.0 / 256.0), action,
		snappedf(hp, 1.0 / 64.0), int(dead) | (int(hidden) << 1) | (severed_mask() << 2)
		| (int(alert) << 8) | (stance << 9) | (limp << 11) | (int(not aggressive) << 13)
		| (clampi(faction, 0, 31) << 14) | (clampi(controller + 1, 0, 15) << 19) | (int(gait_run) << 23)
		| (int(strike_miss) << 24) | (int(resting) << 25), snappedf(mana, 1.0 / 16.0), ph,
		snappedf(_max_hp, 1.0 / 16.0), snappedf(max_mana, 1.0 / 16.0), _buff_snapshot()]


func _buff_snapshot() -> Array:
	var out := []
	for k in buffs:
		var b: Dictionary = buffs[k]
		if b.has("sense") or b.has("detect"):
			out.append([String(k), snappedf(float(b.get("until", 0.0)), 0.1), b.get("sense", 0), b.get("detect", 0)])
		else:
			out.append([String(k), snappedf(float(b.get("until", 0.0)), 0.1)])
	return out


## `quiet`: the unit's state as found by a joining client (no death clip,
## sounds or hit numbers; a corpse lies already dead).
func apply_snapshot(s: Array, quiet := false) -> void:
	if s.size() > 10:
		if not is_equal_approx(_max_hp, s[9]):
			_set_max_hp(s[9])
		max_mana = s[10]
	pos = Vector2(s[1], s[2])
	facing = s[3]
	net_view.got(pos, quiet, facing)   # co-op client: drawn gliding / turning between snapshots (NetSmooth)
	if s[5] < hp - 0.01 and not quiet:
		GameSound.impact(self)
		if world:   # clients see hits only as health drops
			world.combat_event.emit("hp_loss", null, self, hp - s[5])
	hp = s[5]
	var flags: int = s[6]
	if (flags & 1) and not dead:
		dead = true
		action = "death"
		if quiet:   # as CampaignState.restore_zone poses the zone's dead
			model.act("death", 1, 0.0)
			freeze_pose(true)
		else:
			model.act("death", 1, 0.05)
			GameSound.unit(self, "death")
	elif not (flags & 1) and dead:
		revive()
	hidden = bool(flags & 2)
	visible = not hidden and not fogged
	_show_severed((flags >> 2) & 63, not quiet)
	if s.size() > 8:
		mana = s[7]
		var ph: PackedByteArray = s[8]
		for i in mini(ph.size(), parts.size()):
			parts[i].cur = ph[i] / 255.0 * float(parts[i].get("max", 1.0))
		_wounds_dirty = true
		_pose_dirty = true
	alert = bool(flags & 256)
	stance = (flags >> 9) & 3
	if quiet:   # found already in its posture (a joiner, a spawn record)
		_pose_snap = true
	limp = (flags >> 11) & 3
	aggressive = not (flags & 8192)
	faction = (flags >> 14) & 31
	controller = ((flags >> 19) & 15) - 1
	gait_run = bool(flags & (1 << 23))
	strike_miss = bool(flags & (1 << 24))
	resting = bool(flags & (1 << 25))
	if s.size() > 11:
		buffs.clear()
		for b: Array in s[11]:
			var d := {"until": float(b[1])}
			if b.size() > 3:
				if b[2] is Array: d.sense = b[2]
				if b[3] is Array: d.detect = b[3]
			buffs[String(b[0])] = d
	var a: String = s[4]
	if a != action and not dead:
		action = a
		if a.begins_with("anim:"):
			model.play(a.substr(5), 0.1)
		elif a.begins_with("revive:"):   # remake option "revive" (Revive): the held clip
			_keep_clip(a.get_slice(":", 1))
		elif a.begins_with("cast"):
			_update_pose()   # the snapshot's combat flag / posture first
			_cast_anim(_cast_clip(), int(a.get_slice(":", 1)) if a.contains(":") else 0)
		elif a == "attack":
			_update_pose()   # the snapshot's combat flag / posture first
			model.act("attack", randi_range(1, 3), 0.05)
			GameSound.unit(self, "attack")
		else:
			if a == "hit":
				GameSound.unit(self, "hit")
			_set_action(a)
