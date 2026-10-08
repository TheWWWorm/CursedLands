extends RefCounted
## Frozen-scene prototype of Compatibility light-preserving batch membership.
## Godot 5b4e0cb0f RendererSceneCull::_scene_cull chooses lights by distance
## from transformed AABB centre / max(range * energy, 0.01), per light type.
## Default groups require the complete light set to fit the budget. Re-ranking
## truncated sets is an explicit negative control for light-history mismatches.
## This does not yet track live lights, visibility, materials or object lifetime.

static func signature(bounds: AABB, layers: int, lights: Array, limit: int, total_limit: int, rank_overflow := false) -> Variant:
	if limit <= 0 or total_limit <= 0: return []
	var kinds := {}
	for light: Dictionary in lights:
		if (int(light.mask) & layers) == 0 or not bounds.intersects(light.bounds):
			continue
		if not kinds.has(light.kind): kinds[light.kind] = []
		kinds[light.kind].append(light)
	var chosen: Array[int] = []
	for kind in kinds:
		var candidates: Array = kinds[kind]
		# Current energy is insufficient to reconstruct an existing truncated
		# engine list: energy-only changes do not dirty geometry pairing. The
		# ranked mode is a diagnostic control, not the default grouping rule.
		if candidates.size() > limit and not rank_overflow: return null
		# Engine traversal order is not exposed. Do not guess its first-N set
		# or resolve a tie at the cutoff differently from the original mesh.
		if candidates.size() > total_limit: return null
		if candidates.size() <= limit:
			for candidate: Dictionary in candidates: chosen.append(candidate.id)
			continue
		candidates = candidates.map(func(light: Dictionary): return {"id":light.id,
			"score":bounds.get_center().distance_to(light.bounds.get_center()) / maxf(light.range * light.energy, 0.01)})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score)
		if candidates.size() > limit and is_equal_approx(candidates[limit - 1].score, candidates[limit].score):
			return null
		for i in mini(limit, candidates.size()): chosen.append(candidates[i].id)
	chosen.sort()
	return chosen


static func partition(members: Array, lights: Array, limit: int, total_limit: int, rank_overflow := false) -> Array:
	var result: Array = []
	for member: Dictionary in members:
		var selected = signature(member.bounds, member.layers, lights, limit, total_limit, rank_overflow)
		var placed := false
		if selected != null:
			for group: Dictionary in result:
				if group.selected != selected or group.layers != member.layers: continue
				var merged: AABB = group.bounds.merge(member.bounds)
				# Matching the original members alone is insufficient: the
				# combined bounds can pick an extra light between the objects.
				if signature(merged, member.layers, lights, limit, total_limit, rank_overflow) != selected: continue
				group.members.append(member.item)
				group.bounds = merged
				placed = true
				break
		if not placed:
			result.append({"members":[member.item], "bounds":member.bounds,
				"layers":member.layers, "selected":selected})
	return result.map(func(group: Dictionary): return group.members)
