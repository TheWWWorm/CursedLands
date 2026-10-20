extends Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _ready()->void:
 seed(1701)
 GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
 var s:=Session.new();add_child(s);s.set_physics_process(false);s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
 var g:=Game.new();g.session=s;s.game=g;add_child(g)
 await s.enter_zone("gz10g",1,false)
 var w:=s.world;w.set_process(false);w.set_physics_process(false)
 for i in 5:w.time+=GameUnit.TICK;w.vm.tick(GameUnit.TICK)
 var u:GameUnit=w.units.get(59)
 check(u!=null and u.info.name=="GolemSd","original tunnel golem found")
 check(w.ai.mots(u).fight=="none","dormant golem starts without aggression")
 var foes:Array=w.vm.globals.Felem
 var hp:=foes.map(func(a):return a.hp)
 w.lever_sys.set_state(57,1,0)
 var targeted:=false
 for i in 600:
  w.time+=GameUnit.TICK;w.vm.tick(GameUnit.TICK)
  for a:GameUnit in [u]+foes:
   if not a.dead:a.tick(GameUnit.TICK);w.nav.track_unit(a)
  if u.order.get("type","")=="attack" and foes.has(u.order.get("target")):targeted=true
  if foes.any(func(a):return a.hp<float(hp[foes.find(a)])):break
 check(u.mode=="guard" and w.ai.mots(u)=={"fight":"aggression","susp":true,"corpse":true,"fear":0},"native activation supplies the complete Guard motivation list")
 check(targeted,"activated golem chooses an authored fire elemental")
 check(foes.any(func(a):return a.hp<float(hp[foes.find(a)])),"activated golem damages an authored fire elemental")
 var saved:=w.vm.save_state()
 u.remove_meta("um")
 preload("res://src/game/script/story_compat.gd").restore_tunnel_guard(w.vm)
 check(w.ai.mots(u).fight=="aggression","old activated save without combat motivations is repaired")
 u.mode="none";u.remove_meta("um")
 preload("res://src/game/script/story_compat.gd").restore_tunnel_guard(w.vm)
 check(w.ai.mots(u).fight=="none","old deactivated golem is not reactivated")
 w.vm._restore(saved)
 check(w.ai.mots(u).fight=="aggression","Guard combat motivations survive script save restoration")
 var inst:=ScriptVM.Instance.new();inst.locals.actor=u
 w.vm._call("UMClear",[[ScriptParser.N_VAR,"actor"]],inst)
 w.vm._call("UMGuard",[[ScriptParser.N_VAR,"actor"],[ScriptParser.N_NUM,u.pos.x],[ScriptParser.N_NUM,u.pos.y],[ScriptParser.N_NUM,5.0]],inst)
 check(w.ai.mots(u).fight=="none","UMGuard alone still preserves a deliberately passive list")
 g.queue_free();s.queue_free()
 for i in 10:await get_tree().process_frame
 TexUpscale.shutdown()
 print("TUNNEL_GUARD ", JSON.stringify({"checks":checks,"failures":failures}))
 get_tree().quit(1 if failures else 0)
