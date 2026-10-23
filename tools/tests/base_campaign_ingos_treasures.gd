extends "base_campaign_ingos_support.gd"
## All six optional Ingos treasure quests use original map proximity/use
## watchers; none has an injected accepted or completed quest flag.

func _ready() -> void: run.call_deferred()

func run() -> void:
	ingos()
	await enter("gz11k")
	start(["VCheck#0#237","VCheck#0#240","VCheck#0#243"])
	near_object(4044)
	check(value("q.gz11k.qk15k") == 1,"southern ruins approach discovers the optional treasure quest")
	use(4044); ticks(8)
	done("q.gz11k.qk15k","ordinary southern ruins chest completes qk15k")
	stable("southern ruins bonus")
	await enter("gz12k")
	start(["VTriger#0#79","VCheck#0#107","VCheck#0#172"])
	teleport(Vector2(77,204)); near_object(6102)
	check(value("q.gz12k.qk10k") == 1,"hidden dryad-cache approach discovers qk10k")
	use(6102); ticks(8)
	done("q.gz12k.qk10k","ordinary dryad log use completes its treasure quest")
	stable("dryad log bonus")
	await enter("gz13k")
	start(["VTriger#0#195","VCheck#0#221","VCheck#0#222","VCheck#0#223","VCheck#0#230"])
	for pair: Array in [[4225,"qk12k"],[4227,"qk11k"],[4229,"qk13k"],[4231,"qk14k"]]:
		near_object(pair[0])
		var key := "q.gz13k."+String(pair[1])
		check(value(key) == 1,"optional chest approach discovers "+String(pair[1]))
		var before := accounting()
		use(pair[0]); ticks(8)
		done(key,"ordinary chest use completes "+String(pair[1]))
		check(accounting().experience > before.experience and s.state.items != before.items,"optional treasure grants real experience and inventory reward: "+String(pair[1]))
		stable(String(pair[1])+" reward")
	await roundtrip("base_ingos_optional_treasures",["q.gz11k.qk15k","q.gz12k.qk10k","q.gz13k.qk11k","q.gz13k.qk12k","q.gz13k.qk13k","q.gz13k.qk14k"])
	await finish("BASE_CAMPAIGN_INGOS_TREASURES","Original optional treasure quests qk10k–qk15k, discovered by real proximity handlers and completed by ordinary use of original chests/log; experience and item accounting, repeat polls and full save/reload. No accepted/completed quest flags supplied. Field entry and movement accelerated; this is remake passability evidence, not native executable parity.")
