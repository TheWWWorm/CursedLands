extends Node
## Lossless cumulative progress transport using an external campaign save.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func _ready() -> void:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--route-save="): source = arg.trim_prefix("--route-save=")
	var st := CampaignState.load_from(source)
	check(st != null, "load external save without modifying it")
	if st == null: get_tree().quit(1); return
	var s := Session.new(); add_child(s); s.set_physics_process(false)
	s.state=st; s.is_host=true; s.zone_id=st.current_zone
	s.world=GameWorld.new(); add_child(s.world); s.world.session=s
	s.world.set_process(false); s.world.set_physics_process(false)
	var bag := CoopProgress.main_bag(st)
	s.coop._pending[2]={"hero":CoopProgress.main_hero(st).duplicate(true),"vars":st.vars.duplicate(),
		"visited":st.visited.duplicate(),"side_quests":st.side_quests.duplicate(),"quest_items":st.quest_items.duplicate(),
		"seq":{},"purse":bag.duplicate(true),"party_context":CoopProgress.PartyProgress.capture(st)}
	s.coop.on_hello(2,1,"Transport Guest")
	var e:Dictionary=s.coop.joiners["transport guest"]
	e.in_sync=true; e.clean=true; e.present=true
	var started := Time.get_ticks_usec()
	var pkg := s.coop.package(e)
	pkg.sid=e.sid; pkg.seq=1
	var raw := var_to_bytes(pkg)
	var encode_start := Time.get_ticks_usec()
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var decode_start := Time.get_ticks_usec()
	var decoded := CoopProgress.decode_progress(packed,raw.size())
	var end := Time.get_ticks_usec()
	check(decoded == pkg,"compressed package preserves every campaign field")
	check(packed.size()<raw.size()/2,"cumulative save transfer shrinks by more than half")
	check(CoopProgress.decode_progress(packed,0).is_empty(),"invalid declared length is rejected")
	check(CoopProgress.decode_progress(packed,CoopProgress.MAX_PROGRESS_BYTES+1).is_empty(),"oversized declared length is rejected before allocation")
	var target := CampaignState.load_from(source)
	CoopProgress.merge(target,decoded)
	check(target.coop.applied.get(String(e.sid),{}).get("seq")==1,"decoded package keeps progress sequence bookkeeping")
	print("PROGRESS_COST ",JSON.stringify({"raw_bytes":raw.size(),"wire_bytes":packed.size(),"package_us":encode_start-started,
		"encode_us":decode_start-encode_start,"decode_us":end-decode_start,"at_64KiB_s_before_seconds":raw.size()/65536.0,"at_64KiB_s_after_seconds":packed.size()/65536.0}))
	s.world.free(); s.free()
	print("PROGRESS_TRANSPORT ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
