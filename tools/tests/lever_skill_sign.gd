extends Node
## Skill-locked levers and a negative Use value (Dex − 25 + Use, below zero for
## a character with Dex < 25 and no Use skill). The original compares the lock
## level unsigned (0x522A80), so such a character opened every
## skill lock. Cursed Lands compares signed, as the Rebirth edition does; a
## lock of 0 still opens for anyone. Controlled world with the real LeverSystem
## and the real Use value of a hero record.
class QuietSession extends Session:
	func broadcast(_e: Dictionary) -> void: pass

var checks := 0
var failures: Array = []
const ID := 101

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func _ready() -> void:
	GameData.options.merge({"smile_faces":0, "show_tutorial":0}, true)
	var s := QuietSession.new(); add_child(s); s.set_physics_process(false)
	var w := GameWorld.new(); w.session = s; s.world = w; add_child(w)
	w.nav = NavGrid.new(); w.presentation = false
	w.lever_sys = LeverSystem.new(w)
	var opens := func(science: Array, use: float, quest := []) -> bool:
		w.levers[ID] = {"state":0, "states":2, "cycled":0, "science":science, "enabled":true}
		return w.lever_sys.science_ok(ID, use, quest)
	for use in [-1.0, -5.0, -24.0, -0.6]:
		check(not opens.call([1, 0, 22], use), "Use %s does not open a level 22 lock" % use)
		check(not opens.call([5, 0, 1], use), "Use %s does not open a level 1 lock" % use)
		check(opens.call([1, 0, 0], use), "Use %s opens a level 0 lock" % use)
		check(opens.call([1, 0, -3], use) == (roundi(use) >= -3), "Use %s against a negative lock is signed" % use)
	# Positive values keep the nearest-even float32 rounding.
	check(not opens.call([1, 0, 22], 21.49), "21.49 rounds to 21")
	check(opens.call([1, 0, 22], 21.5), "21.5 rounds to 22")
	check(not opens.call([1, 0, 23], 22.5), "22.5 rounds to 22 (nearest even)")
	check(opens.call([1, 0, 22], 40.0), "a higher Use value opens")
	check(not opens.call([0, 0, 22], 40.0) and not opens.call([8, 0, 0], 40.0), "script-only and key-only locks ignore the skill")
	# A quest key still opens a key lock for a character with a negative value.
	var quest := ""; var sid := 0
	for item: Dictionary in GameData.db.table("quest_items"):
		if int(item.get("script_id", 0)) > 0: quest = String(item.name); sid = int(item.script_id); break
	check(sid > 0, "a quest key exists")
	check(opens.call([9, sid, 22], -5.0, [quest]), "the matching quest key opens despite a negative Use value")
	check(not opens.call([9, sid + 100000, 22], -5.0, [quest]), "another key does not")
	# The real Use value of a weak character.
	var hero := GameUnit.new(); hero.world = w; w.add_child(hero)
	hero.set_meta("hero", {"skills":{"science":0}}); hero.stats.dex = 20.0
	check(is_equal_approx(Session.steal_value(hero), -5.0), "Dex 20 without Use skill has Use value -5")
	check(not opens.call([1, 0, 22], Session.steal_value(hero)), "that character cannot open a level 22 lock")
	hero.get_meta("hero").skills.science = 3
	check(opens.call([1, 0, -2], Session.steal_value(hero)) and not opens.call([1, 0, 1], Session.steal_value(hero)), "Use value -2 compares signed")
	w.free(); s.free()
	print("LEVER_SKILL_SIGN ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
