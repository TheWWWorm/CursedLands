extends RefCounted
## The discarded bridge route retains a native watcher after quest completion.
## Revenge reuses area 2, so that watcher can fail an old objective and erase
## the mansion trigger. Add stage guards only to the complete inspected
## original definitions; preserve every body and saved statement index.
const P = preload("res://src/game/script/script_parser.gd")
const ORIGINAL := """
DeclareScript VCheck#1#3 ( this : object )
DeclareScript VCheck#1#4 ( this : object )
DeclareScript VCheck#4#1 ( this : object )
DeclareScript VCheck#4#2 ( this : object )
DeclareScript VCheck#4#3 ( this : object )
Script VCheck#1#3
(
  if
  (
    Any( i, Heroes, IsInArea( 2, GetX( i ) , GetY( i )  )  )
  )
  then
  (
    KillScript(  )
    GSSetVarMax( 0, "q.gz2h.q7h.2", 2 )
    GSSetVarMax( 0, "q.gz2h.q7h.3", 3 )
    GSSetVarMax( 0, "q.gz2h.q7h.4", 1 )
    DeleteArea( 2 )
    DeleteArea( 3 )
    VCheck#1#5( this )
  )
)

Script VCheck#1#4
(
  if
  (
    Any( i, Heroes, IsInArea( 3, GetX( i ) , GetY( i )  )  )
  )
  then
  (
    KillScript(  )
    GSSetVarMax( 0, "q.gz2h.q7h.3", 2 )
    GSSetVarMax( 0, "q.gz2h.q7h.2", 3 )
    GSSetVarMax( 0, "q.gz2h.q7h.4", 1 )
    DeleteArea( 2 )
    DeleteArea( 3 )
    VCheck#1#5( this )
  )
)

Script VCheck#4#1
(
  if
  (
    IsEqual( GSGetVar( 0, "q.gz2h.q14h" ) , 1 )
  )
  then
  (
    KillScript(  )
    AddMob("zone2mest.mob")
    SwitchLeverState( GetObject( 150158 ) , 1 )
    AddRoundToArea( 1, 115, 317 , 10 )
    AddRoundToArea( 2, 117, 354 , 10 )
    Sleep( 20 )
//     SetDiplomacy ( 10 , 16 , -1 )  
//     SetDiplomacy ( 16 , 10 , -1 )
    GSSetVarMax( 0, "q.gz2h.q14h.1", 1 )
    GSSetVarMax( 0, "q.gz2h.q14h.5", 1 )
    VCheck#4#2( this )
    VCheck#4#6( this )
  )
)

Script VCheck#4#2
(
  if
  (
    Any( i, Heroes, IsInArea( 1, GetX( i ) , GetY( i )  )  )
  )
  then
  (
    KillScript(  )
    GSSetVarMax( 0, "q.gz2h.q14h.1", 2 )
    GSSetVarMax( 0, "q.gz2h.q14h.2", 1 )
    UMSentry( GetObject( 1014001 ) , 117 , 354 )
    UMSentry( GetObject( 1014002 ) , 117 , 354 )
    UMSentry( GetObject( 1014003 ) , 117 , 354 )
    DeleteArea( 1 )
  )
)

Script VCheck#4#3
(
  if
  (
    Any( i, Heroes, IsInArea( 2, GetX( i ) , GetY( i )  )  )
    IsEqual( GSGetVar( 0, "q.gz2h.q14h" ) , 1 )
  )
  then
  (
    KillScript(  )
    GSSetVarMax( 0, "q.gz2h.q14h.2", 2 )
    GSSetVarMax( 0, "q.gz2h.q14h.3", 1 )
    UMSentry( GetObject( 1014002 ) , 104 , 358 )
    UMSentry( GetObject( 1014003 ) , 105 , 348 )
    DeleteArea( 2 )
    VCheck#4#4( this )
  )
)
"""
static var _expected: Dictionary = {}


static func apply(ast: ScriptParser) -> void:
	if _expected.is_empty(): _expected = P.parse(ORIGINAL).scripts
	for name: String in _expected:
		if ast.scripts.get(name, {}) != _expected[name]: return
	for name: String in ["VCheck#1#3", "VCheck#1#4"]:
		var stage := "2" if name == "VCheck#1#3" else "3"
		for key: String in ["q.gz2h.q7h", "q.gz2h.q7h." + stage]:
			ast.scripts[name].blocks[0].conds.push_front([P.N_CALL, "IsEqual", [
				[P.N_CALL, "GSGetVar", [[P.N_NUM, 0.0], [P.N_STR, key]]], [P.N_NUM, 1.0]]])
	ast.scripts["VCheck#4#3"].revenge_trigger = true


static func recover(vm: ScriptVM) -> void:
	if not vm.ast.scripts.get("VCheck#4#3", {}).get("revenge_trigger", false): return
	if vm.session.state.get_var(0, "q.gz2h.q14h") != 1: return
	# Earlier checkpoints can already have lost this area. Recreate only an
	# absent native trigger whose matching objective and idle watcher survive.
	for row: Array in [[1,"VCheck#4#2",Vector3(115,317,10)],[2,"VCheck#4#3",Vector3(117,354,10)]]:
		if vm.areas.has(row[0]) or vm.session.state.get_var(0, "q.gz2h.q14h.%d" % row[0]) != 1: continue
		if vm.instances.any(func(i): return i.sname == row[1] and not i.killed and i.frames.is_empty()):
			vm.areas[row[0]] = [row[2]]
