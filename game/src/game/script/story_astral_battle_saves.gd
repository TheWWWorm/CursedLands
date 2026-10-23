extends RefCounted
## Older remake AddMob saves isolated these two groups from their waiting
## parent. Restore only the verified shipped battle before its victory, using
## the actual saved actors. Never infer dead enemies or rewind quest flags.
const ZONE := "e3498ea9211e7340f35bec94881a10e823617f838f105571e2854ba87f52d77a"
const ADDON := "21e4249f63196a19333f2d5d0d62ce1a9966330e8bb6679e53a5a0731153f70d"
const KANIANS := [1021001,1021002,1021003,1021004,1021005,1021006,1021007,
	1021008,1021009,1021010,1021011,1021012,1021013,1021014,1021015,1021016,
	1021017,1021018,1021019,1021020,1021021,1021022,1021023,1021031,1021032,
	1021033,1021034,1021035,1021036,1021041,1021042,1021043,1021044,1021045]

static func recover(vm: ScriptVM) -> bool:
	var s := vm.session
	if s.state.campaign_id != CampaignProfile.ASTRAL or not s.lmp.is_empty() \
			or s.zone_id != "gz35j" or vm.world.mob == null \
			or vm.world.mob.script_text.sha256_text() != ZONE \
			or s.state.get_var(0,"q.gz35j.q21j") != 1.0 \
			or s.state.get_var(0,"q.gz35j.q21j.1") >= 2.0 \
			or s.state.get_var(0,"q.gz35j.q21j.2") != 0.0:
		return false
	var mobs: Array = vm.world.get_meta("added_mobs",[])
	if not mobs.any(func(name):return String(name).to_lower() == "zone35battle.mob"): return false
	for group: String in ["ArEvil","Kanians"]:
		var parent = vm.globals.get(group)
		if not parent is Array or not parent.is_empty(): return false
	var enemies = vm.globals.get("ArEvil_zone35battle")
	var allies = vm.globals.get("Kanians_zone35battle")
	if not _group(vm,enemies,range(1021101,1021140)) or not _group(vm,allies,KANIANS): return false
	var addon := EIMob.load_bytes(GameData.read_file("maps/zone35battle.mob"))
	if addon == null or addon.script_text.sha256_text() != ADDON: return false
	vm.globals.ArEvil = enemies.duplicate()
	vm.globals.Kanians = allies.duplicate()
	vm.globals.erase("ArEvil_zone35battle")
	vm.globals.erase("Kanians_zone35battle")
	return true

static func _group(vm: ScriptVM, value: Variant, ids: Array) -> bool:
	if not value is Array or value.size() != ids.size(): return false
	var found := {}
	for unit in value:
		if not unit is GameUnit or not is_instance_valid(unit) \
				or unit.uid not in ids or found.has(unit.uid) \
				or vm.world.units.get(unit.uid) != unit: return false
		found[unit.uid] = true
	return true
