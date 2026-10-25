extends Node
## Independent ordered sole reduction and production admission, on synthetic
## vertices and authored rigid/smoothed feet. No timing assertion.
var checks := 0
var failures := 0
var marks_script: Variant = GroundMarks
var kernel: RefCounted
class FlatTerrain extends EITerrain:
	var floor_height := 0.0
	var queries := 0
	func ground_at(_x: float,_y: float) -> float:
		queries+=1
		return floor_height
class CustomPart extends Node3D:
	pass
class CustomAnimatedPart extends EIAnimPart:
	pass
class CustomMesh extends MeshInstance3D:
	pass
class CustomMarks extends GroundMarks:
	pass
class Probe extends RefCounted:
	var calls := 0
	var decline := false
	func sole_geometry(_part,_vertices,_part_script) -> Variant:
		calls+=1
		return null if decline else {"p":Vector2.ZERO,"extent":Vector2(.1,.2),"angle":0.0,"height":0.0}

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<16:printerr("FAIL ",label)

func geometry(marks: GroundMarks,n: Node3D) -> Dictionary:
	var points:=PackedVector3Array()
	var bottom:=INF
	if n.has_meta("weld_mesh") and n.is_visible_in_tree():
		var mesh:ArrayMesh=n.get_meta("weld_mesh")[0]
		for vertex:Vector3 in marks._sole_vertices(mesh):
			var p:=n.global_transform*vertex
			points.append(p);bottom=minf(bottom,p.y)
	for child:Node in n.get_children():
		var mi:=child as MeshInstance3D
		if mi==null or mi.mesh==null or not mi.visible:continue
		var transform:=mi.global_transform
		for vertex:Vector3 in marks._sole_vertices(mi.mesh):
			var p:=transform*vertex
			points.append(p);bottom=minf(bottom,p.y)
	if points.is_empty():return {}
	var forward:=Vector2(n.global_basis.z.x,-n.global_basis.z.z).normalized()
	if forward.length_squared()<.1:forward=Vector2.UP
	var across:=Vector2(forward.y,-forward.x)
	var lo:=Vector2(INF,INF);var hi:=-lo
	for p:Vector3 in points:
		if p.y>bottom+.035:continue
		var xy:=Vector2(p.x,-p.z)
		var local:=Vector2(xy.dot(across),xy.dot(forward))
		lo=lo.min(local);hi=hi.max(local)
	var mid:=(lo+hi)*.5
	var p:=across*mid.x+forward*mid.y
	var extent:=((hi-lo)*.5).clamp(Vector2(.025,.045),Vector2(.32,.46))
	return {"p":p,"extent":extent,"angle":forward.angle()-PI*.5,"height":bottom}

func contact(marks: GroundMarks,n: Node3D) -> Dictionary:
	if n.has_meta(EIFigureGeometry.META):
		var box:=n.global_transform*EIFigureGeometry.box(n.get_meta(EIFigureGeometry.META))
		var centre:=box.get_center()
		if box.position.y>marks.world.terrain.ground_at(centre.x,-centre.z)+.09:return {}
	var out:=geometry(marks,n)
	if out.is_empty() or out.height>marks.world.terrain.ground_at(out.p.x,out.p.y)+.075:return {}
	return out

func compare(marks: GroundMarks,n: Node3D,label: String,supported:=true) -> void:
	var expected:=geometry(marks,n)
	var actual:Variant=kernel.sole_geometry(n,marks._sole_vertices,EIAnimPart)
	check((actual!=null)==supported,label+" native support")
	if supported:
		check(actual==expected,label+" exact geometry")
		check(actual.keys()==expected.keys(),label+" exact ordered keys")
	check(marks.call("_sole_geometry",n)==expected,label+" scalar geometry")
	check(marks._sole_contact(n)==contact(marks,n),label+" production admission")

func mesh(points: PackedVector3Array) -> ArrayMesh:
	var out:=ArrayMesh.new()
	if not points.is_empty():
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=points
		out.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS,arrays)
	return out

func finish() -> void:
	print("GROUND_CONTACT_NATIVE checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))

func _ready() -> void:
	check(ClassDB.class_exists("GroundContactKernel"),"native sole geometry is available")
	if failures:finish();return
	kernel=marks_script._sole_kernel
	check(kernel!=null,"production sole geometry uses native helper")
	if failures:finish();return
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	Engine.time_scale=0.0;Gfx.ensure_globals()
	var world:=GameWorld.new();add_child(world);world.set_process(false);world.set_physics_process(false)
	var terrain:=FlatTerrain.new();world.add_child(terrain);world.terrain=terrain;terrain.set_process(false)
	var marks:=GroundMarks.of(world);marks.set_process(false)
	var parent:=Node3D.new();world.add_child(parent)
	var part:=Node3D.new();parent.add_child(part)
	compare(marks,part,"empty part")
	var a:=MeshInstance3D.new();part.add_child(a)
	var b:=MeshInstance3D.new();part.add_child(b)
	part.add_child(Node3D.new())
	compare(marks,part,"missing meshes and non-mesh child")
	var vertices:=PackedVector3Array()
	for i in 96:vertices.append(Vector3(sin(i*.43)*.23,float(i%4)*.035,cos(i*.29)*.37))
	a.mesh=mesh(vertices);b.mesh=mesh(PackedVector3Array([Vector3.ZERO,Vector3(.3,0,.4),Vector3(-.2,.07,-.2)]))
	var welded:=mesh(PackedVector3Array([Vector3(-.1,0,-.2),Vector3(.1,.034,.2),Vector3(.4,.036,.3)]))
	for frame in 160:
		parent.position=Vector3(sin(frame*.17)*10,cos(frame*.13)*.12,cos(frame*.07)*12)
		parent.rotation=Vector3(.1*sin(frame*.2),frame*.09,.08*cos(frame*.3))
		part.scale=Vector3(.25+(frame%7)*.3,.7+(frame%3)*.4,.3+(frame%5)*.2)
		part.rotation=Vector3(.11*sin(frame*.13),frame*.03,.06*cos(frame*.11))
		a.position=Vector3(.02*sin(frame*.3),.02*cos(frame*.1),.03)
		b.position=Vector3(-.1,.04,-.06);b.rotation.y=frame*.12
		a.visible=frame%4!=0;b.visible=frame%7!=0
		parent.visible=frame%9!=0
		if frame%2:part.set_meta("weld_mesh",[welded])
		elif part.has_meta("weld_mesh"):part.remove_meta("weld_mesh")
		compare(marks,part,"live transform, visibility and weld "+str(frame))
	parent.transform=Transform3D.IDENTITY;parent.show();part.transform=Transform3D.IDENTITY;a.show();b.hide()
	if part.has_meta("weld_mesh"):part.remove_meta("weld_mesh")
	for points:PackedVector3Array in [PackedVector3Array(),PackedVector3Array([Vector3.ZERO]),PackedVector3Array([Vector3(-4,0,-4),Vector3(4,0,4)]),PackedVector3Array([Vector3.ZERO,Vector3(.2,.035,.4),Vector3(.3,.035001,.5)])]:
		a.mesh=mesh(points);compare(marks,part,"empty, clamps and sole band "+str(points.size()))
	a.mesh=mesh(vertices)
	for height in [-.2,0.0,.074999,.075,.075001,.090001,2.0]:
		part.position.y=height
		compare(marks,part,"terrain boundary "+str(height))
		part.set_meta(EIFigureGeometry.META,{"centre":Vector3.ZERO,"min":Vector3(-.2,0,-.3),"max":Vector3(.2,.5,.3)})
		compare(marks,part,"authored coarse bounds "+str(height))
		part.remove_meta(EIFigureGeometry.META)
	part.position.y=0.0
	part.basis=Basis(Vector3.RIGHT,Vector3.FORWARD,Vector3.UP)
	compare(marks,part,"zero projected forward uses fallback axis")
	part.basis=Basis.IDENTITY
	var custom:=CustomPart.new();parent.add_child(custom)
	var custom_child:=MeshInstance3D.new();custom.add_child(custom_child);custom_child.mesh=a.mesh
	compare(marks,custom,"custom part complete fallback",false);custom.free()
	var custom_animated:=CustomAnimatedPart.new();parent.add_child(custom_animated)
	var animated_child:=MeshInstance3D.new();custom_animated.add_child(animated_child);animated_child.mesh=a.mesh
	compare(marks,custom_animated,"custom animated part complete fallback",false);custom_animated.free()
	var custom_mesh:=CustomMesh.new();part.add_child(custom_mesh);custom_mesh.mesh=a.mesh
	compare(marks,part,"custom mesh complete fallback",false);custom_mesh.free()
	var probe:=Probe.new();marks_script._sole_kernel=probe
	check(marks._sole_contact(part).extent==Vector2(.1,.2) and probe.calls==1,"production uses one native batch")
	probe.decline=true
	check(marks._sole_contact(part)==contact(marks,part) and probe.calls==2,"declined batch preserves complete scalar result")
	part.position.y=2.0
	part.set_meta(EIFigureGeometry.META,{"centre":Vector3.ZERO,"min":Vector3(-.2,0,-.3),"max":Vector3(.2,.5,.3)})
	terrain.queries=0
	check(marks._sole_contact(part).is_empty() and probe.calls==2 and terrain.queries==1,"authored airborne rejection precedes native geometry")
	part.remove_meta(EIFigureGeometry.META);part.position.y=0.0
	marks_script._sole_kernel=null
	check(marks._sole_contact(part)==contact(marks,part),"older library keeps scalar geometry")
	marks_script._sole_kernel=probe
	var derived:=CustomMarks.new();derived.world=world
	check(derived._sole_contact(part)==contact(derived,part) and probe.calls==2,"derived collector preserves scalar hooks")
	derived.free();marks_script._sole_kernel=kernel
	terrain.floor_height=-.2;terrain.queries=0
	check(marks._sole_contact(part).is_empty() and terrain.queries==1,"sole terrain rejection remains one live query")
	terrain.floor_height=0.0
	for smooth in [false,true]:
		var actor:=GameUnit.new()
		check(actor.setup(world,{"prototype":"Human Hero","nid":100}),"authored figure loads")
		world.add_child(actor);world.set_unit(100,actor);actor.set_process(false);actor.set_physics_process(false)
		if smooth:actor.info.smooth_joints=true;actor.refresh_figure(true)
		actor.model.set_process(false)
		actor.model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var leg:=int(actor.race.get("leg_segment",0))
		check(leg>0,"authored terminal leg segment exists")
		for clip:String in ["walk","run","crawl","idle"]:
			var resolved:=actor.model.resolve(clip)
			check(not resolved.is_empty(),"authored "+clip+" resolves")
			if resolved.is_empty():continue
			actor.model.player.play("ei/"+resolved,0.0)
			for frame in 12:
				actor.model.player.seek(frame*.037,true)
				for name:String in ["ll%d"%leg,"rl%d"%leg]:
					var foot:=actor.model.find_child(name,true,false) as Node3D
					check(foot!=null,"authored "+name+" exists")
					if foot:compare(marks,foot,"authored "+str(smooth)+" "+clip+" "+str(frame)+" "+name)
		world.erase_unit(100);actor.free()
	var timings:=[]
	for native in [false,true,true,false]:
		marks_script._sole_kernel=kernel if native else null
		var started:=Time.get_ticks_usec()
		for i in 1500:marks._sole_contact(part)
		timings.append({"native":native,"queries":1500,"usec":Time.get_ticks_usec()-started})
	print("GROUND_CONTACT_NATIVE_TIMING ",JSON.stringify(timings))
	marks_script._sole_kernel=kernel;world.free();finish()
