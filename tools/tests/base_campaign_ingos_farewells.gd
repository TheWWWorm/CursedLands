extends "base_campaign_ingos_support.gd"
## Earlier companion availability and completed mine rescue are chapter
## inputs. Recruitment, Deva's condition and each farewell are earned here.

func _ready() -> void: run.call_deferred()

func run() -> void:
	ingos()
	var number := 5
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--merc="): number = int(arg.trim_prefix("--merc="))
	GameData.options["merc_travel"] = 0
	s.state.set_var(0,"amerc_%d"%number,1)
	await enter(ScriptVM.MERC_HOME[number])
	await complete("b.merc%d.n1_%d"%[number,number])
	check(s.state.mercs.has(number) and s.party_units(0).size() == 2,"ordinary hire adds the selected Ingos companion to the live party")
	s.state.set_var(0,"b.bz11k.D55",1)
	s.state.add_item(item_name(38)); s.state.add_item(item_name(31))
	await enter("bz11k"); start(["VCheck#0#1","VCheck#0#32"])
	await complete("b.bz11k.D55")
	check(value("b.Deva.D55_2") == 0,"companion route cannot depart before Deva's explanation")
	await complete("b.Deva.D55_3")
	check(value("b.Deva.D55_1") == 1 and value("b.Deva.D55_2") == 0,"actual explanation offers the companion warning while departure stays unavailable")
	await complete("b.Deva.D55_1")
	check(value("b.Deva.D55_2") == 0,"Deva's warning alone does not satisfy the companion farewell")
	var farewell := "b.merc%d.n10_%d"%[number,number]
	await roundtrip("base_ingos_farewell_pending",["b.Deva.D55_1","b.Deva.D55_2",farewell])
	await complete(farewell)
	check(not s.state.mercs.has(number) and s.party_units(0).size() == 1,"ordinary farewell removes the selected companion from the original party")
	check(value("b.Deva.D55_2") == 1,"earned farewell opens Deva's actual departure conversation")
	await complete("b.Deva.D55_2")
	if await wait_zone("bz7g"):
		check(s.party_units(0).size() == 1 and not s.state.mercs.has(number),"actual Ingos departure reaches Gipat with the lone protagonist")
		check(value("b.bz7g.R54") == 1,"companion farewell route offers the same returned-Gipat handoff")
		await roundtrip("base_ingos_farewell_arrival",["b.Deva.D55_2",farewell,"b.bz7g.R54"])
	await finish("BASE_CAMPAIGN_INGOS_FAREWELLS","Prepared earlier availability of companion "+str(number)+" and earned D55 arrival offer, Gipat document book and governor chest. Ordinary hire, D55/D55_3 explanation, companion-present warning, missing-farewell gate, actual n10 farewell, Deva transfer to bz7g and R54 offer. Saved pending/post-departure continuation and duplicate conversation rewards; merc_travel=0 selects original island separation. No tested farewell or departure outcome assigned.")
