extends "story_coop_traps_net.gd"
## Actual ENet ownership, death/revival events and delayed living snapshots.
func loaded()->bool:
 return client.world!=null and client.zone_id=="gz1g" and client.my_index==1 \
  and not client._remote_loading and not client._zone_holding and not client.loading_game
func _ready()->void:
 GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
 GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"revive":1,"control_mode":3,"scroll_border":0,"pad_enabled":0},true)
 PadInput.active="kbm"
 host=branch(false);check(host.host(29952,2)==OK,"open camera authority")
 host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero")
 await host.enter_zone("gz1g",1,false);freeze(host);host.world.vm.instances.clear()
 client=branch(true);check(client.join("127.0.0.1",29952)==OK,"connect camera guest")
 if not await until(loaded):check(false,"guest receives camera scene");await finish();return
 freeze(client);client.game.direct.set_process(false);client.game.set_process(false)
 var own:=visitor();var peer:GameUnit=host.party_units(0)[0]
 own.command({"type":"wait","t":0});own._anim_lock=0;own._set_action("idle")
 peer.command({"type":"wait","t":0});peer._anim_lock=0;peer._set_action("idle")
 check(await sync_visitor(own),"guest starts alive")
 var g:=client.game;var replica:GameUnit=client.world.units[own.uid]
 var watched:GameUnit=client.world.units[peer.uid]
 for mode:int in [2,3]:
  GameData.options.control_mode=mode;g.selected.assign([replica]);g.rig.release();g.direct._process(0)
  own.die(null);check(await sync_visitor(own),"death snapshot arrives in view "+str(mode))
  g._keep_selection();g.direct._process(0);g.direct.focus_portrait(watched)
  check(g.selected.is_empty() and g.direct.view_target()==watched and g.direct.pointer,"dead guest can inspect co-op portrait")
  # The reliable event can arrive before the snapshot that clears dead.
  g.on_event({"t":"revived","uid":replica.uid});g.direct._process(0)
  check(g.direct.view_target()==watched,"early revival notice waits for living ownership snapshot")
  Revive.finish(host,own);check(await sync_visitor(own),"living snapshot arrives")
  g._keep_selection();g.direct._process(0);g.direct.apply_camera(1.0/60)
  check(g.direct.leader()==replica and g.direct.view_target()==replica and not g.direct.pointer,"revival restores own direct camera in view "+str(mode))
  # The original stand-up clip temporarily uses a full-body camera. Let the
  # authority finish it, then deliver its idle snapshot to the frozen guest.
  for i in 180:own._tick(GameUnit.TICK)
  check(not own.action.begins_with("anim:"),"revival stand-up clip finishes")
  host._send_snapshot_records([own.snapshot()],host.world.time);await frames(8)
  g.direct._process(0);g.direct.apply_camera(1.0/60)
  check(is_equal_approx(g.rig.camera.near,0.03 if mode==3 else 0.08),"revival restores perspective near plane")
  check(g.direct._view_model==replica.model if mode==3 else g.direct._view_model==null,"revival restores correct first-person model visibility")
  g.direct.focus_portrait(watched);g.on_event({"t":"revived","uid":replica.uid});g.direct._process(0)
  check(g.direct.view_target()==watched and g.direct.pointer,"alive portrait inspection survives an unrelated/duplicate revival notice")
  g.direct.pointer=false;g.direct._portrait_target=null
 await finish()
func finish()->void:
 for s:Session in [client,host]:
  if is_instance_valid(s) and is_instance_valid(s.game):
   s.game.direct.stop_move();s.game.direct._control_id=-1
 for s:Session in [client,host]:
  if is_instance_valid(s) and s.multiplayer.multiplayer_peer:
   var peer:=s.multiplayer.multiplayer_peer
   s.online=false;s.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new();peer.close()
 for n:Node in branches:n.queue_free()
 await frames(8);TexUpscale.shutdown()
 print("REVIVE_CAMERA ", JSON.stringify({"checks":checks,"failures":failures}))
 get_tree().quit(1 if failures else 0)
