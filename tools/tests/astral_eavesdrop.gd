extends "story_coop_predicates.gd"
const Repair := preload("res://src/game/script/story_astral_eavesdrop.gd")
const Q := "q.gz1h.q12h"
func setup(adapt:=true) -> ProbeVM:
	fixture()
	observer.proto=GameData.db.find("monster_prototypes","q12h Human Citizen M")
	var first:=actor(1012004,Vector2(153,65));first.proto=observer.proto
	actor(1012002,Vector2(93,21));actor(1012003,Vector2(94,17))
	var vm:=vm_for("gz1h","zone1",adapt)
	vm.areas={3:[Vector3(158,73,5)],4:[Vector3(153,66,3.5)],5:[Vector3(110,227,10)],6:[Vector3(126,88,1)]}
	s.state.set_var(0,Q,1);s.state.set_var(0,Q+".1",1)
	return vm
func normal(adapt:bool) -> Array:
	var vm:=setup(adapt)
	party[0].pos=Vector2(163.01,73);start(vm,"VCheck#5#2")
	check(s.state.get_var(0,Q+".1")==1,"outside original discovery radius waits")
	party[0].pos=Vector2(162.99,73);step(vm)
	check(s.state.get_var(0,Q+".1")==2 and s.state.get_var(0,Q+".2")==1,"inside original radius discovers house")
	party[0].pos=Vector2(156.51,66);step(vm)
	check(s.state.get_var(0,Q+".2")==1,"outside original listening radius waits")
	party[0].pos=Vector2(156.49,66);vm.seen[observer]=[party[0]];step(vm)
	check(s.state.get_var(0,Q+".2")==1,"being seen prevents listening")
	vm.seen.clear();step(vm)
	check(s.state.get_var(0,Q+".2")==2,"unseen listener advances original objective")
	step(vm,300)
	return [s.state.vars.duplicate(),green_trace(vm)]
func _ready():
	check(normal(false)==normal(true),"successful quest timing and state match original script exactly")
	for id in [1012004,1012005]:
		for looted in [false,true]:
			for stage in [0,1]:
				var vm:=setup();s.state.set_var(0,Q+".2",stage)
				var dead:GameUnit=s.world.units[id];dead.dead=true
				if looted:s.world.erase_unit(id);s.world.looted[id]=dead
				start(vm,"VCheck#5#2");start(vm,"VCheck#5#5");start(vm,"VCheck#5#8")
				Repair.recover(vm)
				check(s.state.get_var(0,Q+".2")==3,"dead/looted speaker closes impossible listening objective")
				check(s.state.get_var(0,Q+".4")==1 and s.state.get_var(0,Q)==1,"rescue stays available")
				check(actions(vm,"QuestComplete").is_empty(),"dead speaker grants no quest completion reward")
				var vars:=s.state.vars.duplicate();Repair.recover(vm)
				check(vars==s.state.vars,"recovery is idempotent")
				# An old save can carry waiting discovery/listening frames.
				var saved:=vm.save_state();vm=vm_for("gz1h","zone1");vm._restore(saved)
				party[0].pos=Vector2(153,66);dead.dead=false
				step(vm,4)
				check(s.state.get_var(0,Q+".2")==3,"save/revive cannot turn failed listening into heard conversation")
				s.world.units[1012002].dead=true;s.world.units[1012003].dead=true;step(vm,3)
				check(s.state.get_var(0,Q+".4")==2 and s.state.get_var(0,Q+".5")==1,"killing real jailers starts original escort")
				s.world.units[1012001].pos=Vector2(110,227);step(vm,3)
				check(s.state.get_var(0,Q)==2 and actions(vm,"QuestComplete").size()==1,"original rescue still completes and rewards once")
	var vm:=setup();s.world.units[1012004].dead=true;Repair.recover(vm)
	start(vm,"VCheck#5#8");s.world.units[1012001].dead=true;step(vm)
	check(s.state.get_var(0,Q)==3,"captive death still fails quest")
	vm=setup();s.state.set_var(0,Q+".2",2);observer.dead=true;Repair.recover(vm)
	check(s.state.get_var(0,Q+".2")==2,"already heard conversation remains completed")
	vm=setup();s.state.set_var(0,Q,0);observer.dead=true;Repair.recover(vm)
	check(s.state.get_var(0,Q+".2")==0,"inactive quest untouched")
	vm=setup();observer.dead=true;observer.proto={"name":"Mod character"};Repair.recover(vm)
	check(s.state.get_var(0,Q+".2")==0,"replaced actor untouched")
	vm=setup(false);vm.ast.scripts["VCheck#5#3"].blocks[0].body.append([ScriptParser.S_CALL,"Sleep",[[ScriptParser.N_NUM,1.0]]])
	Compat.apply(vm.ast,s.state.campaign_id,"gz1h");observer.dead=true;Repair.recover(vm)
	check(not vm.ast.has_meta(&"astral_eavesdrop") and s.state.get_var(0,Q+".2")==0,"modified quest script is not patched")
	for instance:ProbeVM in vms:instance.briefings=null;instance.instances.clear();instance.globals.clear();instance.seen.clear();instance.actions.clear()
	vms.clear()
	for n:Node in allocations:
		if n is GameWorld:n.units={};n.looted.clear();n.objects.clear();n.vm=null
	for n:Node in allocations:n.free()
	print("ASTRAL_EAVESDROP ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
