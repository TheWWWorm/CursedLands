extends Node
## Quest bags are shared story state, while scripted party archives and each
## guest's resumable context retain the exact collect/deploy boundary.
const Party := preload("res://src/game/coop_party_progress.gd")
const Proof := preload("res://src/game/coop_checkpoint.gd")
const Roles := preload("res://src/game/coop_guest_roles.gd")
var checks := 0
var failures := 0
var s: Session
var vm: ScriptVM

class QuietSession extends Session:
	func sync_state() -> void: pass
	func broadcast(_event: Dictionary) -> void: pass

class QuietProgress extends CoopProgress:
	func send_all() -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func clone(st: CampaignState) -> CampaignState:
	var out := CampaignState.new()
	var data := st.to_dict().duplicate(true)
	for key: String in data:
		if key != "version" and key in out: out.set(key,data[key])
	return out

func operation(name: String, args: Array) -> void:
	var nodes := [[ScriptParser.N_NUM,0]]
	for arg: String in args: nodes.append([ScriptParser.N_STR,arg])
	vm._call(name,nodes,ScriptVM.Instance.new())

func entry(st: CampaignState) -> Dictionary:
	return {"idx":1,"pid":2,"active":true,"in_sync":true,"clean":true,"present":true,
		"hero_in":st.heroes[0][0].duplicate(true),"orig_name":"Personal Guest","seq":0,
		"vars":{},"visited":{},"side_quests":{},"quest_items":st.quest_items.duplicate(),
		"credits":{"vars":{},"visited":{},"side_quests":{},"quest_items":{},"zones":{}},
		"purse":{"money":222,"items":["rune:e1"]},"party_context":Party.capture(st)}

func _ready() -> void:
	s = QuietSession.new(); s.online = true
	s.state = CoopProgress.fresh_state()
	s.state.create_party("A"); s.state.add_party_unit("A","Hero","Human Hero")
	s.state.set_current_party("A"); s.state.store_party_quest_items()
	s.state.quest_items = {"shared":true}; s.state.store_party_quest_items()
	s.state.quest_items.uncollected = true
	s.state.money = 900; s.state.items = ["rune:r1"]
	var origin := clone(s.state)
	origin.heroes[0][0].name = "Personal Guest"; origin.money = 222; origin.items = ["rune:e1"]
	s.state.heroes[1] = origin.heroes[0].duplicate(true)
	s.campaign = CampaignMap.load_from(GameData.texts)
	s.world = GameWorld.new(); s.world.session = s; s.zone_id = "gz1g"
	s.coop = QuietProgress.new(); s.coop.session = s
	vm = ScriptVM.new(); vm.session = s; vm.world = s.world
	var e := entry(origin); s.coop.joiners = {"guest":e}
	s.coop._qi_last = s.state.quest_items.duplicate()
	var initial := Party.capture(s.state)
	var read := Party.read(initial)
	check(read != null and Party.capture(read) == initial,"context roundtrip retains live and stale archived quest bags")
	if read == null: get_tree().quit(1); return
	read.quest_items.erase("uncollected")
	check(s.state.quest_items.has("uncollected") and not s.state.party_quest_items.A.has("uncollected"),"context mutation cannot alias host or refresh the stale archive")
	s.state.quest_items.acquired = true
	operation("CreateParty",["B"]); operation("AddUnitToParty",["B::Hero","Human Hero"])
	check(e.quest_items.has("acquired") and e.party_context.quest_items.has("acquired"),"pre-operation settlement credits an ordinary acquisition to the live context")
	operation("CopyLoot",["A","B"])
	check(s.state.party_quest_items.B == {"shared":true},"CopyLoot reads only the source archive")
	check(e.party_context.party_quest_items.B == s.state.party_quest_items.B,"private story context runs the same archived CopyLoot")
	check(s.state.quest_items.size() == 3 and e.quest_items.size() == 3,"CopyLoot does not deploy or replace either live quest bag")
	operation("SetCurrentParty",["B"])
	check(s.state.current_party == "B" and s.state.quest_party == "A" and s.state.quest_items.size() == 3,"selection keeps the previous loaded quest inventory until deployment")
	check(e.party_context.current_party == "B" and e.party_context.quest_party == "A","private context keeps selected and loaded party identities separate")
	check(e.purse.money == 222 and s.state.money == 900,"scripted quest state does not mix private purses")
	var before_save := s.state.party_quest_items.duplicate(true)
	s.coop.before_save()
	check(s.state.party_quest_items == before_save and e.party_context.quest_party == "A","co-op save bookkeeping does not collect or deploy quest items")
	var waiting := entry(origin); waiting.idx = 2; waiting.clean = false
	s.coop.joiners.waiting = waiting
	s.coop.store_party_quest_items()
	check(s.state.quest_party == "B" and s.state.quest_items == {"shared":true},"collect/deploy activates the selected archived bag")
	check(s.state.party_quest_items.A == {"shared":true,"uncollected":true,"acquired":true},"collection archives the actual outgoing live contents")
	check(e.quest_items == s.state.quest_items and e.party_context.party_quest_items == s.state.party_quest_items,"eligible guest carries the same live and archived story inventory")
	s.coop._settle()
	check(waiting.quest_items == origin.quest_items and waiting.credits.quest_items.is_empty(),"guest who missed the party transition gets no false item-removal credit")
	check(not e.credits.quest_items.has("uncollected"),"deployment is not misreported as quest-item consumption")
	# An older cumulative delta belongs to the pre-switch bag. It must not
	# overwrite the complete context after it has restored another bag.
	e.credits.quest_items = {"shared":false,"uncollected":true}
	var pkg := s.coop.package(e)
	var merged := clone(origin)
	CoopProgress.merge(merged,pkg)
	check(merged.quest_items == {"shared":true} and merged.quest_party == "B","complete context takes precedence over stale cumulative item credits")
	check(merged.party_quest_items == s.state.party_quest_items,"merged solo state preserves every archived quest bag")
	var once := Party.capture(merged)
	CoopProgress.merge(merged,pkg)
	check(Party.capture(merged) == once,"repeated cumulative package cannot replay archived inventory")
	check(merged.money == 222 and merged.items == ["rune:e1"],"quest archive merge preserves the guest's personal purse")
	var path := "user://party-quest-coop.sav"
	check(merged.save(path) == OK,"independent guest checkpoint saves")
	var loaded := CampaignState.load_from(path)
	check(loaded != null and Party.capture(loaded) == once,"guest save reload retains deferred inventory and archives exactly")
	e.clean = false
	s.state.quest_items["partial"] = true
	var partial_package := s.coop.package(e)
	var partial_progress := clone(origin)
	CoopProgress.merge(partial_progress,partial_package)
	check(partial_progress.quest_items == {"shared":true,"partial":true}
		and partial_progress.party_quest_items == before_save.merged({"A":{"shared":true,"uncollected":true,"acquired":true}},true),
		"partial credit in the same loaded party updates live items without refreshing archives")
	var parked: Dictionary = e.context_checkpoint.party_context.duplicate(true)
	parked.current_party = "A"; parked.quest_party = "A"; parked.quest_items = {"parked":true}
	# The saved roster is irrelevant to this owner-isolation control, but its
	# current-party entry must obey the ordinary context schema.
	parked.parties.erase("A")
	e.context_checkpoint.party_context = parked
	var isolated := s.coop.package(e)
	check(isolated.party_context.quest_items == {"parked":true},"partial credit from a different loaded party cannot leak into the parked checkpoint")
	s.state.quest_items.erase("partial"); e.clean = true
	s.coop._settle()
	var legacy := initial.duplicate(true)
	for key: String in Party.QUEST_FIELDS: legacy.erase(key)
	var old := Party.read(legacy)
	check(old != null and not Party.has_quest_inventory(old) and not Party.capture(old).has("quest_items"),"legacy context roundtrip retains absence of inventory evidence")
	var live_before := merged.quest_items.duplicate()
	var archives_before := merged.party_quest_items.duplicate(true)
	var owner_before := merged.quest_party
	Party.apply(merged,old)
	check(merged.quest_items == live_before and merged.party_quest_items == archives_before and merged.quest_party == owner_before,"legacy context cannot clear active items or fabricate archived contents")
	CoopProgress.merge(merged,{"campaign_id":merged.campaign_id,"party_context":legacy,"move":{"zone":"gz1g"},"quest_items":{"shared":false,"legacy_new":true}})
	check(merged.quest_items == {"legacy_new":true},"legacy partial item credits keep their existing merge behavior")
	for bad: Dictionary in [{"quest_items":[]},{"party_quest_items":{"A":[]}}, {"quest_party":false}, {"quest_items":{"bad":false}}]:
		var malformed := initial.duplicate(true); malformed.merge(bad,true)
		check(Party.read(malformed) == null,"malformed quest context is rejected: "+str(bad))
	var partial := initial.duplicate(true); partial.erase("quest_party")
	check(Party.read(partial) == null,"incomplete new inventory context is rejected atomically")
	var story := Proof.story(s.state)
	var signature := Proof.signature(story)
	var changed := story.duplicate(true); changed.party_context.party_quest_items.A.extra = true
	check(Proof.signature(changed) != signature,"receipt covers archived quest items")
	changed = story.duplicate(true); changed.party_context.quest_party = "A"
	check(Proof.signature(changed) != signature,"receipt covers the loaded quest-inventory owner")
	changed = story.duplicate(true); changed.party_context.money = 12345
	check(Proof.signature(changed) == signature,"personal wealth stays outside shared-story receipts")
	var exact := Proof.story(s.state)
	check(s.coop._story_matches(exact),"same active inventory and archives form an identical checkpoint")
	exact.party_context = exact.party_context.duplicate(true); exact.party_context.party_quest_items.A.extra = true
	check(not s.coop._story_matches(exact),"active-item equality cannot hide conflicting archived inventory")
	var advanced := s.state
	s.state = CoopProgress.fresh_state()
	var opening := Proof.story(s.state).duplicate(true)
	s.state.store_party_quest_items()
	check(s.coop._story_matches(opening) and Proof.signature(opening) == Proof.signature(Proof.story(s.state)),
		"initial collection of an empty archive preserves story equality and its receipt")
	for key: String in Party.QUEST_FIELDS: opening.party_context.erase(key)
	check(s.coop._story_matches(opening),"legacy empty inventory can still match an empty current-party checkpoint")
	s.state.quest_party = "Waiting"
	check(not s.coop._story_matches(opening),"legacy context cannot claim an unrecorded loaded owner even when every archive is empty")
	s.state = advanced
	var transient := Roles.GuestState.new()
	transient.ensure_hero(0,"Human Hero"); transient.create_party("Role")
	transient.add_party_unit("Role","Hero","Human Hero"); transient.set_current_party("Role")
	transient.store_party_quest_items(); transient.quest_items.private = true
	check(s.state.quest_items == {"shared":true} and not s.state.party_quest_items.has("Role"),"transient guest roles cannot alter the campaign's shared quest bags")
	vm = null; s.world.free(); s.coop.free(); s.free()
	print("PARTY_QUEST_INVENTORY_COOP ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
