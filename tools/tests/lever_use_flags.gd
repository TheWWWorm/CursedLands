extends Node
## Native permission and consumption contract; controlled world, real VM use.
## Actual path/animation/ENet cases are separate.
class QuietSession extends Session:
	var events: Array = []
	var skill_ok := true
	func broadcast(e: Dictionary) -> void: events.append(e)
	func lever_science_ok(_u: GameUnit, _nid: int) -> bool: return skill_ok

var checks := 0
var failures: Array = []
var s: QuietSession
var w: GameWorld
var vm: ScriptVM
var hero: GameUnit
const ID := 101
const P := preload("res://src/game/script/script_parser.gd")

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr('FAIL ',label)

func observe() -> Dictionary:
	return {'state':int(w.levers[ID].state),'enabled':bool(w.levers[ID].get('enabled',true)),'usable':w.lever_sys.usable(ID)}

func matches(expected: Dictionary) -> bool:
	var actual := observe()
	return int(actual.state)==int(expected.state) and bool(actual.enabled)==bool(expected.enabled) and bool(actual.usable)==bool(expected.usable)

func enable(yes: bool) -> void:
	vm._call('EnableLever',[[P.N_CALL,'GetObject',[[P.N_NUM,ID]]],[P.N_NUM,int(yes)]],ScriptVM.Instance.new())

func _ready() -> void:
	GameData.options.merge({'smile_faces':0,'show_tutorial':0},true)
	s = QuietSession.new(); add_child(s); s.set_physics_process(false)
	w = GameWorld.new(); w.session=s; s.world=w; add_child(w)
	w.nav=NavGrid.new(); w.presentation=false
	var obj := Node3D.new(); obj.set_meta('ei',{'nid':ID,'template':'','lever_science':PackedInt32Array([1,0,0])})
	w.objects[ID]=obj; w.add_child(obj)
	w.lever_sys=LeverSystem.new(w)
	vm=ScriptVM.new(); vm.session=s; vm.world=w; w.vm=vm
	hero=GameUnit.new(); hero.world=w; w.add_child(hero)
	var path: String=get_script().resource_path.get_base_dir().path_join('fixtures/original_lever_use.json')
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path)).campaigns['lost_in_astral' if GameData.campaign_id==CampaignProfile.ASTRAL else 'original']
	for i in source.eligibility.size():
		var row: Dictionary=source.eligibility[i]
		w.levers[ID]=row.input.duplicate(true)
		check(matches(row.expected),'native eligibility '+str(i))
	for i in source.sequences.size():
		var row: Dictionary=source.sequences[i]
		w.levers[ID]={'state':0,'states':int(row.states),'cycled':int(row.cycled),'science':[1,0,0],'enabled':true}
		s.skill_ok=bool(row.success)
		for step: Dictionary in row.steps:
			match String(step.action):
				'use': vm._use_lever(hero,ID)
				'reset': w.lever_sys.set_state(ID,0,0)
				'enable_at_end': enable(true); w.lever_sys.set_state(ID,int(row.states)-1,0)
				'disable': enable(false)
			check(matches(step.expected),'native use sequence %d / %s'%[i,step.action])
			# Every observed permission survives the real saved-row importer.
			var saved: Array=bytes_to_var(var_to_bytes(w.lever_sys.export_row(ID)))
			w.lever_sys.restore_row(ID,saved)
			check(matches(step.expected),'saved use sequence %d / %s'%[i,step.action])
	w.vm=null; vm.world=null; vm.session=null; s.world=null
	w.free(); s.free()
	print('LEVER_USE_FLAGS ',checks,' checks ',failures.size(),' failures')
	get_tree().quit(0 if failures.is_empty() else 1)
