extends Node
## Independent exhaustive legal-order oracle, old-save migration and a live
## camp reset. Run against pre-change export and the new production export.
const Refund := preload("res://src/game/training_refund.gd")
var checks := 0
var failures := 0
var rows := {}
var routes := 0
var original_min := INF
var remake_totals := {}
var oracle_prices := {}
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func native_price(code: String, count: int) -> int:
	var row: Dictionary=rows[code]
	var prev: Dictionary=rows.get(String(row.required_perk),{})
	var raw:=(Skills.curve(float(row.cost))-Skills.curve(float(prev.get("cost",0))))*pow(GameData.ai_value("RPG","Perk Power Base",2),count)
	var unit:=pow(10.0,floorf(log(raw)/log(10.0)))
	if raw/unit<4.0:
		if unit<=10.0:return int(raw)
		unit/=10.0
	return int(floorf(raw/unit+0.5)*unit)
func orders(remaining: Array, owned: Array, native_sum: int, new_sum: int) -> void:
	if remaining.is_empty():
		routes+=1;original_min=minf(original_min,native_sum);remake_totals[new_sum]=true
		return
	for code: String in remaining:
		var req:=String(rows[code].required_perk)
		if req!="none" and req!="" and req not in owned:continue
		var next:=remaining.duplicate();next.erase(code)
		var got:=owned.duplicate();got.append(code)
		orders(next,got,native_sum+native_price(code,owned.size()),new_sum+Perks.cost(code,{"perks":owned}))
func blank() -> Dictionary:
	var h:={"prototype":"Human Hero","exp":1000000.0,"exp_total":1000271.0,"skills":{},"perks":[],"str":23.0,"dex":30.0,"int":25.0}
	Refund.start(h)
	return h
func skill_value(h: Dictionary) -> int:
	var total:=0
	for sk: String in Skills.LIST:
		for i in clampi(Skills.level(h,sk),0,100):total+=maxi(1,int(Skills.curve(i+1)-Skills.curve(i)))
	return total
func zeroed(h: Dictionary) -> bool:
	return Array(h.get("perks",[])).is_empty() and Skills.LIST.all(func(sk):return Skills.level(h,sk)==0)
func _ready() -> void:
	for row: Dictionary in GameData.db.table("perks"):rows[String(row.code)]=row
	var permutations:=0
	for a in 4:
		for b in 4:
			for c in 4:
				if a+b+c==0:continue
				var target:=[]
				for pair: Array in [["sword",a],["fire",b],["bs",c]]:
					for rank in int(pair[1]):target.append(String(pair[0])+str(rank+1))
				routes=0;original_min=INF;remake_totals.clear()
				orders(target,[],0,0)
				permutations+=routes
				oracle_prices[str(target)]=original_min
				check(remake_totals.size()==1 and remake_totals.has(int(original_min)),"all legal orders match cheapest original: %d/%d/%d (%d orders)"%[a,b,c,routes])
	check(Perks.cost("sword1")==native_price("sword1",0) and Perks.cost("bs1")==native_price("bs1",0),"original root prices preserved")
	var pair_price:=mini(native_price("sword1",0)+native_price("bs1",1),native_price("bs1",0)+native_price("sword1",1))
	check(Perks.cost("bs1",{"perks":["sword1"]})==pair_price-native_price("sword1",0) and Perks.cost("sword1",{"perks":["bs1"]})==pair_price-native_price("bs1",0),"both two-rank orders cost the cheapest total")
	var one:=blank();var two:=blank()
	for code: String in ["sword1","sword2","bs1","fire1","fire2"]:check(Perks.learn(one,code),"first order learns "+code)
	for code: String in ["fire1","fire2","bs1","sword1","sword2"]:check(Perks.learn(two,code),"second order learns "+code)
	check(one.exp==two.exp,"real purchases have identical final XP")
	check(not Perks.learn(one,"sword2") and not Perks.learn(blank(),"sword3"),"duplicates and missing prerequisites rejected")
	check(Refund.refund(one) and one.exp==1000000.0 and zeroed(one),"new purchases refund exactly to zero")
	var total:=float(one.exp)
	check(not Refund.refund(one) and one.exp==total,"repeat empty reset grants nothing")
	for cycle in 3:
		Perks.learn(one,"bs1");Perks.learn(one,"sword1");Skills.raise(one,"melee");Refund.refund(one)
	check(one.exp==total,"buy/reset cycles cannot create XP")
	var poor:=blank();poor.exp=1.0;var unchanged:=poor.duplicate(true)
	check(not Perks.learn(poor,"bs1") and poor==unchanged,"unaffordable purchase changes nothing")
	var legacy:=blank();legacy.erase(Refund.KEY);legacy.perks=["sword1","bs1"];legacy.skills={"science":4,"sense":20};legacy.exp=100.0
	var old_value:=native_price("sword1",0)+native_price("bs1",1)+skill_value(legacy)
	check(Refund.amount(legacy)==old_value,"ledgerless character retains old order overpayment and all skill levels")
	var legacy_import:=CoopProgress.sanitize_hero(legacy)
	check(Refund.refund(legacy_import) and legacy_import.exp==100.0+old_value and zeroed(legacy_import),"imported old character fully resets")
	var ambiguous:=blank();ambiguous.perks=["bs1"];ambiguous.skills={"melee":10,"science":3};ambiguous[Refund.KEY]={"version":1,"ambiguous":true}
	check(Refund.reason(ambiguous).is_empty() and Refund.refund(ambiguous) and zeroed(ambiguous),"version-one ambiguous history no longer disables reset")
	var empty:=blank();empty.skills={}
	check(CoopProgress.sanitize_hero(empty).skills.is_empty(),"explicit empty skill allocation survives co-op import")
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g);s.set_physics_process(false)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	var h: Dictionary=s.state.heroes[0][0]
	var earned:=float(h.exp_total);var physical:=[h.str,h.dex,h.int];var kit:=[h.weapons.duplicate(),h.armors.duplicate(),h.spells.duplicate()]
	var initial:=skill_value(h)
	for i in h.perks.size():initial+=native_price(String(h.perks[i]),i)
	check(Refund.amount(h)==initial and initial>0,"Zak's innate backstab and starting skills have refundable value")
	await s.enter_zone("bz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "bz2g",1,false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	var u: GameUnit=s.party_units(0)[0]
	h=u.get_meta("hero")
	s.apply_command({"t":"refund_training","unit":u.uid},0)
	check(zeroed(h) and h.exp==initial,"camp button authority resets Zak to zero")
	check(not u.stats.has("backstab") or float(u.stats.backstab)==0,"live backstab bonus is removed")
	check(h.exp_total==earned and [h.str,h.dex,h.int]==physical and [h.weapons,h.armors,h.spells]==kit,"earned XP, base attributes and equipment are preserved")
	check(s.save_game("reset_training")==OK,"reset saves")
	s.state=CampaignState.load_from(SaveInfo.path("reset_training"))
	check(s.state!=null,"reset reloads")
	await s.enter_zone("bz1h" if GameData.campaign_id==CampaignProfile.ASTRAL else "bz2g",1,false)
	s.world.set_physics_process(false);s.world.vm.instances.clear();h=s.party_units(0)[0].get_meta("hero")
	check(zeroed(h) and h.exp==initial and Refund.amount(h)==0,"saved zero levels and consumed credit stay zero")
	# Values are diagnostics for cold UI preparation and repeat drawing only.
	var big:=blank();big.perks=[]
	for pair: Array in [["sword",1],["axe",2],["dagger",3],["fire",1],["lightning",2],["acid",3],["bs",1],["health",2],["mana",3]]:
		for rank in int(pair[1]):big.perks.append(String(pair[0])+str(rank+1))
	var began:=Time.get_ticks_usec();var possible:=Perks.available(big)
	for code: String in possible:Perks.cost(code,big)
	var cold:=Time.get_ticks_usec()-began
	began=Time.get_ticks_usec()
	for draw in 100:
		for code: String in possible:Perks.cost(code,big)
		Refund.amount(big)
	print("TRAINING_TIMING cold_menu_us=",cold," repeated_menu_us=",(Time.get_ticks_usec()-began)/100.0," options=",possible.size())
	g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	print("TRAINING_RESET ",checks," checks ",failures," failures; ",permutations," legal orders")
	get_tree().quit(1 if failures else 0)
