extends Node
## Disassembly fee of worn weapons and armour. The original prices every deal
## of a weapon or armour as price x coef[mode] - price x coef[8] x wear
## (camp price 0x60FA70, FSUB at 0x60FB4E), so a worn item was cheaper
## to take apart and rebuild than to repair. Cursed Lands adds the repair cost
## instead, as the Rebirth edition does; other deals keep the original
## subtraction. Real authored recipes of each campaign.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func expected(id: String, rates: Array) -> int:
	var p := float(Items.price(id))
	var m := Items.max_durability(id)
	var worn := p * float(rates[Items.Deal.REPAIR]) * clampf(Items.wear(id) / m, 0.0, 1.0)
	return maxi(0, int(p * float(rates[Items.Deal.DECONSTR]) + worn))

func _ready() -> void:
	var saved: Array = Items.coef
	var cases := 0
	for rates: Array in [Items.COEF, [1.0, 0.5, 0.05, 0.05, 1.0, 0.5, 0.1, 0.3, 0.6]]:
		Items.coef = rates
		for bp: String in ["bp:stone axe", "bp:long sword", "bp:gipat medium plate"]:
			for mat: Dictionary in Items.materials_for(bp).slice(0, 2):
				var item := bp.substr(3) + "." + String(mat.name).to_lower()
				if not Items.can_deconstruct(item): continue
				cases += 1
				var fresh := Items.deconstruct_price(item)
				check(fresh == int(float(Items.price(item)) * float(rates[Items.Deal.DECONSTR])), item + " unworn fee is price x coef[7]")
				var last := fresh
				for part in [0.25, 0.75, 1.0]:
					var worn := Items.with_wear(item, Items.max_durability(item) * part)
					var fee := Items.deconstruct_price(worn)
					check(fee == expected(worn, rates), "%s %d%% worn fee adds the repair cost (%d)" % [item, part * 100, fee])
					check(fee >= last and fee >= fresh + Items.repair_price(worn) - 1, "%s %d%% worn costs at least the unworn fee plus repair" % [item, part * 100])
					last = fee
				# The other deals keep the original's subtraction.
				var worn := Items.with_wear(item, Items.max_durability(item) * 0.5)
				check(Items.sell_price(worn) <= Items.sell_price(item), item + " a worn item still sells for less")
	check(cases >= 8, "weapon and armour recipes exercised (%d)" % cases)
	# Wands have no wear; free traders stay free.
	var wand: String = Items.from_spec("Wand 5.Dragon Green Bones[acid_fog{r2;a2}]")[0]
	Items.coef = Items.COEF
	check(Items.deconstruct_price(wand) == int(float(Items.price(wand)) * Items.COEF[Items.Deal.DECONSTR]), "a wand's fee is unchanged")
	Items.coef = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	check(Items.deconstruct_price(Items.with_wear("stone axe.rock", 5.0)) == 0, "a free trader still takes worn items apart for free")
	Items.coef = saved
	print("DISASSEMBLY_WEAR ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
