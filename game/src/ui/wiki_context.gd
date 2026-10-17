class_name WikiContext
extends RefCounted
## One rebindable shortcut and context protocol for native and Control UIs.

static func matches(event: InputEvent, viewport: Viewport) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo: return false
	var focus := viewport.gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return false
	return EIKeymap.event_action(event) == "wiki_context"


static func hovered(root: Node) -> Dictionary:
	var control := root.get_viewport().gui_get_hovered_control()
	while control and control != root:
		if control.has_method("wiki_context"): return control.wiki_context()
		if control.has_meta("wiki_context"): return control.get_meta("wiki_context")
		control = control.get_parent() as Control
	return {}


static func for_unit(unit: GameUnit) -> Dictionary:
	if not is_instance_valid(unit): return {}
	var id := String(unit.proto.get("name", unit.info.get("prototype", ""))).to_lower()
	return {"key": "creature/" + id.uri_encode()} if not id.is_empty() else {}


static func navigate(panel: WikiPanel, context: Dictionary) -> void:
	var id := String(context.get("item", "")).trim_prefix("belt:")
	if id.begins_with("spell:") or id.begins_with("keystone:"):
		var magic := id.trim_prefix("spell:").trim_prefix("keystone:")
		var key: String = panel._source.read(func(): return panel.catalog.add_variant(magic))
		if not key.is_empty(): panel.navigate(key)
	elif id.begins_with("rune:"):
		panel.navigate("rune/" + id.trim_prefix("rune:").uri_encode())
	elif not id.is_empty():
		panel.navigate(WikiCatalog.item_key(id), true, id)
	elif not String(context.get("key", "")).is_empty():
		panel.navigate(context.key)
