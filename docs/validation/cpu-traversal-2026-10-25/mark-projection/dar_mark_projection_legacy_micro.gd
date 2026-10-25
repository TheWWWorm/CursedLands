extends "dar_standard_route.gd"
const Legacy=preload("legacy_mark_projection.gd")

func geometry(projector:GroundMarkProjection)->Array:
 return [projector._verts.duplicate(),projector._normals.duplicate(),projector._uvs.duplicate(),projector._grids.duplicate(),projector._colors.duplicate()]

func phase(label:String,seconds:float,goal:=Vector2.INF,pan:=false)->void:
 await super.phase(label,seconds,goal,pan)
 if label!="final-held":return
 var marks:GroundMarks=s.world.ground_marks
 var current:GroundMarkProjection=marks._projection
 check(current!=null,"live Dar has the terrain mark projector")
 if current==null:return
 var projection_script:Variant=GroundMarkProjection
 check(projection_script._kernel!=null,"Dar uses native mark geometry")
 var reference:=Legacy.new(s.world)
 var selected:Array[GroundMarks.Mark]=[]
 for mark:GroundMarks.Mark in marks.foot_marks:
  if mark.projection and mark.projection.mesh and mark.projection.mesh.get_surface_count()>0:
   selected.append(mark)
   if selected.size()>=32:break
 check(not selected.is_empty(),"Dar traversal leaves visible mark geometry")
 if selected.is_empty():return
 var expected:=[]
 var vertices:=0
 for mark in selected:
  reference.place(mark,true)
  var value:=geometry(reference)
  vertices+=value[0].size();expected.append(value)
 var rows:=[]
 for enabled:bool in [false,true,true,false]:
  var projector:GroundMarkProjection=current if enabled else reference
  for i in selected.size():
   projector.place(selected[i],true)
   check(geometry(projector)==expected[i],"exact Dar mark before timing "+str(i))
  var total:=0
  var started:=Time.get_ticks_usec()
  for repeat in 40:
   for mark in selected:
    projector.place(mark,true)
    total+=projector._verts.size()
  var elapsed:=Time.get_ticks_usec()-started
  check(total==vertices*40,"unchanged geometry count throughout timing")
  for i in selected.size():
   projector.place(selected[i],true)
   check(geometry(projector)==expected[i],"exact Dar mark after timing "+str(i))
  rows.append({"native":enabled,"usec":elapsed,"queries":selected.size()*40,"marks":selected.size(),"vertices":vertices,"soft_ground":Gfx.on("gfx_soft_ground"),"world_actors":s.world.units.size(),"visible_actors":s.world.visible_units().size()})
 write_file("mark-projection-micro.json",JSON.stringify(rows,"\t"))
 print("MARK_PROJECTION_LIVE_MICRO ",JSON.stringify(rows))
