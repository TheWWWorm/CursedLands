extends Node
## Exact ordered rectangles/union for the production actor query. The retained
## scalar path is the oracle; live mesh/pose edits must be visible in one frame.
const Bounds = preload("res://src/ui/mesh_screen_rect.gd")
var bounds_script: Variant = Bounds
var checks := 0
var failures := 0
var camera: Camera3D
var kernel: RefCounted
var fallback_calls := 0

class GroundWorld extends GameWorld:
	func ground_at(_x: float, _y: float) -> float:return 0.0

class DispatchProbe extends RefCounted:
	var calls := 0
	func figure_rects(_parts, _camera, _view, _fallback) -> Array:
		calls+=1
		return [Rect2i(19,23,31,37)]

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<16:printerr("FAIL ",label)

func query(unit: GameUnit, native: bool) -> Array:
	bounds_script._native_figures=native
	return unit.screen_rects(camera)

func compare(unit: GameUnit,label: String) -> void:
	var expected:=query(unit,false)
	check(query(unit,true)==expected,label)
	check(query(unit,true)==expected,label+" repeated same-frame query")

func fallback(part: MeshInstance3D,cam: Camera3D,view: Dictionary) -> Rect2i:
	fallback_calls+=1
	return Bounds.of_context(part,cam,view)

func mesh_for(index: int) -> ArrayMesh:
	var mesh:=ArrayMesh.new()
	var a:=[];a.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array([Vector3(-.7,-.4,0),Vector3(.6,-.4,0),Vector3(.1,.8,.2),Vector3(-.3,.5,-.2)])
	a[Mesh.ARRAY_VERTEX]=vertices
	if index%2:a[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,1,2,3])
	var channels:=[];var shapes:=[]
	mesh.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_NORMALIZED if index%2 else Mesh.BLEND_SHAPE_MODE_RELATIVE
	for k in index%3:
		mesh.add_blend_shape("pose"+str(k));var shape:=vertices.duplicate()
		for i in shape.size():shape[i]+=Vector3(.17*(k+1),.3,-.11)
		var row:=[];row.resize(Mesh.ARRAY_MAX);row[Mesh.ARRAY_VERTEX]=shape
		channels.append(row);shapes.append(shape)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP if index%2==0 else Mesh.PRIMITIVE_TRIANGLES,a,channels)
	mesh.set_meta(EIFigure.GEOMETRY_META,[vertices,a[Mesh.ARRAY_INDEX]])
	if not shapes.is_empty():mesh.set_meta(EIFigure.SHAPES_META,shapes)
	return mesh

func finish() -> void:
	print("PICKING_FIGURES checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))

func _ready() -> void:
	kernel=Bounds._kernel
	check(kernel!=null and kernel.has_method("figure_rects"),"native figure batch available")
	if failures:finish();return
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.near=.1;camera.far=80
	var unit:=GameUnit.new();add_child(unit);unit.set_process(false);unit.set_physics_process(false)
	unit.model=EIUnitModel.new();unit.add_child(unit.model);unit.model.set_process(false)
	var probe:=DispatchProbe.new();Bounds._kernel=probe
	check(query(unit,true)==[Rect2i(19,23,31,37)] and probe.calls==1,"production actor dispatches one batch")
	Bounds._kernel=kernel
	check(query(unit,true).is_empty(),"empty figure has no union")
	var parts:Array[MeshInstance3D]=[]
	for i in 18:
		var part:=MeshInstance3D.new();part.mesh=mesh_for(i);unit.model.add_child(part)
		part.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		parts.append(part);unit._geoms.append(part)
	# Non-mesh geometry and deleted rows remain harmless members of the list.
	var nonmesh:=MultiMeshInstance3D.new();unit.model.add_child(nonmesh);unit._geoms.append(nonmesh)
	var expired:=MeshInstance3D.new();unit.model.add_child(expired);unit._geoms.append(expired);expired.free()
	var rng:=RandomNumberGenerator.new();rng.seed=293768
	for trial in 180:
		camera.projection=trial%3;camera.size=12;camera.fov=65
		camera.frustum_offset=Vector2(.3,-.2);camera.h_offset=.13;camera.v_offset=-.2
		camera.transform=Transform3D(Basis.from_euler(Vector3(.17,-.24,.08)),Vector3(10000,-20000,30000) if trial%7==0 else Vector3(3,2,1))
		for i in parts.size():
			var part:=parts[i]
			part.visible=(trial+i)%9!=0
			var offset:=Vector3(rng.randf_range(-12,12),rng.randf_range(-5,5),[-.1,-5.,-80.,2.][(trial+i)%4])
			part.global_transform=camera.transform*Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())).scaled(Vector3(.7,1.4,1.1)),offset)
			for k in part.mesh.get_blend_shape_count():part.set_blend_shape_value(k,[0.,.000001,-.3,.8,2.][(trial+i+k)%5])
		compare(unit,"all parts and union "+str(trial))
		parts[0].position+=Vector3(.3,-.2,.1);compare(unit,"same-frame placement "+str(trial))
		unit.model.hide();check(query(unit,true).is_empty(),"hidden parent "+str(trial));unit.model.show()
	var part:=parts[1];part.show();part.global_transform=camera.transform*Transform3D(Basis.IDENTITY,Vector3(0,0,-8))
	var retained:=part.mesh
	var generic:=ArrayMesh.new();generic.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,BoxMesh.new().get_mesh_arrays());part.mesh=generic
	compare(unit,"generic mesh fallback")
	var view:=Bounds.camera_context(camera);fallback_calls=0
	kernel.figure_rects(unit._geoms,camera,view,fallback)
	check(fallback_calls==1,"only unsupported part reaches script fallback")
	part.mesh=retained;part.skin=Skin.new();compare(unit,"skin without skeleton fallback");part.skin=null
	var multi:=ArrayMesh.new();var arrays:=BoxMesh.new().get_mesh_arrays()
	for i in 2:multi.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	multi.set_meta(EIFigure.GEOMETRY_META,[arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_INDEX]])
	part.mesh=multi;compare(unit,"multiple surfaces fallback")
	part.mesh=retained;var old_shape=retained.get_meta(EIFigure.SHAPES_META)
	retained.remove_meta(EIFigure.SHAPES_META);compare(unit,"missing morph metadata fallback");retained.set_meta(EIFigure.SHAPES_META,old_shape)
	part.mesh=null;compare(unit,"missing mesh")
	part.mesh=retained
	var expected:=query(unit,false);Bounds._kernel=null
	check(query(unit,true)==expected,"missing native library uses scalar implementation");Bounds._kernel=kernel
	bounds_script._native_figures=false;check(unit.screen_rects(camera)==expected,"older library keeps general path")
	bounds_script._native_figures=true
	check(unit.screen_rects(null).is_empty(),"null camera remains empty")
	var detached:=Camera3D.new();check(unit.screen_rects(detached).is_empty(),"detached camera remains empty");detached.free()
	check(kernel.figure_rects(unit._geoms,null,view,fallback).is_empty(),"native null camera")
	check(kernel.figure_rects(unit._geoms,camera,{},fallback).is_empty(),"native empty view")
	var model:=unit.model;unit.model=null;check(unit.screen_rects(camera).is_empty(),"missing model remains empty");unit.model=model
	# Real authored humans and winged creatures exercise many current morphs.
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	var world:=GroundWorld.new();world.authority=false;world.process_mode=Node.PROCESS_MODE_DISABLED;add_child(world)
	var actors:Array[GameUnit]=[]
	var astral:=GameData.campaign_id=="lost_in_astral"
	for record:Dictionary in [{"prototype":"zone1 Human Fighter3 M" if astral else "Human Hero","nid":1,"player":3},{"prototype":"zone1 JunEvil" if astral else "AncientCurseM25","template":"unmocu","nid":2,"player":6}]:
		var actor:=GameUnit.new();var loaded:=actor.setup(world,record)
		check(loaded,"authored actor loads "+str(record.prototype))
		if not loaded:actor.free();finish();return
		world.add_child(actor);world.set_unit(actor.uid,actor);actors.append(actor)
		actor.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	for pose in ["idle","walk","attack","death"]:
		for frame in 30:
			camera.transform=Transform3D.IDENTITY;camera.position=Vector3(sin(frame*.1)*12,8,cos(frame*.1)*12);camera.look_at(Vector3(0,1,0))
			camera.projection=frame%3
			for actor in actors:
				actor.model.act(pose,1,0.0);actor.model.player.advance(frame*.013);actor.model.flush_pending_pose()
				compare(actor,"authored "+pose+" "+str(frame))
	var timings:=[]
	for moving in [false,true]:
		for native in [false,true,true,false]:
			var start:=Time.get_ticks_usec()
			for frame in 180:
				if moving:camera.position.x=sin(frame*.01)*3
				for actor in actors:query(actor,native)
			timings.append({"native":native,"moving_camera":moving,"usec":Time.get_ticks_usec()-start,"queries":360})
	print("PICKING_FIGURES_TIMING ",JSON.stringify(timings))
	bounds_script._native_figures=true
	unit.free();world.free();camera.free();finish()
