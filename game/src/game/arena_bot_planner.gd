class_name ArenaBotPlanner
extends RefCounted
## Stable personalities choose how to spend, without extra gold, shop knowledge
## or combat bonuses. Valuations are planning estimates, never combat stats.
const PROFILES := [
	{"bank":50,"level":0,"rolls":2,"upgrades":1.0}, # economy
	{"bank":30,"level":1,"rolls":2,"upgrades":0.85}, # expansion
	{"bank":40,"level":-1,"rolls":7,"upgrades":1.5}, # evolution
	{"bank":20,"level":0,"rolls":4,"upgrades":1.15}, # tempo
]
static var _powers := {}
static var _database: WeakRef

static func strategy(_bot: ArenaRun, player: int) -> int:
	return posmod(player - 1, PROFILES.size())

static func power(family: int, rank: int) -> float:
	if _database == null or _database.get_ref() != GameData.db:
		_powers.clear(); _database = weakref(GameData.db)
	var key:=Vector2i(family,rank)
	if _powers.has(key): return _powers[key]
	var id:=ArenaRules.prototype(family,rank)
	var row:=ArenaRules.recruit_prototype(family,rank,GameData.db.find("monster_prototypes",id))
	var values:=ArenaUnitInfo.values(id,null,family,rank)
	var mean:=float(values.min+values.max)*0.5
	var tier:=int(ArenaRules.FAMILIES[family].tier)
	var armor:=(3.0+tier*2.0)*(1.0+rank*0.15)
	var defense:=18.0+tier*3.0+rank*4.0
	var needed:=ceili((defense-float(values.attack)+41.0)/2.0)
	var hit:=clampf(float(41-clampi(needed,0,41))/41.0,0.0,1.0)
	var interval:=maxf(0.6,float(row.get("tuning_actions",50.0))*GameUnit.TICK*15.0/float(values.actions))
	var damage_rate:=maxf(mean*0.2,mean-armor)*hit/interval
	for spell: String in row.get("spells",[]):
		var parsed:=Spells.parse(spell)
		if not Spells.DAMAGE_SCHOOLS.has(parsed.code): continue
		var effect:=float(parsed.effect)
		var cast_time:=maxf(0.6,float(parsed.proto.get("actions",45.0))*GameUnit.TICK*15.0/float(values.actions))
		damage_rate=maxf(damage_rate,maxf(effect*0.2,effect-armor)*ArenaRules.spell_target_budget(parsed)/cast_time)
	# Survival and sustained output both contribute to fighting strength.
	# Multiplying sqrt(HP) by DPS overvalued casters so much that CPUs filled
	# nearly every slot with them, even when those formations lost to melee.
	# Half incoming attacks are estimated as physical; bows cannot parry.
	var incoming:=1.0
	if float(values.defense)>0.0:
		var enemy_attack:=28.0+tier*4.0+rank*8.0
		var defend_roll:=ceili((float(values.defense)-enemy_attack+41.0)/2.0)
		incoming=0.5+0.5*float(41-clampi(defend_roll,0,41))/41.0
	var value:=sqrt(float(values.hp)/incoming*damage_rate)*10.0*(1+float(values.armor[6])/70)
	# This remains an estimate: animation, positioning and counters matter.
	if ArenaRules.recruit_role(family,rank)!="Melee": value*=1.2
	_powers[key]=value
	return value

static func entry_power(entry: Dictionary) -> float:
	return power(int(entry.family),int(entry.rank)) if int(entry.family)>=0 else 1.0

static func reserve(bot: ArenaRun, round_number: int, hp: int, profile: Dictionary) -> int:
	if hp<=30 or round_number>=28: return 0
	var target:=mini(int(profile.bank),maxi(0,round_number-3)*10)
	if hp<=50: target=mini(target,10)
	elif bot.history.size()>=3 and bot.history.slice(-3).all(func(result):return int(result.winner)!=0): target=mini(target,20)
	return target

## A lower-rank copy can finish a three-star unit even when the intervening
## two-star form is weaker than the field. Count both ranks in the offered
## copy's units; never discard that investment merely because the next step
## alone is not an improvement.
static func evolution_value(bot: ArenaRun, family: int, rank: int, weakest: float) -> Dictionary:
	var result := {"score":0.0, "completes":false}
	var owned := bot.army.filter(func(entry): return int(entry.family) == family)
	if owned.is_empty() or owned.any(func(entry): return int(entry.rank) == 2): return result
	var required := 1
	for target in range(rank + 1, 3):
		required *= ArenaRules.evolution_copies(family, target - 1)
		if required == 0: break
		var progress := 0
		for entry: Dictionary in owned:
			if int(entry.rank) < rank or int(entry.rank) >= target: continue
			var copies := 1
			for step_rank in range(rank, int(entry.rank)):
				copies *= ArenaRules.evolution_copies(family, step_rank)
			progress += copies
		var missing := maxi(1, required - progress)
		var gain := maxf(0.0, power(family, target) - maxf(weakest, power(family, rank)))
		var score := gain / missing * (2.5 if missing == 1 else 0.6)
		result.score = maxf(result.score, score)
		if missing == 1 and gain > 0: result.completes = true
	return result

static func step(bot: ArenaRun, player: int, round_number: int, hp: int, plan: Dictionary) -> void:
	if plan.done: return
	plan.actions+=1
	if plan.actions>=40:
		equip(bot); plan.done=true; return
	var profile: Dictionary=PROFILES[strategy(bot,player)]
	var bank:=reserve(bot,round_number,hp,profile)
	var style: String=ArenaTournamentRun.STYLES[posmod(player-1,ArenaTournamentRun.STYLES.size())]
	arrange(bot,style)
	equip(bot)
	var weakest:=INF
	for entry: Dictionary in bot.army:
		if entry.deployed: weakest=minf(weakest,entry_power(entry))
	if weakest==INF: weakest=0
	var empty:=bot.deployed_count()<bot.capacity()
	var best:=-1;var best_score:=0.0
	for index in bot.shop.size():
		if not bot.purchase_error(index).is_empty():continue
		var offer: Dictionary=bot.shop[index]
		var family:=int(offer.family);var rank:=int(offer.get("rank",0))
		var value:=power(family,rank)
		var improvement:=maxf(0,value-weakest) if not empty else value
		var future:=evolution_value(bot,family,rank,weakest)
		var score:=improvement+float(future.score)*float(profile.upgrades)
		if style in ArenaAlliances.traits(family):score*=1.12
		var cost:=bot.offer_cost(offer)
		if bot.gold-cost<bank and not empty and not (future.completes and hp<65):continue
		if score < maxf(6,weakest*0.04):continue
		score/=sqrt(float(cost))
		if score>best_score:best=index;best_score=score
	# Clear obsolete reserves before buying or rolling. Keep real upgrade pairs.
	for entry: Dictionary in bot.army.duplicate():
		if entry.deployed:continue
		var peers:=bot.army.filter(func(other):return other.family==entry.family and other.rank==entry.rank).size()
		var potential:=0.0
		for rank in range(int(entry.rank)+1,3): potential=maxf(potential,power(int(entry.family),rank))
		var obsolete:=potential<weakest*1.05
		var higher:=bot.army.any(func(other):return other.family==entry.family and other.rank>entry.rank)
		if obsolete or (peers==1 and not higher and bot.bench_count()>=4 and entry_power(entry)<weakest*0.65):
			bot.sell(int(entry.uid));bot._undo.clear();return
	if best>=0:
		bot.buy(best);arrange(bot,style);bot._undo.clear();return
	var desired:=clampi(3+round_number/2+int(profile.level),3,ArenaRules.MAX_ARMY)
	# Evolution deliberately stays where its committed families are common.
	# Previously every personality rushed level nine before seriously rolling.
	if strategy(bot,player)==2: desired=clampi(3+round_number/4,3,7 if round_number<24 else 9)
	if bot.capacity()<desired and bot.gold-ArenaRules.TRAINING_COST>=bank:
		if bot.train().is_empty():bot._undo.clear();return
	var rolls:=int(profile.rolls) if round_number>3 else 1
	if hp<=30:rolls=12
	if plan.rerolls<rolls and bot.gold-bot.refresh_cost()>=bank+3 and bot.refresh().is_empty():
		plan.rerolls+=1
	else:plan.done=true
	bot._undo.clear()

static func arrange(bot: ArenaRun, style: String) -> void:
	if bot.stage!="prepare" or bot.preparing_battle:return
	var remaining:=bot.army.duplicate();var chosen:=[];var families:={}
	var counts:={}
	while chosen.size()<bot.capacity() and not remaining.is_empty():
		var best:Dictionary={};var value:=-INF
		for entry: Dictionary in remaining:
			var score:=entry_power(entry)
			if not families.has(entry.family):
				for trait_key in ArenaAlliances.traits(int(entry.family)):
					var count:=int(counts.get(trait_key,0))
					if ArenaAlliances.rank(trait_key,count+1)>ArenaAlliances.rank(trait_key,count):score*=1.18
					if trait_key==style:score*=1.08
			if score>value:best=entry;value=score
		chosen.append(best);remaining.erase(best)
		if not families.has(best.family):
			families[best.family]=true
			for trait_key in ArenaAlliances.traits(int(best.family)):counts[trait_key]=int(counts.get(trait_key,0))+1
	var compact := ["spirit"].any(func(key): return ArenaAlliances.rank(key, int(counts.get(key,0))) > 0)
	compact = compact or chosen.any(func(entry): return ArenaItems.effect(bot.item_for(int(entry.uid))) == "guardian")
	var guards := ArenaAlliances.rank("warrior", int(counts.get("warrior",0))) > 0
	# Put armored Warriors in frontline slots before placing the carry.
	# Only Spirit aid and Guardian items reward a compact formation.
	chosen.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_front := ArenaRules.recruit_role(int(a.family), int(a.rank)) == "Melee"
		var b_front := ArenaRules.recruit_role(int(b.family), int(b.rank)) == "Melee"
		if a_front != b_front: return a_front
		var a_guard := guards and "warrior" in ArenaAlliances.traits(int(a.family))
		var b_guard := guards and "warrior" in ArenaAlliances.traits(int(b.family))
		if a_guard != b_guard: return a_guard
		return int(a.uid) < int(b.uid) if is_equal_approx(entry_power(a), entry_power(b)) else entry_power(a) > entry_power(b))
	var bodies := _formation_bodies(bot)
	var occupied: Array[Dictionary] = []
	for entry: Dictionary in bot.army: entry.deployed = false
	for entry: Dictionary in chosen:
		var radius := float(bodies.get(int(entry.uid), {}).get("radius", 2.0))
		var ranged := ArenaRules.recruit_role(int(entry.family), int(entry.rank)) != "Melee"
		var point := _formation_point(bot, bodies, occupied, entry, ranged, compact)
		if point == Vector2.INF: continue
		entry.deployed = true; entry.point = [point.x, point.y]
		occupied.append({"point":point, "radius":radius})
	bot.reserve_slots()


## Reuse fitted native bodies when this company already has a board. A newly
## bought or evolved body uses the native 2m maximum until it is constructed.
## Model sizes never justify overlap merely to obtain an alliance trigger.
static func _formation_bodies(bot: ArenaRun) -> Dictionary:
	var bodies := {}
	if not bot.deployment_check.is_valid(): return bodies
	var battle := bot.deployment_check.get_object() as ArenaPveMatch
	if not is_instance_valid(battle) or not is_instance_valid(battle.world): return bodies
	for unit: GameUnit in battle.world.unit_rows():
		var p: Dictionary = unit.get_meta("arena_placement", {})
		var uid := int(p.get("run_uid", 0)); var entry := bot.unit(uid)
		if entry.is_empty() or String(p.get("id", "")) != String(entry.prototype): continue
		bodies[uid] = {"radius":unit.body_radius(), "class":unit.move_class()}
	return bodies


static func _formation_point(bot: ArenaRun, bodies: Dictionary, occupied: Array[Dictionary], entry: Dictionary, ranged: bool, compact: bool) -> Vector2:
	var radius := float(bodies.get(int(entry.uid), {}).get("radius", 2.0))
	var movement := int(bodies.get(int(entry.uid), {}).get("class", NavGrid.WALK_CLASS))
	var preferred_x := (24.25 if compact else 22.0) if ranged else 27.0
	var spacing := 2.75 if compact else 4.0
	var candidates: Array[Vector2] = []
	for x in [27.0, 24.25, 21.5, 29.75, 22.0, 20.5]:
		for lane in [0,-1,1,-2,2,-3,3,-4,4]: candidates.append(Vector2(x,32.0+lane*spacing))
	# The conservative fallback grid can hold nine maximum-radius bodies.
	for x in [20.5,25.0,29.5]:
		for y in [20.5,25.0,29.5,34.0,38.5,43.0]: candidates.append(Vector2(x,y))
	candidates.sort_custom(func(a: Vector2, b: Vector2):
		var sa := 4.0*pow(a.x-preferred_x,2)+pow(a.y-32.0,2)
		var sb := 4.0*pow(b.x-preferred_x,2)+pow(b.y-32.0,2)
		return a.y < b.y if is_equal_approx(sa,sb) else sa < sb)
	var battle: ArenaPveMatch
	if bot.deployment_check.is_valid(): battle = bot.deployment_check.get_object() as ArenaPveMatch
	for point: Vector2 in candidates:
		if not ArenaRun.DEPLOY.has_point(point) or not ArenaTerrain.PLAY_AREA.grow(-radius).has_point(point): continue
		if occupied.any(func(other): return point.distance_to(other.point) < maxf(2.5 if compact else 4.0,radius+float(other.radius)+0.25)): continue
		if is_instance_valid(battle) and is_instance_valid(battle.world) and not battle.world.nav.cell_open(point,movement): continue
		return point
	return Vector2.INF


## Item decisions use the same public ownership actions as human preparation.
## A deterministic carrier preference never rerolls rewards or spends shop RNG.
static func equip(bot: ArenaRun) -> void:
	if bot.stage != "prepare" or bot.preparing_battle: return
	var deployed := bot.army.filter(func(entry): return entry.deployed)
	if not bot.item_offers.is_empty():
		var choice := 0; var best := -INF
		for index in bot.item_offers.size():
			var value := 0.0
			for entry: Dictionary in deployed: value = maxf(value, item_value(bot.item_offers[index], entry))
			if value > best: best = value; choice = index
		bot.choose_item(choice)
	var remaining := bot.items.duplicate()
	var assignments := {}
	while not remaining.is_empty() and not deployed.is_empty():
		var best := -INF; var selected_item: Dictionary = {}; var selected_unit: Dictionary = {}
		for item: Dictionary in remaining:
			for entry: Dictionary in deployed:
				var value := item_value(String(item.kind), entry)
				if value > best: best = value; selected_item = item; selected_unit = entry
		if best <= 0.0: break
		assignments[int(selected_item.uid)] = int(selected_unit.uid)
		remaining.erase(selected_item); deployed.erase(selected_unit)
	# Clear moved equipment first so displacement cannot erase another match.
	for item: Dictionary in bot.items:
		if int(item.unit_uid) != int(assignments.get(int(item.uid), 0)):
			bot.equip_item(int(item.uid), 0)
	for item_uid: int in assignments:
		bot.equip_item(item_uid, int(assignments[item_uid]))
	bot._undo.clear()


static func item_value(kind: String, entry: Dictionary) -> float:
	var family := int(entry.family); var rank := int(entry.rank)
	if family < 0 or not ArenaItems.RULES.has(kind): return 0.0
	var role := ArenaRules.recruit_role(family, rank)
	var melee := role == "Melee"; var caster := role == "Magic"
	var proto := ArenaRules.recruit_prototype(family, rank, GameData.db.find("monster_prototypes", ArenaRules.prototype(family, rank)))
	var basic := int(proto.get("weapon_type_id", 0)) != 16
	var spells := not Array(proto.get("spells", [])).is_empty()
	var gear: Dictionary = ArenaItems.RULES[kind]
	var weight := float(gear.get("health", 0.0)) / 160.0 * (1.2 if melee else 0.8)
	weight += float(gear.get("damage", 0.0)) / 25.0 * (0.35 if caster else 1.3) if basic else 0.0
	weight += float(gear.get("actions", 0.0)) / 15.0 * 1.6
	weight += float(gear.get("physical_armor", 0.0)) / 12.0 * (0.6 if melee else 0.3)
	weight += float(gear.get("elemental_armor", 0.0)) / 12.0 * 0.45
	weight += float(gear.get("spell", 0.0)) / 30.0 * (1.4 if caster else 0.5) if spells else 0.0
	match ArenaItems.effect(kind):
		"fang": weight += float(gear.leech) / 20.0 * (2.0 if melee else 1.3) if basic else 0.0
		"storm": weight += float(gear.storm_damage) / 100.0 * int(gear.storm_targets) * (0.7 if caster else 3.2) if basic else 0.0
		"venom": weight += float(gear.healing_reduction) * (0.4 if caster else 0.9) if basic else 0.0
		"ward": weight += float(gear.shield) / 120.0 * (0.8 if melee else 0.5)
		"guardian": weight += float(gear.shield) / 120.0 * 1.2
		"echo": weight += float(gear.echo_damage) / 30.0 / int(gear.echo_every) * (2.0 if caster else 0.5) if spells else 0.0
		"thorn": weight += float(gear.reflect) / 20.0 * (1.6 if melee else 0.3)
		"berserker": weight += float(gear.frenzy) / 15.0 * 2.0 if basic and not spells else 0.0
	return weight
