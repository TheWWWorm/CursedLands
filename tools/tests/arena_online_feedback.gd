extends "arena_online.gd"
func _ready() -> void:
	await frames(8)
	var host := ArenaOnlineSession.new();host.player_name="Worm";add_child(host)
	var guest := ArenaOnlineSession.new();guest.player_name="<3";add_child(guest)
	check(host.host(29826)==OK,"host starts")
	check(guest.join("127.0.0.1:29826")==OK,"guest starts")
	check(await wait_for(func():return guest.my_seat==1),"guest joins")
	guest.request("ready");await wait_for(func():return host.members.values().all(func(m):return m.ready))
	check(host.start_game(7191).is_empty(),"start tournament")
	host.game.set_process(false)
	check(await wait_for(func():return guest.started),"guest receives state")
	for view: ArenaOnlineView in [host.view,guest.view]:
		check(view.player_title(0)==("Worm" if view==host.view else "<3"),"own player name is retained")
	var updates: Array = []
	host.view.changed.connect(func():updates.append(true))
	var names := host._names()
	host.view.apply_state(host.game.state_for(0,names));updates.clear()
	for i in 10:
		host.game.run.preparation_left -= 0.5
		host.view.apply_state(host.game.state_for(0,names))
	check(updates.is_empty(),"countdown does not reset host inspector/UI")
	host.request("speed",[2]);await frames(12)
	check(host.game.battle_speed==2,"host changes shared speed")
	check(await wait_for(func():return guest.view.battle_speed==2),"guest receives shared speed")
	guest.request("speed",[1]);await frames(12)
	check(host.game.battle_speed==2,"guest cannot change shared speed")
	check(not host.game.command(0,"speed",[3]).is_empty(),"unsupported speed rejected")
	host.request("buy",[0]);await frames(12)
	var replica := ArenaOnlineMatch.new();replica.run=host.view;add_child(replica);replica._world_parent=self
	replica.apply_board(host.game.board_frame(0,true));replica.set_physics_process(false)
	var unit: GameUnit = replica.world.unit_rows()[0]
	var point: Vector2 = unit.get_meta("arena_placement").point
	check(replica.formation_motion.movers.has(unit),"new recruit runs into formation")
	for frame in 600: replica.formation_motion.advance(1.0/60.0,replica.world)
	check(unit.pos.distance_to(point)<0.05,"recruit reaches destination")
	var target := point+Vector2(0,4)
	check(host.game.command(0,"deploy",[host.game.run.army[0].uid,target]).is_empty(),"host moves owned recruit")
	var frame := host.game.board_frame(0,true)
	replica.apply_board(frame)
	check(replica.world.units[unit.uid]==unit and unit.pos.distance_to(target)>1.0,"move retains actor and starts at old position")
	for step in 12:
		replica.formation_motion.advance(1.0/60.0,replica.world)
		replica.apply_board(host.game.board_frame(0,false))
	check(unit.pos!=point and unit.pos.distance_to(target)>0.05 and unit.running,"idle snapshots do not interrupt running")
	check(host.game.encounter(0).world.time==0 and replica.world.time==0,"preparation animation never advances combat")
	for step in 600:replica.formation_motion.advance(1.0/60.0,replica.world)
	check(unit.pos.distance_to(target)<0.05,"moved creature arrives")
	host.game.start_round()
	var before := host.game.home.world.time
	host.game.advance_clock(GameUnit.TICK)
	check(is_equal_approx(host.game.home.world.time-before,GameUnit.TICK*2),"2x advances two authoritative ticks")
	host.view.apply_state(host.game.state_for(0,names))
	check(host.view.player_fighting(0),"fighting board carries sword status")
	replica.apply_board(host.game.board_frame(0,true))
	check(replica.formation_motion.movers.is_empty() and not replica.world.authority,"combat clears local motion without authority")
	var survivor: GameUnit = host.game.home.world.unit_rows()[0]
	survivor._set_action("run");survivor._moving=true;survivor._move_speed=3.0
	for actor: GameUnit in host.game.home.world.unit_rows():
		if actor.faction==2:actor.dead=true
	host.game.home._process(0)
	check(host.game.home.phase==ArenaMatch.Phase.FINISHED and survivor.action=="idle" and not survivor._moving and survivor._move_speed==0,"authority clears locomotion at round end")
	for step in 3:replica.apply_board(host.game.board_frame(0,false))
	var final_pose: GameUnit = replica.world.units[survivor.uid]
	check(final_pose.action=="idle" and not final_pose._moving and final_pose._move_speed==0,"finished snapshots preserve stationary survivor pose")
	host.view.apply_state(host.game.state_for(0,names))
	check(not host.view.player_fighting(0),"finished board clears sword status")
	host.game.run.lives=0
	check(host.game.command(0,"speed",[1]).is_empty(),"eliminated host can still control spectator speed")
	replica.queue_free();host.close();guest.close();host.queue_free();guest.queue_free();await frames(5)
	print("ARENA_ONLINE_FEEDBACK ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
