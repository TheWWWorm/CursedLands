extends Node
const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func _ready() -> void:
	GameData.options.gfx_materials=1
	var mat:=EIFigure.world_material_for("hadoganchest00") as ShaderMaterial
	var mask:=mat.get_shader_parameter("surface_tex") as Texture2D
	check(mask!=null,"original Hadagan chest has a spatial material map")
	if mask:
		var image:=mask.get_image()
		for point in [Vector2i(100,130),Vector2i(74,145),Vector2i(247,130),Vector2i(176,174)]:
			var c:=image.get_pixelv(point)
			check(c.b>0.8 and c.g<0.5,"metal lid, rivets and frame reflect as metal: "+str(point))
		for point in [Vector2i(30,140),Vector2i(196,126),Vector2i(30,40),Vector2i(216,54),Vector2i(30,230)]:
			var c:=image.get_pixelv(point)
			check(c.b<0.01 and c.g>0.8,"wood, clay and masonry in shared atlas stay nonmetal: "+str(point))
		image.save_png("user://hadagan-chest-material.png")
	for open in [false,true]:
		var obj:=EIFigure.instantiate("stst92","hadoganchest00",Vector3(1 if open else 0,.5,.5),PackedStringArray(),true,true)
		add_child(obj)
		var scene:=Scene.new();scene.path_materials=true
		for mesh: MeshInstance3D in obj.find_children("*","MeshInstance3D",true,false):scene._pack_mesh(mesh,mesh.mesh)
		check(not scene.geometries.is_empty(),"authored chest geometry loads "+str(open))
		check(scene.geometries.all(func(g):return g.surface_layer>=0),"closed/open chest carries its material mask into PT "+str(open))
		obj.free()
	var other:=EIFigure.world_material_for("barrel00") as ShaderMaterial
	check(other.get_shader_parameter("surface_tex")==null,"unmapped wood objects keep their existing profile")
	print("CHEST_SURFACE_MATERIAL ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
