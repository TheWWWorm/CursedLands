extends "arena_local_host.gd"
var prepared := {}
var outcomes := {}
var states := {}
var blasts := {}
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="): GameData.campaign_roots[CampaignProfile.ASTRAL] = arg.trim_prefix("--astral-path=")
	check(ArenaExpansion.mount(), "frontend mounts expansion")
	GameData.options.net_upnp = 0; GameData.arena_character = "lia_hero"
	var host := connection("Astral worker"); host.expansion = true
	host.solo_prepared.connect(func(data): prepared = data)
	host.solo_result.connect(func(data): outcomes[int(data.seat)] = data)
	host.board_received.connect(func(data): states[int(data.seat)] = data)
	host.effects_received.connect(func(data):
		for event: Dictionary in data.events:
			if event.get("effect", "") == "popper_blast": blasts[int(data.seat)] = true)
	check(await host.local_host.start(0,false,true) == OK, "private worker mounts second installation and handshakes")
	if not host.local_host.owned: get_tree().quit(1); return
	var child := host.local_host.process_id
	var league := ArenaTournamentRun.new(); league.auto_save = false; league.expansion = true; league.live_boards = true; league.begin(7319)
	league.wave = 4
	for player in 9:
		var company := league.company(player); company.army.clear(); company.wave = 4
		for family in [32,33,35] if player % 2 == 0 else [32,34,37]: company._recruit(family,0,1)
		company.arrange()
	league._prepare_round()
	for plan: Dictionary in league.bot_plans: plan.done = true
	var snapshot := league.snapshot()
	host._send(1,{"t":"solo_prepare","snapshot":snapshot,"speed":2})
	check(await until(func(): return not prepared.is_empty(),30), "LiA armies prepare in separate worker")
	check(not prepared.get("error",false) and prepared.get("boards",[]).size() == 9, "nine native boards prepare")
	host._send(1,{"t":"view","seat":-1})
	host._send(1,{"t":"solo_clock","round":4,"paused":false,"speed":2})
	check(await until(func(): return outcomes.size() == 9,75), "all LiA battles finish in separate worker")
	var oracle := ArenaOnlineGame.new(); oracle.run.expansion = true; add_child(oracle); oracle.begin(7319,{0:""}); oracle.set_process(false)
	check(oracle.run.restore(snapshot), "oracle restores identical expansion preparation")
	oracle._prepare(); oracle.start_round()
	for tick in 2300:
		if oracle.run.stage != "fight": break
		oracle.advance_clock(GameUnit.TICK)
		if tick % 80 == 0: await frames(1)
	for player in 9:
		check(outcomes.has(player), "outcome arrives for board " + str(player))
		if not outcomes.has(player): continue
		var expected: Dictionary = oracle.run.board_results[player]
		check(int(outcomes[player].winner) == int(expected.winner) and Array(outcomes[player].survivors) == Array(expected.survivors), "native result agrees " + str(player))
		check(is_equal_approx(float(outcomes[player].time),oracle.encounter(player).world.time), "native clock agrees " + str(player))
		check(blasts.has(player), "native blast is delivered " + str(player))
	oracle.queue_free()
	await host.close_shown(); check(not OS.is_process_running(child), "private worker exits cleanly")
	host.queue_free(); await frames(3)
	print("ARENA_ASTRAL_WORKER checks=",checks," failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
