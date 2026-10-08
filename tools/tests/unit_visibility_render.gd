extends Node
var session: Session
var game: Game
var rows: Array = []
var camera_rows: Array = []

func frames(n := 5) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"control_mode":1,
		"unit_fog":1,"net_upnp":0,"net_lan":0,"net_directory":0,"scroll_border":0},true)
	session=Session.new();add_child(session);session.set_physics_process(false)
	game=Game.new();game.session=session;session.game=game;add_child(game)
	session.state=CampaignState.new();session.state.ensure_hero(0,"Human Hero")
	await session.enter_zone("gz1h",1,false)
	var w:=session.world
	w.set_process(false);w.set_physics_process(false);w.vm.instances.clear()
	game.hud._tutorial.close();game.hud._dialog.visible=false
	game.rig.release();game.rig.set_process(false)
	var fog: UnitFog=game.get_node("UnitFog");fog.set_process(false)
	var hero: GameUnit=session.party_units(0)[0]
	var cam:=game.rig.camera
	for entry: Array in [[997322,Vector2(336.817535,152.929199),false],[1001005,Vector2(455.75,183.75),true],[1002008,Vector2(420.100006,94.099998),false]]:
		var target: GameUnit=w.units[entry[0]]
		var dead: bool=target.dead
		target.dead=entry[2]
		if target.dead:
			target.model.act("death",1,0.0);target.freeze_pose(true)
		var centre:=EISpace.pos(target.pos.x,target.pos.y,w._stand_z(target.pos)+0.6)
		cam.global_position=centre+Vector3(9,13,11);cam.look_at(centre);cam.force_update_transform()
		for delta: Vector2 in [Vector2.ZERO,Vector2(.2,0),Vector2(-.2,0),Vector2(0,.2),Vector2(0,-.2)]:
			hero.pos=entry[1]+delta;hero.resync_drawn();target.resync_drawn()
			for turn in 8:
				hero.facing=turn*PI/4;hero.resync_drawn()
				fog._t=0;fog._process(0)
				await frames(3)
				rows.append({"target":target.uid,"dead":target.dead,"observer":hero.pos,"turn":turn,
					"ray":w.sight_ray(hero,target),"fogged":target.fogged,"visible":target.visible,
					"on_screen":target._screen.is_on_screen(),"body_screen":target._body.is_on_screen(),
					"far":target._far,"position":target.global_position,"layers":target._geoms[0].layers,
					"noticed":UnitFog.noticed_for(session,0,true).has(target),"listed":UnitFog.listed(game,target)})
			if delta==Vector2.ZERO:
				await RenderingServer.frame_post_draw
				game.get_viewport().get_texture().get_image().save_png("user://visibility-%d-normal.png" % target.uid)
				target.fogged=false;target.visible=true
				await frames()
				await RenderingServer.frame_post_draw
				game.get_viewport().get_texture().get_image().save_png("user://visibility-%d-unfogged.png" % target.uid)
		hero.pos=entry[1];hero.resync_drawn()
		for orbit in 8:
			var around:=Vector3(15*cos(orbit*PI/4),13,15*sin(orbit*PI/4))
			cam.global_position=centre+around;cam.look_at(centre);cam.force_update_transform()
			fog._t=0;fog._process(0)
			await frames()
			camera_rows.append({"target":target.uid,"orbit":orbit,"visible":target.visible,"fogged":target.fogged,"listed":UnitFog.listed(game,target)})
		target.dead=dead
	var out:={"rows":rows,"camera_rows":camera_rows}
	FileAccess.open("user://visibility-render-probe.json",FileAccess.WRITE).store_string(JSON.stringify(out,"\t"))
	for entry: Array in [[997322,false],[1001005,true],[1002008,false]]:
		var group:=rows.filter(func(row):return row.target==entry[0])
		print("VISIBILITY_RENDER ",entry," flags=",group.map(func(row):return [row.fogged,row.visible,row.on_screen,row.far,row.layers]))
	game.queue_free();session.queue_free();await frames()
	get_tree().quit()
