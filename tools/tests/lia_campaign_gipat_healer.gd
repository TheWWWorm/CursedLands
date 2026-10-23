extends "lia_campaign_mid_gipat.gd"
## Continue the earned q12g endpoint: prepare only Karh's offered conversation.
## Reuse actual needle/healer mechanics with acceptance overridden to prohibit
## injecting offers. Everything after the first offer must be earned here.
func accept(zone: String,topic: String,quest: String) -> void:
	check(value(topic) == 1,"previous authored quest actually offered "+topic)
	await enter(zone); await complete(topic)
	check(value(quest) == 1,"earned conversation starts "+quest)
func run() -> void:
	boot(); chapter("Gipat","Hero3","Hero","merc2g")
	s.state.set_var(0,"b.Karh.brief_121",1)
	s.state.set_var(0,"q.gz10g.q12g",2)
	await enter("bz11g"); await complete("b.Karh.brief_121")
	await enter("gz10g"); start(["VCheck#1#1"]); ticks(30)
	place_party(Vector2(80,242)); place_party(Vector2(46,242))
	kill([1013001,1013002,1013005])
	check(value("q.gz10g.q13g.3") == 1,"last hunter prevents the sack objective")
	kill([1013007])
	check(value("q.gz10g.q13g.4") == 1 and not s.state.quest_items.has("sackhunter"),"all hunters defeated still waits for their actual container")
	use(1013008)
	check(value("q.gz10g.q13g") == 2 and s.state.quest_items.has("sackhunter"),"actual hunters' chest grants sack and completes quest")
	await enter("bz11g"); await complete("b.Karh.brief_122"); await complete("b.Karh.brief_123")
	check(value("q.gz15g.q14g") == 1 and s.state.quest_items.has("baburletter") and value("z.gz10g_gz15g") == 2,"actual Karh report grants carried letter and opens both delivery choices")
	await enter("gz15g"); start(["VCheck#0#1"]); ticks(30)
	place_party(Vector2(224,147))
	check(value("q.gz15g.q14g.2") == 1 and value("q.gz15g.q14g.3") == 1,"actual camp approach activates both alternative deliveries")
	check(s.save_game("campaign_gipat_letter_choice") == OK,"save earned letter before independent delivery choices")
	use(3398726)
	check(value("q.gz15g.q14g") == 2 and value("q.gz15g.q14g.2") == 3 and value("q.gz15g.q14g.3") == 2 and value("b.Smith.brief_126b") == 1,
		"second delivery completes quest, rejects opposite objective and offers its correct Smith branch")
	use(3359930,false)
	check(not s.state.quest_items.has("baburletter") and value("b.Smith.brief_126a") == 0,"consumed letter prevents completing both delivery alternatives")
	await enter("bz11g"); await complete("b.Smith.brief_126b")
	check(value("q.gz11g.q16g") == 1 and value("z.gz11d1") == 2,"second delivery branch also grants the real needle quest and opens its entrance")
	check(await s.load_game_shown("campaign_gipat_letter_choice"),"restore earned letter for first-delivery branch"); freeze()
	use(3359930)
	check(value("q.gz15g.q14g") == 2 and value("q.gz15g.q14g.2") == 2 and value("q.gz15g.q14g.3") == 3 and value("b.Smith.brief_126a") == 1,
		"first delivery completes quest and offers its actual Smith branch")
	await enter("bz11g"); await complete("b.Karh.brief_124")
	await enter("gz10g"); start(["VCheck#2#1"]); ticks(30)
	place_party(Vector2(107,130)); kill(range(1015001,1015010))
	check(value("q.gz10g.q15g") == 1,"last caravan defender prevents caravan completion")
	kill([1015010])
	check(value("q.gz10g.q15g") == 2 and value("b.Karh.brief_125") == 1,"all ten defenders defeated completes caravan and offers report")
	await enter("bz11g"); await complete("b.Karh.brief_125")
	if not await needle():
		await finish("LIA_CAMPAIGN_GIPAT_HEALER","Earned q13g..q15g and Smith offer; needle path failed."); return
	if not await healer():
		await finish("LIA_CAMPAIGN_GIPAT_HEALER","Earned through needle; healer path failed."); return
	check(value("q.gz12g.q18g") == 1 and value("q.gz7g.q19g") == 1 and value("z.gz10g_gz12g") == 2,
		"actual earned healer arrival grants both next quests and opens monster route")
	await finish("LIA_CAMPAIGN_GIPAT_HEALER","Prepared q12g completion and Karh121 offer (earned in settlements suite). Carried q13g hunters/sack→q14g both independent letter delivery branches→q15g caravan→earned Smith126a→q16g needle/key/flood/actual return→q17g ordered healer controls and actual cave entry→arrival129 grants q18g/q19g. Reused mechanics prohibit preparing any later offer. Saves, missing keys, partial groups, alternate endings, route returns and once-only rewards. Combat/walking accelerated; earlier chapter endpoint is declared, not re-earned here.")
