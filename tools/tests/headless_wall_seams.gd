extends Node
## A map loaded for a world that presents nothing (the simulation worker)
## keeps its authored wall meshes: the seam trimming clips rendering
## triangles only, so the headless load skips it, while a presenting map
## still trims and both keep the authored collision geometry.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func wall_faces(object:Node3D)->PackedVector3Array:
	var faces:=PackedVector3Array()
	for mi:MeshInstance3D in object.find_children("*","MeshInstance3D",true,false):
		if String(mi.get_parent().name).begins_with("wall") and mi.mesh!=null:faces.append_array(mi.mesh.get_faces())
	return faces
func walls(map:EIMapScene)->Dictionary:
	var out:={}
	for object:Node3D in map.object_nodes:
		var info:Dictionary=object.get_meta("ei")
		if String(info.template).begins_with("stwa") or info.template=="stbuho48":out[int(info.nid)]=object
	return out
func _ready()->void:
	var zone:=CampaignMap.load_from(GameData.texts).zone("gz3d1")
	var plain:=EIMapScene.load_map(zone.mpr,"",false,false)
	var shown:=EIMapScene.load_map(zone.mpr,"",false,true)
	var plain_walls:=walls(plain);var shown_walls:=walls(shown)
	check(plain_walls.size()>50 and plain_walls.keys()==shown_walls.keys(),"both maps place the same walls (%d)"%plain_walls.size())
	check(int(plain.stats.wall_seams.get("trimmed",0))==0,"a map that presents nothing trims no seams (%s)"%str(plain.stats.wall_seams))
	check(int(shown.stats.wall_seams.get("trimmed",0))>50,"a presenting map still trims its seams (%s)"%str(shown.stats.wall_seams))
	var authored_kept:=0;var trimmed:=0;var geometry_same:=0
	for nid in plain_walls:
		var object:Node3D=plain_walls[nid];var info:Dictionary=object.get_meta("ei")
		var original:=EIFigure.instantiate(info.template,info.texture,info.complexion,info.parts,false,true)
		original.transform=object.transform
		if wall_faces(original)==wall_faces(object):authored_kept+=1
		if wall_faces(shown_walls[nid])!=wall_faces(original):trimmed+=1
		if EIFigureGeometry.of(original)==EIFigureGeometry.of(object) and EIFigureGeometry.of(original)==EIFigureGeometry.of(shown_walls[nid]):geometry_same+=1
		original.free()
	check(authored_kept==plain_walls.size(),"the headless walls keep their authored meshes (%d of %d)"%[authored_kept,plain_walls.size()])
	check(trimmed>10,"the presenting walls are trimmed (%d)"%trimmed)
	check(geometry_same==plain_walls.size(),"authored collision geometry preserved either way (%d)"%geometry_same)
	# A world that presents nothing loads its map the same way.
	var w:=GameWorld.new();w.zone=zone;w.presentation=false;add_child(w)
	check(w.load_map(zone.mpr,"",false) and int(w.map.stats.wall_seams.get("trimmed",0))==0,"a non-presenting world's map trims no seams")
	var shown_w:=GameWorld.new();shown_w.zone=zone;shown_w.presentation=true;add_child(shown_w)
	check(shown_w.load_map(zone.mpr,"",false) and int(shown_w.map.stats.wall_seams.get("trimmed",0))>50,"a presenting world's map trims them")
	print("HEADLESS_WALL_SEAMS checks=",checks," failures=",failures)
	plain.free();shown.free();w.free();shown_w.free()
	get_tree().quit(1 if failures else 0)
