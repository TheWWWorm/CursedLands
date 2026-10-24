extends "ground_mark_receivers.gd"
func run() -> void:
	prepare_scene()
	var old:=terrain;world.remove_child(old);old.free()
	terrain=EITerrain.load_map("zone7");world.add_child(terrain);world.terrain=terrain
	GameData.options.gfx_soft_ground=1
	terrain.apply_gfx()
	await frames(6)
	var point:=Vector2.ZERO
	for y in range(10,terrain.sectors_y*32-10):
		for x in range(10,terrain.sectors_x*32-10):
			if terrain.ground_type(x,y) in [3,9,12] and terrain.water_at(x,y)<terrain.height_at(x,y)-.2:
				point=Vector2(x+.5,y+.5);break
		if point!=Vector2.ZERO:break
	check(point!=Vector2.ZERO,"soft ground found")
	focus=EISpace.pos(point.x,point.y,terrain.height_at(point.x,point.y))
	camera.position=focus+Vector3(0,5,5);camera.look_at(focus)
	for i in 12:
		var p:=point+Vector2((i%2)*.3,(i/2)*.4)
		marks.add_footprint(p.x,p.y,.12,.25,.2,0,-1)
		terrain.details.soft_ground.add_step(p,Vector2(.12,.25),.2)
	await frames(60)
	marks._projection.sync([marks.foot_marks])
	check(await visible_pixels()>20,"pigment remains on live deformed ground")
	view.get_texture().get_image().save_png("user://projected-soft.png")
	GameData.options.gfx_soft_ground=0;terrain.apply_gfx();await frames(4)
	marks._projection.sync([marks.foot_marks])
	check(await visible_pixels()>20,"existing marks survive disabling soft ground")
	view.free();await frames();TexUpscale.shutdown()
	print("SOFT_PROJECTED_MARKS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
