class_name EIAnimPart
extends BoneAttachment3D
## Original animation keys are applied on the left of the parent's rotation.
## Interpolate those keys first, then compose (the original 0050acd0/0050c230).
## Interpolating preconverted local rotations changes intermediate poses.
## Exact unchanged keys/subtrees may reuse their previously composed result.
var animation_parent: EIAnimPart
var animation_children: Array[EIAnimPart] = []
var _world_key := Quaternion.IDENTITY
var _parent_key := Quaternion.IDENTITY
var _local_key := Quaternion.IDENTITY
var _applied_quaternion := Quaternion.IDENTITY
var _key_dirty := true
var _has_applied := false
var _absolute := false
var _parent_first := false
## The mixer stores keys first, then roots apply them in hierarchy order.
## Unit.anim_flush and restart seeks keep the same timeline/events/pose while
## avoiding a repeated subtree assignment for every track the mixer writes.
static var batch := false
var animation_key := Quaternion.IDENTITY:
	set(value):
		var changed := animation_key != value or quaternion != _applied_quaternion
		animation_key = value
		if changed:
			_mark_dirty()
		if not batch:
			_apply_key()

func _mark_dirty() -> void:
	_key_dirty = true
	var p := animation_parent
	while p and not p._key_dirty:
		p._key_dirty = true
		p = p.animation_parent

func _apply_key() -> void:
	var p := animation_parent._world_key if animation_parent else Quaternion.IDENTITY
	if not _key_dirty and p == _parent_key and _absolute == EIAnim.absolute and _parent_first == EIAnim.parent_first:
		return
	_key_dirty = false
	_parent_key = p
	_absolute = EIAnim.absolute
	_parent_first = EIAnim.parent_first
	_world_key = animation_key if animation_parent == null or EIAnim.absolute else (
		p * animation_key if EIAnim.parent_first else animation_key * p)
	var local := p.inverse() * _world_key if animation_parent else _world_key
	if not _has_applied or local != _local_key or quaternion != _applied_quaternion:
		quaternion = local
		_local_key = local
		_applied_quaternion = quaternion
		_has_applied = true
	for child in animation_children:
		child._apply_key()
