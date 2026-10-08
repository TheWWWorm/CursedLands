extends "local_shadow_selection.gd"
## Tests the actual manager's elapsed transitions, separately from selection
## tests that settle fades. GPU captures also check the zero-opacity pass
## boundary that must preserve ordinary lighting before fades are enabled.

var gpu_report := {}

func bounded(f: Dictionary) -> void:
	var active := 0
	var banks := 0
	for d: Dictionary in f.fx.lights + f.manager._lava:
		if not is_instance_valid(d.light):
			continue
		if d.light.shadow_enabled:
			active += 1
			banks += int(d.has("cell"))
		var marker := Gfx.LOCAL_SPECULAR_PASS if d.light.shadow_enabled and Portability.compatibility() else Gfx.LOCAL_SPECULAR
		check(is_equal_approx(d.light.light_specular, marker), "pass marker follows actual resident flag")
	check(active <= LocalLighting.SHADOW_LIMIT and banks <= LocalLighting.LAVA_SHADOW_LIMIT,
			"every intermediate step stays within both resident budgets")
	check(f.manager._shadow_fades.size() == active, "resident state matches actual shadow flags")
	check(f.manager._shadow_wanted.size() <= LocalLighting.SHADOW_LIMIT, "pending targets stay bounded")
	for id: int in f.manager._shadow_since:
		check(f.manager._shadow_fades.has(id) and f.manager._shadow_wanted.has(id),
				"tenure belongs only to admitted current targets")

func choose(f: Dictionary, x: float) -> void:
	f.manager._assign_shadows(f.fx, f.camera, Vector3(x, 2, 0))
	bounded(f)

func advance(f: Dictionary, dt: float) -> void:
	f.manager._time += dt
	f.manager._advance_shadows(dt)
	bounded(f)

func fading_fixture() -> Dictionary:
	var f := fixture()
	# Exercise the state machine headlessly and on both backends. The rendered
	# transition test below uses the production backend gate without overriding.
	f.manager._fade_shadows = true
	return f

func test_exchange() -> void:
	var f := fading_fixture()
	var pair := clustered_fire(f)
	var before := []
	for d: Dictionary in f.fx.lights:
		before.append([d.light, d.light.light_energy, d.light.light_color, d.light.position])
	choose(f, -2)
	check(pair[0].shadow_enabled and pair[0].shadow_opacity == 0.0, "first admission begins at zero")
	for i in 4:
		advance(f, 0.1)
		check(is_equal_approx(pair[0].shadow_opacity, (i + 1) * 0.25), "initial shadow ramps over 0.4 seconds")
	advance(f, 1.61)
	choose(f, 2)
	check(pair[0].shadow_enabled and not pair[1].shadow_enabled, "full budget defers the incoming map")
	for i in 3:
		advance(f, 0.1)
		check(is_equal_approx(pair[0].shadow_opacity, 0.75 - i * 0.25), "outgoing shadow fades before slot release")
		check(not pair[1].shadow_enabled, "pending light never creates a fifth map")
	advance(f, 0.1)
	check(not pair[0].shadow_enabled and pair[1].shadow_enabled and pair[1].shadow_opacity == 0.0,
			"replacement acquires released slot at zero opacity")
	check(is_equal_approx(f.manager._shadow_since[pair[1].get_instance_id()], f.manager._time),
			"pending time does not consume replacement tenure")
	for i in 4:
		advance(f, 0.1)
		check(is_equal_approx(pair[1].shadow_opacity, (i + 1) * 0.25), "replacement fades to authored strength")
	advance(f, 1.3)
	choose(f, -2)
	check(f.manager._shadow_wanted.has(pair[1].get_instance_id()), "incoming light keeps tenure measured from admission")
	advance(f, 0.31)
	choose(f, -2)
	check(f.manager._shadow_wanted.has(pair[0].get_instance_id()), "replacement can change after its own tenure")
	for row: Array in before:
		check(row[0].light_energy == row[1] and row[0].light_color == row[2] and row[0].position == row[3],
				"transition never alters light energy, colour or position")
	dispose(f)

func test_reversal_and_expiry() -> void:
	var f := fading_fixture()
	var pair := clustered_fire(f)
	choose(f, -2)
	advance(f, 2.01)
	choose(f, 2)
	advance(f, 0.1)
	var partial := pair[0].shadow_opacity
	choose(f, -2)
	check(pair[0].shadow_opacity == partial, "reversing a fade does not jump opacity")
	advance(f, 0.1)
	check(is_equal_approx(pair[0].shadow_opacity, 1.0) and not pair[1].shadow_enabled,
			"reversal restores the same map without admitting the cancelled target")
	Gfx.set_local_shadow(pair[0], false)
	choose(f, -2)
	check(pair[0].shadow_enabled and pair[0].shadow_opacity == 0.0,
			"external shadow disable restarts admission instead of keeping stale strength")
	check(f.manager._shadow_since[pair[0].get_instance_id()] == f.manager._time,
			"external disable restarts tenure")
	advance(f, 0.4)
	pair[0].hide()
	advance(f, 0.01)
	check(not pair[0].shadow_enabled, "hidden resident releases before the next scan")
	choose(f, 2)
	check(pair[1].shadow_enabled, "hard eligibility loss makes a slot available immediately")
	pair[1].queue_free()
	advance(f, 0.01)
	check(not pair[1].shadow_enabled, "queued resident cannot keep fading")
	pair[0].show()
	choose(f, -2)
	pair[0].position = Vector3(500, 2, 0)
	choose(f, -2)
	check(not pair[0].shadow_enabled, "out-of-range resident does not reserve an outgoing slot")
	f.manager._disable_shadows(f.fx)
	check(f.manager._shadow_fades.is_empty() and f.manager._shadow_wanted.is_empty()
			and f.manager._shadow_since.is_empty(), "no-camera reset cancels all transition state")
	dispose(f)
	# Pending targets can disappear while the four original maps fade out.
	f = fading_fixture()
	pair = clustered_fire(f)
	choose(f, -2)
	advance(f, 2.01)
	choose(f, 2)
	var id := pair[1].get_instance_id()
	pair[1].free()
	advance(f, 0.4)
	check(not f.manager._shadow_wanted.has(id), "freed pending target is discarded through its weak reference")
	dispose(f)

func test_lava_transitions() -> void:
	var f := fading_fixture()
	clustered_fire(f)
	choose(f, -2)
	advance(f, 0.4)
	var entries: Array[Dictionary] = [{"cell": 1, "pos": Vector3(-10, 1, 0)},
			{"cell": 2, "pos": Vector3(0, 1, 0)}, {"cell": 3, "pos": Vector3(10, 1, 0)}]
	lava(f, entries)
	choose(f, -2)
	check(lava_ids(f).is_empty(), "new lava reservation waits for outgoing fire slots")
	for i in 4:
		advance(f, 0.1)
	check(lava_ids(f) == [1, 2], "two lava maps replace fire without exceeding the shared budget")
	advance(f, 0.4)
	advance(f, 1.61)
	choose(f, 2)
	advance(f, 0.2)
	check(lava_ids(f) == [1, 2], "lava-to-lava exchange keeps at most two resident banks")
	var reused: OmniLight3D = f.manager._lava[0].light
	lava(f, [entries[1], entries[2], {"cell": 4, "pos": Vector3(30, 1, 0)}])
	check(not reused.shadow_enabled and reused.shadow_opacity == 1.0, "reused lava cell loses partial opacity and old map")
	choose(f, 2)
	advance(f, 0.4)
	check(lava_ids(f) == [2, 3], "new lava selection takes the released slot")
	lava(f, [])
	choose(f, -2)
	check(f.manager._shadow_fades.size() == 4 and lava_ids(f).is_empty(), "inactive lava releases slots to fire immediately")
	GameData.options["gfx_lava_light"] = 0
	f.manager.apply_options()
	check(f.manager._lava.is_empty(), "lava option clears its pool during transition")
	GameData.options["gfx_lava_light"] = 1
	dispose(f)

func test_original_restoration() -> void:
	var f := fading_fixture()
	var light := OmniLight3D.new()
	light.shadow_enabled = true
	light.shadow_opacity = 0.6
	light.light_specular = 0.31
	light.omni_range = 8.0
	f.world.add_child(light)
	var record := {"light": light, "kind": "spell", "external_energy": true,
			"energy": 1.0, "pos": Vector3.ZERO, "until": -1}
	LocalLighting.prepare_particle(record)
	f.fx.lights.append(record)
	choose(f, 0)
	advance(f, 0.2)
	check(is_equal_approx(light.shadow_opacity, 0.3), "fade respects authored opacity ceiling")
	light.light_energy = 0.17
	GameData.options["gfx_firelight"] = 0
	f.manager.apply_options()
	check(light.shadow_enabled and is_equal_approx(light.shadow_opacity, 0.6)
			and is_equal_approx(light.light_specular, 0.31), "option off restores authored shadow properties mid-fade")
	check(is_equal_approx(light.light_energy, 0.17), "option off preserves externally controlled spell fade")
	check(f.manager._shadow_fades.is_empty() and f.manager._shadow_wanted.is_empty(), "option off leaves no deferred opacity writer")
	f.manager.apply_options()
	f.manager._advance_shadows(1.0)
	check(light.shadow_enabled and is_equal_approx(light.shadow_opacity, 0.6), "repeated off option preserves original shadows")
	GameData.options["gfx_firelight"] = 1
	f.manager.apply_options()
	choose(f, 0)
	advance(f, 0.1)
	f.game.world = null
	f.manager._process(0.1)
	check(light.shadow_enabled and is_equal_approx(light.shadow_opacity, 0.6), "world change restores the old world's original opacity")
	check(f.manager._shadow_fades.is_empty() and f.manager._shadow_wanted.is_empty(), "world change clears weak transition tables")
	f.game.world = f.world
	f.manager._world = f.world
	f.manager.apply_options()
	choose(f, 0)
	advance(f, 0.1)
	f.manager.free()
	check(light.shadow_enabled and is_equal_approx(light.shadow_opacity, 0.6), "manager exit restores authored shadow mid-fade")
	f.game.free()
	f.world.free()
	f.camera.free()

func test_process_order() -> void:
	var f := fading_fixture()
	clustered_fire(f)
	f.manager._process(0.1)
	bounded(f)
	check(f.manager._shadow_fades.size() == 4, "normal process admits its first selection")
	for d: Dictionary in f.fx.lights:
		if d.light.shadow_enabled:
			check(d.light.shadow_opacity == 0.0, "new selection does not consume elapsed time from before admission")
	f.manager._process(0.1)
	bounded(f)
	for d: Dictionary in f.fx.lights:
		if d.light.shadow_enabled:
			check(is_equal_approx(d.light.shadow_opacity, 0.25), "normal process advances admitted maps next frame")
	dispose(f)

func delta(a: Image, b: Image) -> Dictionary:
	var aa := a.get_data()
	var bb := b.get_data()
	var total := 0
	var peak := 0
	for p in range(0, aa.size(), 4):
		for c in 3:
			var difference := absi(aa[p + c] - bb[p + c])
			total += difference
			peak = maxi(peak, difference)
	return {"changed_pixels": changed_pixels(a, b), "max_channel_delta": peak,
			"mean_channel_delta": float(total) / (a.get_width() * a.get_height() * 3)}

func test_pass_boundary() -> void:
	var f := rendered_fixture()
	scan(f, 0, -2)
	f.pair[0].shadow_opacity = 0.0
	var zero := await capture(f.view, "pass-zero")
	Gfx.set_local_shadow(f.pair[0], false)
	var disabled := await capture(f.view, "pass-disabled")
	for x in 8:
		var light := fire(f, Vector3(-3.5 + x, 0.5, 2.5))
		light.light_energy = 0.04 + x * 0.01
		light.omni_attenuation = 0.0
	Gfx.set_local_shadow(f.pair[0], true)
	var crowded_zero := await capture(f.view, "pass-crowded-zero")
	Gfx.set_local_shadow(f.pair[0], false)
	var crowded_disabled := await capture(f.view, "pass-crowded-disabled")
	gpu_report["pass_boundary"] = delta(zero, disabled)
	gpu_report["crowded_pass_boundary"] = delta(crowded_zero, crowded_disabled)
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		check(zero.get_data() == disabled.get_data() and crowded_zero.get_data() == crowded_disabled.get_data(),
				"Forward+ zero-opacity flags preserve all unoccluded lighting pixels")
	elif RenderingServer.get_current_rendering_method() == "gl_compatibility":
		var args := OS.get_cmdline_user_args()
		var expected := not args.has("--no-local-shadow-fades") and (not Portability.constrained() or args.has("--local-shadow-fades"))
		check(f.manager._fade_shadows == expected, "Compatibility fade policy follows platform and explicit test switches")
		if expected:
			check(delta(zero, disabled).max_channel_delta <= 2 and delta(crowded_zero, crowded_disabled).max_channel_delta <= 2,
					"Compatibility pass change stays within output quantization at both light counts")
	else:
		check(not f.manager._fade_shadows, "unvalidated backend keeps production fades disabled")
	dispose(f)
	f.view.free()

func test_rendered_fades() -> void:
	var f := rendered_fixture()
	if RenderingServer.get_current_rendering_method() == "forward_plus" or f.manager._fade_shadows:
		check(f.manager._fade_shadows, "validated backend uses production fade policy")
	if not f.manager._fade_shadows:
		dispose(f)
		f.view.free()
		return
	choose(f, -2)
	advance(f, 2.01)
	var first := await capture(f.view, "fade-initial")
	choose(f, 2)
	var start := await capture(f.view, "fade-start")
	check(first.get_data() == start.get_data(), "selection change begins without an instantaneous pixel jump")
	var previous := first
	var steps := []
	for i in 8:
		advance(f, 0.1)
		var next := await capture(f.view, "fade-step-" + str(i + 1))
		steps.append(delta(previous, next))
		previous = next
	var abrupt := delta(first, previous)
	check(abrupt.changed_pixels > 100, "fixture exchanges a visible shadow")
	for measured: Dictionary in steps:
		check(measured.max_channel_delta > 0 and measured.max_channel_delta < abrupt.max_channel_delta,
				"each timed fade step is visible and smaller than the immediate exchange")
	# Stable endpoint must be identical to the old immediate flag exchange.
	f.manager._disable_shadows(f.fx)
	f.manager._fade_shadows = false
	scan(f, 5, 2)
	var direct := await capture(f.view, "fade-direct-endpoint")
	check(previous.get_data() == direct.get_data(), "settled fade preserves the original selection's rendered endpoint")
	f.manager._fade_shadows = true
	choose(f, 2)
	advance(f, 0.2)
	var partial := await capture(f.view, "fade-partial-caster")
	f.blocker.position.x += 0.6
	var moved := await capture(f.view, "fade-moved-caster")
	check(changed_pixels(partial, moved) > 100, "partially faded maps still update moving casters")
	f.pair[1].position.x += 0.6
	var carried := await capture(f.view, "fade-moved-light")
	check(changed_pixels(moved, carried) > 100, "partially faded maps follow carried lights")
	gpu_report["exchange"] = abrupt
	gpu_report["steps"] = steps
	gpu_report["endpoint"] = delta(previous, direct)
	gpu_report["moving_caster_pixels"] = changed_pixels(partial, moved)
	gpu_report["moving_light_pixels"] = changed_pixels(moved, carried)
	dispose(f)
	f.view.free()

func _ready() -> void:
	GameData.options["gfx_firelight"] = 1
	GameData.options["gfx_lava_light"] = 1
	GameData.options["vsync"] = 0
	GameData.options["fps_limit"] = 0
	test_exchange()
	test_reversal_and_expiry()
	test_lava_transitions()
	test_original_restoration()
	test_process_order()
	if DisplayServer.get_name() != "headless":
		await test_pass_boundary()
		if RenderingServer.get_current_rendering_method() in ["forward_plus", "gl_compatibility"]:
			await test_rendered_fades()
	var report := {"checks": checks, "failures": failures, "gpu": gpu_report,
			"renderer": RenderingServer.get_current_rendering_method(), "editor": OS.has_feature("editor"),
			"light_limit": ProjectSettings.get_setting("rendering/limits/opengl/max_lights_per_object")}
	var output := "user://local-shadow-fades-" + RenderingServer.get_current_rendering_method() + ".json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t") + "\n")
	else:
		check(false, "report saved")
	print("LOCAL_SHADOW_FADES ", JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
