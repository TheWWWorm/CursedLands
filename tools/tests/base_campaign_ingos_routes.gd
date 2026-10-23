extends "base_campaign_ingos_support.gd"
## Three authored q54 mine approaches. The gold recovered by q53 is the
## earlier checkpoint input; G53 actually exchanges it for the mine key.

func _ready() -> void: run.call_deferred()

func run() -> void:
	ingos(); s.state.add_item(item_name(28))
	await accept("bz8k","b.Huber.G53","q.gz12k.q54k")
	await enter("gz12k")
	start(["VTriger#0#79","VCheck#0#126","VCheck#0#181"])
	use(5636)
	check(not has_item(30) and value("q.gz12k.q54k") == 1,"earned key opens the gate while all mine approaches remain pending")
	await roundtrip("base_ingos_three_mine_approaches",["q.gz12k.q54k","q.gz12k.q54k.6"])
	var routes := [
		[Vector2(244,458),"gz12k_gz14k",1],
		[Vector2(59,456),"gz12k_gz14ak",2],
		[Vector2(102,465),"gz12k_gz14bk",3],
	]
	for index: int in routes.size():
		if index > 0:
			check(await s.load_game_shown("base_ingos_three_mine_approaches"),"restore pending mine approach for alternate entrance "+str(index+1))
			freeze(); await frames()
			check(value("q.gz12k.q54k") == 1 and value("q.gz14k.q55k") == 0,"saved branch checkpoint restores an unearned mine arrival")
		var row: Array = routes[index]
		teleport(row[0]); ticks(8)
		done("q.gz12k.q54k","authored mine approach completes q54 through entrance "+str(row[2]))
		check(value("q.gz12k.q54k."+str([3,5,4][index])) == 2,"selected mine site's optional exploration objective is earned")
		for alternative: Array in routes:
			gate(alternative[1],alternative[1] == row[1],"only selected mine route is open: "+String(alternative[1]))
		if await leave(row[1],"gz14k"):
			check(s._lmp_entrance == row[2],"actual mine transfer uses original entrance "+str(row[2]))
			var deploy: Rect2 = s.world.zone.exits[row[2]].deploy
			check(deploy.grow(1).has_point(hero().pos),"hero arrives within the authored mine deployment area")
	await finish("BASE_CAMPAIGN_INGOS_ROUTES","Prepared q53 gold and earned G53 offer; normal exchange and keyed gate followed by all three q54 approach branches restored from the same pending full save. Each branch earns q54/q55, closes the other approaches and uses the actual route map transfer into the correct gz14k entrance and deployment area. No completed objective or route-gate outcomes supplied.")
