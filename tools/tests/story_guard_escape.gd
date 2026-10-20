extends "patrol_escape_alerts.gd"
const Escape := preload("res://src/game/script/story_guard_escape.gd")
const Compat := preload("res://src/game/script/story_compat.gd")
func _ready()->void:
	var source:=EIMob.load_bytes(GameData.read_file("maps/zone19.mob")).script_text
	var s:=Session.new();add_child(s)
	var w:=GameWorld.new();w.zone={"id":"gz19h","type":"game"};w.session=s;s.world=w;w.time=1
	var guard:=actor(w,1,1,Vector2.ZERO);var hero:=actor(w,2,0,Vector2(5,0));hero.controller=0
	var guest:=actor(w,3,0,Vector2(6,0));guest.controller=1
	w.set_relation(1,0,2)
	var vm:=ScriptVM.new();vm.world=w;vm.session=s;w.vm=vm;vm.ast=ScriptParser.parse(source)
	Compat.apply(vm.ast,CampaignProfile.ORIGINAL,"gz19h")
	check(vm.ast.scripts["VCheck#0#393"].blocks[0].conds.size()==2,"original pursuit gets a contact condition")
	check(vm.ast.scripts["VCheck#0#439"].blocks[0].conds[0][1]=="RemakeGuardsEscaped","original kill-only objective admits escape")
	vm.areas[1]=[Rect2(-10,-10,25,20)]
	check(Escape.contact(vm,[guard],hero),"gate guard notices the intruder")
	guard.pos=Vector2(-100,0)
	check(Escape.contact(vm,[guard],hero),"gate alarm summons distant reinforcements before visual contact")
	guard.pos=Vector2.ZERO
	check(not Escape.escaped(vm,[guard]),"escaping objective stays active near the gate")
	hero.pos=Vector2(50,0);w.time+=GameUnit.TICK
	check(not Escape.contact(vm,[guard],hero),"pursuit loop loses distant intruder")
	check(not Escape.escaped(vm,[guard]),"host escape cannot abandon a nearby guest")
	guest.pos=Vector2(51,0);w.time+=GameUnit.TICK
	check(Escape.escaped(vm,[guard]),"all living party members can escape without killing guards")
	guest.pos=Vector2(6,0);w.time+=GameUnit.TICK
	check(Escape.contact(vm,[guard],guest),"re-entering intruder can rearm the authored alarm")
	guard.dead=true
	check(Escape.escaped(vm,[guard]),"defeating the guards still completes the objective")
	var modded:=ScriptParser.parse(source)
	modded.scripts["VCheck#0#439"].blocks[0].body.clear()
	Compat.apply(modded,CampaignProfile.ORIGINAL,"gz19h")
	var original:=modded.scripts.duplicate(true);Escape.apply(modded)
	check(modded.scripts==original,"changed mod quest remains untouched")
	for u in [guard,hero,guest]:u.free()
	s.world=null;w.free();s.queue_free()
	print("STORY_GUARD_ESCAPE ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)
