extends Node
## Item-instance conservation across repair, charge recovery and disk saves.
## These are metamorphic regressions, not an original-executable oracle.
const ITEMS := [
	"stone axe.rock",
	"long sword.steel|weak{it}",
	"gipat medium plate.thin|healing{ic}",
	"wand 5.dragon green bones|acid_fog{r2;a2}",
	"unique spear.mithrill|litnwall{it}",
]
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func _ready() -> void:
	var instances: Array = []
	for base: String in ITEMS:
		check(not Items.info(base).row.is_empty(),base+" exists in this campaign")
		var durability := Items.max_durability(base)
		var energy := Items.energy(base)
		check(durability > 1.0 and energy > 0.0,base+" exercises wear and charge")
		for lost: float in [0.0,0.125,1.0,durability/2.0,durability]:
			for requested: float in [-10.0,0.0,energy/4.0,energy/2.0,energy,energy+10.0]:
				var id := Items.with_charge(Items.with_wear(base,lost),requested)
				var label := "%s wear=%s charge=%s"%[base,lost,requested]
				instances.append(id)
				check(Items.unworn(id)==base and Items.spell_of(id)==Items.spell_of(base),label+" retains equipment and enchantment")
				check(absf(Items.wear(id)-lost)<=0.0011,label+" retains wear to documented item precision")
				check(is_equal_approx(Items.charge(id),clampf(requested,0.0,energy)),label+" clamps charge to physical capacity")
				check(id==Items.with_wear(Items.with_charge(base,requested),lost),label+" independent edits commute")
				var repaired := Items.with_wear(id,0.0)
				check(Items.wear(repaired)==0.0 and Items.spent(repaired)==Items.spent(id),label+" repair preserves spent charge")
				var charged := Items.with_charge(id,energy)
				check(Items.spent(charged)==0.0 and Items.wear(charged)==Items.wear(id),label+" full charge preserves damage")
				check(Items.with_wear(repaired,0.0)==repaired and Items.with_charge(charged,energy)==charged,label+" repeated repair/recharge is idempotent")
				var current := id
				var monotone := true
				for tick in 1100:
					var next := Items.recharge(current)
					monotone = monotone and Items.charge(next)>=Items.charge(current) and Items.charge(next)<=energy
					current = next
					if Items.spent(current)==0.0: break
				check(monotone and Items.spent(current)==0.0,label+" repeated native-rate ticks reach full charge without overshoot")
				check(Items.wear(current)==Items.wear(id) and Items.unworn(current)==base,label+" passive recovery preserves the damaged item")
	var legacy := "Long Sword.Steel[weak{it}]@1.25~2"
	check(Items.canonical_equipment(legacy)=="long sword.steel|weak{it}@1.25~2","legacy enchantment canonicalization retains both instance fields")
	check(Items.with_wear("stone axe.rock",-5.0)=="stone axe.rock","negative repair wear clamps to fresh")
	var max_wear := Items.with_wear("stone axe.rock",1.0e9)
	check(Items.is_broken(max_wear) and Items.durability(max_wear)<=0.0011,"excess wear caps at a broken item")
	var st := CampaignState.new()
	st.ensure_hero(0,"Human Hero")
	# Duplicates, distinct charge states and ordering must all survive storage.
	st.items=instances.duplicate()
	st.items.append_array(instances)
	st.party_bags["Waiting"]={"items":instances.duplicate(),"money":321}
	st.coop={"host":{"joiners":{"fixture":{"purse":{"items":instances.duplicate(),"money":123}}}}}
	st.money=654
	check(st.save("user://item-instance-matrix.sav")==OK,"large varied inventory saves")
	var restored := CampaignState.load_from("user://item-instance-matrix.sav")
	check(restored!=null,"varied inventory reloads")
	if restored:
		check(restored.items==st.items and restored.money==654,"bag retains every copy, order, damage and charge")
		check(restored.party_bags==st.party_bags,"waiting party retains exact independent inventory")
		check(restored.coop==st.coop,"guest purse retains exact independent inventory")
		check(restored.save("user://item-instance-repeat.sav")==OK,"reloaded inventory saves again")
		var again := CampaignState.load_from("user://item-instance-repeat.sav")
		check(again!=null and again.to_dict()==restored.to_dict(),"second disk round trip is stable")
	print("ITEM_INSTANCE_MATRIX ",JSON.stringify({"checks":checks,"failures":failures,"instances":instances.size(),"campaign":GameData.campaign_id}))
	get_tree().quit(1 if failures else 0)
