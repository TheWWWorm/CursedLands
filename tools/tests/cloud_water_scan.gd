extends "res://src/game/fx/water_reflection.gd"
var rows:=[]
var checks:=0
var failures:=0
func _ready()->void: run.call_deferred()
func stats(a:Array)->Dictionary:
 a.sort();var total:=0.0
 for v:float in a:total+=v
 return {"mean":total/a.size(),"p95":a[int(a.size()*.95)],"max":a.back()}
func run()->void:
 for option:Array in GameData.OPTIONS:
  if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
 GameData.options.auto_graphics=0
 var cam:=Camera3D.new();get_parent().add_child(cam)
 for map:String in ["zone1","zone12"]:
  terrain=EITerrain.load_map(map)
  if not terrain:printerr("FAIL map ",map);get_tree().quit(1);return
  get_parent().add_child(terrain);terrain.set_process(false)
  prepare_water_cells(terrain)
  var old_us:=[];var new_us:=[];var peak:=0.0
  for i in 80:
   var size:=terrain.size_ei()
   var at:=Vector2(fposmod(i*37.71,size.x+80.0)-40.0,fposmod(i*71.31,size.y+80.0)-40.0)
   var h:=terrain.height_at(at.x,at.y)
   cam.global_position=Vector3(at.x,h+15,-at.y)
   cam.rotation=Vector3(-.7,float(i)*.37,0)
   var start:=Time.get_ticks_usec();var a:=reference(cam);old_us.append(Time.get_ticks_usec()-start)
   start=Time.get_ticks_usec();var b:=_select_plane(cam);new_us.append(Time.get_ticks_usec()-start)
   checks+=1
   if is_finite(a)!=is_finite(b) or (is_finite(a) and absf(a-b)>.0001):failures+=1;printerr("FAIL scan ",map," ",i," ",a," ",b)
   if is_finite(a) and is_finite(b):peak=maxf(peak,absf(a-b))
   if i==39:
    for m in terrain.materials.size():terrain.set_water_offset(m,.23)
  rows.append({"map":map,"reference_us":stats(old_us),"indexed_us":stats(new_us),"max_height_error":peak,"buckets":terrain._reflection_water_cells.size()})
  print("WATER_SCAN ",JSON.stringify(rows.back()))
  terrain.free()
 cam.free();TexUpscale.shutdown()
 FileAccess.open("user://water-scan.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
 print("WATER_SCAN checks=",checks," failures=",failures);get_tree().quit(int(failures>0))

func reference(source: Camera3D) -> float:
 var position := source.global_position
 # Camera3D.is_position_in_frustum rebuilds all six projection planes on
 # every call. A water scan can test thousands of cells with one camera.
 var frustum := source.get_frustum()
 var width := terrain.sectors_x * EITerrain.SECTOR
 var height := terrain.sectors_y * EITerrain.SECTOR
 var groups := {}
 # Probe original liquid cells, not walkable bridge heights. Bucket nearby
 # surface levels so tiny authored river slopes share a stable plane.
 for y in range(maxi(0, int(-position.z - REACH)) & ~1, mini(height, int(-position.z + REACH)), 2):
  for x in range(maxi(0, int(position.x - REACH)) & ~1, mini(width, int(position.x + REACH)), 2):
   var i := y * width + x
   var water_height := terrain.water[i]
   if not is_finite(water_height) or terrain.liquid_ground[i] in [EITerrain.LAVA, 255]: continue
   var point := Vector3(x + 0.5, water_height, -y - 0.5)
   var distance := point.distance_squared_to(position)
   if distance > REACH * REACH: continue
   var visible := true
   for boundary: Plane in frustum:
    if boundary.is_point_over(point):
     visible = false
     break
   if not visible: continue
   if water_height < terrain.height_at(point.x, -point.z) + 0.08: continue
   var weight := 1.0 / maxf(4.0, distance)
   var key := roundi(water_height * 4.0)
   var group: Vector2 = groups.get(key, Vector2.ZERO)
   groups[key] = group + Vector2(weight, water_height * weight)
 var best := -INF
 var score := 0.0
 for key in groups:
  var group: Vector2 = groups[key]
  var candidate := group.y / group.x
  var weight := group.x * (1.25 if is_finite(plane) and absf(candidate - plane) < 0.25 else 1.0)
  if weight > score:
   score = weight
   best = candidate
 return best
