extends "local_shadow_fades.gd"
## Test actual admission and ownership, then independently measure each
## candidate's rendered shadow signal. Frozen prior exports are negative
## controls, not alternative implementations embedded in this tool.

var impact_rows := []
var cost_rows := []

func measure_selection_cost(count: int) -> void:
	var f := fixture()
	for i in count:
		var light := fire(f, Vector3((i % 16 - 7.5) * 2.0, 2, (i / 16 - 3.0) * 2.0))
		light.light_energy = [0.03, 0.3, 1.7][i % 3]
		light.omni_range = [4.0, 8.0, 12.0][i % 3]
	scan(f, 0, -2)
	var elapsed: Array[int] = []
	for i in 320:
		f.manager._time += 0.25
		var start := Time.get_ticks_usec()
		f.manager._assign_shadows(f.fx, f.camera, Vector3(-2, 2, 0))
		var usec := Time.get_ticks_usec() - start
		if i >= 64: elapsed.append(usec)
	elapsed.sort()
	bounded(f)
	cost_rows.append({"lights":count, "samples":elapsed.size(), "scan_median_usec":elapsed[elapsed.size() / 2],
			"scan_p95_usec":elapsed[int(elapsed.size() * 0.95)]})
	dispose(f)

func test_weighted_admission() -> void:
	for feature in ["energy", "colour", "range", "authored-opacity"]:
		var f := fixture()
		var pair := clustered_fire(f, 0.1 if feature == "authored-opacity" else 1.0)
		if feature == "energy":
			pair[0].light_energy = 0.1
		elif feature == "colour":
			pair[0].light_color = Color(0.2, 0.2, 0.2)
		elif feature == "range":
			pair[1].omni_range = 12.0
		var original := [pair[0].light_energy, pair[0].light_color, pair[0].omni_range,
				pair[1].light_energy, pair[1].light_color, pair[1].omni_range]
		scan(f, 0, -2)
		check(pair[1].shadow_enabled and not pair[0].shadow_enabled,
				feature + " can make the farther light more useful than the nearer light")
		check(original == [pair[0].light_energy, pair[0].light_color, pair[0].omni_range,
				pair[1].light_energy, pair[1].light_color, pair[1].omni_range], "ranking does not rewrite light properties")
		dispose(f)

func test_zero_contribution() -> void:
	for feature in ["energy", "colour", "authored-opacity"]:
		var f := fixture()
		var pair := clustered_fire(f, 0.0 if feature == "authored-opacity" else 1.0)
		scan(f, 0, -2)
		if feature == "energy":
			pair[0].light_energy = 0.0
		elif feature == "colour":
			pair[0].light_color = Color.BLACK
		scan(f, 0.25, -2)
		check(not pair[0].shadow_enabled and pair[1].shadow_enabled,
				feature + " at zero cannot keep a slot")
		check(not f.manager._shadow_since.has(pair[0].get_instance_id()), "zero contribution leaves no tenure")
		dispose(f)
	var f := fixture()
	clustered_fire(f)
	lava(f, [{"cell":1, "pos":Vector3(-10, 1, 0)}, {"cell":2, "pos":Vector3(0, 1, 0)},
			{"cell":3, "pos":Vector3(10, 1, 0)}])
	scan(f, 0, -2)
	for d: Dictionary in f.manager._lava:
		if d.cell == 2: d.light.light_energy = 0.0
	scan(f, 0.25, -2)
	check(lava_ids(f) == [1, 3], "dark lava does not reserve a shadow over a contributing bank")
	dispose(f)

func test_strength_stability() -> void:
	var f := fading_fixture()
	var pair := clustered_fire(f)
	choose(f, -2)
	check(pair[0].shadow_enabled and pair[0].shadow_opacity == 0.0, "new resident begins at zero opacity")
	choose(f, -2)
	check(pair[0].shadow_enabled, "zero transition opacity is not mistaken for zero authored strength")
	advance(f, 0.2)
	choose(f, -2)
	check(pair[0].shadow_enabled, "partial transition opacity does not lower ranking")
	advance(f, 2.0)
	# Independent flicker stays inside the existing 1.25 hysteresis. The
	# elapsed hold has expired, so this does not merely exercise tenure.
	var energies := [pair[0].light_energy, pair[1].light_energy]
	for tick in 24:
		pair[0].light_energy = energies[0] * (0.92 if tick % 2 else 1.08)
		pair[1].light_energy = energies[1] * (1.08 if tick % 2 else 0.92)
		scan(f, 3.0 + tick * 0.25, 0)
		check(pair[0].shadow_enabled and not pair[1].shadow_enabled, "ordinary flutter does not exchange nearly equal shadows")
	dispose(f)

func test_rendered_importance(situation: String) -> void:
	var f := rendered_fixture()
	if situation == "brightness":
		f.pair[0].light_energy = 0.02
	else:
		for i in 3:
			f.fx.lights[i].light.position.z = -0.1 * (i + 1)
			f.fx.lights[i].light.light_energy = 1.7
		f.pair[0].omni_range = 5.0
		f.pair[1].omni_range = 10.0
	var lights: Array[OmniLight3D] = []
	for d: Dictionary in f.fx.lights:
		lights.append(d.light)
		Gfx.set_local_shadow(d.light, false)
	var clear := await capture(f.view, "importance-" + situation + "-clear")
	var signals := []
	for i in lights.size():
		lights[i].shadow_opacity = 0.0
		Gfx.set_local_shadow(lights[i], true)
		var zero := await capture(f.view, "importance-" + situation + "-zero-" + str(i))
		lights[i].shadow_opacity = 1.0
		var shadow := await capture(f.view, "importance-" + situation + "-light-" + str(i))
		# Hold native light/pass membership constant while measuring opacity.
		# The separate boundary records reveal per-object light-limit effects.
		var impact := delta(zero, shadow)
		impact["pass_boundary"] = delta(clear, zero)
		impact["light"] = i
		signals.append(impact)
		Gfx.set_local_shadow(lights[i], false)
	var selected := scan(f, 0, -2)
	var selected_indices := []
	var total := 0.0
	var retained := 0.0
	var strongest := 0
	for i in lights.size():
		var impact: float = signals[i].mean_channel_delta
		total += impact
		if impact > float(signals[strongest].mean_channel_delta): strongest = i
		if selected.has(lights[i].get_instance_id()):
			selected_indices.append(i)
			retained += impact
	check(signals[strongest].changed_pixels > 100, "importance fixture has a visible measured shadow")
	check(selected_indices.has(strongest), "selection retains the independently measured strongest shadow")
	await capture(f.view, "importance-" + situation + "-selected")
	var row := {"situation":situation, "selected":selected_indices, "strongest":strongest,
			"retained_signal_fraction":retained / maxf(total, 0.000001), "signals":signals}
	impact_rows.append(row)
	print("LOCAL_SHADOW_IMPORTANCE_ROW ", JSON.stringify(row))
	dispose(f)
	f.view.free()

func _ready() -> void:
	GameData.options["gfx_firelight"] = 1
	GameData.options["gfx_lava_light"] = 1
	GameData.options["vsync"] = 0
	GameData.options["fps_limit"] = 0
	if OS.get_cmdline_user_args().has("--shadow-importance-cost"):
		for count in [16, 64, 128]: measure_selection_cost(count)
	else:
		test_weighted_admission()
		test_zero_contribution()
		test_strength_stability()
		if DisplayServer.get_name() != "headless":
			await test_rendered_importance("brightness")
			await test_rendered_importance("range")
	var report := {"checks":checks, "failures":failures, "rendered_impact":impact_rows, "selection_cost":cost_rows,
			"renderer":RenderingServer.get_current_rendering_method(), "editor":OS.has_feature("editor")}
	FileAccess.open("user://local-shadow-importance-" + RenderingServer.get_current_rendering_method() + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("LOCAL_SHADOW_IMPORTANCE ", JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
