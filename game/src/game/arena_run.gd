class_name ArenaRun
extends RefCounted
## Pure run state. The UI and seeded balance policies use these same operations.

signal changed

const SAVE_PATH := "user://arena-expedition.json"
const PROFILE_PATH := "user://arena-profile.json"
const DEPLOY := Rect2(20, 20, 10.5, 24)
var run_seed := 1
var challenge := 0
var starter := 0 # Legacy save/policy metadata; never grants creatures.
var wave := 1
var wave_limit := ArenaRules.WAVE_COUNT
var gold := ArenaRules.OPENING_GOLD
var lives := 3
var stage := "prepare"
var preparation_left := ArenaRules.PREPARATION_SECONDS
# Short-lived rendered staging lock; never persisted in a save.
var preparing_battle := false
var army: Array[Dictionary] = []
var shop: Array[Dictionary] = []
var boons: Array[String] = []
var free_refresh := false
var training := 0
var battle_savings := 0
var rewards: Array[Dictionary] = []
var history: Array[Dictionary] = []
var last_result := {}
var next_uid := 1
var rng := RandomNumberGenerator.new()
var auto_save := true
var save_error := false
var last_evolutions: Array[int] = []
var _undo: Array[Dictionary] = []
## The rendered match checks scenery as well as the formation's reserved slots.
var deployment_check: Callable


func begin(seed_value: int, chosen_starter := 0, difficulty := 0) -> void:
	preparing_battle = false
	run_seed = maxi(1, seed_value)
	starter = clampi(chosen_starter, 0, 2)
	challenge = clampi(difficulty, 0, 2)
	wave = 1; wave_limit = round_limit(); gold = ArenaRules.OPENING_GOLD; lives = life_limit(); stage = "prepare"; next_uid = 1
	army.clear(); shop.clear(); boons.clear(); rewards.clear(); history.clear(); _undo.clear()
	last_result = {}
	free_refresh = false
	training = 0; battle_savings = 0
	preparation_left = ArenaRules.preparation_seconds(challenge)
	last_evolutions.clear()
	rng.seed = run_seed
	# Deal six different starting creatures from every island.
	var families := ArenaRules.recruit_pool(capacity())
	for i in range(families.size() - 1, 0, -1):
		var other := rng.randi_range(0, i)
		var held: int = families[i]
		families[i] = families[other]; families[other] = held
	# Six different recruits leave room to choose a direction before rolling.
	var opening: Array[int] = families.duplicate()
	while opening.size()<6: opening.append(families[rng.randi_range(0,families.size()-1)])
	# Keep the initial hand playable without biasing subsequent shop rolls.
	for melee in [true,false]:
		if not opening.slice(0,6).any(func(f):return (ArenaRules.FAMILIES[f].role=="Melee")==melee):
			var substitute: int=families.filter(func(f):return (ArenaRules.FAMILIES[f].role=="Melee")==melee)[0]
			opening[5]=substitute
	for family in opening.slice(0,6): shop.append({"family": family, "rank": 0, "locked": false})
	_touch()


func capacity() -> int:
	return ArenaRules.level_for_xp(experience())


func experience() -> int:
	return mini(ArenaRules.MAX_TRAINING, wave - 1 + training)


func level_progress() -> int:
	return experience() - int(ArenaRules.LEVEL_XP[capacity()])


func level_needed() -> int:
	return 0 if capacity() == ArenaRules.MAX_ARMY else int(ArenaRules.LEVEL_XP[capacity() + 1]) - int(ArenaRules.LEVEL_XP[capacity()])


func train() -> String:
	if not can_shop(): return RemakeText.t("Finish the current encounter first.")
	if experience() >= ArenaRules.MAX_TRAINING: return RemakeText.t("Your army is at full strength.")
	var error := spending_error(ArenaRules.TRAINING_COST)
	if not error.is_empty(): return error
	_checkpoint()
	gold -= ArenaRules.TRAINING_COST
	training += mini(ArenaRules.TRAINING_XP, ArenaRules.MAX_TRAINING - experience())
	_touch()
	return ""


func win_streak() -> int:
	var wins := 0
	for i in range(history.size() - 1, -1, -1):
		if int(history[i].winner) != 0: break
		wins += 1
	return wins


## Snapshot savings at battle start. Every round pays base income and interest;
## victory and streak bonuses require a win. Every outcome advances the wave.
func income_preview(savings := -1, won := true) -> Dictionary:
	var bank := gold if savings < 0 else savings
	var streak := win_streak() + 1
	var bonus := (2 if streak >= 6 else 1 if streak >= 3 else 0) if won else 0
	var interest := mini(ArenaRules.INTEREST_CAP, maxi(0, bank) / 10)
	var bounty := ArenaRules.BASE_INCOME
	var victory := ArenaRules.WIN_INCOME if won else 0
	return {"base": bounty, "victory": victory,
		"interest": interest, "streak": bonus,
		"total": bounty + victory + interest + bonus}


func bench_limit() -> int:
	return 11 if "reserve" in boons else 8


func deployed_count() -> int:
	return army.filter(func(u): return u.deployed).size()


func bench_count() -> int:
	return army.size() - deployed_count()


func refresh_cost() -> int:
	return 0 if free_refresh else 1 if "merchant" in boons else 2


func spending_error(cost: int) -> String:
	if gold < cost: return RemakeText.t("Not enough gold.")
	if army.is_empty() and gold - cost < ArenaRules.MIN_RECRUIT_COST:
		return RemakeText.t("Recruit a creature before spending the rest of your gold.")
	return ""


func alliances() -> Dictionary:
	return ArenaAlliances.counts(army)


func unit(uid: int) -> Dictionary:
	for entry: Dictionary in army:
		if int(entry.uid) == uid: return entry
	return {}


func _recruit(family: int, rank: int, investment: int, special := "") -> Dictionary:
	var entry := {"uid": next_uid, "family": family, "rank": rank,
		"prototype": special if not special.is_empty() else ArenaRules.prototype(family, rank),
		"investment": investment, "deployed": false, "point": [22.0, 32.0]}
	next_uid += 1
	army.append(entry)
	return entry


func purchase_error(index: int) -> String:
	if not can_shop(): return RemakeText.t("Finish the current encounter first.")
	if index < 0 or index >= shop.size() or int(shop[index].family) < 0: return RemakeText.t("This offer has already been recruited.")
	var family := int(shop[index].family)
	var rank := int(shop[index].get("rank", 0))
	var cost := offer_cost(shop[index])
	if gold < cost: return RemakeText.t("Not enough gold.")
	var matching := army.filter(func(entry): return entry.family == family and entry.rank == rank).size()
	var needed := ArenaRules.evolution_copies(family, rank)
	if bench_count() >= bench_limit() and (needed == 0 or matching + 1 < needed) and recruit_point(family) == Vector2.INF:
		return RemakeText.t("Reserves full. Deploy or sell a creature first.")
	return ""


func buy(index: int) -> String:
	var error := purchase_error(index)
	if error: return error
	var family := int(shop[index].family)
	var cost := offer_cost(shop[index])
	var rank := int(shop[index].get("rank", 0))
	_checkpoint()
	gold -= cost
	var recruit := _recruit(family, rank, cost)
	shop[index] = {"family": -1, "locked": false}
	combine_ready()
	if not unit(recruit.uid).is_empty():
		_auto_deploy(recruit)
	else:
		for uid in last_evolutions:
			var evolved := unit(uid)
			if not evolved.is_empty(): _auto_deploy(evolved)
	_touch()
	return ""


func recruit_point(family: int) -> Vector2:
	if stage != "prepare" or deployed_count() >= capacity(): return Vector2.INF
	var proto := GameData.db.find("monster_prototypes", ArenaRules.prototype(family, 0))
	var ranged := float(proto.get("attack_range", 0)) > 0 or not Array(proto.get("spells", [])).is_empty()
	for x: float in ([22.0, 25.0, 28.0] if ranged else [28.0, 25.0, 22.0]):
		for y: float in [32.0, 28.0, 36.0, 24.0, 40.0, 21.0, 43.0]:
			var point := Vector2(x, y)
			if army.any(func(entry): return entry.deployed and point.distance_to(Vector2(entry.point[0], entry.point[1])) < 2.5): continue
			if deployment_check.is_valid() and not deployment_check.call(point): continue
			return point
	return Vector2.INF


func _auto_deploy(entry: Dictionary) -> void:
	if entry.deployed: return
	var point := recruit_point(int(entry.family))
	if point == Vector2.INF: return
	entry.deployed = true
	entry.point = [point.x, point.y]


## A purchase and every resulting evolution are one undoable action. Prefer a
## deployed copy, keeping its identity and position through chained evolutions.
func combine_ready() -> void:
	last_evolutions.clear()
	if not can_shop(): return
	for family in ArenaRules.FAMILIES.size():
		for rank in 2:
			var needed := ArenaRules.evolution_copies(family, rank)
			if needed == 0: continue
			while true:
				var matching := army.filter(func(entry): return entry.family == family and entry.rank == rank)
				if matching.size() < needed: break
				var kept: Dictionary = matching[0]
				for entry: Dictionary in matching:
					if entry.deployed:
						kept = entry
						break
				_merge(kept)
				last_evolutions.append(int(kept.uid))


func refresh() -> String:
	if not can_shop(): return RemakeText.t("Finish the current encounter first.")
	if shop.all(func(offer): return offer.locked): return RemakeText.t("Unlock an offer before refreshing.")
	var error := spending_error(refresh_cost())
	if not error.is_empty(): return error
	gold -= refresh_cost()
	free_refresh = false
	_undo.clear() # Revealed randomness is never refunded by undo.
	_roll_shop(true)
	_touch()
	return ""


func lock_offer(index: int) -> void:
	if not can_shop() or index < 0 or index >= shop.size() or int(shop[index].family) < 0: return
	var was_locked := bool(shop[index].locked)
	shop[index].locked = not was_locked
	_touch()


func _roll_shop(keep_lock: bool) -> void:
	var old := shop.duplicate(true)
	var slots := 6 if "scout" in boons else 5
	# Keep every locked slot, including the opening's sixth offer. Once that
	# extra slot is bought or unlocked, the next refresh returns to five.
	if keep_lock and old.size() > slots:
		for index in range(slots, old.size()):
			if old[index].locked: slots = index + 1
	shop.clear()
	var odds: Array = ArenaRules.SHOP_ODDS[capacity()]
	for i in slots:
		if keep_lock and i < old.size() and old[i].locked and int(old[i].family) >= 0:
			shop.append(old[i])
		else:
			var roll := rng.randi_range(0, 99)
			var tier := 1
			for weight: int in odds:
				if roll < weight: break
				roll -= weight
				tier += 1
			var candidates: Array[int] = []
			for family in ArenaRules.ACTIVE_FAMILIES:
				if int(ArenaRules.FAMILIES[family].tier) != tier: continue
				candidates.append(family)

			shop.append({"family": candidates[rng.randi_range(0, candidates.size() - 1)], "rank": 0, "locked": false})
	# An empty company must remain recoverable after a paid refresh/improvement.
	if army.is_empty() and not shop.any(func(offer): return int(offer.family) >= 0 and offer_cost(offer) <= ArenaRules.MIN_RECRUIT_COST):
		for i in shop.size():
			if not shop[i].locked:
				var affordable := ArenaRules.recruit_pool(capacity()).filter(func(family): return int(ArenaRules.FAMILIES[family].cost) <= ArenaRules.MIN_RECRUIT_COST)
				shop[i] = {"family": affordable[rng.randi_range(0, affordable.size() - 1)], "rank": 0, "locked": false}
				break


func offer_cost(offer: Dictionary) -> int:
	var rule: Dictionary = ArenaRules.FAMILIES[int(offer.family)]
	var rank := int(offer.get("rank", 0))
	var copies := 1
	for previous in rank: copies *= ArenaRules.evolution_copies(int(offer.family), previous)
	return int(rule.cost) * copies


func deploy(uid: int, point: Vector2) -> String:
	if preparing_battle: return RemakeText.t("Finish the current encounter first.")
	if stage != "prepare": return RemakeText.t("Arrange your army between battles.")
	var entry := unit(uid)
	if entry.is_empty(): return RemakeText.t("Choose a creature from your army.")
	if not is_finite(point.x) or not is_finite(point.y) or not DEPLOY.has_point(point):
		return RemakeText.t("Deploy inside the blue half of the battlefield.")
	if not entry.deployed and deployed_count() >= capacity(): return RemakeText.t("Army full. Upgrade your company or withdraw a creature.")
	for other: Dictionary in army:
		if other.uid == uid or not other.deployed: continue
		if point.distance_to(Vector2(other.point[0], other.point[1])) < 2.5:
			return RemakeText.t("Leave more space between creatures.")
	_checkpoint()
	entry.deployed = true
	entry.point = [point.x, point.y]
	_touch()
	return ""


func bench(uid: int) -> String:
	if stage != "prepare": return RemakeText.t("Arrange your army between battles.")
	var entry := unit(uid)
	if entry.is_empty() or not entry.deployed: return ""
	if bench_count() >= bench_limit(): return RemakeText.t("Bench full. Deploy, evolve or sell a creature first.")
	_checkpoint()
	entry.deployed = false
	_touch()
	return ""


func swap_from_bench(uid: int, deployed_uid: int) -> String:
	if stage != "prepare": return RemakeText.t("Arrange your army between battles.")
	var incoming := unit(uid)
	var outgoing := unit(deployed_uid)
	if incoming.is_empty() or outgoing.is_empty() or incoming.deployed or not outgoing.deployed:
		return RemakeText.t("Select a reserve, then click one of your deployed creatures to swap them.")
	_checkpoint()
	incoming.deployed = true
	incoming.point = outgoing.point.duplicate()
	outgoing.deployed = false
	_touch()
	return ""


func sell(uid: int) -> String:
	if not can_shop(): return RemakeText.t("Finish the current encounter first.")
	var entry := unit(uid)
	if entry.is_empty(): return RemakeText.t("Choose a creature from your army.")
	if stage != "prepare" and entry.deployed: return RemakeText.t("Only reserves can be sold during battle.")
	_checkpoint()
	gold += sale_value(entry)
	army.erase(entry)
	_touch()
	return ""


func sale_value(entry: Dictionary) -> int:
	if int(entry.family) < 0: return int(entry.investment) / 3
	if int(entry.rank) == 0: return int(entry.investment)
	return mini(offer_cost(entry), int(entry.investment) * 2 / 3)


func copies(entry: Dictionary) -> Array[Dictionary]:
	if entry.is_empty() or int(entry.family) < 0: return []
	var found: Array[Dictionary] = []
	for other: Dictionary in army:
		if other.family == entry.family and other.rank == entry.rank: found.append(other)
	return found


func evolution_error(uid: int) -> String:
	if stage != "prepare" or preparing_battle: return RemakeText.t("Evolve between battles.")
	var entry := unit(uid)
	if entry.is_empty(): return RemakeText.t("Choose a creature from your army.")
	var needed := ArenaRules.evolution_copies(int(entry.family), int(entry.rank))
	if needed == 0: return RemakeText.t("This creature has reached its final form.")
	if copies(entry).size() < needed: return RemakeText.t("Collect %d copies of this form to evolve.") % needed
	return ""


func evolve(uid: int) -> String:
	var error := evolution_error(uid)
	if error: return error
	_checkpoint()
	var entry := unit(uid)
	_merge(entry)
	_touch()
	return ""


func _merge(entry: Dictionary) -> void:
	var needed := ArenaRules.evolution_copies(int(entry.family), int(entry.rank))
	var consumed := 0
	for other: Dictionary in copies(entry):
		if other.uid == entry.uid: continue
		entry.investment += other.investment
		army.erase(other)
		consumed += 1
		if consumed == needed - 1: break
	entry.rank += 1
	entry.prototype = ArenaRules.prototype(entry.family, entry.rank)


## The presentation clock is independent of combat speed and undo history.
func elapse_preparation(seconds: float) -> bool:
	if stage != "prepare": return false
	preparation_left = maxf(0.0, preparation_left - maxf(0.0, seconds))
	return preparation_left <= 0.0


func start_battle(timed_out := false) -> String:
	if stage != "prepare": return RemakeText.t("Finish the current encounter first.")
	if deployed_count() == 0 and not (timed_out and preparation_left <= 0): return RemakeText.t("Deploy at least one creature before starting.")
	battle_savings = gold
	stage = "fight"
	_undo.clear()
	_touch()
	return ""


func arrange() -> void:
	if stage != "prepare" or preparing_battle: return
	_checkpoint()
	var ordered := army.duplicate()
	ordered.sort_custom(func(a, b):
		var pa := GameData.db.find("monster_prototypes", a.prototype)
		var pb := GameData.db.find("monster_prototypes", b.prototype)
		return float(pa.get("base_level", 0)) > float(pb.get("base_level", 0)))
	for entry: Dictionary in army: entry.deployed = false
	var front := 0
	var back := 0
	for i in mini(capacity(), ordered.size()):
		var entry: Dictionary = ordered[i]
		var proto := GameData.db.find("monster_prototypes", entry.prototype)
		var ranged := float(proto.get("attack_range", 0)) > 0 or not Array(proto.get("spells", [])).is_empty()
		var number := back if ranged else front
		entry.deployed = true
		entry.point = [(22.0 if ranged else 27.0) if number < 5 else 24.0,
			32.0 + [0.0, -4.0, 4.0, -8.0, 8.0][number % 5] + (2.0 if number >= 5 else 0.0)]
		if ranged: back += 1
		else: front += 1
	_touch()


func battle_seed() -> int:
	var attempts := history.filter(func(result): return int(result.wave) == wave and int(result.winner) != 0).size()
	return run_seed * 7919 + wave * 104729 + challenge * 31 + attempts * 15485863


func resolve(winner: int, seconds: float, damage: Array, _survivors: Array = [0, 0]) -> void:
	if stage != "fight": return
	last_result = {"wave": wave, "winner": winner, "seconds": seconds, "damage": damage.duplicate(), "gold": 0}
	if deployed_count() == 0: last_result["empty_army"] = true
	var income := income_preview(battle_savings, winner == 0)
	gold += int(income.total)
	last_result.gold = int(income.total)
	last_result.income = income
	if winner != 0:
		lives -= 1
		free_refresh = true
	last_result.health_lost = 1 if winner != 0 else 0
	history.append(last_result.duplicate(true))
	stage = "lost" if lives <= 0 else "won" if wave == wave_limit else "result"
	if auto_save: _update_profile()
	_touch()


func advance() -> void:
	if stage != "result": return
	if wave % 5 == 0:
		stage = "reward"
		_make_rewards()
	else:
		_next_wave()
	_touch()


func _next_wave() -> void:
	wave += 1
	stage = "prepare"
	preparation_left = ArenaRules.preparation_seconds(challenge)
	_undo.clear()
	_roll_shop(true)


func _make_rewards() -> void:
	rewards.clear()
	if experience() < ArenaRules.MAX_TRAINING: rewards.append({"kind": "experience"})
	else: rewards.append({"kind": "companion", "prototype": ArenaRules.companion(wave)})
	var choices: Array[String] = ["merchant", "reserve", "scout"]
	choices = choices.filter(func(k): return k not in boons)
	if not choices.is_empty(): rewards.append({"kind": choices[rng.randi_range(0, choices.size() - 1)]})
	else: rewards.append({"kind": "companion", "prototype": ArenaRules.companion(wave)})
	# At maximum level and with all upgrades, do not repeat the companion.
	if rewards[0] == rewards[1]: rewards.remove_at(1)
	rewards.append({"kind": "life" if lives < 3 else "purse"})


func choose_reward(index: int) -> String:
	if stage != "reward" or index < 0 or index >= rewards.size(): return RemakeText.t("Choose one of the offered rewards.")
	var reward: Dictionary = rewards[index]
	if reward.kind == "companion" and bench_count() > bench_limit():
		return RemakeText.t("Your reserves already hold an extra ally. Choose another reward.")
	match String(reward.kind):
		"experience": training += mini(10, ArenaRules.MAX_TRAINING - experience())
		"companion":
			# A reward must never vanish into a full bench. It arrives in one
			# temporary overflow slot; purchases stay blocked until resolved.
			_recruit(11, 1, int(ArenaRules.FAMILIES[11].cost)*3)
			combine_ready()
		"purse": gold += 8
		"supplies": gold += 6
		"life": lives = mini(3, lives + 1)
		_: boons.append(String(reward.kind))
	rewards.clear()
	_next_wave()
	_touch()
	return ""


func _checkpoint() -> void:
	# Combat shopping is committed immediately. A failed wave must not make
	# those purchases undoable after its income/result has already resolved.
	if stage != "prepare": return
	_undo.append({"army": army.duplicate(true), "shop": shop.duplicate(true), "gold": gold, "next_uid": next_uid, "training": training})
	if _undo.size() > 30: _undo.pop_front()


func undo() -> void:
	if stage != "prepare" or preparing_battle or _undo.is_empty(): return
	var previous: Dictionary = _undo.pop_back()
	army.assign(previous.army); shop.assign(previous.shop)
	gold = previous.gold; next_uid = previous.next_uid; training = previous.training
	_touch()


func can_undo() -> bool:
	return stage == "prepare" and not preparing_battle and not _undo.is_empty()


func can_shop() -> bool:
	return lives > 0 and not preparing_battle and stage in ["prepare", "fight", "result"]


func snapshot() -> Dictionary:
	return {"version": ArenaRules.VERSION, "seed": str(run_seed), "rng": str(rng.state),
		"challenge": challenge, "starter": starter, "wave": wave, "wave_limit": wave_limit, "gold": gold, "lives": lives,
		"stage": stage, "preparation_left": preparation_left, "army": army.duplicate(true), "shop": shop.duplicate(true),
		"boons": boons.duplicate(), "rewards": rewards.duplicate(true), "history": history.duplicate(true),
		"free_refresh": free_refresh,
		"training": training, "battle_savings": battle_savings,
		"last_result": last_result.duplicate(true), "next_uid": next_uid}


func restore(data: Dictionary) -> bool:
	data = data.duplicate(true)
	# Validate before changing any live state. JSON numbers arrive as floats.
	if not _integer(data.get("version"), 1, ArenaRules.VERSION): return false
	if not data.get("stage", "") in ["prepare", "fight", "result", "reward", "won", "lost"]: return false
	for key in ["army", "shop", "boons", "rewards", "history"]:
		if not data.get(key) is Array: return false
	for key in ["seed", "rng"]:
		if not data.get(key) is String or not data[key].is_valid_int(): return false
	if not _integer(int(data.seed), 1, 99999999): return false
	if not _integer(data.get("wave"), 1, round_limit()): return false
	if not _integer(data.get("gold"), 0, 100000) or not _integer(data.get("lives"), 0, life_limit()): return false
	if not _integer(data.get("challenge"), 0, 2) or not _integer(data.get("starter"), 0, 2): return false
	if not _integer(data.get("next_uid"), 1, 100000): return false
	if int(data.version) in range(2, 8) and (not data.has("pact") or not data.has("pact_rank")): return false
	if not data.get("free_refresh", false) is bool: return false
	var saved_pact = data.get("pact", "") if int(data.version) > 1 else ""
	var saved_rank = data.get("pact_rank", 0) if int(data.version) > 1 else 0
	var saved_preparation := ArenaRules.preparation_seconds(int(data.challenge)) if int(data.version) >= 9 else 45.0
	# A resumed schema-8 Champion run may still have its original 45 seconds.
	# Its next snapshot must remain readable after the schema upgrade.
	var maximum_preparation := ArenaRules.PREPARATION_SECONDS if int(data.version) >= 9 else 45.0
	if not _number(data.get("preparation_left", saved_preparation), 0, maximum_preparation): return false
	if not _integer(data.get("shop_level", 0), 0, 2): return false
	if not _integer(data.get("training", 0), 0, ArenaRules.MAX_TRAINING): return false
	if not _integer(data.get("battle_savings", 0), 0, 100000): return false
	if not saved_pact is String or saved_pact not in ["", "hunt", "tribe", "vanguard"]: return false
	if not _integer(saved_rank, 0, 2): return false
	if saved_pact.is_empty() and int(saved_rank) != 0: return false
	if not saved_pact.is_empty() and int(data.wave) < 4: return false
	if int(saved_rank) > 0 and int(data.wave) < (10 if int(saved_rank) == 1 else 16): return false
	if data.army.size() > ArenaRules.MAX_ARMY + 12 or data.boons.size() > 3 or data.history.size() > round_limit() + 16: return false
	var seen := {}
	var deployed := 0
	var points: Array[Vector2] = []
	for entry in data.army:
		if not entry is Dictionary or not entry.get("point") is Array or entry.point.size() != 2: return false
		if not _integer(entry.get("uid"), 1, 100000) or seen.has(int(entry.uid)): return false
		if not entry.get("deployed") is bool or not entry.get("prototype") is String: return false
		if not _integer(entry.get("family"), -1, (ArenaRules.LEGACY_FORMS.size() if int(data.version)<11 else ArenaRules.FAMILIES.size()) - 1) or not _integer(entry.get("rank"), 0, 2): return false
		if not _integer(entry.get("investment"), 1, 10000): return false
		var family := int(entry.family)
		var rank := int(entry.rank)
		if family >= 0:
			if int(data.version)<11:
				if entry.prototype != ArenaRules.LEGACY_FORMS[family][rank]: return false
				family = int(ArenaRules.LEGACY_FAMILIES[family])
				entry.family=family; entry.prototype=ArenaRules.prototype(family,rank)
			elif family not in ArenaRules.ACTIVE_FAMILIES or entry.prototype != ArenaRules.prototype(family,rank): return false
		if family < 0:
			if entry.prototype not in ArenaRules.COMPANIONS or rank != 0: return false
			entry.family=11; entry.prototype=ArenaRules.prototype(11,0)
		if GameData.db.find("monster_prototypes", entry.prototype).is_empty(): return false
		for value in entry.point:
			if not _number(value, 0, 64): return false
		var point := Vector2(entry.point[0], entry.point[1])
		if entry.deployed:
			if not DEPLOY.has_point(point): return false
			for other in points:
				if point.distance_to(other) < 2.49: return false
			points.append(point)
			deployed += 1
		seen[int(entry.uid)] = true
	var capacity_at_wave := ArenaRules.level_for_xp(int(data.wave) - 1 + int(data.get("training", 0))) if int(data.version) >= 8 else mini(ArenaRules.MAX_ARMY, 3 + (int(data.wave) - 1 + int(data.get("training", 0))) / 3)
	if deployed > capacity_at_wave: return false
	var saved_boons := {}
	for key in data.boons:
		if not key is String or key not in ["merchant", "reserve", "scout"] or saved_boons.has(key): return false
		saved_boons[key] = true
	if data.army.size() - deployed > (12 if saved_boons.has("reserve") else 9): return false
	var opening_shelf: bool = int(data.version) >= 5 and int(data.wave) == 1 and data.shop.size() == 6
	var base_slots := 6 if saved_boons.has("scout") else 5
	if not opening_shelf and data.shop.size() != base_slots:
		if int(data.version) < 10 or data.shop.size() != 6: return false
	var locks := 0
	for offer in data.shop:
		if not offer is Dictionary or not _integer(offer.get("family"), -1, (ArenaRules.LEGACY_FORMS.size() if int(data.version)<11 else ArenaRules.FAMILIES.size()) - 1) or not offer.get("locked") is bool: return false
		if not _integer(offer.get("rank", 0), 0, 2): return false
		if int(offer.family)>=0:
			if int(data.version)<11: offer.family=int(ArenaRules.LEGACY_FAMILIES[int(offer.family)])
			elif int(offer.family) not in ArenaRules.ACTIVE_FAMILIES: return false
		if offer.locked:
			if int(offer.family) < 0: return false
			locks += 1
	if int(data.version) < 10 and locks > 1: return false
	if data.stage == "reward":
		if int(data.wave) % (5 if int(data.version) >= 8 else 3) != 0 or int(data.wave) >= ArenaRules.WAVE_COUNT: return false
		if data.rewards.size() != 3 and not (data.rewards.size() == 2 and saved_boons.size() == 3): return false
	elif not data.rewards.is_empty(): return false
	var reward_kinds := {}
	for reward in data.rewards:
		if not reward is Dictionary or not reward.get("kind") is String or (not ArenaRules.BOONS.has(reward.kind) and not (int(data.version) < 8 and reward.kind in ["pact", "pact_upgrade"])): return false
		if reward.kind == "companion":
			var expected: String=ArenaRules.COMPANIONS[clampi(int(data.wave)/6-1,0,3)] if int(data.version)<11 else ArenaRules.companion(int(data.wave))
			if reward.get("prototype")!=expected: return false
			reward.prototype=ArenaRules.companion(int(data.wave))
		if reward.kind == "pact":
			if not saved_pact.is_empty() or int(data.wave) % 6 != 3 or not reward.get("pact") in ["hunt", "tribe", "vanguard"]: return false
			if reward_kinds.has(reward.pact): return false
			reward_kinds[reward.pact] = true
		elif reward.kind == "pact_upgrade":
			if saved_pact.is_empty() or int(saved_rank) >= 2 or (int(data.wave) < 9 or int(data.wave) % 6 != 3): return false
		if reward.kind == "supplies" and int(data.wave) < 6: return false
		if reward.kind in saved_boons: return false
	if reward_kinds.size() not in [0, 3]: return false
	for record in data.history:
		if not _valid_result(record, round_limit()) or int(record.wave) > int(data.wave): return false
	if not data.get("last_result") is Dictionary: return false
	if not data.last_result.is_empty() and not _valid_result(data.last_result, round_limit()): return false
	if data.stage in ["result", "reward", "won", "lost"] and data.last_result.is_empty(): return false
	# Completed older expeditions stay completed; active saves join the extended run.
	var saved_limit = data.get("wave_limit", 18 if int(data.version) <= 4 and data.stage == "won" else ArenaRules.WAVE_COUNT)
	if not _integer(saved_limit, 18, round_limit()) or int(saved_limit) not in [18, round_limit()]: return false
	if int(data.wave) > int(saved_limit): return false
	if not valid_terminal(data, int(saved_limit)): return false
	run_seed = int(data.seed); rng.seed = run_seed; rng.state = int(data.rng)
	challenge = int(data.challenge); starter = int(data.starter)
	wave = int(data.wave); wave_limit = int(saved_limit); gold = int(data.gold); lives = int(data.lives)
	stage = "prepare" if data.stage == "fight" else String(data.stage)
	preparation_left = ArenaRules.preparation_seconds(challenge) if data.stage == "fight" else float(data.get("preparation_left", saved_preparation))
	army.assign(data.army.duplicate(true)); shop.assign(data.shop.duplicate(true)); boons.assign(data.boons)
	free_refresh = bool(data.get("free_refresh", false))
	training = int(data.get("training", 0)); battle_savings = int(data.get("battle_savings", 0))
	rewards.assign(data.rewards.duplicate(true)); history.assign(data.history.duplicate(true))
	last_result = data.last_result.duplicate(true)
	next_uid = int(data.next_uid)
	for id in seen: next_uid = maxi(next_uid, int(id) + 1)
	_undo.clear()
	if int(data.version) < 8:
		# Preserve every purchased slot. Convert retired shop/pact investments
		# into XP and remove the obsolete choice before the saved run is shown.
		training = maxi(training, int(ArenaRules.LEVEL_XP[capacity_at_wave]) - (wave - 1))
		training += [0, 10, 28][int(data.get("shop_level", 0))]
		if not saved_pact.is_empty(): training += 5 + int(saved_rank) * 5
		training = mini(training, ArenaRules.MAX_TRAINING)
		if stage == "reward":
			rewards.clear()
			_next_wave()
	combine_ready()
	return true


static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high


static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value, low, high) and float(value) == floorf(float(value))


static func _valid_result(value: Variant, limit := ArenaRules.WAVE_COUNT) -> bool:
	if not value is Dictionary: return false
	if not _integer(value.get("wave"), 1, limit) or not _integer(value.get("winner"), -1, 1): return false
	if not _number(value.get("seconds"), 0, 301) or not _integer(value.get("gold"), 0, 15): return false
	if value.has("income"):
		if not value.income is Dictionary: return false
		for key in ["base", "victory", "interest", "streak", "total"]:
			if not _integer(value.income.get(key), 0, 15): return false
		if int(value.income.total) != int(value.gold): return false
		if int(value.income.base) + int(value.income.victory) + int(value.income.interest) + int(value.income.streak) != int(value.income.total): return false
	if not value.get("damage") is Array or value.damage.size() != 2: return false
	return _number(value.damage[0], 0, 10000000) and _number(value.damage[1], 0, 10000000)


func load_saved() -> bool:
	if not FileAccess.file_exists(save_path()): return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path()))
	return restore(data) if data is Dictionary else false


func save() -> bool:
	return _write_json(save_path(), snapshot())


static func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK


static func profile() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH)) if FileAccess.file_exists(PROFILE_PATH) else null
	var clean := {"best_wave": 0, "wins": 0, "challenge": 0}
	if data is Dictionary:
		for key in clean:
			var value = data.get(key)
			var limit := ArenaRules.WAVE_COUNT if key == "best_wave" else 2 if key == "challenge" else 2147483647
			if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= 0 and value <= limit:
				clean[key] = int(value)
	return clean


func _update_profile() -> void:
	var data := profile()
	data.best_wave = maxi(int(data.get("best_wave", 0)), wave if stage == "won" or last_result.winner == 0 else wave - 1)
	if stage == "won":
		data.wins = int(data.get("wins", 0)) + 1
		data.challenge = mini(2, maxi(int(data.get("challenge", 0)), challenge + 1))
	_write_json(PROFILE_PATH, data)


func _touch() -> void:
	if auto_save: save_error = not save()
	changed.emit()


func round_limit() -> int:
	return ArenaRules.WAVE_COUNT


func life_limit() -> int:
	return 3


func save_path() -> String:
	return SAVE_PATH


func valid_terminal(data: Dictionary, limit: int) -> bool:
	return not (data.stage == "won" and (int(data.wave) != limit or (int(data.version) < 10 and int(data.last_result.winner) != 0))) and ((data.stage == "lost") == (int(data.lives) == 0))


func enemy_formation() -> Array[Dictionary]:
	return ArenaRules.enemies(wave, run_seed, challenge)


func enemy_army() -> Array[Dictionary]:
	return []


func round_title() -> String:
	return RemakeText.t("Wave %d/%d") % [wave, wave_limit]


func encounter_title() -> String:
	return RemakeText.t(ArenaRules.WAVES[wave - 1][0])


func arrivals_at_start() -> bool:
	return false
