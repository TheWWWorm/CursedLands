extends Node
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FAIL ",message)
func frames(count: int) -> void:
	for index in count: await get_tree().process_frame
func wait_for(predicate: Callable, seconds := 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return predicate.call()
func pair(use_websocket: bool) -> void:
	var host := ArenaOnlineSession.new(); host.player_name="Host"; add_child(host)
	var client := ArenaOnlineSession.new(); client.player_name="Guest"; add_child(client)
	var port := 29816 if use_websocket else 29815
	check(host.host(port,use_websocket)==OK,"host listens")
	check(client.join(("ws://" if use_websocket else "")+"127.0.0.1:%d"%port)==OK,"client connects")
	check(await wait_for(func():return client.my_seat==1),"handshake assigns an independent human seat")
	if client.my_seat!=1: host.queue_free();client.queue_free();return
	check(host.members.size()==2 and client.members.size()==2,"lobby converges")
	check(host.start_game(7319)=="Wait for every player to be ready.","unready joiner blocks start")
	client.request("ready")
	check(await wait_for(func():return host.members.values().all(func(member):return member.ready)),"client ready reaches host")
	check(host.start_game(7319).is_empty(),"ready lobby starts")
	check(await wait_for(func():return client.started and not client.last_state.is_empty()),"client receives initial state")
	host.game.set_process(false)
	check(host.game.run.humans.size()==2 and host.game.run.rivals.size()==8,"two humans plus seven bots")
	var guest := host.game.run.company(1)
	var original_gold := guest.gold
	client.request("buy",[0])
	check(await wait_for(func():return guest.army.size()==1),"client buys through host authority")
	check(host.game.run.army.is_empty() and guest.gold<original_gold,"purchase affects only the sender's company")
	check(await wait_for(func():return client.view.army==guest.army and client.view.gold==guest.gold),"client receives authoritative purchase")
	check(client.view.shop.size()==6 and client.view.rivals.all(func(rival):return rival.shop.is_empty()),"rival shops remain private")
	var offer := guest.shop[1].duplicate(true)
	guest.shop[1].family = (int(offer.family) + 1) % ArenaRules.FAMILIES.size()
	client.request("buy",[1]); await frames(12)
	check(guest.army.size()==1,"a stale shop click cannot buy a different creature")
	guest.shop[1] = offer
	var gold := guest.gold
	client._send(1,{"t":"command","action":"buy","args":[1],"seq":client._sequence,"round":1})
	await frames(12)
	check(guest.gold==gold,"replayed sequence cannot spend twice")
	var own_uid := int(guest.army[0].uid)
	client.request("deploy",[own_uid,Vector2(NAN,22)])
	await frames(12)
	check(is_finite(float(guest.army[0].point[0])),"nonfinite deployment rejected")
	client.request("deploy",[own_uid,Vector2(100,100)])
	await frames(12)
	check(ArenaRun.DEPLOY.has_point(Vector2(guest.army[0].point[0],guest.army[0].point[1])),"out-of-bounds deployment rejected")
	var untouched := guest.snapshot()
	host.game.run.finish_preparation()
	check(guest.snapshot()==untouched,"bots do not shop for a human")
	check(host.game.run.company(2).deployed_count()>0,"empty seats recruit using the existing bot policy")
	host.request("buy",[0]); await frames(12)
	host.game.start_round()
	check(host.game.run.stage=="fight" and guest.stage=="fight","all human companies enter combat together")
	var before_army := guest.army.duplicate(true)
	var saved_gold := guest.battle_savings
	client.request("bench",[own_uid]); await frames(12)
	check(guest.army==before_army,"combat formation is locked")
	client.request("buy",[1]); await wait_for(func():return guest.army.size()>before_army.size())
	check(guest.battle_savings==saved_gold,"combat shopping preserves start-of-round interest")
	var frame := host.game.board_frame(1,true)
	var replica := ArenaOnlineMatch.new(); replica.rendered=false; replica.run=client.view
	add_child(replica); var parent:=Node3D.new(); add_child(parent); replica._world_parent=parent
	replica.apply_board(frame)
	check(not replica.world.authority and replica.world.units.size()==host.game.encounter(1).world.units.size(),"replica builds the host's actors without simulation authority")
	var ticks:=0
	while host.game.run.stage=="fight" and ticks<3000:
		host.game.advance_clock(GameUnit.TICK); ticks+=1
		if ticks%50==0: await frames(1)
	check(host.game.run.stage=="result","native concurrent boards settle the first round")
	replica.apply_board(host.game.board_frame(1,false))
	var all_hp_match:=true
	for unit:GameUnit in replica.world.unit_rows():
		var authoritative:GameUnit=host.game.encounter(1).world.units.get(unit.uid)
		if authoritative and absf(unit.hp-authoritative.hp)>0.02:
			all_hp_match=false
			print("HP_DIAGNOSTIC ",unit.uid," ",unit.hp," != ",authoritative.hp," gen=",replica.generation==host.game.board_key(1)," serial=",replica.serial)
	check(all_hp_match,"received combat health matches authority")
	check(replica.friendly_damage==host.game.encounter(1).friendly_damage,"damage ledger survives a delta snapshot")
	var round_uids := replica.round_army.map(func(entry):return int(entry.uid))
	check(replica.friendly_damage.keys().all(func(uid):return int(uid) in round_uids),"damage rows belong only to the friendly round roster")
	var income:=guest.gold
	host.game.run.record_board(1,0,[9,0]);check(guest.gold==income,"results cannot pay twice")
	host.game.advance_clock(5)
	check(host.game.run.wave==2 and guest.stage=="prepare","next round reopens every human company")
	# Seat zero can be eliminated while remaining humans continue.
	host.game.run.lives=0;host.game.run.placements[0]=9
	host.game.run._choose_pairings()
	host.game.start_round()
	ticks=0
	while host.game.run.stage=="fight" and ticks<3000:
		host.game.advance_clock(GameUnit.TICK);ticks+=1
		if ticks%50==0:await frames(1)
	check(host.game.run.stage=="result","host elimination does not terminate the tournament")
	host.game.advance_clock(5)
	client.close()
	check(await wait_for(func():return host.members.size()==1),"disconnect is detected")
	check(not host.game.run.humans.has(1),"disconnected human becomes a bot")
	var old_plan:=int(host.game.run.bot_plans[0].actions)
	host.game.advance_clock(2)
	check(int(host.game.run.bot_plans[0].actions)>old_plan,"replacement bot resumes purchases")
	replica.queue_free();parent.queue_free();client.queue_free();host.close();host.queue_free();await frames(6)
func _ready() -> void:
	await frames(10)
	await pair(false)
	await pair(true)
	var league:=ArenaOnlineTournament.new();league.begin(31)
	league.wave=4;league.stage="fight";league.rival_health.fill(0);league.rival_health[0]=100
	league.pairings.assign([{"a":0,"b":1,"ghost":false}])
	league._human_result={"wave":4,"winner":0,"seconds":10,"damage":[1,1],"gold":0}
	league.board_results={0:{"winner":0,"survivors":[1,0]},1:{"winner":-1,"survivors":[1,1]}}
	league._settle_round()
	check(league.lives==90 and league.rival_health[0]==90,"mirrored draw applies to both human owners")
	check(league.last_result.winner==-1 and league.rivals[0].last_result.winner==-1 and league.rivals[0].win_streak()==0,"guest results and streaks preserve shared draw outcome")
	print("ARENA_ONLINE ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
