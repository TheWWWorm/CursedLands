extends Node
## Cut content: human skins/portraits that no prototype's "skin" index selects
## and inventory figures that no item record's texture index selects
## (community report 2026-10-27; Atm's A3D-History list of unused female
## faces 01, 04, 06, 13, 17, 18). Their wiki pages preview the skin on a
## placed character of the same figure and the item model with its texture.
var checks := 0
var failures := 0
const FACES := {"unhufe_01": true, "unhufe_04": true, "unhufe_06": false, "unhufe_13": true,
	"unhufe_17": false, "unhufe_18": true}
const TEXTURED := ["initqu0item", "initqu1item", "initqi22item", "initqi23item", "initqi24item", "initqi25item",
	"initqi30item", "initqi31item", "initqi32item", "initqi33item", "initqi34item", "initqi35item",
	"initqi36item", "initqi37item"]
const UNTEXTURED := ["initqi4item", "initqi6item", "initqi7item", "initlitr1item", "initlitr2item",
	"initlitr3item", "initlitr5item", "initlitr6item"]

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)

func albedo_hashes(root: Node) -> Array:
	var out := []
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi.material_override if mi.material_override else mi.get_active_material(0)
		var tex: Texture2D = null
		if m is StandardMaterial3D: tex = (m as StandardMaterial3D).albedo_texture
		elif m is ShaderMaterial: tex = (m as ShaderMaterial).get_shader_parameter("albedo_tex")
		if tex: out.append(hash(tex.get_image().get_data()))
	out.sort()
	return out

func _ready() -> void:
	var c: WikiCatalog = WikiSource.new().read(func(): var x := WikiCatalog.new(); x.rebuild(); return x)
	var cut := c.cut
	check(cut.faces.keys() == FACES.keys(), "unused faces: " + str(cut.faces.keys()))
	for id: String in cut.faces:
		var info: Dictionary = cut.faces[id]
		check(FACES.get(id) == info.portrait, id + " portrait flag")
		var selected := GameData.db.table("monster_prototypes").any(func(r: Dictionary) -> bool:
			return String(GameData.db.find("race_models", String(r.get("base_race", ""))).get("mask", "")).to_lower() == info.mask \
				and int(r.get("skin", 0)) == info.skin)
		check(not selected, id + " is selected by no prototype")
		check(c.entries.has("cut/face/" + id) and c.entries["cut/face/" + id].kind == "cut_face", id + " has a page")
		var page := c.page("cut/face/" + id)
		var preview: Dictionary = page.get("preview", {})
		check(preview.get("kind") == "creature" and preview.get("appearance", {}).get("skin") == info.skin \
			and cut.placed(String(preview.get("value", ""))), id + " previews its skin on a placed character")
		check(String(page.html).contains(RemakeText.t("A matching portrait is in the archives as well.") if info.portrait \
			else RemakeText.t("There is no matching portrait.")), id + " page states the portrait")
	# The skin reaches the composed body texture.
	var proto: String = cut.faces.values()[0].prototype if not cut.faces.is_empty() else ""
	var looks := {}
	for skin in [null, 1, 4]:
		var info := {"prototype": proto}
		if skin != null: info.skin = skin
		var model := EIUnitModel.create(info, true)
		check(model != null, "model for skin %s" % skin)
		if model == null: continue
		add_child(model)
		looks[skin] = albedo_hashes(model)
		model.free()
	check(not looks.get(1, []).is_empty() and looks.get(1) != looks.get(null) and looks.get(4) != looks.get(1),
		"the skin override changes the body texture")
	var doll := Paperdoll.new()
	add_child(doll)
	doll.show_info({"prototype": proto, "skin": 1})
	var dressed := albedo_hashes(doll._model) if doll._model else []
	doll.show_info({"prototype": proto, "skin": 4})
	check(not dressed.is_empty() and dressed == looks.get(1) and albedo_hashes(doll._model) == looks.get(4),
		"the paperdoll rebuilds for a different skin")
	doll.free()

	check(cut.item_models.keys() == TEXTURED.slice(0, 2) + UNTEXTURED.slice(0, 3) + TEXTURED.slice(2) + UNTEXTURED.slice(3),
		"unused item models: " + str(cut.item_models.keys()))
	for model: String in TEXTURED + UNTEXTURED:
		var key := "cut/item/" + model
		check(c.entries.has(key) and c.entries[key].kind == "cut_item_model", model + " has a page")
		if not c.entries.has(key): continue
		var title: String = c.entries[key].title
		check(not title.contains("init") and not title.contains("item0"), model + " title is not an ID: " + title)
		var preview: Dictionary = c.page(key).get("preview", {})
		if model in TEXTURED:
			check(preview.get("kind") == "item" and preview.get("look", {}) == {"model": model, "texture": cut.item_models[model].texture},
				model + " previews its model and texture")
			var view := ItemView.new()
			view.camp = true
			add_child(view)
			view.look_override = preview.look
			view.show_item("")
			check(view._model != null and not view._model.find_children("*", "MeshInstance3D", true, false).is_empty(),
				model + " model builds from the look override")
			view.free()
		else:
			check(preview.is_empty() and String(c.page(key).html).contains(RemakeText.t("It has no texture, so it cannot be shown.")),
				model + " explains that it has no texture")
	var plain := ItemView.new()
	add_child(plain)
	plain.show_item("")
	check(plain._model == null, "an item view without an item or override stays empty")
	plain.free()

	var overview := String(c.page("cut/overview").html)
	for section in ["Unused faces", "Unused item models"]:
		check(overview.contains(RemakeText.t(section)), "overview lists " + section)
	check(overview.contains("cut/face/unhufe_13") and overview.contains("cut/item/initqi36item"), "overview links the pages")
	for lang: String in ["ru", "de"]:
		RemakeText.lang = lang
		check(cut.face_title("unhufe_01") != "Unused female face 1" and cut.face_title("unhufe_01").contains("1"), lang + " face title")
		check(cut.item_model_title("initqu0item") == RemakeText.TEXTS["Compass"][0 if lang == "ru" else 1], lang + " item title")
		check(not cut.item_model_title("initqi4item").begins_with("Unused"), lang + " generic item title")
	RemakeText.lang = "en"
	print("WIKI_CUT_FACES_ITEMS ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
