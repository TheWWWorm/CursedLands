extends EIAnimPart
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
