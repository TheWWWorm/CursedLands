extends "footprint_surface_scene.gd"
## Authored running footfalls at a low drawing cadence and both game speeds.
## Movement is scripted around dry village soil; this tests the visual path,
## not controller input or navigation. The simulation and camera stop only
## while comparing otherwise identical images with/without the live decals.

func run() -> void:
	prepare_scene()
	var unit := world.spawn_unit({"nid":1,"prototype":"Human Hero","position":Vector3(64,62,0)})
	unit.set_process(false); unit.set_physics_process(false); unit.model.set_process(false)
	unit._set_action("run")
	var generated := 0
	for speed: float in [1.0,2.0]:
		for step in 216:
			var dt := speed/18.0
			var phase := (step/18.0*speed)*.60
			unit.pos=Vector2(64,62)+Vector2(sin(phase),cos(phase))*2.5
			unit.facing=phase
			unit.resync_drawn()
			unit._anim_acc+=dt; unit.anim_flush(); unit.model._process(dt)
			marks._process(dt)
			camera.position=unit.global_position+Vector3(sin(phase)*5,6,cos(phase)*5)
			camera.look_at(unit.global_position)
			await frames(1)
			if step%36==35:
				var row := await inspect_marks(unit)
				row.speed=speed; row.step=step; row.count=marks.foot_marks.size(); rows.append(row)
		generated+=marks.foot_marks.size()
		check(marks.foot_marks.size()>16,"native running animation leaves a trail at speed "+str(speed))
		view.get_texture().get_image().save_png("user://running-footprints-%dx.png"%speed)
		for mark: GroundMarks.Mark in marks.foot_marks: mark.decal.free()
		marks.foot_marks.clear()
	FileAccess.open("user://footprint-running-scene.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"generated":generated},"\t"))
	view.free(); await frames(); TexUpscale.shutdown()
	print("FOOTPRINT_RUNNING_SCENE checks=",checks," failures=",failures," generated=",generated)
	get_tree().quit(1 if failures else 0)

func inspect_marks(unit: GameUnit) -> Dictionary:
	marks.hide(); await frames()
	var clear := view.get_texture().get_image()
	marks.show(); await frames()
	var ink := view.get_texture().get_image()
	var observed := 0; var missing := []
	for mark: GroundMarks.Mark in marks.foot_marks:
		# Exclude genuinely occluded marks and the original end-of-life fade.
		if Vector2(mark.x,mark.y).distance_to(unit.pos)<1.5 or mark.life<mark.fade: continue
		var at := camera.unproject_position(mark.decal.global_position)
		if camera.is_position_behind(mark.decal.global_position) or not Rect2(32,32,1216,656).has_point(at): continue
		var changed := 0
		for y in range(int(at.y)-20,int(at.y)+20):
			for x in range(int(at.x)-20,int(at.x)+20):
				var a := clear.get_pixel(x,y); var b := ink.get_pixel(x,y)
				if a.r-b.r>.02 or a.g-b.g>.02 or a.b-b.b>.02: changed+=1
		observed+=1
		if changed<=3: missing.append({"at":str(Vector2(mark.x,mark.y)),"size":str(Vector2(mark.a,mark.b)),"life":mark.life,"pixels":changed})
	check(observed>0 and missing.is_empty(),"running trail stays above dry ground: "+str(missing))
	return {"observed":observed,"missing":missing}
