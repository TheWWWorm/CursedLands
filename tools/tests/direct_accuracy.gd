extends Node
var checks:=0
var failures:=0
class Hits extends Combat:
 var hits:=0
 var misses:=0
 var last:Dictionary
 func melee(_a:GameUnit,_b:GameUnit,record:Dictionary={})->void:
  last=record
  if record.hit:hits+=1
  else:misses+=1
 func weapon_spell(_a:GameUnit,_b:GameUnit)->void:pass
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _ready()->void:
 var w:=GameWorld.new();add_child(w);w.set_process(false);w.set_physics_process(false)
 var c:=Hits.new(w);w.combat=c
 var a:=GameUnit.new();a.world=w;a.uid=1;a.pos=Vector2(5,5);a.figure_half_z=0.9;a._radius_base=0.3
 a.stats={"to_hit":1,"parry":1,"range":0.0,"reach":20.0,"dmg_min":7,"dmg_max":7};w.add_child(a);w.set_unit(1,a)
 var b:=GameUnit.new();b.world=w;b.uid=2;b.pos=Vector2(6,5);b.figure_half_z=0.9;b._radius_base=0.3
 b.stats={"parry":100,"to_hit":1};w.add_child(b);w.set_unit(2,b)
 for mode:int in [2,3]:
  GameData.options.control_mode=mode
  a._resolve_direct_hit(Vector3.RIGHT)
  check(c.last.hit==false,"melee obeys a guaranteed failed accuracy roll in view "+str(mode))
  a.stats.to_hit=200;a._resolve_direct_hit(Vector3.RIGHT)
  check(c.last.hit==true,"melee obeys a guaranteed successful roll in view "+str(mode))
  a.stats.to_hit=1;b.pos=Vector2(8,5)
  var p:=Projectile.launch_direct(w,a,Vector3.RIGHT,true);p.set_physics_process(false);p._tick_direct(0.2)
  check(c.last.hit==false and c.last.dmg==7,"arrow contact retains damage but rolls accuracy in view "+str(mode))
  p.free();a.stats.to_hit=200
  p=Projectile.launch_direct(w,a,Vector3.RIGHT,true);p.set_physics_process(false);p._tick_direct(0.2)
  check(c.last.hit==true and not c.last.backstab,"arrow can hit without becoming a backstab in view "+str(mode))
  p.free();b.pos=Vector2(6,5);a.stats.to_hit=1
 a.stats.to_hit=100;b.stats.parry=100;c.hits=0;c.misses=0;c.rng.seed=4920
 for i in 2000:DirectCombat.contact(a,b)
 check(c.hits>850 and c.hits<1150 and c.misses>850,"equal attack/defence yields both hits and misses across 2000 contacts")
 a.set_meta("hero",{});a.stats.to_hit=0;b.facing=0;b.alert=false
 DirectCombat.contact(a,b)
 check(c.last.hit and c.last.backstab,"ordinary unalerted rear melee backstab remains guaranteed")
 b.alert=true;DirectCombat.contact(a,b)
 check(not c.last.hit and not c.last.backstab,"alerted target restores accuracy check")
 a.remove_meta("hero");w.free();TexUpscale.shutdown()
 print("DIRECT_ACCURACY ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)
