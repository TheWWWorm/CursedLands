extends Node
const Cache=preload("res://src/game/fx/raytrace_source_cache.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _ready() -> void:
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var cache:=Cache.new()
	var first: Dictionary=cache.surface(mesh,0);var second: Dictionary=cache.surface(mesh,0)
	check(cache.hits==1 and cache.misses==1,"repeated snapshot avoids the second GPU mesh readback")
	check(first.arrays==second.arrays and second.arrays[Mesh.ARRAY_VERTEX]==arrays[Mesh.ARRAY_VERTEX],"cached geometry is identical to the source")
	mesh.clear_surfaces();arrays[Mesh.ARRAY_VERTEX][0]=Vector3(3,2,1)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var changed: Dictionary=cache.surface(mesh,0)
	check(cache.misses==2 and changed.arrays[Mesh.ARRAY_VERTEX][0]==Vector3(3,2,1),"mesh change invalidates old source geometry")
	var key:=mesh.get_instance_id();var ref:=weakref(mesh);mesh=null
	check(ref.get_ref()==null,"source cache does not retain mesh resources")
	cache._erase(key)
	check(cache._entries.is_empty() and cache._bytes==0,"expired source entry can be released")
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(Color.RED)
	var texture:=ImageTexture.create_from_image(image)
	var red:=cache.image(texture,-1,4);var hit_count:=cache.hits
	check(cache.image(texture,-1,4)==red and cache.hits==hit_count+1,"repeated snapshot avoids the second texture readback")
	image.fill(Color.BLUE);texture.update(image)
	var blue:=cache.image(texture,-1,4)
	check(blue.get_pixel(0,0).b>0.99 and blue!=red,"texture update invalidates normalized cached pixels")
	cache.clear()
	check(cache._entries.is_empty() and cache._bytes==0,"explicit teardown releases source images and arrays")
	print("RT_SOURCE_CACHE ",checks," checks ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
