extends Node
## Exercise the production camera/stream path over a controlled flat floor.
## Root generation is covered separately against original maps.
var checks := 0
var failures := 0
class Floor extends EITerrain:
	func height_at(_x: float, _y: float) -> float: return 0.0
	func size_ei() -> Vector2: return Vector2(256,256)
class QuietFar extends TerrainDetails.FarGrass:
	func tick(_details: TerrainDetails, _camera: Camera3D, _focus: Vector3, _delta: float) -> void: pass
class Observer extends TerrainDetails:
	var point := Vector2.ZERO
	func _stream(_key: Vector2i) -> void: pass
	func _update_scenery() -> void: pass
	func _update_submissions(p: Vector2) -> void:
		point=p
		super._update_submissions(p)

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)

func _ready() -> void:
	GameData.options.merge({"gfx_grass":0,"gfx_biome_cover":0,"gfx_soft_ground":0},true)
	var floor := Floor.new(); add_child(floor); floor.set_process(false)
	var d := Observer.new(); floor.add_child(d); d.terrain=floor
	d.set_process(false); d._grass=true; d._native_grass=false
	d._far_grass=QuietFar.new()
	d._mesh=TerrainDetails.blade_mesh(); d._far_mesh=TerrainDetails.blade_mesh(false)
	var camera := Camera3D.new(); add_child(camera); camera.make_current()
	await get_tree().process_frame
	var points: Array = []; var max_step := 0.0
	camera.position=Vector3(64,2,-64)
	for i in 81:
		camera.rotation.x=deg_to_rad(-4.0+float(i)*0.05)
		camera.force_update_transform(); d._process(1.0/60.0)
		if not points.is_empty(): max_step=maxf(max_step,d.point.distance_to(points[-1]))
		points.append(d.point)
	check(max_step<0.2,"shoulder pitch across the old horizon cutoff has no focus jump")
	check(d.point.distance_to(Vector2(64,-64))<1.0,"low camera keeps near grass around the player")
	# Repeated translation around an 8m cell boundary used to swap a whole
	# retained chunk between 14 and 6 leaves on every crossing.
	var node := TerrainDetails.Chunk.new(); d.add_child(node)
	node.multimesh=MultiMesh.new(); node.multimesh.mesh=d._far_mesh
	var key := Vector2i(4,0); d._chunks[key]=node
	var switches := 0; var previous: Mesh
	for i in 40:
		camera.position=Vector3(15.9 if i%2==0 else 16.1,2,-4)
		camera.rotation=Vector3.ZERO; camera.force_update_transform(); d._process(1.0/60.0)
		var chosen := d._chunk_mesh(key)
		if previous!=null and chosen!=previous: switches+=1
		node.multimesh.mesh=chosen; previous=chosen
	check(switches==0,"small repeated cell crossings do not alternate mesh detail")
	# Real travel must still promote/demote, so stability cannot just pin LOD.
	camera.position=Vector3(36,2,-4); camera.force_update_transform(); d._process(0.1)
	node.multimesh.mesh=d._chunk_mesh(key)
	check(node.multimesh.mesh==d._mesh,"approaching the chunk restores its detailed mesh")
	camera.position=Vector3(4,2,-4); camera.force_update_transform(); d._process(0.1)
	node.multimesh.mesh=d._chunk_mesh(key)
	check(node.multimesh.mesh==d._far_mesh,"leaving the chunk still selects its cheaper mesh")
	camera.position=Vector3(64,30,-64); camera.rotation.x=-PI/3
	camera.force_update_transform(); d._process(0.1)
	check(d.point.distance_to(Vector2(64,-64-30.0/tan(PI/3)))<0.01,"overhead camera retains its ground intersection")
	FileAccess.open("user://grass-camera-stability.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"horizon_max_step":max_step,"mesh_switches":switches},"\t"))
	floor.free(); camera.free()
	print("GRASS_CAMERA_STABILITY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
