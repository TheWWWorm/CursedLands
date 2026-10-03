class_name SideQuests
extends RefCounted
## Optional quests from the quest maps (maps/zNqK.mq + zNqK.mob). Each .mq
## holds the quest's texts, briefings (<q>_1 offer, _2 reject, _3 reward),
## quest.reg (rewards) and map.txt naming the zone map it plays on. Villages
## offer them for zones the party has visited; while one is active its .mob
## is merged into that zone (units + script). State lives in
## CampaignState.side_quests: q -> "active" | "done" | "rewarded" | "rejected".

static var _all: Array = []
static var _by_id := {}


static func all() -> Array:
	if not _all.is_empty() or GameData.root.is_empty():
		return _all
	var dir := GameData.root.path_join("maps")
	for f in GameFiles.files(dir):
		if not f.to_lower().ends_with(".mq"):
			continue
		var arc := EIResArchive.open_path(dir.path_join(f))
		if arc == null:
			continue
		var id := f.get_basename().to_lower()
		var reg := EIRegFile.parse(arc.read(id + "/quest.reg"))
		var mpr := ""
		var lines := EIText.ansi(arc.read(id + "/map.txt")).split("\n")
		for i in lines.size():
			if lines[i].strip_edges().to_lower() == "#res" and i + 1 < lines.size():
				mpr = lines[i + 1].strip_edges().get_slice(" ", 0).to_lower()
				break
		var text := EIText.ansi(arc.read("quest " + id)).replace("\r", "")
		var q := {"id": id, "arc": arc, "reg": reg, "mpr": mpr, "title": text.get_slice("\n", 0).strip_edges(),
			"desc": text.get_slice("\n", 1).strip_edges(),
			"exp": float(reg.get("briefing complete", {}).get("exp", 0)),
			"money": int(reg.get("briefing complete", {}).get("money", 0))}
		_all.append(q)
		_by_id[id] = q
	return _all


static func get_quest(id: String) -> Dictionary:
	all()
	return _by_id.get(id.to_lower(), {})


## The briefing record the original builds from a quest map's
## quest.reg for its <q>_1 / _2 / _3 briefings ("briefing receive" / "reject"
## / "complete": exp, money, give items, remove items, give quests, complete
## quests), in the briefings.db field names the dialog's reward lines read
## (DialogPanel._reward_lines).
static func briefing_row(brief: String) -> Dictionary:
	brief = brief.to_lower()
	var q := get_quest(brief.get_slice("_", 0))
	if q.is_empty():
		return {}
	var sec := String({"1": "briefing receive", "2": "briefing reject", "3": "briefing complete"}.get(brief.get_slice("_", 1), ""))
	var r: Dictionary = q.reg.get(sec, {}) if sec else {}
	if r.is_empty():
		return {}
	return {"unknown": float(r.get("exp", 0)), "money": float(r.get("money", 0)), "give_items": r.get("give items"),
		"take_items": r.get("remove items"), "give_quests": r.get("give quests"), "give_quests2": r.get("complete quests")}


## Text from any quest map archive ("briefing z3q1_1", "quest z3q1").
static func text(key: String) -> String:
	key = key.to_lower()
	for q: Dictionary in all():
		var arc: EIResArchive = q.arc
		if arc.has(key):
			return EIText.ansi(arc.read(key)).replace("\r", "")
	return ""


## Campaign zone id the quest plays in.
static func zone_of(s: Session, q: Dictionary) -> String:
	if not s.lmp.is_empty():   # the multiplayer game plays the quest map's own zone
		return String(q.get("id", ""))
	return String(s.campaign.zone_by_map(q.mpr).get("id", ""))


## Quests the village the party is in can offer right now.
static func offers(s: Session) -> Array:
	var out := []
	if s.world == null or String(s.world.zone.get("type", "")) != "brief":
		return out
	var allod := String(s.world.zone.get("allod", ""))
	for v in s.state.side_quests.values():
		if v == "active" or v == "done":
			return out   # one side quest at a time
	for q: Dictionary in all():
		if s.state.side_quests.has(q.id):
			continue
		var z := zone_of(s, q)
		if z.is_empty() or not s.state.visited.has(z) or String(s.campaign.zone(z).get("allod", "")) != allod:
			continue
		out.append(q)
	return out


# ---------------------------------------------------------------- LMP quest cycle
# the original's multiplayer server keeps one quest at a time (of the
# server object) and a list of conversation records its quest giver offers
# "<q>_1" offers on a new server
# "<q>_2" while <q> is taken, "<q>_3" once its script reports it done. Each
# reaches the clients as the GS var b.<giver>.<name> = 1 (
# ), a topic of the giver. A finished conversation goes to the
# server (message 1 with the
# briefing name); finds it among the records and by its last two
# characters takes (_1), cancels (_2) or
# completes (_3) the quest. Remake: Session.lmp holds "quest"
# (taken, "" none), "last" and "topics" (the b.* vars offered).

## Host: the giver's topics become `names` ("<q>_<n>"), the old ones gone.
static func _lmp_topics(s: Session, names: Array) -> void:
	for k: String in s.lmp.get("topics", []):
		s.state.set_var(0, k, 0.0)
	var keys := []
	for n: String in names:
		var k := "b.%s.%s" % [LmpMode.giver(n.get_slice("_", 0)), n]
		s.state.set_var(0, k, 1.0)
		keys.append(k)
	s.lmp.topics = keys
	if s.world and s.world.vm:
		for k: String in keys:
			s.world.vm._on_var_changed(k)


## Host: — the base's offers (LmpMode.offers) as "<q>_1" topics.
static func lmp_offer(s: Session) -> void:
	var names := []
	for q: String in LmpMode.offers(s.campaign, String(s.lmp.get("base", "")), String(s.lmp.get("last", ""))):
		names.append(q + "_1")
	_lmp_topics(s, names)
	s.sync_state()


## Host: a finished conversation `id` ("<q>_<n>") of `player`; true when it
## was one of the giver's quest topics. Rewards go to every
## player's own purse (_lmp_complete), so this does not run in the talker's.
static func lmp_briefing(s: Session, id: String, _player: int) -> bool:
	id = id.to_lower()
	var mine := false
	for k: String in s.lmp.get("topics", []):
		if k.get_slice(".", 2) == id:
			mine = true
	if not mine or id.length() < 3 or id[id.length() - 2] != "_":
		return false
	var q := id.substr(0, id.length() - 2)
	match id.right(1):
		"1": take_lmp(s, q)
		"2": _lmp_cancel(s, q)
		"3": _lmp_complete(s, q)
		_: return false
	return true


## Host: — quest `id` is taken: the offers go, the giver's topic
## is now its reject conversation <q>_2 (the record "<q>_2" becomes the
## server's quest), = q, the quest map is loaded and the saved state
## of its zone dropped, every player reads
## «lmp_quest_taken» (line 5) and, as the game zone is set up
## «lmp_zone_enabled» (line 8); the "briefing receive" lists
## apply (give quests: q.<q>.<q> and q.<q>.<q>.1 = 1).
static func take_lmp(s: Session, id: String) -> void:
	var q := get_quest(id)
	if q.is_empty():
		return
	s.lmp.quest = q.id
	s.lmp.last = q.id
	LmpMode.zone_var(s.state, q.id)
	s.state.side_quests[q.id] = "active"
	s.state.zones.erase(q.id)
	_lmp_topics(s, [q.id + "_2"])
	lmp_say(s, "quest_taken", q.id)
	lmp_say(s, "zone_enabled", q.id)   #  (line 8)
	for v in _list(q.reg.get("briefing receive", {}).get("give quests", [])):
		s.state.set_var(0, v.to_lower(), 1.0)
		if s.world and s.world.vm:
			s.world.vm._on_var_changed(v.to_lower())
	for it in _list(q.reg.get("briefing receive", {}).get("give items", "")):
		s.state.add_item(it.to_lower())
	s.sync_state()


## Host: — the quest is given back (its <q>_2 conversation):
## «lmp_quest_canceled», its quest vars back to 0 ((.., 1)), no
## quest, new offers.
static func _lmp_cancel(s: Session, id: String) -> void:
	var q := get_quest(id)
	if q.is_empty():
		return
	lmp_say(s, "quest_canceled", q.id)
	for v in _list(q.reg.get("briefing receive", {}).get("give quests", [])):
		s.state.set_var(0, v.to_lower(), 0.0)
	s.state.side_quests.erase(q.id)
	s.lmp.quest = ""
	LmpMode.zone_var(s.state, "")
	lmp_offer(s)


## Host: — the reward conversation <q>_3 ended: «lmp_quest_completed»
## and every connected player (server list) gets the two values of the
## "<q>_3" record (fields 0 and 1 of each player's record) —
## in the remake the quest's "briefing complete" experience for its hero and
## money for its own purse; no quest, new offers.
static func _lmp_complete(s: Session, id: String) -> void:
	var q := get_quest(id)
	if q.is_empty():
		return
	lmp_say(s, "quest_completed", q.id)
	s.state.side_quests[q.id] = "rewarded"
	var key := "q.%s.%s" % [q.id, q.id]
	s.state.set_var(0, key, 2.0)
	s.state.quests[q.id] = 2
	if s.world and s.world.vm:
		s.world.vm._on_var_changed(key)
	var idxs := [0] if s.players.is_empty() else []
	for p: Dictionary in s.players.values():
		idxs.append(int(p.index))
	for i: int in idxs:
		s.coop.with_purse(i, func() -> void: s.state.money += int(q.money))
		for g: Array in XpRules._party_split(s, float(q.exp), i, true):
			XpRules.gain(s, g[0], g[1], g[2])
	s.lmp.quest = ""
	LmpMode.zone_var(s.state, "")
	lmp_offer(s)


## textsLmp.res «lmp_<what>» with the quest's title, to every player.
static func lmp_say(s: Session, what: String, id := "") -> void:
	var t := GameData.text("string lmp_" + what).strip_edges()
	if t:
		s.broadcast({"t": "msg", "text": t.replace("%s", LmpMode.quest_title(id))})


## Host: the party accepts a quest; its offer briefing plays for everyone.
static func accept(s: Session, id: String) -> void:
	var q := get_quest(id)
	if q.is_empty() or not offers(s).has(q) or s.world.vm == null:
		return
	s.state.side_quests[q.id] = "active"
	s.world.vm.briefings.play_named(q.id + "_1", "sq.%s.1" % q.id)


## Host: a side-quest briefing finished.
static func briefing_done(s: Session, var_name: String) -> void:
	var parts := var_name.split(".")
	if parts.size() < 3:
		return
	var q := get_quest(parts[1])
	if q.is_empty():
		return
	match parts[2]:
		"1":
			for v in _list(q.reg.get("briefing receive", {}).get("give quests", [])):
				s.state.set_var(0, v.to_lower(), 1.0)
				s.world.vm._on_var_changed(v.to_lower())
			for it in _list(q.reg.get("briefing receive", {}).get("give items", "")):
				s.state.quest_items[it.to_lower()] = true
		"3":
			s.state.side_quests[q.id] = "rewarded"
			s.state.money += int(q.money)
			s.give_experience(float(q.exp), "side", 0)   # the original: player 0
			var key := "q.%s.%s" % [q.id, q.id]
			s.state.set_var(0, key, 2.0)
			s.state.quests[q.id] = 2
			s.world.vm._on_var_changed(key)   # the field screen's quest line
	s.sync_state()


## Host: all objectives met (or the quest script called QuestComplete).
static func finish(s: Session, id: String) -> void:
	id = id.to_lower()
	if s.state.side_quests.get(id, "") != "active":
		return
	s.state.side_quests[id] = "done"
	s.state.set_var(0, "q.%s.%s.1" % [id, id], 2.0)
	s.world.vm._on_var_changed("q.%s.%s.1" % [id, id])   # «combat_complete_subobj» line
	if not s.lmp.is_empty() and String(s.lmp.get("quest", "")) == id:
		# the server's quest record goes and the
		# giver's only topic is its reward conversation "<q>_3".
		_lmp_topics(s, [id + "_3"])
		LmpMode.zone_var(s.state, "")   # no server quest: z.MPGame1 = 1
		s.sync_state()


## Host, in a village: plays the reward briefing of a finished side quest.
static func check_rewards(s: Session) -> void:
	if s.world == null or String(s.world.zone.get("type", "")) != "brief" or s.world.vm == null:
		return
	for id: String in s.state.side_quests:
		if s.state.side_quests[id] == "done":
			var z := zone_of(s, get_quest(id))
			# LMP: the reward is a topic of the base's giver (finish, lmp_briefing).
			if s.lmp.is_empty() and String(s.campaign.zone(z).get("allod", "")) == String(s.world.zone.get("allod", "")):
				s.world.vm.briefings.play_named(id + "_3", "sq.%s.3" % id)
				return


## Host, while building a zone: the active side quest that plays here, if any.
static func active_in(s: Session, zone_id: String) -> String:
	for id: String in s.state.side_quests:
		if s.state.side_quests[id] == "active" and zone_of(s, get_quest(id)) == zone_id:
			return id
	return ""


## Host: adds the quest map's units to the world (script is merged by the VM).
static func spawn_units(w: GameWorld, id: String) -> void:
	var mob := EIMob.load_bytes(GameData.read_file("maps/%s.mob" % id))
	if mob == null:
		return
	for o: Dictionary in mob.objects:
		if o.kind == "UNIT" and not w.units.has(int(o.get("nid", -1))):
			w.spawn_unit(o)
	w.add_mob_objects("%s.mob" % id)
	w.set_meta("quest_mob", id)
	w.set_meta("quest_script", mob.script_text)


static func _list(v) -> PackedStringArray:
	var out := PackedStringArray()
	for x in (v if v is Array else [v]):
		if String(x).strip_edges():
			out.append(String(x).strip_edges())
	return out


## Journal text of any quest: texts.res "quest <id>", else the quest maps.
static func quest_doc(q: String) -> String:
	var t := GameData.text("quest " + q)
	return t if t else text("quest " + q)
