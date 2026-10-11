class_name ModSchema
extends RefCounted
## Versioned data contract. A menu definition grants no executable capability.
const API := 1
const RULES := {
	"difficulty": ["Difficulty", ["Normal", "Easy"], "new_game"],
	"unit_fog": ["Unit visibility", ["Off", "On"], "new_game"],
	"start_zones": ["Revisit starting areas", ["Off", "On"], "new_game"],
	"sp_full_xp": ["Full experience in single player", ["Off", "On"], "camp"],
	"revive": ["Revive fallen party members", ["Off", "On"], "camp"],
	"merc_travel": ["Mercenaries travel between regions", ["Off", "On"], "camp"],
	"auto_exit": ["Automatic zone departure", ["Off", "On"], "live"],
	"mechanism_motion": ["Mechanism motion", ["Fast drop", "Original timing"], "new_game"],
	"distant_ai": ["Approximate distant AI", ["Off", "On"], "new_game"],
	"coop_full_xp": ["Full experience in co-op", ["Off", "On"], "camp"],
	"coop_scale": ["Monster scaling", ["Off", "Light", "Normal", "Strong"], "new_game"],
	"coop_share_loot": ["Shared loot", ["Off", "On"], "camp"],
	"coop_clock": ["Shared pause and speed", ["Off", "On"], "live"],
	"sandbox_invulnerable": ["Invulnerable party", ["Off", "On"], "live"],
	"sandbox_mana": ["Unlimited party mana", ["Off", "On"], "live"],
}
const CAPABILITIES := {
	"revival.seconds": {"type": "number", "min": 1.0, "max": 30.0, "default": 5.0},
	"revival.health": {"type": "number", "min": 1.0, "max": 100.0, "default": 1.0},
}
## Only numeric balance fields with stable named records are patchable in v1.
const PATCH_FIELDS := {
	"monster_prototypes": ["hp", "mana", "damage_min", "damage_max", "experience"],
	"spell_prototypes": ["mana", "range", "effect", "duration", "price"],
	"perks": ["cost"],
}
const MODES := ["single_player", "campaign_coop", "original_multiplayer"]

static func identifier(value: Variant) -> bool:
	if not value is String or value.length() < 1 or value.length() > 80: return false
	for c in value:
		if not (c >= "a" and c <= "z" or c >= "0" and c <= "9" or c in ["_", "-", "."]): return false
	return not value.begins_with(".") and not value.contains("..")

static func safe_path(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 240: return false
	if value.begins_with("/") or value.contains("\\") or value.contains(":"): return false
	for c in value:
		if c.unicode_at(0) < 32 or c in ["<", ">", "\"", "|", "?", "*"]: return false
	for part in value.split("/"):
		if part in ["", ".", ".."] or part.ends_with(".") or part.ends_with(" "): return false
		var stem: String = part.get_slice(".", 0).to_lower()
		if stem in ["con", "prn", "aux", "nul"] or (stem.length() == 4 and stem.left(3) in ["com", "lpt"] and stem[3] in "123456789"): return false
	return true

static func finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func value_error(definition: Dictionary, value: Variant) -> String:
	match String(definition.get("type", "")):
		"boolean":
			if not value is bool: return "Expected On or Off."
		"integer", "number":
			if not finite_number(value): return "Expected a finite number."
			if definition.type == "integer" and float(value) != floorf(float(value)): return "Expected a whole number."
			if float(value) < float(definition.min) or float(value) > float(definition.max): return "Value is outside the allowed range."
			var step := float(definition.get("step", 1.0))
			var ticks := (float(value) - float(definition.min)) / step
			if absf(ticks - roundf(ticks)) > 0.00001: return "Value does not match the allowed step."
		"enum":
			if not value is String or not definition.choices.has(value): return "Unknown choice."
		_:
			return "Unsupported option type."
	return ""

static func manifest_error(m: Variant) -> String:
	if not m is Dictionary: return "The manifest must be an object."
	if m.get("api", 0) != API: return "This mod needs a different mod API version."
	for key in ["id", "version"]:
		if not identifier(m.get(key)): return "Invalid mod " + key + "."
	if not m.get("title") is String or m.title.is_empty() or m.title.length() > 100: return "Invalid mod title."
	if not m.get("description", "") is String or m.get("description", "").length() > 3000: return "Invalid description."
	if not m.get("campaigns") is Array or m.campaigns.is_empty(): return "Declare the supported campaigns."
	for id in m.campaigns:
		if id not in ["cursed_lands", "lost_in_astral"]: return "Custom campaigns are not supported by API 1."
	if not m.get("modes", MODES) is Array or m.get("modes", MODES).is_empty(): return "Invalid game modes."
	for mode in m.get("modes", MODES):
		if mode not in MODES: return "Unknown game mode."
	for key in ["requires", "after", "conflicts"]:
		if not m.get(key, []) is Array or m.get(key, []).size() > 64: return "Invalid " + key + "."
		for id in m.get(key, []):
			if not identifier(id) or id == m.id: return "Invalid dependency or conflict."
	if not m.get("options", []) is Array or m.get("options", []).size() > 64: return "Too many options."
	var ids := {}
	for o in m.get("options", []):
		if not o is Dictionary or not identifier(o.get("id")): return "Invalid option ID."
		if ids.has(o.id): return "Duplicate option ID: " + o.id
		ids[o.id] = true
		if not o.get("label") is String or o.label.is_empty() or o.label.length() > 120: return "Invalid option label."
		if not o.get("help", "") is String or o.get("help", "").length() > 2000: return "Invalid option help."
		if not CAPABILITIES.has(o.get("binding", "")): return "Unsupported capability: " + str(o.get("binding", ""))
		var cap: Dictionary = CAPABILITIES[o.binding]
		if o.get("type", "") not in ["integer", "number"]: return "Revival capabilities require a numeric option."
		if not finite_number(o.get("min")) or not finite_number(o.get("max")) or not finite_number(o.get("step", 1.0)): return "Invalid numeric bounds."
		if o.min < cap.min or o.max > cap.max or o.max < o.min or o.get("step", 1.0) < 0.001: return "Unsupported capability range."
		var error := value_error(o, o.get("default"))
		if error != "": return String(o.id) + ": " + error
	if not m.get("overrides", []) is Array or m.get("overrides", []).size() > 4096: return "Invalid archive overrides."
	for a in m.get("overrides", []):
		if not a is Dictionary or not safe_path(a.get("file")) or not safe_path(a.get("entry")): return "Invalid override path."
		if a.get("archive", "") not in ["textures.res", "sfx.res", "speech.res"]: return "Unsupported archive; API 1 supports texture and sound replacements."
		if a.archive == "textures.res" and not a.entry.ends_with(".mmp"): return "Texture overrides must be MMP files."
	if not m.get("patches", []) is Array or m.get("patches", []).size() > 1024: return "Invalid database patches."
	for p in m.get("patches", []):
		if not p is Dictionary or not PATCH_FIELDS.has(p.get("table", "")): return "Unsupported database table."
		if not p.get("record") is String or p.record.is_empty() or p.record.length() > 160: return "Invalid database record."
		if p.get("field", "") not in PATCH_FIELDS[p.table]: return "Unsupported database field."
		if not finite_number(p.get("value")) or p.value < 0 or p.value > 1000000: return "Invalid database value."
		if p.get("database", "campaign") not in ["campaign", "multiplayer"]: return "Invalid database target."
	return ""

static func gameplay(m: Dictionary) -> bool:
	return not m.get("options", []).is_empty() or not m.get("patches", []).is_empty()

static func canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var fields := PackedStringArray()
		for key in keys: fields.append(JSON.stringify(String(key)) + ":" + canonical(value[key]))
		return "{" + ",".join(fields) + "}"
	if value is Array:
		var fields := PackedStringArray()
		for item in value: fields.append(canonical(item))
		return "[" + ",".join(fields) + "]"
	if finite_number(value): return JSON.stringify(float(value), "", true, true)
	return JSON.stringify(value)

static func digest(value: Variant) -> String:
	return canonical(value).sha256_text()
