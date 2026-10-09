extends Node
## Independent coverage/area and terrain-anchor checks across coarse/dense seams.
const Cover=preload("res://src/game/fx/biome_cover.gd")
var checks:=0
var failures:=0
var rows:=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)
func _ready() -> void:
	contact_geometry()
	print("BIOME_COVER_CONTACT checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))

func contact_geometry() -> void:
	var contact=load("res://src/game/fx/biome_cover_contact.gd")
	var field=Cover.new(); field.size=Vector2i(8,8); field.grid_w=9
	for y in 9:
		for x in 9:
			field.heights.append(float(x)*0.015+float(y)*0.04+0.02*sin(x*2+y))
			field.xy.append(Vector2(sin(x+y)*0.08,cos(x-y)*0.06))
	for p in [Vector2(3.12,3.04),Vector2(3.48,3.49),Vector2(3.93,3.94)]:
		for dense in [false,true]:
			var record: Dictionary={"kind":5,"p":p,"scale":0.91,"seed":0.4,"anchor":Vector4(0 if dense else -1,0,0,0)}
			var records: Array[Dictionary]=[record]
			var arrays: Array=contact.build(field,records,Vector2i.ZERO)
			check(not arrays.is_empty(),"sloped contact generated across native seams")
			if arrays.is_empty(): continue
			var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var ids: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var anchors: PackedFloat32Array=arrays[Mesh.ARRAY_CUSTOM0]
			var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
			var valid:=true; var area:=0.0; var radius: float=contact.RADIUS*record.scale
			for i in positions.size():
				valid=valid and positions[i].is_finite() and uv[i].length()<1.0002
				var packed:=int(anchors[i*4]); var cell:=Vector2i(packed/2,int(anchors[i*4+1])); var u:=anchors[i*4+2]; var v:=anchors[i*4+3]
				var corners: Array=[cell+Vector2i.DOWN,cell+Vector2i.RIGHT,cell] if packed%2==0 else [cell+Vector2i.RIGHT,cell+Vector2i.DOWN,cell+Vector2i.ONE]
				var original:=Vector3.ZERO
				for j in 3:
					var at: int=corners[j].y*9+corners[j].x; var xy: Vector2=Vector2(corners[j])+field.xy[at]
					original+=Vector3(xy.x,field.heights[at],-xy.y)*[1.0-u-v,u,v][j]
				valid=valid and positions[i].distance_to(original+Vector3.UP*contact.LIFT)<0.00001
			for i in range(0,ids.size(),3):
				var a:=uv[ids[i]]*radius; var b:=uv[ids[i+1]]*radius; var c:=uv[ids[i+2]]*radius
				area+=absf((b-a).cross(c-a))*0.5
			var expected:=8.0*radius*radius*sin(TAU/16.0)
			check(valid,"contact stays on the original triangle with exact soft-ground anchors")
			check(absf(area-expected)<0.00001,"contact clipping neither overlaps nor leaves holes across seams")
			check(ids.size()/3<200 and positions.size()<500,"contact tessellation stays bounded per stone")
			rows.append({"kind":"contact_geometry","dense":dense,"centre":p,"vertices":positions.size(),"triangles":ids.size()/3,"area":area,"expected_area":expected})
	var empty: Array[Dictionary]=[]
	var empty_contact: Array=contact.build(field,empty,Vector2i.ZERO)
	check(empty_contact.is_empty(),"empty chunks allocate no contact mesh")
	var reference:=weakref(field)
	field=null
	check(reference.get_ref()==null,"contact generation releases its immutable map snapshot")
