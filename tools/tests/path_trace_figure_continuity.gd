extends Node
const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func _ready() -> void:
	var world := GameWorld.new(); add_child(world)
	world.set_process(false); world.set_physics_process(false)
	var unit := world.spawn_unit({"prototype":"Human Hero", "position":Vector3(1,1,0),"weapons":PackedStringArray()})
	unit.set_process(false); unit.set_physics_process(false)
	var neighbour := world.spawn_unit({"prototype":"Human Hero", "position":Vector3(3,1,0),"weapons":PackedStringArray()})
	neighbour.set_process(false); neighbour.set_physics_process(false)
	var marks := OrderMarks.new()
	var body: MeshInstance3D = unit.model.find_children("*","MeshInstance3D",true,false)[0]
	var material := body.get_active_material(0) as EIUnitModel.LitMaterial
	var bright := marks._bright_of(material) as EIUnitModel.LitMaterial
	check(bright.shader == material.shader,"highlight retains the live PT shader")
	check(bright.get_shader_parameter("unit_emission") == material.get_shader_parameter("unit_emission"),"selection does not turn the body into a self-lit surface")
	check(bright.get_shader_parameter("unit_highlight") == 1.0,"selection has a separate presentation cue")
	check(bright.get_shader_parameter("surface_tex") == material.get_shader_parameter("surface_tex"),"selection retains metal/skin response")
	for native in [false,true]:
		var scene := Scene.new(); scene.lighting_camera_mask=1
		if not native: scene._kernel=null
		for actor in [unit,neighbour]:
			for mesh in scene._root_meshes(actor,true): scene._pack_mesh(mesh,mesh.mesh)
		scene.updates(true)
		var neighbour_vertices := {}
		for e: Dictionary in scene.instances:
			if neighbour.model.is_ancestor_of(e.node.get_ref()):
				var geo: Dictionary = scene.geometries[e.geometry]
				neighbour_vertices[e.geometry] = scene.vertices.slice(geo.offset*16,(geo.offset+geo.count)*16)
		var count := scene.instances.filter(func(e):return e.mask!=0).size()
		check(count>12,"fixture gathers the articulated hero")
		for value in [.4,-.4,0.0]:
			var before := unit.model
			if value==0:unit.buffs.erase("strength");unit.buffs.erase("weak")
			else:
				unit.buffs.erase("strength" if value<0 else "weak")
				unit.buffs["strength" if value>0 else "weak"]={"p":1.0,"left":60.0}
			# Exercise the same rebuild used by spell effects, not a mesh stub.
			unit.refresh_figure()
			check(unit.model!=before,"spell replaces the body geometry")
			var changes: Dictionary=scene.updates()
			check(scene.instances.filter(func(e):return e.mask!=0).size()==count,"every retained actor part survives the first buff/debuff frame")
			check(not changes.poses.is_empty(),"the first frame supplies the replacement vertices")
			var exact:=true
			for e: Dictionary in scene.instances:
				var node: MeshInstance3D=e.node.get_ref()
				exact=exact and is_instance_valid(node) and (unit.model.is_ancestor_of(node) or neighbour.model.is_ancestor_of(node)) and e.mesh==node.mesh
			check(exact,"retained rays follow the new model, not the removed body")
			var untouched := true
			for geometry in neighbour_vertices:
				var geo: Dictionary = scene.geometries[geometry]
				untouched = untouched and scene.vertices.slice(geo.offset*16,(geo.offset+geo.count)*16) == neighbour_vertices[geometry]
			check(untouched,"reshaping one actor preserves the adjacent actor's geometry")
			await get_tree().process_frame
			scene.updates()
			check(scene.instances.filter(func(e):return e.mask!=0).size()==count,"freeing the old rig does not remove the traced body")
	marks.free();world.free()
	print("PT_FIGURE_CONTINUITY ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
