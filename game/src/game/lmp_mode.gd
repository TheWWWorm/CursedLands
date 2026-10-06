class_name LmpMode
extends RefCounted
## the original's own multiplayer game ("LMP"), next to the remake's co-op
## campaign. A server plays one base (a "brief" zone of textsLmp.res
## map-LMP.txt: bz1mpg Gipat village, bz2mpg Ingos town, bz3mpg Suslanger's
## Last Shelter, bz4mpg the Great Mage's cave) and one quest at a time; the
## base's only exit leads to the pseudo-zone "MPGame1", the zone of the quest
## taken (maps/<q>.mq "<q>/map.txt": the zone's .mpr with its -LMP .mob, and
## the quest's own <q>.mob merged in), whose exit leads back to the base.
## The whole game runs on res/databaseLMP.res.
## See.

## The pseudo-zone a base's exit names (map-LMP.txt "#exit 1 / MPGame1 1").
const GAME_ZONE := "mpgame1"
## Fixed native GS spelling (57f190, literal), independent
## the archive/map identifiers which use lowercase lookup keys.
const GAME_ZONE_VAR := "z.MPGame1"
## The four bases in textsLmp.res «lmp_allod_name_0..3» order.
const BASES := ["bz1mpg", "bz2mpg", "bz3mpg", "bz4mpg"]


## The base's name: textsLmp.res «string lmp_allod_name_<n>».
static func base_title(base: String) -> String:
	var i := BASES.find(base.to_lower())
	var t := GameData.text("string lmp_allod_name_%d" % i).strip_edges() if i >= 0 else ""
	return t if t else base


## The quests played from `base`: every quest map whose zone exits to it, in
## file name order (z3q1 .. z9q3 for bz1mpg: 12; bz2mpg 6; bz3mpg 7; bz4mpg 3).
static func quests_of(campaign: CampaignMap, base: String) -> Array:
	var out := []
	for id: String in campaign.lmp_zones:
		var z: Dictionary = campaign.lmp_zones[id]
		if String(z.get("type", "")) != "game" or SideQuests.get_quest(id).is_empty():
			continue
		for n in z.get("exits", {}):
			if String(z.exits[n].get("to", "")) == base.to_lower():
				out.append(id)
				break
	out.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return out


## The quests a base's giver offers (the original
## on a new server and after a quest is canceled or completed): the base's
## quests (: every.mq, its base by its zone — zone2..zone9 the
## first, zone12 / zone13 the second, ...) grouped by the zone they play in,
## one taken at random from each group (% count), the last quest
## taken left out of a group that has others.
static func offers(campaign: CampaignMap, base: String, last := "") -> Array:
	var groups := {}
	for q: String in quests_of(campaign, base):
		var mpr := String(SideQuests.get_quest(q).get("mpr", q))
		groups.get_or_add(mpr, []).append(q)
	var keys := groups.keys()
	keys.sort()
	var out := []
	for k: String in keys:
		var g: Array = groups[k]
		if g.size() > 1:
			g.erase(last.to_lower())
		out.append(g[randi() % g.size()])
	return out


## Who gives a quest: the speaker of its offer briefing <q>_1.
## The giver's topic is the GS var b.<giver>.<q>_<n> (sets it 1).
static func giver(q: String) -> String:
	return speaker("briefing %s_1" % q)


## The base's trader (constructor record id, its GS var) and intro speakers:
##  by the base index — b.smith.constr_1 / b.Shopper.constr_3
## / b.kuzn.constr_4 / b.golem.constr_5 = 1, and the conversations intro_<n>q /
## intro_<n>k as b.<speaker>.<name> raised to at least 1.
const TRADERS := {"bz1mpg": "b.smith.constr_1", "bz2mpg": "b.Shopper.constr_3",
	"bz3mpg": "b.kuzn.constr_4", "bz4mpg": "b.golem.constr_5"}


## Host, a new multiplayer game: the base's GS vars.
static func base_vars(st: CampaignState, base: String) -> void:
	var i := BASES.find(base.to_lower())
	if i < 0:
		return
	st.set_var(0, TRADERS[BASES[i]], 1.0)
	for x in ["q", "k"]:
		var name := "intro_%d%s" % [i + 1, x]
		var key := "b.%s.%s" % [speaker("briefing " + name), name]
		st.set_var(0, key, maxf(st.get_var(0, key), 1.0))
	zone_var(st, "")


## GS var "z.MPGame1": 1 — the base exit closed (Session._arm_exit
## Game._over_open_exit) — while the server has no quest, deleted once one is
## taken.
static func zone_var(st: CampaignState, quest: String) -> void:
	if quest.is_empty():
		st.set_var(0, GAME_ZONE_VAR, 1.0)
	else:
		st.del_var(0, GAME_ZONE_VAR)


static func exit_var(target: String) -> String:
	return GAME_ZONE_VAR if target.to_lower() == GAME_ZONE else "z." + target


## The speaker of a conversation: its first "#show" actor other than "Hero"
## "elder" when none ("b.elder.").
static func speaker(text_key: String) -> String:
	var t := GameData.text(text_key)
	if t.is_empty():
		t = SideQuests.text(text_key)
	for l in t.split("\n"):
		var w := l.strip_edges().split(" ", false)
		if w.size() > 1 and w[0].to_lower() == "#show" and w[1].nocasecmp_to("Hero") != 0:
			# 57fc90 / 4dfcb0 copy the original token; 57fde0 concatenates
			# it into the case-sensitive GS key without normalizing it.
			return w[1]
	return "elder"


## A quest's title (the quest map's "quest <q>" first line).
static func quest_title(id: String) -> String:
	var q := SideQuests.get_quest(id)
	return String(q.get("title", id)) if not q.is_empty() else id


## The standalone expansion retains old LMP archives, but has no supported
## original multiplayer campaign. Their presence alone is not sufficient.
static func available() -> bool:
	return GameData.campaign_id != CampaignProfile.ASTRAL \
		and GameData.texts_lmp != null and GameData.texts_lmp.has("map-lmp.txt") \
		and GameFiles.exists(GameData.res_path("databaselmp.res"))


static func unavailable_reason() -> String:
	if GameData.campaign_id == CampaignProfile.ASTRAL:
		return RemakeText.t("Lost in Astral does not include the original multiplayer campaign.")
	return RemakeText.t("Needs the multiplayer files of the original game (databaseLMP.res), missing from this installation.")
