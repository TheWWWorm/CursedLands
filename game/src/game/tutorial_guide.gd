class_name TutorialGuide
extends RefCounted
## Semantic topic IDs share the original localized references, never a modal.
## New copy is translated through RemakeText; installed archives supply detail.
const TOPICS := {
	"zt1": {"title": "Moving", "brief": "Select your hero, then choose a destination.", "detail": "Move, run or sneak using the movement control. Select portraits to change the active character."},
	"zt2": {"title": "Camera", "brief": "Look around to find a clear view of your path.", "detail": "Camera controls depend on your view mode. Centre the camera to return to your selected hero."},
	"zt3": {"title": "Objectives", "brief": "Open your objectives to review the next step.", "detail": "The journal keeps conversations. The message log keeps recent notices."},
	"zt4": {"title": "Tactical pause", "brief": "Pause when you need time to plan your orders.", "detail": "Orders can be given while paused. In co-op, shared pause and speed depend on the host settings."},
	"zt5": {"title": "Attacking", "brief": "Choose a visible enemy to attack.", "detail": "Attack-move engages enemies along the route. Forced commands can target otherwise friendly units."},
	"zt6": {"title": "Loot", "brief": "Collect trophies from defeated enemies.", "detail": "Collected items go into the inventory. Check their value and weight before your next trip."},
	"zt7": {"title": "Healing", "brief": "Wounded? Choose Healing, then your hero.", "detail": "Spells need stamina and time to cast. Your target must be in range; an interrupted cast may not heal."},
	"zt8": {"title": "Saving", "brief": "Save at a quiet moment before moving on.", "detail": "Use the game menu for saves and loads. Quick save and autosave keep separate recovery points."},
	"zt9": {"title": "Combat stance", "brief": "Choose defensive or aggressive behaviour on the movement control.", "detail": "Aggressive characters engage nearby enemies. Defensive behaviour gives you more control over engagement."},
	"zt10": {"title": "Minimap", "brief": "Use the minimap to orient yourself and choose a route.", "detail": "Zoom changes the visible area. Map symbols mark known units, objectives and exits."},
	"zt11": {"title": "Message log", "brief": "Review missed messages in the log.", "detail": "Switch between messages and collected items to find what just happened."},
	"zt12": {"title": "Character status", "brief": "Inspect your hero to check wounds and active effects.", "detail": "The character panel has views for health, attributes, equipment and effects."},
	"zt13": {"title": "Stealth", "brief": "Sneak or crawl to become harder to notice.", "detail": "Movement changes speed, stamina, noise and visibility. Watch enemy awareness before approaching."},
	"zt14": {"title": "Use and steal", "brief": "Choose Use/Steal, then the object or character.", "detail": "Stealing can fail and alert the victim. Mechanisms also use this action."},
	"zt15": {"title": "Aimed strikes", "brief": "Choose an aimed strike to target a body part.", "detail": "Small targets are harder to hit. Wounds to different body parts have different effects."},
	"zt16": {"title": "Leaving an area", "brief": "Lead your party to an available exit.", "detail": "Check the travel map for destinations and routes back to camp. Some exits require quest progress."},
	"zt17": {"title": "Weapon slots", "brief": "Switch weapons using your equipped weapon slots.", "detail": "Assign weapons in the equipment screen before using their quick slots in the field."},
	"zt18": {"title": "Quick items", "brief": "Choose a belt item, then its target.", "detail": "Potions and wands may have limited uses. Assign them to the belt in the equipment screen."},
	"zt19": {"title": "Quest completion", "brief": "Review your objectives before returning for a reward.", "detail": "Some tasks finish immediately; others require returning to the person who gave them."},
	"zt20": {"title": "Party selection", "brief": "Select portraits to command individual companions.", "detail": "Select the whole party for shared orders, or command one character for a precise task."},
	"zt21": {"title": "Backstab", "brief": "Approach an unaware enemy from behind.", "detail": "Stealth and awareness matter. An enemy who notices you can turn before the strike."},
	"zt22": {"title": "Pickpocketing", "brief": "Get close without being noticed before trying to steal.", "detail": "Use/Steal attempts a theft from a character. A failed attempt may provoke a fight."},
	"zt23": {"title": "Water and terrain", "brief": "Look for a shallow route across the water.", "detail": "Depth and terrain height can prevent passage. Try a different route if a movement order fails."},
	"zt24": {"title": "Taking quests", "brief": "Talk to characters to discover new tasks.", "detail": "Read the available conversation topics, then check your objectives after accepting a task."},
	"base": {"title": "In the village", "brief": "Talk to villagers for quests, services and companions.", "detail": "Conversation topics change with events. Shops offer equipment, training and construction."},
	"global_map": {"title": "Travel", "brief": "Choose an available destination on the travel map.", "detail": "Routes and destinations open as you explore and complete quests. You can return to camp between trips."},
	"quest_global_map": {"title": "Choosing a quest", "brief": "Select a quest to review its destination.", "detail": "Read its objectives before choosing where to travel."},
	"quest_mission": {"title": "Quest map", "brief": "Select an objective to see its details and location.", "detail": "Main objectives and smaller steps appear separately. Use the area map to plan your route."},
	"camp_weapons": {"title": "Equipment", "brief": "Choose a character, then place gear in a matching slot.", "detail": "Weapon slots and belt slots become quick actions during play. Compare protection, damage and weight."},
	"camp_skills": {"title": "Training", "brief": "Spend experience on the skills your character needs.", "detail": "Check attributes, skills and abilities, then assign usable spells to the spell slots."},
	"camp_item_trade": {"title": "Item trading", "brief": "Choose items, review the total, then confirm the trade.", "detail": "Buying and selling use different prices. Check the character and your money before confirming."},
	"camp_spell_trade": {"title": "Spell trading", "brief": "Choose spells, review the total, then confirm the trade.", "detail": "Check the required school knowledge and stamina before buying a spell."},
	"camp_item_constr": {"title": "Item construction", "brief": "Choose a blueprint, add materials, then review the result.", "detail": "Construction and dismantling have costs. Enchantments must fit the item energy and complexity limits."},
	"camp_spell_constr": {"title": "Spell construction", "brief": "Choose a base spell, add compatible runes, then review it.", "detail": "Runes change power, duration, complexity and stamina cost. Check the limits before assembling."},
	"camp_repair": {"title": "Repair", "brief": "Choose damaged equipment and check its repair price.", "detail": "Durability falls with use. Repair damaged equipment before it becomes unusable."},
	"options": {"title": "Controls and options", "brief": "Select a setting to read what it changes.", "detail": "Keyboard and gamepad bindings can be changed here. Contextual hints can be disabled; the guide stays available."},
}
const CONTEXT_ONLY := ["zt19", "zt21", "zt22", "zt24"]

static func canonical(id: String) -> String:
	return "global_map" if id == "global_map_nocamp" else id

static func available(id: String) -> bool:
	return id != "lmp" and (TOPICS.has(id) or not pages(id).is_empty())

static func title(id: String) -> String:
	if TOPICS.has(id): return RemakeText.t(TOPICS[id].title)
	var source := pages(id)
	return String(source[0].title) if not source.is_empty() and source[0].title else RemakeText.t("Archived hint")

static func brief(id: String) -> String:
	return RemakeText.t(TOPICS[id].brief) if TOPICS.has(id) else RemakeText.t("Tips stay available in the guide after they disappear.")

static func detail(id: String) -> String:
	return RemakeText.t(TOPICS[id].detail) if TOPICS.has(id) else ""

static func pages(id: String) -> Array:
	var out := []
	var lines := GameData.text("tutorial " + id).split("\n")
	var page := {}
	var want := ""
	var title := ""
	for raw in lines:
		var l := raw.strip_edges()
		if l.is_empty():
			continue
		if l == "#screen":
			if not page.is_empty():
				out.append(page)
			page = {"rects": []}
			want = "head"
		elif l == "#text":
			want = "text"
		elif l.begins_with("#position") or l.begins_with("#rectangle"):
			var v := Array(l.split(" ", false).slice(1)).map(func(s): return int(s))
			if l.begins_with("#position") and v.size() >= 3:
				page["position"] = v
			elif v.size() >= 4:
				page.rects.append(Rect2(v[0], v[1], v[2] - v[0], v[3] - v[1]))
		elif l.begins_with("#"):
			continue
		elif want:
			page[want] = GameData.text("tutor " + l).strip_edges(false, true)
			want = ""
		elif page.is_empty() and title == "":
			title = GameData.text("tutor " + l).strip_edges()
	if not page.is_empty():
		out.append(page)
	out = out.filter(func(p): return String(p.get("text", "")) != "")
	for p in out:
		p["title"] = title
	return out


## Resolve actual device/bindings at display time, including mid-hint changes.
static func prompt(id: String, context := {}, direct := false) -> String:
	var pad := PadInput.active == "pad"
	match id:
		"zt1":
			if pad: return RemakeText.t("Move with %s.") % PadInput.label("LS")
			if TouchInput.enabled: return RemakeText.t("Tap the ground to move your selected hero.")
			if direct:
				return RemakeText.t("Move with %s.") % " / ".join([EIKeymap.key_of("direct_forward", 2), EIKeymap.key_of("direct_left", 2), EIKeymap.key_of("direct_back", 2), EIKeymap.key_of("direct_right", 2)])
			return RemakeText.t("Click the ground to move; double-click to run.")
		"zt2":
			if pad: return RemakeText.t("Move the camera with %s.") % PadInput.label("RS")
			if direct: return RemakeText.t("Move the mouse to look around.")
			if not TouchInput.enabled: return RemakeText.t("Drag with the right mouse button to turn the camera.")
		"zt5":
			if pad: return RemakeText.t("Aim at the enemy and press %s.") % PadInput.label(PadInput.button_of("system" if direct else "interact"))
		"zt7":
			var spell := String(context.get("spell", ""))
			var name := WikiCatalog.spell_title(spell) if spell else title("zt7")
			if pad: return RemakeText.t("Use %s → %s, then target your wounded hero.") % [PadInput.label(PadInput.button_of("actions")), name]
			if spell: return RemakeText.t("Choose %s, then your wounded hero.") % name
		"zt13":
			if pad: return RemakeText.t("Use %s to choose a movement mode.") % PadInput.label(PadInput.button_of("gait"))
		"zt14", "zt22":
			if pad: return RemakeText.t("Open the actions wheel with %s to choose Use/Steal.") % PadInput.label(PadInput.button_of("actions"))
		"zt15":
			if pad: return RemakeText.t("Aim at a body part with %s before attacking.") % PadInput.label(PadInput.button_of("context"))
		"zt17", "zt18":
			if pad: return RemakeText.t("Use %s to choose a weapon or belt item.") % PadInput.label(PadInput.button_of("items"))
		"zt20":
			if pad: return RemakeText.t("Use %s to select a companion; hold it to select everyone.") % PadInput.label("UP")
	return brief(id)

static func tips(id: String, public_export := false) -> Array[String]:
	var out: Array[String] = []
	if id == "zt7":
		out.append(RemakeText.t("Select a spell in the actions wheel. Aim at your hero and confirm with %s.") % PadInput.label(PadInput.button_of("interact")) if PadInput.active == "pad" and not public_export else RemakeText.t("Select a spell slot, then your hero or portrait. Select the same slot again to cancel."))
	if id == "camp_skills":
		out.append(RemakeText.t("Training may apply immediately or require confirmation, depending on the training option.") if public_export else RemakeText.t("Training takes effect immediately. Reset training uses the training reset control." if GameData.option("skill_reset_button") else "Training changes are pending until you confirm them. Cancel discards them."))
	var info := detail(id)
	if info: out.append(info)
	return out

static func help_binding(direct := false) -> String:
	if PadInput.active == "pad":
		return game_wheel_binding(direct) + " → " + RemakeText.t("Help")
	return EIKeymap.key_of("tutorial_script")

static func game_wheel_binding(direct := false) -> String:
	return (PadInput.label(PadInput.button_of("mod")) + "+" if direct else "") + PadInput.label(PadInput.button_of("system"))

static func article(id: String, public_export := false) -> String:
	var direct: bool = is_instance_valid(PadInput.field) and PadInput.field.game.direct.active()
	var html := WikiCatalog.paragraph(brief(id) if public_export else prompt(id, {}, direct))
	for tip in tips(id, public_export): html += WikiCatalog.paragraph(tip)
	if public_export:
		html += WikiCatalog.paragraph(RemakeText.t("Controls depend on your keyboard, gamepad and camera settings. The in-game guide shows your current bindings."))
	elif PadInput.active == "pad":
		html += WikiCatalog.paragraph(RemakeText.t("Open the game wheel with %s. Choose Help for the last hint or Guide to browse all lessons.") % game_wheel_binding(direct))
	else:
		html += WikiCatalog.paragraph(RemakeText.t("Open help: %s") % help_binding())
	var source := pages(id)
	if not source.is_empty():
		html += WikiCatalog.heading(RemakeText.t("Classic edition reference"))
		html += WikiCatalog.paragraph(RemakeText.t("These original pages describe classic mouse and keyboard controls. Use the guidance above for current settings and gamepad controls."))
		for page: Dictionary in source:
			html += WikiCatalog.heading(String(page.get("head", "")))
			for paragraph in String(page.text).split("\n\n", false):
				html += WikiCatalog.paragraph(paragraph.strip_edges())
	return html
