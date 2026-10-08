class_name SceneryBatchWatch
extends Node3D
## A non-rendering child observes inherited transforms and visibility without
## replacing the authored part node or its mesh. The manager is weakly held.
var manager: WeakRef
var mesh_id := 0
var _mesh_resource: Mesh


func _enter_tree() -> void:
	set_notify_transform(true)
	changed()


func _ready() -> void:
	visibility_changed.connect(changed)


func _exit_tree() -> void:
	changed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		var owner: SceneryBatches = manager.get_ref() if manager else null
		if is_instance_valid(owner): owner.mesh_changed(mesh_id, true)


func changed() -> void:
	var owner: SceneryBatches = manager.get_ref() if manager else null
	if is_instance_valid(owner): owner.mesh_changed(mesh_id)


func observe_mesh(resource: Mesh) -> void:
	if _mesh_resource == resource: return
	if _mesh_resource and _mesh_resource.changed.is_connected(changed):
		_mesh_resource.changed.disconnect(changed)
	_mesh_resource = resource
	if _mesh_resource: _mesh_resource.changed.connect(changed)
