extends Node
## Exact ordered contacts on authored terrain and poses, compared with the
## previous collector. The field history and texture writer stay unchanged.
const Pressure = preload("res://src/game/fx/vegetation_interaction.gd")
var pressure_script: Variant = Pressure
var checks := 0
var failures := 0
var kernel: RefCounted
class CustomUnit extends GameUnit:
	var queries := 0
	func near_screen() -> bool:
		queries+=1
		return true
class CustomModel extends EIUnitModel:
	pass
class CustomMesh extends MeshInstance3D:
	pass
class CustomDetails extends TerrainDetails:
	var queries := 0
	func vegetation_allowed(p: Vector2) -> bool:
		queries+=1
		return super.vegetation_allowed(p)
class CustomPressure extends Pressure:
	pass
class Probe extends RefCounted:
	var calls := 0
	var decline := false
	func contacts(_units,_details,_focus,_unit_script,_model_script,_details_script,_width,_limit,_crawl) -> Variant:
		calls+=1
		var rows:Array[Dictionary]=[{"probe":true}]
		return null if decline else rows

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<16:printerr("FAIL ",label)

func oracle(field: Pressure,details: TerrainDetails,world: GameWorld) -> Array[Dictionary]:
	var nearby:=[]
	for u:GameUnit in world.visible_units():
		if not Pressure.shown(u) or not u.near_screen():continue
		var root:=u.get_global_transform_interpolated().origin
		var p:=Vector2(root.x,root.z)
		if (p-field.focus).abs().x>Pressure.WIDTH*.5-3.0 or (p-field.focus).abs().y>Pressure.WIDTH*.5-3.0:continue
		nearby.append({"unit":u,"root":root,"distance":p.distance_squared_to(field.focus),"id":u.get_instance_id()})
	nearby.sort_custom(func(a:Dictionary,b:Dictionary):return a.distance<b.distance if a.distance!=b.distance else a.id<b.id)
	var out:Array[Dictionary]=[]
	for i in mini(Pressure.MAX_UNITS,nearby.size()):
		var row:Dictionary=nearby[i];var u:GameUnit=row.unit
		var p:=Vector2(row.root.x,-row.root.z)
		if not details.vegetation_allowed(p):continue
		var height:float=details.surface_sample(p).height
		var box:=Pressure.posed_bounds(u)
		if not box.position.is_finite() or box.position.y>height+.22 or box.end.y<height:continue
		var radius:=clampf(u.figure_radius*.7,.18,.8)
		var length:=radius
		var centre:=Vector2(row.root.x,row.root.z)
		if u.stance==GameUnit.STANCE_CRAWL:
			length=clampf(maxf(box.size.x,box.size.z)*.45,radius,1.2)
			centre=Vector2(box.get_center().x,box.get_center().z)
		out.append({"id":row.id,"p":centre,"extent":Vector2(length,radius),"angle":-u.facing})
	return out

func compare(field: Pressure,details: TerrainDetails,world: GameWorld,label: String) -> void:
	var expected:=oracle(field,details,world)
	var actual:=field.contacts(details,world)
	check(actual==expected,label+" exact ordered contact values")
	for i in mini(actual.size(),expected.size()):
		check(actual[i].keys()==expected[i].keys(),label+" ordered field keys "+str(i))

func native(field: Pressure,details: TerrainDetails,units: Array) -> Variant:
	return kernel.contacts(units,details,field.focus,GameUnit,EIUnitModel,TerrainDetails,Pressure.WIDTH,Pressure.MAX_UNITS,GameUnit.STANCE_CRAWL)

func location(details: TerrainDetails) -> Vector2:
	var size:=details.terrain.size_ei()
	for y in range(16,int(size.y)-16,4):
		for x in range(16,int(size.x)-16,4):
			var p:=Vector2(x+.5,y+.5)
			if details.grass_allowed(p):return p
	return Vector2.INF

func actor(world: GameWorld,point: Vector3,id: int,custom:=false) -> GameUnit:
	var u:GameUnit=CustomUnit.new() if custom else GameUnit.new()
	check(u.setup(world,{"prototype":"Human Hero","nid":id}),"authored actor loads "+str(id))
	world.add_child(u);world.set_unit(id,u)
	u.set_process(false);u.set_physics_process(false);u.model.set_process(false)
	u.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	u.model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	u.model.player.play("ei/cidle01",0.0);u.model.player.seek(.3,true)
	u.position=point
	return u

func finish() -> void:
	print("VEGETATION_CONTACTS_NATIVE checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))

func _ready() -> void:
	check(ClassDB.class_exists("VegetationContactKernel"),"native contact collector is available")
	if failures:finish();return
	kernel=pressure_script._kernel
	check(kernel!=null,"production contact collector uses the native helper")
	if failures:finish();return
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.gfx_grass=1;GameData.options.gfx_vegetation_interaction=0
	Engine.time_scale=0.0;Gfx.ensure_globals()
	var world:=GameWorld.new();add_child(world);world.set_process(false);world.set_physics_process(false)
	var map:=EIMapScene.new();world.add_child(map);world.map=map
	var terrain:=EITerrain.load_map("zone1");map.add_child(terrain);map.terrain=terrain;world.terrain=terrain;terrain.set_process(false)
	var details:=terrain.details;details.set_process(false)
	var p:=location(details)
	check(p.is_finite(),"authored grass admits a contact fixture")
	if not p.is_finite():world.free();finish();return
	var origin:=Vector3(p.x,terrain.height_at(p.x,p.y),-p.y)
	var field:=Pressure.new();field.focus=Vector2(origin.x,origin.z)
	var actors:Array[GameUnit]=[]
	for i in 48:actors.append(actor(world,origin,i+1))
	var result:Variant=native(field,details,world.visible_units())
	check(result!=null,"authored ordinary meshes are supported by the native batch")
	check(field.contacts(details,world).size()==32,"nearest contact budget remains 32")
	compare(field,details,world,"equal-distance instance-ID ties")
	var probe:=Probe.new();pressure_script._kernel=probe
	check(field.contacts(details,world)==[{"probe":true}] and probe.calls==1,"production performs one contact batch")
	probe.decline=true
	compare(field,details,world,"declined query retains complete script fallback")
	pressure_script._kernel=null
	compare(field,details,world,"older or missing library retains complete script fallback")
	pressure_script._kernel=probe
	var derived_field:=CustomPressure.new();derived_field.focus=field.focus
	compare(derived_field,details,world,"derived pressure owner retains script collection")
	check(probe.calls==2,"derived pressure owner bypasses the native helper")
	pressure_script._kernel=kernel
	# The limit is applied before terrain/height admission. Rejected nearby
	# contacts must not be replaced with more distant actors beyond that limit.
	for i in 32:actors[i].position.y+=5.0
	check(field.contacts(details,world).is_empty(),"airborne nearest actors still consume the candidate budget")
	compare(field,details,world,"candidate budget before terrain admission")
	for u in actors:u.position=origin
	for frame in 80:
		field.focus=Vector2(origin.x+sin(frame*.11)*5.0,origin.z+cos(frame*.13)*5.0)
		for i in actors.size():
			var u:=actors[i]
			u.position=origin+Vector3((i%8-3.5)*.61,sin((frame+i)*.17)*.4,(i/8-2.5)*.57)
			u.rotation=Vector3(sin(i*.8)*.1,float(frame+i)*.17,cos(frame*.13)*.08)
			u.scale=Vector3(.5+(i%5)*.23,.7+(i%3)*.3,.6+(i%7)*.12)
			u.figure_radius=.04+(i%9)*.2;u.facing=frame*.08-i*.19
			u.stance=GameUnit.STANCE_CRAWL if (i+frame)%3==0 else GameUnit.STANCE_NONE
			u.model.player.seek(float((i+frame)%17)*.037,true)
			var mesh:MeshInstance3D=u._geoms[i%u._geoms.size()]
			mesh.visible=(frame+i)%4!=0
		compare(field,details,world,"live pose, scale, visibility and radius "+str(frame))
	for u in actors:
		u.position=origin;u.rotation=Vector3.ZERO;u.scale=Vector3.ONE;u.stance=GameUnit.STANCE_NONE
		for mesh in u._geoms:mesh.visible=true
	field.focus=Vector2(origin.x,origin.z)
	for property:String in ["hidden","fogged","dead","visible"]:
		for i in actors.size():actors[i].set(property,i%2==0)
		compare(field,details,world,"same-frame "+property)
		for u in actors:u.set(property,property=="visible")
	actors[0].model.visible=false;compare(field,details,world,"hidden model");actors[0].model.visible=true
	var parent:=actors[0]._geoms[0].get_parent() as Node3D
	parent.visible=false;compare(field,details,world,"hidden geometry ancestor");parent.visible=true
	var empty_mesh:=MeshInstance3D.new();actors[0].add_child(empty_mesh);actors[0]._geoms.append(empty_mesh)
	var non_mesh:=MultiMeshInstance3D.new();actors[0].add_child(non_mesh);actors[0]._geoms.append(non_mesh)
	compare(field,details,world,"missing mesh and other geometry are skipped")
	actors[0]._geoms.erase(non_mesh);non_mesh.free();empty_mesh.free()
	compare(field,details,world,"freed geometry is skipped");actors[0]._geoms.pop_back()
	var part:=actors[0]._geoms[0] as MeshInstance3D
	var saved_mesh:=part.mesh;var box:=BoxMesh.new();box.size=Vector3(2.0,.2,1.0)
	part.mesh=box;actors[0].stance=GameUnit.STANCE_CRAWL
	compare(field,details,world,"same-frame replacement mesh bounds")
	box.size=Vector3(3.0,.4,.6);compare(field,details,world,"same-frame in-place mesh bounds")
	part.mesh=saved_mesh;actors[0].stance=GameUnit.STANCE_NONE
	actors[0].physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_ON
	actors[0].position+=Vector3(.3,0,-.2)
	compare(field,details,world,"engine interpolated transforms")
	actors[0].reset_physics_interpolation();compare(field,details,world,"reset interpolated transforms")
	actors[0].physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;actors[0].position=origin
	for delta in [-29.001,-29.0,-28.999,28.999,29.0,29.001]:
		actors[0].position=origin+Vector3(delta,0,0)
		compare(field,details,world,"focus border "+str(delta))
	actors[0].position=origin
	var custom_unit:=actor(world,origin,1000,true) as CustomUnit
	check(native(field,details,world.visible_units())==null and custom_unit.queries==0,"custom actor declines before its callback")
	field.contacts(details,world)
	check(custom_unit.queries==1,"custom actor callback runs once through complete fallback")
	compare(field,details,world,"custom actor fallback")
	world.erase_unit(1000);custom_unit.free()
	var custom_details:=CustomDetails.new();custom_details.terrain=terrain;world.add_child(custom_details);custom_details.set_process(false)
	check(native(field,custom_details,world.visible_units())==null and custom_details.queries==0,"custom terrain collector declines before admission callbacks")
	compare(field,custom_details,world,"custom terrain admission fallback")
	custom_details.free()
	var custom_mesh:=CustomMesh.new();custom_mesh.mesh=BoxMesh.new();actors[0].add_child(custom_mesh);actors[0]._geoms.append(custom_mesh)
	check(native(field,details,world.visible_units())==null,"custom mesh methods decline complete query")
	compare(field,details,world,"custom mesh fallback")
	actors[0]._geoms.erase(custom_mesh);custom_mesh.free()
	var old_model:=actors[0].model;var custom_model:=CustomModel.new();actors[0].add_child(custom_model);actors[0].model=custom_model
	check(native(field,details,world.visible_units())==null,"custom model declines complete query")
	compare(field,details,world,"custom model fallback")
	actors[0].model=old_model;custom_model.free()
	actors[0].info.smooth_joints=true;actors[0].refresh_figure(true)
	actors[0].model.set_process(false)
	actors[0].model.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actors[0].model.player.play("ei/cidle01",0.0);actors[0].model.player.seek(.3,true)
	check(native(field,details,world.visible_units())!=null,"rebuilt smooth figure remains native-supported")
	compare(field,details,world,"same-frame smooth figure rebuild")
	var detached:=actors[0];world.remove_child(detached)
	compare(field,details,world,"detached actor is excluded");world.add_child(detached)
	var removed: GameUnit = actors.pop_back();world.erase_unit(48);removed.free()
	compare(field,details,world,"removed actor is absent immediately")
	check(kernel.contacts(world.visible_units(),null,field.focus,GameUnit,EIUnitModel,TerrainDetails,64.0,32,GameUnit.STANCE_CRAWL)==null,"missing terrain collector declines")
	check(kernel.contacts(world.visible_units(),details,Vector2(INF,0),GameUnit,EIUnitModel,TerrainDetails,64.0,32,GameUnit.STANCE_CRAWL)==null,"non-finite focus preserves script fallback")
	var timings:=[]
	for scenario:String in ["crowd","outside","hidden"]:
		for u in actors:
			u.position=origin+Vector3(100,0,0) if scenario=="outside" else origin
			u.hidden=scenario=="hidden"
		pressure_script._kernel=kernel
		compare(field,details,world,"timed "+scenario)
		for enabled in [false,true,true,false]:
			pressure_script._kernel=kernel if enabled else null
			var started:=Time.get_ticks_usec()
			for i in 240:field.contacts(details,world)
			timings.append({"scenario":scenario,"native":enabled,"queries":240,"usec":Time.get_ticks_usec()-started})
	print("VEGETATION_CONTACTS_NATIVE_TIMING ",JSON.stringify(timings))
	pressure_script._kernel=kernel;world.free();finish()
