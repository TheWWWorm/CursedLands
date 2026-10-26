extends "res://tools/tests/terrain_snow_rounding.gd"
## The actual Ingos wall is admitted already. Its long diagonal ridge is the
## counterexample to preserving every cosmetic anchor while curving its cap.

func sector_source(terrain:EITerrain,key:Vector2i)->Array:
	var positions:=PackedVector3Array();var normals:=PackedVector3Array();var codes:=PackedInt32Array()
	for y in 33:
		for x in 33:
			var grid:=key*32+Vector2i(x,y);var i:=grid.y*terrain.grid_w+grid.x
			positions.append(Vector3(grid.x+terrain.land_xy[i].x,terrain.heights[i],-grid.y-terrain.land_xy[i].y))
			normals.append(terrain.land_n[i])
	for y in 16:
		for x in 16:codes.append(terrain.land_tile[(key.y*16+y)*terrain.sectors_x*16+key.x*16+x])
	var source:=terrain._mesh_arrays([positions,normals],codes,PackedInt32Array(),key*16)
	for i in source[Mesh.ARRAY_VERTEX].size():
		var tile:=roundi(source[Mesh.ARRAY_TEX_UV2][i].y)
		source[Mesh.ARRAY_TEX_UV][i]=Vector2(tile%(terrain.sectors_x*16),tile/(terrain.sectors_x*16))*2+Vector2(i%3,(i%9)/3)
	return source


func ridge_angles(arrays:Array)->Dictionary:
	var positions:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var edges:={};var maximum:=0.0;var total:=0.0;var count:=0
	for i in range(0,indices.size(),3):
		var a:=indices[i];var b:=indices[i+1];var c:=indices[i+2]
		var normal:Vector3=(positions[c]-positions[a]).cross(positions[b]-positions[a]).normalized()
		for k in 3:
			var p:=uv[indices[i+k]];var q:=uv[indices[i+(k+1)%3]]
			if p.x+p.y!=359.0 or q.x+q.y!=359.0 or minf(p.x,q.x)<157.0 or maxf(p.x,q.x)>158.0:continue
			var key:=Vector4(p.x,p.y,q.x,q.y) if p.x<q.x else Vector4(q.x,q.y,p.x,p.y)
			if edges.has(key):
				var angle:=rad_to_deg(acos(clampf(normal.dot(edges[key]),-1.0,1.0)))
				maximum=maxf(maximum,angle);total+=angle;count+=1
			else:edges[key]=normal
	return {"count":count,"max":maximum,"mean":total/maxi(count,1)}


func actual_safety(source:Array,result:Array)->void:
	var original:={};var shared:={};var bad:=0;var seams:=0;var folded:=0;var offset:=0.0
	for i in source[Mesh.ARRAY_VERTEX].size():original[source[Mesh.ARRAY_TEX_UV][i]]=source[Mesh.ARRAY_VERTEX][i]
	var positions:PackedVector3Array=result[Mesh.ARRAY_VERTEX]
	var uv:PackedVector2Array=result[Mesh.ARRAY_TEX_UV]
	var ids:PackedInt32Array=result[Mesh.ARRAY_INDEX]
	for index in ids:
		var p:=positions[index];var grid:=uv[index]
		var cell:=grid.floor().clamp(Vector2(128,192),Vector2(159,223));var f:=grid-cell
		var expected:Vector3
		if f.x+f.y<=1.0:expected=original[cell]*(1.0-f.x-f.y)+original[cell+Vector2.RIGHT]*f.x+original[cell+Vector2.DOWN]*f.y
		else:expected=original[cell+Vector2.ONE]*(f.x+f.y-1.0)+original[cell+Vector2.RIGHT]*(1.0-f.y)+original[cell+Vector2.DOWN]*(1.0-f.x)
		offset=maxf(offset,p.distance_to(expected))
		if not p.is_finite() or absf(p.y-expected.y)>0.00001:bad+=1
		if shared.has(grid) and p.distance_to(shared[grid])>0.00001:seams+=1
		shared[grid]=p
	for i in range(0,ids.size(),3):
		var a:=positions[ids[i]];var b:=positions[ids[i+1]];var c:=positions[ids[i+2]]
		var grid:Vector2=(uv[ids[i]]+uv[ids[i+1]]+uv[ids[i+2]])/3.0
		var cell:=grid.floor().clamp(Vector2(128,192),Vector2(159,223));var f:=grid-cell
		var pa:Vector3=original[cell];var pb:Vector3=original[cell+Vector2.RIGHT];var pc:Vector3=original[cell+Vector2.DOWN]
		if f.x+f.y>1.0:pa=original[cell+Vector2.ONE];var swap:=pb;pb=pc;pc=swap
		if (c-a).cross(b-a).length_squared()<1e-14 or (c-a).cross(b-a).dot((pb-pa).cross(pc-pa))<=0.0:folded+=1
	check(bad==0 and offset<=0.30003,"actual hill vertices retain heights and the 30 cm presentation bound")
	check(seams==0 and folded==0,"actual hill faces retain continuous edges, nonzero area and winding")
	check(crossings(result)==0,"actual hill contours do not cross after rounding")
	check(ids.size()<source[Mesh.ARRAY_INDEX].size()*4,"actual hill rounding retains a local triangle budget")
	print("SNOW_BEVEL_SAFETY ",JSON.stringify({"bad":bad,"seams":seams,"folded":folded,"offset":offset}))


func sector_seam(first:Array,second:Array)->void:
	var shared:={};var checked:=0;var mismatches:=0
	for index in first[Mesh.ARRAY_INDEX]:
		var grid:Vector2=first[Mesh.ARRAY_TEX_UV][index]
		if grid.x==160.0:shared[grid]=[first[Mesh.ARRAY_VERTEX][index],first[Mesh.ARRAY_NORMAL][index].normalized()]
	for index in second[Mesh.ARRAY_INDEX]:
		var grid:Vector2=second[Mesh.ARRAY_TEX_UV][index]
		if not shared.has(grid):continue
		checked+=1
		if second[Mesh.ARRAY_VERTEX][index].distance_to(shared[grid][0])>0.00001 or second[Mesh.ARRAY_NORMAL][index].normalized().distance_to(shared[grid][1])>0.00001:mismatches+=1
	check(checked>50 and mismatches==0,"adjacent real sectors share bevel positions and normals")


func _ready()->void:
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	Gfx.ensure_globals()
	var terrain:=EITerrain.load_map("zone12")
	check(terrain!=null,"original Ingos terrain loads for the visible wall")
	if terrain==null:get_tree().quit(1);return
	var heights:=terrain.heights.duplicate();var xy:=terrain.land_xy.duplicate();var normals:=terrain.land_n.duplicate()
	var source:=sector_source(terrain,Vector2i(4,6));var original:=source.duplicate(true)
	var field:=Field.new(terrain)
	var start:=Time.get_ticks_usec()
	var builder:=geometry_for(terrain,field)
	var build_us:=Time.get_ticks_usec()-start
	builder.prepare(source)
	var result:Array=builder.arrays(source)
	var authored:=ridge_angles(source);var refined:=ridge_angles(result)
	print("SNOW_BEVEL_ANGLES ",JSON.stringify({"authored":authored,"refined":refined}))
	var anchor:=Vector2(158,201);var before:=Vector3.ZERO;var after:=Vector3.ZERO
	for i in source[Mesh.ARRAY_VERTEX].size():
		if source[Mesh.ARRAY_TEX_UV][i]==anchor:before=source[Mesh.ARRAY_VERTEX][i]
	for i in result[Mesh.ARRAY_INDEX]:
		if result[Mesh.ARRAY_TEX_UV][i]==anchor:after=result[Mesh.ARRAY_VERTEX][i]
	check(before.distance_to(after)>0.08 and before.distance_to(after)<=0.3,"the visible convex ridge gains a bounded presentation inset")
	check(after.y==before.y,"the visible ridge retains its authored height")
	check(refined.count>=4,"the visible ridge has shared curved samples")
	check(refined.mean<35.0 and refined.max<55.0,"the actual long ridge spreads its sharp angle across a bevel")
	check(builder.get("_snow_fine")==null or builder._snow_fine.size()<=65536,"the shared bevel stencil has a bounded vertex cache")
	actual_safety(source,result)
	var adjacent:=sector_source(terrain,Vector2i(5,6));builder.prepare(adjacent)
	sector_seam(result,builder.arrays(adjacent))
	check(source==original and terrain.heights==heights and terrain.land_xy==xy and terrain.land_n==normals,"bevel leaves source geometry, collision heights and lighting input untouched")
	print("SNOW_BEVEL_ANCHOR ",JSON.stringify({"before":before,"after":after,"inset":before.distance_to(after)}))
	print("SNOW_BEVEL_SETUP ",JSON.stringify({"build_us":build_us,"quarter_points":builder.get("_snow_fine").size() if builder.get("_snow_fine")!=null else 0,"normal_points":builder.get("_snow_fine_normals").size() if builder.get("_snow_fine_normals")!=null else 0,"sector_triangles":result[Mesh.ARRAY_INDEX].size()/3}))
	terrain.free();TexUpscale.shutdown()
	print("SNOW_BEVEL ",checks," checks ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
