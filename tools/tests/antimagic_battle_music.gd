extends Node
## A cast counts as fighting for the battle music when its spell prototype type
## is below 9 (the damage spells), as in the original combat-state test
## (0x54B580). The original also counted type 0x1A, Antimagic, so dispelling
## started battle music. Cursed Lands leaves Antimagic out, as the Rebirth
## edition does. Real spell prototype table of each campaign.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func casting(spell: String) -> bool:
	var u := GameUnit.new()
	u.order = {"type":"cast", "spell":spell}
	var hostile := GameSound._hostile_act(u)
	u.free()
	return hostile

func _ready() -> void:
	var rows: Array = GameData.db.table("spell_prototypes")
	check(rows.size() > 26, "spell prototype table loaded")
	var antimagic := -1
	for i in rows.size():
		var code := String(rows[i].get("code", "")).to_lower()
		if code.is_empty(): continue
		if code == "antimagic": antimagic = i
		check(casting(code + "{}") == (i < 9), "%s (type %d) %s battle music" % [code, i, "starts" if i < 9 else "does not start"])
	check(antimagic == 0x1A, "Antimagic is the original's type 0x1A")
	check(not casting("antimagic{}") and not casting("antimagic{power}"), "casting Antimagic does not start battle music")
	check(casting("fireball{}") and casting("arrow{}"), "damage spells still start it")
	var u := GameUnit.new()
	u.order = {"type":"attack"}
	check(GameSound._hostile_act(u), "an attack order still starts it")
	u.order = {}
	check(not GameSound._hostile_act(u), "an idle unit does not")
	u.free()
	print("ANTIMAGIC_BATTLE_MUSIC ", checks, " checks ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
