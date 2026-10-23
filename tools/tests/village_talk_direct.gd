extends "third_person_kbm.gd"
## Village talk in third and first person with injected keys (bz2g, Airy):
## E opens her topic list at once, picking a topic starts the walk, Space
## skips it; steering keys during the walk do not strand the conversation.
const TOPIC := "b.daughter.z0_1"

func ticks(n: int) -> void:
	for i in n: s.world._tick(GameUnit.TICK)

func airy() -> GameUnit:
	for u: GameUnit in s.world.unit_rows():
		if String(u.info.get("name", "")).to_lower() == "daughter": return u
	return null

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":3,"pad_enabled":0,"confine_mouse":0},true)
	TutorialPanel.auto_show = false
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	s.state.set_var(0,"b.bz2g.z0",2.0)
	mode="bz2g";await s.enter_zone("bz2g",1,false);await prepare()
	hero.set_process(false);hero.set_physics_process(false)
	var a := airy()
	check(a != null,"Airy is in the village")
	if a == null:
		get_tree().quit(1);return
	var d := g.hud._dialog
	var arrival := hero.pos   # the village entry spot (about 11 m from Airy)
	for view: int in [2,3]:
		for skip: bool in [true,false]:
			mode = "%s person, %s" % ["third" if view==2 else "first", "Space" if skip else "steering keys"]
			GameData.options.control_mode=view
			s.state.set_var(0,TOPIC,1.0)
			hero.pos=arrival;hero._sync_transform(0);hero.reset_physics_interpolation();s.world.nav.rebucket(hero)
			a.order={};a.orders.clear();a._anim_lock=0;a._talk_command=0;a._talk_posted=9
			reset();g.direct.apply_camera();await aim(a)
			var start := hero.pos
			await key(KEY_E)
			ticks(1)
			check(d.visible and d._mode==DialogPanel.TOPICS,"E opens the topic list at once")
			check(hero.pos.distance_to(start)<0.01 and hero.order.get("type","")!="follow","the hero stays put while the list is open")
			d._on_topic(0)
			ticks(2)
			check(d._mode==DialogPanel.STAGING and s.world.dialog_movers.has(hero),"picking the topic starts the walk")
			if skip:
				await key(KEY_SPACE)
				ticks(2)
				check(d._mode==DialogPanel.PLAYING or d._mode==DialogPanel.LAST,"Space starts the conversation at once")
				check(hero.pos.distance_to(a.pos)<4.0,"the hero stands by Airy (%.1f m from %.1f m)"%[hero.pos.distance_to(a.pos),start.distance_to(a.pos)])
			else:
				await key(KEY_W)
				await key(KEY_A)
				var n := 0
				while d._mode==DialogPanel.STAGING and n<400:
					ticks(1);await frames(1);n+=1
				check(d._mode==DialogPanel.PLAYING or d._mode==DialogPanel.LAST,"steering keys during the walk still reach the conversation (%.1f s)"%(n*GameUnit.TICK))
			d._finish()
			ticks(4);await frames(2)
			check(s.state.get_var(0,TOPIC)==2.0 and not d.visible,"the conversation completes")
	print("VILLAGE_TALK_DIRECT ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
