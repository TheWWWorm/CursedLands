extends Node
## Compare retained geometry and complete roof maps with renderer readback.
var checks := 0
var failures := 0
var rows := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func _ready() -> void:
	GameData.options["auto_graphics"]=0
	for option in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	var campaign:=CampaignMap.load_from(GameData.texts)
	for zone in ["bz2h","gz2h"]:
		var map:Dictionary=campaign.zone(zone)
		var scene:=EIMapScene.load_map(map.mpr,map.mob,false)
		check(scene!=null,"authored map loads: "+zone)
		if scene==null:continue
		scene.process_mode=Node.PROCESS_MODE_DISABLED;add_child(scene)
		var saved:Dictionary={}
		var bytes:=0
		for mesh_node:MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
			var mesh:=mesh_node.mesh
			if mesh==null or not mesh.has_meta(EIFigure.GEOMETRY_META) or saved.has(mesh):continue
			var retained:=EIFigure.surface_geometry(mesh,0)
			var gpu:=mesh.surface_get_arrays(0)
			check(retained[0]==gpu[Mesh.ARRAY_VERTEX],zone+": retained positions equal rendered positions")
			check(retained[1]==gpu[Mesh.ARRAY_INDEX],zone+": retained indices equal rendered indices")
			saved[mesh]=retained
			bytes+=retained[0].size()*12+retained[1].size()*4
		check(saved.size()>10,zone+": scenery uses shared CPU geometry")
		var fast:=PackedFloat32Array();fast.resize(scene.terrain.water.size());fast.fill(SurfaceWeather.UNCOVERED)
		var expected:=fast.duplicate()
		for node:Node3D in scene.object_nodes:SurfaceWeather.rasterize_cover(node,scene.terrain,fast)
		for mesh:Mesh in saved:mesh.remove_meta(EIFigure.GEOMETRY_META)
		for node:Node3D in scene.object_nodes:SurfaceWeather.rasterize_cover(node,scene.terrain,expected)
		for mesh:Mesh in saved:mesh.set_meta(EIFigure.GEOMETRY_META,saved[mesh])
		check(fast==expected,zone+": entire roof map is bit-identical to readback path")
		var covered:=0
		for height in fast:
			if height!=SurfaceWeather.UNCOVERED:covered+=1
		check(covered>0,zone+": roof map includes actual shelters")
		rows.append({"zone":zone,"objects":scene.object_nodes.size(),"meshes":saved.size(),"retained_bytes":bytes,"covered_cells":covered,"equal":fast==expected})
		scene.free()
		await get_tree().process_frame
	var box:=BoxMesh.new()
	var arrays:=box.surface_get_arrays(0)
	var fallback:=EIFigure.surface_geometry(box,0)
	check(fallback[0]==arrays[Mesh.ARRAY_VERTEX] and fallback[1]==arrays[Mesh.ARRAY_INDEX],"procedural meshes retain fallback geometry")
	FileAccess.open("user://rain-cover-geometry.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"maps":rows},"  "))
	print("RAIN_COVER_GEOMETRY ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
