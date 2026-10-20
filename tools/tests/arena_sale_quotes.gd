extends Node
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL ",label)
func _ready() -> void:
	var host := ArenaOnlineGame.new(); add_child(host); host.begin(7319,{0:"Host",1:"Guest"}); host.set_process(false)
	var view := ArenaOnlineView.new()
	for family in ArenaRules.ACTIVE_FAMILIES:
		for rank in 3:
			var company := host.run.company(1)
			company.army.clear()
			var invested := int(ArenaRules.FAMILIES[family].cost)*int(pow(3,rank))
			var entry := company._recruit(family,rank,invested)
			view.apply_state(host.state_for(1,["Host","Guest","","","","","",""," "]))
			var quote := view.sale_value(view.unit(entry.uid))
			check(quote==invested if rank==0 else quote==invested*2/3,"refund matches invested copies at each star")
			var bank := company.gold
			check(host.command(1,"sell",[entry.uid,quote]).is_empty(),"quoted sale accepted")
			check(company.gold-bank==quote and company.unit(entry.uid).is_empty(),"co-op credited amount equals displayed quote")
			await get_tree().process_frame
	var company := host.run.company(1); company.army.clear()
	var entry := company._recruit(1,0,1)
	view.apply_state(host.state_for(1,["Host","Guest","","","","","",""," "]))
	var quote := view.sale_value(view.unit(entry.uid))
	company._recruit(1,0,1); company._recruit(1,0,1); company.combine_ready()
	var bank := company.gold
	check(host.command(1,"sell",[entry.uid,quote])=="The sale value changed. Select the creature again.","stale one-star quote cannot sell the evolved unit")
	check(company.gold==bank and not company.unit(entry.uid).is_empty(),"rejected quote leaves gold and creature intact")
	print("ARENA_SALE_QUOTES ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
