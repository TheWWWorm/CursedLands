extends Node
## Exact ordered geometry versus the previous subdivision/clipping routine.
var checks:=0
var failures:=0
var projection_script:Variant=GroundMarkProjection
var kernel:RefCounted
var _verts:=PackedVector3Array()
var _normals:=PackedVector3Array()
var _uvs:=PackedVector2Array()
var _grids:=PackedVector2Array()
var _colors:=PackedColorArray()
var _centre:=Vector2.ZERO
var _across:=Vector2.RIGHT
var _along:=Vector2.DOWN
var _half:=Vector2.ONE
var _bounds:=Rect2(-Vector2.ONE,Vector2.ONE*2)
var _height:=0.0
var _thickness:=2.0
class Probe extends RefCounted:
	var calls:=0
	var rows:=0
	func project(triangles,_centre,_across,_along,_half,_bounds,_height,_thickness) -> Variant:
		calls+=1;rows=triangles.size()
		return null
class CustomProjection extends GroundMarkProjection:
	var calls:=0
	func _init(w:GameWorld)->void:super(w)
	func triangle(p:Array,grid:Array,depth:int,land:bool)->void:
		calls+=1;super.triangle(p,grid,depth,land)

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		if failures<15:printerr("FAIL ",label)

func arrays(projection:GroundMarkProjection)->Array:
	# Packed arrays are shared. Retain values before the next place() clears
	# the current output; otherwise the scalar expected arrays become empty.
	return [projection._verts.duplicate(),projection._normals.duplicate(),projection._uvs.duplicate(),projection._grids.duplicate(),projection._colors.duplicate()]

func oracle(rows:Array)->Array:
	_verts.clear();_normals.clear();_uvs.clear();_grids.clear();_colors.clear()
	for row:Array in rows:triangle(row[0],row[1],row[2],row[3])
	return [_verts,_normals,_uvs,_grids,_colors]

func native(rows:Array)->Variant:
	return kernel.project(rows,_centre,_across,_along,_half,_bounds,_height,_thickness)

func compare(rows:Array,label:String)->void:
	var expected:=oracle(rows)
	var actual:Variant=native(rows)
	check(actual!=null and actual.size()==5,label+" native batch supported")
	if actual==null:return
	for i in 5:check(actual[i]==expected[i],label+" exact ordered channel "+str(i))
	check(actual[0].size()%3==0,label+" complete triangles")

func compare_place(projection:GroundMarkProjection,mark:GroundMarks.Mark,label:String)->void:
	projection_script._kernel=null;projection.place(mark,true)
	var expected:=arrays(projection)
	projection_script._kernel=kernel;projection.place(mark,true)
	for i in 5:check(arrays(projection)[i]==expected[i],label+" exact live geometry "+str(i))

func mark(world:GameWorld,marks:GroundMarks,foot:=true)->GroundMarks.Mark:
	var m:=GroundMarks.Mark.new();m.foot=foot;m.x=64.2;m.y=61.8;m.a=.22;m.b=.34
	m.decal=Decal.new();world.add_child(m.decal);marks._place(m)
	return m

func finish()->void:
	print("GROUND_MARK_PROJECTION_NATIVE checks=",checks," failures=",failures)
	get_tree().quit(int(failures>0))

func _ready()->void:
	check(ClassDB.class_exists("GroundMarkProjectionKernel"),"native ground mark projector is available")
	if failures:finish();return
	kernel=projection_script._kernel
	check(kernel!=null,"production projector uses native geometry")
	if failures:finish();return
	compare([],"empty batch")
	var p:=[Vector3.ZERO,Vector3(1,0,0),Vector3(0,0,-1)]
	var g:=[Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN]
	_centre=Vector2(.5,.5);_half=Vector2(.5,.5);_bounds=Rect2(Vector2.ZERO,Vector2.ONE)
	var simple:Variant=native([[p,g,0,true]])
	check(simple[0]==PackedVector3Array(p),"unclipped triangle preserves vertex order")
	check(simple[1]==PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP]),"upward normals")
	check(simple[2]==PackedVector2Array(g),"unclipped UV corners")
	compare([[p,g,0,false],[p,g,0,true]],"floor and land retain source/color order")
	for depth in [0,1,2,4]:
		compare([[p,g,depth,true]],"ordered subdivision depth "+str(depth))
	for height in [-1.000001,-1.0,-.999999,0.0,.999999,1.0,1.000001]:
		_height=height;compare([[p,g,0,true]],"vertical clipping boundary "+str(height))
	_height=0.0
	for offset in [-2.0,-1.0,-.99999,0.0,.99999,1.0,2.0]:
		_centre=Vector2(offset,.5);_bounds=Rect2(_centre-_half,_half*2)
		compare([[p,g,0,true]],"horizontal clipping boundary "+str(offset))
	compare([[[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO],g,4,true]],"degenerate triangle")
	compare([[[Vector3.ZERO,Vector3.UP,Vector3(0,0,-1)],g,4,false]],"vertical receiver excluded")
	var rng:=RandomNumberGenerator.new();rng.seed=20261025
	for frame in 144:
		_centre=Vector2(rng.randf_range(-2,2),rng.randf_range(-2,2))
		var angle:=rng.randf_range(-PI,PI)
		_across=Vector2(cos(angle),sin(angle));_along=Vector2(-sin(angle),cos(angle))
		_half=Vector2(rng.randf_range(.03,1.4),rng.randf_range(.03,1.4))
		var radius:=_across.abs()*_half.x+_along.abs()*_half.y
		_bounds=Rect2(_centre-radius,radius*2)
		_height=rng.randf_range(-.5,.5);_thickness=[.5,2.0,4.0][frame%3]
		var rows:=[]
		for triangle_index in 3:
			var points:=[];var grid:=[]
			for i in 3:
				points.append(Vector3(_centre.x+rng.randf_range(-2,2),rng.randf_range(-1.5,1.5),-_centre.y+rng.randf_range(-2,2)))
				grid.append(Vector2(rng.randf_range(0,64),rng.randf_range(0,64)))
			rows.append([points,grid,[0,1,2,4][frame%4],triangle_index%2==0])
		compare(rows,"rotated clipped land/floor "+str(frame))
	_centre=Vector2.ZERO;_across=Vector2.RIGHT;_along=Vector2.DOWN;_half=Vector2.ONE;_bounds=Rect2(-Vector2.ONE,Vector2.ONE*2);_height=0.0;_thickness=2.0
	for invalid in [[null],[[p,g,5,true]],[[p.slice(0,2),g,0,true]],[[p,[Vector2.ZERO],0,true]],[[p,g,0,1]],[[[Vector3.INF,Vector3.ZERO,Vector3.ONE],g,0,true]]]:
		check(native(invalid)==null,"unsupported batch declines "+str(invalid))
	_half=Vector2.ZERO;check(native([[p,g,0,true]])==null,"zero extent declines");_half=Vector2.ONE
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true);Engine.time_scale=0.0;Gfx.ensure_globals()
	var world:=GameWorld.new();add_child(world);world.set_process(false);world.set_physics_process(false)
	var terrain:=EITerrain.load_map("basegipat");world.add_child(terrain);world.terrain=terrain;terrain.set_process(false)
	var marks:=GroundMarks.of(world);marks.set_process(false)
	var receiver:=MeshInstance3D.new();receiver.mesh=PlaneMesh.new();receiver.layers=EITerrain.DECAL_LAYER;world.add_child(receiver)
	receiver.position=Vector3(64,terrain.ground_at(64,62)+.15,-62);receiver.rotation.z=.1
	var projection:=GroundMarkProjection.new(world)
	marks._projection=projection
	var m:=mark(world,marks);projection.create(m)
	check(not projection._verts.is_empty(),"authored village generates mark geometry")
	for soft in [0,1]:
		GameData.options.gfx_soft_ground=soft
		for i in 12:
			m.x=64.0+sin(i*.7)*.4;m.y=62.0+cos(i*.8)*.4;m.angle=i*.21
			m.a=.02+i*.025;m.b=.04+i*.04;marks._place(m)
			compare_place(projection,m,"authored terrain soft="+str(soft)+" pose="+str(i))
	for shown in [false,true]:
		receiver.visible=shown;receiver.rotation=Vector3(.2,.4,-.15)
		compare_place(projection,m,"live receiver transform and visibility "+str(shown))
	receiver.mesh=PlaneMesh.new();(receiver.mesh as PlaneMesh).size=Vector2(1.5,1.0)
	compare_place(projection,m,"replacement receiver geometry")
	var at:=62*terrain.grid_w+64;var old_height:=terrain.heights[at];var old_xy:=terrain.land_xy[at]
	terrain.heights[at]+=.3;terrain.land_xy[at]+=Vector2(.15,-.1)
	compare_place(projection,m,"live terrain vertices")
	terrain.heights[at]=old_height;terrain.land_xy[at]=old_xy
	m.foot=false;m.grow=.01;m.grow_left=45
	compare_place(projection,m,"animated blood conservative patch")
	var retained:=m.projection.mesh
	m.angle+=.2;marks._place(m)
	check(m.projection.mesh==retained,"animated blood still reuses its conservative geometry")
	m.foot=true;projection_script._kernel=null;projection.place(m,true);var expected:=arrays(projection)
	var probe:=Probe.new();projection_script._kernel=probe;projection.place(m,true)
	check(probe.calls==1 and probe.rows>1,"production performs one batch for multiple source triangles")
	for i in 5:check(arrays(projection)[i]==expected[i],"declined batch keeps complete scalar channel "+str(i))
	projection_script._kernel=null;projection.place(m,true)
	for i in 5:check(arrays(projection)[i]==expected[i],"older library keeps scalar channel "+str(i))
	projection_script._kernel=probe
	var custom:=CustomProjection.new(world);custom.create(m)
	check(custom.calls>0 and probe.calls==1,"derived projection preserves triangle hooks without batching")
	for i in 5:check(arrays(custom)[i]==expected[i],"derived projection exact channel "+str(i))
	projection_script._kernel=kernel
	var timings:=[]
	for enabled in [false,true,true,false]:
		projection_script._kernel=kernel if enabled else null
		var started:=Time.get_ticks_usec()
		for i in 60:projection.place(m,true)
		timings.append({"native":enabled,"marks":60,"vertices":projection._verts.size(),"usec":Time.get_ticks_usec()-started})
	print("GROUND_MARK_PROJECTION_NATIVE_TIMING ",JSON.stringify(timings))
	projection_script._kernel=kernel;world.free();finish()

func triangle(p: Array, grid: Array, depth: int, land: bool) -> void:
	var rect := Rect2(Vector2(p[0].x,-p[0].z),Vector2.ZERO)
	for v: Vector3 in p: rect=rect.expand(Vector2(v.x,-v.z))
	if not rect.intersects(_bounds): return
	if minf(p[0].y,minf(p[1].y,p[2].y)) > _height+_thickness*.5 or maxf(p[0].y,maxf(p[1].y,p[2].y)) < _height-_thickness*.5: return
	var normal: Vector3 = (p[2]-p[0]).cross(p[1]-p[0]).normalized()
	if absf(normal.y)<0.01: return
	if normal.y<0.0: normal=-normal
	if depth>0:
		var ab: Vector3=(p[0]+p[1])*.5; var bc: Vector3=(p[1]+p[2])*.5; var ca: Vector3=(p[2]+p[0])*.5
		var ga: Vector2=(grid[0]+grid[1])*.5; var gb: Vector2=(grid[1]+grid[2])*.5; var gc: Vector2=(grid[2]+grid[0])*.5
		triangle([p[0],ab,ca],[grid[0],ga,gc],depth-1,land)
		triangle([ab,p[1],bc],[ga,grid[1],gb],depth-1,land)
		triangle([ca,bc,p[2]],[gc,gb,grid[2]],depth-1,land)
		triangle([ab,bc,ca],[ga,gb,gc],depth-1,land)
		return
	var poly := []
	for i in 3:
		var delta := Vector2(p[i].x,-p[i].z)-_centre
		var uv := Vector2(delta.dot(_across),delta.dot(_along))/_half*.5+Vector2(.5,.5)
		poly.append([p[i],grid[i],Vector3(uv.x,uv.y,(p[i].y-_height)/_thickness+.5)])
	for axis in 3:
		for edge in [0.0,1.0]:
			var clipped := []
			if poly.is_empty(): return
			var previous: Array=poly[-1]
			for current: Array in poly:
				var a: float=previous[2][axis]; var b: float=current[2][axis]
				var inside_a: bool=a>=edge if edge==0.0 else a<=edge
				var inside_b: bool=b>=edge if edge==0.0 else b<=edge
				if inside_a!=inside_b:
					var t: float=(edge-a)/(b-a)
					clipped.append([previous[0].lerp(current[0],t),previous[1].lerp(current[1],t),previous[2].lerp(current[2],t)])
				if inside_b: clipped.append(current)
				previous=current
			poly=clipped
	for i in range(1,poly.size()-1):
		for vertex: Array in [poly[0],poly[i],poly[i+1]]:
			_verts.append(vertex[0]);_grids.append(vertex[1]);_uvs.append(Vector2(vertex[2].x,vertex[2].y));_normals.append(normal)
			_colors.append(Color(1 if land else 0,0,0,1))
