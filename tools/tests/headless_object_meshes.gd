extends Node
## A map loaded for a world that presents nothing (the simulation worker)
## places its objects as part nodes with their authored geometry but without
## mesh instances or materials; a presenting map keeps them, and both give
## the same collision geometry, part hierarchy, lever morph nodes and
## navigation footprints.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func meshes(o:Node3D)->int:
	return o.find_children("*","MeshInstance3D",true,false).size()
func parts(o:Node3D)->PackedStringArray:
	var out:=PackedStringArray()
	for n:Node in o.find_children("*","Node3D",true,false):
		if not n is MeshInstance3D:out.append(String(n.name))
	out.sort();return out
func morph_nodes(o:Node3D)->int:
	var n:=0
	for c:Node in o.find_children("*","Node3D",true,false):
		if c.has_meta("p0") and c.has_meta("p1"):n+=1
	return n
func by_nid(map:EIMapScene)->Dictionary:
	var out:={}
	for o:Node3D in map.object_nodes:out[int(o.get_meta("ei").nid)]=o
	return out
func _ready()->void:
	var zone:=CampaignMap.load_from(GameData.texts).zone("gz1g")
	var plain:=EIMapScene.load_map(zone.mpr,"",false,false)
	var shown:=EIMapScene.load_map(zone.mpr,"",false,true)
	var a:=by_nid(plain);var b:=by_nid(shown)
	check(a.size()>500 and a.keys()==b.keys(),"both maps place the same objects (%d)"%a.size())
	var plain_meshes:=0;var shown_meshes:=0;var same_geometry:=0;var same_parts:=0;var levers:=0;var same_morph:=0
	for nid in a:
		plain_meshes+=meshes(a[nid]);shown_meshes+=meshes(b[nid])
		if EIFigureGeometry.of(a[nid])==EIFigureGeometry.of(b[nid]):same_geometry+=1
		if parts(a[nid])==parts(b[nid]):same_parts+=1
		if a[nid].get_meta("ei").kind=="LEVER":
			levers+=1
			if morph_nodes(a[nid])>0 and morph_nodes(a[nid])==morph_nodes(b[nid]):same_morph+=1
	check(plain_meshes==0,"a map that presents nothing has no mesh instances (%d)"%plain_meshes)
	check(shown_meshes>a.size(),"a presenting map keeps its mesh instances (%d)"%shown_meshes)
	check(same_geometry==a.size(),"authored collision geometry is the same either way (%d of %d)"%[same_geometry,a.size()])
	check(same_parts==a.size(),"the part hierarchy is the same either way (%d of %d)"%[same_parts,a.size()])
	check(levers==0 or same_morph==levers,"lever morph nodes are kept without meshes (%d of %d levers)"%[same_morph,levers])
	# Worlds: the non-presenting one navigates and operates its levers the same.
	var w:=GameWorld.new();w.zone=zone;w.presentation=false;add_child(w)
	var shown_w:=GameWorld.new();shown_w.zone=zone;shown_w.presentation=true;add_child(shown_w)
	check(w.load_map(zone.mpr,"",false) and shown_w.load_map(zone.mpr,"",false),"both worlds load the map")
	var fp_a:={};var fp_b:={}
	for key in w.nav._fp:fp_a[key]=[w.nav._fp[key].get("faces",[]).size(),w.nav._fp[key].get("spans",{}).size(),w.nav._fp[key].get("floors",{}).size()]
	for key in shown_w.nav._fp:fp_b[key]=[shown_w.nav._fp[key].get("faces",[]).size(),shown_w.nav._fp[key].get("spans",{}).size(),shown_w.nav._fp[key].get("floors",{}).size()]
	check(fp_a.size()>500 and fp_a==fp_b,"the navigation footprints are the same either way (%d)"%fp_a.size())
	var morph_a:=0;var morph_b:=0
	for nid in w.lever_sys._morph:morph_a+=w.lever_sys._morph[nid].nodes.size()
	for nid in shown_w.lever_sys._morph:morph_b+=shown_w.lever_sys._morph[nid].nodes.size()
	check(morph_a==morph_b,"the lever systems track the same morph nodes (%d)"%morph_a)
	var no_meshes:=0
	for o:Node3D in w.map.object_nodes:no_meshes+=meshes(o)
	check(no_meshes==0,"the non-presenting world's objects carry no mesh instances")
	print("HEADLESS_OBJECT_MESHES checks=",checks," failures=",failures)
	plain.free();shown.free();w.free();shown_w.free()
	get_tree().quit(1 if failures else 0)
