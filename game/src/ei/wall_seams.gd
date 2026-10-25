class_name EIWallSeams
extends RefCounted
## Authored masonry segments overlap along a coplanar strip. Give that strip
## to the first placed face, clipping only its duplicate rendering triangles.
## Original part metadata/boxes remain the authority for collision and scripts.
const EPS := 0.0001

static func apply(objects: Array[Node3D]) -> Dictionary:
	var planes := {}
	var stats := {"faces":0,"trimmed":0}
	for object:Node3D in objects:
		var info:Dictionary=object.get_meta("ei",{})
		var template:=String(info.get("template",""))
		if info.get("kind","")=="LEVER" or not (template.begins_with("stwa") or template=="stbuho48"):continue
		for mi:MeshInstance3D in object.find_children("*","MeshInstance3D",true,false):
			if not String(mi.get_parent().name).begins_with("wall") or not mi.mesh is ArrayMesh:continue
			var changed:=false
			var output:=ArrayMesh.new()
			for surface in mi.mesh.get_surface_count():
				var arrays:=mi.mesh.surface_get_arrays(surface)
				var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					for i in vertices.size():indices.append(i)
				var out:=[];out.resize(Mesh.ARRAY_MAX)
				var verts:=PackedVector3Array();var normals:=PackedVector3Array();var uvs:=PackedVector2Array()
				for i in range(0,indices.size(),3):
					var ids:=[indices[i],indices[i+1],indices[i+2]]
					var world:=[object.transform * local_transform(mi,object) * vertices[ids[0]],object.transform * local_transform(mi,object) * vertices[ids[1]],object.transform * local_transform(mi,object) * vertices[ids[2]]]
					var n:Vector3=(world[1]-world[0]).cross(world[2]-world[0]).normalized()
					var axis:=n.abs().max_axis_index()
					# These authored box walls use cardinal planes. Other, sloping masonry
					# keeps its original triangles instead of approximating a plane.
					var cardinal:=absf(n[axis])>0.999999
					var projected:=PackedVector2Array()
					for v:Vector3 in world:projected.append(project(v,axis))
					var pieces:Array[PackedVector2Array]=[projected]
					var key:=Vector3i(axis,int(signf(n[axis])),roundi(world[0][axis]/EPS))
					if cardinal:
						stats.faces+=1
						for prior:PackedVector2Array in planes.get(key,[]):
							var next:Array[PackedVector2Array]=[]
							for polygon:PackedVector2Array in pieces:next.append_array(subtract(polygon,prior))
							pieces=next
							if pieces.is_empty():break
						if pieces.size()!=1 or pieces[0]!=projected:changed=true;stats.trimmed+=1
						if not planes.has(key):planes[key]=[]
						planes[key].append(projected)
					for polygon:PackedVector2Array in pieces:
						for k in range(1,polygon.size()-1):
							for point:Vector2 in [polygon[0],polygon[k],polygon[k+1]]:
								var weights:=barycentric(point,projected)
								verts.append(vertices[ids[0]]*weights.x+vertices[ids[1]]*weights.y+vertices[ids[2]]*weights.z)
								var ns:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
								normals.append((ns[ids[0]]*weights.x+ns[ids[1]]*weights.y+ns[ids[2]]*weights.z).normalized())
								var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
								uvs.append(uv[ids[0]]*weights.x+uv[ids[1]]*weights.y+uv[ids[2]]*weights.z)
				if verts.is_empty():continue
				out[Mesh.ARRAY_VERTEX]=verts;out[Mesh.ARRAY_NORMAL]=normals;out[Mesh.ARRAY_TEX_UV]=uvs
				output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,out)
				output.surface_set_material(output.get_surface_count()-1,mi.mesh.surface_get_material(surface))
			if changed:
				mi.mesh=output if output.get_surface_count()>0 else null
				mi.set_meta("coplanar_wall_trimmed",true)
	return stats

static func local_transform(node:Node3D,root:Node3D)->Transform3D:
	var result:=node.transform
	var parent:=node.get_parent_node_3d()
	while parent and parent!=root:
		result=parent.transform*result;parent=parent.get_parent_node_3d()
	return result

static func project(v:Vector3,axis:int)->Vector2:
	return Vector2(v[(axis+1)%3],v[(axis+2)%3])

static func barycentric(p:Vector2,t:PackedVector2Array)->Vector3:
	var a:=t[1]-t[0];var b:=t[2]-t[0];var q:=p-t[0]
	var det:=a.cross(b)
	if absf(det)<0.0000001:return Vector3(1,0,0)
	var y:=q.cross(b)/det;var z:=a.cross(q)/det
	return Vector3(1-y-z,y,z)

## Subtract a convex triangle, emitting disjoint convex pieces. Keeping the
## outside half at each edge also handles an enclosed cutout without holes.
static func subtract(subject:PackedVector2Array,clip:PackedVector2Array)->Array[PackedVector2Array]:
	if separated(subject,clip) or separated(clip,subject):return [subject]
	var out:Array[PackedVector2Array]=[]
	var remain:=subject
	var orientation:=signf((clip[1]-clip[0]).cross(clip[2]-clip[0]))
	for i in 3:
		if remain.size()<3:break
		var a:=clip[i];var edge:=clip[(i+1)%3]-a
		var inside:=PackedVector2Array();var outside:=PackedVector2Array()
		for j in remain.size():
			var p:=remain[j];var q:=remain[(j+1)%remain.size()]
			var dp:=edge.cross(p-a)*orientation;var dq:=edge.cross(q-a)*orientation
			if dp>=0:inside.append(p)
			if dp<=0:outside.append(p)
			if (dp>0 and dq<0) or (dp<0 and dq>0):
				var hit:=p.lerp(q,dp/(dp-dq));inside.append(hit);outside.append(hit)
		if area(outside)>0.0000001:out.append(outside)
		remain=inside
	return out

static func area(polygon:PackedVector2Array)->float:
	var total:=0.0
	for i in polygon.size():total+=polygon[i].cross(polygon[(i+1)%polygon.size()])
	return absf(total)*0.5

static func separated(a:PackedVector2Array,b:PackedVector2Array)->bool:
	var orientation:=signf((b[1]-b[0]).cross(b[2]-b[0]))
	for i in b.size():
		var edge:=b[(i+1)%b.size()]-b[i]
		var maximum:float=-INF
		for p:Vector2 in a:maximum=maxf(maximum,edge.cross(p-b[i])*orientation)
		if maximum<=0.0000001:return true
	return false
