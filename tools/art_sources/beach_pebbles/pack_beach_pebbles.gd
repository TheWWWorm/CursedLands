extends SceneTree
## Convert Blender's exported metre/normal/UV data into a compact shared resource.
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	assert(args.size()==2,"Expected: -- input.json output.res")
	var rows: Array=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var models:=[]
	for row: Dictionary in rows:
		var model: Dictionary={}
		for lod: String in ["near","far"]:
			var input: Dictionary=row[lod]
			var data: Dictionary={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uvs":PackedVector2Array(),"indices":PackedInt32Array(input.indices)}
			for v: Array in input.vertices: data.vertices.append(Vector3(v[0],v[1],v[2]))
			for n: Array in input.normals: data.normals.append(Vector3(n[0],n[1],n[2]))
			for uv: Array in input.uvs: data.uvs.append(Vector2(uv[0],uv[1]))
			model[lod]=data
		models.append(model)
	var resource:=Resource.new();resource.set_meta("models",models)
	assert(ResourceSaver.save(resource,args[1],ResourceSaver.FLAG_COMPRESS)==OK)
	quit()
