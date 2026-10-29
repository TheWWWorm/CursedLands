extends Node
## A unit's animation library holds the tracks of the parts its figure has.
## EIUnitModel._build makes nodes for the record's body parts and gear only;
## tracks of the template's other parts never resolve, yet AnimationMixer
## resolves every track of every clip whenever it rebuilds its cache (first
## advance, every finished non-looping clip on the stock engine). The pruned
## clips must equal the full clips restricted to the figure's parts and pose
## the figure identically.
var checks := 0
var failures: Array[String] = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _full_library(m: EIUnitModel) -> AnimationLibrary:
	var model := EIFigure.get_model(m._asset_template)
	var root := ""
	for link: Array in model.links:
		if String(link[1]).is_empty():
			root = link[0]
			break
	# The template's full part hierarchy (every link), as the model builder
	# resolves track paths, independent of the builder's own helper.
	var parent_of := {}
	for link: Array in model.links:
		parent_of[link[0]] = link[1]
	var paths := {}
	for p: String in parent_of:
		var chain := PackedStringArray([p.replace(".", "_")])
		var q: String = parent_of[p]
		while parent_of.has(q):
			chain.insert(0, q.replace(".", "_"))
			q = parent_of[q]
		paths[p] = NodePath("/".join(chain))
	return EIAnim.library(m._asset_template, paths, root, m.height_k, true)

func _same_track(a: Animation, ta: int, b: Animation, tb: int) -> bool:
	if a.track_get_path(ta) != b.track_get_path(tb) or a.track_get_type(ta) != b.track_get_type(tb) \
			or a.track_get_key_count(ta) != b.track_get_key_count(tb):
		return false
	for key in b.track_get_key_count(tb):
		if a.track_get_key_time(ta, key) != b.track_get_key_time(tb, key) \
				or a.track_get_key_value(ta, key) != b.track_get_key_value(tb, key):
			return false
	return true

func _pose(m: EIUnitModel) -> Array:
	var out := []
	for n in m.find_children("*", "BoneAttachment3D", true, false):
		if n is EIAnimPart:
			out.append([String(m.get_path_to(n)), n.quaternion, n.position])
	return out

func _ready() -> void:
	var seen := {}
	var records := []
	for p: Dictionary in GameData.db.table("monster_prototypes"):
		var race := GameData.db.find("race_models", p.get("base_race", ""))
		var mask := String(race.get("mask", "")).to_lower()
		if mask.is_empty() or seen.has(mask):
			continue
		seen[mask] = true
		records.append({"prototype": p.name})
		if records.size() >= 16:
			break
	# A geared humanoid (map records carry armour and weapon part lists).
	records.append({"prototype": "zombie01", "armors": PackedStringArray(), "parts": PackedStringArray(["hp", "bd", "hd", "lh1", "rh1", "lh2", "rh2", "lh3", "rh3", "ll1", "rl1", "ll2", "rl2", "ll3", "rl3"])})
	var pruned_any := false
	var pose_models := 0
	for record: Dictionary in records:
		var m := EIUnitModel.create(record, true)
		if m == null:
			continue
		add_child(m)
		var label := String(record.prototype)
		var lib := m.player.get_animation_library("ei")
		var root := m.player.get_node(m.player.root_node)
		var full := _full_library(m)
		var all_paths := {}
		var resolved := {}
		for clip in full.get_animation_list():
			var a := full.get_animation(clip)
			for t in a.get_track_count():
				var path := String(a.track_get_path(t).get_concatenated_names())
				all_paths[path] = true
				if root.get_node_or_null(NodePath(path)) is EIAnimPart:
					resolved[path] = true
		var unresolved := 0
		var tracks := 0
		var full_tracks := 0
		for clip in lib.get_animation_list():
			var a := lib.get_animation(clip)
			tracks += a.get_track_count()
			for t in a.get_track_count():
				if not root.get_node_or_null(NodePath(String(a.track_get_path(t).get_concatenated_names()))) is EIAnimPart:
					unresolved += 1
		check(unresolved == 0, "every track targets a part of the figure: %s (%d unresolved)" % [label, unresolved])
		check(lib.get_animation_list() == full.get_animation_list(), "all clips kept: " + label)
		var equal := true
		for clip in full.get_animation_list():
			var a := lib.get_animation(clip)
			var b := full.get_animation(clip)
			full_tracks += b.get_track_count()
			if a == null or a.length != b.length or a.loop_mode != b.loop_mode or a.step != b.step:
				equal = false
				continue
			var ta := 0
			for tb in b.get_track_count():
				if not resolved.has(String(b.track_get_path(tb).get_concatenated_names())):
					continue
				if ta >= a.get_track_count() or not _same_track(a, ta, b, tb):
					equal = false
					break
				ta += 1
			if ta != a.get_track_count():
				equal = false
		check(equal, "pruned clips are the full clips restricted to the figure's parts, in order: " + label)
		if resolved.size() < all_paths.size():
			pruned_any = true
			check(tracks < full_tracks, "a figure without the template's other parts has fewer tracks: %s (%d of %d)" % [label, tracks, full_tracks])
		# The same pose from both libraries: first advance after the cache
		# rebuild, a looping cycle and a non-looping clip part way through.
		if pose_models < 4 and lib.has_animation("ei/cidle"):
			pose_models += 1
			var clips := ["cidle"]
			for candidate in ["cwalk", "uattack01", "cdeath01", "cattack01", "udeath01"]:
				if lib.has_animation("ei/" + candidate):
					clips.append(candidate)
			var poses := []
			m.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			for clip in clips:
				m.player.play("ei/" + clip)
				m.player.seek(0.0, true)
				m.player.advance(0.0)
				m.player.advance(0.2)
				poses.append(_pose(m))
			m.player.remove_animation_library("ei")
			m.player.add_animation_library("ei", full)
			for i in clips.size():
				m.player.play("ei/" + clips[i])
				m.player.seek(0.0, true)
				m.player.advance(0.0)
				m.player.advance(0.2)
				check(_pose(m) == poses[i], "identical pose from the pruned and the full library: %s %s" % [label, clips[i]])
		m.free()
	check(pruned_any, "at least one figure holds fewer parts than its template")
	print("ANIMATION_LIBRARY_PRUNED ", checks, " checks ", failures.size(), " failures")
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
