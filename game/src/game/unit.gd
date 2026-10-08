class_name GameUnit
extends Node3D
## A creature/character in the world. Simulation runs in EI coordinates (xy plane,
## z up) at a fixed tick on the host; clients only receive snapshots.

signal died(unit: GameUnit)

## Models face EI -Y at rest; facing angle 0 means looking along EI +X.
const MODEL_YAW_OFFSET := PI * 0.5
const TICK := 0.055            # the original logic tick, seconds (= 55 ms)
const ROTATE_SPEED_MULT := 100.0 # ai.reg RotateSpeedMult
const MotionSpline = preload("res://src/game/nav_spline.gd")
## Path node speeds are in 0.5 m AI cells per logic tick (: one
## tick advances v cells), so a speed value v is v x 0.5 / TICK metres per second.
const SPEED_SCALE := 0.5 / TICK
const ARRIVE := 0.15
const MeshScreenRect = preload("res://src/ui/mesh_screen_rect.gd")

## A broad perception row contains only these four state fields. Changing
## any of them invalidates it before the next query. The optional lifetime
## token invalidates native rows when this script instance is destroyed.
## Positions and diplomacy are still read at their original query points.
static var notice_revision := 0
## Registry eligibility changes independently of position/health/perception.
## This also catches a fixture freeing or reparenting a retained registry row.
static var structure_revision := 0
static var visibility_revision := 0
class StructureLifetime extends RefCounted:
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			GameUnit.structure_revision += 1
## Owner-free token also expires when a tool replaces this node's script.
var _structure_lifetime := StructureLifetime.new()
var _notice_lifetime: RefCounted = ClassDB.instantiate("UnitNoticeLifetime") \
	if ClassDB.class_exists("UnitNoticeLifetime") and not OS.get_cmdline_user_args().has("--ei-script-units") else null

## Native inputs stay attached to this script instance and follow public writes.
## Rich containers keep their live backing store; this is not a worker snapshot.
var _sim_lease: RefCounted
var _sim_state: RefCounted:
	set(value):
		if _sim_state != value:
			_sim_lease = null
			_sim_state = value

var world: GameWorld:
	set(value):
		if world != value:
			wake_presentation()
			world = value
			structure_revision += 1
var uid := 0:
	set(value):
		if uid != value:
			uid = value
			if _sim_state: _sim_state.update(&"uid", value)
			structure_revision += 1
var info := {}: # map record (EIMob object) or synthetic spawn data
	set(value):
		info = value
		if _sim_state: _sim_state.update(&"info", value)
var proto := {}: # monster_prototypes row
	set(value):
		proto = value
		if _sim_state: _sim_state.update(&"proto", value)
var race := {}          # race_models row
var faction := 0:   # diplomacy index (OBJ_PLAYER)
	set(value):
		if faction != value:
			faction = value
			if _sim_state: _sim_state.update(&"faction", value)
			notice_revision += 1
var controller := -1:   # player index, -1 = AI
	set(value):
		if controller != value:
			controller = value
			if _sim_state: _sim_state.update(&"controller", value)
			notice_revision += 1
var display_name := ""

## Setting it keeps the unit's spatial bucket (NavGrid.rebucket) exact, so
## nearby-unit queries see a unit moved outside its own tick (scripts,
## teleports, snapshots, placement) at once, as a scan of every unit would.
var pos := Vector2.ZERO:
	set(v):
		if _sim_state and pos != v: _sim_state.update(&"pos", v)
		pos = v
		if _seq != 0:
			world.nav.rebucket(self)
			if world.ai.activity.enabled:
				world.ai.activity.moved(self)
## Order of registration in GameWorld.units (0 = not in it): nearby-unit
## queries return units in this order, the order of a scan of `units`.
var _seq := 0:
	set(value):
		if _seq != value:
			_seq = value
			structure_revision += 1
## Co-op client: where the unit is drawn between the host's snapshots.
var net_view := NetSmooth.create()
var facing := 0.0:
	set(value):
		if facing != value:
			facing = value
			if _sim_state: _sim_state.update(&"facing", value)
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
var _max_hp := 10.0:
	set(value):
		if _max_hp != value:
			_max_hp = value
			if _sim_state: _sim_state.update(&"_max_hp", value)
## head, torso, right arm, left arm, right leg, left leg (race_models columns):
## {type: 0 skull / 1 torso / 2 arm / 3 leg, size, lethal, cur, max, state:
## 0 absent / 1 severed / 2 destroyed / 3 intact}.
const _EMPTY_PARTS: Array[UnitBodyPart] = []
var _parts: Array[UnitBodyPart] = _EMPTY_PARTS
var _parts_revision := UnitBodyPart.Revision.new()
var _health_revision := -1
var _health_max := NAN
var _health_value := 0.0
## Replace the roster as a whole; individual typed fields stay editable.
## Read-only membership prevents an untracked append/erase from staling health.
var parts: Array:
	get: return _parts
	set(records):
		var token := UnitBodyPart.Revision.new()
		var fresh: Array[UnitBodyPart] = []
		for row in records:
			fresh.append(UnitBodyPart.from_record(row.record() if row is UnitBodyPart else row, token))
		fresh.make_read_only()
		_parts = fresh
		_parts_revision = token
		_health_revision = -1
		_limbs.clear()
		_limb_revision = -1
var mana := 0.0
var max_mana := 0.0
var stats := {}: # to_hit, parry, dmg_min, dmg_max, absorption, reach, attack_time
	set(value):
		stats = value
		if _sim_state: _sim_state.update(&"stats", value)
var dead := false:
	set(value):
		if dead != value:
			dead = value
			if _sim_state: _sim_state.update(&"dead", value)
			notice_revision += 1
var hidden := false:
	set(value):
		if hidden != value:
			hidden = value
			if _sim_state: _sim_state.update(&"hidden", value)
			notice_revision += 1
var fogged := false   # out of this player's sight (UnitFog, client-side only)

# --- orders
var orders: Array[Dictionary] = []:
	set(value):
		orders = value
		if _sim_state: _sim_state.update(&"orders", value)
var order := {}:
	set(value):
		order = value
		if _sim_state: _sim_state.update(&"order", value)
var path := PackedVector2Array()
## The active motion consumes at most32 cells. The last cell
## is the first of the next chunk; the full remaining record stays available
## for future-position queries and the owner's path notification.
var _planned_motion := {}
var _motion_public_first := -1  # unchanged immutable remaining-cell suffix
var _motion_public_view := PackedVector2Array()
var _motion: MotionSpline
var _motion_cells: Array[Vector2i] = []
var _motion_values := PackedInt32Array()
var _motion_path := PackedVector2Array()
var _motion_goal := Vector2.ZERO
var _motion_offset := 0
var _motion_tick := 0.0
var _motion_base := 0.0
var _motion_turn := 0.0
var _motion_count := 0
## Draw-only use of the motion most recently accepted by the logic walker.
## A blocked / stopped unit cannot be extrapolated along its old path.
var _draw_motion_active := false
var _draw_line_goal := Vector2.INF
var _remote_move_speed := false
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
var stance := STANCE_NONE:
	set(value):
		if stance != value:
			stance = value
			if _sim_state: _sim_state.update(&"stance", value)
var sneaking: bool:
	get: return stance != STANCE_NONE
var mode := "standard": # AI mode: standard / sentry / guard / follow / fear / aggression / player
	set(value):
		if mode != value:
			mode = value
			if _sim_state: _sim_state.update(&"mode", value)
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
var _anim_lock := 0.0:
	set(value):
		if _anim_lock != value:
			_anim_lock = value
			if _sim_state: _sim_state.update(&"_anim_lock", value)
var _story_clip := ""     # a script clip whose completion the saved VM may await
## Native village talk checks the creature's current command
## (Stop 0 or Rest 11) and posted command (empty 9),.
## This is independent of the AI motivation, held Follow and stance clips.
var _talk_command := 0
var _talk_posted := 9
var _talk_remote_ready := true
var _pending_hit := {}:
	set(value):
		_pending_hit = value
		if _sim_state: _sim_state.update(&"_pending_hit", value)
## Authoritative death-queue ticks and the pool message's once flag. A
## corpse restored without this optional state remains quiet.
var _pool_left := -1
var _pool_sent := true
var _pool_step := -1
var _pool_checked_step := -1
var _step_dist := 0.0
var _last_pos := Vector2.ZERO
## Consecutive casts/strikes can keep the same action string between every
## network snapshot. A generation distinguishes a new action from a repeated
## state packet, so clients restart its clip exactly once.
var _action_serial := 0
var _remote_action_serial := -1
var action := "idle":
	set(value):
		if value != action or value in ["attack", "hit"] or value.begins_with("cast") or value.begins_with("anim:"):
			_action_serial += 1
		if _sim_state and action != value: _sim_state.update(&"action", value)
		action = value
## Combat stance (the original unit): set by an attack command
## (command 3). Humans then stand, walk and idle in the
## combat clips instead of the relaxed ones.
## run on every command tick: command 3 (attack) sets it, any
## other command clears it for a party unit (unit, the party, set)
## units outside a party keep it once set.
var alert := false:
	set(value):
		if alert != value:
			alert = value
			if _sim_state: _sim_state.update(&"alert", value)
var ai_next := 0.0      # world time of the unit's next AI tick (UnitAI)
var _perceive_next := 0.0   # next noticed-list update of a Player-motivation unit
var order_failed := false: # the last order ended unsuccessfully (creature)
	set(value):
		if order_failed != value:
			order_failed = value
			if _sim_state: _sim_state.update(&"order_failed", value)
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
			if resting and _talk_command == 0 and order.is_empty():
				_talk_command = 11
var buffs := {}: # name -> {until, _effect_ticks?, dmg_mul?, hp_mul?, actions_add?, regen_mul?, no_cast?, detect?, sense?, resist?, armor?}
	set(value):
		buffs = value
		if _sim_state: _sim_state.update(&"buffs", value)
const EFFECT_TICKS := "_effect_ticks"
## Old packet rows carried only an absolute deadline. Age their display from
## the received clock at this unit's last list replacement, not from later
## unrelated snapshot chunks. Canonical counts need neither anchor.
var _legacy_effect_at := 0.0
var _legacy_effect_step := 0
var _legacy_effect_received := false

# --- body and movement (the original unit radius; NavGrid stamps)
## 0.9 x the larger horizontal half-extent of the figure's bounding box
## (over figure, set).
var figure_radius := 0.5
var _radius_base := 0.5
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
var _path_limit := 1000000.0
var _plan_blocks := -1
var _plan_path := PackedVector2Array()
var _avoid_at := Vector2.INF
var _fresh_path := false     # a path planned round a blocker (_avoid), no step taken on it yet
var _wait_on: WeakRef        # creature, shared-target blocker
var _order_started_tick := -1000000 # last installed command, creature
var _arrive_t := 0.0         # estimated arrival at the attack target (unit-AI)
var _goal := Vector2.INF     # where the current attack path leads (unit-AI)
var _follow_n := 0           # Follow check counter (AI; 0 at AI init)
## Navigation's flat cost table (unit, initially 0).
## A move samples its starting water cell once; an attack
## approach sets it. Replans and AI spot tests keep that value.
## Preliminary move / interaction searches temporarily override it without
## changing the last order's value.
var path_flat_cost := false

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
## The figure and its action lock share the completed game clock. Real-time
## authority draws at the world's native tick+fraction; deterministic tools
## and snapshot clients retain their physics clock. Raw frame delta would
## let a clip finish on screen while its authoritative lock still held orders.
var _game_clock := 0.0
var _anim_clock := -1.0
var _frame_drawing := false
var _frame_priority_set := false
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
## The native spline's tangent length × node speed, in m/s. Clients receive
## this scalar; older snapshots retain their drawn-displacement fallback.
var _move_speed := 0.0
var _draw_move_speed := 0.0
var _speed_from := Vector2.INF
var _drawn := Vector2.ZERO
## Shown in the unit panel, whose figure mirrors this pose: full animation rate.
var anim_watched := false:
	set(value):
		anim_watched = value
		if value and _presentation_sleeping:
			wake_presentation()
var _anim_roots: Array[EIAnimPart] = []
## Render layer of out-of-view figures; the sun's shadow_caster_mask leaves it out.
const OFFSCREEN_LAYER := 1 << 19
var _geoms: Array[GeometryInstance3D] = []
var _far := false


func _init() -> void:
	visibility_changed.connect(_visibility_revision_changed)
	tree_entered.connect(_visibility_revision_changed)
	tree_exiting.connect(_visibility_revision_changed)
	if ClassDB.class_exists("UnitSimulationState") and not OS.get_cmdline_user_args().has("--ei-script-unit-state"):
		_sim_state = ClassDB.instantiate("UnitSimulationState")
		_sim_state.capture(self)
		_sim_lease = _sim_state.attach()


func _visibility_revision_changed() -> void:
	visibility_revision += 1


func setup(w: GameWorld, record: Dictionary) -> bool:
	record = CampaignState.map_unit_record(record)
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


##  5304a0 / 552fb0: use the authored FIG boxes at the
## loaded part origins. Render vertices, empty parts and part rotation do
## not replace the header geometry used by native movement classes.
func _measure_figure() -> void:
	var raw := EIFigureGeometry.of(model)
	var character := int(race.get("type_id",0)) == 0x32
	if raw.is_empty():
		figure_radius = 0.45 if character else 0.5
		_radius_base = figure_radius
		figure_half_z = 0.9
		_classes = [1,2,3]
		return
	_radius_base = (0.5 if character else maxf(raw.max.x,raw.max.y))*0.8999999761581421
	figure_radius = PackedFloat32Array([_radius_base])[0]
	figure_half_z = float(raw.max.z)
	if int(race.get("locomotion",1)) == 2:
		_classes = [0,0,0]
		return
	var width := 0.0
	var part: Node3D = model.find_child("bd",true,false)
	if part == null: part = model.find_child("chest",true,false)
	if part and part.has_meta(EIFigureGeometry.META):
		var g: Dictionary = part.get_meta(EIFigureGeometry.META)
		var hi: Vector3 = g.max
		width = sqrt(float(hi.x)*hi.x+float(hi.y)*hi.y)
		if int(race.get("type_id",0)) == 0x33 and model.template == "unmosp": width *= 2.0
	width = PackedFloat32Array([width])[0]
	var height := figure_half_z*2.0*float(race.get("head_height",1.0))
	if character: height = minf(PackedFloat32Array([height])[0],1.8899999856948853)
	_classes = [_class_of(width,height*0.20000000298023224),_class_of(width,height*0.6000000238418579),_class_of(width,height)]


## Movement class of a body: width <= 0.85: height < 0.6 -> 1
## < 1.2 -> 2, < 1.9 -> 3, else 4; width <= 1.5: height <= 1.7 -> 5, else 6;
## wider 7.
static func _class_of(width: float, height: float) -> int:
	if width > 1.5:
		return 7
	if width > 0.8500000238418579:
		return 5 if height <= 1.7000000476837158 else 6
	if height < 0.6000000238418579:
		return 1
	if height < 1.2000000476837158:
		return 2
	return 3 if height < 1.8999999761581421 else 4


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
var _radius_cached_base := NAN
var _radius_cached_party := false
var _radius_cached_high := false
var _radius_cached_value := 0.0

func body_radius() -> float:
	var party_unit := controller >= 0
	var high := move_class() == 0 and float(proto.get("altitude",0.0)) > 1.5
	if _radius_cached_base == _radius_base and _radius_cached_party == party_unit and _radius_cached_high == high:
		return _radius_cached_value
	_radius_cached_base = _radius_base
	_radius_cached_party = party_unit
	_radius_cached_high = high
	_radius_cached_value = 0.009999999776482582 if high else \
		float(PackedFloat32Array([minf(2.0, _radius_base + (0.20000000298023224 if party_unit else 0.0))])[0])
	return _radius_cached_value


##  stores the use radius separately from the
## movement radius; the party's extra0.2 does not enter it.
func use_radius() -> float:
	return PackedFloat32Array([figure_radius + 0.05000000074505806])[0]


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
	if t.is_empty():
		t = GameData.text("pers " + proto_name)
	return t.get_slice("\n", 0).strip_edges()


## A prototype's body build in the remake's (fat, muscle, height) order:
## monster_prototypes stores (muscle, fat, height) — the original puts
## fields 5 / 6 / 7 copies them to the
## figure's (muscle) / (fat) / (height).
static func proto_complexion(proto: Dictionary) -> Vector3:
	return Vector3(float(proto.get("complexion_y", 0.5)), float(proto.get("complexion_x", 0.5)),
		float(proto.get("complexion_z", 0.5)))


## Effective figure build; the record and trained/saved hero keep their base.
## Native 50f2d0 restores base first, then reads presence of effects 29/30
## (muscle ±0.4; creatures also height) and 37/38 (all axes). Powers and
## duplicate effects do not multiply the visual offset. Values have no top clamp.
static func buff_complexion(base: Vector3, type_id: int, effects: Dictionary) -> Vector3:
	var strength := int(effects.has("strength")) - int(effects.has("weak"))
	var size := int(effects.has("enlarge")) - int(effects.has("shrink"))
	var delta := float(strength + size if size != 0 else strength) * 0.4000000059604645
	if delta == 0.0:
		return base
	base.y = maxf(0.0, base.y + delta)
	if size != 0:
		base.x = maxf(0.0, base.x + delta)
	if size != 0 or type_id != 0x32:
		base.z = maxf(0.0, base.z + delta)
	return base


func figure_complexion() -> Vector3:
	var base: Vector3 = info.get("complexion", Vector3.ZERO)
	if base == Vector3.ZERO:
		base = proto_complexion(proto)
	return buff_complexion(base, int(race.get("type_id", 0)), buffs)


func figure_info() -> Dictionary:
	var shown := info.duplicate()
	shown.complexion = figure_complexion()
	# An actual effective zero build is not the absent-map-override sentinel.
	shown.effective_complexion = true
	return shown


## Refresh only when magic changed the build. Preserve the playing mixer,
## blend, queue and clock when the native translation height factor matches;
## otherwise restore the same clip/phase under the updated height factor.
func refresh_figure() -> void:
	if model == null:
		return
	if model.get_meta("complexion", Vector3.INF) == figure_complexion():
		return
	var shown := figure_info()
	# The replacement copies the old rig's current keys and transforms.
	# Materialize a hidden figure's deferred pose before reading those keys.
	model.flush_pending_pose()
	var m := EIUnitModel.create(shown, false, false)
	if m == null:
		return
	var old := model
	for property: String in ["pose_state", "pose_mod", "_current", "_cycle", "_cycle_pos", "_resume", "_resume_clip"]:
		m.set(property, old.get(property))
	var was_acc := _anim_acc
	var was_due := _anim_due
	add_child(m)
	m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if old.player and m.player and old.height_k == m.height_k:
		# The same player retains in-progress blending and method-track state.
		# Clear its node bindings after moving it to the replacement hierarchy.
		var fresh := m.player
		m.remove_child(fresh)
		fresh.free()
		if old.player.mixer_applied.is_connected(old._apply_morphs):
			old.player.mixer_applied.disconnect(old._apply_morphs)
		m.player = old.player
		old.player = null
		m.player.reparent(m, false)
		if not m._morph_parts.is_empty():
			m.player.mixer_applied.connect(m._apply_morphs)
		m.player.clear_caches()
		var batching := EIAnimPart.batch
		EIAnimPart.batch = true
		for n in old.find_children("*", "BoneAttachment3D", true, false):
			if n is EIAnimPart:
				var next := m.get_node_or_null(old.get_path_to(n)) as EIAnimPart
				if next:
					next.animation_key = n.animation_key
		for root: EIAnimPart in m._animation_roots:
			var previous := old.get_node_or_null(m.get_path_to(root)) as EIAnimPart
			if previous:
				root.position = previous.position
			root._apply_key()
		EIAnimPart.batch = batching
	elif old.player and m.player and old.player.assigned_animation != "":
		var clip := old.player.assigned_animation
		var at := old.player.current_animation_position
		m.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		m.player.speed_scale = old.player.speed_scale
		m.player.play(clip, 0.0)
		m.player.seek(at, true)
		for queued: String in old.player.get_queue():
			m.player.queue(queued)
		if not old.player.is_playing():
			m.player.pause()
	model = m
	remove_child(old)
	old.queue_free()
	_anim_lod_setup()
	_anim_acc = was_acc
	_anim_due = was_due
	_wounds_dirty = true
	_pose_dirty = true


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
	parts = []
	var records: Array = []
	_limbs.clear()
	var torso: Array = Array(race.get("torso", []))
	if torso.size() < 4 or float(torso[2]) <= 0.0:
		return
	for k: String in PART_KEYS:
		var r: Array = Array(race.get(k, []))
		var size := float(r[2]) if r.size() >= 4 else 0.0
		var t: int = PART_TYPES.get(String(r[0]) if r.size() else "none", -1)
		var m := _max_hp * size / float(torso[2])
		records.append({"type": t, "size": size, "lethal": float(r[3]) if r.size() >= 4 else 0.0,
			"sever": int(r[1]) if r.size() >= 4 else 0,
			"cur": m, "max": m, "state": 3 if size > 0.0 and t >= 0 else 0})
	parts = records


func _part_frac(p: UnitBodyPart) -> float:
	if p.cur < 0.0:
		return 1.0
	return (p.max - p.cur) / p.max


func _get_hp() -> float:
	if parts.is_empty():
		return _hp
	if _health_revision == _parts_revision.value and _health_max == _max_hp:
		return _health_value
	var lost := 0.0
	for p: UnitBodyPart in _parts:
		if p.state > 0:
			lost += _max_hp * p.lethal * _part_frac(p)
	_health_revision = _parts_revision.value
	_health_max = _max_hp
	_health_value = _max_hp - lost
	return _health_value


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
	for p: UnitBodyPart in parts:
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
	refresh_figure()


## health spread over the damaged, attached parts by lethality
## destroyed parts that climb above 0 work again.
func heal(amount: float) -> void:
	if parts.is_empty():
		_hp = minf(_max_hp, _hp + amount)
		return
	var w := 0.0
	for p: UnitBodyPart in parts:
		if p.state > 1 and p.cur < p.max:
			w += p.lethal
	if w <= 0.0:
		return
	for p: UnitBodyPart in parts:
		if p.state > 1 and p.cur < p.max:
			p.cur = minf(p.max, p.cur + amount / (w * _max_hp) * p.max)
			_wounds_dirty = true
			_pose_dirty = true
			if p.cur >= 0.001:
				p.state = 3


##  (respawn / resurrection): every attached part intact and full.
func restore_parts() -> void:
	for p: UnitBodyPart in parts:
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
	var p: UnitBodyPart = parts[i]
	if p.state < 2:
		return
	p.cur -= dmg
	_wounds_dirty = true
	_pose_dirty = true
	var sever: bool = p.cur < -5.0 * p.max
	for t in types.size():
		if types[t] >= p.max and int(p.sever) & (1 << t):
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
	for p: UnitBodyPart in parts:
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
	_refresh_limb_cache()
	if _wound_factors.has(type):
		return _wound_factors[type]
	var r := 1.0
	for p: UnitBodyPart in _limbs_of(type):
		if p.state != 0 and p.cur != p.max:
			r = minf(r, p.cur / p.max)
	var lv := _wound_levels()
	var result := lv[1] if r <= lv[0] else lv[3] if r <= lv[2] else 1.0
	_wound_factors[type] = result
	return result


var _limbs := {}   # part type -> typed body records (reset with the roster)
var _limb_revision := -1
var _limb_reg := {}
var _wound_factors := {}
var _leg_ratio := NAN


func _refresh_limb_cache() -> void:
	if _limb_revision == _parts_revision.value and is_same(_limb_reg, GameData.ai_reg):
		return
	_limb_revision = _parts_revision.value
	_limb_reg = GameData.ai_reg
	_limbs.clear()
	_wound_factors.clear()
	_leg_ratio = NAN


## The parts of one type in `parts` order (remembered until _init_parts).
func _limbs_of(type: int) -> Array:
	_refresh_limb_cache()
	var of_type = _limbs.get(type)
	if of_type == null:
		of_type = []
		for p: UnitBodyPart in parts:
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
	_refresh_limb_cache()
	if not is_nan(_leg_ratio):
		return _leg_ratio
	var r := 1.0
	for p: UnitBodyPart in _limbs_of(3):
		if p.state != 0:
			r = minf(r, p.cur / p.max)
	_leg_ratio = r
	return r


# ------------------------------------------------------------------ orders API

func command(o: Dictionary, queue := false) -> void:
	if dead:
		return
	if not queue:
		# A replacement order cancels the pending arrival interaction.
		# Callers attach the new interaction after posting its approach.
		remove_meta("interact")
		_wait_on = null
		orders.clear()
		order = {}
		path = PackedVector2Array()
	if o.get("type", "") != "wait":
		order_failed = false   # cleared by a new order
	if orders.is_empty():
		_talk_posted = _talk_order_command(o)
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
func attack(t: GameUnit, queue := false, aim := -1, run := false, path_notice := false) -> void:
	command({"type": "attack", "target": t, "aim": aim, "run": run, "path_notice": path_notice}, queue)


func is_idle() -> bool:
	return order.is_empty() and orders.is_empty() and _anim_lock <= 0.0


## The original village dialogue gate, not the simulation's is_idle().
## A scripted animation is command 10; an idle stance-cross remains Stop.
func village_talk_ready() -> bool:
	if world != null and not world.authority:
		return _talk_remote_ready
	return _talk_command in [0, 11] and _talk_posted == 9


static func _talk_order_command(o: Dictionary) -> int:
	match String(o.get("type", "")):
		"move": return 1
		"rotate": return 2
		"attack": return 3
		"cast": return 4
		"use": return 6
		"anim": return 10
		"wait": return 2 if o.has("face") else 0
		"follow": return 1 if o.get("once", false) else 0
	return 0


## Metres per second (moves along the path spline at the node
## speeds): base x the step's terrain factor.
## base (unit) = speed byte of the posture (: run
## walk, kneel, crawl) x 2/255 x factor byte
##  25.5, the bytes packed (race speed x 255/2
## tuning_move x the legs' wound factor x 25.5). The terrain
## factor: NavGrid.step_factor into the next cell. No spell
## enters it. Motion keeps one terrain / slope factor per native path node.
func speed() -> float:
	return _move_base() * SPEED_SCALE


##  packs the gait and legs' wound multiplier into bytes. Walk
## postures use the running base for rotation, while their translation walks.
func _move_base(for_turn := false) -> float:
	var _profile := world.profile_scope("unit_move_base", uid) if world and world.profile_simulation else null
	var s: Array = race.get("speeds", [0.4, 0.16])
	# race speeds: run, walk, sneak, crawl
	# no running while carrying more than the maximum load.
	var v: float = s[0] if running and not cannot_run() else s[1]
	if stance != STANCE_NONE and s.size() >= 4:
		v = s[2] if stance == STANCE_KNEEL else s[3]
	elif for_turn:
		v = float(s[0])
	var sb := mini(255, _fistp(v * 255.0 / 2.0))
	var fb := mini(255, _fistp(float(proto.get("tuning_move", 1.0)) * wound_factor(3) * 25.5))
	return sb * 2.0 / 255.0 * fb / 25.5


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

## The normal figure's eye point: half its
## height x 1.8, then posture. Native stores each intermediate as float32.
## Flying eye placement still uses the previous altitude approximation.
func eye_z(posture := true) -> float:
	var ground := world._stand_z(pos) if world else 0.0
	if has_meta("flying") or (move_class() == 0 and float(proto.get("altitude", 0.0)) >= 0.5):
		return ground + 1.5 * float(race.get("head_height", 1.0))
	var half_z := float(PackedFloat32Array([figure_half_z])[0])
	var offset := float(PackedFloat32Array([half_z * 1.7999999523162842])[0])
	if posture and (dead or stance == STANCE_CRAWL):
		offset = float(PackedFloat32Array([offset * 0.20000000298023224])[0])
	elif posture and stance == STANCE_KNEEL:
		offset = float(PackedFloat32Array([offset * 0.699999988079071])[0])
	return float(PackedFloat32Array([ground + offset])[0])

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
	var dark := world.darkness() if world else 0.0
	var weather := world.weather_sight_factor() if world else 1.0
	# The native crawling multiplier is exactly 1.0.
	return float(PackedFloat32Array([(1.0 - dark + dark * sense(1) * 0.009999999776482582) * weather])[0])


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

## Effect record+4 is a signed32-bit counter (688560/688510). Reject an
## optional malformed field without interpreting a float/bool/string as one.
static func valid_effect_ticks(value: Variant) -> bool:
	return value is int and value >= -0x80000000 and value <= 0x7fffffff


## Only old saved seconds very close to a complete tick can reconstruct an
## integer count. This is legacy migration, not recovery of an old packet's
## discarded0.1s precision or a replacement for the native update phase.
static func legacy_effect_ticks(seconds: float) -> int:
	if not is_finite(seconds) or seconds < 0.0 or seconds > float(0x7fffffff) * TICK:
		return -1
	var n := roundi(seconds / TICK)
	return n if absf(seconds - float(n) * TICK) <= maxf(0.0000001, absf(seconds) * 0.000000000001) else -1


## 646b50 reads record+4 directly. The client keeps zero until the host
## replaces its list. Unannotated old rows retain an explicit approximate
## deadline fallback, aged locally after their receipt.
func effect_ticks(code: String) -> int:
	var b: Dictionary = buffs.get(code, {})
	if valid_effect_ticks(b.get(EFFECT_TICKS)):
		return int(b[EFFECT_TICKS])
	var now := world.time if world else 0.0
	if world and not world.authority and _legacy_effect_received:
		now = _legacy_effect_at + float(world._client_effect_step - _legacy_effect_step) * TICK
	var left := maxf(float(b.get("until", now)) - now, 0.0)
	return int(left / TICK) if is_finite(left) else 0


## 52f7d0: the creature controller runs first; the attached model515820
## then decrements every record once, even on a dead unit.6884f0 is signed
## DWORD subtraction, and authority removes/refreshes a nonpositive result.
func _tick_effects() -> void:
	if world == null or not world.authority:
		return
	for code: String in buffs.keys():
		var b: Dictionary = buffs[code]
		if not valid_effect_ticks(b.get(EFFECT_TICKS)):
			continue
		var left := (int(b[EFFECT_TICKS]) - 1) & 0xffffffff
		if left > 0x7fffffff:
			left -= 0x100000000
		if left <= 0:
			buffs.erase(code)
			refresh_max_hp()
		else:
			b[EFFECT_TICKS] = left
			# Compatibility for existing absolute-deadline visual/save readers.
			# Applying before this unit phase consumes a tick immediately;
			# applying after it does not. No absolute clock snap defines phase.
			b.until = world.time + float(left) * TICK


## 510890: client presentation only. It decrements positive counters and
## retains zero records/stats until the authoritative list changes.
func client_tick_effects() -> void:
	for b: Dictionary in buffs.values():
		if valid_effect_ticks(b.get(EFFECT_TICKS)) and int(b[EFFECT_TICKS]) > 0:
			b[EFFECT_TICKS] = int(b[EFFECT_TICKS]) - 1


func tick(dt: float) -> void:
	var started := Time.get_ticks_usec() if world.profile_simulation else 0
	_moving = false
	_move_speed = 0.0
	_draw_motion_active = false
	_draw_line_goal = Vector2.INF
	if not dead:
		_tick(dt)
	else:
		_tick_blood_pool()
	if not buffs.is_empty():
		_tick_effects()
	if world.profile_simulation: world.profile_record("unit_logic",started,uid)
	started = Time.get_ticks_usec() if world.profile_simulation else 0
	world.nav.track_unit(self)
	if world.profile_simulation: world.profile_record("unit_stamp",started,uid)


func _tick(dt: float) -> void:
	var started := Time.get_ticks_usec() if world.profile_simulation else 0
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
	# Native54d960 compares integer ticks, including equality. Do not let
	# repeated55ms subtraction retain a positive floating-point remainder.
	# Negative elapsed deadlines remain negative for attack prediction.
	if absf(_attack_cd) <= 0.000000001:
		_attack_cd = 0.0
	if not buffs.is_empty():
		for b in buffs.keys():
			# Unannotated custom/ambiguous old deadlines keep their old path.
			# Native integer effects expire in the model phase AFTER commands.
			if not valid_effect_ticks(buffs[b].get(EFFECT_TICKS)) and world.time >= float(buffs[b].until):
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
		# Native549160 completes when the integer end counter is reached.
		if _pending_hit.t <= 0.000000001:
			var hit_target = _pending_hit.get("target")
			if is_instance_valid(hit_target) and hit_target is GameUnit:
				_resolve_hit(hit_target, _pending_hit.get("roll", {}))
			_pending_hit = {}
	if world.profile_simulation: world.profile_record("unit_housekeeping",started,uid)
	# The perception of a Player-motivation unit runs on every AI tick, busy,
	# walking or in a clip: the noticed list the
	# engage check reads (UnitAI.player_perceive).
	if (controller >= 0 or mode == "player") and world.time >= _perceive_next:
		_perceive_next = world.time + TICK - 0.0001
		world.ai.player_perceive(self)
	if _anim_lock > 0.0:
		_anim_lock -= dt
		return
	_story_clip = ""
	if _talk_command == 10 and order.is_empty():
		_talk_command = 11 if resting else 0
	if resting and not (order.is_empty() and orders.is_empty()):
		resting = false   # a new order ends the Rest order (0xb)
	if order.is_empty():
		if orders.is_empty():
			_talk_command = 11 if resting else 0
			_talk_posted = 9
			if world.time >= ai_next:
				world.ai.think(self)
			if orders.is_empty():
				_set_action("idle")
				return
		order = orders.pop_front()
		_order_started_tick = roundi(world.time / TICK)
		_wait_on = null
		path = PackedVector2Array()
	elif controller < 0 and world.time >= ai_next and order.get("calm", false):
		world.ai.think(self)   # a calm motivation's walk: the AI keeps choosing
		if order.is_empty() and not orders.is_empty():
			order = orders.pop_front()
			_order_started_tick = roundi(world.time / TICK)
			_wait_on = null
			path = PackedVector2Array()
	elif controller < 0 and world.time >= ai_next and not order.get("ai", false) and world.ai.calm_tick(self):
		return   #  cast a buff / heal over the calm walk
	elif controller >= 0 and order.has("swarm") and world.ai.swarm_tick(self):
		return   # Ctrl / aimed-key ground click (packet 0x3a): engages on the way
	elif controller >= 0 and order.get("type", "") == "follow" and not order.get("once", false) \
			and world.ai.follow_engage(self):
		return   # F order (Player motivation state 6): engages while following
	_talk_command = _talk_order_command(order)
	_talk_posted = 9
	match order.type:
		"move": _do_move(dt)
		"attack": _do_attack(dt)
		"follow":
			_do_follow(dt)
			# Follow is an AI state: only its actual move is command 1.
			_talk_command = 1 if order.get("once", false) or order.has("walk") else 0
		"wait":
			_set_action("idle")
			if order.has("face") and not _turn_to(float(order.face), dt):
				return
			_talk_command = 0
			order.t = float(order.get("t", 1.0)) - dt
			if order.t <= 0.0:
				order = {}
		"anim":
			_story_clip = String(order.name) if order.get("story", false) else ""
			_anim_lock = model.act(order.name, int(order.get("variant", 1)), 0.1) if not model.has_anim(order.name) \
				else _play_clip(order.name)
			action = "anim:" + String(order.name)
			order = {}
		"rotate":
			if _turn_to(float(order.angle), dt, float(order.get("turn_speed", 0.0))):
				order = {}
		"cast": _do_cast(dt)
		"use": _do_use(dt)
		_: order = {}
	if order.is_empty() and _anim_lock <= 0.0:
		_talk_command = 11 if resting else 0
	if not orders.is_empty():
		_talk_posted = _talk_order_command(orders[0])


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
	var _profile := world.profile_scope("unit_do_move", uid) if world and world.profile_simulation else null
	var use_target: Node3D = world.objects.get(int(order.get("use_object", 0)))
	if order.has("use_object") and (use_target == null or not world.lever_sys.usable(int(order.use_object))):
		remove_meta("interact")
		_fail_order(EIAcks.NO_PATH)
		return
	if not order.has("cost_started"):
		path_flat_cost = order.has("use_object") or world.nav.cell_wet(pos)
		order.cost_started = true
	# A player's move order runs by the unit's gait (: == 3)
	# or its double-click flag (standing only); script / AI moves
	# carry their own run flag.
	if order.get("gait", false):
		running = stance == STANCE_NONE and (gait_run or bool(order.get("run", false)))
	else:
		running = bool(order.get("run", true))
	if path.is_empty():
		var replan := _avoid != null and is_instance_valid(_avoid)
		if order.get("story_move", false) and not world.prepare_story_move(self, order.to):
			_set_action("idle")
			return
		# The stick's moves ("line", remake): the straight line when it can
		# be walked as it is (NavGrid.direct_line), else the path search.
		if order.get("line", false) and not replan and world.nav.direct_line(self, order.to):
			path = PackedVector2Array([order.to])
		if path.is_empty():
			# Native554830 plans every new move. The nav memo validates standing
			# stamps; even identical cells need a fresh physical motion anchor.
			path = _path_to(order.to)
		if use_target:
			motion_notice(order.to, 1, world.vm._interact_reach(self, use_target))
		else:
			motion_notice(order.to, 0)
		if path.is_empty():
			if order.has("use_object"):
				remove_meta("interact")
			_fail_order(EIAcks.NO_PATH)
			return
		_fresh_path = replan
	if _step_along_path(dt):
		order = {}


## Empty compatibility slot cleared by NavGrid._relocate after object changes.
## New move commands use the nav memo rather than retaining a unit-local suffix.
var _kept := {}


## A path to `to` for this unit: its own stamp and that of `t` (an attack
## target) lifted, and a unit it bumped into stamped (see NavGrid.find_path).
## Unit-target interaction searches temporarily use the flat table; a plain
## search keeps the last order's table. `flat_override` is for a preliminary
## move search: the current wet cell, restored after the query.
func _path_to(to: Vector2, t: GameUnit = null, flat_override := -1, limit := 1e6) -> PackedVector2Array:
	var moving_at := _avoid_at
	_avoid = null;_avoid_at = Vector2.INF
	var found: PackedVector2Array
	if order.has("use_object"):
		var plan := world.nav.find_object_path(self, to, int(order.use_object), limit, moving_at)
		found = plan.path
		_planned_motion = plan.motion
		_plan_blocks = int(plan.blocks)
	else:
		found = world.nav.find_path(pos, to, [self, t] if t else [self], [], 0.0, move_class(),
			bool(flat_override) if flat_override >= 0 else (t != null or path_flat_cost),NAN,limit,0.0,controller < 0,moving_at)
		_plan_blocks = world.nav.last_block_count
		_planned_motion = world.nav.motion_record(pos, found, move_class(), has_meta("flying"))
	_path_limit = limit
	_plan_path = found
	_planned_motion.path = found
	_planned_motion.from = pos
	return found


func _ensure_motion() -> bool:
	var _profile := world.profile_scope("unit_ensure_motion", uid) if world and world.profile_simulation else null
	if path.is_empty():
		_motion = null
		return false
	var base := _move_base()
	var turn := _move_base(true) * ROTATE_SPEED_MULT
	# A successful query resets the active record even when its remaining
	# cells match (native5bb190 ->5c7d50/5c7b00). Its physical start and
	# heading may have changed since this spline was built.
	if _planned_motion.is_empty() and _motion != null and _motion_path == path \
			and _motion_base == base and _motion_turn == turn:
		return true
	var record := _planned_motion
	_planned_motion = {}
	if record.is_empty() or record.get("path") != path or record.get("from") != pos:
		record = world.nav.motion_record(pos, path, move_class(), has_meta("flying"))
	_motion_cells.assign(record.get("cells", []))
	_motion_values = record.get("values", PackedInt32Array())
	_motion_goal = path[-1]
	_motion_path = path
	_motion_public_first = -1
	_motion_public_view = PackedVector2Array()
	_motion_offset = 0
	_motion_base = base
	_motion_turn = turn
	_build_motion(pos, facing)
	return _motion != null


func _build_motion(from: Vector2, angle: float) -> void:
	_motion_count = mini(32, _motion_cells.size() - _motion_offset)
	_motion_tick = 0.0
	if _motion_count <= 0:
		_motion = null
		return
	var cells: Array[Vector2i] = []
	cells.assign(_motion_cells.slice(_motion_offset, _motion_offset + _motion_count))
	var end := _motion_goal if _motion_offset + _motion_count == _motion_cells.size() \
		else NavGrid.center(cells[-1])
	_motion = MotionSpline.new()
	_motion.build(from, end, cells, _motion_values.slice(_motion_offset, _motion_offset + _motion_count),
		_motion_base, _motion_turn, angle)


## Full original cell record, as the ghost / future-position query receives
## it. Internal full_path orders preserve the native1e6 ghost cutoff.
func motion_notice(at: Vector2, mode: int, reach := -1.0, full_path := false) -> void:
	if not order.get("path_notice", false) or world == null or world.session == null:
		return
	order.erase("path_notice")
	var record := _planned_motion if _planned_motion.get("path") == path and _planned_motion.get("from") == pos \
		else world.nav.motion_record(pos, path, move_class(), has_meta("flying"))
	var cells: Array = []
	for c: Vector2i in record.cells:
		cells.append([c.x, c.y])
	var failed := path.is_empty()
	var ray := _ghost_ray(at,full_path)
	var already := reach >= 0.0 and _ghost_in_range(pos,at,reach,ray)
	var ring := 0
	var f := 1000000.0
	if reach < 0.0:
		if not failed:
			ring = int(path[-1].distance_squared_to(at) >= pos.distance_squared_to(at) * 0.01)
	elif already:
		mode = 3
		cells.clear()
	elif failed:
		mode = 3
		ring = 1
	else:
		ring = int(not _ghost_in_range(path[-1],at,reach,ray))
		# Native54e600 calls54e250 only for an endpoint that can perform
		# the action. A failed endpoint and restored full-path order keep1e6.
		if ring == 0 and not full_path:
			f = _ghost_cutoff(record,at,reach,ray)
	if failed and not already:
		mode = 3
		ring = 1
	world.session.broadcast({"t": "order_path", "to": controller, "uid": uid,
		"start": [pos.x, pos.y], "target": [at.x, at.y], "end": [path[-1].x, path[-1].y] if not failed else [pos.x, pos.y],
		"heading": facing, "mode": mode, "cross": ring, "cells": cells, "values": Array(record.values), "ticks": f})


## Native54bcb0: attack/use rays to a creature allow the10m² overlap;
## traced spells require their prototype flag, with summed body radii+0.3.
## Point spells trace to ground+1. The ghost carries no independent pose.
func _ghost_ray(at: Vector2,full_path: bool) -> Dictionary:
	if full_path: return {}
	var target := _order_target()
	var casting: bool = order.get("type","") == "cast"
	if casting and int(Spells.parse(String(order.get("spell",""))).proto.get("require_trace",0)) == 0:
		return {}
	if target == null and not casting: return {}
	var overlap := 0.0
	var point := at
	var z := float(PackedFloat32Array([world.ground_at(at.x,at.y)+1.0])[0])
	if target:
		point = target.pos
		z = target.eye_z()
		if casting:
			var radius := float(PackedFloat32Array([body_radius()+target.body_radius()+0.3])[0])
			overlap = float(PackedFloat32Array([radius*radius])[0])
		else:
			overlap = 10.0
	return {"point":point,"z":z,"overlap":overlap,"eye":_ghost_eye_offset()}


## Native530370 uses authored bounds, without crouch/death eye scaling.
func _ghost_eye_offset() -> float:
	var raw := EIFigureGeometry.of(model)
	if raw.is_empty():
		return float(PackedFloat32Array([figure_half_z*1.7999999523162842])[0])
	return float(PackedFloat32Array([float(raw.max.z)*1.7999999523162842 if int(raw.flags)&2 else float(raw.radius)*0.7+raw.centre.z])[0])


func _ghost_in_range(point: Vector2,at: Vector2,reach: float,ray: Dictionary) -> bool:
	var range2 := float(PackedFloat32Array([reach*reach])[0])
	if point.distance_squared_to(at) > range2: return false
	if ray.is_empty() or point.distance_squared_to(ray.point) < float(ray.overlap): return true
	var z := float(PackedFloat32Array([world._stand_z(point)+float(ray.eye)])[0])
	return world.terrain_ray(point,z,ray.point,float(ray.z)) >= 0.1


## Complete54e250: the native0.5-base spline sampled every five ticks,
## stopping only at a repeated position or a feasible in-range sample.
func _ghost_cutoff(record: Dictionary,at: Vector2,reach: float,ray: Dictionary) -> float:
	if record.cells.is_empty(): return 0.0
	var spline := MotionSpline.new()
	spline.build(pos,path[-1],record.cells,record.values,0.5,1e10,facing)
	var f := 0.0
	var previous := Vector2.INF
	while true:
		var current: Vector2 = spline.sample(f).p
		if current == previous or _ghost_in_range(current,at,reach,ray): return f
		previous = current
		f += 5.0
	return f


## Returns true when the path end is reached. Every step is first checked
## against the other units (NavGrid.step_blocker, the original): a
## standing blocker makes the unit plan anew round it; a moving one makes it
## wait (stand) this tick — it then counts as standing to the other, which
## goes round — unless this unit is the faster: it then plans round the
## blocker's spot. Two attackers of one target, this one more
## than sqrt(60) m from it, queue instead (unit-AI).
## Units never push each other.
func _step_along_path(dt: float) -> bool:
	var _profile := world.profile_scope("unit_step_along_path", uid) if world and world.profile_simulation else null
	# Straight stick movement is an explicit remake input mode. Ordinary
	# commands use the original cell spline, including its initial turn hold.
	if order.get("line", false) and path.size() == 1:
		return _step_line_path(dt)
	if not _ensure_motion():
		return true
	_draw_motion_active = true
	var from := pos
	var left := maxf(0.0, dt / TICK)
	# Positive time samples its destination inside the loop. Only a zero
	# step needs the current sample for the remaining path and draw speed.
	var sample: Dictionary = _motion.sample(_motion_tick) if left <= 0.0 else {}
	while left > 0.0:
		var remaining := maxf(0.0, _motion.duration - _motion_tick)
		var step := minf(left, remaining)
		var next := _motion.sample(_motion_tick + step)
		var q: Vector2 = next.p
		if q.distance_squared_to(pos) > 0.00000001:
			var res := {}
			var b := world.nav.step_blocker(self, q, res, next.cell)
			if b:
				_blocked_by(b, bool(res.standing),q)
				_move_speed = 0.0
				_draw_motion_active = false
				return false
			_moving = true
			_fresh_path = false
			pos = q
		var tangent: Vector2 = next.d
		if tangent != Vector2.ZERO:
			facing = tangent.angle()
		_motion_tick += step
		left -= step
		sample = next
		if _motion_tick + 0.0000001 < _motion.duration:
			break
		if _motion_offset + _motion_count == _motion_cells.size():
			path = PackedVector2Array()
			_motion_path = path
			_motion = null
			_move_speed = 0.0
			break
		_motion_offset += _motion_count - 1
		_build_motion(pos, facing)
		sample = _motion.sample(0.0) if left <= 0.0 else {}
	# Remaining public cells are kept for command reach checks and save/debug
	# tools. An in-place public edit is restored as by the scalar rebuild;
	# replacing the path invalidates _ensure_motion's active record.
	if _motion != null:
		var first := _motion_offset + maxi(0, int(sample.index) - 1)
		# Most ticks stay on the same node. Its remaining public cells are
		# immutable until that index changes; fresh motion always invalidates
		# this view, including a replan to the same cells from another point.
		if first != _motion_public_first or path != _motion_public_view:
			path = PackedVector2Array()
			for c: Vector2i in _motion_cells.slice(first):
				path.append(NavGrid.center(c))
			path[-1] = _motion_goal
			_motion_path = path
			_motion_public_first = first
			_motion_public_view = path.duplicate()
		_move_speed = (sample.d as Vector2).length() * float(sample.v) * SPEED_SCALE
	var arrived := path.is_empty()
	if not _moving or arrived and pos.distance_to(from) < 0.01:
		if not arrived:
			_set_action("idle")
		return arrived
	_walk_action()
	return arrived


func _step_line_path(dt: float) -> bool:
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
			_blocked_by(b, bool(res.standing),q)
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
	_move_speed = speed() if _moving and not arrived else 0.0
	_draw_line_goal = path[0] if path.size() == 1 and _moving else Vector2.INF
	if arrived and pos.distance_to(from) < 0.01:
		return true   # already there: no walk clip for an order that ends at once
	_walk_action()
	return arrived


func _walk_action() -> void:
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


func _blocked_by(b: GameUnit, standing: bool, next := Vector2.INF) -> void:
	var kind: String = order.get("type","")
	var t: GameUnit = _order_target() if kind in ["attack","cast"] else null
	var party := XpRules.party_of(self)
	#  first lets a newly commanded leader wait for its own
	# follower. The followed unit is looked up on the BLOCKER's Player AI.
	if party >= 0 and XpRules.party_of(b) == party and b._held_follow_target() == self \
			and _order_started_tick + 2 > roundi(world.time / TICK):
		_set_action("idle")
		return
	if _waiting_for() == b:
		_set_action("idle")
		return
	var queue: bool = t != null \
		and b.order.get("type","") in ["attack","cast"] and b.order.get("target") == t \
		and b.faction == faction and b.move_class() == move_class() and dist3(t)*dist3(t) > 60.0 \
		and not (b.action == "attack" and b._anim_lock > 0.0)
	var temporary_moving := false
	if queue:
		var cursor: GameUnit = b
		var visited := {}
		while cursor != null and not visited.has(cursor):
			visited[cursor] = true
			cursor = cursor._waiting_for()
			if cursor == self:
				# Cancel both ends before rebuilding around the moving layer.
				b._wait_on = null
				_wait_on = null
				temporary_moving = true
				break
		if not temporary_moving:
			_wait_on = weakref(b)
			_set_action("idle")
			return
	if temporary_moving or standing or speed() > b.speed():
		var goal: Vector2 = path[-1] if not path.is_empty() else order.get("to",pos)
		_avoid = b
		_avoid_at = next if temporary_moving or not standing else Vector2.INF
		path = _path_to(goal,_order_target() if kind in ["attack","cast","follow"] else null,-1,_path_limit)
		if path.is_empty():
			_fail_order(EIAcks.NO_WAY_TO_ATTACK if kind == "attack" else EIAcks.NO_PATH)
			if kind == "attack": target = null;_goal = Vector2.INF
	_set_action("idle")


func _waiting_for() -> GameUnit:
	var unit = _wait_on.get_ref() if _wait_on else null
	return unit if is_instance_valid(unit) and unit is GameUnit and not unit.dead else null


## a queued type6 motivation is preferred, then current
## Player Follow state6. The follow target survives an intervening attack.
func _held_follow_target() -> GameUnit:
	if controller < 0 and mode != "player":
		return null
	for o: Dictionary in orders:
		if o.get("type","") == "follow" and not o.get("once",false):
			var unit = o.get("target")
			if is_instance_valid(unit) and unit is GameUnit:
				return unit
	if order.get("type","") == "follow" and not order.get("once",false):
		return _order_target()
	return null


## Where the unit will be `dist` metres further along its path.
func pos_ahead(dist: float) -> Vector2:
	if not path.is_empty() and not order.get("line", false) and _ensure_motion():
		return _motion_future(maxf(dist, 0.0) / maxf(speed() * TICK, 0.000001))
	var p := pos
	for q in path:
		var l := p.distance_to(q)
		if l >= dist:
			return p + (q - p) / l * dist if l > 0.0 else p
		dist -= l
		p = q
	return p


func _turn_to(ang: float, dt: float, turn_speed := 0.0) -> bool:
	var diff := wrapf(ang - facing, -PI, PI)
	var step := (_move_base(true) * ROTATE_SPEED_MULT / TICK if turn_speed == 0.0 else turn_speed) * dt
	if absf(diff) < step or turn_speed == 0.0 and absf(diff) == step:
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
		motion_notice(t.pos, 1, dist, bool(order.get("full_path", false)))
		path = PackedVector2Array()
		_set_action("idle")
		if order.get("once", false):
			order = {}
		return
	_repath -= dt
	if path.is_empty() or _repath <= 0.0:
		path = _path_to(t.pos, t)
		_repath = 0.5
		motion_notice(t.pos, 1, dist, bool(order.get("full_path", false)))
		if path.is_empty():
			_fail_order(EIAcks.NO_PATH)
			return
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
		path = _path_to(order.walk,null,-1,float(order.get("walk_limit",1000000.0)))
		if path.is_empty() or not path_fits(path, order.walk, float(order.get("walk_limit", 1000000.0))):
			path = PackedVector2Array()
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
## The move keeps its search limit for every replan. The preliminary aside
## test compares result (float cell-space goal) × 0.5 with c.
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
				_follow_walk(p5, 3.0 * d + 10.0)
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
		_follow_walk(t.pos, 3.0 * d + 10.0)
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
	var p := _path_to(c, null, int(world.nav.cell_wet(pos)),10.0)   # preliminary move
	if not p.is_empty() and p[-1].distance_squared_to(c) < 0.1 and path_fits(p, c, 10.0):
		_follow_walk(c, 10.0, p)
	elif goal.distance_squared_to(p40) > 0.5:
		_follow_walk(p40, 20.0)
	else:
		return
	_follow_n = 6


## The follower's move: a new goal, planned afresh.
func _follow_walk(to: Vector2, limit := 1000000.0, p := PackedVector2Array()) -> void:
	order.walk = to
	order.walk_limit = limit
	path_flat_cost = world.nav.cell_wet(pos)
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
	if not order.get("line", false) and _ensure_motion():
		return _motion_future(maxi(0, ticks))
	return pos_ahead(speed() * maxi(0, ticks) * TICK)


func _motion_future(ticks: float) -> Vector2:
	return _motion_future_sample(ticks).p


## Pure coefficient sampling. In particular the render caller neither
## calls _ensure_motion nor consumes public path cells or changes stamps.
func _motion_future_sample(ticks: float) -> Dictionary:
	if _motion == null:
		return {"p": pos, "d": Vector2.from_angle(facing), "v": 0.0}
	var spline := _motion
	var at := _motion_tick + ticks
	var offset := _motion_offset
	var count := _motion_count
	while offset + count < _motion_cells.size() and at > spline.duration:
		at -= spline.duration
		var end := spline.sample(spline.duration + 0.000001)
		offset += count - 1
		count = mini(32, _motion_cells.size() - offset)
		var cells: Array[Vector2i] = []
		cells.assign(_motion_cells.slice(offset, offset + count))
		spline = MotionSpline.new()
		spline.build(end.p, _motion_goal if offset + count == _motion_cells.size() else NavGrid.center(cells[-1]),
			cells, _motion_values.slice(offset, offset + count), _motion_base, _motion_turn, (end.d as Vector2).angle())
	return spline.sample(at)


func _draw_motion_sample(fraction: float) -> Dictionary:
	if _draw_motion_active and _motion != null and not path.is_empty() and _motion_path == path:
		return _motion_future_sample(fraction)
	if _draw_line_goal != Vector2.INF and path.size() == 1 and path[0] == _draw_line_goal \
			and order.get("line", false):
		var direction := (_draw_line_goal - pos).normalized()
		return {"p": pos.move_toward(_draw_line_goal, _move_speed * TICK * fraction),
			"d": direction, "v": _move_speed / SPEED_SCALE}
	return {}


## both intermediate values are stored as float32, then
## FISTP rounds the result nearest-even. Unarmed tuning first uses __ftol.
static func _strike_delay_ticks(base: float, act: float, armed := true) -> int:
	var factor := float(PackedFloat32Array([act])[0])
	if factor != 0.0:
		factor = float(PackedFloat32Array([15.0 / factor])[0])
	var value := int(base) if armed else int(PackedFloat32Array([base])[0])
	return _fistp(float(PackedFloat32Array([float(value) * factor])[0]))


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
	# A party unit's aligned, standing melee query can test the selected clip's
	# impact tick directly. Do not reject this branch against
	# today's blocker positions before it reaches that query. Outside the
	# native10m² ray overlap, or for flying bodies, keep the current gate:
	# full turn search / relative height / optional ray remain separate work.
	var impact_query: bool = controller >= 0 and not ranged and stance == STANCE_NONE and _attack_cd <= 0.0 \
		and not bool(order.get("full_path", false)) \
		and pos.distance_squared_to(t.pos) < 10.0 \
		and absf(float(PackedFloat32Array([wrapf((t.pos - pos).angle() - facing, -PI, PI)])[0])) <= 0.009999999776482582 \
		and not world.ai._flying(self) and not world.ai._flying(t)
	if d <= reach:
		motion_notice(t.pos, 2, reach, bool(order.get("full_path", false)))
	#  hands the tick to while the strike delay
	#  runs or the target is out of reach; that one only stands
	# still next to a target that is not moving — one that
	# moves is followed (see _approach).
	# Native54ca40 can admit an incoming target at the selected impact tick.
	# Its first sample needs no queued turn in this already-aligned subset.
	# Keep all waiting-turn scheduling on the existing path for now.
	if (d > reach and not (impact_query and t._moving)) \
			or (not ranged and not impact_query and not _strike_clear(t, d)) \
			or (_attack_cd > 0.0 and t._moving):
		_approach(t, d, reach, dt)
		return
	if not impact_query:
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
	var variant := randi_range(1, 3)
	var clip := ""
	var hit_ticks := -1.0
	if impact_query:
		# Query once: the same clip supplies both the blocker horizon and the
		# played strike. act() here would select again and consume another roll.
		clip = model.action_clip("attack", variant)
		if clip != "" and model.has_anim(clip):
			hit_ticks = _clip_hit_ticks(clip)
		# No authored hit record: preserve the existing current-position gate
		# and half-clip fallback instead of inventing an impact deadline.
		var clear := false
		if hit_ticks >= 1.0:
			var at := t.pos
			var admitted := true
			if d > reach:
				at = t.future_pos(int(hit_ticks))
				var delta := at - pos
				var distance2 := float(PackedFloat32Array([float(delta.x) * delta.x + float(delta.y) * delta.y])[0])
				var radius := float(PackedFloat32Array([reach])[0])
				var radius2 := float(PackedFloat32Array([radius * radius])[0])
				var angle := absf(float(PackedFloat32Array([delta.angle() - float(PackedFloat32Array([facing])[0])])[0]))
				if angle > 3.1415927410125732:
					angle = 6.2831854820251465 - angle
				admitted = distance2 <= radius2 and angle <= 0.009999999776482582
			clear = admitted and _strike_clear_at(t, int(hit_ticks), at)
		else:
			clear = d <= reach and _strike_clear(t, d)
		if not clear:
			_approach(t, d, reach, dt)
			return
		_goal = Vector2.INF
		path = PackedVector2Array()
	var len := 0.0
	if clip != "" and model.has_anim(clip):
		model.play(clip, 0.05, clip == model._current)
		len = model.player.get_animation("ei/" + clip).length
	else:
		len = model.act("attack", variant, 0.05)
	len = maxf(len, 0.6)
	action = "attack"
	_anim_lock = len
	# the original: the next strike may start round(A x 15 / actions)
	# ticks after this one, A = the weapon's "actions" (unarmed: the prototype's
	# "tuning actions", inferred), actions = Dex * 0.2 + 10 (x quickness, x arm
	# wounds; monsters 15). The strike animation still has to finish.
	var a_w := float(stats.get("weapon_actions", proto.get("tuning_actions", 50.0)))
	_attack_cd = maxf(_strike_delay_ticks(a_w, actions(), stats.has("weapon_actions")) * TICK, len)
	# The outcome is rolled now, the blow lands later. The hit
	# record takes this order's aim before the roll (
	# then reads its).
	strike_aim = int(order.get("aim", -1))
	var roll := world.combat.strike_roll(self, t)
	strike_miss = not roll.hit
	_pending_hit = {"t": (hit_ticks if hit_ticks >= 1.0 else _hit_ticks()) * TICK, "target": t, "roll": roll}
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
	path_flat_cost = true   # even while waiting for a target coming closer
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
			if v > 0.0 and (pos.distance_to(t.future_pos(w)) - reach) / v < w:
				_goal = Vector2.INF
				_set_action("idle")
				return
			path = p
	if path.is_empty() or world.time >= _arrive_t - 16.0 * TICK:
		var tv := t.speed() * TICK if t._moving else 0.0
		var closing := speed() * TICK + tv * Vector2.from_angle(t.facing).dot((t.pos - pos) / maxf(d, 0.001))
		var ticks := clampi(roundi((d - reach) / maxf(closing, 0.1)), 2, 64)
		var at := t.future_pos(ticks)
		if path.is_empty() or _goal.distance_to(at) >= (d + 1.0) * 0.1:
			_fresh_path = _avoid != null and is_instance_valid(_avoid)
			path = _path_to(at,t,-1,3.0*dist3(t)+15.0 if controller < 0 else 1000000.0)
			motion_notice(at, 2, reach, bool(order.get("full_path", false)))
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


##  compares the static block route count times8 with the
## nearest-even cell limit before dynamic windows or turn refinement. Direct
## routes have no block count; no polyline-length estimate is substituted.
func path_fits(p: PackedVector2Array, _to: Vector2, limit: float) -> bool:
	if p.is_empty(): return false
	var blocks := _plan_blocks if p == _plan_path else world.nav.path_blocks(p)
	return blocks >= 0 and blocks*8 <= NavGrid.round_even(limit*2.0-0.5)


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


## The aligned grounded melee part, at the chosen hit tick.
## logic+a78 is the AI sector-candidate cache (ai_near), not noticed. Consume
## that cache without refreshing it here; its8–11tick producer keeps its
## own cadence and RNG. For the ordinary zero-relativeZ case,52fcc0 retains
## unit+24. Use XY without substituting different ground heights.
func _strike_clear_at(t: GameUnit, ticks: int, point := Vector2.INF) -> bool:
	if order.get("full_path", false) or float(stats.get("range", 0.0)) >= 3.0 \
			or GameSound.held_weapon_type(self) in [5, 6]:
		return true
	var delta := (t.pos if point == Vector2.INF else point) - pos
	var length2 := float(delta.x) * delta.x + float(delta.y) * delta.y
	if length2 <= 0.0:
		return true
	# Native stores both normalized vectors and their dot products as float32.
	var along := Vector2(delta.x / length2, delta.y / length2)
	var side_length := float(PackedFloat32Array([sqrt(float(along.x) * along.x + float(along.y) * along.y)])[0])
	var side := Vector2(along.y / side_length, -along.x / side_length)
	var candidates: Array = get_meta("ai_near", [])
	for value in candidates:
		if not is_instance_valid(value) or not value is GameUnit:
			continue
		var o := value as GameUnit
		if o == self or o == t or o.dead or o.world != world:
			continue
		var at := o.future_pos(ticks)
		var x := float(at.x) - pos.x
		var y := float(at.y) - pos.y
		var a := float(PackedFloat32Array([x * along.x + y * along.y])[0])
		var c := float(PackedFloat32Array([x * side.x + y * side.y])[0])
		if a > 0.10000000149011612 and a < 0.8999999761581421 \
				and c > -0.30000001192092896 and c < 0.30000001192092896:
			return false
	return true


## The stamina a cast costs. Only the players' units pay it or need it
## (test unit, the owning party): AI
## units cast for free. The server's float Intelligence factor is 25/Int
## the UI uses the quantized byte instead.
func _spell_cost(sp: Dictionary) -> float:
	if controller < 0:
		return 0.0
	var intelligence := float(stats.get("int", 0.0))
	return float(sp.mana) * 25.0 / intelligence if intelligence > 0.0 else INF


func _do_cast(dt: float) -> void:
	var t: GameUnit = _order_target()
	#  execute quick potion kind 8 before
	# checking the cannot-cast bit. Wands and known spells still refuse it.
	var potion := order.has("item") and int(Items.info(String(order.item)).get("row", {}).get("item_id", -1)) == 8
	var refused := cannot_cast() and not potion
	if (t != null and (not is_instance_valid(t) or t.dead)) or refused:
		if refused and world.session:
			world.session.failed(self, 9)   # "Can't cast spells"
		order = order.get("then", {}) if refused else {}
		return
	var at: Vector2 = t.pos if t else order.point
	var sp := Spells.parse(order.spell)
	var notice_mode := 2 if int(sp.proto.get("type_id", 0)) == 0 else 1
	if pos.distance_to(at) <= float(order.get("range", sp.range)):
		motion_notice(at, notice_mode, float(order.get("range", sp.range)), bool(order.get("full_path", false)))
	# An AI cast reaches its option's range (the prototype's attack range on
	# a weapon-type-16 unit).
	if pos.distance_to(at) > float(order.get("range", sp.range)):
		if path.is_empty():
			path = _path_to(at, t)
			motion_notice(at, notice_mode, float(order.get("range", sp.range)), bool(order.get("full_path", false)))
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
	Spells.cast_after(world, self, spell, t, at, cast_t)


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


## Death needs the clip duration even if that clip has no strike frame.
static func _clip_duration(tmpl: String, clip: String) -> int:
	_clip_hit_frame(tmpl, clip)
	return _hit_frames.get(tmpl, {}).get(clip, Vector2i(-1, -1)).x


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
## `hit_flags`: native hit flags: 1 backstab, 4 electrical flash. Callers
## preserve bit4 from the pre-armour record; `types` here
## normally contains only what armour left for body-part severance.
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
	# `owner_only`: a lasting spell's later ticks pass no attacker, only the
	# owner (with effect flag bit 0): the
	# experience still goes to the owner's party (param 3
	# ). Native (NULL) calls for help at this unit
	# it names no aggressor. Do not restart the remake's movement-stopping
	# hit lock on each wall tick (native moving reactions continue the walk,
	#  with param4=1).
	if owner_only:
		remove_meta("attacker")
		world.ai.hit_hook(self, null)
		return
	if _anim_lock <= 0.0 and randf() < 0.5:
		_anim_lock = minf(model.act("hit", 1, 0.05), 0.6)
		action = "hit"
		GameSound.unit(self, "hit")
	# a blow that does not kill: a creature attacker's side goes
	# into this unit's own hostility mask ((attacker, victim)) unless
	# the diplomacy makes it a friend — then the hit hook.
	if source and is_instance_valid(source) and source != self \
			and world.relation(faction, source.faction) != 0:
		world.ai._hate(self, source.faction)
	if controller < 0:
		world.ai.on_attacked(self, source)
	else:
		world.ai.on_player_attacked(self, source)


func die(killer: GameUnit = null) -> void:
	if dead:
		return
	#  forces witness scans before the unit becomes a corpse.
	if world and world.authority and world.ai:
		world.ai.seen_murder(self, killer)
	dead = true
	orders.clear()
	order = {}
	path = PackedVector2Array()
	var len := model.act("death", 1, 0.05)
	_queue_blood_pool(model._current if len > 0.0 else "")
	action = "death"
	GameSound.unit(self, "death")
	if len > 0.0:
		var m := model
		get_tree().create_timer(len - 0.05).timeout.connect(func():
			if is_instance_valid(m) and m == model and dead:
				freeze_pose())
	died.emit(self)
	world.on_death(self, killer)


func _queue_blood_pool(clip: String) -> void:
	restore_blood_pool(null)
	if world == null or not world.authority:
		return
	var frames := _clip_duration(String(model.template).to_lower() if model else "", clip)
	var rates: Array = Array(race.get("anim_speeds", []))
	var rate := float(PackedFloat32Array([float(rates[3]) if rates.size() > 3 else 1.0])[0])
	# Invalid custom rates retain a finite compatibility fallback. Supplied
	# races have a positive death rate; native duration division truncates.
	if not is_finite(rate) or rate <= 0.0:
		rate = 1.0
	var duration := float(PackedFloat32Array([float(maxi(frames, 0))])[0]) / rate
	_pool_left = maxi(int(duration), 0) if is_finite(duration) and duration < 2147483648.0 else 0
	_pool_sent = false
	_pool_step = world._logic_step


func _tick_blood_pool() -> void:
	if world == null or not world.authority or _pool_sent or _pool_checked_step == world._logic_step:
		return
	_pool_checked_step = world._logic_step
	# Native tests an empty queue before expiring its animation row. A death
	# earlier in this very step must not age a positive-duration row yet.
	if _pool_left == 0:
		_pool_sent = true
		_pool_left = -1
		world.corpse_pools.emit_pool(self)
	elif _pool_left > 0:
		_pool_left = maxi(_pool_left - maxi(world._logic_step - _pool_step, 0), 0)
		_pool_step = world._logic_step


func blood_pool_state() -> Dictionary:
	return {"left": _pool_left, "sent": _pool_sent}


func restore_blood_pool(value: Variant) -> void:
	_pool_left = -1
	_pool_sent = true
	_pool_step = world._logic_step if world else -1
	_pool_checked_step = -1
	if not (value is Dictionary) or not (value.get("sent") is bool) or not (value.get("left") is int):
		return
	var left: int = value.left
	if left < -1 or left > 0x7fffffff or (not value.sent and left < 0):
		return
	_pool_left = left
	_pool_sent = value.sent


## Holds a corpse in its current (death) pose. The clip stays the player's
## current animation at speed 0 instead of being paused: a paused or finished
## AnimationPlayer reports no current_animation, and the unit panel's figure
## (Paperdoll.follow_pose, mirroring the hovered unit) then replayed the
## death clip from its start every time the corpse was hovered. `at_end`: the
## clip's last frame (corpses of a restored zone / a late joiner).
func freeze_pose(at_end := false) -> void:
	if world and is_instance_valid(world.ground_marks):
		world.ground_marks.queue_unit(self)
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
	restore_blood_pool(null)
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
	restore_blood_pool(null)
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
	restore_blood_pool(null)
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
		for p: UnitBodyPart in parts:
			if p.state > 0:
				l += float(p.lethal)
		var f := clampf((_max_hp - total) / (_max_hp * l), 0.0, 0.999) if l > 0.0 and _max_hp > 0.0 else 0.0
		for p: UnitBodyPart in parts:
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
	var m := EIUnitModel.create(figure_info())
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


static var defer_hidden_pose := not OS.get_cmdline_user_args().has("--ei-eager-poses")
static var sleep_hidden_replicas := not OS.get_cmdline_user_args().has("--ei-eager-replicas")
var _presentation_sleeping := false
var _presentation_advancing := false
var _presentation_generation := 0
var _presentation_stamp := 0.0
var _presentation_paused_at := -1.0
var _presentation_observed_until := 0.0
var _sleeping_model: EIUnitModel
var _sleeping_model_process := false
var _sleeping_physics := false
var _presentation_pause_observer: Node


## This node has no frame callbacks. Putting _notification on GameUnit itself
## would add a script call to every actor's process and physics notification,
## including the authority. Only replicas that sleep need this observer.
class PresentationPauseObserver extends Node:
	var unit: GameUnit
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED \
				or what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED:
			unit._presentation_mode_changed()


func _presentation_mode_changed() -> void:
	if not _presentation_sleeping or world == null:
		return
	if not can_process():
		if _presentation_paused_at < 0.0:
			_presentation_paused_at = world._presentation_clock
	elif _presentation_paused_at >= 0.0:
		# A disabled actor may share a world that continues rendering. Keep
		# its pending active interval, but never replay the paused interval.
		_presentation_stamp += world._presentation_clock - _presentation_paused_at
		_presentation_paused_at = -1.0


func _can_sleep_presentation() -> bool:
	if not sleep_hidden_replicas or visible or anim_watched or world == null or world.authority \
			or not world.draw_frame_enabled() or not is_inside_tree() or model == null:
		return false
	if world._presentation_clock < _presentation_observed_until:
		return false
	var sound := GameSound.instance
	if sound == null or sound._world != world or sound.mixer == null:
		return false
	var eye := Vector2(sound.mixer.listener.x, sound.mixer.listener.y)
	return pos.distance_squared_to(eye) > ANIM_HEAR * ANIM_HEAR


func _sleep_model() -> void:
	if _sleeping_model == model:
		return
	_sleeping_model = model
	_sleeping_model_process = model != null and model.is_processing()
	if model:
		model.set_process(false)


func _advance_sleeping_presentation() -> void:
	if not _presentation_sleeping or _presentation_advancing or world == null or not can_process():
		return
	var dt := maxf(world._presentation_clock - _presentation_stamp, 0.0)
	_presentation_stamp = world._presentation_clock
	if dt > 0.0:
		_presentation_advancing = true
		_present_frame(dt)
		if is_instance_valid(_sleeping_model) and _sleeping_model_process and _sleeping_model.can_process():
			_sleeping_model._process(dt)
		_presentation_advancing = false


func _step_sleeping_presentation() -> void:
	if not _can_sleep_presentation():
		wake_presentation()
	else:
		_advance_sleeping_presentation()
		_sleep_model()   # a complexion/snapshot may have replaced the figure


func wake_presentation() -> void:
	if not _presentation_sleeping:
		return
	_advance_sleeping_presentation()
	_presentation_sleeping = false
	_presentation_paused_at = -1.0
	set_process(true)
	set_physics_process(_sleeping_physics)
	if is_instance_valid(_sleeping_model):
		_sleeping_model.set_process(_sleeping_model_process)
	_sleeping_model = null
	# Its first visible frame starts at the latest authoritative placement.
	net_view.got(pos, true, facing)
	_sync_transform(0.0)
	if _wounds_dirty and world and world.presentation:
		_wounds_dirty = false
		UnitWounds.update(self)
	if model:
		model.flush_pending_pose()


## A particle/bone consumer needs a current transform even outside sight.
## Keep it active across nearby effect ticks instead of sleeping every frame.
func observe_presentation() -> void:
	if world:
		_presentation_observed_until = world._presentation_clock + ANIM_OFFSCREEN_STEP
	wake_presentation()


func _process(dt: float) -> void:
	if world and not world.authority and is_processing() and _can_sleep_presentation():
		_presentation_sleeping = true
		_presentation_generation += 1
		_presentation_stamp = world._presentation_clock
		# World and actor callbacks have different priorities once drawing
		# starts. Include this skipped frame only if the world already sampled
		# it; otherwise the world's later callback will add it to the clock.
		if world._presentation_frame == Engine.get_process_frames():
			_presentation_stamp -= dt
		_sleeping_physics = is_physics_processing()
		set_process(false)
		set_physics_process(false)
		_sleep_model()
		if _presentation_pause_observer == null:
			var observer := PresentationPauseObserver.new()
			observer.unit = self
			add_child(observer)
			_presentation_pause_observer = observer
		world.sleep_presentation(self)
		return
	_present_frame(dt)


func _present_frame(dt: float) -> void:
	if _screen == null:
		return
	# Current peers send movement speed explicitly, so hidden animation does
	# not need a terrain lookup or a model transform to recover that speed.
	# Older packets retain the original placement-derived fallback.
	var dormant := _presentation_advancing and _remote_move_speed
	if world and world.draw_frame_enabled():
		if not _frame_drawing:
			# Authority samples its native spline; replicas advance NetSmooth
			# with the rendered delta. Both already supply this frame's position,
			# so physics interpolation would add a second, older placement.
			_frame_drawing = true
			_anim_clock = -1.0
			if process_priority == 0:
				process_priority = -1   # native transform before camera / UI
				_frame_priority_set = true
			physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			reset_physics_interpolation()
		_game_clock = world.draw_time() if world.authority else _game_clock + dt
		if dormant:
			_update_pose()
		else:
			_draw_step(0.0 if world.authority else dt,
				not world.authority and _placement_frame == Engine.get_process_frames())
	# Wound layers from part health (every peer), redone when part health,
	# armour or the figure changed (_wounds_dirty).
	if not dormant and _wounds_dirty and (world == null or world.presentation):
		_wounds_dirty = false
		UnitWounds.update(self)
	# Out of view (box and shadow reach), the figure leaves the sun's shadow
	# casters (Game sets the sun's caster mask): neither it nor its shadow can
	# be seen, and a few hundred figures in the shadow splits cost more than
	# everything on screen.
	var far := _far if dormant else not _screen.is_on_screen() and not _headless
	if far != _far:
		_far = far
		for g in _geoms:
			if is_instance_valid(g):
				g.layers = OFFSCREEN_LAYER if far else 1
	var now := _game_clock
	if not _frame_drawing:
		now += Engine.get_physics_interpolation_fraction() * get_physics_process_delta_time()
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
	if dormant:
		_anim_due -= dt
		if _anim_due <= 0.0:
			_anim_due = maxf(_anim_due + ANIM_OFFSCREEN_STEP, 0.0)
			anim_flush(defer_hidden_pose)
		return
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
		anim_flush(defer_hidden_pose and (not visible or (world and not world.presentation)) and not anim_watched)
		return
	_anim_due -= dt
	if _anim_due <= 0.0:
		_anim_due = maxf(_anim_due + step, 0.0)
		anim_flush(defer_hidden_pose and (not visible or (world and not world.presentation)) and not anim_watched)


## The playback factor of the playing clip: a walk / run / crawl clip runs at
## the unit's ground speed (the original, EIUnitModel.move_rate), so
## its feet keep to the ground; any other clip at the normal rate.
func _anim_rate() -> float:
	if model == null or not action in ["walk", "run", "crawl"]:
		return 1.0
	return model.move_rate(_draw_move_speed if world and world.authority else _move_speed)


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
var _cover_key: Array = []
var _cover_lo := Vector2.ZERO
var _cover_hi := Vector2.ZERO
var _cover_behind := false


func may_cover(cam: Camera3D, p: Vector2, margin := 0.0) -> bool:
	if _body == null:
		return true
	var h := _body.aabb.size.y
	var gx := get_global_transform_interpolated()
	# This broad rectangle depends on the view and unit placement, not its
	# animation or pointer position. Reuse only exactly equal inputs.
	var key := [gx, h, figure_radius, cam.get_camera_projection(), cam.get_camera_transform(),
		cam.global_transform, cam.get_viewport().get_visible_rect().size]
	if key != _cover_key:
		_cover_key = key
		_cover_behind = false
		var r := maxf(figure_radius, h) + 0.5
		var box := AABB(Vector3(-r, -0.5, -r), Vector3(2.0 * r, h + 0.5, 2.0 * r))
		_cover_lo = Vector2(INF, INF)
		_cover_hi = Vector2(-INF, -INF)
		for c in 8:
			var wp := gx * box.get_endpoint(c)
			if cam.is_position_behind(wp):
				_cover_behind = true
				break
			var sp := cam.unproject_position(wp)
			_cover_lo = _cover_lo.min(sp)
			_cover_hi = _cover_hi.max(sp)
	# Touch fallback accepts a silhouette within its pixel radius. Expand
	# only the query, sharing the same cached bounds with exact picking.
	return _cover_behind or (p.x >= _cover_lo.x - margin and p.y >= _cover_lo.y - margin \
		and p.x <= _cover_hi.x + margin and p.y <= _cover_hi.y + margin)


## Screen rectangles of the figure as drawn (the original
## Game.pick_unit): [union, part 1, part 2, ...], integer pixels; empty when
## nothing is drawn. Each part clips its actual posed vertices to the frustum.
func screen_rects(cam: Camera3D) -> Array:
	var out: Array = []
	if model == null or cam == null:
		return out
	var view := MeshScreenRect.camera_context(cam)
	var union := Rect2i()
	for g in _geoms:
		if not is_instance_valid(g) or not (g is MeshInstance3D) or not g.is_visible_in_tree():
			continue
		var mi: MeshInstance3D = g
		if mi.mesh == null:
			continue
		var r := MeshScreenRect.of_context(mi, cam, view)
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
static var native_unobserved_pose := ClassDB.class_has_method("AnimationPlayer", "advance_unobserved_pose")

func anim_flush(defer_pose := false) -> void:
	if not defer_pose and _presentation_sleeping and not _presentation_advancing:
		wake_presentation()
	if _anim_acc > 0.0 and model and model.player:
		if world and is_instance_valid(world.ground_marks):
			world.ground_marks.queue_unit(self)
		var a := _anim_acc
		_anim_acc = 0.0
		if _anim_roots.is_empty():
			model.player.advance(a)
			model._timeline_pending = false
			return
		EIAnimPart.batch = true
		if defer_pose and native_unobserved_pose:
			model._timeline_pending = bool(model.player.call("advance_unobserved_pose", a))
		else:
			model.player.advance(a)
			model._timeline_pending = false
		EIAnimPart.batch = false
		model._pose_pending = defer_pose
		if not defer_pose:
			for r: EIAnimPart in _anim_roots:
				if is_instance_valid(r):
					r._apply_key()
	elif not defer_pose and model and model._pose_pending:
		model.flush_pending_pose()


func _set_action(a: String) -> void:
	var _profile := world.profile_scope("unit_set_action", uid) if world and world.profile_simulation else null
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
		wake_presentation()
		resync_drawn()


## The figure drawn where the unit stands, at once (no interpolation from an
## older placement): after a hide, a load, a placement.
func resync_drawn() -> void:
	if world and world.authority:   # (a co-op client's NetSmooth glide is left alone)
		_xf_pos = Vector2(INF, INF)   # _sync_transform's cache: place it again
		_sync_transform()
	if model:
		model.flush_pending_pose()
		model.transform = model.transform   # re-places every part / mesh below
	reset_physics_interpolation()


func _sync_transform(draw_dt := -1.0) -> void:
	# A direct/script placement invalidates the native replica's copied cache.
	_placement_revision += 1
	if world == null:
		return
	# Only on change: a moved node re-places its whole part / mesh subtree.
	# The same drawn position, facing and ground as the last placement (and
	# the node still there) give the same transform; the ground lookup is
	# skipped (most units stand still).
	var t := world.terrain
	var p := pos
	var yaw := facing
	_draw_move_speed = _move_speed
	if world.authority and (_draw_motion_active or _draw_line_goal != Vector2.INF):
		#  evaluates the existing path at integer server time
		# plus the draw-clock remainder.
		var sample := _draw_motion_sample(world.logic_fraction())
		if not sample.is_empty():
			p = sample.p
			var direction: Vector2 = sample.d
			if direction != Vector2.ZERO:
				yaw = direction.angle()
			_draw_move_speed = direction.length() * float(sample.v) * SPEED_SCALE
	if not world.authority:
		var elapsed := get_physics_process_delta_time() if draw_dt < 0.0 else draw_dt
		p = net_view.step(pos, elapsed)
		yaw = net_view.step_yaw(facing, elapsed)
	# Advance smoothing before checking the cache. Once it reaches the
	# target, stationary actors can share the host's exact placement cache.
	if p == _xf_pos and yaw == _xf_facing and (t.get_instance_id() if t else 0) == _xf_tid \
			and (t == null or t.surface_rev == _xf_rev) and world.nav.floor_rev == _xf_floor_rev and transform == _xf:
		return
	_drawn = p
	var xf := Transform3D(Basis(Vector3.UP, yaw + MODEL_YAW_OFFSET),
		EISpace.pos(p.x, p.y, world.ground_at(p.x, p.y)))
	if transform != xf:
		# A jump (placement, teleport, revive, a snapshot far off): drawn there
		# at once, not slid there over a physics step.
		var jump := transform.origin.distance_squared_to(xf.origin) > 4.0
		transform = xf
		if jump:
			reset_physics_interpolation()
	_xf_pos = p
	_xf_facing = yaw
	_xf_tid = t.get_instance_id() if t else 0
	_xf_rev = t.surface_rev if t else 0
	_xf_floor_rev = world.nav.floor_rev
	_xf = transform


# _sync_transform's last drawn placement (pos, facing, terrain and its surface
# revision, the transform set).
var _xf_pos := Vector2(INF, INF)
var _xf_facing := 0.0
var _xf_tid := -1   # the terrain's instance id
var _xf_rev := 0
var _xf_floor_rev := -1
var _xf := Transform3D()
var _placement_frame := -1   # native roster placement already supplied this frame
var _placement_revision := 0


func _physics_process(_dt: float) -> void:
	if world and world.draw_frame_enabled():
		return
	if _frame_drawing:
		_frame_drawing = false
		_anim_clock = -1.0
		if _frame_priority_set and process_priority == -1:
			process_priority = 0
		_frame_priority_set = false
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		reset_physics_interpolation()
	_game_clock += _dt
	_draw_step(_dt)


func _draw_step(_dt: float, placement_ready := false) -> void:
	if not placement_ready:
		_sync_transform(_dt)
	#  takes the speed along the path spline where the unit is
	# drawn; here the distance covered in the step (a jump of more than 2 m,
	# a placement or teleport, counts as standing).
	var cur := pos if world == null or world.authority else _drawn
	var moved := cur.distance_to(_speed_from) if _speed_from != Vector2.INF else 0.0
	if world != null and not world.authority and not _remote_move_speed:
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
## of a player who left are AI, -1), bit 23 the run gait, bit 24 the strike's
## miss, bit 25 resting, bit 26 BlockUnit / say_block (+8)
## bit 27 the authoritative village dialogue gate (creature commands).
## Element 11 lists the magic effects
## (buffs) as [name, until] or [name, until, sense, detect]: the unit panel's
## effect list and the client's own vision (eagle eye) need them. Remake-only
## Element 12 optionally carries this party member's noticed and seen-corpse
## ids, so clients use the host's retained perception in this world.
## wire format.
func snapshot() -> Array:
	var ph := PackedByteArray()
	for p: UnitBodyPart in parts:
		ph.append(clampi(roundi(float(p.cur) / maxf(float(p.max), 0.001) * 255.0), 0, 255))
	# Co-op bandwidth: values on a binary grid fit 4-byte floats in var_to_bytes.
	return [uid, snappedf(pos.x, 1.0 / 64.0), snappedf(pos.y, 1.0 / 64.0), snappedf(facing, 1.0 / 256.0), action,
		snappedf(hp, 1.0 / 64.0), int(dead) | (int(hidden) << 1) | (severed_mask() << 2)
		| (int(alert) << 8) | (stance << 9) | (limp << 11) | (int(not aggressive) << 13)
		| (clampi(faction, 0, 31) << 14) | (clampi(controller + 1, 0, 15) << 19) | (int(gait_run) << 23)
		| (int(strike_miss) << 24) | (int(resting) << 25) | (int(blocked) << 26)
		| (int(village_talk_ready()) << 27), snappedf(mana, 1.0 / 16.0), ph,
		snappedf(_max_hp, 1.0 / 16.0), snappedf(max_mana, 1.0 / 16.0), _buff_snapshot(), _perception_snapshot(),
		snappedf(_move_speed, 1.0 / 256.0), _action_serial]


func _perception_snapshot() -> Array:
	var out := [[], []]
	if controller < 0 or world == null:
		return out
	var slot := 0
	for key in ["noticed", "seen_corpses"]:
		for o in (get_meta(key, {}) as Dictionary).values():
			if is_instance_valid(o) and o is GameUnit and world.units.get(o.uid) == o:
				out[slot].append(o.uid)
		slot += 1
	return out


func _apply_perception_snapshot(row) -> void:
	var ids := []
	if row is Array and row.size() == 2 and world != null:
		for list in row:
			if list is Array or list is PackedInt32Array or list is PackedInt64Array:
				for id in list:
					if (id is int or id is float) and is_finite(float(id)) and float(id) == float(int(id)) \
							and int(id) > 0 and world.units.has(int(id)):
						ids.append(int(id))
	set_meta("net_noticed", ids)


func _buff_snapshot() -> Array:
	var out := []
	for k in buffs:
		var b: Dictionary = buffs[k]
		var extra := b.duplicate(true)
		for key in ["until", "sense", "detect"]:
			extra.erase(key)
		if valid_effect_ticks(extra.get(EFFECT_TICKS)):
			# 50eaf0 sends two raw bytes;50ec30 zero-extends them into DWORD.
			extra[EFFECT_TICKS] = int(extra[EFFECT_TICKS]) & 0xffff
		else:
			extra.erase(EFFECT_TICKS)
		if not extra.is_empty():
			out.append([String(k), snappedf(float(b.get("until", 0.0)), 0.1), b.get("sense", 0), b.get("detect", 0), extra])
		elif b.has("sense") or b.has("detect"):
			out.append([String(k), snappedf(float(b.get("until", 0.0)), 0.1), b.get("sense", 0), b.get("detect", 0)])
		else:
			out.append([String(k), snappedf(float(b.get("until", 0.0)), 0.1)])
	return out


## `quiet`: the unit's state as found by a joining client (no death clip,
## sounds or hit numbers; a corpse lies already dead).
func apply_snapshot(s: Array, quiet := false) -> void:
	# Account for the old clip/rate before replacing it with newer authority
	# state. This prevents a late hidden update advancing the new action by
	# time that belonged to its predecessor.
	_advance_sleeping_presentation()
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
			parts[i].cur = ph[i] / 255.0 * float(parts[i].max)
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
	blocked = bool(flags & (1 << 26))
	resting = bool(flags & (1 << 25))
	_talk_remote_ready = bool(flags & (1 << 27))
	_apply_perception_snapshot(s[12] if s.size() > 12 else null)
	_remote_move_speed = s.size() > 13 and (s[13] is int or s[13] is float) \
		and is_finite(float(s[13])) and float(s[13]) >= 0.0
	if _remote_move_speed:
		_move_speed = float(s[13])
	if s.size() > 11:
		buffs.clear()
		_legacy_effect_at = world.time if world else 0.0
		_legacy_effect_step = world._client_effect_step if world else 0
		_legacy_effect_received = true
		for b: Array in s[11]:
			var d := {"until": float(b[1])}
			if b.size() > 3:
				if b[2] is Array: d.sense = b[2]
				if b[3] is Array: d.detect = b[3]
			if b.size() > 4 and b[4] is Dictionary:
				d.merge(b[4], true)
			if not valid_effect_ticks(d.get(EFFECT_TICKS)):
				d.erase(EFFECT_TICKS)
			buffs[String(b[0])] = d
		refresh_figure()
	var a: String = s[4]
	var fresh_action := false
	if s.size() > 14:
		fresh_action = int(s[14]) != _remote_action_serial
		_remote_action_serial = int(s[14])
	if (a != action or (fresh_action and not a in _STEADY)) and not dead:
		action = a
		_anim_acc = 0.0
		if a.begins_with("anim:"):
			model.play(a.substr(5), 0.1, fresh_action)
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
	if _presentation_sleeping:
		if not _can_sleep_presentation():
			wake_presentation()
		else:
			_sleep_model()
