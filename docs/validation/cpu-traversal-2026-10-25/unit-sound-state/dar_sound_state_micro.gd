extends "dar_standard_route.gd"
const Previous = preload("repo/tools/tests/unit_sound_state_reference.gd")

func sound_state(collector) -> Dictionary:
	var result := {}
	for key in collector._units:
		var st = collector._units[key]
		result[key] = [st.clip,st.anim,st.name,st.frame,st.idle,st.attack,
			st.get("far",false) if st is Dictionary else st.far]
	return result

func phase(label: String,seconds: float,goal := Vector2.INF,pan := false) -> void:
	await super.phase(label,seconds,goal,pan)
	if label != "final-held": return
	var old = Previous.new(g.sound.mixer,s.world)
	var current := UnitSounds.new(g.sound.mixer,s.world)
	# Same live actors, player timelines, listener and normal mixer. The first
	# observation is silent. Repeated current-frame scans must emit no events.
	old.tick(); current.tick()
	var expected := sound_state(old)
	check(expected == sound_state(current),"live sound state starts identically")
	var sound_serial := g.sound.mixer._next_handle
	var rows := []
	var near := 0
	var listener := Vector2(g.sound.mixer.listener.x,g.sound.mixer.listener.y)
	for actor: GameUnit in s.world.unit_rows():
		if actor.pos.distance_squared_to(listener) <= UnitSounds.MAX_D * UnitSounds.MAX_D: near += 1
	for candidate: bool in [false,true,true,false]:
		var collector = current if candidate else old
		var started := Time.get_ticks_usec()
		for repeat in 4000: collector.tick()
		var elapsed := Time.get_ticks_usec()-started
		check(sound_state(collector) == expected,"same live state after timed scans")
		check(g.sound.mixer._next_handle == sound_serial,"current-frame scans produce no duplicate sound requests")
		rows.append({"candidate":candidate,"usec":elapsed,"calls":4000,
			"actors":s.world.units.size(),"near":near,"states":collector._units.size()})
	check(old._stamp == current._stamp,"both scans advance exactly one stamp per call")
	write_file("sound-state-micro.json",JSON.stringify(rows,"\t"))
	print("SOUND_STATE_LIVE_MICRO ",JSON.stringify(rows))
