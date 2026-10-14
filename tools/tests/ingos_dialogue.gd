extends "third_person_kbm.gd"
## Actual Ingos map, original Tr49_1 topic, normal authoritative walk/turn ticks.
var shopper:GameUnit
var fleyn:GameUnit
func step_world()->void:
 s.world._tick(GameUnit.TICK)
 for u:GameUnit in s.world.unit_rows():u._sync_transform(0)
func _ready()->void:
 GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
 GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":3,"pad_enabled":0},true)
 PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
 s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
 s.state.set_var(0,"q.gz12k.q49k",2);s.state.set_var(0,"Tr49",2);s.state.set_var(0,"b.Shopper.Tr49_1",1)
 mode="Ingos dialogue";await s.enter_zone("bz8k",1,false)
 s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false)
 g.set_process(false);g.direct.set_process(false);g.rig.set_process(false)
 for i in 12:step_world()
 s.world.vm.instances.clear();s.world.vm.briefings._check=INF
 hero=s.party_units(0)[0];shopper=s.world.vm._by_name("Shopper");fleyn=s.world.vm._by_name("Vor")
 check(fleyn!=null and not fleyn.hidden and fleyn.model!=null,"authored Fleyn is present and visible")
 g.hud._dialog.visible=false;g.rig.release();g.selected.assign([hero])
 hero.blocked=false;hero.pos=Vector2(71,79);hero.facing=PI;hero.command({"type":"wait","t":0});hero._anim_lock=0
 hero.direct_controlled=true;hero.direct_heading=PI*0.75;hero.direct_look_until=Time.get_ticks_msec()+60000
 hero._sync_transform(0)
 var original:=shopper.pos;var fleyn_original:=fleyn.pos
 var b:=s.world.vm.briefings
 b.topic(0,"b.Shopper.Tr49_1",shopper.uid)
 check(b.active=="b.Shopper.Tr49_1" and not b._pending_dialog.is_empty(),"ordinary topic enters original walking stage")
 check(s.world.dialog_movers.has(hero) and s.world.dialog_movers[hero].to!=hero.pos,"protagonist receives the approach destination")
 check(s.world.dialog_movers.has(shopper) and s.world.dialog_movers[shopper].to!=original,"Karansul receives the third actor triangle destination")
 var started:=s.world.time
 for i in 540:
  step_world()
  if b._pending_dialog.is_empty():break
 check(b._pending_dialog.is_empty() and s.world.time-started<10,"actual map walk completes without 30-second fallback")
 check(shopper.pos.distance_to(original)>0.3,"Karansul physically walks for the conversation")
 check(fleyn.pos.distance_to(fleyn_original)<0.1,"Fleyn retains the authored second actor position")
 var faces:={}
 for u:GameUnit in [shopper,hero,fleyn]:faces[u.uid]=u.facing
 var errors:=[]
 for i in 120:
  step_world()
  for u:GameUnit in [shopper,hero,fleyn]:
   if absf(angle_difference(u.facing,faces[u.uid]))>0.01:errors.append(u.uid)
 check(errors.is_empty(),"participants retain dialogue facing despite direct-look and idle AI")
 check(absf(angle_difference(shopper.facing,((hero.pos+fleyn.pos)*0.5-shopper.pos).angle()))<0.11,"Karansul faces the speaking pair")
 check(absf(angle_difference(hero.facing,(fleyn.pos-hero.pos).angle()))<0.11,"hero faces Fleyn")
 var c:Dictionary=g.hud._dialog._cast
 check(c.a==hero.uid and c.b==fleyn.uid and c.c==shopper.uid,"authored camera slots retain Hero, Fleyn, Karansul despite clicked NPC")
 for role:String in ["a","b","c"]:
  var u:GameUnit=s.world.units[int(c[role])]
  check(Vector2(c.at[role][0],c.at[role][1]).distance_to(u.pos)<0.1,"camera uses actual staged actor "+role)
 if DisplayServer.get_name()!="headless":
  g.hud._dialog._i=1;g.hud._dialog._show();await frames(8)
  check(get_viewport().get_texture().get_image().save_png("user://fleyn-dialogue.png")==OK,"render Fleyn's original speaking scene")
 b.complete(0,b.active)
 check(b._return_actors.is_empty() and s.world.dialog_movers.has(shopper) and s.world.dialog_movers[shopper].get("restore",false),"closing schedules third actor's original return walk")
 for i in 360:step_world()
 check(shopper.pos.distance_to(original)<0.3,"Karansul walks back after dialogue")
 # A fully blocked static route must settle in place, not hang the dialogue.
 hero.direct_heading=NAN;g.hud._dialog.visible=false
 b.play_named("Tr49_1","b.Shopper.Tr49_1",0,shopper)
 var m:Dictionary=s.world.dialog_movers[shopper];shopper.command({"type":"wait","t":0});shopper._anim_lock=0
 m.to=shopper.pos+Vector2(1000,1000)
 for i in 200:
  step_world()
  if b._pending_dialog.is_empty():break
 check(b._pending_dialog.is_empty(),"failed staging route falls back to actual positions promptly")
 b.complete(0,b.active,true)
 g.queue_free();s.queue_free();await frames(8);TexUpscale.shutdown()
 print("INGOS_DIALOGUE ",checks," checks ",failures.size()," failures");get_tree().quit(0 if failures.is_empty() else 1)
