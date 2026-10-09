class_name TerrainColorCache
extends Node
## A bounded derived-color cache. Map shape, original tile codes, live light,
## weather, water levels and procedural normal/sharpening stay in their owners.
## Only immutable tile color blending moves out of the per-fragment hot path.
const BUDGET_BYTES:=128*1024*1024
const MAX_JOBS:=2
const SECTOR_TILES:=16
const GUTTER_TILES:=1
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

class BakeJob extends RefCounted:
	var field:RefCounted
	var sector:Vector2i
	var density:int
	var pixels:Image
	func run()->void:pixels=field.bake(sector,density)

static func available()->bool:
	var args:=OS.get_cmdline_user_args()
	return DisplayServer.get_name()!="headless" and ClassDB.class_exists("TerrainColorField") \
		and Portability.compatibility() and not args.has("--ei-script-terrain") \
		and (OS.has_feature("android") or args.has("--ei-baked-terrain"))

static func create(t:EITerrain)->TerrainColorCache:
	var cache:=TerrainColorCache.new();cache.name="TerrainColorCache";cache.terrain=t;t.add_child(cache);cache.refresh();return cache

func refresh()->void:
	var enabled:=Gfx.on("gfx_terrain") and not Gfx.on("gfx_soft_ground")
	if not enabled:
		clear();_enabled=false;return
	_enabled=true
	if _field==null:
		var images:Array[Image]=[]
		for i in terrain._detail_atlases.get_layers():
			var pixels:=terrain._detail_atlases.get_layer_data(i)
			if pixels==null:_enabled=false;return
			images.append(pixels)
		_field=ClassDB.instantiate("TerrainColorField")
		if not _field.configure(images,terrain.land_tile,Vector2i(terrain.sectors_x*16,terrain.sectors_y*16),terrain.texture_size,terrain.tile_size,EITerrain.TERRAIN_GUTTER,false):
			_field=null;_enabled=false;return
		_sectors.clear()
		for node in terrain.get_children():
			if not (node is EITerrainSector or node is MeshInstance3D) or not String(node.name).begins_with("Sector_"):continue
			var parts:=String(node.name).split("_");var key:=Vector2i(int(parts[1]),int(parts[2]))
			_sectors.append({"key":key,"node":node,"box":node.global_transform*node.get_aabb()})
	var source := terrain.land_shader_source()
	if source != _shader_source:
		_shader_source=source
		_shader=Gfx.make_shader(source.replace("shader_type spatial;","shader_type spatial;\n#define EI_BAKED_TERRAIN"),true,true)
	for record:Dictionary in _resident.values():
		record.material.shader=_shader
		_copy_parameters(record.material)
	_poll=0.0

func _copy_parameters(material:ShaderMaterial)->void:
	if terrain._transitions==null or terrain._transitions.admitted==0:
		material.set_shader_parameter("transition_tiles",null)
	if terrain._cliffs==null or terrain._cliffs.admitted==0:
		material.set_shader_parameter("cliff_tiles",null)
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
	for record:Dictionary in _sectors:
		if not is_instance_valid(record.node):continue
		var box:AABB=record.box
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
	return clampi((terrain.tile_size-16)*(2 if terrain._atlas_hd else 1),16,192)

func _start_jobs()->void:
	if not _enabled:return
	for record:Dictionary in _wanted:
		if _jobs.size()>=MAX_JOBS:return
		var key:Vector2i=record.key
		if _resident.has(key) or _building.has(key) or _failed.has(key):continue
		var job:=BakeJob.new();job.field=_field;job.sector=key;job.density=_density()
		var task:=WorkerThreadPool.add_task(job.run,false,"terrain color")
		_jobs.append({"task":task,"job":job,"key":key,"node":record.node});_building[key]=true

func _evict()->bool:
	var victim:Variant=null;var oldest:=2147483647
	for key in _resident:
		var record:Dictionary=_resident[key]
		if not _wanted_keys.has(key) and int(record.used)<oldest:victim=key;oldest=record.used
	if victim==null:return false
	var record:Dictionary=_resident[victim]
	if is_instance_valid(record.node) and record.node.get_surface_override_material(0)==record.material:
		record.node.set_surface_override_material(0,null)
	_bytes-=int(record.bytes);_resident.erase(victim);return true

func _finish(wait_all:=false)->void:
	var uploaded:=false
	for i in range(_jobs.size()-1,-1,-1):
		var row:Dictionary=_jobs[i]
		if not wait_all and (uploaded or not WorkerThreadPool.is_task_completed(row.task)):continue
		WorkerThreadPool.wait_for_task_completion(row.task)
		_jobs.remove_at(i);_building.erase(row.key)
		var pixels:Image=row.job.pixels
		if pixels==null:_failed[row.key]=true;discarded+=1;continue
		if not _wanted_keys.has(row.key) or not is_instance_valid(row.node):discarded+=1;continue
		var bytes:=pixels.get_data().size()
		while _bytes+bytes>BUDGET_BYTES and _evict():pass
		if _bytes+bytes>BUDGET_BYTES:_failed[row.key]=true;discarded+=1;continue
		var material:=ShaderMaterial.new();material.shader=_shader;_copy_parameters(material)
		material.set_shader_parameter("baked_ground",ImageTexture.create_from_image(pixels))
		material.set_shader_parameter("bake_origin",Vector2(row.key*16-Vector2i.ONE))
		material.set_shader_parameter("bake_span",Vector2(18,18))
		row.node.set_surface_override_material(0,material)
		_resident[row.key]={"node":row.node,"material":material,"bytes":bytes,"used":_serial};_bytes+=bytes;built+=1;uploaded=true

func prepare(camera:Camera3D)->void:
	if not _enabled:return
	_select(camera);_start_jobs()
	while not _jobs.is_empty():
		_finish(true);NetStatus.keep_alive();_start_jobs()

func _process(dt:float)->void:
	if not _enabled:return
	_poll-=dt
	var camera:=get_viewport().get_camera_3d()
	if camera==null:return
	if _poll<=0.0:_select(camera);_poll=.2
	_finish();_start_jobs()

func clear()->void:
	_enabled=false
	for row in _jobs:WorkerThreadPool.wait_for_task_completion(row.task)
	_jobs.clear();_building.clear();_failed.clear();_wanted.clear();_wanted_keys.clear()
	for row:Dictionary in _resident.values():
		if is_instance_valid(row.node) and row.node.get_surface_override_material(0)==row.material:row.node.set_surface_override_material(0,null)
	_resident.clear();_bytes=0;_field=null;_shader=null;_shader_source="";_sectors.clear()

func _exit_tree()->void:clear()
