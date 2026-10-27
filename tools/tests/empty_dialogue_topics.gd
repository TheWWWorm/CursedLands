extends Node
class CaptureSession extends Session:
	var topics: Array = []
	func broadcast(event: Dictionary) -> void:
		if event.get("t", "") == "topics": topics.append(event.duplicate(true))
		super.broadcast(event)
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	TutorialPanel.auto_show = false
	var s := CaptureSession.new(); add_child(s)
	var g := Game.new(); g.session=s; s.game=g; add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0))
	var astral := GameData.campaign_id == CampaignProfile.ASTRAL
	await s.enter_zone("bz3h" if astral else "bz8k",1,false)
	s.set_physics_process(false); s.world.set_process(false); s.world.set_physics_process(false); s.world.vm.instances.clear()
	var b := s.world.vm.briefings
	b.active=""; b._pending_dialog={}; b._check=INF
	for key in s.state.gs_keys(0,"b.",true): s.state.set_var(0,key,3)
	var npc: GameUnit = s.world.vm._by_name("merc10" if astral else "merc5")
	check(npc != null, "authored NPC exists")
	if npc == null: get_tree().quit(1); return
	npc._talk_command=0; npc._talk_posted=9
	var owner := String(npc.info.name)
	var missing := "n11_10" if astral else "n5_2"
	var key := "b.%s.%s" % [owner,missing]
	check(GameData.text("briefing " + missing).is_empty(), "original data really lacks this legacy briefing")
	s.state.set_var(0,key,1)
	check(Briefings.pending_for(s.state,npc).size()==1, "legacy campaign variable remains pending")
	s.topics.clear(); b.interact(null,npc,0)
	check(s.topics.is_empty(), "missing-only offers cannot open a Goodbye-only menu")
	check(not g.can_talk_to(npc), "unavailable dialogue has no interaction affordance")
	var known := "brief_42" if astral else "z1"
	check(not GameData.text("briefing "+known).is_empty(), "authored conversation control exists")
	s.state.set_var(0,"b.%s.%s" % [owner,known],1)
	b.interact(null,npc,0)
	check(s.topics.size()==1 and s.topics[0].options.size()==1 and not s.topics[0].options[0].title.strip_edges().is_empty(), "mixed list contains its real authored topic without blank rows")
	check(g.can_talk_to(npc), "real conversation stays available")
	var before := s.state.money
	b.topic(0,key,npc.uid)
	check(b.active.is_empty() and s.state.get_var(0,key)==1 and s.state.money==before, "stale missing choice cannot silently complete a story or award rewards")
	g.queue_free(); s.queue_free(); await get_tree().process_frame
	print("EMPTY_DIALOGUE_TOPICS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
