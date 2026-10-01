class_name EIAnimPart
extends BoneAttachment3D
## Original animation keys are applied on the left of the parent's rotation.
## Interpolate those keys first, then compose (the original 0050acd0 / 0050c230).
## Interpolating preconverted Godot local rotations instead changes the pose
## between keys, by up to a centimetre in the tested human attack animation.

var animation_parent: EIAnimPart
var animation_children: Array[EIAnimPart] = []
var _world_key := Quaternion.IDENTITY
## While set, keys are only stored; the caller then runs _apply_key() on the
## root parts once (GameUnit.anim_flush): the same final pose, without
## re-applying a subtree for every key the AnimationMixer writes.
static var batch := false
var animation_key := Quaternion.IDENTITY:
	set(value):
		animation_key = value
		if not batch:
			_apply_key()


func _apply_key() -> void:
	if animation_parent:
		var p := animation_parent._world_key
		_world_key = animation_key if EIAnim.absolute else (
			p * animation_key if EIAnim.parent_first else animation_key * p)
		quaternion = p.inverse() * _world_key
	else:
		_world_key = animation_key
		quaternion = animation_key
	# AnimationMixer can write tracks in either order. Refresh descendants so
	# the final pose uses every part's current key, even when the parent was
	# written last. Static mounts inherit the same animated parent rotation.
	for child in animation_children:
		child._apply_key()
