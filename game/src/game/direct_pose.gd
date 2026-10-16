class_name DirectPose
extends Node
## Direct-control pose composer. Original clips remain unchanged. Each clip is
## composed in EI's original quaternion convention before the two poses mix.
var unit: GameUnit
var phase := 0.0
var weight := 0.0
var leg_yaw := 0.0
var reverse := false
var playback_direction := 1.0
var _base_keys := {}
var _base_positions := {}
var lower_clip := ""
var _lower_code := -1
var parts: Array[EIAnimPart] = []
var model: EIUnitModel
var applied_frames := 0
var torso_error := 0.0
var _last_clock := -1.0

func _init(actor: GameUnit) -> void:
	unit = actor

func _ready() -> void:
	process_priority = 10 # after the native model's cycle/crossfade callbacks

func _process(_dt: float) -> void:
	var now := unit._game_clock
	var elapsed := maxf(0.0, now-_last_clock) if _last_clock >= 0.0 else 0.0
	_last_clock = now
	apply_pose(minf(elapsed,0.25))

func collect(n: EIAnimPart) -> void:
	parts.append(n)
	for c in n.animation_children: collect(c)

func sample(clip: String, time: float) -> Dictionary:
	var rotations := {}
	var positions := {}
	var anim := model.player.get_animation("ei/"+clip)
	if anim == null: return {}
	for i in anim.get_track_count():
		var path := anim.track_get_path(i)
		var n := model.get_node_or_null(NodePath(path.get_concatenated_names())) as EIAnimPart
		if n == null: continue
		if anim.track_get_type(i) == Animation.TYPE_VALUE:
			rotations[n] = anim.value_track_interpolate(i,time)
		elif anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			positions[n] = anim.position_track_interpolate(i,time)
	var world_rot := {}
	for n in parts:
		var q: Quaternion = rotations.get(n,Quaternion.IDENTITY)
		var parent: Quaternion = world_rot.get(n.animation_parent,Quaternion.IDENTITY)
		world_rot[n] = q if EIAnim.absolute or n.animation_parent == null else parent*q if EIAnim.parent_first else q*parent
	return {"rot":world_rot,"pos":positions}

## Remove the previous additive pose before the animation mixer advances.
## Its authored crossfade is the upper-body source for the next frame.
func restore_pose() -> void:
	if not is_instance_valid(model):
		_base_keys.clear(); _base_positions.clear()
		return
	var was_batching := EIAnimPart.batch
	EIAnimPart.batch = true
	for part: EIAnimPart in _base_keys:
		if is_instance_valid(part):
			part.animation_key = _base_keys[part]
			part.position = _base_positions[part]
	EIAnimPart.batch = was_batching
	for root in model._animation_roots: root._apply_key()
	_base_keys.clear(); _base_positions.clear()


func apply_pose(dt: float) -> void:
	_compose_pose(dt)
	# The weighted body reads skeleton bones; hair and weapons remain node
	# attachments. Flush their pending transforms together after the final
	# mixed pose, before the renderer consumes either representation.
	if is_instance_valid(model):
		for part: EIAnimPart in parts:
			if part.override_pose: part.force_update_transform()


func _compose_pose(dt: float) -> void:
	if not is_instance_valid(unit) or unit.model == null: return
	if model != unit.model:
		model = unit.model
		parts.clear()
		for n in model._animation_roots: collect(n)
		phase = 0.0; weight = 0.0; leg_yaw = 0.0
		reverse = false; playback_direction = 1.0; _lower_code = -1; lower_clip = ""
		_base_keys.clear(); _base_positions.clear()
	var eligible := model.has_node("hp/bd") and unit.direct_controlled and not unit.dead and unit.stance == GameUnit.STANCE_NONE and (unit.action in ["idle","walk","run","attack"] or unit.action.begins_with("cast"))
	if not eligible:
		weight = 0.0
		return
	var moving := eligible and unit._move_speed > 0.001 and unit.direct_motion != Vector2.ZERO
	weight = move_toward(weight,1.0 if moving else 0.0,dt*6.0)
	# A one-shot clears current_animation when its last frame is reached,
	# before the authority's recovery tick selects the next action. Keep
	# composing that final pose or the body briefly snaps to planted feet.
	if weight <= 0.0 or model._current.is_empty(): return
	# Keep one gait across swings. Re-picking a weighted animation every
	# frame or toggling combat readiness changes stride beneath planted feet.
	var gait := "run" if unit.running else "walk"
	var code := (model.code_for(gait) & ~0x38000) | (EIUnitModel.ST_NEUTRAL if model.has_neutral() else EIUnitModel.ST_ATTACK)
	if lower_clip.is_empty() or _lower_code != code:
		var cycle_fraction := phase / maxf(model.player.get_animation("ei/"+lower_clip).length,0.01) if not lower_clip.is_empty() else 0.0
		# Modifiers distinguish the healthy and limping walks. Ignoring them
		# randomly picked a short injured stride after gait/weapon changes.
		lower_clip = model.pick(code, true)
		if lower_clip.is_empty() and code & 0x3fc00000:
			lower_clip = model.pick(code & ~0x3fc00000, true)
		if lower_clip.is_empty(): lower_clip = model.resolve(gait)
		if not lower_clip.is_empty(): phase = cycle_fraction * model.player.get_animation("ei/"+lower_clip).length
		_lower_code = code
	if lower_clip.is_empty(): return
	var walk := model.player.get_animation("ei/"+lower_clip)
	var base := {"rot":{},"pos":{}}
	for part: EIAnimPart in parts:
		_base_keys[part] = part.animation_key
		_base_positions[part] = part.position
		base.rot[part] = part._world_key
		base.pos[part] = part.position
	var e: Dictionary = model._clip_records().get(lower_clip,{})
	var authored_speed := float(e.get("speed",1.0))
	var rate := unit._move_speed * 15.0 / (model.height_k * authored_speed * EIAnim.FPS) if authored_speed != 0.0 and model.height_k != 0.0 else 1.0
	var angle := wrapf(unit.direct_motion.angle()-unit.facing,-PI,PI) if moving else leg_yaw
	if moving:
		if reverse and absf(angle) < deg_to_rad(80.0): reverse = false
		elif not reverse and absf(angle) > deg_to_rad(100.0): reverse = true
	if moving and reverse: angle = wrapf(angle-PI,-PI,PI)
	leg_yaw = lerp_angle(leg_yaw,clampf(angle,-1.35,1.35),1.0-exp(-dt*10.0))
	playback_direction = move_toward(playback_direction, -1.0 if reverse else 1.0, dt*8.0)
	phase = fposmod(phase+dt*rate*playback_direction,maxf(walk.length,0.01))
	var lower := sample(lower_clip,phase)
	if base.is_empty() or lower.is_empty(): return
	var desired := {}
	var twist := Quaternion(Vector3.UP,leg_yaw)
	var hip_twist := Quaternion(Vector3.UP,leg_yaw*0.5)
	var batch_was := EIAnimPart.batch
	EIAnimPart.batch = true
	for n in parts:
		var original: Quaternion = (base.rot.get(n,Quaternion.IDENTITY) as Quaternion).normalized()
		var upper := n.name == "bd" or String(model.get_path_to(n)).contains("/bd/")
		var target: Quaternion = original if upper else original.slerp((hip_twist if n.animation_parent == null else twist)*(lower.rot.get(n,Quaternion.IDENTITY) as Quaternion),weight)
		desired[n] = target
		var parent: Quaternion = desired.get(n.animation_parent,Quaternion.IDENTITY)
		n.animation_key = target if EIAnim.absolute or n.animation_parent == null else parent.inverse()*target if EIAnim.parent_first else target*parent.inverse()
		if lower.pos.has(n): n.position = (base.pos[n] as Vector3).lerp(lower.pos[n],weight)
	EIAnimPart.batch = batch_was
	for root in model._animation_roots: root._apply_key()
	var chest := model.get_node_or_null("hp/bd") as EIAnimPart
	if chest and base.rot.has(chest): torso_error = (base.rot[chest] as Quaternion).normalized().angle_to(chest._world_key.normalized())
	applied_frames += 1
