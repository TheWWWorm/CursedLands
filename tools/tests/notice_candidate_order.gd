extends Node
## The AI's nearby-unit list follows the original refresh (0x5ca1d0): cells in
## the original cell table order, each cell's units in arrival order, every
## unit inserted at the list head, so the list runs backwards. Registry order
## (the earlier remake order) differs from it in every case below.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _ready() -> void:
	cell_table()
	list_order()
	print("NOTICE_CANDIDATE_ORDER ", JSON.stringify({"checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

static func cell_distance(c: Vector2i) -> float:
	var ex := maxi(absi(c.x) - 1, 0)
	var ey := maxi(absi(c.y) - 1, 0)
	return sqrt(float(ex * ex + ey * ey))

## Read through the script so that this program also runs, and fails on its
## order checks, against a source without the table.
func cell_table() -> void:
	var unit_ai: Variant = UnitAI
	var table: Array = (UnitAI as Script).get_script_constant_map().get("NOTICE_CELL_ORDER", [])
	check(table.size() == 882, "cell table present")
	var seen := {}
	var last := -1.0
	var sorted := true
	for i in table.size() >> 1:
		var c := Vector2i(table[i * 2], table[i * 2 + 1])
		seen[c] = true
		sorted = sorted and cell_distance(c) >= last
		last = cell_distance(c)
		check(unit_ai.call("notice_cell_rank", c) == i, "rank of table entry %d" % i)
	check(seen.size() == 441, "table holds the 441 offsets once")
	check(sorted, "table sorted by cell distance")
	# The original table's first D = 0 cells (its qsort is not stable).
	var head := []
	for i in mini(9, table.size() >> 1):
		head.append(Vector2i(table[i * 2], table[i * 2 + 1]))
	check(head == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1)], "original order of the D = 0 cells")
	if not table.is_empty():
		check(unit_ai.call("notice_cell_rank", Vector2i(11, 0)) == 441, "outside the table ranks last")

var names := {}

func spawn(w: GameWorld, label: String, pos: Vector2, dead := false) -> GameUnit:
	var u := GameUnit.new()
	u.uid = w.new_uid()
	u.world = w
	u.pos = pos
	u.dead = dead
	u.stats = {"sight": 25.0}
	u.proto = {"senses": [25.0, 100.0, 0.0]}
	w.adopt_prepared_unit(u)
	names[u] = label
	return u

func labels(list: Array) -> String:
	var out := PackedStringArray()
	for u in list:
		out.append(String(names.get(u, "?")))
	return " ".join(out)

## Cell (6, 6) holds the observer; offsets below are from it (16 m cells,
## round(2x - 0.5) / 32). Ranks: (0,0) 0, (1,0) 1, (1,1) 2, (-1,-1) 8,
## (-2,0) 9, (2,0) 10, (0,-2) 16, (3,0) 25; (4,0) is beyond D = 2.
func list_order() -> void:
	var w := GameWorld.new()
	w.nav.size = Vector2i(2048, 2048)
	var o := spawn(w, "O", Vector2(104, 104))
	spawn(w, "A", Vector2(105, 104))
	var b := spawn(w, "B", Vector2(88, 88))
	spawn(w, "C", Vector2(120, 120))
	spawn(w, "D", Vector2(100, 106))
	spawn(w, "E", Vector2(136, 104))
	spawn(w, "F", Vector2(72, 104))
	spawn(w, "G", Vector2(104, 72))
	spawn(w, "H", Vector2(120, 104), true)
	b.pos = Vector2(110, 99)   # enters the observer's cell after A and D
	spawn(w, "I", Vector2(89, 90))
	spawn(w, "J", Vector2(152, 104))
	spawn(w, "K", Vector2(168, 104))
	var grid := UnitAI._friend_grid(25.0 * 2.0 / 32.0)
	var radius := float(int(grid.reach) + 1) * 16.0 * 1.5
	var want := "J G E F I C H B D A"
	var want_alive := "J G E F I C B D A"
	var kernel: RefCounted = w.ai._unit_query
	print("NOTICE_ORDER_KERNEL ", kernel != null)
	check(labels(w.notice_units_near(o, radius, grid.cells, false, true)) == want,
		"tracked list order: " + labels(w.notice_units_near(o, radius, grid.cells, false, true)))
	check(labels(w.notice_units_near(o, radius, grid.cells, true, false)) == want_alive,
		"living list order: " + labels(w.notice_units_near(o, radius, grid.cells, true, false)))
	check(labels(w.ai._notice_candidates(o)) == want, "UnitAI nearby list: " + labels(w.ai._notice_candidates(o)))
	# Script paths (no helper, then the exhaustive client query) keep the order.
	w.ai._unit_query = null
	check(labels(w.notice_units_near(o, radius, grid.cells, false, true)) == want, "script path order")
	w.authority = false
	check(labels(w.notice_units_near(o, radius, grid.cells, false, true)) == want, "exhaustive path order")
	w.authority = true
	w.ai._unit_query = kernel
	# A death does not move a unit in its cell; a later arrival goes last.
	var a: GameUnit = names.find_key("A")
	a.dead = true
	w.nav.rebucket(a)
	check(labels(w.notice_units_near(o, radius, grid.cells, false, true)) == want, "death keeps arrival rank")
	a.pos = Vector2(105, 120)   # (0, 1), rank 3, then back to (0, 0)
	a.pos = Vector2(105, 104)
	check(labels(w.notice_units_near(o, radius, grid.cells, false, true)) == "J G E F I C H A B D",
		"return to a cell is a new arrival: " + labels(w.notice_units_near(o, radius, grid.cells, false, true)))
	# Removing a unit leaves the others' order unchanged.
	w.remove_unit(names.find_key("C"))
	check(labels(w.notice_units_near(o, radius, grid.cells, false, true)) == "J G E F I H A B D", "removal")
	w.free()
