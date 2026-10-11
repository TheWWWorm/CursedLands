extends RefCounted
## Save identities are independent of deployment IDs. VM and effect records
## share these rules; a missing identity must never fall back to a recycled UID.

static func hero_key(u: GameUnit, state: CampaignState = null) -> Array:
	if not u.has_meta("hero") or u.get_meta("hero").has("merc"):
		return []
	var owner := int(u.get_meta("orphan_of", u.controller))
	if state == null and u.world and u.world.session: state = u.world.session.state
	if state == null: return []
	var roster: Array = state.heroes.get(owner, [])
	for i in roster.size():
		if is_same(roster[i], u.get_meta("hero")): return [owner, i]
	return []


static func pet_key(u: GameUnit) -> String:
	var key := String(u.get_meta("pet_id", ""))
	if key.is_empty():
		key = Crypto.new().generate_random_bytes(16).hex_encode()
		u.set_meta("pet_id", key)
	return key


static func of(actor) -> Array:
	if not is_instance_valid(actor) or not actor is GameUnit: return []
	var u: GameUnit = actor
	if u.has_meta("hero"):
		var h: Dictionary = u.get_meta("hero")
		if h.has("merc"): return ["merc", h.merc]
		var key := hero_key(u)
		if not key.is_empty():
			var ref := ["hero_slot", key[0], key[1]]
			# Named companions embedded in an authored party are shared roles.
			# A protagonist (including a temporary slot-zero substitute) is a
			# physical participant and never inherits this exception.
			var name := String(h.get("unit_name", ""))
			if int(key[1]) > 0 and not name.is_empty() and not name.to_lower().begins_with("hero"):
				ref.append(name)
			return ref
		return ["hero", String(h.get("unit_name", h.get("name", ""))), int(u.get_meta("orphan_of", u.controller))]
	if u.has_meta("pet_id") or int(u.get_meta("tame_stage", 0)) >= 3:
		return ["pet", pet_key(u)]
	return ["uid", u.uid]


static func resolve(world: GameWorld, ref: Array) -> GameUnit:
	if world == null or ref.size() < 2: return null
	if ref[0] == "uid": return world.units.get(int(ref[1]), world.looted.get(int(ref[1])))
	for u: GameUnit in world.units.values() + world.looted.values():
		if ref[0] == "pet" and u.get_meta("pet_id", "") == ref[1]: return u
		if not u.has_meta("hero"): continue
		var h: Dictionary = u.get_meta("hero")
		if ref[0] == "merc" and str(h.get("merc", "")) == str(ref[1]): return u
		if ref.size() < 3: continue
		if ref[0] == "hero_slot" and hero_key(u, world.session.state if world.session else null) == [int(ref[1]), int(ref[2])] \
				and (ref.size() < 4 or String(h.get("unit_name", "")) == String(ref[3])): return u
		if ref[0] == "hero" and u.controller == int(ref[2]) \
				and String(h.get("unit_name", h.get("name", ""))) == String(ref[1]): return u
	return null


## Effects refer to physical actors. Only the recipient changes controller;
## host protagonists do not become that recipient. VM narrative roles opt in
## explicitly to the shared-story mapping used by co-op continuations.
static func project(ref: Array, player: int, shared_story := false) -> Array:
	if ref.size() >= 3 and ref[0] in ["hero_slot", "hero"]:
		var owner_index := 1 if ref[0] == "hero_slot" else 2
		var owner := int(ref[owner_index])
		var companion: bool = ref[0] == "hero_slot" and ref.size() >= 4 and int(ref[2]) > 0 and not String(ref[3]).is_empty()
		if owner != player and not ((shared_story or companion) and owner == 0): return []
		var out := ref.duplicate(true)
		out[owner_index] = 0
		return out
	return ref.duplicate(true)


static func project_value(value: Variant, player: int) -> Variant:
	if value is Array:
		if value.size() >= 2 and value[0] is String and value[0] in ["hero_slot", "hero", "pet", "merc", "uid"]:
			return project(value, player)
		return value.map(func(v): return project_value(v, player))
	if value is Dictionary:
		var out := {}
		for k in value: out[k] = project_value(value[k], player)
		return out
	return value


## A spell may have started before its target finished taming. Refresh its
## captured map ID while the old world still exists, before collecting pets.
static func refresh_value(world: GameWorld, value: Variant) -> Variant:
	if value is Array:
		if value.size() >= 2 and value[0] is String and value[0] in ["hero_slot", "hero", "pet", "merc", "uid"]:
			var actor := resolve(world, value)
			return of(actor) if actor else value.duplicate(true)
		return value.map(func(v): return refresh_value(world, v))
	if value is Dictionary:
		var out := {}
		for k in value: out[k] = refresh_value(world, value[k])
		return out
	return value
