extends Node
## Live models and unmodified inventories on both campaign sides of a hub.
var checks:=0
var failures:=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func frames(n:=4) -> void:
	for i in n:await get_tree().process_frame
func helmet(m:EIUnitModel) -> bool:
	return not m.find_children("hd_armor*","",true,false).is_empty()
func _ready() -> void:
	GameData.options.merge({"auto_graphics":0,"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"confine_mouse":0},true)
	var s:=Session.new();add_child(s);var g:=Game.new();g.session=s;s.game=g;add_child(g)
	s.state.ensure_hero(0,"Human Hero");s.state.ensure_hero(1,"Human Hero","Appearance Guest")
	var armor:=PackedStringArray(["hadagan high2 helm.adamantium","hadagan high2 plate.adamantium"])
	var weapons:=PackedStringArray(["battle axe.adamantium"])
	s.state.heroes[0][0].armors=Array(armor);s.state.heroes[0][0].weapons=Array(weapons)
	await s.enter_zone("bz13h",1,false);s.set_physics_process(false);s.world.vm.instances.clear()
	var u:GameUnit=s.party_units(0)[0];var original:=u.info.duplicate(true);var stats:=u.stats.duplicate(true)
	check(u.model.weapon_type.is_empty() and not helmet(u.model),"safe-zone protagonist has bare head and empty hands")
	check(u.info.armors==armor and u.info.weapons==weapons and s.state.heroes[0][0].armors==Array(armor),"safe appearance retains actual equipped items")
	u.set_equipment(armor,weapons)
	check(u.model.weapon_type.is_empty() and not helmet(u.model),"changing equipment inside hub retains peaceful appearance")
	check(u.stats==stats,"presentation does not change combat stats")
	var preview:=EIUnitModel.create(u.figure_info(),true);check(helmet(preview) and preview.weapon_type=="axe","inventory preview retains actual helmet and weapon");preview.free()
	u.buffs.strength={};u.refresh_figure();check(not helmet(u.model) and u.model.weapon_type.is_empty(),"buff rebuilding preserves peaceful equipment");u.buffs.clear()
	var npc:GameUnit=s.world.units[338791]
	check(helmet(npc.model) and npc.model.weapon_type=="axe","authored guard retains helmet and weapon")
	# Same figure as a hired companion is deliberately outside the original
	# protagonist-only helmet suppression, even when player-controlled.
	npc.controller=0;npc.set_meta("hero",{"merc":1});npc.refresh_figure()
	check(helmet(npc.model) and npc.model.weapon_type=="axe","hired companion retains authored equipment")
	u.controller=1;u.refresh_figure();check(not helmet(u.model) and u.model.weapon_type.is_empty(),"co-op protagonist uses same safe-zone rule")
	u.controller=0
	await s.enter_zone("gz15h",1,false);s.set_physics_process(false);s.world.vm.instances.clear()
	u=s.party_units(0)[0]
	check(helmet(u.model) and u.model.weapon_type=="axe","leaving safe zone restores helmet and held weapon")
	check(u.info.armors==original.armors and u.info.weapons==original.weapons,"zone travel preserves real equipment")
	g.free();s.free();await frames(6);TexUpscale.shutdown()
	print("SAFE_ZONE_APPEARANCE ",checks," checks ",failures," failures");get_tree().quit(1 if failures else 0)
