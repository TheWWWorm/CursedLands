extends Node
## Authored ancient-item enchantments, recharge, and inventory lifetime.
const HELMET_SPEC := "UniqueGipatHadagan Helm.Iron[eagle_sight{ic}]"
const SWORD_SPEC := "unique sword.steel[weak{it}]"
var checks := 0
var failures := 0
var s: Session
var w: GameWorld

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func actor(id: int, owner: int) -> GameUnit:
	var u := GameUnit.new()
	check(u.setup(w, {"prototype":"Human Hero", "nid":id, "player":0}), "original actor loads")
	u.controller = owner; u.mode = "player"
	w.add_child(u); w.set_unit(id,u)
	u.pos = Vector2(1 + id % 3, 1)
	return u

func step(n := 1) -> void:
	for i in n:
		w._advance(GameUnit.TICK)
		# Session physics must never add another equipment tick.
		s._tick_world_session(GameUnit.TICK)

func _ready() -> void:
	GameData.options.merge({"autosave":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	s = Session.new(); add_child(s); s.set_physics_process(false)
	w = GameWorld.new(); w.process_mode = Node.PROCESS_MODE_DISABLED
	w.session = s; s.world = w; add_child(w)
	w.zone = {"id":"equipment-test", "type":"game"}; s.zone_id = "equipment-test"
	s._exit_t = 1000000.0
	var hero := actor(900001,0)
	var target := actor(900002,2)
	s.state.ensure_hero(0,"Human Hero")
	var h: Dictionary = s.state.heroes[0][0]
	hero.set_meta("hero", h)
	h.armors = []; h.weapons = []; h.quick = []
	var helmet: String = Items.from_spec(HELMET_SPEC)[0]
	var sword: String = Items.from_spec(SWORD_SPEC)[0]
	var sense_cost := float(Spells.parse(Items.spell_of(helmet)).mana)
	check(Items.spell_of(helmet) == "eagle_sight{ic}", "ancient helmet carries Eagle Sight")
	check(Items.spell_of(sword) == "weak{it}", "ancient sword carries Weaken on hit")
	check(Items.parse_stack(HELMET_SPEC) == [helmet,1], "loot parser preserves helmet enchantment")
	check(Items.parse_stack(SWORD_SPEC) == [sword,1], "loot parser preserves sword enchantment")
	check(Items.parse_stack("material.iron [12]") == ["material.iron",12], "numeric loot stacks retain their count")
	check(Items.parse_stack("Spell Container [weak{it}]") == ["spell:weak{it}",1], "native spell containers remain containers")
	var worn := Items.with_charge(Items.with_wear(sword,2.5), 12.0)
	check(Items.parse_stack(worn) == [worn,1], "canonical loot keeps wear and charge")
	var corpse := actor(900003,-1)
	corpse.dead = true; corpse.set_meta("loot",[HELMET_SPEC,SWORD_SPEC])
	s.take_loot(hero,corpse)
	check(s.state.items.has(helmet) and s.state.items.has(sword), "actual corpse pickup keeps both enchantments")
	s.state.items.clear()

	# The base campaign's authored helmet fits its energy capacity. LiA changes
	# spell costs; use its authored diamond Eagle Sight pants for that ruleset.
	var sensing := helmet if sense_cost < Items.energy(helmet) else \
		String(Items.from_spec("Jun High Pants.Diamond[eagle_sight{ic;d1;m2}]")[0])
	check(float(Spells.parse(Items.spell_of(sensing)).mana) < Items.energy(sensing), "campaign's authored sensing equipment can afford its spell")
	h.armors = [sensing]
	w.zone.type = "brief"
	h.weapons = [sword]
	w.combat.weapon_spell(hero,target)
	check(h.weapons[0] == sword and not target.buffs.has("weak"), "blocked village strikes do not consume weapon charge")
	h.weapons = []
	step(5)
	check(Items.spent(h.armors[0]) == 0.0 and hero.sense_bonus(0) == 0.0, "village does not spend charge on blocked automatic casts")
	w.zone.type = "game"
	step()
	check(hero.sense_bonus(0) > 0.0 and Items.spent(h.armors[0]) > 0.0, "entering the field activates the sight bonus")
	var duration := int(Spells.parse(Items.spell_of(sensing)).duration)
	step(duration + 5)
	check(hero.sense_bonus(0) > 0.0 and hero.effect_ticks("eagle_sight") > duration - 10, "sight effect renews after its first complete duration")
	h.armors = []

	# Exhaust the sword without advancing time, then wait for another strike.
	h.weapons = [sword]
	var cost := float(Spells.parse(Items.spell_of(sword)).mana)
	for i in int(Items.energy(sword) / cost): w.combat.weapon_spell(hero,target)
	check(target.buffs.has("weak") and target.max_hp < hero.max_hp, "ancient sword applies its actual combat effect")
	target.buffs = {}; target.refresh_max_hp()
	w.combat.weapon_spell(hero,target)
	check(not target.buffs.has("weak"), "empty sword cannot cast before it recharges")
	var before := Items.charge(h.weapons[0])
	step(10)
	check(absf(Items.charge(h.weapons[0]) - before - Items.energy(sword)*0.01) < 0.002, "ten logic ticks restore one percent of sword capacity")
	step(1000)
	check(is_equal_approx(Items.charge(h.weapons[0]),Items.energy(sword)), "depleted equipment refills to its capacity")
	target.buffs = {}; target.refresh_max_hp()
	w.combat.weapon_spell(hero,target)
	check(target.buffs.has("weak"), "sword enchantment works again after recharge")

	# Recharge follows each copy through worn gear, spare weapons, belts and bags.
	h.weapons = [worn,worn]
	h.armors = [Items.with_charge(helmet,0)]
	h.quick = [Items.with_charge("wand 6.rock|weak{t2;fe}",0)]
	s.state.items = [worn,worn]
	var guest := actor(900004,1)
	s.state.ensure_hero(1,"Human Hero")
	var gh: Dictionary = s.state.heroes[1][0]
	gh.weapons = [worn]; gh.armors = []; gh.quick = []
	guest.set_meta("hero",gh)
	s.coop.joiners.test = {"idx":1,"purse":{"money":0,"items":[worn,worn]}}
	# A second guest shares the campaign bag; it must not get a second tick.
	var shared := actor(900005,3)
	shared.set_meta("hero", {"weapons":[],"armors":[],"quick":[]})
	w.zone.type = "brief"
	step(10)
	var expected := 12.0 + Items.energy(sword)*0.01
	for list: Array in [h.weapons,s.state.items,gh.weapons,s.coop.joiners.test.purse.items]:
		check(list.all(func(it):return absf(Items.charge(it)-expected)<0.002 and Items.wear(it)==2.5), "independent item copies recharge once and retain wear")
	check(absf(Items.charge(h.armors[0])-Items.energy(helmet)*0.01)<0.002, "depleted helmet recovers in camp")
	check(absf(Items.charge(h.quick[0])-Items.energy(h.quick[0])*0.01)<0.002, "belt wand follows the same original recharge rate")
	var saved_items: Array = h.weapons.duplicate()
	var frozen := String(h.weapons[0])
	w._advance(GameUnit.TICK*0.5)
	check(h.weapons[0] == frozen, "partial simulation tick does not recharge")
	w._advance(GameUnit.TICK*0.5)
	check(Items.charge(h.weapons[0]) > Items.charge(frozen), "completed simulation tick recharges without session physics")
	frozen = h.weapons[0]
	s._tick_world_session(1.0)
	check(h.weapons[0] == frozen, "network/session processing alone cannot recharge or cast")
	var charge_before := Items.charge(h.weapons[0])
	w._advance(GameUnit.TICK*2)
	check(absf(Items.charge(h.weapons[0])-charge_before-Items.energy(sword)*0.002)<0.002, "double simulation speed gives exactly two recharge steps")
	w.authority = false
	frozen = h.weapons[0]
	w._deliver(GameUnit.TICK*2)
	check(h.weapons[0] == frozen, "client world never advances authoritative charge")
	w.authority = true
	check(s.state.save("user://equipment.sav") == OK, "recharging equipment saves")
	var restored := CampaignState.load_from("user://equipment.sav")
	check(restored != null and restored.heroes[0][0].weapons == h.weapons, "save/reload preserves partially restored charges")
	h.weapons = restored.heroes[0][0].weapons if restored else saved_items
	frozen = h.weapons[0]
	step()
	check(Items.charge(h.weapons[0]) > Items.charge(frozen), "recharge resumes from saved charge")
	w.free(); s.free()
	print("ENCHANTED_EQUIPMENT ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
