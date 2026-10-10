class_name Briefings
extends RefCounted
## Conversations ("briefings") driven by campaign variables:
##   b.<npc>.<id> = 1   the NPC named <npc> has conversation <id> to tell
##   b.<zone>.<id> = 1  conversation <id> plays as soon as the party is in <zone>
## When a conversation ends its variable becomes 2, its rewards from
## quests.qdb/briefings are applied and #OnBriefingComplete(player, "b.npc.id")
## runs. Text comes from texts.res ("briefing <id>"), voice from speech.res.

var vm: ScriptVM
var active := ""          # full variable name of the running conversation
var active_player := -1   # initiator; another peer may close the shared dialog
var _named_id := ""       # a script requested this briefing without an owner
var _check := 0.0
## Native screen saves the third actor and, in #cage scenes, the second.
## Closing the conversation walks them back before reporting completion.
var _return_actors: Array = []
## A walking conversation waits for its required staging orders. The host
## publishes the first phrase only after its ordinary walk/turn tick finishes.
var _pending_dialog: Dictionary = {}
var _after_movie: Array = []
var _original_village_topics := {} # player -> [NPC id, hero id]; transient host context


func _init(v: ScriptVM) -> void:
	vm = v


func tick() -> void:
	if vm.session.movie_active(): return
	if active.is_empty() and not _after_movie.is_empty():
		var request: Array = _after_movie.pop_front()
		play_named.callv(request)
	if not active.is_empty() or vm.time < _check:
		return
	_check = vm.time + 0.5
	var zone := String(vm.world.zone.get("id", "")).to_lower()
	SideQuests.check_rewards(vm.session)
	if not active.is_empty():
		return
	var pre := "b.%s." % zone
	for k: String in vm.session.state.gs_keys(0, "b.", true):
		if k.begins_with(pre) and vm.session.state.get_var(0, k) == 1.0:
			#  starts automatic zone briefings with (1, 1).
			play_named(k.substr(pre.length()), "b.%s.%s" % [zone, k.substr(pre.length())], 0, null, true)
			return


## Player clicked a unit: offer its pending conversations. the original
##  fills the dialog's topic list with every
## b.<owner>.<id> = 1 of the unit, then one "constr*" entry if the unit has
## any (the last one found), then "goodbye" (
## append). Nothing pending -> the dialog does not open (count 0 in
## ). Each row is the first line of texts.res "briefing <id>"
## ((.., 1); "constr*" rows use "briefing constr").
## Picking one: "goodbye" closes, "constr<N>" sets GS var
## constr.current = N and opens the camp screen with that trader, the
## variable staying 1; anything else plays the conversation.
## A conversation without a "briefing <id>" text (bz8k / bz10k / bz11k
## b.merc5.n5_2, n5_10, merc6 the same) is still listed: leaves
## the title empty when finds no text, so the row is the topic
## prefix alone (empty in the shipped texts), a blank row that can be picked.
## 607320 scans a temporary copy of the raw GS hash (460ee0), sorted only
## online by byte _stricmp. Old saves can only reconstruct their discarded
## spelling/insertion order from the dictionary they still contain.
func interact(_unit: GameUnit, target: Object, player: int, original_stage := false) -> void:
	clear_original_topics(player)
	if not active.is_empty() or not (target is GameUnit):
		return
	var t: GameUnit = target
	if t.dead or (vm.session.shop_available() and not t.village_talk_ready()):
		return
	var options := []
	var constr := []
	for e: Array in available_for(t, player):
		if String(e[1]).to_lower().begins_with("constr"):
			constr = e
			continue
		var text := GameData.text("briefing " + String(e[1]))
		if text.is_empty():
			text = vm.session.quest_text("briefing " + String(e[1]))
		var title := text.get_slice("\n", 0).strip_edges() if text else ""
		options.append({"var": "b.%s.%s" % e, "title": title})
	if not constr.is_empty():
		var title := GameData.text("briefing constr").get_slice("\n", 0).strip_edges()
		options.append({"var": "b.%s.%s" % constr, "title": title})
	if options.is_empty():
		return
	# Host-only, per-player topic context. It is never saved or supplied by a
	# client; another player's topic list must not overwrite this choice.
	if original_stage: _original_village_topics[player]=[t.uid, _unit.uid]
	vm.session.broadcast({"t": "topics", "player": player, "uid": t.uid, "name": t.display_name, "options": options})


## Another command replaces this topic flow, including an approach that has
## not reached its target yet. A local Goodbye alone starts no conversation.
func clear_original_topics(player: int) -> void:
	_original_village_topics.erase(player)


## The player picked conversation `var_name` from unit `uid`'s topic list.
func topic(player: int, var_name: String, uid: int) -> void:
	var context: Array = _original_village_topics.get(player, [])
	clear_original_topics(player)
	var t: GameUnit = vm.world.units.get(uid)
	if not active.is_empty() or t == null or t.dead:
		return
	for e: Array in available_for(t, player):
		if "b.%s.%s" % e == var_name:
			var id := String(e[1])
			if id.to_lower().begins_with("constr"):
				# atof(id.Mid(7)) -> sets "constr.current"
				# (5) opens the camp screen (the shop).
				# Only when finds that record. The host restocks it
				# here (on opening) and sends the goods with the state.
				var n := int(float(id.substr(7)))
				if not Shops.exists(n):
					return
				vm.session.state.set_var(0, "constr.current", float(n))
				vm.session.open_shop(n)
				vm.session.broadcast({"t": "shop", "player": player, "constr": n})
				return
			var original := context.size()==2 and int(context[0])==uid \
				and preload("res://src/game/script/authored_village_talk.gd").original_stage( \
					vm.session, vm.world.units.get(int(context[1])), t, player, var_name)
			play_named(id, var_name, player, t, original, not original)
			return


func available(npc: String) -> Array:
	var pre := "b.%s." % npc
	var out := []
	for k: String in vm.session.state.gs_keys(0, "b.", true):
		if k.begins_with(pre) and vm.session.state.get_var(0, k) == 1.0:
			out.append(k.substr(pre.length()))
	return out


## Pending conversations of a unit as [owner name, id]: the original
## takes every GS var b.<owner>.<id> = 1 whose owner names this unit's id
## (ScriptVM.name_id) — usually the unit's own name, but e.g. "OrcC" is the
## unit named Shaivar.
func available_for(u: GameUnit, player := 0) -> Array:
	return pending_for(vm.session.state, u, player)


## The same from the synced state (clients use it for the village click).
## `player`'s view: its own mercenary vars over the shared ones
## (CampaignState.get_pvar).
static func pending_for(state: CampaignState, u: GameUnit, player := 0) -> Array:
	var name := String(u.info.get("name", "")).to_lower()
	# A recruited mercenary is one shared-world unit, owned by its hirer.
	# Other players cannot treat it as an available village NPC or dismiss it.
	if name.begins_with("merc") and name.substr(4).is_valid_int():
		var m: Dictionary = state.mercs.get(name.substr(4).to_int(), {})
		if not m.is_empty() and (int(m.get("controller", 0)) != player or m.get("travel_waiting", false)):
			return []
	var out := []
	var seen := {}
	var constr := []
	var keys := state.gs_keys(0, "b.", true)
	if player != 0:
		keys.append_array(state.gs_keys(player, "b.", true))
	for key: String in keys:
		if seen.has(key):
			continue
		seen[key] = true
		if state.get_pvar(player, key) != 1.0:
			continue
		var parts := key.split(".")
		if parts.size() != 3:
			continue
		if parts[1] == name or ScriptVM.name_id(parts[1]) == u.uid:
			if parts[2].to_lower().begins_with("constr"):
				constr = [parts[1], parts[2]]   # last found before online sorting
			else:
				out.append([parts[1], parts[2]])
	if u.world and u.world.session and u.world.session.multiplayer_game:
		# Native network60b2f0 ->6f21f0 uses _stricmp, so n10 precedes
		# n2. GS identifiers are bytes; only ASCII uppercase folds here.
		out.sort_custom(func(a, b): return _topic_compare(a[1], b[1]) < 0)
	if not constr.is_empty():
		out.append(constr)
	return out


static func _topic_compare(a: String, b: String) -> int:
	for i in mini(a.length(), b.length()):
		var x := a.unicode_at(i) & 0xff
		var y := b.unicode_at(i) & 0xff
		if x >= 65 and x <= 90:
			x += 32
		if y >= 65 and y <= 90:
			y += 32
		if x != y:
			return -1 if x < y else 1
	return signi(a.length() - b.length())


## Starts conversation `id` for everyone. `var_name` is reported on completion.
func play_named(id: String, var_name: String, player := 0, partner: GameUnit = null, instant := false, approached := false) -> void:
	if vm.session.movie_active():
		_after_movie.append([id, var_name, player, partner, instant, approached])
		return
	var text := GameData.text("briefing " + id)
	if text.is_empty():
		# Quest maps ship their own briefings inside the .mq archive.
		text = vm.session.quest_text("briefing " + id)
	_named_id = id if var_name.is_empty() else ""
	if not _named_id.is_empty():
		var_name = _named_key(id, player)
		if var_name.is_empty():
			# An event ID for the dialog UI only; completion never creates a
			# campaign variable if the native lookup still finds no owner.
			var_name = "b.%s.%s" % [String(vm.world.zone.get("id", "")).to_lower(), id]
	if text.is_empty():
		push_warning("missing briefing " + id)
		complete(player, var_name, true)
		return
	active = var_name
	active_player = player
	var b := parse(text)
	var c := cast(b.actors, partner, player)
	vm.world.dialog_actors.clear()
	for k in ["a", "b", "c"]:
		if c.has(k):
			vm.world.dialog_actors[int(c[k])] = true
	_face(c, instant, approached)
	var event := {"t": "dialog", "id": var_name, "brief": id, "title": b.title, "phrases": b.phrases, "cast": c}
	_pending_dialog = {} if instant else event
	if instant:
		vm.session.broadcast(event)
	else:
		var waiting := event.duplicate(true)
		waiting["staging"] = true
		vm.session.broadcast(waiting)


## Native village mode 2: only unfinished orders whose wait flag is set
## delay the first phrase. Closing a prior conversation's return walk does
## not delay this one. Called after World's mover/turn completion checks.
func staging_tick() -> void:
	if _pending_dialog.is_empty() or active.is_empty():
		return
	for m: Dictionary in vm.world.dialog_movers.values():
		if int(m.get("state", 1)) > 0 and bool(m.get("wait", not m.get("restore", false))):
			return
	var event := _pending_dialog
	_pending_dialog = {}
	vm.session.broadcast(event)


## LiA: closing a script-started briefing scans the temporary
## b.* GS table in hash order and matches its third component with _stricmp.
## There is no value==1 filter. Retain the key's exact case for GSSetVar and
## #OnBriefingComplete (e.g. b.First.brief_0, not b.bz1r.brief_0).
func _named_key(id: String, player: int) -> String:
	for key: String in vm.session.state.gs_keys(player, "b.", true):
		var parts := key.split(".")
		if parts.size() == 3 and parts[2].nocasecmp_to(id) == 0:
			return key
	return ""


## Clicked conversations face the actors where the player approached the NPC.
## Other briefings retain authored staging: the partner
## moves in front of the hero, or the hero in front of the partner in #cage
## zones; the third actor takes the triangle's corner. The cast retains these
## positions and heights for the conversation camera.
func _face(c: Dictionary, instant := false, approached := false) -> void:
	_return_actors.clear()
	var a: GameUnit = vm.world.units.get(int(c.get("a", -1)))
	var b: GameUnit = vm.world.units.get(int(c.get("b", -1)))
	if a == null or b == null:
		return
	if approached:
		# Clicked conversations begin where the player approached the NPC.
		# Walking the NPC to a camera mark can fail on a wall or body and
		# used to hold the entire dialogue behind a 30-second deadline.
		_face_in_place(c, a, b)
		return
	var d := float(b.proto.get("dialog_cam_distance", 0.0)) + 2.5
	var a_at := a.pos
	var b_at := b.pos
	var a_z := a.position.y
	var b_z := b.position.y
	var cage := bool(vm.world.zone.get("cage", false))
	if cage:
		b_at = a.pos + Vector2.from_angle(a.facing) * d
		b_z = a_z
	else:
		a_at = b.pos + Vector2.from_angle(b.facing) * d
		a_z = b_z
		_stage(a, a_at, (b_at - a_at).angle(), instant)
	# The third actor's place: the middle of a and b
	# turned by a right angle — mid + (b.y − mid.y, mid.x − b.x) — then
	#  walks it there facing the middle.
	var mid := (a_at + b_at) * 0.5
	var cu: GameUnit = vm.world.units.get(int(c.get("c", -1)))
	var c_at := cu.pos if cu else Vector2.ZERO
	if cu:
		_remember_return(cu)
		c_at = mid + Vector2(b_at.y - mid.y, mid.x - b_at.x)
		_stage(cu, c_at, (mid - c_at).angle(), instant)
	if cage:
		_remember_return(b)
		_stage(b, b_at, (a_at - b_at).angle(), instant)
	if instant:
		# A co-op body or static footprint can refuse the requested placement.
		# Freeze the actual stage, not an imaginary mark behind a wall/body.
		a_at = a.pos
		b_at = b.pos
		a_z = a.position.y
		b_z = b.position.y
		if a_at != b_at:
			a.facing = (b_at - a_at).angle()
			b.facing = (a_at - b_at).angle()
		if cu:
			c_at = cu.pos
			cu.facing = ((a_at + b_at) * 0.5 - c_at).angle()
	# The places the conversation camera works from (the original keeps them
	#  and never reads the units again; DialogCamera).
	c["at"] = {"a": [a_at.x, a_at.y], "b": [b_at.x, b_at.y]}
	# Keep XY rows backward-compatible; the original camera separately
	# retains the staged height rather than sampling the final footprint.
	c["at_z"] = {"a": a_z, "b": b_z}
	if cu:
		c["at"]["c"] = [c_at.x, c_at.y]
		c["at_z"]["c"] = cu.position.y if instant else (a_z + b_z) * 0.5


func _face_in_place(cast: Dictionary, a: GameUnit, b: GameUnit) -> void:
	cast["at"] = {}
	cast["at_z"] = {}
	var middle := (a.pos + b.pos) * 0.5
	for key in ["a", "b", "c"]:
		var u: GameUnit = vm.world.units.get(int(cast.get(key, -1)))
		if u == null:
			continue
		cast.at[key] = [u.pos.x, u.pos.y]
		cast.at_z[key] = u.position.y
		if u.blocked:
			continue
		var toward := b.pos if key == "a" else a.pos if key == "b" else middle
		var angle := (toward - u.pos).angle() if toward != u.pos else u.facing
		vm.world.dialog_movers[u] = {"to": u.pos, "angle": angle, "state": 2, "elapsed": 0.0, "wait": true}
		u.command({"type": "rotate", "angle": angle, "turn_speed": 1.0 / GameUnit.TICK})


func _remember_return(u: GameUnit) -> void:
	# A new conversation may interrupt an earlier return walk. Native
	# 6064a0 / LiA53fbb0 preserve that earlier destination and facing.
	var pending: Dictionary = vm.world.dialog_movers.get(u, {})
	_return_actors.append({"uid": u.uid,
		"to": pending.to if pending.get("restore", false) else u.pos,
		"angle": pending.angle if pending.get("restore", false) else u.facing})
	vm.world.dialog_movers.erase(u)


func _stage(u: GameUnit, point: Vector2, angle: float, instant: bool, waiting := true) -> void:
	if instant:
		#  tries placement, then applies the facing and clears
		# the AI order even when the footprint prevents that placement.
		vm.world.dialog_place(u, point, angle)
	elif not u.blocked:   #  refuses a walk under flag.
		vm.world.dialog_movers[u] = {"to": point, "angle": angle, "state": 1, "elapsed": 0.0, "wait": waiting}
		u.command({"type": "move", "to": point, "run": false})
		u.set_meta("ai_state", 1)   # 608990 / LiA539810 call the ordinary AI move setter


func complete(player: int, var_name: String, force := false) -> void:
	if not force and not _pending_dialog.is_empty():
		return   # mode 2 has no phrase/close controls yet
	if var_name != active and not force:
		return   # already finished (another co-op player closed it first)
	if not force and active_player >= 0:
		player = active_player   # credit the speaker even when its peer closes it
	# 608410 / LiA53bd80 restore c first, then #cage b, using walking
	# staging (all three flags zero), before the GS completion callback.
	for row: Dictionary in _return_actors:
		var u: GameUnit = vm.world.units.get(int(row.uid))
		if u and not u.dead:
			_stage(u, row.to, float(row.angle), false, false)
			if vm.world.dialog_movers.has(u):
				vm.world.dialog_movers[u].restore = true
	_return_actors.clear()
	# A missing script-started briefing closes the currently displayed
	# conversation, even when its completion key belongs to another topic.
	var close_id := active if force and not active.is_empty() else var_name
	_pending_dialog = {}
	active = ""
	active_player = -1
	vm.session.broadcast({"t": "dialog_close", "id": close_id})
	var key := _named_key(_named_id, player) if not _named_id.is_empty() else var_name
	_named_id = ""
	if key.is_empty():
		return
	vm.merc_briefing_done(key, player)   #  runs first
	vm.session.state.set_pvar(player, key, 2.0)
	# Rewards go to the talking player's purse (a joiner's own, CoopProgress.with_purse);
	# with the remake option coop_share_loot the others get copies.
	var id := key.get_slice(".", key.get_slice_count(".") - 1)
	if key.begins_with("sq."):
		vm.session.coop.with_purse(player, SideQuests.briefing_done.bind(vm.session, key), true)
	elif not vm.session.lmp.is_empty() and key.begins_with("b.") \
			and SideQuests.lmp_briefing(vm.session, id, player):
		pass   # the multiplayer quest giver's take / cancel / complete
	else:
		vm.session.coop.with_purse(player, _rewards.bind(id, player), true)
	vm.fire_event("#OnBriefingComplete", [float(player), key])


func _rewards(id: String, player := 0) -> void:
	var row := GameData.db.find("briefings", id)
	if row.is_empty():
		return
	var st := vm.session.state
	# the original (record read): field 1 (
	# "unknown" here) is experience for the party, field 2 money.
	# No text window line: the conversation box shows the rewards at its last
	# phrase (DialogPanel._reward_lines).
	var exp := float(row.get("unknown", 0.0))
	if exp != 0.0:
		vm.session.give_experience(exp, "talk", player)
	var money := int(float(row.get("money", 0.0)))
	if exp > 0.0 or money > 0 or not _list(row.get("give_items")).is_empty():
		SmileFaces.party(vm.session, player)   # remake option "smile_faces": a reward
	if money:
		st.money += money
	# give_quests and open_zones are GSSetVarMax(var, 1)
	# give_quests2 and unknown2 are GSSetVar(var, 2) — objectives
	# done (Dr22: q.gz9g.q26g.1) and zones closed (K42 z.gz11k, Gl63 z.bz14h,
	# Gl64 z.gz17h).
	for field in ["give_quests", "give_quests2", "open_zones", "unknown2"]:
		var two: bool = field in ["give_quests2", "unknown2"]
		for q in _list(row.get(field), false):
			if two:
				st.set_var(0, q, 2.0)
				vm._on_var_changed(q)
			elif float(st.get_var(0, q)) < 1.0:
				st.set_var(0, q, 1.0)
				vm._on_var_changed(q)
	for spec in _list(row.get("give_items")):
		# Quest items go to the quest list, everything else (weapons, armour,
		# materials, wands) into the party bag.
		var it: Array = Items.from_spec(spec)
		if not vm.session.lmp.is_empty():
			vm.session.add_item(String(it[0]), int(it[1]))
		elif not Items.is_spell_piece(String(it[0])) and Items.info(it[0]).table in ["quest_items", ""]:
			st.quest_items[it[0]] = true
		else:
			for k in it[1]:
				st.items.append(it[0])
	for spec in _list(row.get("take_items")):
		var it: Array = Items.from_spec(spec)
		if vm.session.lmp.is_empty():
			st.quest_items.erase(it[0])
		for k in it[1]:
			st.items.erase(it[0])
	vm.session.sync_state()


static func _list(v, normalize := true) -> PackedStringArray:
	var out := PackedStringArray()
	if v == null:
		return out
	var items: Array = Array(v) if (v is Array or v is PackedStringArray) else str(v).split(";")
	for s in items:
		var t := String(s).strip_edges()
		if normalize:
			t = t.to_lower()
		if t:
			out.append(t)
	return out


## Parses a briefing text into {title, actors, phrases: [{speaker, actor, n,
## text, desc, anim, camera, cam_args}]}. As in the original the
## #animation / #camera lines before a #phrase apply to that phrase only
## (-1 = none); "#camera N angle distance height" gives a free angle.
## `actors` lists the #show names in order of appearance; each phrase's
## `shows` holds the "#show name N" / "#hide name" (N = 0) lines before it
## in order (quest items are drawn at slot N).
static func parse(text: String) -> Dictionary:
	var lines := text.replace("\r", "").split("\n")
	var out := {"title": lines[0].strip_edges() if lines.size() > 0 else "", "phrases": [], "actors": []}
	var cur := {}
	var anim := -1
	var cam := -1
	var cam_args := []
	var shows := []
	var nolips := false
	for i in range(1, lines.size()):
		var l := lines[i].strip_edges()
		if l.begins_with("#"):
			var w := l.split(" ", false)
			match w[0].to_upper():
				"#PHRASE":
					cur = {"speaker": w[1] if w.size() > 1 else "", "actor": (w[1] if w.size() > 1 else "").to_lower(),
						"n": int(w[2]) if w.size() > 2 else 0, "text": "", "desc": "", "anim": anim, "camera": cam,
						"cam_args": cam_args, "shows": shows, "nolips": nolips}
					out.phrases.append(cur)
					nolips = false
					shows = []
					anim = -1
					cam = -1
					cam_args = []
				"#NOLIPS":   # the next phrase in grey, no lips
					nolips = true
				"#DESC":
					if not cur.is_empty():
						cur.desc = l.substr(5).strip_edges()
				"#ANIMATION":
					anim = int(w[1]) if w.size() > 1 else -1
				"#CAMERA":
					cam = int(w[1]) if w.size() > 1 else -1
					cam_args = [float(w[2]), float(w[3]), float(w[4])] if w.size() > 4 else []
				"#SHOW":
					if w.size() > 1 and not w[1].to_lower() in out.actors:
						out.actors.append(w[1].to_lower())
					if w.size() > 2:
						shows.append([w[1].to_lower(), int(w[2])])
				"#HIDE":
					if w.size() > 1:
						shows.append([w[1].to_lower(), 0])   # 0 = take away
		elif not cur.is_empty() and l:
			cur.text += ("\n" if cur.text else "") + l
	for p: Dictionary in out.phrases:
		p.speaker = speaker_name(p.speaker)
	return out


## The units playing a conversation's actors (the original): "a" the
## partner the player talked to, "b" the first other #show actor (usually the
## hero), "c" the next one; `names` maps actor names to unit ids ("hero" is
## the talking player's hero).
func cast(actors: Array, partner: GameUnit, player: int) -> Dictionary:
	var names := {}
	for n: String in actors:
		var u := _actor_unit(n, player)
		if u:
			names[n] = u.uid
	var order: Array = []
	if partner:
		order.append(partner.uid)
	for n: String in actors:
		if names.has(n) and not int(names[n]) in order:
			order.append(int(names[n]))
	var out := {"names": names}
	for i in mini(order.size(), 3):
		out[["a", "b", "c"][i]] = order[i]
	return out


func _actor_unit(actor: String, player: int) -> GameUnit:
	var fallback: GameUnit = null
	for u: GameUnit in vm.world.units.values():
		if u.dead:
			continue
		if actor == "hero":
			if u.has_meta("hero") and not u.get_meta("hero").has("merc"):
				if u.controller == player:
					return u
				fallback = u if fallback == null else fallback
		elif String(u.info.get("name", "")).to_lower() == actor or u.uid == ScriptVM.name_id(actor):
			return u
	return fallback


static func speaker_name(actor: String) -> String:
	if actor.to_lower() == "hero":
		return CampaignState.hero_name()
	var t := GameData.text("pers " + actor.to_lower())
	return t.get_slice("\n", 0).strip_edges() if t else actor
