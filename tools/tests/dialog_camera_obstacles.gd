extends Node
## Real camera presets with controlled scenery, including an open doorway
## whose merged bounding box would incorrectly reject the original shot.
var checks:=0
var failures:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func box(parent: Node3D, p: Vector3, size: Vector3) -> MeshInstance3D:
	var m:=MeshInstance3D.new();m.mesh=BoxMesh.new();(m.mesh as BoxMesh).size=size
	parent.add_child(m);m.position=EISpace.vec(p)
	return m
func blocked(root: Node3D, view: Array) -> bool:
	var a:=EISpace.vec(view[0]);var b:=EISpace.vec(view[1])
	for m: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		var faces: PackedVector3Array=m.global_transform*m.mesh.get_faces()
		for i in range(0,faces.size()-2,3):
			if Geometry3D.segment_intersects_triangle(a,b,faces[i],faces[i+1],faces[i+2])!=null:return true
	return false
func _ready() -> void:
	var w:=GameWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false)
	var a:=GameUnit.new();a.uid=1;a.pos=Vector2.ZERO;a.proto={"dialog_cam_height":1.3};w.add_child(a)
	var b:=GameUnit.new();b.uid=2;b.pos=Vector2(2,0);w.add_child(b)
	w.units={1:a,2:b}
	var cast:={"a":1,"b":2}
	var phrase:={"camera":2}
	var original:=DialogCamera.shot(w,cast,phrase,false)
	var expected:=DialogCamera._place(w,a,b,null,"a",-0.5236,4.0,1.5,false)
	check(original.slice(0,2)==expected,"clear authored camera is unchanged")
	var scenery:=Node3D.new();w.add_child(scenery);w.objects[1]=scenery
	var centre: Vector3=(original[0]+original[1])*0.5
	var wall:=box(scenery,centre,Vector3(1.2,4.0,0.5))
	check(blocked(scenery,original),"fixture scenery obscures the authored camera")
	var adjusted:=DialogCamera.shot(w,cast,phrase,false)
	check(adjusted[0]!=original[0] and adjusted[1]==original[1],"obstructed shot changes eye while preserving its target")
	check(not blocked(scenery,adjusted),"replacement shot clears actual scenery triangles")
	check(adjusted[2]==original[2],"camera adjustment preserves actor hide rules")
	if DisplayServer.get_name()!="headless":
		var actor:=EIUnitModel.create({"prototype":"Human Hero"});a.add_child(actor)
		var camera:=Camera3D.new();w.add_child(camera);camera.current=true
		var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-25,0);w.add_child(light)
		var environment:=WorldEnvironment.new();environment.environment=Environment.new()
		environment.environment.background_mode=Environment.BG_COLOR
		environment.environment.background_color=Color(0.14,0.16,0.18)
		environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color=Color.WHITE
		environment.environment.ambient_light_energy=0.8;w.add_child(environment)
		for view: Array in [original,adjusted]:
			camera.position=EISpace.vec(view[0]);camera.look_at(EISpace.vec(view[1]),Vector3.UP)
			for i in 8:await get_tree().process_frame
			var file:="user://dialog-camera-%s.png"%("original" if view==original else "clear")
			check(get_viewport().get_texture().get_image().save_png(file)==OK,"rendered camera view captured")
			print("DIALOG_CAMERA_IMAGE ",ProjectSettings.globalize_path(file))
	wall.position.x+=20.0
	check(DialogCamera.shot(w,cast,phrase,false)==original,"moving the obstacle restores the authored shot without stale geometry")
	wall.queue_free();await get_tree().process_frame
	box(scenery,centre+Vector3(0,2,0),Vector3(0.4,4.0,0.4))
	box(scenery,centre-Vector3(0,2,0),Vector3(0.4,4.0,0.4))
	check(DialogCamera.shot(w,cast,phrase,false)==original,"open gap is not blocked by a merged object box")
	w.queue_free()
	for i in 8:await get_tree().process_frame
	print("DIALOG_CAMERA_OBSTACLES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
