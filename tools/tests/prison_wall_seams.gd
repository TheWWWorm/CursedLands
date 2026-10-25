extends Node
## Independently intersect rendered triangles from the real prison and its
## untouched authored meshes. Collision metadata must remain identical.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func area(p:PackedVector2Array)->float:
	var sum:=0.0
	for i in p.size():sum+=p[i].cross(p[(i+1)%p.size()])
	return absf(sum)*0.5
func collect(object:Node3D,planes:Dictionary)->void:
	for mi:MeshInstance3D in object.find_children("*","MeshInstance3D",true,false):
		if not String(mi.get_parent().name).begins_with("wall") or mi.mesh==null:continue
		var xf:=mi.transform;var parent:=mi.get_parent_node_3d()
		while parent!=object:xf=parent.transform*xf;parent=parent.get_parent_node_3d()
		xf=object.transform*xf
		var v:=mi.mesh.get_faces()
		for i in range(0,v.size(),3):
			var t:=[xf*v[i],xf*v[i+1],xf*v[i+2]]
			var n:Vector3=(t[1]-t[0]).cross(t[2]-t[0]).normalized()
			var axis:=n.abs().max_axis_index()
			if absf(n[axis])<0.999999:continue
			var key:=Vector3i(axis,int(signf(n[axis])),roundi(t[0][axis]*10000))
			var p:=PackedVector2Array()
			for point:Vector3 in t:p.append(Vector2(point[(axis+1)%3],point[(axis+2)%3]))
			if area(p)<0.000001:continue
			if not planes.has(key):planes[key]=[]
			planes[key].append(p)
func overlaps(planes:Dictionary)->float:
	var total:=0.0
	for faces:Array in planes.values():
		for i in faces.size():
			for j in i:
				for p:PackedVector2Array in Geometry2D.intersect_polygons(faces[i],faces[j]):total+=area(p)
	return total
func _ready()->void:
	var zone:=CampaignMap.load_from(GameData.texts).zone("gz3d1")
	var map:=EIMapScene.load_map(zone.mpr,"",false)
	var before:={};var after:={};var counts:={}
	for object:Node3D in map.object_nodes:
		var info:Dictionary=object.get_meta("ei")
		if not (String(info.template).begins_with("stwa") or info.template=="stbuho48"):continue
		counts[info.template]=counts.get(info.template,0)+1
		var original:=EIFigure.instantiate(info.template,info.texture,info.complexion,info.parts,false,true)
		original.transform=object.transform
		collect(original,before);collect(object,after)
		check(EIFigureGeometry.of(original)==EIFigureGeometry.of(object),"authored collision geometry preserved "+str(info.nid))
		original.free()
	check(int(counts.get("stwa10",0))>50 and int(counts.get("stbuho48",0))>5,"actual tall walls and cell partitions covered")
	var old_overlap:=overlaps(before);var new_overlap:=overlaps(after)
	print("PRISON_OVERLAP before=",old_overlap," after=",new_overlap)
	check(old_overlap>1.0,"authored fixture reproduces substantial coplanar overlap")
	check(new_overlap<0.01,"no duplicate visible wall area remains")
	# Subtract the output's union from every authored triangle. A trim must
	# never open a hole, even at adjoining wall corners or low partitions.
	for plane:Vector3i in before:
		var missing:=0.0
		for face:PackedVector2Array in before[plane]:
			var rest:Array[PackedVector2Array]=[face]
			for cut:PackedVector2Array in after.get(plane,[]):
				var next:Array[PackedVector2Array]=[]
				for p:PackedVector2Array in rest:next.append_array(Geometry2D.clip_polygons(p,cut))
				rest=next
				if rest.is_empty():break
			for p:PackedVector2Array in rest:missing+=area(p)
		check(missing<0.01,"wall coverage preserved on plane "+str(plane))
	map.free()
	print("PRISON_WALL_SEAMS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
