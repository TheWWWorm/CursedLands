extends "third_person_kbm.gd"
## Prepared original actors; real authority dispatch, approach/use animation,
## VM completion, theft accounting and corpse collection. No OG runtime oracle.

func settle_theft() -> void:
	for i in 320:
		hero._tick(GameUnit.TICK)
		s.world.vm._check_interactions()
		if not hero.has_meta("interact") and hero.orders.is_empty() and hero.order.is_empty():
			break
	check(not hero.has_meta("interact") and hero.orders.is_empty() and hero.order.is_empty(),
		"theft action reaches completion or cancellation")

func request(target: GameUnit, player := 0) -> void:
	s.apply_command({"t":"steal", "unit":hero.uid, "target":target.uid}, player)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,
		"control_mode":2,"confine_mouse":0,"net_upnp":0,"net_lan":0,"net_directory":0}, true)
	s = Session.new(); add_child(s)
	g = Game.new(); g.session=s; s.game=g; add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("gz1h" if GameData.campaign_id == CampaignProfile.ASTRAL else "gz1g",1,false)
	await prepare()
	mode = "pickpocket lifecycle"
	var target := body(free_point(1.3),910001,false)
	target.faction=1; hero.faction=0
	s.world.set_relation(1,0,0); s.world.set_relation(0,1,0)
	var h: Dictionary=hero.get_meta("hero")
	h.skills.science=200; h.dex=25.0; Combat.hero_stats(hero,h)
	target.proto=target.proto.duplicate(true); target.proto.steal_skills=5.0
	var material := Items.material_unit("steel")
	var quest := ""
	for item: Dictionary in GameData.db.table("quest_items"):
		quest=String(item.get("name","")).to_lower()
		if not quest.is_empty(): break
	check(not quest.is_empty() and Items.kind(quest)=="quest","campaign supplies a real quest item")
	if quest.is_empty():
		await finish_case(); return
	target.info.quest_items=[quest]
	target.set_meta("pockets",[material+"[3]","money[17]",quest])
	target.set_meta("looted",false)
	var cash := s.state.money
	var count := s.state.items.count(material)
	request(target,1)
	check(hero.orders.is_empty() and not hero.has_meta("interact"),"another player cannot order this thief")
	hero.blocked=true; request(target)
	check(hero.orders.is_empty() and not hero.has_meta("interact"),"blocked thief cannot start an approach")
	hero.blocked=false
	request(target)
	check(hero.has_meta("interact") and not hero.orders.is_empty(),"ordinary steal command starts its approach")
	await settle_theft()
	check(s.have_quest_item(0,quest),"first theft collects the carried quest item")
	check(s.state.money==cash and s.state.items.count(material)==count,"quest theft preserves other pockets")
	check(not target.get_meta("looted",false),"quest-only theft leaves ordinary pockets available")
	request(target); await settle_theft()
	check(s.state.money==cash+17 and s.state.items.count(material)==count+3,"next theft collects exactly the authored money and material stack")
	check(target.get_meta("pockets").is_empty() and target.get_meta("looted",false),"successful ordinary theft consumes pockets once")
	request(target); await settle_theft()
	check(s.state.money==cash+17 and s.state.items.count(material)==count+3,"empty repeated theft grants nothing")
	check(s.world.relation(1,0)==0,"successful theft preserves neutral relationship")

	# Invalidating an in-flight interaction must not pay its deferred callback.
	for invalidation in ["death","stop","target_death","target_removed"]:
		reset(); hero.dead=false
		var other := body(free_point(1.3),0,false)
		other.proto=other.proto.duplicate(true); other.proto.steal_skills=0.0
		other.set_meta("pockets",["money[23]"]); other.set_meta("looted",false)
		request(other)
		check(hero.has_meta("interact"),invalidation+" begins with a pending real interaction")
		match invalidation:
			"death": hero.dead=true
			"stop": s.apply_command({"t":"stop","units":[hero.uid]},0)
			"target_death": other.dead=true
			"target_removed":
				s.world.remove_unit(other)
				# remove_unit queues disposal for the frame boundary. Do not
				# simulate 17 seconds while keeping that freed actor alive.
				await frames(1)
		if invalidation=="death":
			s.world.vm._check_interactions()
			check(not hero.has_meta("interact"),"death clears the pending theft")
		else:
			await settle_theft()
		check(s.state.money==cash+17,invalidation+" cannot grant money from a stale interaction")
		hero.dead=false; reset()
		if is_instance_valid(other) and s.world.units.has(other.uid): s.world.remove_unit(other)

	# Equal skill is insufficient; failed theft alerts a neutral victim.
	reset(); h.skills.science=5; Combat.hero_stats(hero,h)
	check(Session.steal_value(hero)==Session.steal_value(target),"equal-skill fixture is exact after effective-stat calculation")
	target.set_meta("pockets",["money[29]"]); target.set_meta("looted",false)
	request(target); await settle_theft()
	check(s.state.money==cash+17 and target.get_meta("pockets")==["money[29]"],"equal skill leaves the victim's inventory intact")
	check(s.world.is_enemy(target,hero),"failed theft makes the neutral victim hostile toward the thief")
	check(s.world.relation(1,0)==0,"a victim's personal hostility does not change every member of its faction")
	h.skills.science=200
	target.set_meta("pockets",[]); target.set_meta("looted",true)
	target.dead=true; target.set_meta("loot",[material+"[3]","money[17]"])
	s.take_loot(hero,target)
	check(s.state.money==cash+17 and s.state.items.count(material)==count+3,"looting a previously emptied victim cannot pay its original pockets twice")
	check(s.save_game("theft_completed")==OK,"completed theft state saves")
	var saved := CampaignState.load_from(SaveInfo.path("theft_completed"))
	check(saved!=null and saved.money==cash+17 and saved.items.count(material)==count+3,"theft accounting survives disk round trip")
	await finish_case()

func finish_case() -> void:
	g.queue_free(); s.queue_free(); await frames(8)
	print("STEAL_LIFECYCLE ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
