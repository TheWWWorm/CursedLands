extends Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func _ready() -> void:
	check("nalo" in ArenaCommanders.choices(), "Odalisque is selectable in base autochess")
	check("nalo" in ArenaCommanders.choices(true), "Odalisque is selectable with LiA")
	check(ArenaCommanders.valid("nalo",false) == "nalo", "native commander identity survives validation")
	check(ArenaCommanders.prototype("nalo") == "human hadagan pretty", "commander uses the original Odalisque prototype")
	for row in [["en","Odalisque"],["ru","Наложница"],["de","Odalisque"]]:
		RemakeText.lang = row[0]
		check(ArenaCommanders.title("nalo") == row[1], "original localized name in " + row[0])
	var run := ArenaTournamentRun.new(); run.auto_save = false; run.begin(7191); run.commander = "nalo"
	var restored := ArenaTournamentRun.new(); restored.auto_save = false
	check(restored.restore(run.snapshot()) and restored.commander == "nalo", "commander persists through save/reload")
	var portrait := ArenaCommanderPortrait.new(); add_child(portrait); portrait.show_character("nalo")
	check(portrait.face != null and portrait.model != null, "original detailed head creates the commander bust")
	if portrait.face:
		for key in ["expression_smile_tex","expression_frown_tex"]:
			var tex: Texture2D = portrait.face.get_shader_parameter(key)
			check(tex != null and tex != portrait.face.albedo_texture, "authored " + key + " is present")
		portrait.set_result(0,"win",false)
		# Immediate presentation is deliberately neutral; real reactions use
		# the same interpolation as every other commander.
		portrait.set_result(0,"win-animated",true); portrait._advance_expression(1.0)
		check(portrait.face.get_shader_parameter("expression_weights") == Vector2.RIGHT, "victory selects the native smile")
		portrait.set_result(1,"loss",true); portrait._advance_expression(1.0)
		check(portrait.face.get_shader_parameter("expression_weights") == Vector2.DOWN, "defeat selects the native frown")
	portrait.free()
	print("ARENA_ODALISQUE ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
