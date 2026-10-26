extends RefCounted
## A bounded stencil on the already existing quarter-metre mesh. Curvature
## is shared in global terrain coordinates, so sector and tile edges agree.
const SUBDIV := 4
const MAX_POINTS := 65536
const STEPS := [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i(-1,1),Vector2i(1,-1)]
var owner: RefCounted
var terrain: EITerrain
var width: int
var cache := {}
var sources := {}
var free_points := {}
var positions := {}
var normals := {}
var triangles := {}


func _init(builder: RefCounted, input: EITerrain, edges: Array) -> void:
	owner=builder;terrain=input;width=owner.grid_size.x*SUBDIV
	var points := {}
	for record: Array in edges:
		var a: int=record[0];var b: int=record[1]
		if record[2] or absf(terrain.heights[a]-terrain.heights[b])<=owner.MIN_SPAN:continue
		if not owner._snow_insets.has(a) and not owner._snow_insets.has(b):continue
		if owner._snow_anchor(a)==0.0 or owner._snow_anchor(b)==0.0:continue
		if not _sharp(a,b):continue
		if points.size()+128>MAX_POINTS:break
		var qa:=Vector2i(a%owner.grid_size.x,a/owner.grid_size.x)*SUBDIV
		var qb:=Vector2i(b%owner.grid_size.x,b/owner.grid_size.x)*SUBDIV
		for i in SUBDIV+1:
			var q:=qa+(qb-qa)*i/SUBDIV
			var ring:={q:true}
			for depth in 1:
				for p:Vector2i in ring.keys():
					for step:Vector2i in STEPS:
						var neighbour:=p+step
						if _valid(neighbour):ring[neighbour]=true
			for p:Vector2i in ring:points[_key(p)]=p
	for pass_index in 2:
		var next:=positions.duplicate()
		for q:Vector2i in points.values():
			if not _free(q):continue
			var point:=_current(q)
			var shape:=_shape(q)
			if shape.weight<=1e-8 or shape.normal.length_squared()<0.5:continue
			if shape.flat and shape.high>point.y+0.25:continue
			var curvature:Vector3=shape.sum/shape.weight
			var delta:=Vector3(curvature.x,0.0,curvature.z)*0.8
			if curvature.dot(shape.normal)>=-0.00001 or delta.dot(shape.normal)>=-0.00001:continue
			delta=delta.limit_length(minf(0.08,shape.width*0.35))
			var original:Vector3=sources[_key(q)]
			var final:=original+(point+delta-original).limit_length(owner.SNOW_OFFSET)
			final.y=original.y
			if final.distance_squared_to(_base(q))>1e-10:next[_key(q)]=final
		positions=next
	for key:int in positions:
		var q:=Vector2i(key%width,key/width)
		_mark_triangles(q)
	for q:Vector2i in points.values():
		if _free(q):normals[_key(q)]=_shape(q).normal


func _sharp(a:int,b:int)->bool:
	var grid:=Vector2i(a%owner.grid_size.x,a/owner.grid_size.x)
	var first:=Vector3.ZERO
	for y in range(maxi(grid.y-1,0),mini(grid.y,owner.grid_size.y-2)+1):
		for x in range(maxi(grid.x-1,0),mini(grid.x,owner.grid_size.x-2)+1):
			var p:int=y*owner.grid_size.x+x
			for ids:PackedInt32Array in [PackedInt32Array([p,p+1,p+owner.grid_size.x]),PackedInt32Array([p+1,p+owner.grid_size.x+1,p+owner.grid_size.x])]:
				if not a in ids or not b in ids:continue
				var normal:Vector3=(owner._point(terrain,ids[1])-owner._point(terrain,ids[0])).cross(owner._point(terrain,ids[2])-owner._point(terrain,ids[0])).normalized()
				if first!=Vector3.ZERO:return first.dot(normal)<0.85
				first=normal
	return false


func _valid(q:Vector2i)->bool:
	return q.x>=0 and q.y>=0 and q.x<=(owner.grid_size.x-1)*SUBDIV and q.y<=(owner.grid_size.y-1)*SUBDIV


func _key(q:Vector2i)->int:
	return q.y*width+q.x


func _base(q:Vector2i)->Vector3:
	var key:=_key(q)
	if cache.has(key):return cache[key]
	var cell:=Vector2i(q.x/SUBDIV,q.y/SUBDIV).min(owner.grid_size-Vector2i(2,2))
	var f:=Vector2(q)/SUBDIV-Vector2(cell)
	var a:int=cell.y*owner.grid_size.x+cell.x
	var ids:=PackedInt32Array([a,a+1,a+owner.grid_size.x])
	var weights:=Vector3(1.0-f.x-f.y,f.x,f.y)
	if f.x+f.y>1.0:
		ids=PackedInt32Array([a+owner.grid_size.x+1,a+owner.grid_size.x,a+1])
		weights=Vector3(f.x+f.y-1.0,1.0-f.x,1.0-f.y)
	var original:=Vector3.ZERO;var point:=Vector3.ZERO;var mask:=0.0
	for i in 3:
		original+=owner._point(terrain,ids[i])*weights[i]
		point+=owner._presentation_point(terrain,ids[i])*weights[i]
		mask+=owner._snow_anchor(ids[i])*weights[i]
	sources[key]=original;free_points[key]=mask>0.999999
	cache[key]=owner._snow_position(point,weights,owner._snow_controls(ids)) if free_points[key] else original
	return cache[key]


func _free(q:Vector2i)->bool:
	_base(q)
	return free_points[_key(q)]


func _current(q:Vector2i)->Vector3:
	return positions.get(_key(q),_base(q))


func _shape(q:Vector2i)->Dictionary:
	var point:=_current(q)
	var sum:=Vector3.ZERO;var weight:=0.0;var normal:=Vector3.ZERO
	var narrow:=INF;var high:=point.y;var flat:=false
	for y in range(q.y-1,q.y+1):
		for x in range(q.x-1,q.x+1):
			var a:=Vector2i(x,y)
			if not _valid(a) or not _valid(a+Vector2i.ONE):continue
			for row:Array in [[a,a+Vector2i.RIGHT,a+Vector2i.DOWN],[a+Vector2i.RIGHT,a+Vector2i.ONE,a+Vector2i.DOWN]]:
				var at:=row.find(q)
				if at<0:continue
				var u:=_current(row[(at+1)%3])-point;var v:=_current(row[(at+2)%3])-point
				var cross:=u.cross(v);var area:=cross.length()
				if area<1e-8:continue
				normal+=cross/area*atan2(area,u.dot(v))
				var wu:=maxf((u-v).dot(-v)/area,0.0);var wv:=maxf((v-u).dot(-u)/area,0.0)
				sum+=u*wu+v*wv;weight+=wu+wv
				high=maxf(high,point.y+maxf(u.y,v.y));flat=flat or (absf(u.y)<0.0625 and absf(v.y)<0.0625)
				var longest:=maxf(Vector2(u.x,u.z).length(),maxf(Vector2(v.x,v.z).length(),Vector2(u.x-v.x,u.z-v.z).length()))
				narrow=minf(narrow,absf(cross.y)/maxf(longest,0.00001))
	return {"sum":sum,"weight":weight,"normal":normal.normalized(),"width":narrow,"flat":flat,"high":high}


func _mark_triangles(q:Vector2i)->void:
	var last:=Vector2i(q.x/SUBDIV,q.y/SUBDIV)
	var first:=last-Vector2i(int(q.x%SUBDIV==0),int(q.y%SUBDIV==0))
	for y in range(maxi(first.y,0),mini(last.y,owner.grid_size.y-2)+1):
		for x in range(maxi(first.x,0),mini(last.x,owner.grid_size.x-2)+1):
			var f:=Vector2(q)/SUBDIV-Vector2(x,y)
			var base:int=(y*owner.grid_size.x+x)*2
			if f.x+f.y<=1.0:triangles[base]=true
			if f.x+f.y>=1.0:triangles[base+1]=true
