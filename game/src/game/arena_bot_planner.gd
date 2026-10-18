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
	var attack:=float(values.min+values.max)*0.5
	var spell_power:=0.0
	for spell: String in row.get("spells",[]):
		if not Spells.offensive(spell): continue
		var parsed:=Spells.parse(spell)
		var area:=1.5 if parsed.code in ["firewall","fireball","acid_fog","litnwall"] else 1.0
		# Recruited creatures use the native AI casting rule: no stamina cost.
		# Applying the player spell-builder cost undervalues almost every caster.
		spell_power=maxf(spell_power,float(parsed.effect)*area)
	attack=maxf(attack,spell_power*1.3)
	var value:=sqrt(float(values.hp))*attack*(1+float(values.armor[6])/70)
	if float(row.get("attack_range",0))>0 or spell_power>0: value*=1.2
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
	if plan.actions>=40: plan.done=true;return
	var profile: Dictionary=PROFILES[strategy(bot,player)]
	var bank:=reserve(bot,round_number,hp,profile)
	var style: String=ArenaTournamentRun.STYLES[posmod(player-1,ArenaTournamentRun.STYLES.size())]
	arrange(bot,style)
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
	for entry: Dictionary in bot.army:entry.deployed=false
	var front:=0;var back:=0
	for entry: Dictionary in chosen:
		var proto:=GameData.db.find("monster_prototypes",entry.prototype)
		var ranged:=float(proto.get("attack_range",0))>0 or not Array(proto.get("spells",[])).is_empty()
		var number:=back if ranged else front
		entry.deployed=true
		entry.point=[(22.0 if ranged else 27.0) if number<5 else 24.0,
			32.0+[0.0,-4.0,4.0,-8.0,8.0][number%5]+(2.0 if number>=5 else 0.0)]
		if ranged:back+=1
		else:front+=1
