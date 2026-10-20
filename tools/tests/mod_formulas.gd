extends Node
## Public package, runtime, gameplay and save boundaries in a disposable profile.
var checks := 0
var failures := 0
var examples := ""
var serial := 0
const KEYS := ["example.quest-focus@1.0.0", "example.expedition-xp@1.0.0", "example.field-medicine@1.0.0"]

class ProbeSession extends Session:
	var events: Array = []
	func broadcast(event: Dictionary) -> void: events.append(event)
	func sync_state() -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func manifest() -> Dictionary:
	var m: Dictionary = ModStore.catalog["example.expedition-xp@1.0.0"].duplicate(true)
	m.erase("_root"); m.erase("_digest")
	return m

func fixture(source: String) -> String:
	serial += 1
	var m := manifest()
	m.id = "test.formula-" + str(serial)
	var path := "user://formula-fixture.eimod"
	var zip := ZIPPacker.new()
	zip.open(path)
	for name in ["mod.json", "main.lua"]:
		zip.start_file(name)
		zip.write_file((JSON.stringify(m) if name == "mod.json" else source).to_utf8_buffer())
		zip.close_file()
	zip.close()
	check(ModStore.import_package(path) == "", "import fixture " + str(serial))
	return m.id + "@" + m.version

func mount(keys: Array) -> String:
	var error := ModStore.set_packages(keys)
	return error if error != "" else ModStore.mount()

func probe() -> ProbeSession:
	var s := ProbeSession.new()
	s.state = CampaignState.new()
	s.mod_config = ModStore.snapshot()
	s.state.mod_config = s.mod_config.duplicate(true)
	s.world = GameWorld.new(); s.world.session = s
	s.local_host = LocalHost.new(); s.local_host.session = s
	var u := GameUnit.new(); u.world = s.world; u.uid = 1; u.controller = 0
	var record := {"exp":0.0, "exp_total":0.0, "exp_debt":0.0, "str":25.0, "dex":25.0, "int":25.0, "perks":[]}
	u.set_meta("hero", record)
	s.state.heroes[0] = [record]
	s.world.set_unit(1, u)
	return s

func dispose(s: Session) -> void:
	for u: GameUnit in s.world.unit_rows(): u.free()
	s.world.units = {}; s.world.free(); s.local_host.free(); s.free()

func reward(s: Session, source := "quest") -> float:
	var record: Dictionary = s.state.heroes[0][0]
	var before := float(record.exp_total)
	XpRules.give(s, 100.0, source)
	return float(record.exp_total) - before

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--examples="): examples = arg.trim_prefix("--examples=")
	check(not ClassDB.class_exists("ModLuaKernel"), "vanilla boot does not load the native formula library")
	var vanilla := probe()
	check(is_equal_approx(reward(vanilla), 100.0), "ordinary reward unchanged")
	check(not ClassDB.class_exists("ModLuaKernel") and ModFormula.invocations == 0, "ordinary reward creates no Lua VM")
	check(not vanilla.state.to_dict().has("mod_script_failed"), "runtime failure guard adds no save field")
	check(vanilla.state.save("user://ordinary.sav") == OK, "ordinary save writes")
	var vanilla_hash := FileAccess.get_sha256("user://ordinary.sav")
	dispose(vanilla)
	for name in ["expedition-xp", "quest-focus", "field-medicine"]:
		check(ModStore.import_package(examples.path_join(name + "-1.0.0.eimod")) == "", "import example " + name)
	var m := manifest()
	for language in ["en", "ru", "de"]:
		RemakeText.lang = language
		check(not ModSchema.text(m, "title").is_empty(), "localized title " + language)
		var bad := m.duplicate(true)
		bad.translations.de.options.clear()
		check(ModSchema.manifest_error(bad) != "", "missing dynamic translations refused " + language)
	RemakeText.lang = "en"
	var bad := m.duplicate(true); bad.script.modules.main = "../outside.lua"
	check(ModSchema.manifest_error(bad) != "", "module traversal rejected")
	bad = m.duplicate(true); bad.script.hooks = ["execute_arbitrary"]
	check(ModSchema.manifest_error(bad) != "", "undeclared engine capability rejected")
	bad = m.duplicate(true); bad.api = 2
	check(ModSchema.manifest_error(bad) != "", "API 2 cannot silently enable scripts")
	bad = m.duplicate(true); bad.modes = ["original_multiplayer"]
	check(ModSchema.manifest_error(bad) != "", "formula mods cannot enter original multiplayer")
	check(ModStore.create_profile("Formula examples") == "", "create separate mod profile")
	check(mount(KEYS) == "", "all examples mount together")
	check(ModStore._mounted[0] == "example.expedition-xp@1.0.0", "after dependency overrides reversed selection")
	check(ClassDB.class_exists("ModLuaKernel"), "native library loads on formula activation")
	for language in ["en", "ru", "de"]:
		RemakeText.lang = language
		var options := ModStore.option_definitions()
		check(options.size() == 3, "three configurable examples " + language)
		if language != "en":
			for option in options:
				check(option.label != m.options[0].label and not option.help.is_empty(), "localized option " + option.key)
	RemakeText.lang = "en"
	var s := probe()
	check(is_equal_approx(reward(s), 187.5), "quest chain runs before distribution and intelligence")
	check(is_equal_approx(reward(s, "kill"), 150.0), "quest module leaves combat reward alone")
	s.mod_config.values["example.expedition-xp:multiplier"] = 2.0
	check(is_equal_approx(reward(s), 250.0), "formula uses effective run options")
	var context := {"helper_intelligence":50.0, "target_max_health":100.0}
	var result := ModFormula.transform("revival_seconds", 5.0, context, s)
	check(result.ok and is_equal_approx(result.value, 2.5), "helper intelligence scales revival duration")
	result = ModFormula.transform("revival_health", 1.0, context, s)
	check(result.ok and result.value == 25.0, "field medicine health formula")
	var u: GameUnit = s.world.units[1]
	u.dead = true
	s.mod_config.rules.revive = 1
	GameData.options.revive = 1
	var helper := GameUnit.new(); helper.world = s.world; helper.controller = 0
	helper.set_meta("hero", {"int":50.0})
	Revive.begin(s, helper, u)
	check(helper.orders.any(func(order): return order.get("hold") == 2.5), "actual revival order receives formula duration")
	helper.free()
	Revive.finish(s, u)
	check(not u.dead and is_equal_approx(u.hp, maxf(1.0, floorf(u.max_hp * 0.25))), "actual revival applies formula after pool refresh")
	s.state.mod_config = s.mod_config.duplicate(true)
	check(s.state.save(SaveInfo.path("formulas")) == OK, "modded save writes")
	var loaded := CampaignState.load_from(SaveInfo.path("formulas"))
	check(loaded != null and loaded.mod_config.values["example.expedition-xp:multiplier"] == 2.0, "save preserves effective script options")
	if loaded == null: dispose(s); get_tree().quit(1); return
	s.mod_config = loaded.mod_config
	check(is_equal_approx(reward(s), 250.0), "restored run repeats formula result")
	var changed := s.mod_config.duplicate(true)
	changed.packages[0].digest = "a".repeat(64)
	check(ModStore.configuration_error(changed) != "", "source fingerprint mismatch rejected")
	var calls := ModFormula.invocations
	s.is_host = false
	result = ModFormula.transform("experience_reward", 100.0, {}, s)
	check(result.ok and result.value == 100.0 and ModFormula.invocations == calls, "replica cannot execute gameplay formulas")
	dispose(s)
	var stateless := fixture("local count=0\nfunction experience_reward(v,c,o) count=count+1; c.source='mutated'; return v+count end")
	check(mount([stateless]) == "", "stateless fixture mounts")
	s = probe()
	for i in 3: check(is_equal_approx(reward(s), 101.0), "new VM resets globals and captured locals")
	dispose(s)
	var isolated := fixture("function experience_reward(v,c,o) assert(io==nil and os==nil and debug==nil and package==nil and loadfile==nil and dofile==nil and loadstring==nil and math.random==nil); return v end")
	check(mount([isolated]) == "", "capability fixture mounts")
	s = probe(); check(is_equal_approx(reward(s),100.0), "formula has no filesystem, process, native loader or clock"); dispose(s)
	var zero := fixture("function experience_reward(v,c,o) return 0 end")
	check(mount([zero]) == "", "zero reward fixture mounts")
	s = probe()
	var health_before: float = s.world.units[1].hp
	check(reward(s) == 0.0 and s.events.is_empty() and s.world.units[1].hp == health_before, "zero formula reward has no pool or notification side effects")
	dispose(s)
	var missing := fixture("function not_the_hook() return 1 end")
	check(mount([missing]) != "" and ModFormula._bundles.is_empty(), "missing function refuses activation atomically")
	var cyclic := fixture("require('main')")
	check(mount([cyclic]) != "" and ModFormula._bundles.is_empty(), "cyclic module load refuses activation")
	for source in [
		"function experience_reward(v,c,o) return 'bad' end",
		"function experience_reward(v,c,o) return 0/0 end",
		"function experience_reward(v,c,o) return 1000000001 end",
		"function experience_reward(v,c,o) while true do end end",
		"function experience_reward(v,c,o) local t={} for i=1,1000 do t[i]=string.rep('x',1048576) end return v end"
	]:
		var key := fixture(source)
		check(mount(["example.expedition-xp@1.0.0", key]) == "", "failing hook can be validated without an event")
		s = probe()
		check(s.state.save("user://protected.sav") == OK, "write valid checkpoint before failure")
		var before := FileAccess.get_sha256("user://protected.sav")
		check(reward(s) == 0.0, "failure commits no partial experience chain")
		check(s.mod_script_failed and s.state.mod_script_failed, "failure latches authority and save guard")
		check(s.events.size() == 1 and s.events[0].t == "mod_script_failed", "failure is sent to clients")
		check(s.state.save("user://protected.sav") == ERR_UNAVAILABLE and s.save_game("forbidden") == ERR_UNAVAILABLE, "all campaign save paths refuse failed state")
		check(FileAccess.get_sha256("user://protected.sav") == before, "failed save preserves existing bytes")
		calls = ModFormula.invocations
		XpRules.give(s, 100.0)
		check(ModFormula.invocations == calls, "failed authority cannot re-enter Lua")
		dispose(s)
	check(ModStore.select_profile("default") == "" and ModStore.mount() == "", "return to unmodded profile clears scripts")
	vanilla = probe()
	calls = ModFormula.invocations
	check(is_equal_approx(reward(vanilla), 100.0) and ModFormula.invocations == calls, "return-to-vanilla reward creates no VM")
	check(FileAccess.get_sha256("user://ordinary.sav") == vanilla_hash, "original save bytes unchanged")
	dispose(vanilla)
	print("MOD_FORMULAS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
