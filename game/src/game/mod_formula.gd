class_name ModFormula
extends RefCounted
## Explicit, stateless formulas. Each invocation owns a fresh bounded Lua VM.
## No engine bridge, retained Lua state, bytecode or original-game DLL ABI.
const CONFIG := "res://src/native/mod_lua.cfg"
static var _bundles: Array = []
static var invocations := 0

static func clear() -> void:
	_bundles.clear()

static func supported() -> bool:
	return OS.has_feature("x86_64") and (OS.has_feature("linux") or OS.has_feature("windows")) and not OS.has_feature("web")

static func _load_runtime() -> bool:
	if ClassDB.class_exists("ModLuaKernel"): return true
	if not supported(): return false
	var status := GDExtensionManager.load_extension(CONFIG)
	return status in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED] and ClassDB.class_exists("ModLuaKernel")

static func mount(order: Array) -> String:
	clear()
	var pending: Array = []
	for key in order:
		var m: Dictionary = ModStore.catalog[key]
		if not m.has("script"): continue
		if not supported(): return RemakeText.t("Formula mods currently require Windows or Linux on a 64-bit PC.")
		if not _load_runtime(): return RemakeText.t("The formula runtime is unavailable. Reinstall this game build.")
		var verified := ModStore.inspect_package(m._root, _manifest(m))
		if verified.error != "" or verified.package._digest != m._digest: return RemakeText.t("The formula package changed. Reinstall the matching version.")
		var sources := {}
		for name in m.script.modules:
			var bytes := FileAccess.get_file_as_bytes(m._root.path_join(m.script.modules[name]))
			var source := bytes.get_string_from_utf8()
			if source.to_utf8_buffer() != bytes: return RemakeText.t("Formula modules must contain UTF-8 Lua source.")
			sources[name] = source
		var bundle := {"manifest": m, "sources": sources}
		var checked := _kernel(bundle)
		if not checked.ok:
			print("MOD_FORMULA: ", m.id, ": ", checked.error)
			return RemakeText.t("A formula mod could not start. See the game log for details.")
		pending.append(bundle)
	_bundles = pending
	return ""

static func _manifest(m: Dictionary) -> Dictionary:
	var copy := m.duplicate(true)
	copy.erase("_root")
	copy.erase("_digest")
	return copy

static func _kernel(bundle: Dictionary) -> Dictionary:
	var kernel: RefCounted = ClassDB.instantiate("ModLuaKernel")
	var script: Dictionary = bundle.manifest.script
	var result: Dictionary = kernel.configure(bundle.sources, script.entry)
	if not result.ok: return result
	for hook in script.hooks:
		if not kernel.has_function(hook): return {"ok": false, "error": "Missing declared function: " + hook}
	return {"ok": true, "kernel": kernel}

static func has_hook(hook: String) -> bool:
	for bundle in _bundles:
		if hook in bundle.manifest.script.hooks: return true
	return false

## Transform the complete event before the caller commits its gameplay writes.
## On failure no partial chain is returned; the authority stops and refuses saves.
static func transform(hook: String, value: float, context: Dictionary, session: Session) -> Dictionary:
	if _bundles.is_empty() or not session.is_host: return {"ok": true, "value": value}
	if session.mod_script_failed: return {"ok": false}
	var output := value
	for bundle in _bundles:
		var m: Dictionary = bundle.manifest
		if hook not in m.script.hooks: continue
		var checked := _kernel(bundle)
		if checked.ok:
			var options := {}
			for o in m.get("options", []):
				options[o.id] = session.mod_config.values.get(m.id + ":" + o.id, o.default)
			var input := context.duplicate(true)
			input.campaign = GameData.campaign_id
			input.mode = "original_multiplayer" if not session.lmp.is_empty() else ("campaign_coop" if session.multiplayer_game else "single_player")
			invocations += 1
			checked = checked.kernel.invoke(hook, [output, input, options])
		var bounds: Array = ModSchema.FORMULA_HOOKS[hook]
		if not checked.ok or not ModSchema.finite_number(checked.get("value")) or float(checked.value) < bounds[0] or float(checked.value) > bounds[1]:
			var reason := str(checked.get("error", ""))
			if reason.is_empty(): reason = "Result outside the hook's numeric range"
			session.stop_mod_script("%s / %s: %s" % [m.id, hook, reason])
			return {"ok": false}
		output = float(checked.value)
	return {"ok": true, "value": output}
