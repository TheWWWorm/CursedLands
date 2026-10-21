extends "dialogue_feedback.gd"
const Rewards=preload("res://src/game/astral_challenge_rewards.gd")
func _ready():
	var s:=CaptureSession.new();add_child(s)
	var w:=GameWorld.new();s.world=w;w.session=s;w.authority=true
	var hero:=GameUnit.new();hero.world=w;hero.controller=0;hero.uid=1500000001
	var victim:=GameUnit.new();victim.world=w;victim.dead=true
	var original_campaign:=s.state.campaign_id
	for zone:String in Rewards.rows():
		w.zone={"id":zone}
		for name:String in Rewards.rows()[zone]:
			var row:Dictionary=Rewards.rows()[zone][name]
			victim.proto=GameData.db.find("monster_prototypes",name)
			victim.info={}
			check(not victim.proto.is_empty(),"reward matches installed original prototype: "+name)
			for id in row.ids:
				victim.uid=int(id)
				var result:=Rewards.claim(w,victim,hero)
				check(not result.is_empty(),"reviewed placement receives reward: %s/%d"%[zone,id])
				check(Rewards.claim(w,victim,hero).is_empty(),"same corpse cannot pay twice")
				if not result.is_empty():
					for item:String in result.items:
						var part:=Items.parse_stack(item)
						check(String(part[0]).begins_with("money") or not Items.info(part[0]).row.is_empty(),"bonus uses actual item: "+item)
				victim.dead=false;check(Rewards.claim(w,victim,hero).is_empty(),"no reward for living actor");victim.dead=true
			victim.uid=1900000000
			check(Rewards.claim(w,victim,hero).is_empty(),"summoned copy is outside authored placement list")
			victim.uid=int(row.ids[0]);s.state.vars.clear()
			victim.proto=victim.proto.duplicate(true);victim.proto.hp+=10
			check(Rewards.claim(w,victim,hero).is_empty(),"modified prototype is not overridden")
	# Use an actual world death, XP distribution, pockets and campaign save.
	s.world=null;w.free();hero.free();victim.free();s.queue_free();await get_tree().process_frame
	s=CaptureSession.new();add_child(s)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero")
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0},true)
	await s.enter_zone("gz11g",1,false)
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	hero=s.party_units(0)[0]
	var row:Dictionary=Rewards.rows().gz11g["zone11 cyclop"]
	victim=s.world.units.get(int(row.ids[0]))
	check(victim!=null,"actual authored cyclops is present")
	if victim:
		var h:Dictionary=hero.get_meta("hero");h.int=25.0;h.exp_debt=0.0
		var before:=float(h.exp_total)
		victim.die(hero)
		check(is_equal_approx(float(h.exp_total)-before,float(row.xp)),"actual kill grants additional XP once through normal rules")
		check(victim.get_meta("loot",[])==row.items,"actual corpse contains the added loot")
		s.state.store_zone("gz11g",s.world);s.state.save("user://challenge-save.eis")
		var loaded:=CampaignState.load_from("user://challenge-save.eis")
		check(loaded.get_var(0,"remake.challenge_reward.gz11g.%d"%victim.uid)==1,"claim persists through save/load")
		s.state=loaded
		check(Rewards.claim(s.world,victim,hero).is_empty(),"loaded campaign cannot repeat the claim")
		s.state.vars.clear();s.state.campaign_id=CampaignProfile.ORIGINAL
		check(Rewards.claim(s.world,victim,hero).is_empty(),"base campaign untouched")
		s.state.campaign_id=original_campaign;s.lmp={"quest":"test"}
		check(Rewards.claim(s.world,victim,hero).is_empty(),"original multiplayer untouched")
		s.lmp={};hero.controller=-1
		check(Rewards.claim(s.world,victim,hero).is_empty(),"NPC/script death is not a player reward")
	g.queue_free();s.queue_free();await get_tree().process_frame
	print("ASTRAL_CHALLENGE_REWARDS ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
