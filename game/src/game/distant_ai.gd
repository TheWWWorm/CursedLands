class_name DistantAI
extends RefCounted
## Experimental simulation LOD: only quiet, non-scripted, idle NPC decisions.
## Unit ticks, movement, damage, timers, VM scripts and chatter are untouched.
## Delayed perception/calm decisions intentionally do not preserve exact replay.

const NEAR := 64.0
const FAR := 128.0
const SIGHT_MARGIN := 16.0
const EMPTY: Dictionary = {}

var world: GameWorld
var enabled := false
var _forced := OS.get_cmdline_user_args().has("--distant-ai")
var skipped := 0
var executed := 0
var _step := -1
var _party: Array[GameUnit] = []
var _radii := PackedFloat64Array()
var _full_world := true


func _init(w: GameWorld) -> void:
	world = w
	_settings_changed()
	GameData.options_changed.connect(_settings_changed)


func _settings_changed() -> void:
	enabled = _forced or GameData.option("distant_ai") == 1
	_step = -1


func should_think(u: GameUnit) -> bool:
	var period := interval(u)
	# Registry IDs stagger work without consuming the gameplay RNG. Never
	# postpone ai_next: relevance is rechecked at each ordinary decision tick.
	if period > 1 and (world._logic_step + u.uid) % period != 0:
		skipped += 1
		return false
	executed += 1
	return true


func interval(u: GameUnit) -> int:
	if not enabled or world._logic_step <= 1:
		return 1
	if _step != world._logic_step:
		_refresh()
	if _full_world or _party.is_empty():
		return 1
	# Script actors and active interactions retain their original cadence.
	if u.controller >= 0 or u.dead or u.alert or u.has_meta("hero") \
			or u.mode != "standard" or bool(u.info.get("use_in_script", false)) \
			or not u.order.is_empty() or not u.orders.is_empty() or u._anim_lock > 0.0 \
			or not u._pending_hit.is_empty() or not u.buffs.is_empty() or u._hp < u.max_hp:
		return 1
	if u.has_meta("suspect") or u.has_meta("fear_on") or u.has_meta("attacker") \
			or u.has_meta("um") or u.has_meta("alerted") \
			or not (u.get_meta("noticed", EMPTY) as Dictionary).is_empty() \
			or not (u.get_meta("seen_corpses", EMPTY) as Dictionary).is_empty():
		return 1
	var closest := INF
	var id := u.get_instance_id()
	for i in _party.size():
		var p := _party[i]
		if not is_instance_valid(p) or p.dead or p.hidden or p.controller < 0:
			continue
		# Read position and retained perception live, including same-tick
		# movement/teleports. No renderer, camera or local fog flag is sampled.
		var d := p.pos.distance_squared_to(u.pos)
		if d <= _radii[i] or (p.get_meta("noticed", EMPTY) as Dictionary).has(id):
			return 1
		closest = minf(closest, d)
	if not is_finite(closest):
		return 1
	return 4 if closest < FAR * FAR else 8


func _refresh() -> void:
	_step = world._logic_step
	_party.clear()
	_radii.clear()
	_full_world = not world.authority or world.session == null \
		or not UnitFog.sight_active(world.session) or not world.dialog_actors.is_empty() \
		or (world.vm != null and not world.vm.briefings.active.is_empty())
	if _full_world:
		return
	for p: GameUnit in world.party_units():
		if not is_instance_valid(p) or p.dead or p.hidden or p.controller < 0:
			continue
		var r := maxf(NEAR, UnitFog.range_of(p) + SIGHT_MARGIN)
		_party.append(p)
		_radii.append(r * r)
