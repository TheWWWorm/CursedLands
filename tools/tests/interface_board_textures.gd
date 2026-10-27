extends Node
## Interface boards texture each part by its figure texture group, as the
## original: group 2 is the labels sheet. The Esc signpost's foot
## (unmoco1 "coloumndetls") is a group-2 part without a label name; drawn
## with the stone sheet its label UVs smeared dark red stripes under
## "Exit to main menu" (community report 2026-10-27).
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", message)

func part_materials(board: InterfaceBoard) -> Dictionary:
	var out := {}
	for mi: MeshInstance3D in board._fig.find_children("*", "MeshInstance3D", true, false):
		out[String(mi.get_parent().name)] = mi.material_override
	return out

func albedo(m: Material) -> Texture2D:
	if m is StandardMaterial3D: return (m as StandardMaterial3D).albedo_texture
	if m is ShaderMaterial: return (m as ShaderMaterial).get_shader_parameter("albedo_tex")
	return null

func _ready() -> void:
	check(InterfaceBoard.is_label_part("coloumndetls", {"texture_group": 2}), "group 2 is a labels part")
	check(not InterfaceBoard.is_label_part("savelabel", {"texture_group": 1}), "the figure's group decides over the name")
	check(InterfaceBoard.is_label_part("savelabel", {}) and InterfaceBoard.is_label_part("but03", {}) \
		and not InterfaceBoard.is_label_part("button01", {}) and not InterfaceBoard.is_label_part("load", {}), "name rule without figure data")
	var cases := [["unmoco1", "escmenu00", "escmenu00labels"], ["unmoco2", "mainmenu00", "mainmenu00labels"]]
	for c: Array in cases:
		var board := InterfaceBoard.create(c[0], c[1], c[2], PackedStringArray(), PI * 0.5, Vector3(400, 300, 4.8))
		add_child(board)
		check(board._fig != null, c[0] + " board builds")
		if board._fig == null: continue
		var parts: Dictionary = EIFigure.get_model(c[0]).parts
		# Board sheets are the edge-enlarged originals (MenuCaptions).
		var stone := MenuCaptions.enlarged(GameData.get_texture(c[1]))
		var labels := MenuCaptions.enlarged(GameData.get_texture(c[2]))
		check(stone != null and labels != null and stone != labels, c[0] + " has distinct stone and labels sheets")
		var mats := part_materials(board)
		var groups := {1: 0, 2: 0}
		for part: String in mats:
			var group: int = parts[part].texture_group
			groups[group] = groups.get(group, 0) + 1
			var tex := albedo(mats[part])
			check(tex == (labels if group == 2 else stone), "%s %s (group %d) uses the %s sheet" % [c[0], part, group, "labels" if group == 2 else "stone"])
		check(groups[1] >= 6 and groups[2] >= 6, c[0] + " has stone and label parts: " + str(groups))
		board.free()
	# The reported part: the foot of the Esc signpost.
	var sp := EscSignpost.new()
	add_child(sp)
	await get_tree().process_frame
	var mats := part_materials(sp)
	check(mats.has("coloumndetls") and mats.has("exit2mainmenulabel"), "Esc signpost has its foot and captions")
	if mats.has("coloumndetls"):
		check(albedo(mats.coloumndetls) == albedo(mats.exit2mainmenulabel) and albedo(mats.coloumndetls) != albedo(mats.escmenu00),
			"the signpost's foot is drawn from the labels sheet")
	sp.free()
	print("INTERFACE_BOARD_TEXTURES ", checks, " checks ", failures, " failures")
	get_tree().quit(1 if failures else 0)
