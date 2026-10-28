extends "local_host_campaign.gd"
## The game-speed family (#62, #98, #116, #119) reopened because each fix
## measured one quantity in one situation. This test measures the player-
## visible quantities together: world time, the Eagle Sight countdown, mana
## recovery and walking distance of the hero, at normal and fast speed, on a
## fresh worker load in the Foothills, after a save taken at fast speed is
## loaded again, and after a Ruins round trip. Every quantity must follow
## the selected rate (55/27 for fast) and the fast/normal ratio must stay
## distinct. Eagle Sight is measured while the buff is present; whether it
## survives the console travel is recorded, not asserted.
const FAST := 55.0 / 27.0
var samples: Array[Dictionary] = []
var mana_ratios := 0

func ready(s: Session, seconds := 60.0) -> bool:
	return await until(func(): return s.world != null and not s._remote_loading and LoadingScreen._current == null \
		and ShaderCompilationScreen._current == null, seconds)

## A walkable point about ten units from the hero, or Vector2.INF. Short
## walks keep the hero near its quiet entrance, away from patrols.
func walk_target(s: Session, hero: GameUnit) -> Vector2:
	for angle in 8:
		var target: Vector2 = hero.pos + Vector2.RIGHT.rotated(angle * PI / 4.0) * 10.0
		if s.world.nav != null and s.world.nav.size.x > 0 and s.world.nav.cell_open(target, hero.move_class()):
			return target
	return Vector2.INF

## Order the hero to `target` until it visibly moves (an order sent while a
## zone is still settling can be dropped).
func moving(s: Session, hero: GameUnit, target: Vector2) -> bool:
	var origin := hero.pos
	for attempt in 12:
		s.submit({"t":"move", "units":[hero.uid], "x":target.x, "y":target.y})
		await get_tree().create_timer(0.5, true, false, true).timeout
		if (hero.pos - origin).length() > 0.3: return true
	return false

## One measurement: an idle window first (world time, Eagle Sight and mana,
## which the original only recovers while standing idle; three seconds hold
## 3-4 recovery steps at normal and 7-8 at fast speed without reaching the
## cap from an empty pool), then a walking window (world time, Eagle Sight,
## distance).
func measure(s: Session, g: Game, phase: String, speed: int, select := true) -> Dictionary:
	if select: g.set_speed(speed)
	await get_tree().create_timer(0.5, true, false, true).timeout
	var hero: GameUnit = s.world.party_units()[0]
	var eagle := hero.effect_ticks("eagle_sight") > 0
	var mana0 := hero.mana; var ticks0 := hero.effect_ticks("eagle_sight"); var sim0 := s.world.time
	var start := Time.get_ticks_usec()
	await get_tree().create_timer(3.0, true, false, true).timeout
	var wall := (Time.get_ticks_usec() - start) / 1000000.0
	var idle := hero.action == "idle"
	var mana := hero.mana - mana0
	var capped := mana0 >= hero.max_mana - 0.5 or hero.mana >= hero.max_mana - 0.5
	var world_idle := (s.world.time - sim0) / wall
	var eagle_idle := (ticks0 - hero.effect_ticks("eagle_sight")) * GameUnit.TICK / wall
	var target := walk_target(s, hero)
	var walking := target != Vector2.INF and await moving(s, hero, target)
	ticks0 = hero.effect_ticks("eagle_sight"); sim0 = s.world.time
	var pos0 := hero.pos
	start = Time.get_ticks_usec()
	await get_tree().create_timer(2.5, true, false, true).timeout
	wall = (Time.get_ticks_usec() - start) / 1000000.0
	var expected := FAST if speed == 2 else 1.0
	var row := {"phase":phase, "speed":speed, "world_walking":(s.world.time - sim0) / wall, "world_idle":world_idle,
		"eagle_walking":(ticks0 - hero.effect_ticks("eagle_sight")) * GameUnit.TICK / wall, "eagle_idle":eagle_idle,
		"eagle_left":hero.effect_ticks("eagle_sight"), "mana":mana, "max_mana":hero.max_mana,
		"mana_capped":capped, "idle":idle, "walked":(hero.pos - pos0).length(), "walking":walking, "buffs":hero.buffs.keys(),
		"action":hero.action, "dial":g.speed, "field":s.field_speed, "presented":Engine.time_scale}
	samples.append(row); print("SPEED_SAMPLE ", JSON.stringify(row))
	var tag := "%s at speed %d: " % [phase, speed]
	check(absf(float(row.world_walking) - expected) < 0.2 and absf(float(row.world_idle) - expected) < 0.2, tag + "world time follows the selected rate")
	row.eagle = eagle
	if eagle:
		check(absf(float(row.eagle_walking) - expected) < 0.2 and absf(float(row.eagle_idle) - expected) < 0.2, tag + "Eagle Sight countdown follows the selected rate")
	else:
		print("NOTE ", tag, "Eagle Sight absent (buffs ", row.buffs, "); countdown not measured")
	# A patrol may reach the entrance and draw the hero into a fight, where
	# the original recovers no mana; that window then measures no recovery.
	if idle:
		check(capped or mana > 0.0, tag + "mana recovers while idle")
	else:
		print("NOTE ", tag, "the hero is busy (", row.action, "); mana recovery not measured")
	check(walking and float(row.walked) > 1.0, tag + "the hero walks")
	check(int(row.dial) == speed - 1 and int(row.field) == speed - 1, tag + "dial and field keep the selection")
	return row

func compare(normal: Dictionary, fast: Dictionary, phase: String) -> void:
	check(float(fast.world_idle) / maxf(0.01, float(normal.world_idle)) > 1.8, phase + ": fast/normal world time stays distinct")
	if bool(normal.eagle) and bool(fast.eagle):
		check(float(fast.eagle_idle) / maxf(0.01, float(normal.eagle_idle)) > 1.8, phase + ": fast/normal Eagle Sight stays distinct")
	if bool(normal.idle) and bool(fast.idle) and not bool(normal.mana_capped) and not bool(fast.mana_capped):
		check(float(fast.mana) / maxf(0.1, float(normal.mana)) > 1.5, phase + ": fast mana recovery is faster")
		mana_ratios += 1
	if bool(normal.walking) and bool(fast.walking):
		check(float(fast.walked) / maxf(0.1, float(normal.walked)) > 1.6, phase + ": the hero walks farther at fast speed")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0, "net_websocket":0, "net_lan":0, "net_directory":0, "autosave":0, "show_tutorial":0}, true)
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	var seed := Session.new(); add_child(seed)
	seed.local_host.worker = true; seed.local_host.single_player = true
	var seed_game := Game.new(); seed_game.session = seed; seed.game = seed_game; add_child(seed_game)
	seed.state.ensure_hero(0, "Human Hero")
	seed._enter_zone("gz3g", 1, false)
	seed.state.god_modes[0] = 1
	var hero: GameUnit = seed.world.party_units()[0]
	hero.mana = 0.0; hero.aggressive = false
	hero.buffs.eagle_sight = {"until":seed.world.time + 600.0, "_effect_ticks":10800, "sense":[0, 10.0]}
	seed.restore_play_clock({"speed":0, "paused":false})
	check(seed.save_game("speed-matrix-seed") == OK, "Foothills fixture saved")
	seed_game.queue_free(); seed.queue_free()
	for i in 8: await get_tree().process_frame
	var s := Session.new(); get_parent().add_child(s)
	var g := Game.new(); g.session = s; s.game = g; get_parent().add_child(g)
	check(await s.local_host.start(0, 1, true) == OK, "separate solo worker starts")
	check((await s.local_host.request("load", {"slot":"speed-matrix-seed"})).get("ok", false), "worker loads the fixture")
	check(await ready(s), "Foothills ready")

	# Each load starts from the saved pool and position, so the windows are
	# comparable and the entrance is still quiet.
	var normal := await measure(s, g, "loaded", 1)
	check((await s.local_host.request("load", {"slot":"speed-matrix-seed"})).get("ok", false), "worker reloads the fixture")
	check(await ready(s), "Foothills ready again")
	g.set_speed(2)
	await get_tree().create_timer(0.5, true, false, true).timeout
	# A save taken at fast speed restores fast speed and the same rates.
	var answer := await s.local_host.request("save", {"slot":"speed-matrix-fast", "camera":s.local_host.view()})
	check(answer.get("ok", false), "save at fast speed")
	check(int(s.saved_play_clock().get("speed", -1)) == 1, "the save records fast speed")
	var fast := await measure(s, g, "loaded", 2, false)
	compare(normal, fast, "loaded")

	check((await s.local_host.request("load", {"slot":"speed-matrix-fast"})).get("ok", false), "worker loads the fast save")
	check(await ready(s), "loaded fast save ready")
	check(g.speed == 1 and s.field_speed == 1, "loading restores the fast selection")
	fast = await measure(s, g, "reloaded", 2, false)
	check((await s.local_host.request("load", {"slot":"speed-matrix-fast"})).get("ok", false), "worker loads the fast save again")
	check(await ready(s), "loaded fast save ready again")
	normal = await measure(s, g, "reloaded", 1)
	compare(normal, fast, "reloaded")

	# Two zone transitions (to the Ruins and back) keep the rates of both
	# selections; the measurement returns to the quiet Foothills entrance.
	var request := 1
	for zone: String in ["gz1g", "gz3g"]:
		s.submit({"t":"console", "line":"travel " + zone, "request":request}); request += 1
		check(await until(func(): return s.zone_id == zone and not s._remote_loading, 60), "arrives in " + zone)
		check(await ready(s), zone + " ready")
		await get_tree().create_timer(2.0, true, false, true).timeout
	normal = await measure(s, g, "travelled", 1)
	fast = await measure(s, g, "travelled", 2)
	compare(normal, fast, "travelled")
	g.set_speed(1)
	check(Engine.time_scale == 1.0, "returning to normal presents 1x at once")
	check(mana_ratios >= 1, "at least one phase compared idle mana recovery at both speeds")

	await s.local_host.stop()
	g.queue_free(); s.queue_free()
	for i in 8: await get_tree().process_frame
	FileAccess.open("user://speed-scaling-matrix.json", FileAccess.WRITE).store_string(JSON.stringify(samples, "\t"))
	print("SPEED_SCALING_MATRIX ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
