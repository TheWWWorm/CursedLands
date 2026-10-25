extends Node
const Legacy=preload("legacy_unit_sounds.gd")
const Candidate=preload("typed_unit_sounds.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:
  failures+=1
  if failures<12:printerr("FAIL ",label)
func _ready()->void:
 var world:=GameWorld.new()
 var mixer:=SoundMixer.new()
 var player:=AnimationPlayer.new();add_child(player)
 var library:=AnimationLibrary.new()
 for clip:String in ["idle","run"]:
  var animation:=Animation.new();animation.length=2.0
  library.add_animation(clip,animation)
 player.add_animation_library("ei",library)
 player.play("ei/idle");player.advance(0)
 var actors:Array[GameUnit]=[]
 for i in 334:
  var unit:=GameUnit.new();unit.pos=Vector2(float(i),0)
  var model:=EIUnitModel.new();model.template="probe";model.player=player
  unit.model=model;unit.add_child(model);actors.append(unit)
 world._unit_rows=actors
 var old:=Legacy.new(mixer,world);var current:=Candidate.new(mixer,world)
 old._adb["probe"]={};current._adb["probe"]={}
 for frame in 100:
  mixer.listener=Vector3(float(frame*3),0,0)
  player.play("ei/idle" if frame%2==0 else "ei/run");player.advance(.01*frame)
  old.tick();current.tick()
  check(old._stamp==current._stamp,"stamp "+str(frame))
  check(snapshot(old._units)==snapshot(current._units),"exact live state "+str(frame))
 var rows:=[]
 mixer.listener=Vector3.ZERO
 for near_count in [0,16,56,334]:
  for i in actors.size():actors[i].pos=Vector2.ZERO if i<near_count else Vector2(100,100)
  old._units.clear();current._units.clear();old.tick();current.tick()
  for native:bool in [false,true,true,false]:
   var collector=current if native else old
   var started:=Time.get_ticks_usec()
   for frame in 2000:collector.tick()
   rows.append({"native":native,"usec":Time.get_ticks_usec()-started,"frames":2000,"actors":actors.size(),"near":near_count})
 print("TYPED_UNIT_SOUND_SCAN_PROBE_TIMING ",JSON.stringify(rows))
 print("TYPED_UNIT_SOUND_SCAN_PROBE checks=",checks," failures=",failures)
 for unit in actors:unit.free()
 mixer.free();world.free();player.free();get_tree().quit(int(failures>0))

func snapshot(states: Dictionary)->Dictionary:
 var out:={}
 for key in states:
  var st=states[key]
  out[key]=[st.clip,st.anim,st.name,st.frame,st.idle,st.attack,st.seen,st.get("far",false) if st is Dictionary else st.far]
 return out
