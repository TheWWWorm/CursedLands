extends "lia_kel_support.gd"
## Loaded original maps and authored VM threads; only traversal/combat are
## accelerated. Each suite names its prepared inputs in its report scope.

func wait_zone(id: String) -> bool:
	await frames(3)
	var deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		if s.world != null and s.zone_id == id and not s.loading_game:
			freeze(); return check(true,"authored transition reaches "+id)
		await frames(1)
	return check(false,"authored transition reaches "+id)

func advance_until(condition: Callable, label: String, maximum := 4000) -> bool:
	var deadline := Time.get_ticks_msec()+90000
	var count := 0
	while Time.get_ticks_msec()<deadline and count<maximum:
		if not s.loading_game and condition.call():
			freeze(); return check(true,label)
		if s.loading_game:
			await frames(1); continue
		s.world._tick(GameUnit.TICK)
		count += 1
		if count%20 == 0: await frames(1)
	return check(false,label)

func normal_exit(number: int, destination: String) -> bool:
	var ex: Dictionary = s.world.zone.exits[number]
	var point: Vector2 = ex.remove.get_center()
	if not check(s.open_exit_at(point,0) == number,"normal exit is open: "+s.zone_id+" -> "+destination): return false
	for u: GameUnit in s.party_heroes(): u.pos = point; u.resync_drawn()
	s.apply_command({"t":"move","units":[hero().uid],"x":point.x,"y":point.y,"exit":number},0)
	s._check_exits()
	if not check(MessageBox.is_up(game.hud._leave_box),"ordinary exit confirmation opens"): return false
	game.hud._leave_box._answer(true)
	await frames(3)
	if String(s.campaign.zone(String(ex.to)).get("type","")) == "edge":
		check(s.map_open,"authored edge opens the travel map")
		var options: Array = s.travel_options.filter(func(row):return row.zone == destination)
		if not check(not options.is_empty(),"earned edge offers destination "+destination): return false
		s.apply_command({"t":"travel","zone":destination,"entrance":options[0].entrance},0)
	return await wait_zone(destination)

func poll_once(label: String) -> void:
	var before := accounting()
	ticks(15)
	check(accounting() == before,label+": repeated trigger polls do not repeat rewards")

func party_at(point: Vector2) -> void:
	for u: GameUnit in s.party_heroes():
		u.command({"type":"wait","t":0.0}); u.pos = point; u.resync_drawn()
	ticks()
