extends Node
## Actual LiA lever metadata, frontend state, skill rounding, key bypass and
## shared spell-tooltip layout. Run with isolated user data and LiA assets.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
func _ready() -> void:
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"scroll_border":0,"control_mode":0},true)
	GameData.options.merge(GfxPresets.values(GfxPresets.VERY_LOW),true)
	var s:=Session.new();add_child(s)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,s._hero_proto(0));await s.enter_zone("gz2h",1,false)
	s.world.set_process(false);s.world.set_physics_process(false);s.set_physics_process(false)
	var hero:GameUnit=s.party_units(0)[0]
	g.selected.assign([hero])
	var actors:Array[GameUnit]=[hero]
	var h:Dictionary=hero.get_meta("hero");h.skills.science=0;hero.stats.dex=25.0
	var nid:=-1
	for id in s.world.levers:
		if s.world.lever_sys.usable(id):nid=id;break
	check(nid>=0,"real Suslanger interactable exists")
	if nid<0:get_tree().quit(1);return
	var original:Dictionary=s.world.levers[nid].duplicate(true)
	s.world.levers[nid].merge({"science":[5,0,22],"state":0,"states":2,"enabled":true},true)
	check(s.lever_requirement(nid,actors).contains("22"),"insufficient selected skill shows requirement")
	check(not s.lever_science_ok(hero,nid),"hover agrees with authoritative failure")
	for use in [21.49,21.5,21.51,22.0,24.0,-1.0]:
		hero.stats.dex=25.0+use
		check(s.lever_requirement(nid,actors).is_empty()==s.lever_science_ok(hero,nid),"effective dexterity, nearest-even and legacy unsigned skill: "+str(use))
	hero.stats.dex=25.0
	s.world.levers[nid].state=1
	check(s.lever_requirement(nid,actors).is_empty(),"open container has no locked tooltip")
	s.world.levers[nid].state=0;s.world.levers[nid].enabled=false
	check(s.lever_requirement(nid,actors).is_empty(),"disabled script object has no skill tooltip")
	s.world.levers[nid].enabled=true
	for science in [[0,0,0],[8,123,0],[1,0,0],[2,0,22],[]]:
		s.world.levers[nid].science=science
		check(s.lever_requirement(nid,actors).is_empty(),"script/key-only/tool-only/unlocked: "+str(science))
	var quest:="";var sid:=0
	for item:Dictionary in GameData.db.table("quest_items"):
		if int(item.get("script_id",0))>0:quest=String(item.name);sid=int(item.script_id);break
	check(sid>0,"original quest key exists")
	if sid>0:
		s.world.levers[nid].science=[9,sid,22]
		s.state.quest_items[quest]=1
		check(s.lever_science_ok(hero,nid) and s.lever_requirement(nid,actors).is_empty(),"party quest key suppresses a misleading skill requirement")
		s.state.quest_items.erase(quest)
	s.world.levers[nid].science=[1,0,22]
	check(s.lever_requirement(nid,[]).is_empty(),"no selection has no requirement")
	hero.dead=true
	check(s.lever_requirement(nid,actors).is_empty(),"dead selection has no requirement")
	hero.dead=false
	# A network frontend has no VM; requirements still use replicated state.
	var vm:=s.world.vm;s.world.vm=null
	check(s.lever_requirement(nid,actors).contains("22"),"frontend does not depend on authoritative script VM")
	s.world.vm=vm
	var corpse:=s.world.spawn_unit({"prototype":"q11h Human DeadMan M","name":"q11h Human DeadMan M-150088","need_import":0,"player":1})
	check(corpse!=null,"reported corpse prototype loads")
	if corpse:
		corpse.dead=true
		check(WorldLabels.unit_name(corpse)==RemakeText.t("Remains"),"reported corpse has a localized label rather than map id")
		check(not corpse.display_name.contains("150088") and not corpse.display_name.contains("q11h"),"raw id never enters displayed name")
		corpse.display_name="Test player"
		check(WorldLabels.unit_name(corpse)=="Test player","explicit player name is preserved")
		s.world.remove_unit(corpse)
	s.world.levers[nid]=original
	g.queue_free();s.queue_free();await get_tree().process_frame
	print("LOCKED_HOVER ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
