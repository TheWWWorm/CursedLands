extends "arena_combat_effects.gd"
## Suicide burst must matter at every star without removing range, fire armor,
## target cap, friendly protection or the once-only fuse/death contract.
func _ready()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="):GameData.campaign_roots[CampaignProfile.ASTRAL]=arg.trim_prefix("--astral-path=")
	check(ArenaExpansion.mount(),"Astral creatures mounted")
	if not ArenaExpansion.mounted():get_tree().quit(1);return
	var native:=hash(GameData.db.tables)
	for rank_value in 3:
		setup([32,0],[9,9,9,9],[],[],rank_value)
		var rabbit:=own[0];var ally_hp:=own[1].hp
		for i in enemies.size():enemies[i].pos=rabbit.pos+Vector2(1.0,i*0.3)
		var fx:=battle.world.arena_effects
		fx.tick();battle.world.time+=0.59;fx.tick()
		check(not rabbit.dead,"visible fuse remains cancellable by lethal damage until expiry")
		battle.world.time+=0.02;fx.tick()
		check(rabbit.dead and fx.totals.get("popper_blast",0)==1,"exactly one blast per rabbit")
		var lost:=enemies.map(func(u):return u.max_hp-u.hp)
		check(lost[0]>=enemies[0].max_hp*0.6,"blast removes meaningful same-star tank health at star "+str(rank_value+1))
		check(lost[0]<enemies[0].max_hp,"same-star armored frontline can survive the burst")
		print("POPPER_HITS rank=",rank_value," lost=",lost," count=",enemies.size())
		check(lost.filter(func(n):return n>0.0001).size()==3,"only three closest enemies are hit")
		check(own[1].hp==ally_hp,"nearby ally remains unharmed")
		fx.on_death(rabbit,null);fx.tick()
		check(lost==enemies.map(func(u):return u.max_hp-u.hp),"death and later ticks cannot repeat the blast")
		setup([32],[9],[],[],rank_value)
		enemies[0].pos=own[0].pos+Vector2(8,0)
		var hp:=enemies[0].hp;own[0].die(enemies[0])
		check(enemies[0].hp==hp,"ranged kill outside the blast remains a counter")
	var hook:String=ArenaRules.FAMILIES[32].hook
	for language in ["en","ru","de"]:
		RemakeText.lang=language
		check((language=="en" or RemakeText.t(hook)!=hook) and RemakeText.t(hook).contains("60/125/300"),"localized blast values "+language)
	check(hash(GameData.db.tables)==native,"blast tuning leaves original campaign records intact")
	print("ARENA_POPPER_BALANCE ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
