extends "dar_standard_route.gd"
const Pressure = preload("res://src/game/fx/vegetation_interaction.gd")
func phase(label: String,seconds: float,goal:=Vector2.INF,pan:=false)->void:
 await super.phase(label,seconds,goal,pan)
 if label!="final-held":return
 # Run only after the route measurements. No await separates the ABBA passes:
 # scene inputs stay unchanged; these timings are not frame-rate measurements.
 var details:=s.world.terrain.details
 var field=details.interaction
 check(field!=null,"Dar has its live vegetation pressure owner")
 if field==null:return
 var saved=Pressure._kernel
 var focus:Vector2=field.focus
 var rows:=[]
 for offset:Vector2 in [Vector2.ZERO,Vector2(5,0),Vector2(0,5)]:
  field.focus=focus+offset
  Pressure._kernel=null
  var expected=field.contacts(details,s.world)
  var direct=saved.contacts(s.world.visible_units(),details,field.focus,GameUnit,EIUnitModel,TerrainDetails,Pressure.WIDTH,Pressure.MAX_UNITS,GameUnit.STANCE_CRAWL)
  check(direct!=null and direct==expected,"native live Dar contacts match script at "+str(offset))
  for enabled:bool in [false,true,true,false]:
   Pressure._kernel=saved if enabled else null
   var before=field.contacts(details,s.world)
   check(before==expected,"unchanged live inputs before timing")
   var total:=0
   var start:=Time.get_ticks_usec()
   for i in 300:total+=field.contacts(details,s.world).size()
   var elapsed:=Time.get_ticks_usec()-start
   check(field.contacts(details,s.world)==expected and total==expected.size()*300,"unchanged live contacts after timing")
   rows.append({"offset":str(offset),"native":enabled,"usec":elapsed,"queries":300,"contacts":expected.size(),"world_actors":s.world.units.size(),"visible_actors":s.world.visible_units().size()})
 Pressure._kernel=saved;field.focus=focus
 write_file("vegetation-contacts-micro.json",JSON.stringify(rows,"\t"))
 print("VEGETATION_CONTACTS_LIVE_MICRO ",JSON.stringify(rows))
