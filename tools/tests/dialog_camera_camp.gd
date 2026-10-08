extends Node
## Exercise the shot search against real camp buildings. Prepared actor
## pairs cover geometry/query cost; this is not a dialogue playthrough.
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	var s:=Session.new();add_child(s)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.set_physics_process(false)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	await s.enter_zone("bz1g",1,false)
	s.world.set_physics_process(false);s.world.vm.instances.clear()
	var hero: GameUnit=s.party_units(0)[0]
	var samples:=[]
	var changed:=0
	var image_saved:=false
	for actor: GameUnit in s.world.units.values():
		if actor.has_meta("hero") or actor.dead or actor.hidden:continue
		var p:=actor.pos+Vector2.from_angle(actor.facing)*2.0
		if not s.world.nav.is_walkable(p,hero.move_class()):continue
		var cast:={"a":actor.uid,"b":hero.uid,"at":{"a":[actor.pos.x,actor.pos.y],"b":[p.x,p.y]}}
		for n in [2,6,10]:
			var preset: Array=DialogCamera.PRESETS[n]
			var original:=DialogCamera._place(s.world,actor,hero,null,preset[0],preset[1],preset[2],preset[3],false,cast.at)
			var start:=Time.get_ticks_usec()
			var shot:=DialogCamera.shot(s.world,cast,{"camera":n},false)
			samples.append(Time.get_ticks_usec()-start)
			if shot[0]==original[0]:continue
			changed+=1
			if not image_saved and DisplayServer.get_name()!="headless":
				g.hud.hide();g.rig.hold_view(EISpace.vec(shot[0]),EISpace.vec(shot[1]))
				for i in 8:await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("user://dialog-camera-camp.png")
				print("CAMP_CAMERA_IMAGE actor=",actor.info.get("name")," preset=",n," original=",original," adjusted=",shot)
				image_saved=true
	samples.sort()
	print("CAMP_CAMERA ",JSON.stringify({"shots":samples.size(),"adjusted":changed,"median_us":samples[samples.size()/2] if samples else 0,"max_us":samples.max()}))
	g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	get_tree().quit(0 if samples.size()>5 else 1)
