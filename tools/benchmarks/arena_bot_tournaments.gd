extends Node
## Paired seats, identical offers/prices, actual nine-board native combat.
const Legacy=preload("arena_legacy_bot.gd")
class League extends ArenaOnlineTournament:
	var flip:=0
	var all_new:=false
	var strategy_offset:=0
	var samples:=[]
	var planned_round:=-1
	func is_new(player:int)->bool:return all_new or (player+flip)%2==0
	func finish_preparation()->void:
		if planned_round==wave:return
		planned_round=wave
		for player in alive_players():
			var bot:=company(player)
			var plan:={"actions":0,"rerolls":0,"done":false}
			var spending:={"recruits":0,"training":0,"refreshes":0,"sales":0}
			while not plan.done:
				var before_gold:=bot.gold
				var before_training:=bot.training
				var before_rolls:=int(plan.rerolls)
				if is_new(player):ArenaBotPlanner.step(bot,player+1+strategy_offset,wave,health(player),plan)
				else:Legacy.legacy_step(bot,player+1,wave,health(player),plan)
				var spent:=before_gold-bot.gold
				if spent<0:spending.sales-=spent
				elif bot.training>before_training:spending.training+=spent
				elif int(plan.rerolls)>before_rolls:spending.refreshes+=spent
				else:spending.recruits+=spent
			# Equipment access stays equal when comparing economy policies.
			if not is_new(player): ArenaBotPlanner.equip(bot)
			if player>0:bot_plans[player-1].done=true
			samples.append({"round":wave,"seat":player,"new":is_new(player),"strategy":ArenaBotPlanner.strategy(bot,player+1+strategy_offset),"gold":bot.gold,"interest":bot.income_preview().interest,"capacity":bot.capacity(),"field":bot.deployed_count(),"families":bot.army.filter(func(entry):return entry.deployed).map(func(entry):return entry.family),"stars":bot.army.filter(func(entry):return entry.deployed).map(func(entry):return entry.rank),"hp":health(player),"spending":spending,"items":bot.items.duplicate(true),"alliances":ArenaAlliances.counts(bot.army)})
var results:=[]
func _ready()->void:
	var count:=4
	var first_game:=0
	var self_play := "--all-new" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--games="):count=int(arg.get_slice("=",1))
		elif arg.begins_with("--first-game="):first_game=int(arg.get_slice("=",1))
		elif arg.begins_with("--astral-path="):GameData.campaign_roots[CampaignProfile.ASTRAL]=arg.trim_prefix("--astral-path=")
	var expanded := GameData.campaign_roots.has(CampaignProfile.ASTRAL)
	if expanded and not ArenaExpansion.mount():
		printerr("FAIL Astral roster unavailable");get_tree().quit(1);return
	for index in range(first_game,first_game+count):
		var game:=ArenaOnlineGame.new();var league:=League.new()
		var encounters:=[]
		league.auto_save=false;league.flip=index%2;league.all_new=self_play;league.strategy_offset=index%4 if self_play else 0;game.run=league
		league.expansion=expanded
		add_child(game);game.begin(7319+index/2*997,{});game.set_process(false)
		for wave in 60:
			if league.stage=="won":break
			var participants:=league.alive_players()
			game.start_round()
			for tick in 2300:
				if league.stage!="fight":break
				game.advance_clock(GameUnit.TICK)
				if tick%80==0:await get_tree().process_frame
			if league.stage=="fight":push_error("Tournament did not settle");get_tree().quit(1);return
			for seat: int in participants:
				var battle:=game.encounter(seat)
				encounters.append({"round":league.wave,"seat":seat,"winner":battle.winner,"seconds":battle.world.time,"reason":battle.end_reason,"effects":battle.world.arena_effects.totals.duplicate(true) if battle.world.arena_effects else {}})
			print("BOT_ROUND ",index," ",league.wave," alive=",league.alive_players()," bank=",league.alive_players().map(func(p):return league.company(p).gold))
			if league.stage=="result":league.advance();game._prepare()
		var winner:=league.placements.find(1)
		var result:={"seed":7319+index/2*997,"flip":index%2,"all_new":self_play,"strategy_offset":league.strategy_offset,"winner":winner,"new_winner":league.is_new(winner),"placements":league.placements,"rounds":league.wave,"samples":league.samples}
		result["encounters"]=encounters
		result["expansion"]=expanded
		results.append(result)
		FileAccess.open("user://arena-bot-tournaments.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
		print("BOT_TOURNAMENT ",index," winner=",winner," new=",result.new_winner," rounds=",league.wave," placements=",league.placements)
		game.queue_free();await get_tree().process_frame
	get_tree().quit()
