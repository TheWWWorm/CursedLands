extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func _ready() -> void:
	check(EIKeymap.bindings(2).get(EIKeymap.scan_code(KEY_Q)) == "direct_quests", "fresh direct layout binds Q")
	var file := FileAccess.open(EIKeymap.DIRECT_FILE,FileAccess.WRITE)
	file.store_string("Q direct_interact\nTAB direct_pointer\nW direct_forward\n"); file.close()
	EIKeymap._direct_loaded = false
	var upgraded := EIKeymap.bindings(2)
	check(upgraded.get(EIKeymap.scan_code(KEY_Q)) == "direct_interact", "upgrade keeps custom Q")
	check(upgraded.get(EIKeymap.scan_code(KEY_J)) == "direct_quests", "upgrade uses a spare key")
	upgraded.erase(EIKeymap.scan_code(KEY_J))
	EIKeymap._direct_map = upgraded; EIKeymap.save(2); EIKeymap._direct_loaded = false
	check(not "direct_quests" in EIKeymap.bindings(2).values(), "intentional unbind survives reload")
	check(EIKeymap.bindings(2).get(EIKeymap.scan_code(KEY_TAB)) == "direct_pointer", "Tab remains pointer toggle")
	print("DIRECT_QUEST_BINDINGS ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
