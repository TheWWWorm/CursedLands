class_name ArenaExpansion
extends RefCounted
## Opt-in arena content from the player's second installation. Namespaced rows
## and assets never replace a campaign row, texture, rig or animation cache.
const PREFIX := "arena-lia/"
const FAMILIES := [30, 31, 32, 33, 34, 35, 36, 37]
const POPPER := 32
const POPPER_DAMAGE := [30, 55, 120]
const POPPER_FUSE := 0.6
const POPPER_RADIUS := 2.5
const POPPER_TARGETS := 3
const CHARACTERS := {
	"lia_hero": ["Hero4", "hero"],
	"lia_merc2": ["merc2", "merc2"],
	"lia_merc8": ["merc8", "merc8"],
	"lia_merc10": ["bz2h Human Alija F", "merc10"],
	"lia_merc7": ["bz3h Human Sahilja F", "merc7"],
}
const CHARACTER_SKINS := {
	"lia_hero_unmasked": "Hero1",
	"lia_hero_wrapped": "Hero2",
	"lia_hero_armored": "Hero3",
	"lia_merc2_armored": "merc2g",
}
# Source prototypes and OBJPRIMTXTR palettes from LiA's shipped MOB records.
# Repeated native ages retain one species/role; arena stars supply the budget.
const RECRUITS := {
	"fox1": ["zone31 Fox1", "fox00", "Young fox"],
	"fox2": ["zone31 Fox2", "fox00", "Adult fox"],
	"fox3": ["zone32 Fox2", "fox00", "Veteran fox"],
	"leopard1": ["zone1 Leopard1", "tiger02", "Young leopard"],
	"leopard2": ["zone1 Leopard2", "tiger02", "Adult leopard"],
	"leopard3": ["zone3 Leopard2", "tiger02", "Veteran leopard"],
	"popper1": ["zone32 Popper", "hare02", "Exploding hare"],
	"popper2": ["zone32 Popper", "hare02", "Exploding hare"],
	"popper3": ["zone32 Popper", "hare02", "Exploding hare"],
	"deer1": ["zone32 DeadDeer", "deer03", "Undead stag"],
	"deer2": ["zone34 DeadDeer", "deer03", "Undead stag"],
	"deer3": ["zone35 DeadDeer", "deer03", "Undead stag"],
	"jwolf1": ["zone31 WolfBraun", "jwolf00", "Jigran wolf"],
	"jwolf2": ["zone33 WolfBraun", "jwolf00", "Jigran wolf"],
	"jwolf3": ["zone35 WolfBlack", "jwolf01", "Black Jigran wolf"],
	"jun1": ["zone11dun1 LizardMonstr", "lizardman03", "Jun lizard"],
	"jun2": ["zone11dun1 LizardMonstr", "lizardman03", "Jun lizard"],
	"jun3": ["zone11dun1 LizardMonstr", "lizardman03", "Jun lizard"],
	"wight1": ["zone7 Undead Fighter M", "", "Undead warrior"],
	"wight2": ["zone33 Undead Fighter1 M", "", "Undead warrior"],
	"wight3": ["zone35 Undead Fighter2 M", "", "Undead warrior"],
	"plague1": ["zone7 Undead Mage M", "", "Undead mage"],
	"plague2": ["zone35 Undead Mage M", "", "Undead mage"],
	"plague3": ["q21j Undead Mage M", "", "Undead mage"],
}
static var _mounted_db: EIDatabase
static var _root := ""
static var _archives := {}
static var _fingerprint := ""

static func available() -> bool:
	return not DataSwitch.installed(CampaignProfile.ORIGINAL).is_empty() \
		and not DataSwitch.installed(CampaignProfile.ASTRAL).is_empty()

static func mounted() -> bool:
	return _mounted_db != null and _mounted_db == GameData.db and not _root.is_empty()

static func mount() -> bool:
	if mounted(): return true
	if GameData.campaign_id != CampaignProfile.ORIGINAL or not available(): return false
	var path := DataSwitch.installed(CampaignProfile.ASTRAL)
	var archives := {}
	for kind in ["database", "figures", "textures", "redress"]:
		archives[kind] = EIResArchive.open_path(path.path_join("res/" + kind + ".res"))
		if archives[kind] == null: return false
	# Decode the second edition without changing the current UI's language.
	var prior_page := EIText.code_page
	EIText.code_page = EIText.detect_code_page(EIResArchive.open_path(path.path_join("res/texts.res")))
	var source := EIDatabase.load_from(archives.database, true)
	EIText.code_page = prior_page
	var rows := EIDatabase.new()
	var sources := {}
	for key: String in RECRUITS: sources[key] = RECRUITS[key][0]
	for key: String in CHARACTERS: sources[key] = CHARACTERS[key][0]
	sources.merge(CHARACTER_SKINS)
	for key: String in sources:
		var proto := source.find("monster_prototypes", sources[key]).duplicate(true)
		if proto.is_empty(): return false
		var race := source.find("race_models", str(proto.base_race)).duplicate(true)
		if race.is_empty(): return false
		race.name = PREFIX + String(race.name).to_lower()
		proto.name = PREFIX + key; proto.base_race = race.name
		proto["_arena_assets"] = PREFIX
		proto["_arena_commander"] = CHARACTERS.has(key) or CHARACTER_SKINS.has(key)
		_append(rows, "monster_prototypes", proto)
		_append(rows, "race_models", race)
	# Preserve both original and multiplayer-fallback crafting definitions.
	# Only missing records are needed for LiA's clothing and weapons.
	for table in ["weapons", "armors", "materials"]:
		for row: Dictionary in source.table(table):
			if GameData.db.find(table, String(row.name)).is_empty(): _append(rows, table, row.duplicate(true))
	for table in ["monster_prototypes", "race_models", "weapons", "armors", "materials"]:
		GameData.db.merge_missing(rows, table)
	_root = path; _archives = archives; _mounted_db = GameData.db; _fingerprint = ""
	return true

static func _append(db: EIDatabase, table: String, row: Dictionary) -> void:
	if not db.tables.has(table): db.tables[table] = []
	db.tables[table].append(row)

static func asset(archive: String, name: String) -> PackedByteArray:
	if not mounted() or not name.begins_with(PREFIX): return PackedByteArray()
	var source: EIResArchive = _archives.get(archive)
	return source.read_original(name.trim_prefix(PREFIX)) if source else PackedByteArray()

static func has_asset(archive: String, name: String) -> bool:
	if not mounted() or not name.begins_with(PREFIX): return false
	var source: EIResArchive = _archives.get(archive)
	return source != null and source.entries.has(name.trim_prefix(PREFIX).to_lower())

static func appearance(id: String) -> Dictionary:
	var key := id.trim_prefix(PREFIX)
	var result := {"prototype": id}
	if id.begins_with(PREFIX) and RECRUITS.has(key) and not String(RECRUITS[key][1]).is_empty():
		result.texture = RECRUITS[key][1]
	return result

static func title(id: String) -> String:
	var row: Array = RECRUITS.get(id.trim_prefix(PREFIX), [])
	return RemakeText.t(row[2]) if not row.is_empty() else ""

static func fingerprint() -> String:
	if not mounted(): return ""
	if not _fingerprint.is_empty(): return _fingerprint
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	# Native stats, equipment, geometry and animation timing affect combat.
	# Localized texts and paintings do not affect the host simulation.
	var inputs := {"database":["units.udb", "items.idb", "spells.sdb"], "figures":[]}
	var templates := {}
	for id: String in RECRUITS:
		var proto := GameData.db.find("monster_prototypes", PREFIX + id)
		var race := GameData.db.find("race_models", proto.base_race)
		templates[String(race.mask).to_lower()] = true
	var ordered := templates.keys(); ordered.sort()
	for template: String in ordered:
		inputs.database.append(template + ".adb")
		for suffix in [".mod", ".bon", ".anm"]: inputs.figures.append(template + suffix)
	for archive: String in inputs:
		for name: String in inputs[archive]:
			context.update((archive + ":" + name).to_utf8_buffer())
			context.update((_archives[archive] as EIResArchive).read_original(name))
	_fingerprint = context.finish().hex_encode()
	return _fingerprint
