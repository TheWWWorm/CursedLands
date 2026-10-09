extends Node
## Server receipt validation and bounded opening admission; the sibling
## fixture exercises real menu/ENet traffic against both original campaigns.
class QuietSession extends Session:
	func _ready() -> void: pass
	func broadcast(_event: Dictionary) -> void: pass
class QuietProgress extends CoopProgress:
	func send_all() -> void: pass
var s: Session
var checks:=0
var failures:=0

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func payload() -> Dictionary:
	var st:=CoopProgress.fresh_state()
	return {"campaign_id":st.campaign_id,"hero":CoopProgress.main_hero(st),"vars":{},"visited":["gz1g"],
		"side_quests":{},"quest_items":{},"zone":"gz1g","seq":{},"money":0,"items":[],
		"party_context":CoopProgress.PartyProgress.capture(st),"new_origin":true}

func reset_host() -> void:
	s.state=CoopProgress.fresh_state(); s.zone_id="gz1g"
	s.coop._loading=false; s.coop.joiners={}; s.coop._pending={}
	if GameData.campaign_id==CampaignProfile.ORIGINAL:
		for key: String in CoopProgress.OPENING_VARS:s.state.set_var(0,key,1.0)

func rejected_source(kind: String) -> void:
	reset_host()
	var data:=payload()
	match kind:
		"saved origin":data.new_origin=false
		"missing opt-in":data.erase("new_origin")
		"numeric opt-in":data.new_origin=1
		"wrong campaign":data.campaign_id="wrong"
		"earned hero":data.hero.str+=1; data.party_context.roster[0].str+=1
		"private earned hero":data.party_context.roster[0].exp=1.0
		"spent health":data.hero.hp=12.0
		"purse":data.money=1
		"inventory":data.items=["rune:e1"]
		"private inventory":data.party_context.items=["rune:e1"]
		"known quest":data.vars["q.gz1g.progress"]=1.0
		"unknown flag":data.vars.story=1.0
		"visited map":data.visited.append("gz2g")
		"current zone":data.zone="gz2g"
		"acknowledged save":data.seq={"old-tally":1}
		"side quest":data.side_quests.fixture="active"
		"quest item":data.quest_items.fixture=true
		"private party":data.party_context.parties.older=[data.hero.duplicate(true)]
		"private bag":data.party_context.party_bags.older={"money":1,"items":[]}
		"private hire":data.party_context.mercs[1]=data.hero.duplicate(true)
		"private pet":data.party_context.pets=[{"rec":{}}]
		"extra state":data.history={"done":true}
	check(not CoopProgress._pristine_new_origin(data),kind+" cannot validate as a pristine NEW origin")
	# Invoke the actual RPC receiver on its tree-bound multiplayer API;
	# sender0 is local here. No test injects a trusted pending NEW marker.
	s.coop._rpc_bring(data)
	check(not bool(s.coop._pending.get(0,{}).get("new_origin",false)),kind+" cannot acquire trusted NEW admission at the receiver")

func rejected_host(kind: String) -> void:
	reset_host()
	match kind:
		"different live zone":s.zone_id="gz2g"
		"different saved zone":s.state.current_zone="gz2g"
		"named chapter":s.state.current_party="FPrison"
		"alternate body":s.state.heroes[0][0].prototype="Hero1"
		"alternate identity":s.state.heroes[0][0].unit_name="AnotherHero"
		"other visited zone":s.state.visited.gz2g=true
		"other saved zone":s.state.zones.gz2g={}
		"waiting party":s.state.parties.old=[]
		"waiting bag":s.state.party_bags.old={"items":[],"money":0}
		"hired companion":s.state.mercs[1]={}
		"pet":s.state.pets=[{}]
		"quest journal":s.state.quests.fixture=2
		"advanced quest":s.state.set_var(0,"q.gz1g.fixture",1.0)
		"completed quest":s.state.set_var(0,"q.gz1g.fixture",2.0)
		"quest item":s.state.quest_items.fixture=true
		"side quest":s.state.side_quests.fixture="active"
		"unknown flag":s.state.set_var(0,"unverified_startup",1.0)
		"later startup value":s.state.set_var(0,"ZT1",2.0)
		"loading":s.coop._loading=true
	var e:={"vars":{},"credits":{"vars":{}}}
	check(not s.coop._admit_new_origin(e,{"new_origin":true}) and e.vars.is_empty() and e.credits.vars.is_empty(),kind+" cannot use opening admission or receive its vars")

func _ready() -> void:
	s=QuietSession.new(); add_child(s); s.online=true
	s.world=GameWorld.new(); s.world.session=s
	s.coop=QuietProgress.new(); s.coop.session=s; s.add_child(s.coop)
	reset_host()
	var data:=payload()
	check(CoopProgress._pristine_new_origin(data),"actual campaign fresh origin validates")
	data.hero.name="Other locale"; data.party_context.roster[0].name="Другое имя"
	check(CoopProgress._pristine_new_origin(data),"only display names may differ by locale")
	s.coop._rpc_bring(data)
	check(s.coop._pending[0].new_origin,"server receipt validates the explicit menu NEW source")
	var original_hero: Dictionary=s.coop._pending[0].hero.duplicate(true)
	var original_purse: Dictionary=s.coop._pending[0].purse.duplicate(true)
	s.coop.on_hello(0,1,"Guest")
	var e: Dictionary=s.coop.joiners.guest
	check(e.clean and e.present and e.in_sync,"validated pristine origin admits an untouched authored opening")
	original_hero.name="Guest"
	check(e.hero_in==original_hero and e.purse==original_purse,"admission retains the new source hero and purse")
	if GameData.campaign_id==CampaignProfile.ORIGINAL:
		check(e.vars.size()==6 and e.credits.vars==e.vars,"all six original startup flags receive explicit old-value credit")
		s.state.set_var(0,"Said1",2.0)
		check(e.vars.Said1==2.0 and e.clean,"subsequent exact old-value change remains credited")
	else:
		check(e.vars.is_empty(),"LiA opening needs no invented startup flags")
	# A new-origin opt-in never replaces an existing reserved participant.
	e.active=false; e.seq=3; e.sid="existing-personal-tally"
	s.state.heroes[1][0].str=41.0; e.purse={"money":222,"items":["rune:e1"]}
	s.coop._rpc_bring(payload()); s.coop.on_hello(0,1,"Guest")
	check(s.state.heroes[1][0].str==41.0 and e.purse=={"money":222,"items":["rune:e1"]},"NEW cannot replace an existing reserved personal hero or purse")
	check(not e.clean and not e.present,"NEW without acknowledgement cannot admit an existing tally")
	for kind: String in ["saved origin","missing opt-in","numeric opt-in","wrong campaign","earned hero","private earned hero","spent health","purse","inventory","private inventory","known quest","unknown flag","visited map","current zone","acknowledged save","side quest","quest item","private party","private bag","private hire","private pet","extra state"]:
		rejected_source(kind)
	for kind: String in ["different live zone","different saved zone","named chapter","alternate body","alternate identity","other visited zone","other saved zone","waiting party","waiting bag","hired companion","pet","quest journal","advanced quest","completed quest","quest item","side quest","unknown flag","later startup value","loading"]:
		rejected_host(kind)
	s.world.free();s.world=null;s.free()
	print("COOP_FRESH_START_GUARDS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
