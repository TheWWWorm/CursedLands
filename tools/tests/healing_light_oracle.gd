extends Node
## Compare healing against independently executed x86 light trajectories.
## --fixture=<original_spell_light_expected.json>, retained outside the repo.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _ready() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fixture="): path = a.trim_prefix("--fixture=")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var rows: Array = data.filter(func(r): return int(r.code) == 24) if data is Array else []
	check(rows.size() == 2, "two original x86 healing trajectories supplied")
	var world := GameWorld.new()
	add_child(world); world.set_physics_process(false)
	var ticks := 0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var sp := Spells.parse("healing").duplicate(true)
		sp.id = "healing_oracle_%d" % i
		sp.duration = int(row.duration); sp.radius = float(row.area_radius)
		sp.proto.light_radius = float(row.row_radius); sp.proto.fadeout = float(row.fadeout)
		sp.proto.red = 0.1; sp.proto.green = 0.2; sp.proto.blue = 0.3
		Spells._cache[sp.id] = sp
		var fx := SpellFx.spawn_event(world, {"spell":sp.id,"x":row.point[0],"y":row.point[1],"z":row.point[2]})
		check(fx != null, "case%d creates native healing light" % i)
		if fx == null: continue
		fx.set_process(false)
		var position_matches := true
		var light_matches := true
		var cleanup_matches := true
		for sample: Dictionary in row.samples:
			fx.advance(int(sample.tick)); ticks += 1
			if sample.present:
				var p := Vector3(sample.position[0], sample.position[1], sample.position[2])
				position_matches = position_matches and ParticleFx.ei(fx.position).is_equal_approx(p)
				light_matches = light_matches and fx._light.light_color.is_equal_approx(Color(
					sample.rgb[0],sample.rgb[1],sample.rgb[2])) and is_equal_approx(
					fx._light.omni_range,absf(float(sample.radius))) and fx._light.light_energy == 1.0
			cleanup_matches = cleanup_matches and fx.is_queued_for_deletion() == not bool(sample.present)
		check(position_matches, "case%d every native float32 position matches" % i)
		check(light_matches, "case%d native colour, range and energy stay constant" % i)
		check(cleanup_matches, "case%d exact native cleanup tick" % i)
		fx.free(); Spells._cache.erase(sp.id)
	# Removing healing's halo must not suppress the other spell presentations.
	var other := SpellFx.spawn_event(world,{"spell":"acid_column","light_pos":[0,0,0]})
	check(other != null and other._light.get_child_count() == 1,"non-healing spell retains its existing halo")
	if other: other.free()
	var healing := SpellFx.spawn_event(world,{"spell":"healing","light_pos":[0,0,0]})
	if healing:
		LocalLighting.apply_particle(healing._local_light,false)
		LocalLighting.apply_particle(healing._local_light,true)
		healing.advance(20)
	check(healing != null and healing._light.get_child_count() == 0,"local lighting toggle never recreates healing orb")
	if healing: healing.free()
	world.free()
	print("HEALING_LIGHT_ORACLE %d checks %d failures; %d native ticks compared" % [checks,failures,ticks])
	get_tree().quit(0 if failures == 0 else 1)
