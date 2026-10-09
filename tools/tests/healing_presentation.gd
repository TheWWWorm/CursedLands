extends "story_coop_traps_net.gd"
## Real healing delivery on two peers. Native light motion is preserved;
## only its unintentional visible billboard must be absent.

func loaded() -> bool:
	return client.world != null and client.zone_id == "gz1g" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game

func light_in(s: Session) -> SpellFx:
	for n in s.world.get_children():
		if n is SpellFx and not n.is_queued_for_deletion(): return n
	return null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0,"gfx_torch_glow":1,"gfx_firelight":1},true)
	host = branch(false); check(host.host(29945,2)==OK,"open healing host")
	host.state=CampaignState.new(); host.state.ensure_hero(0,"Human Hero"); host.state.world_time=0.0
	host.set_physics_process(false)
	await host.enter_zone("gz1g",1,false); freeze(host)
	client = branch(true); GameData.player_name="Healing Guest"
	check(client.join("127.0.0.1",29945)==OK,"connect healing guest")
	check(await until(loaded),"guest receives target map")
	if client.world==null: await finish(); return
	freeze(client)
	var hero: GameUnit=host.party_units(0)[0]
	var uid:=hero.uid
	for s: Session in [host,client]:
		ParticleFx.of(s.world).set_process(false)
		s.game.hud.hide(); s.game.rig.hold_view(hero.global_position+Vector3(7,5,7),hero.global_position+Vector3(0,2.5,0))
	var before:=maxf(hero.max_hp-20.0,1.0); hero.hp=before
	Spells.cast_unit(host.world,hero,"healing",hero,hero.pos)
	check(hero.hp>before,"ordinary healing spell restores health")
	check(await until(func():return light_in(client)!=null),"healing light and particles reach guest")
	var lights: Array[SpellFx]=[light_in(host),light_in(client)]
	for i in 2:
		var s: Session=[host,client][i]; var light:=lights[i]
		check(light!=null,"peer %d creates original healing illumination"%i)
		if light==null: await finish(); return
		light.set_process(false)
		check(light._light.get_child_count()==0,"peer %d healing light has no flying billboard"%i)
		check(light.light_radius==2.0 and light._life==33 and is_equal_approx(light._speed,0.2),"peer %d retains original radius, velocity and lifetime"%i)
		check(ParticleFx.of(s.world).effects.any(func(ef):return ef.e.type==0x2006 and ef.e.carrier==s.world.units[uid]),"peer %d attaches original particles to healed actor"%i)
	var low:=[INF,INF]; var high:=[-INF,-INF]
	for tick in 50:
		for i in 2:
			var s: Session=[host,client][i]; var fx:=ParticleFx.of(s.world)
			fx._tick()
			if tick<33: lights[i].advance(tick)
			for ef in fx.effects:
				if ef.e.type!=0x2006: continue
				for p in ef.e.parts:
					low[i]=minf(low[i],p[2]-s.world.units[uid].position.y)
					high[i]=maxf(high[i],p[2]-s.world.units[uid].position.y)
		if tick==20 and DisplayServer.get_name()!="headless":
			for s: Session in [host,client]: ParticleFx.of(s.world)._draw(0.0)
			await frames(8)
			var file:="user://healing-age20.png"
			check(get_viewport().get_texture().get_image().save_png(file)==OK,"capture healing without altering its native timing")
			print("HEALING_IMAGE ",ProjectSettings.globalize_path(file))
	for i in 2:
		var s: Session=[host,client][i]; var u: GameUnit=s.world.units[uid]
		print("HEALING_RANGE peer=",i," particles=",[low[i],high[i]]," light=",lights[i].position.y-u.position.y)
		check(low[i]<0.5 and high[i]>1.0 and high[i]<3.0,"peer %d particles rise around body within original carrier bounds"%i)
		check(is_equal_approx(lights[i].position.y-u.position.y,6.7),"peer %d native light still moves upward to fade ground illumination"%i)
		check(not ParticleFx.of(s.world).effects.any(func(ef):return ef.e.type==0x2006 and ef.e.live()>0),"peer %d healing particles expire normally"%i)
		lights[i].advance(33)
		check(lights[i].is_queued_for_deletion(),"peer %d light expires at original cleanup tick"%i)
	# A replayed late effect has the same age/position and never gains a halo.
	var aged:=SpellFx.spawn_event(host.world,{"spell":"healing","a":uid,"tu":uid,"x":hero.pos.x,"y":hero.pos.y,"age":20})
	check(aged!=null and aged._age==20 and aged._light.get_child_count()==0,"aged healing replay retains native age without billboard")
	if aged: aged.queue_free()
	print("HEALING_PRESENTATION ",checks," checks ",failures," failures")
	await finish()
