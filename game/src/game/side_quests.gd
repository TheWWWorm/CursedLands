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
	for f in DirAccess.get_files_at(dir):
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


## Host, in a village: plays the reward briefing of a finished side quest.
static func check_rewards(s: Session) -> void:
	if s.world == null or String(s.world.zone.get("type", "")) != "brief" or s.world.vm == null:
		return
	for id: String in s.state.side_quests:
		if s.state.side_quests[id] == "done":
			var z := zone_of(s, get_quest(id))
			if String(s.campaign.zone(z).get("allod", "")) == String(s.world.zone.get("allod", "")):
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
