extends "third_person_kbm.gd"
func _ready()->void:
 GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0},true)
 PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
 s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
 mode="direct chest targeting"
 await s.enter_zone("gz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "gz10g",1,false)
 await prepare()
 var found:=-1
 for nid:int in s.world.levers:
  if not s.world.lever_sys.usable(nid) or int(s.world.levers[nid].get("door",0))!=0:continue
  var obj:Node3D=s.world.objects.get(nid)
  if not is_instance_valid(obj):continue
  # Retain the original mechanism/model, place it on this fixture's clear
  # arrival patch to isolate crosshair selection from tunnel floor routing.
  var p:=free_point(2.0)
  obj.global_position=Vector3(p.x,s.world.ground_at(p.x,p.y),-p.y)
  g.direct.heading=(p-hero.pos).angle();g.direct.tilt=0;g.direct.apply_camera()
  if g.direct._nearby_lever()==nid:found=nid;break
 check(found>=0,"original map provides a nearby usable mechanism")
 if found>=0:
  var obj:Node3D=s.world.objects[found]
  print("NATIVE_MECHANISM ",obj.get_meta("ei").get("template"))
  for camera_mode:int in [2,3]:
   GameData.options.control_mode=camera_mode;reset();g.direct.apply_camera();g._pick_key=[]
   check(g.direct._nearby_lever()==found,"chest-height object is selected below a level crosshair in mode "+str(camera_mode))
   g.direct.interact()
   check(hero.orders.any(func(o):return int(o.get("use_object",-1))==found),"interaction posts ordinary authority use/approach in mode "+str(camera_mode))
  reset();g.direct.heading+=PI;g.direct.apply_camera()
  check(g.direct._nearby_lever()!=found,"nearby assist excludes mechanisms behind the player")
  g.direct.heading-=PI;s.world.levers[found].enabled=false;g.direct.apply_camera()
  check(g.direct._nearby_lever()!=found,"nearby assist excludes disabled mechanisms")
 g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
 print("DIRECT_INTERACTIONS ",checks," checks ",failures.size()," failures")
 get_tree().quit(0 if failures.is_empty() else 1)
