extends "dar_standard_route.gd"
const Legacy=preload("legacy_ground_contact.gd")
var marks_script:Variant=GroundMarks
func phase(label:String,seconds:float,goal:=Vector2.INF,pan:=false)->void:
 await super.phase(label,seconds,goal,pan)
 if label!="final-held":return
 var marks:GroundMarks=s.world.ground_marks
 var feet:Array[Node3D]=[]
 for u:GameUnit in s.world.visible_units():
  if u.dead or not u.is_visible_in_tree() or u.model==null:continue
  var leg:=int(u.race.get("leg_segment",0))
  if leg<=0 or leg>=9:continue
  for name:String in ["ll%d"%leg,"rl%d"%leg]:
   var part:=marks._part(u,name)
   if part:feet.append(part)
 check(not feet.is_empty(),"live Dar animated feet are present")
 var saved=marks_script._sole_kernel
 check(saved!=null,"Dar uses native sole geometry")
 if saved==null:return
 var reference:=Legacy.new()
 reference.world=s.world
 reference._sole_meshes=marks._sole_meshes
 var expected:Array[Dictionary]=[]
 for part in feet:expected.append(reference._sole_contact(part))
 var admitted:=0
 for row in expected:admitted+=int(not row.is_empty())
 check(admitted>0,"live Dar feet include planted contacts")
 var rows:=[]
 for enabled:bool in [false,true,true,false]:
  var collector:GroundMarks=marks if enabled else reference
  for i in feet.size():check(collector._sole_contact(feet[i])==expected[i],"live sole before timing "+str(i))
  var total:=0
  var started:=Time.get_ticks_usec()
  for repeat in 200:
   for part in feet:total+=int(not collector._sole_contact(part).is_empty())
  var elapsed:=Time.get_ticks_usec()-started
  check(total==admitted*200,"same admitted sole count throughout timing")
  for i in feet.size():check(collector._sole_contact(feet[i])==expected[i],"live sole after timing "+str(i))
  rows.append({"native":enabled,"usec":elapsed,"queries":feet.size()*200,"feet":feet.size(),"admitted":admitted,"world_actors":s.world.units.size(),"visible_actors":s.world.visible_units().size()})
 reference.free()
 write_file("ground-contact-micro.json",JSON.stringify(rows,"\t"))
 print("GROUND_CONTACT_LIVE_MICRO ",JSON.stringify(rows))
