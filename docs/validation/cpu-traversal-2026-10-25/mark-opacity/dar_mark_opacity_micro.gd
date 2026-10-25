extends "dar_standard_route.gd"
const Legacy=preload("legacy_mark_update.gd")
func state(m:GroundMarks.Mark)->Array:
 return [m.life,m.a,m.b,m.angle,m.decal.modulate,PackedFloat32Array([m.projection.material_override.get_shader_parameter(&"opacity")])[0] if m.projection else -1.0]
func phase(label:String,seconds:float,goal:=Vector2.INF,pan:=false)->void:
 await super.phase(label,seconds,goal,pan)
 if label!="final-held":return
 var marks:GroundMarks=s.world.ground_marks
 var selected:Array[GroundMarks.Mark]=[]
 for m:GroundMarks.Mark in marks.foot_marks:
  if m.grow==0.0 and m.projection:selected.append(m)
  if selected.size()==32:break
 check(not selected.is_empty(),"actual Dar projected footprints are present")
 var reference:=Legacy.new();reference.world=s.world
 var original:=[];var expected:=[];var alphas:=[]
 for m in selected:
  original.append([m.life,m.decal.modulate,m.projection.material_override.get_shader_parameter(&"opacity")])
  alphas.append(m.alpha0)
  reference._update(m);expected.append(state(m))
 var rows:=[]
 for candidate:bool in [false,true,true,false]:
  var collector:GroundMarks=marks if candidate else reference
  var elapsed:=0
  for repeat in 2000:
   for i in selected.size():
    var m:=selected[i];m.life=original[i][0];m.decal.modulate=original[i][1]
    m.projection.material_override.set_shader_parameter(&"opacity",original[i][2])
   var started:=Time.get_ticks_usec()
   for m in selected:collector._update(m)
   elapsed+=Time.get_ticks_usec()-started
  for i in selected.size():check(state(selected[i])==expected[i],"same live footprint output after timed updates")
  rows.append({"candidate":candidate,"usec":elapsed,"queries":selected.size()*2000,"footprints":selected.size(),"alphas":alphas,"actors":s.world.units.size()})
 for i in selected.size():
  var m:=selected[i];m.life=original[i][0];m.decal.modulate=original[i][1]
  m.projection.material_override.set_shader_parameter(&"opacity",original[i][2])
 reference.free()
 write_file("mark-opacity-micro.json",JSON.stringify(rows,"\t"))
 print("MARK_OPACITY_LIVE_MICRO ",JSON.stringify(rows))
