extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func _ready()->void:
 var terrain:=EITerrain.new();terrain.sectors_x=1;terrain.sectors_y=1;terrain.grid_w=33
 terrain.heights.resize(33*33);terrain.heights.fill(0.0)
 var vertices:=PackedVector3Array([Vector3(1,2,-1),Vector3(7,2,-1),Vector3(1,2,-7)])
 var reference:=PackedFloat32Array()
 for indexed in [true,false]:
  var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
  if indexed:arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
  var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  var geometry:=EIFigure.surface_geometry(mesh,0)
  check(geometry[0]==vertices,"procedural positions remain exact")
  check(geometry[1] is PackedInt32Array,"unindexed geometry has an empty index array rather than Nil")
  if not geometry[1] is PackedInt32Array:continue
  check(geometry[1].size()==(3 if indexed else 0),"geometry retains its indexed or sequential topology")
  var roof:=Node3D.new();add_child(roof)
  var mi:=MeshInstance3D.new();mi.mesh=mesh;roof.add_child(mi)
  var cover:=PackedFloat32Array();cover.resize(32*32);cover.fill(SurfaceWeather.UNCOVERED)
  SurfaceWeather.rasterize_cover(roof,terrain,cover)
  check(is_equal_approx(cover[2*32+2],2.0),"sequential triangle shelters the expected terrain cell")
  check(cover[15*32+15]==SurfaceWeather.UNCOVERED,"outside terrain stays exposed")
  if indexed:reference=cover
  else:check(cover==reference,"indexed and unindexed roof maps are identical")
  roof.free()
 terrain.free()
 print("RAIN_COVER_UNINDEXED ",checks," checks ",failures," failures")
 get_tree().quit(1 if failures else 0)
