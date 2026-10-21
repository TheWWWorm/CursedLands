extends Node
## Native/script parity for packing, budgets, visibility and scene lifetime.
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
	terrain.free(); finish()

func finish() -> void:
	FileAccess.open(out.path_join("native.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	TexUpscale.shutdown(); get_tree().quit(1 if not failures.is_empty() else 0)
