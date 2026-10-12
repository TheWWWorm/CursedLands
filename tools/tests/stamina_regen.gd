extends Node
## Optional party recovery, including authoritative rules and save persistence.
var checks := 0
var failures := 0
var u: GameUnit
var s: Session

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func recover() -> void:
	u._regen_t = 0.0
	for i in 15: u._regenerate(GameUnit.TICK)

func _ready() -> void:
	GameData.options.stamina_regen = 1
	s = Session.new()
	var w := GameWorld.new()
	s.world = w; w.session = s
	s.state = CampaignState.new()
	s.mod_config = ModStore.snapshot()
	s.mod_config.rules.stamina_regen = 0
	ModStore.attach(s)
	u = GameUnit.new(); u.world = w; u.controller = 0; u.uid = 123
	u.set_meta("hero", {})
	u.max_hp = 100.0; u.max_mana = 100.0
	u.stats = {"regen_hp":100.0, "regen_mana":0.0}
	u.race = {"health_regen":0.02, "mana_regen":0.005}
	u.hp = 50.0; u.mana = 50.0; u.order = {"type":"direct_move"}
	recover()
	check(is_equal_approx(u.hp,54.0) and u.mana==50.0,"off keeps normal HP recovery and no movement stamina recovery")
	check(not u.always_regenerate_stamina(),"host rule overrides local preference")
	u.order = {}; u.direct_steering={"direction":Vector2.RIGHT};recover()
	check(u.mana==50.0,"independent direct steering retains active stamina rules")
	u.direct_steering.clear();recover()
	check(is_equal_approx(u.mana,50.5),"off retains normal idle stamina rate")
	s.mod_config.rules.stamina_regen = 1
	for action in ["direct_move","move","attack","cast"]:
		u.hp=50.0;u.mana=50.0;u.order={"type":action}
		recover()
		check(is_equal_approx(u.mana,54.0) and is_equal_approx(u.hp,54.0),"on recovers exactly HP amount during "+action)
	u.hp=100.0;u.mana=50.0;recover()
	check(is_equal_approx(u.mana,54.0),"full health does not remove the stamina rate")
	u.buffs={"regeneration":{"regen_mul":2.0}};u.mana=50.0;recover()
	check(is_equal_approx(u.mana,58.0),"health regeneration buffs also raise the stamina rate")
	u.buffs={};u.race.mana_regen=0.1;u.mana=50.0;recover()
	check(is_equal_approx(u.mana,54.0),"higher native stamina rate does not accelerate continuous recovery")
	u.order={};u.mana=50.0;recover()
	check(is_equal_approx(u.mana,60.0),"standing idle retains faster native stamina recovery")
	u.order={"type":"attack"}
	u.mana=99.0;recover()
	check(u.mana==100.0,"recovery cannot exceed maximum stamina")
	u.race.mana_regen=0.005;u.controller=-1;u.mana=50.0;recover()
	check(u.mana==50.0,"party rule does not alter hostile NPC recovery")
	u.controller=0;u.dead=true;u.hp=0.0;u.mana=50.0;recover()
	check(u.hp==0.0 and u.mana==50.0,"dead units cannot regenerate")
	u.dead=false
	s.mod_config.rules.erase("stamina_regen")
	check(ModStore.configuration_error(s.mod_config).is_empty() and not u.always_regenerate_stamina(),"older saved rule sets load with the new option off")
	check(ModStore.new_game_defaults().rules.stamina_regen==0,"new games keep optional recovery off by default")
	s.mod_config.rules["stamina_regen"]=1
	s.state.mod_config=s.mod_config.duplicate(true)
	check(s.state.save("user://stamina-rule.sav")==OK,"save accepts the stamina rule")
	var saved:=CampaignState.load_from("user://stamina-rule.sav")
	if saved==null:
		var data:Variant=CampaignState.read_data("user://stamina-rule.sav")
		print("SAVE_DIAGNOSTIC ",CampaignState.compatible_data(data)," ",ModStore.saved_error(data.get("mod_config",{})))
	check(saved!=null and saved.mod_config.rules.stamina_regen==1,"load preserves the stamina rule")
	var lang:=RemakeText.lang
	for locale in ["ru","de"]:
		RemakeText.lang=locale
		check(RemakeText.t("Always regenerate stamina")!="Always regenerate stamina",locale+" translates the rule")
		var tip:String=GameData.REMAKE_OPTIONS.stamina_regen[1]
		check(RemakeText.t(tip)!=tip,locale+" translates its explanation")
	RemakeText.lang=lang
	s.mod_config.rules.stamina_regen=0;u.mana=50.0;u.order={"type":"attack"};recover()
	check(u.mana==50.0,"disabling the option restores the idle restriction")
	ModStore.detach(s);u.free();w.free();s.free()
	print("STAMINA_REGEN ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
