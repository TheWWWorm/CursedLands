extends "story_coop_traps_net.gd"
## Prepared campaign boundaries, then actual map commands and ENet transfers.
## Island excursions retain VM/NPC state and restore positions, not old stats.
var expected_zone:="bz8k"
var dead_id:=0
var removed_id:=0
func loaded()->bool:
 return client.world!=null and client.zone_id==expected_zone and client.my_index==1 \
  and not host.loading_game and not client._remote_loading and not client._zone_holding and not client.loading_game \
  and client._pool_epoch==host._load_serial
func pause_scene(s:Session)->void:
 freeze(s);s.game.set_process(false);s.game.direct.set_process(false)
 if s.world.vm: s.world.vm.briefings._check=INF
func offer(allod:String)->Dictionary:
 for o:Dictionary in host.travel_options:
  if o.get("return_allod","")==allod:return o
 return {}
func arrive(id:String)->bool:
 expected_zone=id
 var ok:=await until(loaded,45)
 check(ok,"both peers arrive in "+id)
 if ok:pause_scene(host);pause_scene(client)
 return ok
func pick(o:Dictionary)->void:
 host.game.issue({"t":"travel","zone":o.zone,"entrance":o.entrance})
func _ready()->void:
 GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
 GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":1,"scroll_border":0,"pad_enabled":0,"auto_exit":1},true)
 host=branch(false);check(host.host(29953,2)==OK,"open island travel authority")
 host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero")
 host.set_physics_process(false)
 await host.enter_zone("bz1g",1,false);pause_scene(host);host.world.vm.instances.clear()
 var elder:GameUnit=host.world.vm._by_name("Elder");dead_id=elder.uid;elder.die(null)
 var removed:GameUnit=host.world.unit_rows().filter(func(u):return not u.has_meta("hero") and u!=elder)[0]
 removed_id=removed.uid;host.world.remove_unit(removed)
 host.state.set_var(0,"q.gz3g.q23g",2)
 await host.enter_zone("bz8k",1,false);pause_scene(host)
 host.world.vm.instances.clear()
 var fleyn:GameUnit=host.world.vm._by_name("Vor")
 host.world.vm.globals.Vor=fleyn;host.world.vm.spawn("VCheck#0#23",[null]);ticks(8)
 check(fleyn.hidden,"Fleyn's original gate has hidden him before the excursion")
 host.world.vm.instances.clear()
 host.world.vm.spawn("VTriger#0#30",[null]);ticks(2)
 var waiting:Array=host.world.vm.save_state().instances
 client=branch(true);check(client.join("127.0.0.1",29953)==OK,"join island travel guest")
 if not await arrive("bz8k"):await finish();return
 var poses:={}
 for u:GameUnit in host.party_heroes():
  u.command({"type":"wait","t":0});u._anim_lock=0
  u.pos=Vector2(71+2*u.controller,79);u.facing=.45+u.controller
  host.world.nav.rebucket(u);poses[u.controller]=[u.pos,u.facing]
 host.leave_zone("gz11k_bz8k",1)
 check(await until(func():return client.map_open),"other islands menu reaches guest")
 var back:=offer("gipat")
 check(not back.is_empty() and offer("suslanger").is_empty(),"only previously visited islands are offered")
 if back.is_empty():await finish();return
 var cm:TravelMap=client.game.hud._travel.get_child(0)
 var return_buttons:=cm._extra.find_children("*","Button",true,false)
 check(return_buttons.size()==1 and return_buttons[0].disabled,"guest sees the return destination but cannot select it")
 client.game.issue({"t":"travel","zone":back.zone,"entrance":back.entrance});await frames(8)
 check(host.zone_id=="bz8k" and host.map_open and not host.loading_game,"authority rejects a guest's island travel command")
 pick(back)
 if not await arrive("bz1g"):await finish();return
 check(host.world.units.has(dead_id) and host.world.units[dead_id].dead,"return keeps the earlier island's corpse")
 check(not host.world.units.has(removed_id),"return never respawns a removed actor")
 check(not host.world.vm.instances.any(func(i):return i.sname=="WorldScript"),"return never restarts the village startup sequence")
 check(host.state.get_var(0,"q.gz3g.q23g")==2,"completed earlier-island quest stays complete")
 # Persist the departure point across a save load while on the other island.
 check(host.save_game("island_excursion")==OK,"save while visiting the earlier island")
 var saved:=CampaignState.load_from(SaveInfo.path("island_excursion"))
 check(saved!=null and saved.island_returns==host.state.island_returns,"save retains exact departure location and stable party identities")
 check(host.load_game("island_excursion"),"reload the excursion save through the real session")
 if not await arrive("bz1g"):await finish();return
 host.state.set_var(0,"q.gz12k.q49k",2);host.state.money+=137
 var purse:=host.state.money
 host.leave_zone("gz1g_bz1g",1);var forward:=offer("ingos")
 check(not forward.is_empty() and forward.zone=="bz8k","return route leads to the area actually left")
 if forward.is_empty():await finish();return
 pick(forward)
 if not await arrive("bz8k"):await finish();return
 for u:GameUnit in host.party_heroes():
  check(u.pos.distance_to(poses[u.controller][0])<.001 and absf(angle_difference(u.facing,poses[u.controller][1]))<.001,"owner %d returns to exact departure coordinates/facing"%u.controller)
  check(await sync_visitor(u),"guest receives owner's restored position")
 check(host.state.money==purse and host.state.get_var(0,"q.gz12k.q49k")==2,"new money and quest progress survive the round trip")
 fleyn=host.world.vm._by_name("Vor")
 check(not fleyn.hidden and fleyn.visible,"Fleyn reconciles the completed quest on real zone revisit")
 check(not client.world.units[fleyn.uid].hidden,"guest's initial zone snapshot contains the restored visible Fleyn")
 check(not host.state.island_returns.has("ingos"),"arrival consumes the old return point")
 var resumed:Array=host.world.vm.save_state().instances.filter(func(i):return i.s=="VTriger#0#30")
 check(resumed.size()==1 and [resumed[0].s,resumed[0].b,resumed[0].i,resumed[0].f,resumed[0].k]==[waiting[0].s,waiting[0].b,waiting[0].i,waiting[0].f,waiting[0].k] \
  and absf(float(resumed[0].w)-float(waiting[0].w))<=host.world.vm.time+.001,"sleeping authored script keeps its statement and remaining delay across the excursion")
 # The return is the original field, even when that island's hub is elsewhere.
 await host.enter_zone("gz11k",1,false)
 if not await arrive("gz11k"):await finish();return
 host.world.vm.instances.clear()
 var at:Vector2=host.party_units(0)[0].pos+Vector2(2,2)
 host.party_units(0)[0].pos=at;host.world.nav.rebucket(host.party_units(0)[0])
 host.leave_zone("gz11k_bz8k",1);back=offer("gipat");pick(back)
 if not await arrive("bz1g"):await finish();return
 host.leave_zone("gz1g_bz1g",1);forward=offer("ingos")
 check(forward.zone=="gz11k","field departure returns to that field rather than a settlement")
 pick(forward)
 if not await arrive("gz11k"):await finish();return
 check(host.party_units(0)[0].pos.distance_to(at)<.001,"field round trip restores the exact point")
 # Native exit suppression treats return inside an exit like save/load.
 host.mod_config.rules.auto_exit=1;client.mod_config.rules.auto_exit=1
 host._auto_exit_check()
 check(host._auto_world==host.world and host._leave_armed==-1,"return does not immediately re-arm an exit or replay travel")
 # Closing allod travel in story-controlled scenes does not change flags.
 host.state.current_party="HeroAlone"
 check(host.island_return_options("gz11k_bz8k").is_empty(),"temporary parties cannot bypass their sequence")
 host.state.current_party="";host.state.set_var(0,"i.nocamp",1)
 check(host.island_return_options("gz11k_bz8k").is_empty(),"authored no-camp sequence blocks island travel")
 host.state.del_var(0,"i.nocamp");host.world.zone.cage=true
 check(host.island_return_options("gz11k_bz8k").is_empty(),"captivity cannot be escaped through island travel")
 host.world.zone.erase("cage")
 check(host.island_return_options("gz1g_bz1g").is_empty(),"an authored cross-island transfer cannot be diverted midway")
 host.leave_zone("gz11k_bz8k",1);back=offer("gipat")
 host.state.current_party="HeroAlone"
 pick(back);await frames(4)
 check(host.map_open and host.zone_id=="gz11k" and not host.loading_game,"authority rechecks sequence restrictions after the map opens")
 host.state.current_party=""
 print("ISLAND_RETURN ", JSON.stringify({"checks":checks,"failures":failures}));await finish()
