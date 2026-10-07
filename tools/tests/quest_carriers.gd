extends Node
const QuestLights := preload("res://src/game/fx/quest_lights.gd")
class Shell extends Game:
	func _ready() -> void:
		set_process(false)
		set_process_unhandled_input(false)
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)
func object(w: GameWorld, id: int, info: String) -> Node3D:
	var n := Node3D.new()
	n.set_meta("ei",{"nid":id,"kind":"OBJECT","quest_info":info})
	w.add_child(n); w._register_object(n)
	return n
func _ready() -> void:
	var s := Session.new(); s.state = CampaignState.new()
	var g := Shell.new(); g.session = s; s.game = g
	var w := GameWorld.new(); w.zone = {"id":"test"}; w.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(w); g.world = w
	var fx := QuestLights.new(g)
	add_child(fx)
	add_child(g)
	var n := object(w,1,"goal")
	for i in range(2,102): object(w,i,"")
	s.state.set_var(0,"q.test.goal",1)
	fx.on_world(w)
	check(fx.lights.has(1) and fx._objects.size() == 1,"initial scan registers only quest carriers")
	var original: OmniLight3D = fx.lights[1]
	for i in 20: fx._refresh_objects(false)
	check(fx.lights[1] == original,"unchanged snapshots retain the light")
	s.state.set_var(0,"q.test.goal",0); fx._refresh_objects(false)
	check(fx.lights[1] == original,"zero preserves an existing light")
	s.state.set_var(0,"q.test.goal",2); fx._refresh_objects(false)
	check(not fx.lights.has(1),"state snapshot removes completed quest light")
	fx.quest_changed("q.other.goal",1)
	check(fx.lights.has(1),"native suffix notification works across zones")
	fx._refresh_objects(false)
	check(fx.lights.has(1),"unchanged local state does not undo suffix notification")
	var added := object(w,102,"next")
	s.state.set_var(0,"q.test.next",1); fx._refresh_objects(false)
	check(fx.lights.has(102),"AddMob registration discovers a new carrier")
	w.objects.erase(102); fx._refresh_objects(false)
	check(not fx.lights.has(102),"removed registered object loses light while node is alive")
	var replacement := object(w,1,"goal")
	fx._refresh_objects(false)
	check(fx._objects[1][0] == replacement,"same-count replacement refreshes carrier identity")
	w.objects.erase(1); fx._refresh_objects(false)
	check(not fx.lights.has(1),"removed carrier cannot retain light")
	var u := GameUnit.new(); u.world = w; u.uid = 200; u.info = {"quest_info":"next"}
	w.add_child(u); w.set_unit(u.uid,u); fx._refresh_objects(false)
	check(fx.lights.has(200),"new unit registry entry discovers carrier")
	w.erase_unit(200); fx._refresh_objects(false)
	check(not fx.lights.has(200),"looted unit loses light before node is freed")
	g.world = null; fx.on_world(null)
	fx.queue_free(); w.queue_free(); g.queue_free(); s.free()
	await get_tree().process_frame
	print("QUEST_CARRIERS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
