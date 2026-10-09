class_name CoopProgress
extends Node
const TrainingRefund := preload("res://src/game/training_refund.gd")
const PartyProgress := preload("res://src/game/coop_party_progress.gd")
const GuestRoles := preload("res://src/game/coop_guest_roles.gd")
## Remake-only co-op feature: bring your own hero, shared progression.
## (Not in the original: the original network game played separate LMP maps with
## network characters;.)
##
## Joining: the client picks one of its own saves (or a new campaign hero).
## Its main hero (attributes, skills, perks, experience, worn items, weapons,
## belt, spells) goes to the host and plays in the host's world in place of a
## fresh co-op hero. The host's world drives everything; the client's own
## campaign is only credited:
## - Quest credit (q.<zone>.<quest>[.<objective>]): a change the host makes
##   is credited to the joiner when, in the joiner's own game,
##     1. that quest is not finished (not done, not failed) — "ahead" players
##        get nothing extra, they just help;
##     2. the joiner has reached the place: they have been to (or unlocked) the
##        quest's zone, or the zone the party is playing now counts as reached
##        for them (see below) — "behind" players get nothing;
##     3. it moves them forward (the host's new value is higher than theirs,
##        or they had the host's old value). A quest the host already had open
##        is given to the joiner along with its first credited change.
## - Other story vars (conversations, zone flags, script flags of the zone):
##   credited while the current zone counts as reached and only if the joiner
##   had exactly the host's old value (same point).
## - A zone counts as reached when the joiner's game has visited it or opened
##   it on the travel map (z.<zone> ≥ 1), or when the party walks into a
##   village straight from a zone that counted as reached. A player present
##   for all credited progress in the preceding zone also follows scripted
##   field transfers, which need not write a separate travel-map unlock.
## - Zone map state (dead units, gates, chests, the zone script) is copied
##   for a zone only when the joiner was there from the party's arrival,
##   was not ahead in that zone's quests, and every change made there was
##   credited to them.
## - Quest items and village side quests found / changed in a reached zone
##   follow the same rules.
## - Always carried back: the hero itself (experience, skills learned, perks,
##   equipment, belt, spells) and the joiner's own purse and bag: brought from
##   its save, used and filled by its own trades, loot and rewards in the
##   host's world (with_purse), kept apart from the host's.
## Mercenary hiring vars, the campaign clock and engine vars are not credited
## (the hirer owns the mercenary).
##
## Progress packages: the host sends each joiner a cumulative package at every
## zone change, host save, after quest steps and every 15 s while something
## changed (and when the host leaves to the menu). The client merges it into a
## copy of the save it brought and writes the slot "coop_<host>_<date>", named
## "Co-op: <host>" (the Load screen's date column has the date; the name
## column is 178 px and clips); the save it brought is never touched.
##
## Host saves keep the entries (CampaignState.coop "host"), so a later session
## of the save goes on with the same players; packages carry a tally id and
## number, and a merged save remembers the last one it got ("applied"), so a
## joiner coming back with its co-op save is credited from that save on; its
## purse and bag are carried whole, never added up.

const NEW := "new"
## Client: "" = the co-op class hero (no progress kept), NEW = a new campaign
## hero, else the save slot whose hero is brought.
static var bring_slot := ""

const SEND_EVERY := 15.0
const SCALE_EVERY := 1.0

var session: Session

# ---------------------------------------------------------------- host state
var _pending := {}      # pid -> sanitized bring data
## lowercase player name -> entry (see _new_entry)
var joiners := {}
var _zone := ""         # zone the entries' in_sync refers to
var _qi_last := {}      # host quest items at the start of the period
var _sq_last := {}      # host side quests at the start of the period
var _loading := false
var _send_t := SEND_EVERY
var _scale_t := 0.0
var _sent_hash := {}
var _swap := {}         # with_purse: the campaign's purse while a joiner's stands in
## LMP (Session.lmp): player slot -> {idx, purse: {money, items}} — in the original's
## network game every player has its own money and bag; the
## host's own (slot 0) are the state's.
var lmp_purses := {}

# ---------------------------------------------------------------- client state
var _origin_slot := ""   # the save brought ("" = new hero)
var _origin_new := false
var _merged_slot := ""
var _merged_name := ""
var _preview_zone := ""   # one preview per visited location, independent of save frequency
var _preview_serial := 0
## Client: the last merged save written (tests read it).
var last_merged := ""
var merged_count := 0    # packages merged so far (NetStatus.leave waits for one more)


func _ready() -> void:
	name = "CoopProgress"
	CampaignState.watch = _on_var
	multiplayer.peer_disconnected.connect(_on_peer_gone)


func _exit_tree() -> void:
	if CampaignState.watch.is_valid() and CampaignState.watch.get_object() == self:
		CampaignState.watch = Callable()


## A peer that can still be sent to (a client may drop and come back while
## the host is busy; ENet then has no peer object for the old id).
static func peer_alive(mp: MultiplayerAPI, pid: int) -> bool:
	if pid <= 0 or mp == null or not mp.has_multiplayer_peer() or not pid in mp.get_peers():
		return false
	var enet := NetSim.enet_of(mp)
	if enet == null:
		return true
	var p := enet.get_peer(pid)
	return p != null and p.get_state() == ENetPacketPeer.STATE_CONNECTED


func _host_online() -> bool:
	return session != null and session.multiplayer_game and session.is_host


func _physics_process(dt: float) -> void:
	if not _host_online() or session.world == null or session.loading_game or get_tree().paused:
		return
	_scale_t -= dt
	if _scale_t <= 0.0:
		_scale_t = SCALE_EVERY
		# The original multiplayer game (Session.lmp) scales nothing: its LMP maps bring their own monsters.
		MobScaling.apply(session.world, session.players.size() if session.lmp.is_empty() else 1)
	if joiners.is_empty():
		return
	_send_t -= dt
	if _send_t <= 0.0:
		_send_t = SEND_EVERY
		send_all()


# ================================================================ client

## Client, on connecting (before the hello): send the brought hero and the
## save's story state.
func client_hello() -> void:
	if bring_slot.is_empty():
		return
	var st := _load_origin()
	if st == null:
		session.message.emit(RemakeText.t("Save '%s' not found: joining with a co-op hero.") % bring_slot)
		return
	_origin_slot = "" if bring_slot == NEW else bring_slot
	_origin_new = bring_slot == NEW
	var view := {}
	for k: String in st.vars:
		if k.begins_with("0:"):
			view[k.substr(2)] = float(st.vars[k])
	var seq := {}
	var applied = st.coop.get("applied", {})
	if applied is Dictionary:
		for id in applied:
			if applied[id] is Dictionary:
				seq[String(id)] = int(_num(applied[id].get("seq", 0), 0.0))
	var bag := main_bag(st)
	_rpc_bring.rpc_id(1, {"campaign_id": st.campaign_id, "hero": main_hero(st), "vars": view, "visited": st.visited.keys(),
		"side_quests": st.side_quests, "quest_items": st.quest_items, "zone": st.current_zone, "seq": seq,
		"money": int(bag.money), "items": bag.items, "party_context": PartyProgress.capture(st)})


## The campaign state the client brought (a fresh one for a new hero).
func _load_origin() -> CampaignState:
	if bring_slot == NEW:
		return fresh_state()
	return CampaignState.load_from(SaveInfo.path(bring_slot))


## A new campaign as Session.new_campaign starts it (Zak, at the ruins).
static func fresh_state() -> CampaignState:
	var st := CampaignState.new()
	st.ensure_hero(0, "Human Hero")
	st.visited["gz1g"] = true
	return st


## Base campaign substitutions leave Zak in the original party. LiA's named
## parties are Kir's normal chapter progression; only Shaina is temporary
## (bz5h returns explicitly to FSusel).
static func main_party(st: CampaignState) -> String:
	if st.campaign_id != CampaignProfile.ASTRAL:
		return ""
	if st.current_party == "Shaina" and st.parties.has("FSusel"):
		return "FSusel"
	return st.current_party


## The save's protagonist, including completed LiA chapter progression.
static func main_hero(st: CampaignState) -> Dictionary:
	var party := main_party(st)
	var roster: Array = st.heroes.get(0, []) if st.current_party == party else st.parties.get(party, [])
	return roster[0] if not roster.is_empty() and roster[0] is Dictionary else {}


## The same protagonist's purse and bag. `items` is the save's own array.
static func main_bag(st: CampaignState) -> Dictionary:
	var party := main_party(st)
	if st.current_party == party:
		return {"money": st.money, "items": st.items}
	var b: Dictionary = st.party_bags.get_or_add(party, {"items": [], "money": 0})
	return {"money": int(b.get("money", 0)), "items": b.get_or_add("items", [])}


@rpc("authority", "call_remote", "reliable")
func _rpc_package(pkg: Dictionary) -> void:
	var st: CampaignState = null
	if _origin_slot:
		st = CampaignState.load_from(SaveInfo.path(_origin_slot))
	elif _origin_new:
		st = fresh_state()
	if st == null or not CampaignProfile.matches(pkg.get("campaign_id", CampaignProfile.ORIGINAL), st.campaign_id):
		return
	merge(st, pkg)
	if _merged_slot.is_empty():
		var d := Time.get_datetime_dict_from_system()
		var host := String(pkg.get("host", "host"))
		var safe := host.to_lower().validate_filename().replace(" ", "_").left(16)
		_merged_slot = "coop_%s_%04d%02d%02d_%02d%02d%02d" % [safe, d.year, d.month, d.day, d.hour, d.minute, d.second]
		_merged_name = RemakeText.t("Co-op: %s") % host
	var err := st.save(SaveInfo.path(_merged_slot))
	if err != OK:
		session.message.emit(RemakeText.t("Co-op progress could not be saved (%d).") % err)
		return
	var allod := ""
	if session.campaign:
		allod = String(session.campaign.zones.get(st.current_zone, {}).get("allod", "")).to_lower()
	SaveInfo.write(_merged_slot, st.get_var(0, "gtime"), allod, st.current_zone, _merged_name)
	_refresh_preview(st.current_zone)
	if last_merged.is_empty():
		session.message.emit(RemakeText.t("Your progress is saved as \"%s\".") % _merged_name)
	last_merged = _merged_slot
	merged_count += 1


## Progress still saves at every package. Re-reading a 4K viewport for its
## thumbnail every few seconds stalls the client; refresh the preview only
## when its saved location changes. Never photograph a different host zone
## for an origin whose story progress did not move there.
func _refresh_preview(zone: String) -> void:
	if zone.is_empty() or zone == _preview_zone or zone != session.zone_id:
		return
	_preview_zone = zone
	_preview_serial += 1
	var serial := _preview_serial
	var valid := func() -> bool:
		return is_instance_valid(session) and serial == _preview_serial \
			and session.zone_id == zone and not session.loading_game and not session._remote_loading
	var written := await SaveInfo.write_shot(_merged_slot, session.get_viewport(), valid)
	if not written and serial == _preview_serial:
		_preview_zone = ""   # a cancelled/loading capture may retry on the next package


## Client: brought its own hero (progress packages come back to it).
func brings() -> bool:
	return _origin_slot != "" or _origin_new


## Applies a progress package to the client's own campaign state.
static func merge(st: CampaignState, pkg: Dictionary) -> void:
	if not CampaignProfile.matches(pkg.get("campaign_id", CampaignProfile.ORIGINAL), st.campaign_id):
		return
	var move: Dictionary = pkg.get("move", {}) if pkg.get("move") is Dictionary else {}
	var context := PartyProgress.read(pkg.get("party_context"))
	if context != null and move and campaign_zone_ok(String(move.get("zone", ""))):
		PartyProgress.apply(st, context)
	else:
		context = null
	# Story vars credited to this player.
	var cv: Dictionary = pkg.get("vars", {}) if pkg.get("vars") is Dictionary else {}
	for k in cv:
		var key := String(k)
		var v := _num(cv[k], 0.0)
		st.set_var(0, key, v)
		var parts := key.split(".")
		if parts.size() == 3 and parts[0] == "q":
			var q := parts[2]
			if is_equal_approx(v, 2.0):
				st.quests[q] = 2
			elif v >= 3.0:
				if st.quests.get(q, 0) != 2:
					st.quests[q] = 3
			elif v >= 1.0 and not st.quests.has(q):
				st.quests[q] = 1
	for z in (pkg.get("visited", []) if pkg.get("visited") is Array else []):
		st.visited[String(z)] = true
	var sq: Dictionary = pkg.get("side_quests", {}) if pkg.get("side_quests") is Dictionary else {}
	for id in sq:
		if String(sq[id]).is_empty():
			st.side_quests.erase(id)
		else:
			st.side_quests[String(id)] = String(sq[id])
	var qi: Dictionary = pkg.get("quest_items", {}) if pkg.get("quest_items") is Dictionary else {}
	for n in qi:
		if bool(qi[n]):
			st.quest_items[String(n)] = true
		else:
			st.quest_items.erase(String(n))
	var zs: Dictionary = pkg.get("zones", {}) if pkg.get("zones") is Dictionary else {}
	for z in zs:
		if zs[z] is Dictionary:
			st.zones[String(z)] = (zs[z] as Dictionary).duplicate(true)
	# The hero, as it is in the host's world.
	# LiA normally progresses through named protagonist parties. Only a
	# temporary substitute leaves the imported hero in a waiting party.
	var hero_party := main_party(st)
	var h := sanitize_hero(pkg.get("hero", {}))
	if context != null and move:
		# The context already combines personal progress with the authored
		# chapter body, waiting-party positions and companion ownership.
		h = main_hero(st).duplicate(true)
	if not h.is_empty():
		var roster: Array = st.heroes.get_or_add(0, []) if st.current_party == hero_party else st.parties.get_or_add(hero_party, [])
		var old: Dictionary = roster[0] if not roster.is_empty() and roster[0] is Dictionary else {}
		h.name = String(old.get("name", pkg.get("orig_name", h.name)))
		if old.has("unit_name"):
			h.unit_name = old.unit_name
		# Where the hero stands: the host's world when the save moves there,
		# else where it was in the joiner's own game.
		var src: Dictionary = pkg.hero if move and context == null and pkg.get("hero") is Dictionary else old
		for k in ["pos", "mana", "gait"]:
			if src.has(k):
				h[k] = src[k]
			else:
				h.erase(k)
		if roster.is_empty():
			roster.append(h)
		else:
			roster[0] = h
	# The joiner's own purse and bag as they are in the host's world (brought
	# along, then spent / filled by its own trades, loot and rewards).
	var purse: Dictionary = pkg.get("purse", {}) if pkg.get("purse") is Dictionary else {}
	if purse.has("money"):
		var money := maxi(0, int(_num(purse.money, 0.0)))
		var items := _items(purse.get("items", []))
		if st.current_party == hero_party:
			st.money = money
			st.items = items
		else:
			var b: Dictionary = st.party_bags.get_or_add(hero_party, {"items": [], "money": 0})
			b.money = money
			b.items = items
	if not h.is_empty():
		CampaignState.cap_belt(h, st._bag(hero_party).items)   # the belt's four; extras to its bag
	var sid := String(pkg.get("sid", ""))
	if sid:
		var applied: Dictionary = st.coop.get_or_add("applied", {}) if st.coop.get("applied") is Dictionary else {}
		st.coop.applied = applied
		applied[sid] = {"seq": int(_num(pkg.get("seq", 0), 0.0))}
	if move and campaign_zone_ok(String(move.get("zone", ""))):
		st.current_zone = String(move.zone)
		st.world_time = clampf(_num(move.get("world_time", st.world_time), st.world_time), 0.0, 23.999)
		st.day = maxi(1, int(_num(move.get("day", st.day), st.day)))


static func campaign_zone_ok(id: String) -> bool:
	return not id.is_empty() and id.length() < 32 and id.is_valid_filename()


# ================================================================ host

## Any peer -> host: the hero and the story state the joiner brings.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_bring(data: Dictionary) -> void:
	if not session.is_host or not CampaignProfile.matches(data.get("campaign_id", CampaignProfile.ORIGINAL), session.state.campaign_id):
		return
	var pid := multiplayer.get_remote_sender_id()
	var h := sanitize_hero(data.get("hero", {}))
	if h.is_empty():
		return
	var view := {}
	var vars = data.get("vars", {})
	if vars is Dictionary:
		for k in vars:
			if k is String and k.length() < 128 and (vars[k] is float or vars[k] is int):
				view[k] = float(vars[k])
	var visited := {}
	for z in (data.get("visited", []) if data.get("visited") is Array else []):
		if z is String and campaign_zone_ok(z):
			visited[z] = true
	var sq := {}
	if data.get("side_quests") is Dictionary:
		for id in data.side_quests:
			sq[String(id)] = String(data.side_quests[id])
	var qi := {}
	if data.get("quest_items") is Dictionary:
		for n in data.quest_items:
			qi[String(n)] = true
	var seq := {}
	if data.get("seq") is Dictionary and data.seq.size() < 64:
		for id in data.seq:
			seq[String(id)] = int(_num(data.seq[id], -1.0))
	for k in ["unit_name", "pos", "mana"]:   # a fresh unit in the host's world
		h.erase(k)
	_pending[pid] = {"hero": h, "vars": view, "visited": visited, "side_quests": sq, "quest_items": qi, "seq": seq,
		"purse": {"money": clampi(int(_num(data.get("money", 0), 0.0)), 0, 99999999), "items": _items(data.get("items", []))}}
	var context := PartyProgress.read(data.get("party_context"))
	if context != null:
		_pending[pid].party_context = PartyProgress.capture(context)
	CampaignState.cap_belt(h, _pending[pid].purse.items)   # the belt's four; extras to its own bag


## A changed lobby name may reclaim its own absent character when the
## brought progress proves the latest package of exactly one host tally.
## Names, prototype/stats equality and uncredited original saves are not
## identity proof. An active, stale, ambiguous or replaced slot stays put.
func renamed_slot(pid: int, player_name: String) -> int:
	var key := player_name.strip_edges().to_lower()
	if not session.is_host or key.is_empty() or joiners.has(key) or not _pending.has(pid):
		return -1
	var seq: Dictionary = _pending[pid].seq
	var previous := ""
	for candidate: String in joiners:
		var sid := String(joiners[candidate].get("sid", ""))
		if not sid.is_empty() and seq.has(sid):
			if not previous.is_empty():
				return -1
			previous = candidate
	if previous.is_empty():
		return -1
	var e: Dictionary = joiners[previous]
	var idx := int(e.get("idx", -1))
	var current := int(e.get("seq", 0))
	var roster: Array = session.state.heroes.get(idx, [])
	if idx <= 0 or current <= 0 or int(seq.get(String(e.sid), -1)) != current \
			or bool(e.get("active", false)) or session.players_include(idx) or roster.is_empty() \
			or String(roster[0].get("name", "")).strip_edges().to_lower() != previous:
		return -1
	for other: String in joiners:
		if other != previous and int(joiners[other].get("idx", -1)) == idx:
			return -1
	joiners.erase(previous)
	_sent_hash.erase(previous)
	e.name = player_name
	joiners[key] = e
	return idx


## Host: a player said hello and got slot `idx` (before its hero is made).
func on_hello(pid: int, idx: int, player_name: String) -> void:
	if not session.is_host or idx == 0:
		return
	var key := player_name.strip_edges().to_lower()
	var data: Dictionary = _pending.get(pid, {})
	_pending.erase(pid)
	if joiners.has(key):
		# The same player again in this session (reconnect): it keeps its hero
		# in the host's world and what was credited so far.
		var e: Dictionary = joiners[key]
		_sent_hash.erase(key)   # its client may have restarted: send the package again
		if not data.is_empty() and int(e.get("seq", 0)) > 0 \
				and int((data.seq as Dictionary).get(String(e.get("sid", "")), -1)) >= int(e.seq):
			# It brings a save made from every package of this tally (its
			# co-op save): that save is its game now, the tally goes on from it.
			for k in ["vars", "visited", "side_quests", "quest_items"]:
				e[k] = data[k]
			e.credits = {"vars": {}, "visited": {}, "side_quests": {}, "quest_items": {}, "zones": {}}
			if data.has("party_context"):
				e.party_context = data.party_context
		if not e.has("party_context") and data.has("party_context"):
			e.party_context = data.party_context
		e.pid = pid
		e.idx = idx
		e.active = true
		e.present = false
		e.clean = false
		e.in_sync = session.world != null and _reached(e, session.zone_id)
		if not e.has("purse") and not data.is_empty():
			e.purse = data.purse
		if not session.state.heroes.has(idx):
			session.state.heroes[idx] = [(e.hero_in as Dictionary).duplicate(true)]
		_send_t = minf(_send_t, 1.0)
		return
	if data.is_empty():
		return
	var e := {
		"name": player_name, "idx": idx, "pid": pid, "active": true,
		"orig_name": String(data.hero.name), "hero_in": data.hero,
		"vars": data.vars, "visited": data.visited, "side_quests": data.side_quests,
		"quest_items": data.quest_items,
		"credits": {"vars": {}, "visited": {}, "side_quests": {}, "quest_items": {}, "zones": {}},
		"in_sync": false, "clean": false, "present": false,
		# Its own gold and bag in the host's world (with_purse).
		"purse": data.purse,
		# This tally's id and the number of packages sent (a save merged from
		# all of them can carry on from itself, see the reconnect above).
		"sid": "%08x%08x" % [randi(), Time.get_ticks_usec() & 0xffffffff], "seq": 0,
	}
	e.hero_in.name = player_name.strip_edges() if player_name.strip_edges() else String(e.orig_name)
	if data.has("party_context"):
		e.party_context = data.party_context
	joiners[key] = e
	session.state.coop.get(GuestRoles.KEY, {}).erase(idx)
	if session.world:
		# Late join: the hero comes in place of any old one of this slot.
		_drop_old_units(idx)
		e.in_sync = _reached(e, session.zone_id)
	session.state.heroes[idx] = [(e.hero_in as Dictionary).duplicate(true)]
	session.message.emit(RemakeText.t("%s brings their own hero.") % player_name)


func _drop_old_units(idx: int) -> void:
	for u: GameUnit in session.world.units.values().duplicate():
		if int(u.get_meta("orphan_of", -1)) == idx and u.has_meta("hero") and not u.get_meta("hero").has("merc"):
			session.world.remove_unit(u)
			session.broadcast({"t": "remove", "uid": u.uid})


## Host, Session.new_campaign: the brought heroes join the new state.
func campaign_started() -> void:
	for e: Dictionary in joiners.values():
		if e.active:
			session.state.heroes[int(e.idx)] = [(e.hero_in as Dictionary).duplicate(true)]


## Host, Session.enter_zone (world and party built, script not started yet).
func zone_entered(id: String) -> void:
	if joiners.is_empty():
		_zone = id
		return
	if not _loading:
		_settle()
	for e: Dictionary in joiners.values():
		if not _loading and e.active and _zone and e.clean and e.in_sync and e.present:
			e.credits.zones[_zone] = (session.state.zones.get(_zone, {}) as Dictionary).duplicate(true)
		var was: bool = e.in_sync and not _loading and _zone != ""
		# Original chapter scripts can LeaveToZone without setting z.<id>
		# (LiA's bz1h -> gz1h prison transfer does exactly that). A guest who
		# shared the preceding progress must carry on with the same party.
		# Late arrivals, missed/conflicting changes and host save loads have
		# no such continuity; their own reached-zone rules still apply.
		var shared_travel: bool = was and e.clean and e.present
		e.in_sync = e.active and (_reached(e, id) or shared_travel \
			or (was and String(session.campaign.zone(id).get("type", "")) == "brief"))
		e.present = e.active
		e.clean = e.in_sync and not _ahead_in(e, id)
		if e.in_sync and not e.visited.has(id):
			e.visited[id] = true
			e.credits.visited[id] = true
	_loading = false
	_zone = id
	_qi_last = session.state.quest_items.duplicate()
	_sq_last = session.state.side_quests.duplicate()
	send_all.call_deferred()


## Host, Session.save_game before the state is written: the joiners get
## their packages and their entries go into the save (CampaignState.coop),
## so a later session of this save goes on with the same players.
func before_save() -> void:
	if joiners.is_empty():
		return
	_settle()
	send_all()
	var saved := joiners.duplicate(true)
	for e: Dictionary in saved.values():
		e.pid = 0
		e.active = false
	session.state.coop["host"] = {"joiners": saved, "zone": _zone,
		"qi": _qi_last.duplicate(), "sq": _sq_last.duplicate()}


## Host, Session.load_game before `next` replaces the state: entries go back
## to the save's moment when the save has them (CampaignState.coop), else
## keep their credits (and the purse / bag baseline moves to the loaded
## state). Players in the save who are not here wait for their rejoin.
func before_load(_slot: String, next: CampaignState) -> void:
	var snap: Dictionary = next.coop.get("host", {}) if next.coop.get("host") is Dictionary else {}
	var saved: Dictionary = snap.get("joiners", {}) if snap.get("joiners") is Dictionary else {}
	if joiners.is_empty() and saved.is_empty():
		return
	if not joiners.is_empty():
		_settle()
	# A save from before a proven rename still uses the old alias. Follow
	# the unique tally id, so loading it rolls back the same character/bag
	# without resurrecting a second entry with the former name.
	for key: String in joiners:
		var live: Dictionary = joiners[key]
		if not bool(live.get("active", false)) or saved.has(key):
			continue
		var sid := String(live.get("sid", ""))
		if sid.is_empty():
			continue
		var matches := saved.keys().filter(func(k): return saved[k] is Dictionary and String(saved[k].get("sid", "")) == sid)
		var live_matches := joiners.values().filter(func(e): return String(e.get("sid", "")) == sid)
		if matches.size() != 1 or live_matches.size() != 1:
			continue
		var old: Dictionary = saved[matches[0]]
		if int(old.get("idx", -1)) != int(live.idx):
			continue
		old = old.duplicate(true)
		old.name = live.name
		saved.erase(matches[0])
		saved[key] = old
	for key in saved:
		if not joiners.has(key) and saved[key] is Dictionary:
			var e: Dictionary = (saved[key] as Dictionary).duplicate(true)
			e.pid = 0
			e.active = false
			e.present = false
			e.clean = false
			e.in_sync = false
			joiners[key] = e
	for key in joiners:
		var e: Dictionary = joiners[key]
		var cur := e
		if saved.has(key):
			var old: Dictionary = (saved[key] as Dictionary).duplicate(true)
			old.pid = e.pid
			old.active = e.active
			joiners[key] = old
			e = old
		if not e.active:
			continue
		var roster: Array = session.state.heroes.get(int(e.idx), [])
		if e.active and not next.heroes.has(int(e.idx)):
			next.heroes[int(e.idx)] = [(roster[0] if not roster.is_empty() else cur.hero_in as Dictionary).duplicate(true)]
	if snap.has("zone"):
		_zone = snap.zone
		_qi_last = snap.qi
		_sq_last = snap.sq
	_loading = true


## Host leaving (Esc menu → main menu): last packages, sent at once.
func flush() -> void:
	if not _host_online() or joiners.is_empty():
		return
	_sent_hash.clear()
	send_all()
	var enet := NetSim.enet_of(multiplayer)
	if enet and enet.host:
		enet.host.flush()


func _on_peer_gone(pid: int) -> void:
	_pending.erase(pid)
	for e: Dictionary in joiners.values():
		if int(e.pid) == pid:
			e.active = false
			e.pid = 0
			e.clean = false
			e.present = false


# ---------------------------------------------------------------- joiners' purses

## The joiner entry with its own purse for player slot `player` ({} = none:
## the host's party and co-op class heroes use the campaign's purse and bag).
func purse_entry(player: int) -> Dictionary:
	if player <= 0:
		return {}
	if session and not session.lmp.is_empty():
		return lmp_purses.get_or_add(player, {"idx": player, "purse": {"money": 0, "items": []}})
	for e: Dictionary in joiners.values():
		if int(e.idx) == player and e.get("purse") is Dictionary:
			return e
	return GuestRoles.purse(session.state, player) if session else {}


## Host: runs `f` with player `player`'s own purse and bag standing in for the
## campaign's (state.money / state.items), so trades, loot, rewards and
## equipment changes of a joiner who brought its hero use its own gold and
## bag (the original: money and bag are per player in a network game, player
## LMP loot goes to whoever takes it). Nothing of it reaches the
## host's purse or save (only its joiner entry).
## `found`: what `f` adds to the purse and bag is a find from the world
## (loot, theft, a conversation's or a script's reward): with the option
## "coop_share_loot" the other players get a copy (share_found).
func with_purse(player: int, f: Callable, found := false) -> Variant:
	if not _swap.is_empty() and int(_swap.e.idx) != player:
		# A shared dialogue can be closed by a different peer from its
		# speaker. Commit the outer owner's bag before entering that
		# speaker's scope, then resume the outer command with its own bag.
		var outer := _swap
		var state := session.state
		if not outer.get("shared", false):
			outer.e.purse.money = state.money
			outer.e.purse.items = state.items
			state.money = int(outer.money)
			state.items = outer.items
		_swap = {}
		var nested = with_purse(player, f, found)
		outer.money = state.money
		outer.items = state.items
		# A party operation can change a class guest from the shared bag to
		# a temporary private bag (or back) while this command is unwinding.
		var resumed := purse_entry(int(outer.e.idx))
		outer.shared = resumed.is_empty()
		if not resumed.is_empty():
			outer.e = resumed
			state.money = int(resumed.purse.money)
			state.items = resumed.purse.items
		_swap = outer
		return nested
	var e := purse_entry(player) if _swap.is_empty() else {}
	if e.is_empty() and (player <= 0 or not _swap.is_empty()):
		if not found or not sharing():
			return f.call()
		var before := _purse_now(player)
		var r0 = f.call()
		_found(before)
		return r0
	var st := session.state
	var shared := e.is_empty()
	if shared: e = {"idx":player}
	_swap = {"e": e, "money": st.money, "items": st.items, "shared":shared}
	if not shared:
		st.money = int(e.purse.get("money", 0))
		st.items = e.purse.get_or_add("items", [])
	var before := _purse_now(player) if found and sharing() else {}
	var r = f.call()
	if not before.is_empty():
		_found(before)
	if not _swap.get("shared", false):
		_swap.e.purse.money = st.money
		_swap.e.purse.items = st.items
		st.money = int(_swap.money)
		st.items = _swap.items
	_swap = {}
	session.mark_dirty()
	_flush_shared()
	return r


## Authored party operations belong to the campaign's protagonist. A guest
## may close the dialogue while its personal bag is temporarily installed.
## Keep that guest's rewards, restore the host bag for the party operation,
## then resume the outer command with the same guest bag. The saved host
## bag must now be the newly selected party's, not the one we started with.
func with_campaign_purse(f: Callable) -> Variant:
	return with_purse(0, f)


# ---------------------------------------------------------------- shared loot

## Remake co-op option "coop_share_loot" (host, default ; not in the original
## whose network game gives a find to whoever takes it, to that
## player only): a find from the world — a body or chest looted, a theft, the
## money and items of a conversation's or a script's reward — reaches every
## other connected player's own purse and bag as an identical copy (the same
## item strings, so the same wear, charge and enchantment; the same money).
## Players who share a bag (the host and co-op class heroes use the
## campaign's) get one copy between them, none when it is the finder's own.
## Not copied: trades, the belt and equipment moves, broken items, anything
## a player had already. Quest items are not copied either: they go to the
## campaign's one quest item list (CampaignState.add_item), which every
## player has and which HaveItem / EraseQuestItem / levers read, so a quest
## goes on whoever holds it. Copies land in the host's state and the joiners'
## entries, so saves and the joiners' progress packages keep them. Not in
## the original multiplayer game (Session.lmp).
const SHARE_OPTION := "coop_share_loot"
var _share_queue: Array = []   # finds waiting for a purse swap to end


func sharing() -> bool:
	return _host_online() and session.lmp.is_empty() and session.players.size() > 1 \
		and GameData.option(SHARE_OPTION) != 0


## The purse in session.state right now, for a find by `player` (-1: the
## party, a script's reward).
func _purse_now(player: int) -> Dictionary:
	var key := "campaign"
	if not _swap.is_empty() and not _swap.get("shared", false):
		key = "p%d" % int(_swap.e.idx)
	elif not purse_entry(player).is_empty():
		key = "p%d" % player
	return {"player": player, "key": key, "money": session.state.money, "items": session.state.items.duplicate()}


## What came into the purse since `before` (as a multiset), queued for sharing.
func _found(before: Dictionary) -> void:
	var left := {}
	for x in before.items:
		left[x] = int(left.get(x, 0)) + 1
	var got := []
	for x in session.state.items:
		if int(left.get(x, 0)) > 0:
			left[x] -= 1
		else:
			got.append(x)
	var money := maxi(0, session.state.money - int(before.money))
	if not got.is_empty() or money > 0:
		share_found(int(before.player), got, money, String(before.key))


## Host: player `player` (-1 the party) found `items` and `money`, which went
## to the purse `key` ("campaign" or "p<slot>"); the others get copies.
func share_found(player: int, items: Array, money: int, key := "") -> void:
	if not sharing():
		return
	if key.is_empty():
		key = "campaign" if purse_entry(player).is_empty() else "p%d" % player
	_share_queue.append({"player": player, "items": items.duplicate(), "money": money, "key": key})
	if _swap.is_empty():
		_flush_shared()


func _flush_shared() -> void:
	if _share_queue.is_empty() or not _swap.is_empty():
		return
	var q := _share_queue
	_share_queue = []
	for f: Dictionary in q:
		_give_copies(f)
	session.sync_state()


func _give_copies(f: Dictionary) -> void:
	var given := {String(f.key): true}
	var who := ""
	for p: Dictionary in session.players.values():
		if int(p.index) == int(f.player):
			who = String(p.name)
	for p: Dictionary in session.players.values():
		var idx := int(p.index)
		if idx == int(f.player):
			continue
		var e := purse_entry(idx)
		var key := "campaign" if e.is_empty() else "p%d" % idx
		if key == String(f.key):
			continue   # the finder's own bag (shared with it)
		if not given.has(key):
			given[key] = true
			if e.is_empty():
				session.state.items.append_array(f.items)
				session.state.money += int(f.money)
			else:
				(e.purse.get_or_add("items", []) as Array).append_array(f.items)
				e.purse.money = int(e.purse.get("money", 0)) + int(f.money)
		session.broadcast({"t": "loot_copy", "to": idx, "who": who, "items": f.items, "money": f.money})
	session.mark_dirty()


## Player's line for a copy it got (Session._on_event "loot_copy").
static func copy_text(event: Dictionary) -> String:
	var parts := []
	for it in event.get("items", []):
		parts.append(Items.log_text(String(it)))
	var money := int(event.get("money", 0))
	if money > 0:
		var fmt := GameData.text("string format_money").strip_edges()
		parts.append(fmt % money if "%d" in fmt else "%s (%d)" % [fmt, money])
	var what := ", ".join(parts)
	var who := String(event.get("who", ""))
	if who.is_empty():
		return RemakeText.t("The party got %s — you get a copy too.") % what
	return RemakeText.t("%s found %s — you get a copy too.") % [who, what]


## A purse is standing in for the campaign's right now (Session.sync_state waits).
func purse_active() -> bool:
	return not _swap.is_empty()


## Player `player`'s bag (its own as a joiner who brought its hero, else the party's).
func bag_of(player: int) -> Array:
	var e := purse_entry(player) if _swap.is_empty() else {}
	return e.purse.get_or_add("items", []) if not e.is_empty() else session.state.items


## Explicit owner lookup, even during another player's temporary purse swap.
## Native LMP script builtins name the player; they cannot read or erase an
## item from whichever purse happens to stand in for state.items at that time.
func owner_bag(player: int) -> Array:
	if not session.is_host:
		# state_for sends this peer's bag as state.items; remote purses are
		# host-only records and are not populated on a client.
		return session.state.items if player == session.my_index else []
	#  resolves the exact player number and returns null for an
	# absent owner; do not create a purse or alias -1 to the host's bag.
	if not session.lmp.is_empty() and not session.players_include(player):
		return []
	if not _swap.is_empty() and int(_swap.e.get("idx", -1)) == player:
		return session.state.items
	var e := purse_entry(player)
	if not e.is_empty():
		return e.purse.get_or_add("items", [])
	return _swap.items if not _swap.is_empty() else session.state.items


## Host: the "state" event for peer `pid` with its own purse and bag in place
## of the party's (or `ev` itself).
func state_for(pid: int, ev: Dictionary) -> Dictionary:
	var p: Dictionary = session.players.get(pid, {})
	var e := purse_entry(int(p.get("index", 0)))
	if e.is_empty():
		return ev
	var out := ev.duplicate()
	out.money = int(e.purse.get("money", 0))
	out.items = e.purse.get("items", [])
	return out


static func _items(v) -> Array:
	var out := []
	if v is Array:
		for it in v:
			if it is String and out.size() < 2000 and (Items.kind(it) != "" or it.begins_with("spell:")):
				out.append(Items.canonical_rune(it))
	return out


# ---------------------------------------------------------------- credit rules

## CampaignState.watch: a var of the host's campaign changed.
func _on_var(st: CampaignState, player: int, key: String, old: float, new: float) -> void:
	if player != 0 or _loading or joiners.is_empty() or not _host_online() or st != session.state:
		return
	for e: Dictionary in joiners.values():
		if e.active:
			_credit_var(e, key, old, new)


static func excluded(key: String) -> bool:
	return key == "gtime" or key == "constr.current" or key.begins_with("zs.") or key.begins_with("zt.") \
		or key.begins_with("apartyn") or key.begins_with("adeadn") or key.begins_with("z.mpgame") \
		or key.begins_with("z.MPGame") or CampaignState.is_player_var(key)


func _credit_var(e: Dictionary, key: String, old: float, new: float) -> void:
	if excluded(key):
		return
	var j := float(e.vars.get(key, 0.0))
	if is_equal_approx(j, new):
		return
	if key.begins_with("q.") and key.get_slice_count(".") >= 3:
		var qz := key.get_slice(".", 1)
		var qkey := "q.%s.%s" % [qz, key.get_slice(".", 2)]
		var jq := float(e.vars.get(qkey, 0.0))
		if jq >= 2.0 or not (e.in_sync or _reached(e, qz)) or not (new > j or is_equal_approx(j, old)):
			e.clean = false
			return
		_credit(e, key, new)
		# The host had the quest already: the joiner gets it now too.
		if key != qkey:
			var hq := session.state.get_var(0, qkey)
			if hq > jq and hq < 2.0:
				_credit(e, qkey, hq)
		if key == qkey and new >= 2.0:
			_send_t = minf(_send_t, 1.0)
		return
	if e.in_sync and is_equal_approx(j, old):
		_credit(e, key, new)
	else:
		e.clean = false


func _credit(e: Dictionary, key: String, v: float) -> void:
	e.vars[key] = v
	e.credits.vars[key] = v


## The joiner's game has been to zone `z` or opened it on the travel map.
static func _reached(e: Dictionary, z: String) -> bool:
	return not z.is_empty() and (e.visited.has(z) or float(e.vars.get("z." + z, 0.0)) >= 1.0)


## A quest var of the zone is further in the joiner's game than in the host's.
func _ahead_in(e: Dictionary, z: String) -> bool:
	var pre := "q.%s." % z
	for k: String in e.vars:
		if k.begins_with(pre) and float(e.vars[k]) > session.state.get_var(0, k):
			return true
	return false


## Quest items and side quests changed since the period began.
func _settle() -> void:
	var st := session.state
	var names := _qi_last.keys()
	for n in st.quest_items:
		if not _qi_last.has(n):
			names.append(n)
	for n in names:
		var had := _qi_last.has(n)
		var has := st.quest_items.has(n)
		if had == has:
			continue
		for e: Dictionary in joiners.values():
			if e.active and e.in_sync and e.quest_items.has(n) == had:
				if has:
					e.quest_items[n] = true
				else:
					e.quest_items.erase(n)
				e.credits.quest_items[n] = has
	var ids := _sq_last.keys()
	for id in st.side_quests:
		if not _sq_last.has(id):
			ids.append(id)
	for id in ids:
		var was := String(_sq_last.get(id, ""))
		var now := String(st.side_quests.get(id, ""))
		if was == now:
			continue
		for e: Dictionary in joiners.values():
			if not e.active:
				continue
			if e.in_sync and String(e.side_quests.get(id, "")) == was:
				e.side_quests[id] = now
				e.credits.side_quests[id] = now
			else:
				e.clean = false
	_qi_last = st.quest_items.duplicate()
	_sq_last = st.side_quests.duplicate()


# ---------------------------------------------------------------- packages

## Original party operations run on each eligible player's private story
## copy before changing the host's party. This is event-driven, never part of
## an actor tick. A behind/ahead guest keeps its own chapter untouched.
func party_operation(op: String, args: Array) -> void:
	if not _host_online() or _loading or not session.lmp.is_empty():
		return
	for e: Dictionary in joiners.values():
		if not e.active or not e.in_sync or not e.clean or not e.present:
			continue
		var context := PartyProgress.read(e.get("party_context"))
		if context == null or context.current_party != session.state.current_party:
			continue
		var roster: Array = session.state.heroes.get(int(e.idx), [])
		var hero: Dictionary = roster[0] if not roster.is_empty() else e.hero_in
		var purse: Dictionary = {"money": session.state.money, "items": session.state.items} \
			if not _swap.is_empty() and int(_swap.e.idx) == int(e.idx) else e.purse
		var personal := GuestRoles.personal(session, int(e.idx), hero, purse)
		PartyProgress.personal(context, personal.hero, personal.purse, false)
		PartyProgress.dependents(context, session.state, e)
		GuestRoles.progress(session, int(e.idx), context)
		PartyProgress.operation(context, op, args)
		e.party_context = PartyProgress.capture(context)
	with_campaign_purse(GuestRoles.operation.bind(session, op, args))


func package(e: Dictionary) -> Dictionary:
	var st := session.state
	var roster: Array = st.heroes.get(int(e.idx), [])
	var personal := GuestRoles.personal(session, int(e.idx), roster[0] if not roster.is_empty() else e.hero_in as Dictionary, e.get("purse", {}))
	var hero: Dictionary = personal.hero.duplicate(true)
	var zones: Dictionary = (e.credits.zones as Dictionary).duplicate()
	if e.in_sync and e.clean and e.present and session.world and session.zone_id:
		zones[session.zone_id] = (st.zones.get(session.zone_id, {}) as Dictionary).duplicate(true)
	zones = preload("res://src/game/script/coop_vm_state.gd").mark_zones(zones, int(e.idx))
	var move := {}
	if e.in_sync and e.clean and e.present and session.zone_id:
		move = {"zone": session.zone_id, "world_time": st.world_time, "day": st.day}
	var purse: Dictionary = personal.purse
	var context := PartyProgress.read(e.get("party_context"))
	var party_context := {}
	if context == null:
		move.clear()   # old tallies still return their hero/purse, never an incomplete chapter
	else:
		if context.current_party != st.current_party:
			# A rejected/missed party change must not move this save into a
			# location requiring a character it cannot deploy.
			move.clear()
		elif not move.is_empty():
			PartyProgress.personal(context, hero, purse, true)
			if e.clean and e.present:
				PartyProgress.dependents(context, st, e)
			GuestRoles.progress(session, int(e.idx), context)
			party_context = PartyProgress.capture(context)
			e.party_context = party_context.duplicate(true)
			e.context_checkpoint = {"party_context": party_context.duplicate(true), "move": move.duplicate()}
	if move.is_empty():
		# Packages are cumulative from the original imported save. Leaving a
		# credited chapter must not discard the last resumable checkpoint.
		var previous: Dictionary = e.get("context_checkpoint", {})
		var saved := PartyProgress.read(previous.get("party_context"))
		if saved != null:
			PartyProgress.personal(saved, hero, purse, false)
			party_context = PartyProgress.capture(saved)
			move = previous.get("move", {}).duplicate()
	var host := "host"
	for p in session.players.values():
		if int(p.index) == 0:
			host = String(p.name)
	return {"campaign_id": st.campaign_id, "host": host, "orig_name": e.orig_name, "hero": hero, "vars": (e.credits.vars as Dictionary).duplicate(),
		"visited": (e.credits.visited as Dictionary).keys(), "side_quests": (e.credits.side_quests as Dictionary).duplicate(),
		"quest_items": (e.credits.quest_items as Dictionary).duplicate(), "zones": zones,
		"purse": {"money": int(purse.get("money", 0)), "items": (purse.get("items", []) as Array).duplicate()},
		"move": move, "party_context": party_context}


## Host: every connected joiner gets its package when it changed.
func send_all() -> void:
	if not _host_online() or joiners.is_empty():
		return
	if purse_active():   # a joiner's purse stands in for the party's: next frame
		_send_t = 0.0
		return
	_settle()
	if session.world and session.zone_id:
		session.state.store_party_positions(session.world)
		session.state.collect_pets(session.world)
		if joiners.values().any(func(e): return e.active and e.in_sync and e.clean and e.present):
			session.state.store_zone(session.zone_id, session.world)
	for key in joiners:
		var e: Dictionary = joiners[key]
		if not e.active or not peer_alive(multiplayer, int(e.pid)):
			continue
		var pkg := package(e)
		var h := hash(var_to_bytes(pkg))
		if _sent_hash.get(key) == h:
			continue
		_sent_hash[key] = h
		e.seq = int(e.get("seq", 0)) + 1
		pkg.sid = String(e.get("sid", ""))
		pkg.seq = e.seq
		_rpc_package.rpc_id(int(e.pid), pkg)


# ---------------------------------------------------------------- validation

static func _num(v, def: float) -> float:
	if v is float or v is int:
		var f := float(v)
		if not is_nan(f) and not is_inf(f):
			return f
	return def


static func _strings(v, max_n: int, max_len := 96) -> Array:
	var out := []
	if v is Array or v is PackedStringArray:
		for x in v:
			if out.size() >= max_n:
				break
			if x is String and not x.is_empty() and x.length() <= max_len:
				out.append(String(x).to_lower())
	return out


## A hero record from another player's save, made safe for this game (unknown
## prototype → Zak's, unknown items dropped, numbers clamped). {} if unusable.
static func sanitize_hero(d) -> Dictionary:
	if not d is Dictionary or (d as Dictionary).is_empty():
		return {}
	var proto := String(d.get("prototype", "Human Hero")) if d.get("prototype") is String else "Human Hero"
	if proto.length() > 64 or GameData.db.find("monster_prototypes", proto).is_empty():
		proto = "Human Hero"
	var npc := GameData.db.find("npcs", proto)
	var h := {"prototype": proto, "level": 1, "hp": -1.0}
	var nm := String(d.get("name", "")) if d.get("name") is String else ""
	h.name = nm.strip_edges().left(32) if nm.strip_edges() else CampaignState.hero_name()
	for k in ["exp", "exp_total", "exp_debt"]:
		h[k] = clampf(_num(d.get(k), 0.0), 0.0, 1.0e9)
	for k in ["str", "dex", "int"]:
		h[k] = clampf(_num(d.get(k), float(npc.get(k, 25.0))), 1.0, 500.0)
	var skills := {}
	if d.get("skills") is Dictionary:
		for k in d.skills:
			# Native starting Science uses a StringName dictionary key. Binary
			# saves/RPC preserve it; retain that allocation with canonical keys.
			if (k is String or k is StringName) and String(k).length() <= 32:
				skills[String(k)] = clampf(_num(d.skills[k], 0.0), 0.0, 1000.0)
	h.skills = skills if d.get("skills") is Dictionary else Skills.from_npc(npc)
	h.perks = _strings(d.get("perks"), 256, 64)
	h.armors = _strings(d.get("armors"), 16).filter(func(x): return Items.kind(x) == "armor")
	h.weapons = _strings(d.get("weapons"), 4).filter(func(x): return Items.kind(x) == "weapon")
	h.quick = _strings(d.get("quick"), 32).filter(func(x): return Items.kind(x) != "")
	h.spells = _strings(d.get("spells"), 64, 128)
	var c = d.get("complexion")
	h.complexion = c if c is Vector3 else GameUnit.proto_complexion(GameData.db.find("monster_prototypes", proto))
	h.aggressive = bool(d.get("aggressive", true)) if d.get("aggressive") is bool else true
	h.gait = clampi(int(_num(d.get("gait", 2), 2.0)), 0, 3)
	if d.get("pos") is Vector2:
		h.pos = d.pos
	if d.get("mana") is float:
		h.mana = maxf(0.0, d.mana)
	if d.get("unit_name") is String:
		h.unit_name = String(d.unit_name).left(32)
	var camp := preload("res://src/game/script/camp_grants.gd")
	var camp_receipt: Dictionary = camp.sanitize(d.get(camp.KEY))
	if not camp_receipt.is_empty():
		h[camp.KEY] = camp_receipt
	if d.has(TrainingRefund.KEY):
		h[TrainingRefund.KEY] = TrainingRefund.sanitize(h, d[TrainingRefund.KEY])
	else:
		TrainingRefund.prepare(h)
	return h
