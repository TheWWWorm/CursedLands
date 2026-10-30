class_name MenuMultiplayerBoard
extends RefCounted
## Lost in Astral's signpost (menus.res "unmoco2") replaces the original's
## Multiplayer board with a bare skull, and its menus.reg leaves that click
## area empty (0, 0, 0, 0). The remake's LiA co-op restores the board in the
## original's middle place: the expansion's own Authors board geometry and
## stone, its painted caption cleared, under a localized "Multiplayer" caption.
## The base game keeps its own board and label artwork untouched.

const PART := "button03_multiplayer"
## The base game's board part labels ("but03").
const LABEL := "but03"
## The board whose shape and stone are reused (button06_credits, "АВТОРЫ").
const DONOR := "button06_credits"
## The base game's menus.reg [MainMenu] Multiplayer rectangle (800×600). LiA
## keeps the same bones (unmoco2.bon) and hover clip (unmoco2.anm) for it.
const REG_RECT := Rect2(354, 265, 141, 43)
## The donor's caption strip in the 256² skin (mainmenu00): its painted
## letters, and the stone at the strip's left that replaces them.
const LETTERS := Rect2i(166, 215, 59, 31)
const STONE_X := Vector2i(140, 165)
## The caption face in the donor mesh's space: centre, the lettering's largest
## size (m) and the colours of the painted captions.
const FACE := Vector3(0.0, -0.045, 0.148)
const TEXT_SIZE := Vector2(0.74, 0.135)
const INK := Color(0.74, 0.71, 0.62)
const OUTLINE := Color(0.10, 0.08, 0.06)
const CACHE := &"menu_multiplayer_skin"
const NAME := "MultiplayerCaption"


## The edition's signpost has no Multiplayer board (LiA's empty click area).
static func needed() -> bool:
	if not GameData.menus or not GameData.menus.has("menus.reg"):
		return false
	var v: Array = EIRegFile.parse(GameData.menus.read("menus.reg")).get("MainMenu", {}).get("Multiplayer", [])
	return v.size() != 4 or (int(v[0]) == int(v[2]) and int(v[1]) == int(v[3]))


## Replaces the skull of a built "unmoco2" figure (signpost or interface
## board) with the Multiplayer board. `lit`: the caption takes the scene's
## lighting like the stone (the 3D menu); interface boards are unshaded.
static func install(figure: Node3D, lit: bool) -> bool:
	var node := figure.find_child(PART, true, false) as Node3D
	if node == null or not needed():
		return false
	var model := EIFigure.get_model("unmoco2")
	var donor: Dictionary = model.get("parts", {}).get(DONOR, {})
	var skull: MeshInstance3D = null
	for child in node.get_children():
		if child is MeshInstance3D:
			skull = child
	if donor.is_empty() or skull == null:
		return false
	skull.mesh = EIFigure.build_mesh(donor, Vector3(0.5, 0.5, 0.5))
	var material: Material = skull.material_override.duplicate() if skull.material_override else EIFigure.material_for("mainmenu00").duplicate()
	var texture := MenuCaptions.enlarged(skin())
	if material is StandardMaterial3D: material.albedo_texture = texture
	elif material is ShaderMaterial: material.set_shader_parameter("albedo_tex", texture)
	skull.material_override = material
	# LiA's blank label plane belonged to the skull.
	var label := node.find_child(LABEL, false, false)
	if label is Node3D:
		label.visible = false
	node.add_child(caption(lit))
	return true


## The native skin with the donor's painted letters replaced by the stone at
## the strip's left, row by row (keeping the strip's bevel and shading).
static func skin() -> Texture2D:
	var native := GameData.get_texture("mainmenu00")
	if native == null:
		return null
	if native.has_meta(CACHE):
		return native.get_meta(CACHE)
	var image := native.get_image()
	if image == null or image.is_empty():
		return native
	image = image.duplicate() as Image
	if image.is_compressed(): image.decompress()
	image.clear_mipmaps()
	var k := image.get_width() / 256   # HD texture packs keep the 256² layout
	var span := STONE_X.y - STONE_X.x
	for y in range(LETTERS.position.y * k, LETTERS.end.y * k):
		for x in range(LETTERS.position.x * k, LETTERS.end.x * k):
			# Mirror back and forth over the stone columns (no hard seam).
			var d := x - LETTERS.position.x * k
			var period := 2 * span * k
			var m := d % period
			var source := STONE_X.y * k - 1 - m if m < span * k else STONE_X.x * k + (m - span * k)
			image.set_pixel(x, y, image.get_pixel(source, y))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	native.set_meta(CACHE, texture)
	return texture


## The localized caption: a distance-field font stays sharp at every size.
static func caption(lit: bool) -> Label3D:
	var text := RemakeText.t("Multiplayer").to_upper()
	var label := Label3D.new()
	label.name = NAME
	var base := Interface800.font()
	var font: Font = base.duplicate() if base else null
	if font is FontFile or font is SystemFont:
		font.set("multichannel_signed_distance_field", true)
		font.set("msdf_pixel_range", 16)
	var variation := FontVariation.new()
	variation.base_font = font
	variation.variation_embolden = 0.55
	variation.spacing_glyph = 2
	label.font = variation
	label.font_size = 64
	label.outline_size = 14
	label.text = text
	label.modulate = INK
	label.outline_modulate = OUTLINE
	label.shaded = lit
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var size := variation.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
	size.y = variation.get_height(label.font_size)
	label.pixel_size = minf(TEXT_SIZE.x / maxf(size.x + label.outline_size, 1.0), TEXT_SIZE.y / maxf(size.y, 1.0))
	label.position = FACE
	return label
