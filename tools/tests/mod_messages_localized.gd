extends Node
## Mod profile, package, schema and sandbox messages reach the screen in the
## player's language. On the former code, messages composed with runtime values
## ("Unknown mod option: x", "Missing asset: y") could never match a catalog key
## and stayed English, and the save and difficulty status labels showed the
## English key directly. Run through Main --tool with --mod-tests.
var checks := 0
var failures := 0

## Every message key that ModStore, ModSchema and Session.sandbox_action return.
const KEYS := [
	"Unknown game rule.", "Invalid game rule value.", "Game rule is outside its allowed range.",
	"Unknown mod option: %s", "Unsupported saved mod configuration.",
	"The mod configuration belongs to another campaign.", "Invalid mod configuration.",
	"Mod configuration is too large.", "Invalid profile metadata.", "Invalid mod configuration metadata.",
	"The shared rule list is incomplete.", "The shared mod options are incomplete.",
	"Sandbox rules require a sandbox profile.", "Invalid required package.", "Invalid package fingerprint.",
	"Required setup: %s. Select a matching mod profile first.",
	"Sandbox profiles support single player and campaign co-op.", "%s does not support this game mode.",
	"Could not create a new save folder.", "The mod profile file is too large.",
	"Could not preserve the unreadable profile file.", "Could not write mod settings.",
	"Could not finish writing mod settings.", "Could not replace mod settings.",
	"Missing or oversized mod.json.", "Missing or oversized asset: %s", "Installed mod exceeds its package limit.",
	"Missing package: %s", "Choose one version of %s", "%s does not support this campaign.",
	"%s conflicts with %s", "The mod dependency order contains a cycle.", "Conflict on %s between %s and %s",
	"Cannot patch %s: %s", "This database field requires a whole number: %s",
	"Choose a ZIP or .eimod package containing mod.json.", "Missing mod.json or too many package files.",
	"Unsafe or duplicate package path.", "Damaged manifest.", "Package directory exceeds its API limit.",
	"Package exceeds the limit for its API version.", "Undeclared file: %s", "Missing asset: %s",
	"Damaged or empty package member: %s", "Could not install the package.", "Could not create the save copy.",
	"Could not finish the save copy.", "Choose a named profile from the main menu first.", "Invalid save name.",
	"The source save cannot be read.", "Copy only an unmodded, non-sandbox save from Current defaults.",
	"Save copied to this profile: %s", "Sandbox actions require a sandbox host.",
	"Sandbox actions are unavailable here.", "Unknown sandbox action.", "The save cannot be read.",
	"Sandbox action failed.", "This legacy save belongs to Current defaults.",
	"Could not read mod profiles. A recovery copy will be kept before saving changes.",
	"Invalid installed package folder: %s",
	"Expected On or Off.", "Expected a finite number.", "Expected a whole number.",
	"Value is outside the allowed range.", "Value does not match the allowed step.", "Unknown choice.",
	"Unsupported option type.", "The manifest must be an object.", "This mod needs a different mod API version.",
	"Invalid mod %s.", "Invalid mod title.", "Invalid description.", "Declare the supported campaigns.",
	"Custom campaigns are not supported by API 1.", "Invalid game modes.", "Unknown game mode.", "Invalid %s.",
	"Invalid dependency or conflict.", "Too many options.", "Invalid option ID.", "Duplicate option ID: %s",
	"Invalid option label.", "Invalid option help.", "Unsupported capability: %s", "Invalid numeric bounds.",
	"Unsupported capability range.", "Invalid archive overrides.", "Invalid override path.",
	"Invalid mod documentation.", "Mod documentation needs package API 2.", "Invalid mod documentation path.",
	"Invalid database patches.", "Unsupported database table.", "Invalid database record.",
	"Unsupported database field.", "Invalid database value.", "Invalid database target.",
]

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

static func placeholders(text: String) -> int:
	return text.count("%s")

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"):
		printerr("Use disposable XDG directories and --mod-tests.")
		get_tree().quit(2)
		return
	await get_tree().process_frame
	var english := RemakeText.lang
	var bad_manifest := {"api": 1, "id": "example.mod", "version": "1.0", "title": "", "campaigns": ["cursed_lands"]}
	for lang in ["ru", "de"]:
		RemakeText.lang = lang
		for key in KEYS:
			var text := RemakeText.t(key)
			check(text != key, lang + ": translated: " + key)
			check(placeholders(text) == placeholders(key), lang + ": placeholders kept: " + key)
		# Composed messages are translated at the source and keep the runtime value.
		var option := ModStore.values_error({"example.bogus": 1})
		check(option.contains("example.bogus") and not option.begins_with("Unknown mod option"),
			lang + ": unknown option message is translated and names the option")
		check(RemakeText.t(option) == option, lang + ": a composed message passes through a second translation unchanged")
		var rule := ModStore.rule_error({"bogus_rule": 1})
		check(rule == RemakeText.t("Unknown game rule.") or RemakeText.t(rule) != rule, lang + ": rule error is shown translated")
		var manifest := ModSchema.manifest_error(bad_manifest)
		check(manifest != "" and RemakeText.t(manifest) != manifest, lang + ": manifest error has a translation")
		var field := ModSchema.manifest_error({"api": 1, "id": "", "version": "1.0", "title": "x", "campaigns": ["cursed_lands"]})
		check(field.contains("id") and not field.begins_with("Invalid mod "), lang + ": field error names the field in the player's language")
		check(ModStore.saved_error({"rules": 7}) != "" and RemakeText.t(ModStore.saved_error({"rules": 7})) != ModStore.saved_error({"rules": 7}),
			lang + ": saved configuration error has a translation")
	RemakeText.lang = "en"
	check(ModStore.values_error({"example.bogus": 1}) == "Unknown mod option: example.bogus", "English option message unchanged")
	check(ModStore.rule_error({"bogus_rule": 1}) == "Unknown game rule.", "English rule message unchanged")
	check(ModSchema.manifest_error({"api": 1, "id": "", "version": "1.0", "title": "x", "campaigns": ["cursed_lands"]}) == "Invalid mod id.",
		"English field message unchanged")
	RemakeText.lang = english
	print("MOD_MESSAGES_LOCALIZED %d checks %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
