extends Node
## Native/script parity for packing, budgets, visibility and scene lifetime.
class VisibilityUnit extends GameUnit:
	var audit_invisible := false
	func is_invisible() -> bool: return audit_invisible

const Scene = preload("res://src/game/fx/water_raytrace_scene.gd")
var checks := 0
var failures := []
var out := "user://water-rt-native"
func check(ok: bool, label: String) -> void:
	checks += 1; print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func _ready() -> void: run.call_deferred()

func arrays() -> Array:
	var a := []; a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-1,1,0),Vector3(1,1,0),Vector3(0,3,0),
		Vector3(120,1,0),Vector3(122,1,0),Vector3(121,3,0),Vector3(0,-4,0),Vector3(1,-4,0),Vector3(0,-3,0)])
	a[Mesh.ARRAY_NORMAL]=PackedVector3Array(); a[Mesh.ARRAY_TEX_UV]=PackedVector2Array(); a[Mesh.ARRAY_TEX_UV2]=PackedVector2Array()
	for i in 9:
		a[Mesh.ARRAY_NORMAL].append(Vector3(0.3,0.5,0.8).normalized()); a[Mesh.ARRAY_TEX_UV].append(Vector2(i*0.13,i*0.17))
		a[Mesh.ARRAY_TEX_UV2].append(Vector2(i/3,0))
	return a

func compare(a: Scene,b: Scene,label: String) -> void:
	check(a.triangles==b.triangles and a.failed==b.failed and a.images.size()==b.images.size(),label+": same geometry and texture budgets")
	check(a.geometries==b.geometries,label+": same vertex membership")
	var error := INF
	if a.vertices.size()==b.vertices.size():
		error=0.0
		for i in a.vertices.size(): error=maxf(error,absf(a.vertices[i]-b.vertices[i]))
	check(error<0.000002,label+": vertex attributes match (max error %.8f)"%error)
	var equal := true
	for i in mini(a.images.size(),b.images.size()): equal=equal and a.images[i].get_data()==b.images[i].get_data()
	check(equal,label+": texture layers match exactly")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="): out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(ClassDB.class_exists("WaterRaytraceKernel"),"native RT scene helper is loaded")
	if not ClassDB.class_exists("WaterRaytraceKernel"): finish(); return
	var terrain := EITerrain.new()
	var atlas := Texture2DArray.new(); var images: Array[Image]=[]
	for colour in [Color.RED,Color.GREEN,Color.BLUE]:
		var im := Image.create(4,4,false,Image.FORMAT_RGBA8); im.fill(colour); images.append(im)
	atlas.create_from_images(images); terrain._atlases=atlas
	var material := StandardMaterial3D.new(); material.albedo_color=Color(0.3,0.6,0.9,0.7)
	for land in [false,true]:
		for indexed in [false,true]:
			for transformed in [false,true]:
				var a := arrays()
				if indexed: a[Mesh.ARRAY_INDEX]=PackedInt32Array([6,7,8,0,2,1,3,5,4])
				var xf := Transform3D(Basis.from_euler(Vector3(0.1,0.2,0.3)).scaled(Vector3(1.2,0.7,1.7)),Vector3(2,0.4,1)) if transformed else Transform3D.IDENTITY
				var native := Scene.new(); var script := Scene.new(); script._kernel=null
				for scene in [native,script]:
					scene._terrain=terrain; scene._plane=0.0; scene._append(a,xf,material,land)
				compare(native,script,"land %s indexed %s transformed %s"%[land,indexed,transformed])
	var native := Scene.new(); var script := Scene.new(); script._kernel=null
	var negative_atlas := arrays(); negative_atlas[Mesh.ARRAY_TEX_UV2][0]=Vector2(-1,0)
	for scene in [native,script]:
		scene._terrain=terrain; scene._plane=0.0; scene._append(negative_atlas,Transform3D.IDENTITY,null,true)
	compare(native,script,"negative terrain atlas uses the original white fallback")
	native=Scene.new(); script=Scene.new(); script._kernel=null
	for scene in [native,script]:
		scene.triangles=Scene.MAX_TRIANGLES-1; scene._append(arrays(),Transform3D.IDENTITY,material,false)
	check(native.failed and script.failed,"both paths reject the full snapshot when the triangle budget is exceeded")
	var parent := Node3D.new(); add_child(parent)
	var node := MeshInstance3D.new(); node.mesh=BoxMesh.new(); parent.add_child(node)
	native=Scene.new(); script=Scene.new(); script._kernel=null
	for scene in [native,script]:
		scene._mesh_roots[node.get_instance_id()]=weakref(parent)
		scene._add_instance(node,0,node.global_transform)
	check(native._instance_updates(false)==script._instance_updates(false),"initial live instance masks match")
	check(native._instance_updates(false).is_empty() and script._instance_updates(false).is_empty(),"unchanged instances emit no updates")
	parent.position=Vector3(4,2,-3); parent.rotation=Vector3(0.2,0.4,-0.1)
	check(native._instance_updates(false)==script._instance_updates(false),"parent movement propagates the same transforms")
	for setting in [GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF]:
		node.cast_shadow=setting
		check(native._instance_updates(false)==script._instance_updates(false),"shadow visibility mask matches for setting %d"%setting)
	for layer in [EIUnitModel.CLOSE_VIEW_LAYER,EIUnitModel.REFLECTION_LAYER,EIUnitModel.CLOSE_VIEW_LAYER|1,0,1]:
		node.layers=layer
		var expected := 0 if layer in [0,EIUnitModel.CLOSE_VIEW_LAYER] else 1
		var a := native._instance_updates(true); var b := script._instance_updates(true)
		check(a==b and a[0].mask==expected,"camera layer changes update native/script reflection masks: %d"%layer)
	parent.hide()
	check(native._instance_updates(false)==script._instance_updates(false),"hidden ancestor masks its descendants")
	parent.show(); node.hide()
	check(native._instance_updates(false)==script._instance_updates(false),"hidden part remains masked after its parent returns")
	node.show()
	check(native._instance_updates(false)==script._instance_updates(false),"revealed part returns without a new geometry snapshot")
	node.mesh=SphereMesh.new()
	check(native._instance_updates(false)==script._instance_updates(false),"replaced mesh masks stale geometry")
	node.free()
	check(native._instance_updates(true)==script._instance_updates(true),"freed node is safe and stays masked")
	parent.free()
	check(native._instance_updates(true)==script._instance_updates(true),"freed ancestor is safe and stays masked")
	lighting_tracking()
	unit_visibility()
	terrain.free(); finish()


func lighting_tracking() -> void:
	for land in [false,true]:
		var parent := Node3D.new(); add_child(parent)
		var node := MeshInstance3D.new(); node.mesh=BoxMesh.new(); parent.add_child(node)
		var native := Scene.new(); var script := Scene.new(); script._kernel=null
		check(native._kernel.has_method("lighting_updates"),"native lighting tracker is available")
		for scene in [native,script]:
			scene._mesh_roots[node.get_instance_id()]=weakref(parent)
			scene._add_instance(node,0,node.global_transform)
			scene.instances[0].terrain=land
		for camera_mask in [1,1|EIUnitModel.CLOSE_VIEW_LAYER,EIUnitModel.REFLECTION_LAYER,0]:
			for scene in [native,script]:scene.lighting_camera_mask=camera_mask
			for setting in [GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
					GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED,GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY]:
				node.cast_shadow=setting
				for layer in [0,1,1<<19,EIUnitModel.CLOSE_VIEW_LAYER,EIUnitModel.REFLECTION_LAYER,EIUnitModel.CLOSE_VIEW_LAYER|1]:
					node.layers=layer
					var expected := 1 if (layer&camera_mask)!=0 else 0
					if (layer&~EIUnitModel.CLOSE_VIEW_LAYER)!=0:expected|=4
					if setting!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:expected|=2
					if setting==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:expected&=~1
					var a := native._instance_updates(false); var b := script._instance_updates(false)
					check(a==b and native.instances[0].mask==expected,"lighting masks land=%s camera=%d shadow=%d layers=%d"%[land,camera_mask,setting,layer])
		parent.position=Vector3(3,-2,7)
		check(native._instance_updates(false)==script._instance_updates(false),"lighting movement preserves baked terrain transforms: "+str(land))
		check(native._instance_updates(false).is_empty() and script._instance_updates(false).is_empty(),"stationary lighting instances emit no updates")
		parent.hide()
		check(native._instance_updates(false)==script._instance_updates(false),"lighting hidden ancestor parity")
		check(native._instance_updates(false).is_empty() and script._instance_updates(false).is_empty(),"hidden lighting group stays quiet")
		parent.show();node.hide()
		check(native._instance_updates(false)==script._instance_updates(false),"lighting hidden part parity")
		node.show();node.mesh=SphereMesh.new()
		check(native._instance_updates(false)==script._instance_updates(false),"lighting replaced mesh parity")
		# Switching back to reflection rules must also change native cached masks.
		for scene in [native,script]:scene.lighting_camera_mask=-1
		check(native._instance_updates(true)==script._instance_updates(true),"lighting to water mask parity")
		node.free()
		check(native._instance_updates(true)==script._instance_updates(true),"lighting freed node parity")
		parent.free()
		check(native._instance_updates(true)==script._instance_updates(true),"lighting freed ancestor parity")

func unit_visibility() -> void:
	var parent := VisibilityUnit.new(); add_child(parent)
	var node := MeshInstance3D.new(); node.mesh=BoxMesh.new(); parent.add_child(node)
	var native := Scene.new(); var script := Scene.new(); script._kernel=null
	for scene in [native,script]:
		scene.lighting_camera_mask=1
		scene._mesh_roots[node.get_instance_id()]=weakref(parent)
		scene._add_instance(node,0,node.global_transform)
	for hidden in [false,true,true,false]:
		parent.audit_invisible=hidden
		var a := native._instance_updates(false);var b := script._instance_updates(false)
		check(a==b and native.instances[0].mask==(0 if hidden else 7),"invisible unit masks match without a scene rebuild: "+str(hidden))
	parent.free()
	check(native._instance_updates(true)==script._instance_updates(true),"freed unit masks its retained parts safely")

func finish() -> void:
	FileAccess.open(out.path_join("native.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	TexUpscale.shutdown(); get_tree().quit(1 if not failures.is_empty() else 0)
