extends Node
## Cold authored parts must not synchronize with the renderer during travel.
## The actual GPU readback remains the oracle for every PT-consumed channel.
const Figure = preload("res://src/ei/figure.gd")
const Cache = preload("res://src/game/fx/raytrace_source_cache.gd")
const CHANNELS := [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_INDEX]
var checks:=0
var failures:=0

func check(ok: bool,label: String) -> void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func readbacks(cache: RefCounted) -> int:
	for property in cache.get_property_list():
		if property.name=="surface_readbacks":return int(cache.get("surface_readbacks"))
	# Every cache miss in the original implementation reads the GPU surface.
	return int(cache.get("misses"))

func equal_channels(a: Array,b: Array) -> bool:
	for channel in CHANNELS:
		if a[channel]!=b[channel]:return false
	return true

func equal_gpu(mesh: ArrayMesh,source: Dictionary) -> bool:
	if not equal_channels(source.arrays,mesh.surface_get_arrays(0)):return false
	var shapes: Array=[]
	if mesh.get_blend_shape_count()>0:shapes=mesh.surface_get_blend_shape_arrays(0)
	if shapes.size()!=source.shapes.size():return false
	for i in shapes.size():
		if not equal_channels(source.shapes[i],shapes[i]):return false
	return true

func probe(mesh: ArrayMesh,label: String) -> void:
	var cache:=Cache.new()
	var source:=cache.surface(mesh,0)
	check(readbacks(cache)==0,label+" cold source avoids all GPU readbacks")
	check(equal_gpu(mesh,source),label+" positions, normals, UVs, indices and shapes match GPU exactly")
	cache.clear()

func edit_vertex(mesh: ArrayMesh,point: Vector3) -> void:
	if DisplayServer.get_name()=="headless":
		# Dummy storage ignores region uploads. Keep CPU validation useful with
		# a real surface edit; rendered runs exercise the native region update.
		var arrays:=mesh.surface_get_arrays(0)
		arrays[Mesh.ARRAY_VERTEX][0]=point
		mesh.clear_surfaces();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	else:mesh.surface_update_vertex_region(0,0,PackedVector3Array([point]).to_byte_array())

func _ready() -> void: run.call_deferred()

func run() -> void:
	print("RT_RETAINED_EDIT_MODE ","headless surface replacement" if DisplayServer.get_name()=="headless" else "native buffer region")
	var model:=Figure.get_model("unmocu")
	check(not model.is_empty() and not model.parts.is_empty(),"authored winged figure is available")
	if model.is_empty():finish();return
	var part: Dictionary=model.parts.values()[0]
	var fixed:=Figure.build_mesh(part,Vector3(.37,.58,.41))
	probe(fixed,"rigid figure")
	var morphed:=Figure.build_morph_mesh(part,Vector3(.37,.58,.41))
	probe(morphed,"complexion morph")
	var offsets:=PackedVector3Array();offsets.resize(int(part.vblocks)*4)
	for i in offsets.size():offsets[i]=Vector3(sin(i*.37)*.13,.17,cos(i*.21)*.09)
	var animated:=Figure.build_anim_morph_mesh(part,Vector3(.37,.58,.41),PackedStringArray(["audit"]),[offsets])
	probe(animated,"animation morph")
	# Cover arbitrary octants and values close to quantization boundaries.
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	var positions:=PackedVector3Array();var normals:=PackedVector3Array();var uv:=PackedVector2Array()
	for i in 600:
		positions.append(Vector3(i%3,float(i/3)*.01,float(i%7)*.13))
		normals.append(Vector3(sin(i*.73),cos(i*.37),sin(i*.51+.2)).normalized())
		uv.append(Vector2(i*.00317-.73,cos(i*.17)*3.7))
	arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv
	var sampled:=ArrayMesh.new();sampled.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var figure_script: Script=Figure
	if figure_script.has_method("_remember_raytrace_source"):figure_script.call("_remember_raytrace_source",sampled,arrays)
	probe(sampled,"600 uncompressed normal and UV samples")
	var retained: Dictionary=fixed.get_meta(&"ei_cpu_raytrace_source",{})
	check(retained.is_empty() or (int(retained.get("added_bytes",0))>0 and int(retained.get("added_bytes",0))<=int(retained.get("bytes",0))),"any retained source accounts for its additional CPU storage")
	var cache:=Cache.new();var generic:=ArrayMesh.new()
	generic.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var fallback:=cache.surface(generic,0)
	check(readbacks(cache)==1 and equal_gpu(generic,fallback),"unowned procedural mesh keeps the current-buffer fallback")
	cache.clear();cache=Cache.new()
	var old:=cache.surface(sampled,0)
	var before_edit:=readbacks(cache)
	var moved:=positions[0]+Vector3(.3,.2,.1)
	edit_vertex(sampled,moved)
	var changed:=cache.surface(sampled,0)
	check(readbacks(cache)==before_edit+1 and changed.arrays[Mesh.ARRAY_VERTEX][0]==moved and not sampled.has_meta(&"ei_cpu_raytrace_source"),"a same-resource vertex edit invalidates both retained and normalized source data")
	check(old.arrays[Mesh.ARRAY_VERTEX][0]==positions[0],"a live vertex edit cannot mutate an already packed source snapshot")
	sampled.clear_surfaces();arrays[Mesh.ARRAY_TEX_UV][0]=Vector2(4.25,-1.5)
	sampled.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	before_edit=readbacks(cache)
	changed=cache.surface(sampled,0)
	check(readbacks(cache)==before_edit+1 and changed.arrays[Mesh.ARRAY_TEX_UV][0]==Vector2(4.25,-1.5) and equal_gpu(sampled,changed),"surface replacement exposes current UVs through the fallback")
	var clone:=fixed.duplicate() as ArrayMesh;var clone_cache:=Cache.new()
	var copied:=clone_cache.surface(clone,0)
	check(readbacks(clone_cache)==1 and equal_gpu(clone,copied),"duplicated metadata cannot claim ownership of another mesh")
	var clone_point: Vector3=copied.arrays[Mesh.ARRAY_VERTEX][0]+Vector3(.7,.8,.9)
	edit_vertex(clone,clone_point)
	copied=clone_cache.surface(clone,0)
	check(readbacks(clone_cache)==2 and copied.arrays[Mesh.ARRAY_VERTEX][0]==clone_point,"a duplicated mesh remains live after region edits")
	var disabled:=Cache.new();disabled._enabled=false
	var one:=disabled.surface(fixed,0);var two:=disabled.surface(fixed,0)
	check(readbacks(disabled)==2 and equal_channels(one.arrays,two.arrays),"disabled-source-cache reference still forces actual readback")
	var ephemeral:=Figure._build_mesh(part,Vector3(.23,.71,.61));var life:=Cache.new()
	var key:=ephemeral.get_instance_id();var weak: WeakRef = weakref(ephemeral)
	life.surface(ephemeral,0);ephemeral=null
	check(weak.get_ref()==null,"retained source watches do not keep an unused mesh alive")
	life._erase(key)
	check(life._entries.is_empty() and life._bytes==0,"expired retained source can release its cache accounting")
	print("RT_RETAINED_MEMORY ",JSON.stringify({"rigid":retained.get("bytes",0),"rigid_added":retained.get("added_bytes",0),
		"morph":morphed.get_meta(&"ei_cpu_raytrace_source",{}).get("bytes",0),"animation":animated.get_meta(&"ei_cpu_raytrace_source",{}).get("bytes",0)}))
	finish()

func finish() -> void:
	print("RT_RETAINED_SOURCES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
