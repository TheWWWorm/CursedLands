class_name TerrainColorCache
extends Node
## A bounded derived-color cache. Map shape, original tile codes, live light,
## weather, water levels and procedural normal/sharpening stay in their owners.
## Only immutable tile color blending moves out of the per-fragment hot path.
const BUDGET_BYTES:=128*1024*1024
const MAX_JOBS:=2
const PREPARE_JOBS:=8
const PREPARE_BYTES:=64*1024*1024
const SECTOR_TILES:=16
const GUTTER_TILES:=1
# Content-addressed immutable textures survive a save/zone rebuild. They own
# no terrain, materials or worker jobs; active worlds keep their own uniforms.
# A single shared LRU has the same bound as one world's resident page set.
static var _shared_pages := {}
static var _shared_bytes := 0
var _source_key := ""
var terrain:EITerrain
var _field:RefCounted
var _shader:Shader
var _shader_source := ""
var _sectors:Array[Dictionary]=[]
var _wanted:Array[Dictionary]=[]
var _wanted_keys:Dictionary={}
var _resident:Dictionary={}
var _jobs:Array[Dictionary]=[]
var _building:Dictionary={}
var _failed:Dictionary={}
var _bytes:=0
var _serial:=0
var _poll:=0.0
var _enabled:=false
var built:=0
var discarded:=0
var reused:=0

class BakeJob extends RefCounted:
	var field:RefCounted
	var sector:Vector2i
	var density:int
	var pixels:Image
	var _thread:Thread
	var _task: int = -1
	func run()->void:pixels=field.bake(sector,density)
	func start(preparing:bool)->bool:
		if preparing or not Portability.threads():
			_task=WorkerThreadPool.add_task(run,preparing,"terrain color")
			return _task>=0
		# The render worker cooperatively takes pool tasks while waiting.
		# A native bake can take hundreds of milliseconds: keep runtime
		# bakes off that queue, even when their priority would be low.
		# MAX_JOBS still bounds both CPU work and temporary image memory.
		_thread=Thread.new()
		if _thread.start(run,Thread.PRIORITY_LOW)!=OK:
			_thread=null;return false
		return true
	func completed()->bool:
		return not _thread.is_alive() if _thread!=null else _task<0 or WorkerThreadPool.is_task_completed(_task)
	func join()->void:
		if _thread!=null:
			_thread.wait_to_finish();_thread=null
		elif _task>=0:
			WorkerThreadPool.wait_for_task_completion(_task);_task=-1

static func available(t:EITerrain=null)->bool:
	var args:=OS.get_cmdline_user_args()
	if RenderingServer.get_current_rendering_method()=="forward_plus":
		return DisplayServer.get_name()!="headless" and ClassDB.class_exists("TerrainColorField") \
			and not args.has("--ei-script-terrain") and _forward_eligible(t)
	return DisplayServer.get_name()!="headless" and ClassDB.class_exists("TerrainColorField") \
		and RenderingServer.get_current_rendering_method() in ["gl_compatibility", "mobile"] and not args.has("--ei-script-terrain") \
		and (OS.has_feature("android") or args.has("--ei-baked-terrain"))

static func _forward_eligible(t:EITerrain)->bool:
	# Arenas share their own compact cache. Keep richer transition samplers
	# and oversized replacement atlases on the original desktop path.
	if t==null or t.texture_size<=0 or (t.sectors_x<=2 and t.sectors_y<=2):return false
	var density:=(t.tile_size-16)*(t._atlas_source_size/t.texture_size)*(2 if t._atlas_hd else 1)
	return density>=16 and density<=192 \
		and (t._transitions==null or t._transitions.admitted==0)

static func create(t:EITerrain)->TerrainColorCache:
	var cache:=TerrainColorCache.new();cache.name="TerrainColorCache";cache.terrain=t;t.add_child(cache);cache.refresh();return cache

func refresh()->void:
	var enabled:=Gfx.on("gfx_terrain") and (not Gfx.on("gfx_soft_ground") or not Portability.compatibility())
	if RenderingServer.get_current_rendering_method()=="forward_plus":enabled=enabled and _forward_eligible(terrain)
	if not enabled:
		clear();_enabled=false;return
	_enabled=true
	if _field==null:
		var images:Array[Image]=[]
		for i in terrain._detail_atlases.get_layers():
			var pixels:=terrain._detail_atlases.get_layer_data(i)
			if pixels==null:_enabled=false;return
			if pixels.is_compressed() and pixels.decompress()!=OK:_enabled=false;return
			images.append(pixels)
		_field=ClassDB.instantiate("TerrainColorField")
		if not _field.configure(images,terrain.land_tile,Vector2i(terrain.sectors_x*16,terrain.sectors_y*16),terrain.texture_size,terrain.tile_size,EITerrain.TERRAIN_GUTTER,not Portability.compatibility()):
			_field=null;_enabled=false;return
		_source_key=source_key(images,terrain.land_tile,Vector2i(terrain.sectors_x*16,terrain.sectors_y*16),terrain.texture_size,terrain.tile_size,EITerrain.TERRAIN_GUTTER,not Portability.compatibility())
		_sectors.clear()
		for node in terrain.get_children():
			if not (node is EITerrainSector or node is MeshInstance3D) or not String(node.name).begins_with("Sector_"):continue
			var parts:=String(node.name).split("_");var key:=Vector2i(int(parts[1]),int(parts[2]))
			# Terrain-local: the cache may be created before the terrain
			# enters the tree (the world built ahead); _select maps the boxes.
			_sectors.append({"key":key,"node":node,"box":node.transform*node.get_aabb()})
	var source := terrain.land_shader_source()
	if source != _shader_source:
		_shader_source=source
		_shader=Gfx.make_shader(source.replace("shader_type spatial;","shader_type spatial;\n#define EI_BAKED_TERRAIN"),true,true)
	for record:Dictionary in _resident.values():
		record.material.shader=_shader
		_copy_parameters(record.material)
	for key:Vector2i in _resident:_refresh_soft(key)
	_poll=0.0

## The deformed mesh owns its live trail parameters. Change only its colour
## sampler, retaining clock, layer, geometry, lighting and weather updates.
## Mobile/Compatibility preserve their existing override/expiry behaviour.
func apply_soft_material(key:Vector2i,material:ShaderMaterial)->void:
	if RenderingServer.get_current_rendering_method()!="forward_plus" or not _resident.has(key):return
	var cached:ShaderMaterial=_resident[key].material
	material.shader=_shader
	for name:StringName in [&"baked_ground",&"bake_origin",&"bake_span"]:
		material.set_shader_parameter(name,cached.get_shader_parameter(name))

func _refresh_soft(key:Vector2i,restore:=false)->void:
	if RenderingServer.get_current_rendering_method()!="forward_plus" or not is_instance_valid(terrain.details):return
	var soft:=terrain.details.soft_ground
	if not is_instance_valid(soft) or not soft.sectors.has(key):return
	var material:ShaderMaterial=soft.sectors[key].material
	if restore:
		material.shader=terrain._land_mat.shader
		material.set_shader_parameter("baked_ground",null)
	else:apply_soft_material(key,material)

func _copy_parameters(material:ShaderMaterial)->void:
	if terrain._transitions==null or terrain._transitions.admitted==0:
		material.set_shader_parameter("transition_tiles",null)
	if terrain._cliffs==null or terrain._cliffs.admitted==0:
		material.set_shader_parameter("cliff_tiles",null)
		material.set_shader_parameter("cliff_blends",null)
		material.set_shader_parameter("cliff_flatness",null)
	if terrain._caustics==null or terrain._caustics.admitted==0:
		material.set_shader_parameter("caustic_bed",null)
		material.set_shader_parameter("caustic_pattern",null)
	for parameter in terrain._land_mat.shader.get_shader_uniform_list():
		var key:StringName=parameter.name
		var value:Variant=terrain._land_mat.get_shader_parameter(key)
		if value!=null:material.set_shader_parameter(key,value)

func sync_parameter(key:StringName,value:Variant)->void:
	for record:Dictionary in _resident.values():record.material.set_shader_parameter(key,value)

func _select(camera:Camera3D)->void:
	_serial+=1;_wanted.clear();_wanted_keys.clear()
	var planes:=camera.get_frustum()
	var to_world:Transform3D=terrain.global_transform if terrain.is_inside_tree() else terrain.transform
	for record:Dictionary in _sectors:
		if not is_instance_valid(record.node):continue
		var box:AABB=to_world*record.box
		var centre:=box.get_center();var half:=box.size*.5
		var inside:=true
		for plane:Plane in planes:
			if plane.distance_to(centre)>plane.normal.abs().dot(half):inside=false;break
		if not inside:continue
		var row:=record.duplicate();row.distance=centre.distance_squared_to(camera.global_position)
		_wanted.append(row)
	_wanted.sort_custom(func(a,b):return a.distance<b.distance)
	var density:=_density()
	var n:=density*18
	# Image mip storage is at most four-thirds of the base RGBA plane.
	var limit:=maxi(1,BUDGET_BYTES/(n*n*4*4/3+64))
	if _wanted.size()>limit:_wanted.resize(limit)
	for record:Dictionary in _wanted:
		_wanted_keys[record.key]=true
		if _resident.has(record.key):_resident[record.key].used=_serial

func _density()->int:
	return clampi((terrain.tile_size-16)*(terrain._atlas_source_size/terrain.texture_size)*(2 if terrain._atlas_hd else 1),16,192)

## Hash exactly the native bake inputs, including authored/replacement pixels
## and sampling space. Map names or graphics revisions alone are insufficient.
static func source_key(images:Array[Image],tiles:PackedInt32Array,size:Vector2i,source_size:int,tile_size:int,gutter:int,linear:bool)->String:
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes([size,source_size,tile_size,gutter,linear,images.size()]))
	digest.update(tiles.to_byte_array())
	for pixels:Image in images:
		digest.update(var_to_bytes([pixels.get_size(),pixels.get_format(),pixels.has_mipmaps()]))
		digest.update(pixels.get_data())
	return digest.finish().hex_encode()

func _page_key(key:Vector2i)->String:
	return "%s:%d:%d:%d"%[_source_key,key.x,key.y,_density()]

static func _remember(key:String,texture:Texture2D,bytes:int)->void:
	if bytes<=0 or bytes>BUDGET_BYTES:return
	if _shared_pages.has(key):
		_shared_bytes-=int(_shared_pages[key].bytes);_shared_pages.erase(key)
	while not _shared_pages.is_empty() and (_shared_bytes+bytes>BUDGET_BYTES or _shared_pages.size()>=64):
		var oldest:String=_shared_pages.keys()[0]
		_shared_bytes-=int(_shared_pages[oldest].bytes);_shared_pages.erase(oldest)
	_shared_pages[key]={"texture":texture,"bytes":bytes};_shared_bytes+=bytes

static func clear_shared()->void:
	_shared_pages.clear();_shared_bytes=0

func _job_limit(preparing:bool)->int:
	if not preparing or Portability.handheld() or not Portability.threads():return MAX_JOBS
	var side:=_density()*18
	var page_bytes:=side*side*4*4/3+64
	return clampi(mini(OS.get_processor_count(),PREPARE_BYTES/page_bytes),1,PREPARE_JOBS)

func _start_jobs(preparing:=false)->void:
	if not _enabled:return
	var limit:=_job_limit(preparing)
	for record:Dictionary in _wanted:
		if _jobs.size()>=limit:return
		var key:Vector2i=record.key
		if _resident.has(key) or _building.has(key) or _failed.has(key):continue
		var page_key:=_page_key(key)
		if _shared_pages.has(page_key):
			var page:Dictionary=_shared_pages[page_key]
			_shared_pages.erase(page_key);_shared_pages[page_key]=page
			if _install(key,record.node,page.texture,page.bytes):reused+=1
			continue
		var job:=BakeJob.new();job.field=_field;job.sector=key;job.density=_density()
		if not job.start(preparing):_failed[key]=true;continue
		_jobs.append({"job":job,"key":key,"node":record.node});_building[key]=true

func _evict()->bool:
	var victim:Variant=null;var oldest:=2147483647
	for key in _resident:
		var record:Dictionary=_resident[key]
		if not _wanted_keys.has(key) and int(record.used)<oldest:victim=key;oldest=record.used
	if victim==null:return false
	var record:Dictionary=_resident[victim]
	_refresh_soft(victim,true)
	if is_instance_valid(record.node) and record.node.get_surface_override_material(0)==record.material:
		record.node.set_surface_override_material(0,null)
	_bytes-=int(record.bytes);_resident.erase(victim);return true

func _finish(wait_all:=false)->void:
	var uploaded:=false
	for i in range(_jobs.size()-1,-1,-1):
		var row:Dictionary=_jobs[i]
		if not wait_all and (uploaded or not row.job.completed()):continue
		row.job.join()
		_jobs.remove_at(i);_building.erase(row.key)
		var pixels:Image=row.job.pixels
		if pixels==null:_failed[row.key]=true;discarded+=1;continue
		if not _wanted_keys.has(row.key) or not is_instance_valid(row.node):discarded+=1;continue
		var bytes:=pixels.get_data().size()
		var texture:=ImageTexture.create_from_image(pixels)
		if _install(row.key,row.node,texture,bytes):
			_remember(_page_key(row.key),texture,bytes);built+=1;uploaded=true

func _install(key:Vector2i,node:Node3D,texture:Texture2D,bytes:int)->bool:
	while _bytes+bytes>BUDGET_BYTES and _evict():pass
	if _bytes+bytes>BUDGET_BYTES:_failed[key]=true;discarded+=1;return false
	var material:=ShaderMaterial.new();material.shader=_shader;_copy_parameters(material)
	material.set_shader_parameter("baked_ground",texture)
	material.set_shader_parameter("bake_origin",Vector2(key*16-Vector2i.ONE))
	material.set_shader_parameter("bake_span",Vector2(18,18))
	node.set_surface_override_material(0,material)
	_resident[key]={"node":node,"material":material,"bytes":bytes,"used":_serial};_bytes+=bytes
	_refresh_soft(key)
	return true

## Loading, early: select this view's pages and start their bakes on the
## pool, then return; the caller does other work (the replica spawn) while
## they bake. prepare_pump joins finished pages and starts the rest within
## the same bound; prepare(camera) finally joins them all.
func prepare_start(camera:Camera3D)->void:
	if not _enabled:return
	_select(camera);_start_jobs(true)

func prepare_pump()->void:
	if not _enabled or _jobs.is_empty():return
	_finish();_start_jobs(true)

func prepare(camera:Camera3D)->void:
	if not _enabled:return
	# Loading joins these independent native jobs before revealing the scene.
	# Use idle CPU cores here, with a separate bound on temporary image memory;
	# ordinary camera streaming keeps its separate, small worker allowance.
	_select(camera);_start_jobs(true)
	while not _jobs.is_empty():
		_finish(true);NetStatus.keep_alive();_start_jobs(true)

func _process(dt:float)->void:
	if not _enabled:return
	_poll-=dt
	var camera:=get_viewport().get_camera_3d()
	if camera==null:return
	if _poll<=0.0:_select(camera);_poll=.2
	_finish();_start_jobs()

func clear()->void:
	_enabled=false
	for row in _jobs:row.job.join()
	_jobs.clear();_building.clear();_failed.clear();_wanted.clear();_wanted_keys.clear()
	for key:Vector2i in _resident:
		_refresh_soft(key,true)
		var row:Dictionary=_resident[key]
		if is_instance_valid(row.node) and row.node.get_surface_override_material(0)==row.material:row.node.set_surface_override_material(0,null)
	_resident.clear();_bytes=0;_field=null;_shader=null;_shader_source="";_source_key="";_sectors.clear()

func _exit_tree()->void:clear()
