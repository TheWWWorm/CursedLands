extends RefCounted
## Live guest counterparts of the original temporary parties. This journal is
## separate from quest credit: even a visiting/out-of-sync guest must obey the
## current chapter's equipment/body rules. Only party events touch it.
const Progress := preload("res://src/game/coop_party_progress.gd")
const KEY := "guest_roles"


class GuestState extends CampaignState:
	func party_member(ref: String) -> Dictionary:
		# The script's main Hero means this guest's original character,
		# regardless of their network deployment name (even one with ::).
		if ref.to_lower() in ["hero", "::hero"]:
			var main := _party_roster("")
			if not main.is_empty(): return main[0]
		return super.party_member(ref)


static func temporary(st: CampaignState, party: String) -> bool:
	return party == "Shaina" if st.campaign_id == CampaignProfile.ASTRAL else party in ["HeroAlone", "Pretty", "JunParty"]


static func row(st: CampaignState, player: int) -> Dictionary:
	return st.coop.get(KEY, {}).get(player, {})


static func purse(st: CampaignState, player: int) -> Dictionary:
	var r := row(st, player)
	return r if not r.is_empty() and temporary(st, String(r.party)) else {}


static func owner(s: Session, player: int) -> Dictionary:
	for e: Dictionary in s.coop.joiners.values():
		if int(e.idx) == player: return e
	return {}


static func context(s: Session, r: Dictionary) -> CampaignState:
	# Keep record references, just like the host's SetCurrentParty: outgoing
	# actors may write their final position after their party has been parked.
	var st := GuestState.new()
	var e := owner(s, int(r.idx))
	if not e.is_empty(): r.purse = e.purse
	if not s.coop._swap.is_empty() and int(s.coop._swap.e.idx) == int(r.idx) and not s.coop._swap.get("shared", false):
		r.purse.money = s.state.money
		r.purse.items = s.state.items
	if not r.roster.is_empty(): r.name = String(r.roster[0].name)
	st.campaign_id = s.state.campaign_id
	st.current_party = r.party
	st.heroes[0] = r.roster
	st.parties = r.parties
	st.party_bags = r.bags
	st.items = r.purse.items
	st.money = int(r.purse.money)
	return st


static func remember(s: Session, r: Dictionary, st: CampaignState, bind := false) -> void:
	r.party = st.current_party
	r.roster = st.heroes.get(0, [])
	r.parties = st.parties
	r.bags = st.party_bags
	r.purse = {"money":st.money, "items":st.items}
	var e := owner(s, int(r.idx))
	if not e.is_empty(): e.purse = r.purse
	if bind:
		for i in r.roster.size():
			var h: Dictionary = r.roster[i]
			h.name = r.name
			if temporary(st, st.current_party): h.guest_unit_name = "RemakeGuest%d_%d" % [int(r.idx), i]
			else: h.erase("guest_unit_name")
		s.state.heroes[int(r.idx)] = r.roster


static func create(s: Session, player: int) -> Dictionary:
	var roster: Array = s.state.heroes.get(player, [])
	if roster.is_empty(): return {}
	var e := owner(s, player)
	var normal := "FSusel" if s.state.campaign_id == CampaignProfile.ASTRAL else ""
	if not temporary(s.state, s.state.current_party): normal = s.state.current_party
	var r := {"idx":player, "name":String(roster[0].name), "normal":normal, "party":normal,
		"roster":roster, "parties":{}, "bags":{}, "shared":e.is_empty(),
		"purse":e.get("purse", {"money":0,"items":[]})}
	s.state.coop.get_or_add(KEY, {})[player] = r
	return r


## Late joins and old saves have no live journal. Recreate only the inspected
## authored operations, with this player's stats/items and fresh stock roles.
## No host equipment, purse, wounds or earned skills are copied.
static func seed_role(st: CampaignState, party: String) -> void:
	if party == "Shaina":
		st.create_party(party)
		st.add_party_unit(party, "merc8", "merc8")
	elif party in ["HeroAlone", "Pretty"]:
		st.create_party("HeroAlone")
		st.add_party_unit("HeroAlone", "Hero", "Human Hero Hadagan")
		st.copy_stats("Hero", "HeroAlone::Hero")
		if party == "Pretty":
			st.create_party(party)
			st.add_party_unit(party, "Nalo", "Human Hadagan Pretty")
	elif party == "JunParty":
		st.create_party(party)
		st.add_party_unit(party, "JunBoy", "Jun Male Hero")
		st.copy_stats("Hero", "JunParty::JunBoy")
		st.copy_items("Hero", "JunParty::JunBoy")
		st.move_loot("", party, true)
	st.set_current_party(party)


static func ensure(s: Session, player: int) -> bool:
	if player <= 0 or not s.lmp.is_empty(): return false
	var r := row(s.state, player)
	if not r.is_empty():
		# The serializer restores equal arrays independently. Rebind the active
		# journal to the actual roster so subsequent wounds/gear are retained.
		r.roster = s.state.heroes.get(player, r.roster)
		return false
	if not temporary(s.state, s.state.current_party): return false
	r = create(s, player)
	if r.is_empty(): return false
	var st := context(s, r)
	seed_role(st, s.state.current_party)
	remember(s, r, st, true)
	return true


static func relevant(s: Session, r: Dictionary, op: String, args: Array) -> bool:
	if s.state.campaign_id != CampaignProfile.ASTRAL: return true
	if temporary(s.state, s.state.current_party): return true
	if not r.is_empty() and r.party == "Shaina": return true
	return op in ["CreateParty", "AddUnitToParty", "SetCurrentParty"] and args.size() > 1 \
		and str(args[1]).get_slice("::", 0) == "Shaina"


static func operation(s: Session, op: String, args: Array) -> void:
	if not s.lmp.is_empty(): return
	for player: int in s.state.heroes.keys():
		if player <= 0: continue
		var r := row(s.state, player)
		if not relevant(s, r, op, args): continue
		if r.is_empty():
			if not temporary(s.state, s.state.current_party) and (op != "CreateParty" or args.size() < 2 or not temporary(s.state, str(args[1]))): continue
			r = create(s, player)
			# An offline guest from an old save was not deployed by ensure().
			# Establish its current chapter before a nested switch or return.
			if not r.is_empty() and temporary(s.state, s.state.current_party):
				var previous := context(s, r)
				seed_role(previous, s.state.current_party)
				remember(s, r, previous, true)
		if r.is_empty(): continue
		var st := context(s, r)
		var before := st.current_party
		Progress.operation(st, op, args)
		var changed := before != st.current_party
		if changed and not temporary(st, st.current_party) and bool(r.shared):
			# Class-only guests originally share the host bag. Their temporary
			# findings return to it once; entering a role never clones that bag.
			var destination := s.state._bag(st.current_party)
			destination.items.append_array(st.items)
			destination.money = int(destination.money) + st.money
			if s.state.current_party == st.current_party: s.state.money = int(destination.money)
			st.items = []; st.money = 0
		remember(s, r, st, changed)


static func personal(s: Session, player: int, hero: Dictionary, bag: Dictionary) -> Dictionary:
	var r := row(s.state, player)
	if r.is_empty(): return {"hero":hero, "purse":bag}
	var st := context(s, r)
	var roster := st._party_roster(String(r.normal))
	return {"hero":roster[0] if not roster.is_empty() else hero, "purse":st._bag(String(r.normal))}


## Credit stays gated by CoopProgress. Within an eligible checkpoint, save
## each guest's played temporary role, not the host's copy of Nalo/Shaina.
static func progress(s: Session, player: int, dest: CampaignState) -> void:
	var r := row(s.state, player)
	if r.is_empty() or r.party != dest.current_party: return
	var source := context(s, r)
	for party: String in [source.current_party] + source.parties.keys():
		var from := source._party_roster(party)
		var to := dest._party_roster(party)
		if from.is_empty() or to.is_empty(): continue
		var h: Dictionary = from[0].duplicate(true)
		h.erase("guest_unit_name")   # independent saves regain the authored name
		# Match the personal-package representation so a later uncredited
		# checkpoint does not acquire new defaults or change skill key types.
		var normalized := CoopProgress.sanitize_hero(h)
		for key in ["exp", "exp_total", "exp_debt", "str", "dex", "int", "skills", "perks", "aggressive"]:
			h[key] = normalized[key]
		for key in ["prototype", "unit_name", "complexion", "voice", "name"]:
			if to[0].has(key): h[key] = to[0][key]
			elif key == "unit_name": h.erase(key)
		to[0] = h
		var bag := source._bag(party)
		if party == dest.current_party:
			dest.money = int(bag.money); dest.items = bag.items.duplicate()
		else: dest.party_bags[party] = bag.duplicate(true)


## Redeploy only guests whose selected record changed. The host still owns
## the unique named narrative role; extra bodies receive unambiguous names.
static func redeploy(s: Session) -> void:
	var changed := {}
	for u: GameUnit in s.world.units.values():
		var idx := int(u.get_meta("orphan_of", u.controller))
		if idx <= 0 or not u.has_meta("hero") or u.get_meta("hero").has("merc"): continue
		var roster: Array = s.state.heroes.get(idx, [])
		if roster.any(func(h): return is_same(h, u.get_meta("hero"))): continue
		if s.players_include(idx): changed[idx] = true
		else:
			s.world.remove_unit(u)
			s.broadcast({"t":"remove", "uid":u.uid})
	for idx: int in changed: s.redeploy_party(idx)
