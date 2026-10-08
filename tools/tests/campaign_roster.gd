extends Node
## Synthetic ownership/death permutations with actual campaign handlers and
## predicates from the installed original .mob files; isolated save roundtrips.
const Grants := preload("res://src/game/script/camp_grants.gd")
const P := preload("res://src/game/script/script_parser.gd")
var checks := 0
var failures := 0
var allocations: Array[Node] = []

class ProbeSession extends Session:
	func sync_state() -> void: pass
	func broadcast(_event: Dictionary) -> void: pass
	func _refresh_character(_u: GameUnit, _h: Dictionary) -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func fixture() -> ProbeSession:
	var s := ProbeSession.new(); allocations.append(s)
	s.state = CampaignState.new()
	s.state.ensure_hero(0, "Human Hero")
	s.state.ensure_hero(1, "Human Hero", "Guest")
	s.players = {1:{"index":0,"name":"Host"},42:{"index":1,"name":"Guest"}}
	s.online = true
	s.coop = CoopProgress.new(); allocations.append(s.coop); s.coop.session = s
	s.world = GameWorld.new(); allocations.append(s.world); s.world.session = s
	s.world.zone = {"id":"test","type":"game"}
	return s

func actor(s: ProbeSession, h: Dictionary, owner: int, uid: int) -> GameUnit:
	var u := GameUnit.new(); allocations.append(u)
	u.uid = uid; u.controller = owner; u.world = s.world
	u.info = {"name":h.get("unit_name",h.name),"complexion":h.complexion}
	u.proto = {"name":h.prototype}
	u.set_meta("hero", h); s.world.set_unit(uid, u)
	return u

func vm_for(s: ProbeSession, mob := "") -> ScriptVM:
	var vm := ScriptVM.new(); vm.session = s; vm.world = s.world; s.world.vm = vm
	vm.ast = ScriptParser.parse("") if mob.is_empty() else ScriptParser.parse(EIMob.load_bytes(GameData.read_file("maps/"+mob+".mob")).script_text)
	vm.globals.Heroes = []
	return vm

func vm_call(vm: ScriptVM, name: String, values: Array) -> Variant:
	var args := []
	for v in values: args.append([P.N_STR if v is String else P.N_NUM, v])
	return vm._call(name, args, ScriptVM.Instance.new())

func _ready() -> void:
	var s := fixture()
	var main := actor(s, s.state.heroes[0][0], 0, 1500000001)
	var guest := actor(s, s.state.heroes[1][0], 1, 1500000002)
	var vm := vm_for(s)
	for dead in [false,true]:
		main.dead = dead
		guest.controller = -1
		s.players.erase(42)
		check(vm._by_name("Hero") == main, "protagonist survives disconnect, dead="+str(dead))
		check(vm_call(vm,"GetUnitOfPlayer",[0.0,0.0]) == main, "slot zero survives disconnect, dead="+str(dead))
		check(vm_call(vm,"GetMercsNumber",[0.0]) == 0.0, "abandoned guest is not a mercenary")
		guest.controller = 1
		s.players[42] = {"index":1,"name":"Guest"}
		check(vm._by_name("Hero") == main, "protagonist survives guest reconnect, dead="+str(dead))
	main.dead = false
	var companion: Dictionary = s.state.heroes[0][0].duplicate(true)
	companion.merc = 2; companion.unit_name = "merc2"; companion.party = ""
	s.state.mercs[2] = companion
	var kel := actor(s, companion, 1, ScriptVM.name_id("merc2"))
	for owner in [0,1]:
		kel.controller = owner; companion.controller = owner
		check(vm_call(vm,"GetUnitOfPlayer",[0.0,1.0]) == kel, "story slot one is Kel with owner "+str(owner))
		check(vm_call(vm,"GetUnitOfPlayer",[0.0,2.0]) == null, "extra guest cannot fill an absent story role")
		check(vm_call(vm,"GetMercsNumber",[0.0]) == 1.0, "companion count independent of owner")
		kel.dead = true
		check(vm_call(vm,"GetUnitOfPlayer",[0.0,1.0]) == kel, "dead companion retains authored slot")
		check(vm_call(vm,"GetMercsNumber",[0.0]) == 0.0, "dead companion is not counted alive")
		kel.dead = false
	if GameData.campaign_id == CampaignProfile.ASTRAL:
		vm = vm_for(s,"zone31")
		var inst := ScriptVM.Instance.new()
		kel.dead = true; vm._refresh_heroes()
		check(vm._all(vm.ast.scripts.CheckFail.blocks[0].conds,inst), "original LiA CheckFail observes dead required companion")
		kel.dead = false; guest.dead = true; vm._refresh_heroes()
		check(not vm._all(vm.ast.scripts.CheckFail.blocks[0].conds,inst), "extra guest death uses co-op revive rules")
		guest.dead = false; main.dead = true; vm._refresh_heroes()
		check(vm._all(vm.ast.scripts.CheckFail.blocks[0].conds,inst), "original LiA CheckFail observes dead protagonist")
		main.dead = false
		var imported := CampaignState.new(); imported.ensure_hero(0,"Human Hero")
		imported.money = 123
		for chapter in ["FPrison","FSusel","Gipat","Jigran1","Jigran2","Jigran3"]:
			imported.create_party(chapter); imported.add_party_unit(chapter,"Hero","Human Hero"); imported.set_current_party(chapter)
			imported.heroes[0][0].str = 61.0; imported.money = 9876
			check(CoopProgress.main_hero(imported).str == 61.0 and CoopProgress.main_bag(imported).money == 9876, chapter+": import uses progressed Kir and his bag")
		imported.set_current_party("FSusel")
		imported.create_party("Shaina"); imported.add_party_unit("Shaina","Shaina","Human Hero"); imported.set_current_party("Shaina")
		imported.heroes[0][0].str = 99.0; imported.money = 44
		check(CoopProgress.main_hero(imported).str == 61.0 and CoopProgress.main_bag(imported).money == 9876,"temporary Shaina import keeps waiting Kir")
		for branch: String in Grants.HERO:
			var st := CampaignState.new(); st.ensure_hero(0,"Human Hero")
			st.set_var(0,"b.Clerk.brief_3"+branch,2)
			st.create_party("FPrison"); st.add_party_unit("FPrison","Hero","Hero1"); st.set_current_party("FPrison")
			st.ensure_hero(1,"Human Hero","Late")
			check(Grants.catch_up(st,1), branch+": actual prison chapter allows late catch-up")
			var expected: Dictionary = st.heroes[1][0].duplicate(true)
			check(not Grants.catch_up(st,1) and st.heroes[1][0] == expected, branch+": reconnect does not repeat grant")
			st.create_party("FSusel"); st.add_party_unit("FSusel","Hero","Hero2"); st.set_current_party("FSusel")
			check(not Grants.catch_up(st,1),branch+": next chapter keeps grant receipt")
			check(st.save("user://chapter-"+branch+".sav") == OK,branch+": chapter save")
			var loaded := CampaignState.load_from("user://chapter-"+branch+".sav")
			check(not Grants.catch_up(loaded,1) and loaded.heroes[1][0] == expected,branch+": saved receipt remains idempotent")
	else:
		var ps := fixture(); var st := ps.state
		st.create_party("HeroAlone"); st.add_party_unit("HeroAlone","Hero","Human Hero Hadagan"); st.set_current_party("HeroAlone")
		st.money = 111; st.items = ["host-bag-sentinel"]
		check(CoopProgress.main_hero(st) == st.parties[""][0], "base substitution still imports original Zak")
		# This purse-only fixture has no imported/active chapter context.
		ps.coop.joiners.guest = {"idx":1,"active":false,"purse":{"money":222,"items":["guest-bag-sentinel"]}}
		ps.coop.joiners.other = {"idx":2,"active":false,"purse":{"money":333,"items":["other-bag-sentinel"]}}
		var pvm := vm_for(ps,"bz13h")
		ps.coop.with_purse(1,func(): pvm.fire_event("#OnBriefingComplete",[0.0,"b.Nalo.Kr60"]))
		check(st.current_party == "Pretty" and st.money == 0 and st.items.is_empty(),"original Nalo handoff selects Nalo's bag")
		check(st.party_bags.HeroAlone == {"money":111,"items":["host-bag-sentinel"]},"waiting host bag retains its money and items")
		check(ps.coop.joiners.guest.purse == {"money":222,"items":["guest-bag-sentinel"]},"guest closing Nalo dialogue retains personal bag")
		ps.coop.with_purse(1,func():
			ps.coop.with_purse(0,func(): st.money += 10; st.items.append("host-reward"))
			ps.coop.with_purse(2,func(): st.money += 20; st.items.append("other-reward"))
			st.money += 30; st.items.append("guest-reward"))
		check(st.money == 10 and st.items == ["host-reward"],"nested host reward has correct owner")
		check(ps.coop.joiners.other.purse == {"money":353,"items":["other-bag-sentinel","other-reward"]},"nested third-player reward has correct owner")
		check(ps.coop.joiners.guest.purse == {"money":252,"items":["guest-bag-sentinel","guest-reward"]},"outer guest scope resumes its own bag")
		ps.coop.with_purse(1,func(): vm_call(pvm,"SetCurrentParty",[0.0,"HeroAlone"]))
		check(st.money == 111 and st.items == ["host-bag-sentinel"],"return restores waiting protagonist bag")
		check(st.party_bags.Pretty == {"money":10,"items":["host-reward"]},"Nalo's bag stays with Nalo")
		ps.coop.with_purse(1,func(): vm_call(pvm,"AddLoot",[0.0,"Pretty","HeroAlone"]))
		check(st.money == 121 and st.items == ["host-bag-sentinel","host-reward"],"authored AddLoot uses named campaign bags")
		check(ps.coop.joiners.guest.purse.money == 252,"campaign loot copy leaves guest purse intact")
		check(st.save("user://party-purses.sav") == OK,"party bags save")
		var loaded := CampaignState.load_from("user://party-purses.sav")
		check(loaded.current_party == st.current_party and loaded.money == st.money and loaded.items == st.items and loaded.party_bags == st.party_bags,"saved party bags reload without reassignment")
	var original_name: String = s.state.heroes[0][0].name
	var before_guest: Dictionary = s.state.heroes[1][0].duplicate(true)
	s.state.ensure_hero(1,"Human Hero","Alice")
	s._relink_heroes()
	check(s.state.heroes[1][0].name=="Alice" and guest.display_name=="Alice","rebound guest name updates live character preview")
	check(s.state.heroes[1][0].get("unit_name","")==before_guest.get("unit_name",before_guest.name),"renaming preserves the deployment identity")
	check(s.state.heroes[1][0].weapons==before_guest.weapons and s.state.heroes[1][0].skills==before_guest.skills,"renaming does not replace the guest character")
	s.state.ensure_hero(0,"Human Hero","Host Alias")
	check(s.state.heroes[0][0].name==original_name,"host lobby alias does not rename the story protagonist")
	check(s.state.save("user://renamed-party.sav")==OK,"renamed party saves")
	var renamed := CampaignState.load_from("user://renamed-party.sav")
	check(renamed.heroes[1][0].name=="Alice" and renamed.heroes[1][0].unit_name==s.state.heroes[1][0].unit_name,"guest display and deployment names survive save/load")
	for n in allocations:
		if n is GameWorld: n.units = {}
	for n in allocations: n.free()
	print("CAMPAIGN_ROSTER ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
