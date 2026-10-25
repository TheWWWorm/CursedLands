extends Node
const Legacy=preload("legacy_animation_part.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:
  failures+=1
  if failures<12:printerr("FAIL ",label)
func state(n:EIAnimPart)->Array:
 return [n.animation_key,n._world_key,n._parent_key,n._local_key,n._applied_quaternion,n._key_dirty,n._has_applied,n._absolute,n._parent_first,n.quaternion,n.transform]
func tree(legacy:bool)->Array[EIAnimPart]:
 var nodes:Array[EIAnimPart]=[]
 for i in 31:
  var n:EIAnimPart=Legacy.new() if legacy else EIAnimPart.new()
  n.name="part"+str(i);nodes.append(n)
  if i==0:add_child(n)
  else:
   var parent:EIAnimPart=nodes[(i-1)/2]
   parent.add_child(n);n.animation_parent=parent;parent.animation_children.append(n)
  n.position=Vector3(.1,.2,.3)
 return nodes
func _ready()->void:
 check(ClassDB.class_exists("AnimationCompositionKernel"),"native composition is available")
 if failures:get_tree().quit(1);return
 var a:=tree(false);var b:=tree(true)
 var rng:=RandomNumberGenerator.new();rng.seed=20261025
 for frame in 128:
  EIAnim.absolute=frame%3==0;EIAnim.parent_first=frame%4<2
  EIAnimPart.batch=true
  for i in a.size():
   var axis:=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
   var q:=Quaternion(axis,rng.randf_range(-PI,PI))
   a[i].animation_key=q;b[i].animation_key=q
  EIAnimPart.batch=false
  a[0]._apply_key();b[0]._apply_key()
  for i in a.size():check(state(a[i])==state(b[i]),"exact composition frame="+str(frame)+" part="+str(i))
  a[0]._apply_key();b[0]._apply_key()
  for i in a.size():check(state(a[i])==state(b[i]),"unchanged branch frame="+str(frame)+" part="+str(i))
 var rows:=[]
 EIAnim.absolute=false;EIAnim.parent_first=false
 for native:bool in [false,true,true,false]:
  var nodes:=a if native else b
  var micros:=0
  for frame in 1000:
   EIAnimPart.batch=true
   for i in nodes.size():nodes[i].animation_key=Quaternion(Vector3.UP,float(frame+i)*.005)
   EIAnimPart.batch=false
   var started:=Time.get_ticks_usec();nodes[0]._apply_key();micros+=Time.get_ticks_usec()-started
  rows.append({"native":native,"usec":micros,"frames":1000,"parts":nodes.size()})
 print("ANIMATION_COMPOSITION_PROBE_TIMING ",JSON.stringify(rows))
 print("ANIMATION_COMPOSITION_PROBE checks=",checks," failures=",failures)
 a[0].free();b[0].free();get_tree().quit(int(failures>0))
