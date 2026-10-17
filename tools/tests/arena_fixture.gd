extends RefCounted
## Existing mechanics fixtures buy their company explicitly. They retain a
## fixed six-gold budget so unrelated economy thresholds stay isolated.
const COMPOSITIONS := [[0, 1, 3], [0, 2, 4], [1, 3, 5]]

static func begin(run: ArenaRun, seed_value: int, composition := 0, challenge := 0) -> void:
	run.begin(seed_value, composition, challenge)
	buy_company(run, composition)

static func buy_company(run: ArenaRun, composition := 0) -> void:
	for i in 3:
		var family: int = COMPOSITIONS[composition][i]
		run.shop[0] = {"family":family,"rank":0,"locked":false}
		var index := 0
		var bought := run.buy(index)
		assert(bought.is_empty())
		var entry: Dictionary = run.army.back()
		var placed := run.deploy(entry.uid, Vector2(25.5 if i < 2 else 21.5, 29.5 if i == 0 else 34.5 if i == 1 else 32.0))
		assert(placed.is_empty())
	run.gold = 6
	run._undo.clear()
	run._roll_shop(false)
	run._touch()
