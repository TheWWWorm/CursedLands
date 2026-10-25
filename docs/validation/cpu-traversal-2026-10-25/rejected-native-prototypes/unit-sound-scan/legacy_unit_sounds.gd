extends UnitSounds
# Unmodified tick() from b57eba96 (pre-native sound scan).
func tick() -> void:
	if world == null:
		return
	# Every frame over every unit: no per-frame allocations (the clip name is
	# only rebuilt when the player's animation changes, units not seen this
	# frame are found by a stamp instead of a set).
	# A unit farther than MAX_D (2D) from the listener is skipped: each of its
	# sounds would get volume 0 and a silent one-shot is never started
	# (see SoundMixer._start); it re-syncs without a sound when
	# it comes back in range.
	_stamp += 1
	var n := 0
	var lis := Vector2(mixer.listener.x, mixer.listener.y)
	for u: GameUnit in world.unit_rows():
		if not is_instance_valid(u):
			continue
		var key := u.get_instance_id()
		var st: Dictionary = _units.get(key, EMPTY_STATE)
		if u.pos.distance_squared_to(lis) > MAX_D * MAX_D:
			if not st.is_empty():
				n += 1
				st.seen = _stamp
				st.far = true
			continue
		if u._presentation_sleeping:
			u.wake_presentation()
		if u.model == null or u.model.player == null:
			continue
		var pl := u.model.player
		var anim: StringName = pl.current_animation
		# Static figures and an exhausted/missing clip have no animation time.
		# Retain the unit's entry but resynchronise before the next valid clip.
		if anim == &"":
			if not st.is_empty():
				n += 1
				st.seen = _stamp
				st.far = true
			continue
		n += 1
		var cur := pl.current_animation_position * EIAnim.FPS
		if st.is_empty() or st.get("far", false):   # first sight (a joiner's corpse, a new model) / back in range: no sound
			var c := String(anim).trim_prefix("ei/")
			if st.is_empty():
				_units[key] = {"clip": c, "anim": anim, "name": c, "frame": cur, "idle": -1, "attack": -1, "seen": _stamp}
			else:
				st.merge({"clip": c, "anim": anim, "name": c, "frame": cur, "seen": _stamp, "far": false}, true)
			continue
		st.seen = _stamp
		if anim != st.anim:
			st.anim = anim
			st.name = String(anim).trim_prefix("ei/")
		var clip: String = st.get("name", st.clip)
		if clip == "":
			continue
		var prev: float = st.frame
		if clip != st.clip:   # a new clip record: the previous frame restarts at 0
			st.clip = clip
			prev = 0.0
		#  resets the previous frame only for a different clip
		# record. A wrap in the same record crosses no sound frame that tick.
		st.frame = cur
		if cur == prev or not u.visible:
			continue
		var rec: Dictionary = _clips(u.model.template).get(clip, {})
		if not rec.is_empty():
			_frame(u, st, rec, prev, cur)
	if _units.size() > n:
		for k in _units.keys():
			if int(_units[k].seen) != _stamp:
				_units.erase(k)
