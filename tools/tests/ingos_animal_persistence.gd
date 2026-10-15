extends Node
var checks:=0
var failures:=0
var rows:=[]
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func freeze(s:Session)->void:
 s.set_physics_process(false);s.world.set_physics_process(false);s.world.set_process(false)
func verify(s:Session,dead:Dictionary,looted:Array,phase:String)->void:
 for uid:int in dead:
  var u:GameUnit=s.world.units.get(uid)
  if uid in looted:
   check(u==null and s.world.looted.has(uid),phase+" looted animal remains absent "+str(uid))
  else:
   check(u!=null and u.dead and u.hp<=0.001,phase+" dead animal stays dead "+str(uid))
 for u:GameUnit in s.world.unit_rows():
  if u.has_meta("hero"):u.hp=u.max_hp
 for i in 200:s.world._tick(GameUnit.TICK)
 for uid:int in dead:
  var u:GameUnit=s.world.units.get(uid)
  check(u==null or u.dead,phase+" authored scripts do not revive "+str(uid))
 # New IDs with the same prototype would also constitute a respawn.
 check(not s.world.unit_rows().any(func(u:GameUnit):return not u.dead and String(u.info.get("prototype","")).to_lower() in dead.values()),phase+" no replacement animals spawn")
func _ready()->void: _run.call_deferred()
func _run()->void:
 GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0},true)
 GameData.options.merge(GfxPresets.values(GfxPresets.VERY_LOW),true)
 var campaign:=CampaignMap.load_from(GameData.texts)
 var zones:=[]
 for id:String in campaign.zones:
  var z:Dictionary=campaign.zones[id]
  if z.get("allod","")!="ingos" or z.get("type","")!="game":continue
  var mob:=EIMob.load_bytes(GameData.read_file("maps/"+String(z.get("mob",z.mpr))+".mob"))
  if mob.objects.any(func(o:Dictionary):return o.kind=="UNIT" and ("tiger" in String(o.get("prototype","")).to_lower() or "dog" in String(o.get("prototype","")).to_lower())):zones.append(id)
 check(not zones.is_empty(),"campaign has authored Ingos animals")
 for zone:String in zones:
  var s:=Session.new();add_child(s)
  var g:=Game.new();g.session=s;s.game=g;add_child(g)
  s.state.ensure_hero(0,s._hero_proto(0));await s.enter_zone(zone,1,false);freeze(s)
  var dead:={};var looted:=[]
  for u:GameUnit in s.world.unit_rows():
   var proto:=String(u.info.get("prototype","")).to_lower()
   if "tiger" not in proto and "dog" not in proto:continue
   dead[u.uid]=proto;u.die(null)
   if dead.size()%2==0:s.take_loot(s.party_units(0)[0],u);looted.append(u.uid)
  check(not dead.is_empty(),zone+" has actual authored tigers and dogs")
  check(s.save_game("animal-persistence")==OK,zone+" save all deaths")
  check(s.load_game("animal-persistence"),zone+" full session reload")
  while s.loading_game:await get_tree().process_frame
  freeze(s);verify(s,dead,looted,zone+" reload")
  await s.enter_zone("bz21k" if GameData.campaign_id==CampaignProfile.ASTRAL else "bz8k",1,false);freeze(s)
  await s.enter_zone(zone,1,false);freeze(s);verify(s,dead,looted,zone+" revisit")
  rows.append({"zone":zone,"animals":dead.size(),"looted":looted.size()})
  g.queue_free();s.queue_free();await get_tree().process_frame
 print("INGOS_ANIMAL_PERSISTENCE ",checks," checks ",failures," failures ",JSON.stringify(rows))
 FileAccess.open("user://ingos-animal-persistence.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"maps":rows},"  "))
 get_tree().quit(1 if failures else 0)
