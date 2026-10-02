class_name EIAnim
extends RefCounted
## Loads "<template>.anm" from figures.res: an archive of animations, each an archive
## of per-part tracks (rotation quaternions, translations, optional vertex morphs).
## Produces a Godot AnimationLibrary targeting the node layout built by EIUnitModel.

const FPS := 20.0

static var _libraries := {}
static var parent_first := false
static var absolute := false
static var invert_keys := false


## `paths` maps part name -> NodePath (relative to the animated root).
static func library(template: String, paths: Dictionary, root_part: String, root_scale := 1.0,
		native_keys := false) -> AnimationLibrary:
	var key := "%s@%.3f:%s:%s:%s:%s" % [template, root_scale, native_keys, parent_first, absolute, invert_keys]
	if _libraries.has(key):
		return _libraries[key]
	# Units of one template differ only in the root's translation scale (their
	# height): the clips are decoded once (at scale 1) and copied with the root
	# position keys scaled, the same values _build makes (vec * root_scale).
	var base_key := "%s@base:%s:%s:%s:%s" % [template, native_keys, parent_first, absolute, invert_keys]
	if not _libraries.has(base_key):
		_libraries[base_key] = _build_library(template, paths, root_part, 1.0, native_keys)
	var base: AnimationLibrary = _libraries[base_key]
	var lib := base
	if root_scale != 1.0:
		lib = AnimationLibrary.new()
		var names := base.get_animation_list()
		var out := []
		out.resize(names.size())
		# The clips are copied on the worker threads (each task writes its own
		# slot; the base clips are only read).
		Portability.group(func(i: int) -> void:
			out[i] = _scaled(base.get_animation(names[i]), root_scale), names.size())
		for i in names.size():
			lib.add_animation(names[i], out[i])
	_libraries[key] = lib
	return lib


## `src` with its position keys times `k`: a copy (track by track, much
## faster than duplicate()), or `src` itself when it has no position track.
static func _scaled(src: Animation, k: float) -> Animation:
	var has_pos := false
	for t in src.get_track_count():
		has_pos = has_pos or src.track_get_type(t) == Animation.TYPE_POSITION_3D
	if not has_pos:
		return src
	var a := Animation.new()
	a.length = src.length
	a.loop_mode = src.loop_mode
	a.step = src.step
	for t in src.get_track_count():
		src.copy_track(t, a)
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			for key in a.track_get_key_count(t):
				a.track_set_key_value(t, key, (a.track_get_key_value(t, key) as Vector3) * k)
	return a


static func _build_library(template: String, paths: Dictionary, root_part: String, root_scale: float,
		native_keys: bool) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var arc_bytes := GameData.read_figure(template + ".anm")
	if EIResArchive.is_archive(arc_bytes):
		var arc := EIResArchive.from_bytes(arc_bytes)
		var names: Array = arc.entries.keys()
		var data := []
		for anim_name: String in names:
			data.append(arc.read(anim_name))
		# Decoded on the worker threads (_build only reads its arguments).
		var built := []
		built.resize(names.size())
		Portability.group(func(i: int) -> void:
			built[i] = _build(EIResArchive.from_bytes(data[i]), paths, root_part, root_scale, native_keys), names.size())
		for i in names.size():
			var anim_name: String = names[i]
			var anim: Animation = built[i]
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR if anim_name.begins_with("c") else Animation.LOOP_NONE
				lib.add_animation(anim_name, anim)
	return lib


static func _build(tracks: EIResArchive, paths: Dictionary, root_part: String, root_scale: float,
		native_keys := false) -> Animation:
	if tracks == null:
		return null
	var anim := Animation.new()
	var length := 0.0
	# the original: a part's world rotation is its key
	# times its parent's world rotation (Hamilton key * parent, the root's is its
	# key), and a child sits at the parent's position plus the parent's world
	# rotation applied to its .bon offset (translation keys move the root only).
	# Unit nodes (EIAnimPart) do this after key interpolation. Plain Node3D
	# consumers such as menu signposts retain preconverted local rotations.
	var rot := {}
	var tracks_d := {}
	for part: String in tracks.entries:
		if not paths.has(part):
			continue
		var d := tracks.read(part)
		if d.size() < 8:
			continue
		tracks_d[part] = d
		var rc := d.decode_u32(0)
		var qs: Array[Quaternion] = []
		for i in rc:
			var p := 4 + i * 16
			qs.append(EISpace.quat(d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8), d.decode_float(p + 12)))
		# A zero-length rotation track means identity, not the previous clip.
		if qs.is_empty():
			qs.append(Quaternion.IDENTITY)
		rot[part] = qs
	if native_keys:
		#  resets missing tracks when switching animations. Without
		# these identity keys a weapon mount retained its last idle/run angle.
		for part: String in paths:
			if not rot.has(part):
				rot[part] = [Quaternion.IDENTITY]
	var world := {}
	var part_at_path := {}
	for part: String in paths:
		part_at_path[String(paths[part])] = part
	var parts_sorted: Array = rot.keys()
	parts_sorted.sort_custom(func(x, y): return String(paths[x]).count("/") < String(paths[y]).count("/"))
	for part: String in parts_sorted:
		# Paths sanitize dots in original names (rh3.sword00 -> rh3_sword00).
		# Walk to the closest animated ancestor; static variant nodes inherit
		# that rotation, and their original BON translations stay in the tree.
		var path := String(paths[part])
		var par := ""
		while "/" in path:
			path = path.left(path.rfind("/"))
			var candidate: String = part_at_path.get(path, "")
			if world.has(candidate):
				par = candidate
				break
		var qs: Array = rot[part]
		var ws: Array[Quaternion] = []
		var locs: Array[Quaternion] = []
		for i in qs.size():
			var l: Quaternion = qs[i].inverse() if invert_keys else qs[i]
			if par != "" and world.has(par):
				var pw: Array = world[par]
				var wp: Quaternion = pw[mini(i, pw.size() - 1)]
				var w := l if absolute else ((wp * l) if parent_first else (l * wp))
				ws.append(w)
				locs.append(wp.inverse() * w)
			else:
				ws.append(l)
				locs.append(l)
		world[part] = ws
		var t := anim.add_track(Animation.TYPE_VALUE if native_keys else Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath(String(paths[part]) + ":animation_key") if native_keys else paths[part])
		for i in locs.size():
			if native_keys:
				anim.track_insert_key(t, i / FPS, qs[i].inverse() if invert_keys else qs[i])
			else:
				anim.rotation_track_insert_key(t, i / FPS, locs[i])
		length = maxf(length, (qs.size() - 1) / FPS)
		if part == root_part and tracks_d.has(part):
			var d: PackedByteArray = tracks_d[part]
			var o := 4 + d.decode_u32(0) * 16
			var tc := d.decode_u32(o)
			if tc > 0:
				var pt := anim.add_track(Animation.TYPE_POSITION_3D)
				anim.track_set_path(pt, paths[part])
				for i in tc:
					var p := o + 4 + i * 12
					anim.position_track_insert_key(pt, i / FPS, EISpace.vec(Vector3(
						d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8))) * root_scale)
	anim.length = maxf(length, 1.0 / FPS)
	return anim
