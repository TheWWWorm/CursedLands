extends Node
## Exercise the actual worker, upload and resident-page paths with controlled
## bake inputs. Mutable material state must never enter the shared LRU.
const SOURCE="""shader_type spatial;
render_mode unshaded;
uniform sampler2D baked_ground : source_color;
uniform vec2 bake_origin;
uniform vec2 bake_span;
uniform float probe_weather;
void fragment(){ALBEDO=texture(baked_ground,UV).rgb*probe_weather;}
"""
class TestTerrain extends EITerrain:
	func land_shader_source() -> String:
		return TERRAIN_SHADER.replace("shader_type spatial;","shader_type spatial;\nuniform float probe_weather;")

var checks:=0
var failures:=[]
var camera:Camera3D

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)

func make_terrain(weather:float,changed_pixels:=false,changed_tiles:=false)->EITerrain:
	var t:=TestTerrain.new()
	t.sectors_x=3;t.sectors_y=3;t.texture_size=128;t.tile_size=32;t._atlas_source_size=128
	var pixels:=Image.create(128,128,false,Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:pixels.set_pixel(x,y,Color(float(x)/128.0,float(y)/128.0,.75 if changed_pixels else .25))
	var images:Array[Image]=[EITerrain.padded_atlas(pixels,32,EITerrain.TERRAIN_GUTTER)]
	t._detail_atlases=Texture2DArray.new();t._detail_atlases.create_from_images(images)
	t.land_tile.resize(48*48);t.land_tile.fill(1 if changed_tiles else 0)
	var shader:=Shader.new();shader.code=SOURCE
	t._land_mat=ShaderMaterial.new();t._land_mat.shader=shader
	t._land_mat.set_shader_parameter("probe_weather",weather)
	add_child(t)
	var sector:=MeshInstance3D.new();sector.name="Sector_0_0"
	var mesh:=PlaneMesh.new();mesh.size=Vector2(32,32);sector.mesh=mesh;sector.position=Vector3(16,0,-16);t.add_child(sector)
	t.color_cache=TerrainColorCache.create(t);t.color_cache.set_process(false)
	t.color_cache.prepare(camera)
	return t

func texture(t:EITerrain)->Texture2D:
	if t.color_cache._resident.is_empty():return null
	return t.color_cache._resident[Vector2i.ZERO].material.get_shader_parameter("baked_ground")

func _ready()->void:run.call_deferred()

func run()->void:
	GameData.options.gfx_terrain=1;GameData.options.gfx_soft_ground=0
	camera=Camera3D.new();add_child(camera);camera.position=Vector3(16,30,0);camera.look_at(Vector3(16,0,-16));camera.current=true
	TerrainColorCache.clear_shared()
	var first:=make_terrain(.25)
	var old:=texture(first)
	check(old!=null and first.color_cache.built==1,"first page uses the native bake and upload")
	if old==null:first.free();finish();return
	var pixels:=old.get_image().get_data()
	var first_material:ShaderMaterial=first.color_cache._resident[Vector2i.ZERO].material
	var weak: WeakRef = weakref(first);first.free()
	check(weak.get_ref()==null,"shared pages do not retain their terrain")
	var second:=make_terrain(.75)
	check(texture(second)==old and second.color_cache.built==0 and second.color_cache.reused==1,"recreated terrain reuses the uploaded texture without a bake")
	var second_material:ShaderMaterial=second.color_cache._resident[Vector2i.ZERO].material
	check(second_material!=first_material and second_material.get_shader_parameter("probe_weather")==.75,"reused colour gets current-world material uniforms")
	check(texture(second).get_image().get_data()==pixels,"reused mipmapped colour is byte identical")
	second.free()
	for change in ["pixels","tiles"]:
		var changed:=make_terrain(.75,change=="pixels",change=="tiles")
		check(changed.color_cache.built==1 and texture(changed)!=old,"changed "+change+" trigger a new native bake")
		check(texture(changed).get_image().get_data()!=pixels,"changed "+change+" are reflected in output colour")
		changed.free()
	var restored:=make_terrain(.5)
	check(texture(restored)==old,"returning to unchanged inputs finds their page")
	# Every native configure input and per-page density participates in identity.
	var images:Array[Image]=[Image.create(16,16,false,Image.FORMAT_RGBA8)]
	var tiles:=PackedInt32Array([0,1,2,3])
	var key:=TerrainColorCache.source_key(images,tiles,Vector2i(2,2),16,16,4,false)
	for args in [[Vector2i(1,4),16,16,4,false],[Vector2i(2,2),32,16,4,false],
		[Vector2i(2,2),16,32,4,false],[Vector2i(2,2),16,16,8,false],[Vector2i(2,2),16,16,4,true]]:
		check(key!=TerrainColorCache.source_key(images,tiles,args[0],args[1],args[2],args[3],args[4]),"sampling layout and colour space invalidate shared colour")
	var page_key:=restored.color_cache._page_key(Vector2i.ZERO)
	restored._atlas_hd=true
	check(page_key!=restored.color_cache._page_key(Vector2i.ZERO),"output density invalidates a page")
	restored._atlas_hd=false
	check(page_key!=restored.color_cache._page_key(Vector2i.ONE),"sector coordinates identify separate pages")
	# Small real textures with conservative byte charges exercise the byte
	# and entry limits without allocating hundreds of MiB for a test.
	TerrainColorCache.clear_shared()
	for i in 70:TerrainColorCache._remember(str(i),old,1)
	check(TerrainColorCache._shared_pages.size()==64 and not TerrainColorCache._shared_pages.has("0"),"entry limit evicts oldest pages")
	TerrainColorCache.clear_shared()
	for i in 3:TerrainColorCache._remember(str(i),old,TerrainColorCache.BUDGET_BYTES/2)
	check(TerrainColorCache._shared_bytes==TerrainColorCache.BUDGET_BYTES and TerrainColorCache._shared_pages.size()==2 \
		and not TerrainColorCache._shared_pages.has("0"),"byte budget evicts oldest pages")
	TerrainColorCache.clear_shared()
	check(texture(restored)==old and old.get_image().get_data()==pixels,"LRU eviction never invalidates an active world's texture")
	restored.free();finish()

func finish()->void:
	camera.queue_free()
	print("TERRAIN_COLOR_REUSE ",checks," checks ",failures.size()," failures")
	get_tree().quit(int(not failures.is_empty()))
