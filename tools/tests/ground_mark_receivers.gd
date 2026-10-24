extends "footprint_surface_scene.gd"
## Campaign mark geometry, receivers and lifecycle on Compatibility. Uses
## authored pigment/terrain, then a raised sloping bridge as an isolated control.
func changed(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0,a.get_height(),2):
		for x in range(0,a.get_width(),2):
			var ca:=a.get_pixel(x,y); var cb:=b.get_pixel(x,y)
			if absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)>.04: count+=1
	return count

func visible_pixels() -> int:
	marks.hide(); await frames(4); var base:=view.get_texture().get_image()
	marks.show(); await frames(4); return changed(base,view.get_texture().get_image())

func clear_marks() -> void:
	for list in [marks.foot_marks,marks.blood_marks,marks.fire_marks]:
		for mark: GroundMarks.Mark in list: mark.decal.free()
		list.clear()

func run() -> void:
	prepare_scene()
	GameData.options.marks=1
	# Pick actual sloping dry terrain instead of the old flat village sample.
	var slope := -1.0
	var point:=Vector2(64,62)
	for y in range(24,104):
		for x in range(24,104):
			if marks._row("foot",terrain.mark_ground(x+.5,y+.5)).is_empty(): continue
			var h:=terrain.height_at(x+.5,y+.5)
			if terrain.water_at(x+.5,y+.5)>h-.1:continue
			var grade:=absf(terrain.height_at(x+1,y+.5)-terrain.height_at(x,y+.5))+absf(terrain.height_at(x+.5,y+1)-terrain.height_at(x+.5,y))
			if grade>slope and grade<1.5: slope=grade;point=Vector2(x+.5,y+.5)
	focus=EISpace.pos(point.x,point.y,terrain.height_at(point.x,point.y))
	marks.add_footprint(point.x,point.y,.23,.5,.63,0,-1)
	for angle: float in [0.0,2.0,4.0]:
		camera.position=focus+Vector3(sin(angle)*5,5,cos(angle)*5);camera.look_at(focus)
		check(await visible_pixels()>10,"footprint visible on actual slope from angle "+str(angle))
	view.get_texture().get_image().save_png("user://projected-slope.png")
	clear_marks()
	# A raised receiving mesh must receive ink without painting a floating
	# rectangle across its edge. The ground query names this walking floor.
	focus=Vector3(64,terrain.height_at(64,62)+1.5,-62)
	var bridge:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(3,3)
	bridge.mesh=plane;bridge.layers|=EITerrain.DECAL_LAYER
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.65,.6,.5);bridge.material_override=material
	world.add_child(bridge);bridge.position=focus;bridge.rotation.z=.2
	for y in range(60,64):
		for x in range(62,66):terrain.surface[y*(terrain.grid_w-1)+x]=focus.y
	# Recreate after registering the receiver, as at the end of map load.
	marks._projection=null
	marks.add_footprint(64,62,.3,.6,.3,0,-1)
	camera.position=focus+Vector3(0,5,5);camera.look_at(focus)
	check(await visible_pixels()>30,"raised sloping floor receives the footprint")
	var mark:=marks.foot_marks[0]
	if mark.projection:
		var vertices:PackedVector3Array=mark.projection.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check(not vertices.is_empty() and Array(vertices).all(func(v):return v.y>focus.y-.5),"projection stays on the bridge, above the terrain")
		var inverse:=bridge.transform.affine_inverse()
		check(Array(vertices).all(func(v):return absf((inverse*v).y)<.0001),"projection follows the rendered bridge plane")
	view.get_texture().get_image().save_png("user://projected-bridge.png")
	GameData.options.footprints=0;marks._apply_options();await frames()
	marks.hide();await frames();var hidden:=view.get_texture().get_image()
	marks.show();await frames();check(changed(hidden,view.get_texture().get_image())==0,"option hides projected children")
	GameData.options.footprints=1;marks._apply_options()
	mark.life=mark.fade/2;marks._update(mark)
	if mark.projection:check(is_equal_approx(mark.projection.material_override.get_shader_parameter("opacity"),mark.decal.modulate.a),"projected opacity follows authored fade")
	mark.life=1;marks._tick();await frames()
	check(marks.foot_marks.is_empty(),"expired projected mark is removed")
	for code in [2,65538]:
		marks.add_blood(64,62,.1,.45,code,false)
		for i in 45:marks._tick()
		check(await visible_pixels()>30,"growing blood pigment is visible "+str(code))
		view.get_texture().get_image().save_png("user://projected-blood-%d.png"%code)
		clear_marks()
	marks.add_scorch(64,62,.6,.6,0,0.8)
	check(await visible_pixels()>30,"scorch pigment is visible")
	clear_marks();bridge.free()
	var id:=marks.get_instance_id();view.free();await frames()
	check(not is_instance_id_valid(id),"leaving the world releases mark nodes")
	TexUpscale.shutdown()
	print("GROUND_MARK_RECEIVERS checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
