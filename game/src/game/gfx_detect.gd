class_name GfxDetect
extends CanvasLayer
## Remake: a short graphics test that picks settings the device runs smoothly
## (no counterpart in the 2000 game, whose renderer had nothing to tune).
## Runs over the main menu's 3D island on the first start (no detection record
## and the graphics still at the platform defaults), after a graphics card /
## renderer change if the settings detection chose were not touched since,
## and from Options (Graphics: "Detect best settings"). Option
## auto_graphics off: never on its own.
##
## The test steps down a ladder of tiers (TIER_NAMES, tier_values): each
## tier switches off more of the remake's effects, dearest and least visible
## first, then the render scale. The device class (start_tier: OS, GPU name,
## screen, CPU count) picks the first tier tried. Each step applies the tier
## live, drops the warm-up frames (shader compiles), then measures for about a
## second (frame_cost):
##  - desktop: wall-clock frame time with VSync and the FPS cap off;
##  - phones / handhelds / web: VSync usually cannot be turned off there. With
##    the GPU time of the view (RenderingServer measured render time) when
##    the driver reports it, else the scene is drawn twice per frame (a
##    second view of the same world, `_stress`) and the frame time halved, so
##    a refresh-bound frame still shows its headroom.
## The 75th percentile of a step's frames, × the adapter's zone margin (the menu island is
## lighter than a zone), must fit the frame budget × headroom (choose). The
## result and the device fingerprint go to settings.cfg [gfx_detect]; a short
## message names the tier. Esc during the test keeps the previous settings.
## A low-FPS watchdog (Watchdog) later offers, never forces, one step down.

const SECTION := "gfx_detect"
const VERSION := 3
const ORIGINAL := 5   # the tier equal to Options' "Original look" (every gfx_* off)
const LAST := 7
const TIER_NAMES := ["High", "Medium-high", "Medium", "Low", "Very low", "Original look",
	"Original look, lower resolution", "Original look, lowest resolution"]
## The menu island is lighter than a play zone (fewer objects, units and
## lights, a 64 m map): measured costs are scaled by this before the budget.
const ZONE_FACTOR := 1.4
## Retroid Pocket 5 / Compatibility: 65 actual-device menu / zone samples
## measured Original-resolution scene costs up to 6.4 times the menu cost.
## This includes shared drawing CPU work, never divided by the two views;
## live AI / movement is a separate limit that graphics settings cannot fix.
const ADRENO_650_ZONE_FACTOR := 6.5
## Share of the frame budget a tier may use: thermal throttling on phones and
## handhelds, browsers' own work on the web.
const HEADROOM := {"desktop": 0.9, "handheld": 0.8, "web": 0.85}
## A step far over budget skips a tier (never past ORIGINAL).
const JUMP_RATIO := 1.8
## Costs within this factor of the fastest tier count as "no faster" (choose).
const FLAT := 1.15
const WARM_S := 0.4
const MEASURE_S := {"desktop": 1.0, "handheld": 1.0, "web": 0.6}
const MAX_STEPS := {"desktop": 6, "handheld": 5, "web": 3}
## No new step starts after this long (very slow devices: 200 ms frames).
const DEADLINE_S := 12.0
## Views drawn per frame in the stress mode.
const STRESS := 2

## The options the ladder sets: every gfx_* switch and the render quality.
static func keys() -> PackedStringArray:
	var out := PackedStringArray()
	for o: Array in GameData.OPTIONS:
		if String(o[0]).begins_with("gfx_"):
			out.append(o[0])
	out.append_array(["q_aa", "q_shadows", "q_aniso", "render_scale"])
	return out


## The platform's defaults (OPTIONS overlaid with Portability.defaults) for keys().
static func base_values(platform_defaults: Dictionary = Portability.defaults()) -> Dictionary:
	var d := {}
	for o: Array in GameData.OPTIONS:
		d[o[0]] = int(platform_defaults.get(o[0], o[5]))
	var out := {}
	for k in keys():
		out[k] = d[k]
	return out


## Absolute option values of `tier` on top of `base` (cumulative). Order by
## cost / visual value: screen-space passes first (volumetric mist, SSAO,
## SSR, heat haze, soft particles), then shadowed dynamic lights, bloom and
## texture / material work, then the cheap shader looks (terrain detail,
## water), then every effect (the Original look preset), then resolution.
static func tier_values(tier: int, base: Dictionary) -> Dictionary:
	var v := base.duplicate()
	if tier >= 1:
		v.gfx_volumetric = 0
		v.gfx_torch_glow = 0
		v.gfx_water_reflections = mini(v.gfx_water_reflections, 1)
		v.q_shadows = mini(v.q_shadows, 1)
		v.q_aa = mini(v.q_aa, 1)   # MSAA / TAA / FSR 2 → SMAA
	if tier >= 2:
		for k in ["gfx_ssao", "gfx_water_reflections", "gfx_heat_haze", "gfx_soft_particles", "gfx_far_view", "gfx_grass", "gfx_ground_contact", "gfx_water_interaction"]:
			v[k] = 0
	if tier >= 3:
		for k in ["gfx_firelight", "gfx_lava_light", "gfx_bloom", "gfx_hd_textures", "gfx_materials",
				"gfx_weather_surfaces", "gfx_contact_shadows", "gfx_soft_ground"]:
			v[k] = 0
		v.q_shadows = 0
		v.q_aniso = mini(v.q_aniso, 2)
	if tier >= 4:
		for k in ["gfx_terrain", "gfx_water", "gfx_detailed_heads", "gfx_foliage_light"]:
			v[k] = 0
	if tier >= ORIGINAL:
		for k: String in v:
			if k.begins_with("gfx_"):
				v[k] = 0
		v.q_aniso = mini(v.q_aniso, 1)
	if tier >= 6:
		v.q_aa = 0
		var s := mini(int(base.render_scale), 2)   # 75 %, or one step below a lower base
		if s == int(base.render_scale) and s > 0:
			s -= 1
		v.render_scale = s
	if tier >= 7:
		v.render_scale = 0
	return v


static func all_tiers(base: Dictionary) -> Array:
	var out := []
	for t in LAST + 1:
		out.append(tier_values(t, base))
	return out


## Device class: "desktop", "handheld" (Android / iOS) or "web".
static func device_kind() -> String:
	if OS.get_cmdline_user_args().has("--gfx-handheld"):   # testing the phone path on a PC
		return "handheld"
	if OS.has_feature("web"):
		return "web"
	return "handheld" if Portability.handheld() else "desktop"


## Use the measured margin only for the tested GPU / renderer combination.
## Other adapters retain the existing estimate until measured on hardware.
static func zone_factor(kind: String, adapter: String,
		method: String = RenderingServer.get_current_rendering_method()) -> float:
	var a := adapter.to_lower()
	if kind == "handheld" and method == "gl_compatibility" \
			and a.contains("adreno") and _model_number(a) == 650:
		return ADRENO_650_ZONE_FACTOR
	return ZONE_FACTOR


## The first tier tried. Desktop: High. Phones: by GPU family and generation,
## one lower for a large screen (> 2.6 Mpx), a weak CPU (≤ 4 cores) or the
## Forward+ renderer (Android's Vulkan choice, RendererChoice); then
## verified by measuring. Unknown mobile GPUs start at Low.
static func start_tier(kind: String, adapter: String, screen: Vector2i, cpus: int,
		method: String = RenderingServer.get_current_rendering_method()) -> int:
	if kind == "desktop":
		return 0
	var a := adapter.to_lower()
	var t := 3
	var num := _model_number(a)
	if a.contains("adreno"):
		if num >= 730:
			t = 1
		elif num >= 640:
			t = 2   # Adreno 640 … 7x0: Snapdragon 855 / 865 / 888 class
		elif num >= 615:
			t = 3
		else:
			t = 4
	elif a.contains("immortalis") or a.contains("apple"):
		t = 1
	elif a.contains("mali"):
		if num >= 710 or (num >= 76 and num < 100):
			t = 2   # G710+, G76 / G77 / G78
		elif num >= 57:
			t = 3
		else:
			t = 4
	elif a.contains("xclipse"):
		t = 2
	elif a.contains("powervr") or a.contains("llvmpipe") or a.contains("swiftshader"):
		t = 4
	elif kind == "web":
		t = 2   # a desktop GPU behind the browser
	if screen.x * screen.y > 2600000:
		t += 1
	if cpus > 0 and cpus <= 4:
		t += 1
	if kind == "handheld" and method == "forward_plus":
		t += 1   # Forward+ on a phone GPU (RendererChoice): the desktop renderer's fixed cost
	return clampi(t, 0, ORIGINAL)


## The first number after the GPU family name ("Adreno (TM) 650" → 650,
## "Mali-G78 MP24" → 78), 0 if none.
static func _model_number(a: String) -> int:
	for fam in ["adreno", "mali", "xclipse", "immortalis"]:
		var i := a.find(fam)
		if i < 0:
			continue
		var digits := ""
		for ch in a.substr(i + fam.length()):
			if ch >= "0" and ch <= "9":
				digits += ch
			elif not digits.is_empty():
				break
		return digits.to_int() if not digits.is_empty() else 0
	return 0


## The frame rate to reach: 60, or the display's refresh if lower (≥ 30).
static func target_fps(refresh: float) -> float:
	if not (refresh > 0.0) or is_inf(refresh):   # unknown: -1, or NaN (Xvfb)
		return 60.0
	return clampf(roundf(refresh), 30.0, 60.0)


static func fits(cost_ms: float, fps: float, headroom: float, zone: float) -> bool:
	return cost_ms * zone <= 1000.0 / fps * headroom


## The ladder search. `measure(tier) -> float` gives a tier's frame cost (ms,
## on the test scene). cfg: tiers (all_tiers), target (fps), handheld (bool),
## headroom, zone, max_steps. Goes down from `start` to the first tier that
## fits; unless cfg.original_at_target is false, ORIGINAL is accepted without
## the zone margin (the full resolution matters more than headroom there).
## A calibrated handheld still prefers Original resolution at the 30 FPS
## fallback, where lowering resolution cannot fix shared drawing / AI CPU.
## Identical tiers (e.g. effects a phone's
## defaults already have off) are not measured again. Out of steps: one tier
## below the last that failed. Phones / handhelds: if 60 needs the lowest
## resolution or cannot be had at all, the best measured tier that holds 30 at
## or above ORIGINAL, capped at 30 FPS. When lowering the settings does not
## make frames faster (FLAT: the CPU, the driver's present or a frame cap is
## the limit, not the graphics), on desktop the search stops after three steps and the
## first tier measured within FLAT of the fastest is kept ("flat"). Phones
## always go on: there the Original look guarantee matters more.
## Returns {tier, fps (0 or 30), costs, steps, found, flat}.
static func choose(start: int, measure: Callable, cfg: Dictionary) -> Dictionary:
	var tiers: Array = cfg.get("tiers", [])
	var target: float = cfg.get("target", 60.0)
	var head: float = cfg.get("headroom", 0.9)
	var zone: float = cfg.get("zone", ZONE_FACTOR)
	var max_steps: int = cfg.get("max_steps", 6)
	var hand: bool = cfg.get("handheld", false)
	var original_at_target: bool = cfg.get("original_at_target", true)
	var costs := {}
	var steps := 0
	var t := clampi(start, 0, LAST)
	var found := -1
	var last_t := -1
	var last_cost := 0.0
	var first_cost := -1.0
	var min_cost := INF
	while t <= LAST:
		var c := last_cost
		var same: bool = last_t >= 0 and t < tiers.size() and last_t < tiers.size() and tiers[t] == tiers[last_t]
		if not same:
			if steps >= max_steps:
				break
			c = float(measure.call(t))
			steps += 1
		if first_cost < 0.0:
			first_cost = c
		min_cost = minf(min_cost, c)
		costs[t] = c
		last_t = t
		last_cost = c
		if fits(c, target, head, zone) or (original_at_target and t == ORIGINAL and fits(c, target, head, 1.0)):
			found = t
			break
		if not hand and steps >= 3 and first_cost <= min_cost * FLAT:
			break
		var nxt := t + 1
		if c * zone / (1000.0 / target * head) > JUMP_RATIO and t + 2 <= ORIGINAL:
			nxt = t + 2
		t = nxt
	var tier := found
	var fps := 0
	var flat := false
	if found < 0:
		tier = mini(last_t + 1, LAST) if last_t >= 0 else LAST
		var ks := costs.keys()
		ks.sort()
		if not hand and not ks.is_empty() and first_cost <= min_cost * FLAT:
			flat = true
			for k: int in ks:
				if costs[k] <= min_cost * FLAT:
					tier = k
					break
	if hand and (found < 0 or found > ORIGINAL + 1):
		var ks := costs.keys()
		ks.sort()
		var best := -1
		for k: int in ks:
			if fits(costs[k], 30.0, head, zone) or (k == ORIGINAL and fits(costs[k], 30.0, head, 1.0)):
				best = k
				break
		if best >= 0 and best <= ORIGINAL:
			tier = best
			fps = 30
		elif found < 0:
			fps = 30
	return {"tier": tier, "fps": fps, "costs": costs, "steps": steps, "found": found, "flat": flat}


## The values to store for a result (the tier's options, and the 30 FPS cap
## on phones; desktop keeps its frame rate limit).
static func result_values(res: Dictionary, base: Dictionary, kind: String) -> Dictionary:
	var v := tier_values(int(res.tier), base)
	if kind != "desktop":
		v.fps_limit = 1 if int(res.get("fps", 0)) == 30 else 2   # GameData.FPS_LIMITS: 30 / 60
	return v


# ------------------------------------------------------------------ record

static func fingerprint() -> String:
	return "%s|%s|%s|%s" % [OS.get_name(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()]


static func load_record(path := GameData.CONFIG_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not cfg.has_section(SECTION):
		return {}
	var r := {}
	for k in cfg.get_section_keys(SECTION):
		r[k] = cfg.get_value(SECTION, k)
	# Retired remake toggle: keep automatic-tier/manual detection valid when
	# loading an older record, without changing any remaining graphics choice.
	if r.get("values") is Dictionary:
		r.values.erase("gfx_edge_fade")
	return r


## Replaces the [gfx_detect] section (GameData.save_settings keeps it).
static func save_record(rec: Dictionary, path := GameData.CONFIG_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	if cfg.has_section(SECTION):
		cfg.erase_section(SECTION)
	for k: String in rec:
		cfg.set_value(SECTION, k, rec[k])
	cfg.save(path)


static func _matches(current: Dictionary, values: Dictionary) -> bool:
	for k: String in values:
		if int(current.get(k, -1)) != int(values[k]):
			return false
	return true


## Why the test should run by itself now ("first", "device", "version"), or "" (also
## "manual": the record to write so a hand-made choice is not asked again).
## First start: no record and the graphics as the platform defaults; another
## GPU / renderer: only while the settings are still those detection chose.
static func auto_reason(rec: Dictionary, current: Dictionary, base: Dictionary, fp: String, enabled: bool) -> String:
	if not enabled:
		return ""
	if rec.is_empty():
		return "first" if _matches(current, base) else "manual"
	var vals: Dictionary = rec.get("values", {})
	if int(rec.get("tier", -1)) >= 0 and not vals.is_empty() and _matches(current, vals):
		if String(rec.get("fingerprint", "")) != fp:
			return "device"
		if int(rec.get("version", 0)) < VERSION:
			return "version"
	return ""


## The detection's settings are still in force (nothing changed by hand).
static func untouched(rec: Dictionary, current: Dictionary) -> bool:
	var vals: Dictionary = rec.get("values", {})
	return int(rec.get("tier", -1)) >= 0 and not vals.is_empty() and _matches(current, vals)


# ------------------------------------------------------------------ Original look

## Options' "Original look" toggle (OptionsPanel, the PRESET_ROW of the three
## remake graphics pages): on while every gfx_* switch is off. It touches
## only the gfx_* switches (render quality, render scale and the frame-rate
## cap stay as they are).
static func original_look_on(values: Dictionary) -> bool:
	for k in keys():
		if k.begins_with("gfx_") and int(values.get(k, 0)) != 0:
			return false
	return true


## The tier to come back to when Original look is switched on now over
## `current`: the detection's tier while its settings are still in force
## (untouched) and it has effects on (below ORIGINAL), else -1.
static func original_look_from(rec: Dictionary, current: Dictionary) -> int:
	if untouched(rec, current) and int(rec.tier) < ORIGINAL:
		return int(rec.tier)
	return -1


## The gfx_* values the toggle sets. On: all off. Off: those of the detected
## tier `from` (the record's values, as the test stored them) when Original
## look was switched on over the detection's settings, else the platform's
## defaults (a fresh install's values here, `base`).
static func original_look_values(on: bool, rec: Dictionary, from: int, base: Dictionary = base_values()) -> Dictionary:
	var src := base
	var vals: Dictionary = rec.get("values", {}) if rec.get("values") is Dictionary else {}
	if not on and from >= 0 and from < ORIGINAL and int(rec.get("tier", -1)) == from and not vals.is_empty():
		src = vals
	var out := {}
	for k in keys():
		if k.begins_with("gfx_"):
			out[k] = 0 if on else int(src.get(k, base.get(k, 0)))
	return out


## The record after the player switched Original look on or off (Options ✓):
## a choice of the player's, so the detection treats it as one. On over the
## detection's settings: "original_look_from" keeps the tier to restore; the
## settings no longer match the record's values, so the low-FPS watchdog and
## the new-GPU re-test leave them alone (`untouched` false). Off: the key goes;
## restored to the detected tier the settings match its values again (the
## watchdog may offer a step down as before), restored to the defaults they
## stay the player's own. No record yet (no test ever ran): the "manual"
## record, so the first-start test does not replace the choice.
static func original_look_record(rec: Dictionary, on: bool, from: int) -> Dictionary:
	var r := rec.duplicate(true)
	if r.is_empty():
		r = {"version": VERSION, "fingerprint": fingerprint(), "tier": -1, "manual": 1}
	if on and from >= 0:
		r.original_look_from = from
	else:
		r.erase("original_look_from")
	return r


# ------------------------------------------------------------------ running

## The main menu, once built: the automatic run when auto_reason asks for one.
## Not in test tools (unless `--gfx-detect`), headless runs or without a 3D scene.
static func auto_start() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless":
		return
	if Array(args).any(func(a): return String(a).begins_with("--tool=")) and not args.has("--gfx-detect"):
		return
	Watchdog.ensure()
	var rec := load_record()
	var reason := auto_reason(rec, GameData.options, base_values(), fingerprint(), GameData.option("auto_graphics") != 0)
	if reason == "manual":
		save_record({"version": VERSION, "fingerprint": fingerprint(), "tier": -1, "manual": 1})
		return
	if reason != "":
		GameData.trace("graphics detection: " + reason)
		start(false)


## Starts the test (one at a time) over whatever the main view shows.
static func start(manual_run: bool) -> GfxDetect:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or DisplayServer.get_name() == "headless":
		return null
	for n in tree.root.get_children():
		if n is GfxDetect and not n.is_queued_for_deletion():
			return n
	var d := GfxDetect.new()
	d.manual = manual_run
	tree.root.add_child(d)
	return d


signal finished(result: Dictionary)

var manual := false
var kind := "desktop"
var result := {}
var _overlay: Overlay
var _box: MessageBox
var _cancelled := false
var _before := {}
var _base := {}
var _tiers: Array = []
var _mode := "wall"   # wall / gpu / stress
var _stress: SubViewport
var _stress_cam: Camera3D
var _old_vsync := DisplayServer.VSYNC_ENABLED
var _env: Environment
var _env_saved := {}
var _step := 0


func _ready() -> void:
	layer = 104
	process_mode = Node.PROCESS_MODE_ALWAYS
	kind = device_kind()
	_overlay = Overlay.new()
	_overlay.owner_detect = self
	add_child(_overlay)
	_run.call_deferred()


func _run() -> void:
	# After the startup screen and movies (StartupScreen, MovieSequence).
	var t0 := Time.get_ticks_msec()
	while _busy_screen() and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _wait(0.5)
	_base = base_values()
	_tiers = all_tiers(_base)
	for k in keys():
		_before[k] = GameData.option(k)
	_before.fps_limit = GameData.option("fps_limit")
	_prepare()
	var screen := DisplayServer.screen_get_size()
	var start := start_tier(kind, RenderingServer.get_video_adapter_name(), screen, OS.get_processor_count())
	var margin := zone_factor(kind, RenderingServer.get_video_adapter_name())
	var cfg := {"tiers": _tiers, "target": target_fps(DisplayServer.screen_get_refresh_rate()),
		"handheld": kind != "desktop", "headroom": HEADROOM[kind], "zone": margin,
		"original_at_target": margin == ZONE_FACTOR,
		"max_steps": MAX_STEPS[kind]}
	GameData.trace("graphics detection: %s, %s, start tier %d, target %.0f FPS" % [kind, RenderingServer.get_video_adapter_name(), start, cfg.target])
	_overlay.status = RemakeText.t("Testing graphics for this device…")
	var res := {}
	if not _cancelled:
		res = await _choose_async(start, cfg)
	_finish_measuring()
	if _cancelled:
		_set_values(_before)
		_apply_live()
		_restore_env()
		if not manual:
			save_record({"version": VERSION, "fingerprint": fingerprint(), "tier": -1, "cancelled": 1})
		_overlay.visible = false
		_message(RemakeText.t("Graphics test skipped; the settings are unchanged."))
		return
	result = res
	var vals := result_values(res, _base, kind)
	_set_values(vals)
	GameData.save_settings()
	_apply_live()
	_restore_env()
	save_record({"version": VERSION, "fingerprint": fingerprint(), "tier": int(res.tier),
		"fps": int(res.fps), "values": vals, "start": start, "mode": _mode,
		"zone_factor": margin,
		"costs": res.costs, "date": Time.get_datetime_string_from_system()})
	GameData.trace("graphics detection: tier %d (%s), fps cap %d, mode %s, costs %s" % [res.tier, TIER_NAMES[res.tier], res.fps, _mode, res.costs])
	_overlay.visible = false
	_message(RemakeText.t("Graphics set to %s for this device. You can change this in Options.") % tier_label(int(res.tier), int(res.fps)))
	finished.emit(res)


static func tier_label(tier: int, fps: int) -> String:
	var s := RemakeText.t(TIER_NAMES[clampi(tier, 0, LAST)])
	return s + " (30 FPS)" if fps == 30 else s


## choose() with the measurements awaited one by one.
func _choose_async(start: int, cfg: Dictionary) -> Dictionary:
	var measured := {}
	var t0 := Time.get_ticks_msec()
	# choose() is synchronous: replay it, measuring the tier it asks for next.
	while true:
		if Time.get_ticks_msec() - t0 > DEADLINE_S * 1000.0 and not measured.is_empty():
			cfg.max_steps = measured.size()   # out of time: decide on what was measured
		var need := [-1]
		var res := choose(start, func(t: int) -> float:
			if measured.has(t):
				return measured[t]
			if need[0] < 0:
				need[0] = t
			return 1.0e6, cfg)
		if need[0] < 0 or _cancelled:
			return res
		_step += 1
		_overlay.detail = "%s  (%d)" % [RemakeText.t(TIER_NAMES[need[0]]), _step]
		measured[need[0]] = await _measure(need[0])
	return {}


func _busy_screen() -> bool:
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if n is StartupScreen or n is MovieSequence:
			return true
	return false


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


## Measurement setup: the FPS cap and (where it works) VSync off, the frame
## timers on, the menu's environment kept to restore.
func _prepare() -> void:
	var vp := get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	_old_vsync = DisplayServer.window_get_vsync_mode()
	_env = vp.find_world_3d().environment if vp.find_world_3d() else null
	if _env and not _in_game():
		_env_saved = {"ssao_enabled": _env.ssao_enabled, "glow_enabled": _env.glow_enabled,
			"volumetric_fog_enabled": _env.volumetric_fog_enabled, "reflected_light_source": _env.reflected_light_source}
	_mode = "wall" if kind == "desktop" else "probe"


func _finish_measuring() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
	if is_instance_valid(_stress):
		_stress.queue_free()
	_stress = null
	DisplayServer.window_set_vsync_mode(_old_vsync)


## The menu island keeps its original environment (MenuScene: no remake
## passes); the test switched them on to measure their cost.
func _restore_env() -> void:
	if _env and not _env_saved.is_empty() and is_instance_valid(_env) and not _in_game():
		for k: String in _env_saved:
			_env.set(k, _env_saved[k])


func _in_game() -> bool:
	var main := get_tree().current_scene
	return main != null and main.get("game") != null


func _set_values(vals: Dictionary) -> void:
	for k: String in vals:
		GameData.options[k] = int(vals[k])


## The options in force at once, as Options' ✓ does (GameData.set_option)
## without writing the file each time.
func _apply_live() -> void:
	GameData._apply_window()
	if _env and is_instance_valid(_env):
		Gfx.apply_env(_env)
	EIFigure.set_wind(Gfx.on("gfx_wind"))
	for n in get_tree().root.find_children("*", "", true, false):
		if n is EITerrain:
			(n as EITerrain).apply_gfx()
	GameData.options_changed.emit()


func _apply_tier(t: int) -> void:
	_set_values(_tiers[t])
	_apply_live()
	Engine.max_fps = 0
	if _mode != "stress":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


## One tier's frame cost (ms): the 75th percentile after the warm-up.
func _measure(t: int) -> float:
	_apply_tier(t)
	var dur: float = MEASURE_S[kind]
	await _frames(WARM_S, 10)   # shader compiles and buffer reallocation
	if _mode == "probe":
		var probe: Dictionary = await _frames(0.3, 10)
		var gpu := _pct(probe.gpu, 0.5)
		_mode = "gpu" if gpu > 0.05 and not OS.get_cmdline_user_args().has("--gfx-stress") else "stress"
		if _mode == "stress":
			_make_stress()
			await _frames(WARM_S, 8)
	# Until frames stop getting faster (shaders still compiling at their
	# first draw, as GLES drivers and software renderers do), at most 3 s.
	var prev := INF
	var w0 := Time.get_ticks_msec()
	while not _cancelled and Time.get_ticks_msec() - w0 < 3000:
		var m := _cost(await _frames(0.0, 4), 0.5)
		if m >= prev * 0.85:
			break
		prev = m
	var s: Dictionary = await _frames(dur, 6)
	var cost := _cost(s, 0.75)
	GameData.trace("graphics detection: tier %d %s %.2f ms (%d frames)" % [t, _mode, cost, s.wall.size()])
	return cost if not _cancelled else 1.0e6


## A batch of frames' cost (ms) at quantile `p`: wall-clock; the view's GPU
## time (or the CPU's share if larger); the stress mode's wall-clock per view.
func _cost(s: Dictionary, p: float) -> float:
	match _mode:
		"gpu":
			return maxf(_pct(s.gpu, p), _pct(s.cpu, p))
		"stress":
			# Script/physics and shared frame setup run once for both views.
			# Halving that work can mistake a CPU-bound scene for GPU headroom.
			return maxf(_pct(s.wall, p) / STRESS, _pct(s.cpu, p))
	return _pct(s.wall, p)


## Frames for at least `secs` and `min_n` frames (at most 3 s): wall-clock,
## GPU and CPU times in ms.
func _frames(secs: float, min_n: int) -> Dictionary:
	var out := {"wall": PackedFloat32Array(), "gpu": PackedFloat32Array(), "cpu": PackedFloat32Array(),
		"process": PackedFloat32Array(), "physics": PackedFloat32Array(), "setup": PackedFloat32Array(),
		"view_cpu": PackedFloat32Array()}
	var rid := get_viewport().get_viewport_rid()
	var tree := get_tree()
	# The monitor is a one-second maximum of a single physics tick. Measure
	# this frame's whole physics phase, including multiple catch-up ticks.
	var physics_start := [-1]
	var mark_physics := func() -> void:
		if physics_start[0] < 0:
			physics_start[0] = Time.get_ticks_usec()
	tree.physics_frame.connect(mark_physics)
	var t0 := Time.get_ticks_usec()
	var last := t0
	while not _cancelled:
		await tree.process_frame
		var process_start := Time.get_ticks_usec()
		var physics_ms := (process_start - int(physics_start[0])) / 1000.0 if physics_start[0] >= 0 else 0.0
		physics_start[0] = -1
		_sync_stress()
		# TIME_PROCESS also includes RenderingServer.draw and is a one-second
		# maximum, so adding viewport CPU time to it counts rendering twice.
		# Measure the node-processing phase before draw instead.
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_pre_draw
		var now := Time.get_ticks_usec()
		out.wall.append((now - last) / 1000.0)
		last = now
		out.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		var process_ms := (now - process_start) / 1000.0
		var setup_ms := RenderingServer.get_frame_setup_time_cpu()
		var view_ms := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		out.process.append(process_ms)
		out.physics.append(physics_ms)
		out.setup.append(setup_ms)
		out.view_cpu.append(view_ms)
		out.cpu.append(process_ms + physics_ms + setup_ms + view_ms)
		var el := (now - t0) / 1.0e6
		if (el >= secs and out.wall.size() >= min_n) or el >= 3.0:
			break
	tree.physics_frame.disconnect(mark_physics)
	return out


## The p-quantile of `a`, single spikes (over 4 × the median: a shader
## compiled at its first draw, a driver hitch) left out.
static func _pct(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var all := a.duplicate()
	all.sort()
	var med := all[all.size() / 2]
	var s := PackedFloat32Array()
	for v in all:
		if v <= med * 4.0:
			s.append(v)
	return s[clampi(int(p * (s.size() - 1) + 0.5), 0, s.size() - 1)]


## A second view of the same world from the same camera, drawn every frame.
func _make_stress() -> void:
	var vp := get_viewport()
	_stress = SubViewport.new()
	_stress.size = Vector2i(vp.get_visible_rect().size)
	_stress.world_3d = vp.find_world_3d()
	_stress.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_stress.msaa_3d = vp.msaa_3d
	_stress.screen_space_aa = vp.screen_space_aa
	_stress.scaling_3d_mode = vp.scaling_3d_mode
	_stress.scaling_3d_scale = vp.scaling_3d_scale
	_stress.positional_shadow_atlas_size = vp.positional_shadow_atlas_size
	_stress.audio_listener_enable_3d = false
	_stress_cam = Camera3D.new()
	_stress.add_child(_stress_cam)
	add_child(_stress)
	_stress_cam.current = true
	_sync_stress()


func _sync_stress() -> void:
	if not is_instance_valid(_stress):
		return
	var vp := get_viewport()
	_stress.scaling_3d_scale = vp.scaling_3d_scale
	_stress.msaa_3d = vp.msaa_3d
	var cam := vp.get_camera_3d()
	if cam:
		_stress_cam.global_transform = cam.global_transform
		_stress_cam.fov = cam.fov
		_stress_cam.near = cam.near
		_stress_cam.far = cam.far
		_stress_cam.cull_mask = cam.cull_mask


func _message(text: String) -> void:
	_box = MessageBox.new()
	_box.title = RemakeText.t("Graphics")
	_box.message = text
	_box.ok_only = true
	_box.esc_closes = true
	add_child(_box)
	_box.answered.connect(func(_y): queue_free())
	_box.dismissed.connect(queue_free)


func cancel() -> void:
	_cancelled = true


## The progress text over the scene (original 800×600 interface font).
class Overlay extends Interface800:
	var owner_detect: GfxDetect
	var status := "":
		set(v):
			status = v
			queue_redraw()
	var detail := "":
		set(v):
			detail = v
			queue_redraw()

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP   # the menu waits
		resized.connect(queue_redraw)

	func _draw() -> void:
		if status.is_empty():
			return
		panel(Rect2(180, 470, 440, 86))
		text(Rect2(190, 478, 420, 24), status, 2, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		text(Rect2(190, 504, 420, 22), detail, 1, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		text(Rect2(190, 530, 420, 20), RemakeText.t("Esc: skip the test"), 0, GREY, HORIZONTAL_ALIGNMENT_CENTER)

	func _input(e: InputEvent) -> void:
		if not visible:
			return
		if e is InputEventKey or e is InputEventJoypadButton:
			if e.is_pressed() and (e is InputEventKey and (e as InputEventKey).keycode == KEY_ESCAPE
					or e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_B):
				owner_detect.cancel()
				status = RemakeText.t("Restoring the settings…")
			get_viewport().set_input_as_handled()

	func _gui_input(e: InputEvent) -> void:
		accept_event()



# ------------------------------------------------------------------ watchdog

## Seconds of low frame rate before the offer.
const WATCH_S := 20.0
## "Low": below this share of the target frame rate.
const WATCH_LOW := 0.75


## One second of play for the watchdog: the low-FPS time so far, `fps`
## measured against `target`. Low seconds count up; good ones take off three
## (a short dip in a big fight does not add up over a session).
static func watch_step(acc: float, fps: float, target: float, dt: float) -> float:
	if fps < target * WATCH_LOW:
		return acc + dt
	return maxf(0.0, acc - 3.0 * dt)


## The frame rate the detection aimed at (its 30 FPS cap, else 60 or the
## display's refresh).
static func watch_target(rec: Dictionary) -> float:
	if int(rec.get("fps", 0)) == 30:
		return 30.0
	return target_fps(DisplayServer.screen_get_refresh_rate())


## The low-FPS watchdog: in a zone, on a device where the test chose the
## settings and they are still in force, ~20 s well below the target offer
## the next tier down in a small notice at the top (Lower / Hide), once per
## session. Never changes anything by itself.
class Watchdog extends Interface800:
	var _acc := 0.0
	var _tick := 0.0
	var _offered := false
	var _shown := 0.0
	var _rec := {}
	var _next := -1

	static func ensure() -> void:
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null or tree.root.has_node("GfxWatchdog"):
			return
		var layer := CanvasLayer.new()
		layer.name = "GfxWatchdog"
		layer.layer = 103
		layer.process_mode = Node.PROCESS_MODE_PAUSABLE   # paused: nothing counts
		var w := Watchdog.new()
		layer.add_child(w)
		tree.root.add_child.call_deferred(layer)

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _in_zone() -> bool:
		var main := get_tree().current_scene
		var game: Variant = main.get("game") if main else null
		return game != null and is_instance_valid(game) and game.get("world") != null

	func _process(dt: float) -> void:
		if visible:
			_shown += dt
			if _shown > 25.0:
				visible = false
			return
		if _offered:
			return
		_tick += dt
		if _tick < 1.0:
			return
		var step := _tick
		_tick = 0.0
		if GameData.option("auto_graphics") == 0 or not _in_zone() or not DisplayServer.window_is_focused():
			_acc = 0.0
			return
		if _acc == 0.0:
			_rec = GfxDetect.load_record()
		if int(_rec.get("tier", -1)) < 0 or int(_rec.tier) >= GfxDetect.LAST or not GfxDetect.untouched(_rec, GameData.options):
			return
		_acc = GfxDetect.watch_step(_acc, Engine.get_frames_per_second(), GfxDetect.watch_target(_rec), step)
		if _acc >= GfxDetect.WATCH_S:
			_offered = true
			_next = int(_rec.tier) + 1
			_shown = 0.0
			visible = true
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			queue_redraw()

	func _rects() -> Dictionary:
		return {"panel": Rect2(170, 40, 460, 74), "lower": Rect2(250, 88, 140, 20), "hide": Rect2(410, 88, 140, 20)}

	func _draw() -> void:
		var r := _rects()
		panel(r.panel)
		var msg := RemakeText.t("The game runs slowly here. Lower the graphics to %s?") % GfxDetect.tier_label(_next, 0)
		text_block(Rect2(180, 46, 440, 40), msg, 1, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		text(r.lower, RemakeText.t("Lower"), 1, Interface800.colorref(0x31b3ff), HORIZONTAL_ALIGNMENT_CENTER)
		text(r.hide, RemakeText.t("Not now"), 1, GREY, HORIZONTAL_ALIGNMENT_CENTER)

	## Clicks on the two words only; the rest of the screen plays on.
	func _input(e: InputEvent) -> void:
		if not visible or not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
			return
		var p := to800(e.position)
		var r := _rects()
		if (r.lower as Rect2).grow(4).has_point(p):
			get_viewport().set_input_as_handled()
			sound("messbox\\ok")
			visible = false
			lower(_rec, _next)
		elif (r.hide as Rect2).grow(4).has_point(p):
			get_viewport().set_input_as_handled()
			sound("messbox\\cancel")
			visible = false

	## Applies tier `t` as the detection would have and keeps the record in
	## step (so the settings still count as the detection's).
	static func lower(rec: Dictionary, t: int) -> void:
		var vals := GfxDetect.result_values({"tier": t, "fps": int(rec.get("fps", 0))}, GfxDetect.base_values(), GfxDetect.device_kind())
		for k: String in vals:
			GameData.options[k] = int(vals[k])
		GameData.save_settings()
		GameData._apply_window()
		GameData.options_changed.emit()
		rec.tier = t
		rec.values = vals
		rec.lowered = int(rec.get("lowered", 0)) + 1
		GfxDetect.save_record(rec)
		GameData.trace("graphics watchdog: lowered to tier %d" % t)
