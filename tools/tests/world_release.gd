## Game.attach_world queues the previous map's world for deletion at the end
## of a frame. Fixtures that freeze the session and drive the script VM by hand
## let few frames pass, so every visited map stayed loaded (0.5-1 GB each, over
## 10 GB in one program). Call after a map change, once the caller is no longer
## inside the old world's code: frees the already-queued worlds as the next
## frame would and returns how many worlds remain loaded.
static func release(tree: SceneTree, current: Node) -> int:
	for w: Node in tree.get_nodes_in_group(GameWorld.DIAGNOSTIC_GROUP):
		if w != current and w.is_queued_for_deletion(): w.free()
	return tree.get_nodes_in_group(GameWorld.DIAGNOSTIC_GROUP).size()
