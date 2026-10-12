extends Node
## Lossless large campaign documents and wall-time batching at double speed.
var checks := 0
var failures := 0
class CountSession extends Session:
	var sends := 0
	var recipients := []
	func _sync_state_to(only_pid: int, _periodic: bool) -> void: sends+=1; recipients.append(only_pid)
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func _ready() -> void:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--route-save="): source=arg.trim_prefix("--route-save=")
	var st := CampaignState.load_from(source)
	check(st!=null,"read actual supplied campaign without changing it")
	if st==null: get_tree().quit(1); return
	var ev := {"t":"state","money":st.money,"quests":st.quests,"quest_items":st.quest_items,"items":st.items,
		"heroes":st.heroes,"mercs":st.mercs,"side_quests":st.side_quests,"shops":st.shops,"visited":st.visited,
		"current_party":st.current_party,"parties":st.parties,"party_bags":st.party_bags,"vars":st.vars,
		"gs_tables":st.gs_metadata(),"gs_reconstructed":st.gs_reconstructed,"last_quest":st.last_quest,
		"world_time":st.world_time,"day":st.day,"revive":0,"unit_stats":{},"lmp_settings":{}}
	var packet := NetState.pack(ev)
	check(packet.get("t")=="state_zip","large campaign is compressed before fragmentation")
	check(NetState.unpack(packet)==ev,"all campaign fields survive exact Variant round-trip")
	var raw := var_to_bytes(ev).size(); var wire := var_to_bytes(packet).size()
	check(wire<raw/2,"whole-document compression cuts large state by more than half")
	var receiver := Session.new(); add_child(receiver); receiver.set_physics_process(false)
	receiver.is_host=false; receiver.state=CampaignState.new(); receiver.world=GameWorld.new()
	receiver._on_event(packet)
	check(receiver.state.vars==st.vars and receiver.state.gs_metadata()==st.gs_metadata(),"client restores exact script variables and hash metadata")
	check(receiver.state.heroes==st.heroes and receiver.state.parties==st.parties,"client retains every party and character record")
	check(receiver.state.items==st.items and receiver.state.party_bags==st.party_bags,"client retains every inventory and chapter bag")
	check(receiver.state.quests==st.quests and receiver.state.visited==st.visited,"client retains journal and visited zones")
	var own := ev.duplicate(); own.money=456; own.items=["guest item"]
	var guest := NetState.pack(own)
	check(NetState.unpack(guest).money==456 and NetState.unpack(guest).items==["guest item"] and NetState.unpack(packet).items==st.items,"recipient-specific purse is encoded after ownership projection")
	check(NetState.pack({"t":"state","money":1})=={"t":"state","money":1},"small state keeps its ordinary representation")
	for invalid in [{},{"bytes":0,"data":packet.data},{"bytes":NetState.MAX_BYTES+1,"data":packet.data},
		{"bytes":packet.bytes,"data":"wrong type"},{"bytes":packet.bytes,"data":PackedByteArray()}]:
		check(NetState.unpack(invalid).is_empty(),"invalid wrapper is rejected before decompression")
	var wrong := var_to_bytes({"t":"state_zip","data":packet.data,"bytes":packet.bytes})
	check(NetState.unpack({"bytes":wrong.size(),"data":wrong.compress(FileAccess.COMPRESSION_ZSTD)}).is_empty(),"nested wrapper cannot recursively decompress")
	var counter := CountSession.new(); add_child(counter); counter.set_physics_process(false); counter.online=true
	counter._state_dirty=true; counter._state_sync_at_ms=0; counter._sync_state_due()
	check(counter.sends==1,"dirty state sends at the first wall-time opportunity")
	Engine.time_scale=2.0
	for i in 30: counter._state_dirty=true; counter._sync_state_due()
	check(counter.sends==1 and counter._state_dirty,"double-speed and catch-up callbacks retain one pending state")
	counter._state_sync_at_ms=Time.get_ticks_msec()-1; counter._sync_state_due()
	check(counter.sends==2 and not counter._state_dirty,"next wall-time opportunity includes the latest pending state")
	counter._state_dirty=false; counter._state_sync_at_ms=Time.get_ticks_msec()-5001; counter._sync_state_due()
	check(counter.sends==3,"unchanged state still receives a periodic refresh")
	counter._state_waiting={2:5,3:6}; counter._state_pending={2:true,3:true}
	counter._state_ack(2,4)
	check(counter.sends==3 and counter._state_waiting[2]==5,"stale acknowledgement cannot release a newer state")
	counter._state_ack(2,5)
	check(counter.sends==4 and counter.recipients[-1]==2 and not counter._state_waiting.has(2) and counter._state_waiting[3]==6,"acknowledgement recomputes only its peer's latest deferred state")
	counter._state_ack(2,5)
	check(counter.sends==4,"duplicate acknowledgement cannot send another document")
	counter._state_waiting[2]=7; counter._state_pending.erase(2); counter._state_ack(2,7)
	check(counter.sends==4 and not counter._state_waiting.has(2),"acknowledgement without new changes ends the stream")
	Engine.time_scale=1.0; counter.online=false
	receiver.world.free(); receiver.world=null; receiver.queue_free(); counter.queue_free()
	print("CAMPAIGN_STATE_COST ",JSON.stringify({"raw_bytes":raw,"wire_bytes":wire}))
	print("CAMPAIGN_STATE_TRANSPORT %d checks %d failures"%[checks,failures])
	for i in 4: await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
