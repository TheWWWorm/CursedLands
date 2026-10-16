class_name ArenaRun
extends RefCounted
## Pure run state. The UI and seeded balance policies use these same operations.

signal changed

const SAVE_PATH := "user://arena-expedition.json"
const PROFILE_PATH := "user://arena-profile.json"
const DEPLOY := Rect2(20, 20, 10.5, 24)
var run_seed := 1
var challenge := 0
var starter := 0
var wave := 1
var gold := 6
var lives := 3
var stage := "prepare"
var army: Array[Dictionary] = []
var shop: Array[Dictionary] = []
var boons: Array[String] = []
var rewards: Array[Dictionary] = []
var history: Array[Dictionary] = []
var last_result := {}
var next_uid := 1
var rng := RandomNumberGenerator.new()
var auto_save := true
var save_error := false
var _undo: Array[Dictionary] = []


func begin(seed_value: int, chosen_starter := 0, difficulty := 0) -> void:
	run_seed = maxi(1, seed_value)
	starter = clampi(chosen_starter, 0, ArenaRules.STARTERS.size() - 1)
	challenge = clampi(difficulty, 0, 2)
	wave = 1; gold = 6; lives = 3; stage = "prepare"; next_uid = 1
	army.clear(); shop.clear(); boons.clear(); rewards.clear(); history.clear(); _undo.clear()
	last_result = {}
	rng.seed = run_seed
	var families: Array = ArenaRules.STARTERS[starter].families
	for i in families.size():
		var unit := _recruit(int(families[i]), 0, 3)
		unit.deployed = true
		unit.point = [25.5 if i < 2 else 21.5, 29.5 if i == 0 else 34.5 if i == 1 else 32.0]
	_roll_shop(false)
	_touch()


func capacity() -> int:
	return mini(7, 3 + (wave - 1) / 3)


func bench_limit() -> int:
	return 9 if "reserve" in boons else 6


func deployed_count() -> int:
	return army.filter(func(u): return u.deployed).size()


func bench_count() -> int:
	return army.size() - deployed_count()


func refresh_cost() -> int:
	return 1 if "merchant" in boons else 2


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


func buy(index: int) -> String:
	if stage != "prepare": return RemakeText.t("Recruit between battles.")
	if index < 0 or index >= shop.size() or int(shop[index].family) < 0: return RemakeText.t("This offer has already been recruited.")
	var family := int(shop[index].family)
	var cost := int(ArenaRules.FAMILIES[family].cost)
	if gold < cost: return RemakeText.t("Not enough gold.")
	if bench_count() >= bench_limit(): return RemakeText.t("Bench full. Deploy, evolve or sell a creature first.")
	_checkpoint()
	gold -= cost
	_recruit(family, 0, cost)
	shop[index] = {"family": -1, "locked": false}
	_touch()
	return ""


func refresh() -> String:
	if stage != "prepare": return RemakeText.t("Recruit between battles.")
	if gold < refresh_cost(): return RemakeText.t("Not enough gold.")
	gold -= refresh_cost()
	_undo.clear() # Revealed randomness is never refunded by undo.
	_roll_shop(true)
	_touch()
	return ""


func lock_offer(index: int) -> void:
	if stage != "prepare" or index < 0 or index >= shop.size() or int(shop[index].family) < 0: return
	var was_locked := bool(shop[index].locked)
	for offer: Dictionary in shop: offer.locked = false
	shop[index].locked = not was_locked
	_touch()


func _roll_shop(keep_lock: bool) -> void:
	var old := shop.duplicate(true)
	shop.clear()
	for i in (6 if "scout" in boons else 5):
		if keep_lock and i < old.size() and old[i].locked and int(old[i].family) >= 0:
			shop.append(old[i])
		else:
			shop.append({"family": rng.randi_range(0, ArenaRules.FAMILIES.size() - 1), "locked": false})


func deploy(uid: int, point: Vector2) -> String:
	if stage != "prepare": return RemakeText.t("Arrange your army between battles.")
	var entry := unit(uid)
	if entry.is_empty(): return RemakeText.t("Choose a creature from your army.")
	if not is_finite(point.x) or not is_finite(point.y) or not DEPLOY.has_point(point):
		return RemakeText.t("Deploy inside the blue half of the battlefield.")
	if not entry.deployed and deployed_count() >= capacity(): return RemakeText.t("Army full. Move a creature to the bench first.")
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


func sell(uid: int) -> String:
	if stage != "prepare": return RemakeText.t("Recruit between battles.")
	var entry := unit(uid)
	if entry.is_empty(): return RemakeText.t("Choose a creature from your army.")
	_checkpoint()
	gold += sale_value(entry)
	army.erase(entry)
	_touch()
	return ""


func sale_value(entry: Dictionary) -> int:
	return int(entry.investment) / 3


func copies(entry: Dictionary) -> Array[Dictionary]:
	if entry.is_empty() or int(entry.family) < 0: return []
	var found: Array[Dictionary] = []
	for other: Dictionary in army:
		if other.family == entry.family and other.rank == entry.rank: found.append(other)
	return found


func evolution_error(uid: int) -> String:
	if stage != "prepare": return RemakeText.t("Evolve between battles.")
	var entry := unit(uid)
	if entry.is_empty(): return RemakeText.t("Choose a creature from your army.")
	var needed := ArenaRules.evolution_copies(int(entry.family), int(entry.rank))
	if needed == 0: return RemakeText.t("This creature has reached its final form.")
	var unlock := 4 if int(entry.rank) == 0 else 10
	if wave < unlock: return RemakeText.t("This evolution unlocks at wave %d.") % unlock
	if copies(entry).size() < needed: return RemakeText.t("Collect %d copies of this form to evolve.") % needed
	return ""


func evolve(uid: int) -> String:
	var error := evolution_error(uid)
	if error: return error
	_checkpoint()
	var entry := unit(uid)
	var needed := ArenaRules.evolution_copies(int(entry.family), int(entry.rank))
	var consumed := 0
	for other: Dictionary in copies(entry):
		if other.uid == uid: continue
		entry.investment += other.investment
		army.erase(other)
		consumed += 1
		if consumed == needed - 1: break
	entry.rank += 1
	entry.prototype = ArenaRules.prototype(entry.family, entry.rank)
	_touch()
	return ""


func start_battle() -> String:
	if stage != "prepare": return RemakeText.t("Finish the current encounter first.")
	if deployed_count() == 0: return RemakeText.t("Deploy at least one creature before starting.")
	stage = "fight"
	_undo.clear()
	_touch()
	return ""


func arrange() -> void:
	if stage != "prepare": return
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


func resolve(winner: int, seconds: float, damage: Array) -> void:
	if stage != "fight": return
	last_result = {"wave": wave, "winner": winner, "seconds": seconds, "damage": damage.duplicate(), "gold": 0}
	if winner == 0:
		if wave < ArenaRules.WAVE_COUNT:
			gold += 8
			last_result.gold = 8
	else:
		lives -= 1
	history.append(last_result.duplicate(true))
	stage = "won" if winner == 0 and wave == ArenaRules.WAVE_COUNT else "lost" if lives <= 0 else "result"
	if auto_save: _update_profile()
	_touch()


func advance() -> void:
	if stage != "result": return
	if int(last_result.winner) != 0:
		stage = "prepare"
	elif wave % 6 == 0:
		stage = "reward"
		_make_rewards()
	else:
		_next_wave()
	_touch()


func _next_wave() -> void:
	wave += 1
	stage = "prepare"
	_undo.clear()
	_roll_shop(true)


func _make_rewards() -> void:
	rewards.clear()
	var special := "orcfemalem3" if wave == 6 else "orcfemalem5"
	rewards.append({"kind": "companion", "prototype": special})
	var choices: Array[String] = ["merchant", "reserve", "scout"]
	choices = choices.filter(func(k): return k not in boons)
	rewards.append({"kind": choices[rng.randi_range(0, choices.size() - 1)] if not choices.is_empty() else "purse"})
	rewards.append({"kind": "life" if lives < 3 else "purse"})


func choose_reward(index: int) -> String:
	if stage != "reward" or index < 0 or index >= rewards.size(): return RemakeText.t("Choose one of the offered rewards.")
	var reward: Dictionary = rewards[index]
	match String(reward.kind):
		"companion":
			# A reward must never vanish into a full bench. It arrives in one
			# temporary overflow slot; purchases stay blocked until resolved.
			_recruit(-1, 0, 9 if wave == 6 else 18, reward.prototype)
		"purse": gold += 12
		"life": lives = mini(3, lives + 1)
		_: boons.append(String(reward.kind))
	rewards.clear()
	_next_wave()
	_touch()
	return ""


func _checkpoint() -> void:
	_undo.append({"army": army.duplicate(true), "shop": shop.duplicate(true), "gold": gold, "next_uid": next_uid})
	if _undo.size() > 30: _undo.pop_front()


func undo() -> void:
	if stage != "prepare" or _undo.is_empty(): return
	var previous: Dictionary = _undo.pop_back()
	army.assign(previous.army); shop.assign(previous.shop)
	gold = previous.gold; next_uid = previous.next_uid
	_touch()


func can_undo() -> bool:
	return stage == "prepare" and not _undo.is_empty()


func snapshot() -> Dictionary:
	return {"version": ArenaRules.VERSION, "seed": str(run_seed), "rng": str(rng.state),
		"challenge": challenge, "starter": starter, "wave": wave, "gold": gold, "lives": lives,
		"stage": stage, "army": army.duplicate(true), "shop": shop.duplicate(true),
		"boons": boons.duplicate(), "rewards": rewards.duplicate(true), "history": history.duplicate(true),
		"last_result": last_result.duplicate(true), "next_uid": next_uid}


func restore(data: Dictionary) -> bool:
	# Validate before changing any live state. JSON numbers arrive as floats.
	if data.get("version") != ArenaRules.VERSION: return false
	if not data.get("stage", "") in ["prepare", "fight", "result", "reward", "won", "lost"]: return false
	for key in ["army", "shop", "boons", "rewards", "history"]:
		if not data.get(key) is Array: return false
	for key in ["seed", "rng"]:
		if not data.get(key) is String or not data[key].is_valid_int(): return false
	if not _integer(int(data.seed), 1, 99999999): return false
	if not _integer(data.get("wave"), 1, ArenaRules.WAVE_COUNT): return false
	if not _integer(data.get("gold"), 0, 100000) or not _integer(data.get("lives"), 0, 3): return false
	if not _integer(data.get("challenge"), 0, 2) or not _integer(data.get("starter"), 0, 2): return false
	if not _integer(data.get("next_uid"), 1, 100000): return false
	if data.army.size() > 17 or data.boons.size() > 3 or data.history.size() > 24: return false
	var seen := {}
	var deployed := 0
	var points: Array[Vector2] = []
	for entry in data.army:
		if not entry is Dictionary or not entry.get("point") is Array or entry.point.size() != 2: return false
		if not _integer(entry.get("uid"), 1, 100000) or seen.has(int(entry.uid)): return false
		if not entry.get("deployed") is bool or not entry.get("prototype") is String: return false
		if not _integer(entry.get("family"), -1, ArenaRules.FAMILIES.size() - 1) or not _integer(entry.get("rank"), 0, 2): return false
		if not _integer(entry.get("investment"), 1, 10000): return false
		var family := int(entry.family)
		var rank := int(entry.rank)
		if family >= 0 and entry.prototype != ArenaRules.prototype(family, rank): return false
		if family < 0 and (entry.prototype not in ["orcfemalem3", "orcfemalem5"] or rank != 0): return false
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
	var capacity_at_wave := mini(7, 3 + (int(data.wave) - 1) / 3)
	if deployed > capacity_at_wave: return false
	var saved_boons := {}
	for key in data.boons:
		if not key is String or key not in ["merchant", "reserve", "scout"] or saved_boons.has(key): return false
		saved_boons[key] = true
	if data.army.size() - deployed > (10 if saved_boons.has("reserve") else 7): return false
	if data.shop.size() != (6 if saved_boons.has("scout") else 5): return false
	var locks := 0
	for offer in data.shop:
		if not offer is Dictionary or not _integer(offer.get("family"), -1, ArenaRules.FAMILIES.size() - 1) or not offer.get("locked") is bool: return false
		if offer.locked:
			if int(offer.family) < 0: return false
			locks += 1
	if locks > 1: return false
	if data.stage == "reward":
		if int(data.wave) not in [6, 12] or data.rewards.size() != 3: return false
	elif not data.rewards.is_empty(): return false
	for reward in data.rewards:
		if not reward is Dictionary or not reward.get("kind") is String or not ArenaRules.BOONS.has(reward.kind): return false
		if reward.kind == "companion" and reward.get("prototype") != ("orcfemalem3" if int(data.wave) == 6 else "orcfemalem5"): return false
		if reward.kind in saved_boons: return false
	for record in data.history:
		if not _valid_result(record) or int(record.wave) > int(data.wave): return false
	if not data.get("last_result") is Dictionary: return false
	if not data.last_result.is_empty() and not _valid_result(data.last_result): return false
	if data.stage in ["result", "reward", "won", "lost"] and data.last_result.is_empty(): return false
	if data.stage == "won" and (int(data.wave) != ArenaRules.WAVE_COUNT or int(data.last_result.winner) != 0): return false
	if (data.stage == "lost") != (int(data.lives) == 0): return false
	run_seed = int(data.seed); rng.seed = run_seed; rng.state = int(data.rng)
	challenge = int(data.challenge); starter = int(data.starter)
	wave = int(data.wave); gold = int(data.gold); lives = int(data.lives)
	stage = "prepare" if data.stage == "fight" else String(data.stage)
	army.assign(data.army.duplicate(true)); shop.assign(data.shop.duplicate(true)); boons.assign(data.boons)
	rewards.assign(data.rewards.duplicate(true)); history.assign(data.history.duplicate(true))
	last_result = data.last_result.duplicate(true)
	next_uid = int(data.next_uid)
	for id in seen: next_uid = maxi(next_uid, int(id) + 1)
	_undo.clear()
	return true


static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high


static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value, low, high) and float(value) == floorf(float(value))


static func _valid_result(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not _integer(value.get("wave"), 1, ArenaRules.WAVE_COUNT) or not _integer(value.get("winner"), -1, 1): return false
	if not _number(value.get("seconds"), 0, 301) or not _integer(value.get("gold"), 0, 8): return false
	if not value.get("damage") is Array or value.damage.size() != 2: return false
	return _number(value.damage[0], 0, 10000000) and _number(value.damage[1], 0, 10000000)


func load_saved() -> bool:
	if not FileAccess.file_exists(SAVE_PATH): return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return restore(data) if data is Dictionary else false


func save() -> bool:
	return _write_json(SAVE_PATH, snapshot())


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
			var limit := 18 if key == "best_wave" else 2 if key == "challenge" else 2147483647
			if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= 0 and value <= limit:
				clean[key] = int(value)
	return clean


func _update_profile() -> void:
	var data := profile()
	data.best_wave = maxi(int(data.get("best_wave", 0)), wave if last_result.winner == 0 else wave - 1)
	if stage == "won":
		data.wins = int(data.get("wins", 0)) + 1
		data.challenge = mini(2, maxi(int(data.get("challenge", 0)), challenge + 1))
	_write_json(PROFILE_PATH, data)


func _touch() -> void:
	if auto_save: save_error = not save()
	changed.emit()
