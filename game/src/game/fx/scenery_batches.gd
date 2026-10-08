class_name SceneryBatches
extends Node3D
## World-owned Compatibility batches. Logical meshes remain visible to picking,
## navigation, weather, grass and camera obstruction; only their RS draw is hidden.
## Complete light sets must match for every member AND the combined bounds.
## Opt in with --scenery-batches while runtime/device acceptance is in progress.
const CELL := 16.0
const WATCH := &"ei_scenery_batch_watch"
var _map: WeakRef
var _roots := {} # weak roots retained for a manager/world re-entry
var _entries := {} # mesh ID -> weak node/watch, last key/bounds, current batch ID
var _groups := {} # mesh/material/state/cell key -> set of mesh IDs
var _dirty_entries := {}
var _dirty_groups := {}
var _batches := {} # batch ID -> node, member IDs, key
var _group_batches := {} # group key -> batch IDs
var _lights := {} # light ID -> weak node and last snapshot
var _volumes := {} # unsupported probe/lightmap volumes -> weak node
var _light_rows: Array = []
var _world: World3D
var _next_batch := 1
var _enabled := true
var _closing := false
var _blocked_by_volume := false
var rebuilds := 0
var last_update_usec := 0
var last_rebuilt_groups := 0
var _limit := 8
var _total_limit := 256


static func requested() -> bool:
	return DisplayServer.get_name() != "headless" and Portability.compatibility() \
		and OS.get_cmdline_user_args().has("--scenery-batches")


static func create(owner: Node3D, roots: Array) -> SceneryBatches:
	var result := SceneryBatches.new()
	result.name = "SceneryBatches"
	result._map = weakref(owner)
	for root: Node3D in roots:
		if is_instance_valid(root): result._roots[root.get_instance_id()] = weakref(root)
	owner.add_child(result)
	return result


## Call BEFORE replacing a registered mesh's material/geometry/render state.
## Shared material uniform updates need no call: batches share that resource.
static func changed(mesh: GeometryInstance3D) -> void:
	if not mesh.has_meta(WATCH): return
	var reference := mesh.get_meta(WATCH, null) as WeakRef
	var observer := reference.get_ref() as SceneryBatchWatch if reference else null
	if observer: observer.changed()


func _ready() -> void:
	_closing = false
	_enabled = _enabled and Portability.compatibility()
	_world = get_world_3d()
	_limit = int(ProjectSettings.get_setting_with_override("rendering/limits/opengl/max_lights_per_object"))
	_total_limit = int(ProjectSettings.get_setting_with_override("rendering/limits/opengl/max_renderable_lights"))
	for reference: WeakRef in _roots.values():
		var root := reference.get_ref() as Node3D
		if root: register(root)
	get_tree().node_added.connect(_node_added)
	for node: Node in get_tree().root.find_children("*", "Node3D", true, false):
		_node_added(node)
	GameData.options_changed.connect(invalidate_all)
	RenderingServer.frame_pre_draw.connect(flush)


func register(root: Node3D) -> void:
	var record: Dictionary = root.get_meta("ei", {})
	if record.get("kind", "") != "OBJECT" or String(record.get("template", "")).begins_with("ef"):
		return
	_roots[root.get_instance_id()] = weakref(root)
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var id := mesh.get_instance_id()
		if _entries.has(id) or mesh.has_meta(WATCH): continue
		var observer := SceneryBatchWatch.new()
		observer.name = "SceneryBatchWatch"
		observer.manager = weakref(self); observer.mesh_id = id
		_entries[id] = {"node":weakref(mesh), "watch":weakref(observer), "key":[], "bounds":AABB(),
			"batch":0, "transform":null, "moved":false}
		mesh.set_meta(WATCH, weakref(observer))
		mesh.add_child(observer)
		mesh_changed(id)


func set_enabled(value: bool) -> void:
	_enabled = value and Portability.compatibility()
	invalidate_all()


func mesh_changed(id: int, transformed := false) -> void:
	if _closing or not _entries.has(id): return
	var entry: Dictionary = _entries[id]
	# Scripted movers retain the engine's interpolation history. Reconstructing
	# their current transform in a new MultiMesh can jump ahead of that history.
	if transformed and entry.transform != null and not entry.moved:
		var node := entry.node.get_ref() as MeshInstance3D
		if node and node.global_transform != entry.transform: entry.moved = true
	if entry.batch: _remove_batch(entry.batch)
	_dirty_entries[id] = true
	if not entry.key.is_empty(): _dirty_groups[entry.key] = true


func invalidate_all() -> void:
	if _closing: return
	for id: int in _batches.keys(): _remove_batch(id)
	for id: int in _entries: _dirty_entries[id] = true


func _node_added(node: Node) -> void:
	if _closing or not node is Node3D or not node.is_inside_tree(): return
	if (node as Node3D).get_world_3d() != _world: return
	if node is Light3D and not node is DirectionalLight3D:
		_lights[node.get_instance_id()] = {"node":weakref(node), "snapshot":{}}
	elif node is ReflectionProbe or node is LightmapGI or node is VoxelGI:
		_volumes[node.get_instance_id()] = weakref(node)


func _light_changes() -> void:
	var changed_bounds: Array[AABB] = []
	var rows: Array = []
	for id: int in _lights.keys():
		var entry: Dictionary = _lights[id]
		var node := entry.node.get_ref() as Light3D
		var current := {}
		if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() \
				and node.get_world_3d() == _world and node.is_visible_in_tree():
			current = {"id":id, "kind":node.get_class(), "mask":node.light_cull_mask,
				"bounds":node.global_transform * node.get_aabb()}
		if current != entry.snapshot:
			if not entry.snapshot.is_empty(): changed_bounds.append(entry.snapshot.bounds)
			if not current.is_empty(): changed_bounds.append(current.bounds)
			entry.snapshot = current
		if not current.is_empty(): rows.append(current)
		if not is_instance_valid(node) or not node.is_inside_tree(): _lights.erase(id)
	_light_rows = rows
	var blocked := false
	for id: int in _volumes.keys():
		var node := (_volumes[id] as WeakRef).get_ref() as Node3D
		if not is_instance_valid(node) or not node.is_inside_tree():
			_volumes.erase(id)
		elif node.get_world_3d() == _world and node.is_visible_in_tree(): blocked = true
	if blocked != _blocked_by_volume:
		_blocked_by_volume = blocked
		invalidate_all()
	if changed_bounds.is_empty(): return
	# This runs only when spatial membership can change, not on energy flicker.
	# Test the full group bounds too: a new light can enter a gap between parts.
	for key: Array in _groups:
		var bounds := AABB(); var first := true
		for id: int in _groups[key]:
			var box: AABB = _entries[id].bounds
			bounds = box if first else bounds.merge(box); first = false
		for box: AABB in changed_bounds:
			if bounds.intersects(box):
				_dirty_groups[key] = true
				break


func _eligible(node: MeshInstance3D) -> bool:
	var owner := _map.get_ref() as Node3D if _map else null
	if not _enabled or _blocked_by_volume or not is_instance_valid(owner) or not node.is_inside_tree() \
			or not owner.is_ancestor_of(node) or node.get_world_3d() != _world or node.is_queued_for_deletion() \
			or not node.is_visible_in_tree() or node.has_meta("cam_fade_mat"):
		return false
	if node.mesh == null or (node.mesh is ArrayMesh and node.mesh.get_blend_shape_count() > 0) or node.skin != null \
			or node.material_overlay != null or node.transparency != 0.0 \
			or node.custom_aabb != AABB() \
			or node.visibility_range_begin != 0.0 or node.visibility_range_end != 0.0 \
			or not node.visibility_parent.is_empty():
		return false
	var material := node.material_override as ShaderMaterial
	return material != null and material.next_pass == null and material.shader != null \
		and (material.has_meta("ground_contact_source") or material.shader.code.contains("#define EI_GROUND_CONTACT"))


func _refresh_entry(id: int) -> void:
	if not _entries.has(id): return
	var entry: Dictionary = _entries[id]
	var old_key: Array = entry.key
	if not old_key.is_empty():
		_groups[old_key].erase(id)
		if _groups[old_key].is_empty(): _groups.erase(old_key)
		_dirty_groups[old_key] = true
	entry.key = []
	var node := entry.node.get_ref() as MeshInstance3D
	if node == null:
		for root_id: int in _roots.keys():
			if (_roots[root_id] as WeakRef).get_ref() == null: _roots.erase(root_id)
		_entries.erase(id); return
	var observer := entry.watch.get_ref() as SceneryBatchWatch
	if observer: observer.observe_mesh(node.mesh)
	if entry.moved or not _eligible(node): return
	entry.transform = node.global_transform
	entry.bounds = node.global_transform * node.get_aabb().grow(node.extra_cull_margin)
	var cell := Vector2i(floori(node.global_position.x / CELL), floori(node.global_position.z / CELL))
	var key := [cell, node.mesh.get_rid(), node.material_override.get_rid(), node.layers,
		node.cast_shadow, node.gi_mode, node.lod_bias, node.sorting_offset, node.sorting_use_aabb_center,
		node.ignore_occlusion_culling]
	entry.key = key
	if not _groups.has(key): _groups[key] = {}
	_groups[key][id] = true
	_dirty_groups[key] = true


func flush() -> void:
	if _closing or not is_inside_tree(): return
	var start := Time.get_ticks_usec()
	last_rebuilt_groups = 0
	_light_changes()
	var dirty := _dirty_entries.keys(); _dirty_entries.clear()
	for id: int in dirty: _refresh_entry(id)
	var keys := _dirty_groups.keys(); _dirty_groups.clear()
	for key: Array in keys:
		if not _groups.has(key) or not _enabled or _blocked_by_volume:
			for id: int in _group_batches.get(key, []).duplicate(): _remove_batch(id)
			continue
		var records := []
		for id: int in _groups[key]:
			var entry: Dictionary = _entries[id]
			records.append({"item":id, "bounds":entry.bounds, "layers":key[3]})
		var previous: Array = _group_batches.get(key, []).duplicate()
		var kept := {}; var pending: Array = []
		for members: Array in SceneryLightGroups.partition(records, _light_rows, _limit, _total_limit):
			if members.size() < 2: continue
			var found := false
			for id: int in previous:
				if _batches[id].members == members:
					kept[id] = true; found = true; break
			if not found: pending.append(members)
		# A moving light often leaves membership unchanged. The engine updates
		# that batch's complete light list itself; keep its existing draw object.
		for id: int in previous:
			if not kept.has(id): _remove_batch(id)
		for members: Array in pending: _make_batch(key, members)
		if kept.size() != previous.size() or not pending.is_empty(): last_rebuilt_groups += 1
	if last_rebuilt_groups: rebuilds += 1
	last_update_usec = Time.get_ticks_usec() - start


func _make_batch(key: Array, members: Array) -> void:
	var first := _entries[members[0]].node.get_ref() as MeshInstance3D
	if first == null: return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = first.mesh; multi.instance_count = members.size()
	var bounds := AABB()
	for i in members.size():
		var entry: Dictionary = _entries[members[i]]
		var node := entry.node.get_ref() as MeshInstance3D
		if node == null: return
		multi.set_instance_transform(i, node.global_transform)
		bounds = entry.bounds if i == 0 else bounds.merge(entry.bounds)
	multi.custom_aabb = bounds
	var draw := MultiMeshInstance3D.new()
	draw.name = "SceneryBatch"
	draw.top_level = true
	draw.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	draw.multimesh = multi; draw.material_override = first.material_override
	draw.layers = first.layers; draw.cast_shadow = first.cast_shadow
	draw.gi_mode = first.gi_mode; draw.lod_bias = first.lod_bias
	draw.sorting_offset = first.sorting_offset; draw.sorting_use_aabb_center = first.sorting_use_aabb_center
	draw.ignore_occlusion_culling = first.ignore_occlusion_culling
	add_child(draw); draw.global_transform = Transform3D.IDENTITY
	var id := _next_batch; _next_batch += 1
	_batches[id] = {"node":draw, "members":members, "key":key}
	if not _group_batches.has(key): _group_batches[key] = []
	_group_batches[key].append(id)
	for member: int in members:
		var entry: Dictionary = _entries[member]
		entry.batch = id
		var node := entry.node.get_ref() as MeshInstance3D
		RenderingServer.instance_set_visible(node.get_instance(), false)


func _remove_batch(id: int) -> void:
	if not _batches.has(id): return
	var batch: Dictionary = _batches[id]
	var draw := batch.node as MultiMeshInstance3D
	if is_instance_valid(draw):
		RenderingServer.instance_set_visible(draw.get_instance(), false)
		draw.queue_free()
	for member: int in batch.members:
		if not _entries.has(member): continue
		var entry: Dictionary = _entries[member]
		entry.batch = 0
		var node := entry.node.get_ref() as MeshInstance3D
		if node and node.is_inside_tree(): RenderingServer.instance_set_visible(node.get_instance(), node.is_visible_in_tree())
	if _group_batches.has(batch.key):
		_group_batches[batch.key].erase(id)
		if _group_batches[batch.key].is_empty(): _group_batches.erase(batch.key)
	_batches.erase(id)


func _exit_tree() -> void:
	_closing = true
	if RenderingServer.frame_pre_draw.is_connected(flush): RenderingServer.frame_pre_draw.disconnect(flush)
	if get_tree().node_added.is_connected(_node_added): get_tree().node_added.disconnect(_node_added)
	if GameData.options_changed.is_connected(invalidate_all): GameData.options_changed.disconnect(invalidate_all)
	for id: int in _batches.keys(): _remove_batch(id)
	for entry: Dictionary in _entries.values():
		var node := entry.node.get_ref() as MeshInstance3D
		var observer := entry.watch.get_ref() as SceneryBatchWatch
		if node: node.remove_meta(WATCH)
		if observer:
			observer.manager = null
			observer.queue_free()
	_entries.clear(); _groups.clear(); _dirty_entries.clear(); _dirty_groups.clear()
	_group_batches.clear(); _lights.clear(); _volumes.clear(); _light_rows.clear()
	_world = null
	request_ready()
