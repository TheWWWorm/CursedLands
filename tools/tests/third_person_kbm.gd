extends Node
## Prepared native-model/input regression. No physical route or ENet claim.
var s: Session
var g: Game
var hero: GameUnit
var checks := 0
var failures := []
var evidence := {"cases":[],"assertions":[],"scope":"Injected keyboard/mouse input in loaded original campaign and original multiplayer worlds, prepared spell/loot cases; no ENet, full route, Windows or rendered acceptance."}
var mode := ""
func check(ok: bool,label: String) -> void:
	checks += 1;label=mode+": "+label;evidence.assertions.append({"label":label,"ok":ok})
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func frames(n := 4) -> void:
	for i in n: await get_tree().process_frame
func key(code: Key,echo := false) -> void:
	var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=true;e.echo=echo
	Input.parse_input_event(e);await frames(1)
	e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;Input.parse_input_event(e);await frames(1)
func click() -> void:
	var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true;e.position=get_viewport().get_visible_rect().size*0.5
	Input.parse_input_event(e);await frames(1);e=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(e);await frames(1)
func reset() -> void:
	hero.order={};hero.orders.clear();hero.path=PackedVector2Array();hero._anim_lock=0;hero._pending_hit={};hero._attack_cd=0;hero.blocked=false
	if hero.has_meta("interact"): hero.remove_meta("interact")
	g.pending_spell="";g.hud.set_targeting("");g.direct._fire=false;g.direct._neutral=false;g.direct.pointer=false
func sky() -> void:
	g.direct.tilt=0.7;g.direct.apply_camera();g._pick_key=[]
func aim(u:GameUnit) -> void:
	var cam:=g.rig.camera
	cam.look_at(u.global_position+Vector3.UP*maxf(0.2,u.figure_half_z),Vector3.UP)
	cam.reset_physics_interpolation();g._pick_key=[];await frames(2)
	# Aim at an actual native posed part, not the standing-height estimate of
	# a corpse whose authored death pose can extend sideways.
	for attempt in 5:
		if g._pick_unit(get_viewport().get_visible_rect().size*0.5,hero)==u:return
		var parts:=u.screen_rects(cam)
		var chosen:=Vector2.INF
		for rect:Rect2i in parts.slice(1):
			var at:=Vector2(rect.position)+Vector2(rect.size)*0.5
			if g._pick_unit(at,hero)==u:chosen=at;break
		if chosen==Vector2.INF:return
		cam.look_at(cam.global_position+cam.project_ray_normal(chosen)*10,Vector3.UP)
		cam.reset_physics_interpolation();g._pick_key=[];await frames(2)
func order_target(t: GameUnit) -> bool:
	return hero.orders.size()==1 and hero.orders[0].get("target")==t
func prepare() -> void:
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	hero=s.party_units(0)[0];hero.blocked=false;g.selected.assign([hero]);g.rig.release()
	var h:Dictionary=hero.get_meta("hero");h.skills={"astral":100,"fire":100};h.spells=["healing{}","arrow{}","healing{e1;e1}"];h.int=25.0
	Combat.hero_stats(hero,h);hero.mana=hero.max_mana
	await frames(8);g.rig.set_process(false);g.direct.set_process(false);reset();sky()
	if DisplayServer.get_name()=="headless":g.direct._captured=true # exercise the real captured-click input handler without OS capture
	check(g.direct.usable(),"loaded scene accepts third-person keyboard input")
func body(at:Vector2,uid:=0,fallen:=true) -> GameUnit:
	var rec:=hero.info.duplicate(true);rec.nid=uid;rec.position=Vector3(at.x,at.y,0);rec.erase("controller");rec.name="Loot test body"
	var u:=s.world.spawn_unit(rec);u.controller=-1
	if fallen:u.lie_dead()
	u._sync_transform(0);u.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF;u.reset_physics_interpolation();u.visible=true;u.fogged=false;u.hidden=false
	u.set_process(false);u.set_physics_process(false) # fixed authored pose for exact crosshair controls
	u.set_meta("loot",["money[7]"]);return u
func free_point(distance:=1.5,angle_offset:=0.0) -> Vector2:
	for i in 16:
		var p:=hero.pos+Vector2.from_angle(angle_offset+float(i)*TAU/16)*distance
		if s.world.nav.cell_open(p,hero._classes[2]) and DirectCombat.scene_fraction(s.world,DirectCombat.origin(hero),Vector3(p.x,s.world.ground_at(p.x,p.y)+0.3,-p.y))==1.0:return p
	return hero.pos
func spell_cases() -> void:
	reset();sky();await key(KEY_1)
	check(g.pending_spell=="healing{}","spell hotkey selects native heal")
	check(g.pick_unit(get_viewport().get_visible_rect().size*0.5,hero)==null,"sky-facing crosshair has no target")
	check(g.direct.has_method("interaction_hint") and str(g.direct.call("interaction_hint").get("text","")).contains(RemakeText.t("Cast on self")),"self action is named in the reticle prompt")
	await key(KEY_E)
	check(order_target(hero) and hero.orders[0].get("type")=="cast","E queues a self-cast through authority without aiming at a portrait")
	check(g.pending_spell.is_empty() and g.selected==[hero],"successful self-cast ends targeting and keeps selection")
	var mana:=hero.mana
	for i in 4: hero._tick(GameUnit.TICK)
	check(hero.mana<mana,"queued self-cast reaches native execution and pays stamina")
	reset();hero.mana=hero.max_mana;g.pending_spell="arrow{}";await key(KEY_E)
	check(hero.orders.is_empty() and g.pending_spell=="arrow{}","E never self-casts an offensive spell")
	reset();hero.mana=0;g.pending_spell="healing{}";await key(KEY_E)
	check(hero.orders.is_empty() and g.pending_spell=="healing{}","insufficient stamina keeps pending spell without a cast")
	reset();hero.mana=hero.max_mana;hero.buffs["fixture_no_cast"]={"no_cast":true};g.pending_spell="healing{}";await key(KEY_E)
	check(hero.orders.is_empty(),"cannot-cast effect prevents self-cast");hero.buffs.erase("fixture_no_cast")
	reset();hero.get_meta("hero").skills.astral=0;g.pending_spell="healing{e1;e1}";await key(KEY_E)
	check(hero.orders.is_empty(),"lost training prevents self-cast");hero.get_meta("hero").skills.astral=100
	for guard in ["pointer","loading","focus","pause","blocked","echo","neutral","panel"]:
		reset();g.pending_spell="healing{}"
		match guard:
			"pointer":g.direct.pointer=true
			"loading":s.loading_game=true
			"focus":g.rig._window_focused=false
			"pause":get_tree().paused=true
			"blocked":hero.blocked=true
			"neutral":g.direct._neutral=true
			"panel":g.hud._inventory.visible=true
		await key(KEY_E,guard=="echo")
		check(hero.orders.is_empty(),guard+" input cannot consume selected self spell")
		s.loading_game=false;g.rig._window_focused=true;get_tree().paused=false;g.hud._inventory.visible=false
	reset();hero.mana=hero.max_mana
	var ally:=body(free_point(2.2),0,false);ally.controller=1;ally._sync_transform(0);ally.visible=true;ally.fogged=false
	await aim(ally);await frames(2);await key(KEY_1)
	check(g.pick_unit(get_viewport().get_visible_rect().size*0.5,hero)==ally,"actual crosshair picks prepared ally native silhouette")
	await click();check(order_target(ally),"left click still casts selected heal on aimed ally")
	check(g.selected==[hero],"ally targeting retains owned caster")
	s.world.remove_unit(ally);reset();sky()
func belt_cases() -> void:
	var potion:="";var wand:=""
	for row:Dictionary in GameData.db.table("quick_items"):
		var name:=String(row.get("name","")).to_lower()
		var sp:=Items.potion_spell(name)
		if potion.is_empty() and int(row.get("item_id",0))==8 and not sp.is_empty() and not Spells.offensive(sp) and not Spells.parse(sp).point:potion=name
		var item:=name+".rock|healing{}"
		if wand.is_empty() and Items.is_wand(item) and Items.energy(item)>=float(Spells.parse("healing{}").mana):wand=item
	check(not potion.is_empty() and not wand.is_empty(),"original item database supplies a friendly potion and charged wand")
	if potion.is_empty() or wand.is_empty():return
	var h:Dictionary=hero.get_meta("hero")
	for item:String in [potion,wand]:
		reset();h.quick=[item];g.begin_belt(hero,item);await key(KEY_E)
		check(order_target(hero) and hero.orders[0].get("item","")==item,"E targets selected belt item at its holder: "+item)
		var old_charge:=Items.charge(item)
		for i in 4:hero._tick(GameUnit.TICK)
		check(h.quick.is_empty() if item==potion else not h.quick.is_empty() and Items.charge(String(h.quick[0]))<old_charge,"item execution consumes potion/charge through normal native rule: "+item)
	reset();h.quick=[Items.with_charge(wand,0)];g.pending_spell=Game.BELT+str(hero.uid)+":"+wand;await key(KEY_E)
	check(hero.orders.is_empty() and not g.pending_spell.is_empty(),"spent wand cannot self-cast")
	reset();h.quick=[];g.pending_spell=Game.BELT+str(hero.uid)+":"+potion;await key(KEY_E)
	check(hero.orders.is_empty() and not g.pending_spell.is_empty(),"missing belt item cannot self-cast")
	reset()
func loot_cases() -> void:
	var original:=hero.pos;var p:=free_point();check(p!=hero.pos,"nearby body has a clear original navigation location")
	var loot:=body(p);evidence.cases.append({"mode":mode,"zone":s.zone_id,"hero":[hero.pos.x,hero.pos.y],"loot":[p.x,p.y],"model":loot.model.template,"distance":p.distance_to(hero.pos)})
	reset();sky();check(g.pick_unit(get_viewport().get_visible_rect().size*0.5,hero)==null,"body near feet is outside exact sky-facing crosshair")
	await key(KEY_E)
	check(hero.has_meta("interact") and hero.get_meta("interact")[0]==loot,"E posts ordinary loot approach despite missing exact silhouette")
	check(g.direct.has_method("interaction_hint") and str(g.direct.call("interaction_hint").get("text","")).contains(RemakeText.t("Loot")),"nearby loot action has a visible named prompt")
	var cash:=s.state.money
	for i in 250:
		hero._tick(GameUnit.TICK);s.world.vm._check_interactions()
		if not s.world.units.has(loot.uid):break
	check(not s.world.units.has(loot.uid) and s.state.money==cash+7,"ordinary approach/use animation collects loot once")
	await key(KEY_E);check(s.state.money<=cash+7,"repeating E cannot duplicate collected loot")
	reset();hero.pos=original;hero._sync_transform(0);sky()
	if s.world.units.has(loot.uid):s.world.remove_unit(loot)
	loot=body(p)
	for guard in ["hidden","fogged","invisible","looted","distant","foreign_body"]:
		reset();sky();loot.pos=p;loot.hidden=false;loot.fogged=false;loot.visible=true
		match guard:
			"hidden":loot.hidden=true
			"fogged":loot.fogged=true
			"invisible":loot.visible=false
			"looted":loot.set_meta("looted",true)
			"distant":loot.pos=hero.pos+(p-hero.pos).normalized()*6.0
			"foreign_body":loot.set_meta("lmp_owner",1);loot.set_meta("lmp_conn",23)
		loot._sync_transform(0);await key(KEY_E)
		check(not hero.has_meta("interact"),guard+" body is not selected by proximity")
		if loot.has_meta("looted"):loot.remove_meta("looted")
		if loot.has_meta("lmp_owner"):loot.remove_meta("lmp_owner");loot.remove_meta("lmp_conn")
	reset();loot.pos=p;loot.hidden=false;loot.fogged=false;loot.visible=true;loot._sync_transform(0);sky()
	# A controlled solid span uses the same native navigation query as walls.
	var mid:=hero.pos.lerp(p,0.5);var cell:=s.world.nav.cell(mid);var ci:=cell.y*s.world.nav.size.x+cell.x
	var had:=s.world.nav._spans.has(ci);var spans:Variant=s.world.nav._spans.get(ci)
	s.world.nav._spans[ci]=[[0.0,65535.0,0,-123]]
	await key(KEY_E);check(not hero.has_meta("interact"),"nearby loot behind solid native-navigation span is refused")
	if had:s.world.nav._spans[ci]=spans
	else:s.world.nav._spans.erase(ci)
	reset();loot.set_meta("lmp_owner",0);loot.set_meta("lmp_conn",1);await key(KEY_E)
	check(hero.has_meta("interact") and hero.get_meta("interact")[0]==loot,"own original-multiplayer body remains eligible")
	reset();loot.remove_meta("lmp_owner");loot.remove_meta("lmp_conn")
	var explicit:=body(free_point(2.5,PI*0.5));await aim(explicit);await frames(2)
	check(g.pick_unit(get_viewport().get_visible_rect().size*0.5,hero)==explicit,"crosshair deliberately selects farther body")
	await key(KEY_E)
	check(hero.has_meta("interact") and hero.get_meta("interact")[0]==explicit,"explicit crosshair target precedes nearer loot")
	reset();s.world.remove_unit(explicit);s.world.remove_unit(loot);sky()
func safe_zone() -> void:
	reset();g.pending_spell="healing{}";await key(KEY_E)
	check(hero.orders.is_empty() and g.pending_spell=="healing{}","safe zone refuses already-selected self spell")
	g.pending_spell="";await key(KEY_1);check(g.pending_spell.is_empty(),"safe zone refuses spell selection")
func _ready() -> void:
	get_window().size=Vector2i(800,600)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":2,"pad_enabled":0,"blood":0},true)
	PadInput.active="kbm";s=Session.new();add_child(s);g=Game.new();g.session=s;s.game=g;add_child(g)
	s.state=CampaignState.new();s.state.ensure_hero(0,"Human Hero")
	mode="campaign";await s.enter_zone("gz1g",1,false);await prepare();await spell_cases();await belt_cases();await loot_cases()
	await s.enter_zone("bz1g",1,false);await prepare();await safe_zone()
	GameData.use_lmp_database(true)
	var faces:=MpCharacter.faces();var c:=MpCharacter.create(String(faces[0][0]));MpCharacter.finish(c,"","","")
	MpCharacter.save_file("1.mp",c);MpCharacter.select("1.mp")
	mode="original multiplayer Ingos";check(s.new_lmp_game("bz2mpg"),"new native multiplayer game loads selected character")
	await prepare();await safe_zone()
	var quest:=String(LmpMode.quests_of(s.campaign,"bz2mpg")[0]);SideQuests.take_lmp(s,quest);s.submit({"t":"travel","zone":quest,"entrance":1})
	while s.zone_id!=quest or s.loading_game or s.party_units(0).is_empty():await get_tree().process_frame
	await prepare();await spell_cases();await belt_cases();await loot_cases()
	evidence.checks=checks;evidence.failures=failures
	FileAccess.open("user://third-person-kbm.json",FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"))
	g.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
	print("THIRD_PERSON_KBM ",checks," checks ",failures.size()," failures");get_tree().quit(0 if failures.is_empty() else 1)
