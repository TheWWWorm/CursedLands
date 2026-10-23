extends Node
## AddMob shares a zone's global symbol table. Side-quest overlays retain
## isolated names; the real q21 battle/save gate is in lia_campaign_late_ending.
var checks := 0
var failures := 0
const BASE = '''GlobalVars(NULL:object, fighters:group, count:float)
DeclareScript Gate(this:object)
Script Gate(if()then(KillScript()))
WorldScript()'''
const EXTRA = '''GlobalVars(NULL:object, fighters:group, count:float, added:group)
DeclareScript Gate(this:object)
Script Gate(if()then(KillScript()))
WorldScript(AddObject(fighters,NULL) count=8)'''
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func fixture() -> ScriptVM:
	var vm := ScriptVM.new()
	vm.ast = ScriptParser.parse(BASE)
	vm.globals = {"NULL":null,"fighters":[17],"count":6.0}
	return vm
func _ready() -> void:
	var shared := fixture()
	var body := shared._merge_script(EXTRA,"addon",true)
	check(shared.ast.errors.is_empty(),"shared addon parses with original declarations")
	check(shared.globals.fighters == [17] and shared.globals.count == 6.0,"AddMob redeclaration preserves existing group and scalar values")
	check(not shared.globals.has("fighters_addon") and not shared.globals.has("count_addon"),"AddMob keeps parent global names")
	check(shared.globals.has("added") and shared.globals.added.is_empty(),"new addon globals initialize normally")
	check(shared.ast.scripts.has("Gate") and shared.ast.scripts.has("Gate_addon"),"script-name collision still keeps both handlers")
	check(str(body).contains('"fighters"') and not str(body).contains("fighters_addon"),"addon world body refers to parent group")
	var overlay := fixture()
	var other := overlay._merge_script(EXTRA,"sidequest")
	check(overlay.globals.fighters == [17] and overlay.globals.count == 6.0,"side quest preserves parent values")
	check(overlay.globals.has("fighters_sidequest") and overlay.globals.fighters_sidequest.is_empty(),"side-quest group remains isolated")
	check(overlay.globals.has("count_sidequest") and overlay.globals.count_sidequest == null,"side-quest scalar remains isolated")
	check(str(other).contains("fighters_sidequest") and str(other).contains("count_sidequest"),"side-quest body uses its isolated symbols")
	print("LIA_CAMPAIGN_LATE_ADDMOB ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
