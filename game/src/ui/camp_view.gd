class_name CampView
extends Control
## The camp / settlement screen in the original's stone-frame look (the original
## ), drawn at the original's 800×600 coordinates scaled to the window.
## Modes (the original's screen widgets):
## - "weapons" (dressing):
##   - top row: eight 100×100 cells from textures.res
##     "campslots": the four weapon slots (crossed swords frame, UV
##     14,14-114,114) and four belt slots (helmet frame, UV 142,14-242,114).
##      puts the hero's weapons (hero)
##     the left cell rightwards and its belt (hero: the
##     stacked quick items, camphelp 3 "Taking potions and wands") from the
##     right cell leftwards;
##   - the paperdoll panel 200..600 × 100..500 from "camp1".."camp4" (UV
##     28,28-228,228 each) with the seven armour slots centred at (250,150)
##     (250,300) (250,450) (550,150) (550,350) (550,450) (550,250) (table
## ) = helm, cuirass, leggings, shirt, pants, boots
##     gloves (armour type_id order hl pl lg sh pt bt gl), and the hero's figure
##     on the pedestal painted into "camp3" / "camp4" with its turn arrows.
##     Holding an arrow turns at 2 rad/s; release stops it.
## - "itemtrade" / "spelltrade" (draw):
##   - the trader's goods row at the top (with
##     param 1: y 0..100, "Inventory02"). Filters are mode 2
##     (items, tips 21000-21005, icon U + 0) or mode 1 (spells, tips
##     21200-21205, icon U + 84);
##   - the centre 200..600 × 100..500 tiled from "trade1".."trade4": 100×100
##     cells, UV origin alternating 28 / 128; the first row uses trade1 / trade2,
##     the rest trade3 / trade4;
##   - two 8-item piles, each shown with its count and price at the cell's
##     bottom (x+15..85, y+65..85). The upper pile (centres 250+100i, 150+100j)
##     is priced with deal mode 4 = buy (spells 0); the lower one (centres
##     250+100i, 350+100j) with mode 5 = sell (spells 1), Items.Deal.
## - "repair" (draw): the centre tiled
##   "repair1".."repair4" as above, one 16-item pile (centres 250+100i,
##   150+100j) priced with deal mode 8 = repair. The mode switch
##   shows the item goods row here and in the item constructor, the
##   spell goods row in the spell screens; prices per row come
##    (_row_accepts).
## - "itemconstr" (draw): the centre
##   "constritem1".."constritem4" (200×200 quadrants, UV 28,28-228,228) and
##   the slots the draw sorts the pile into: a ready (deconstructable) item
##   at (250,300), the blueprint at (350,250), a
##   spell at (350,350) and up to 8 materials at x 450 / 550
##   y 150..450 (four per column). Blueprint + material build
##   the item (Session._construct, missing pieces bought from the trader); a
##   ready item alone is taken apart (Session._deconstruct). Approx.: the
##   spell slot is drawn but not used (wands are built without a spell).
## - "spellconstr" (draw): the centre
##   "constrspell1".."constrspell4" as the item constructor; the ready spell
##   at (250,300) (CItemSpell), its keystone at (350,300)
##   (loot kind 2 / 3) and up to 8 runes at x 450 / 550, y
##   150..450 (kind 2 / 4); the draw sums the complexity and
##   stamina it shows. The remake's heroes keep their spells outside the bag,
##   so here the bag row also lists the hero's known spells (the original's
##   spell items); runes put in are added one by one with the "enchant"
##   command. Approx.: runes already in a spell cannot be taken out again.
## - "spells" (Skills/Spells, tip 20101, tutorial camp_skills): the top row
##   holds the hero's spells (camphelp 1, up to eight), the left widget the
##   attributes (mode 1) and the centre the skills widget (
##   _draw_skills; a click raises a skill or learns an ability at once).
## - All modes: the hero's bag row 500..600 (
##   "Inventory01"): seven cells at x 50..750, end caps, scroll buttons (tip
##   20400) and six filter buttons (mode 0, tips 21100-21105
##   icons at U + 168).
## textures.res images come out of EIMmp upside down against the original's UVs, so
## they are flipped once here. Every slot shows its item's 3D model.
## Side areas:
## - backdrop (draw, texture "campinfo"): the
##   stone tile UV 14,14-114,114 over 0,100-800,500 (8×4), per 200-wide
##   column bevel strips left / right (21 wide, UV 254,76-233,176 mirrored)
##   and top / bottom (30 high, UV 254,2-154,32 halves), and dividers 40 high
##   (UV 254,34-154,74) at y 380 in the left and right columns and at y 280 in
##   the 200..400 column; the centre art of each mode covers its part;
## - left, modes 0 / 1: the hero widget (build
##   draw) — the name box (campinfo UV 145,76-231,136, the left
##   half mirrored) with the hero-cycle arrows (8,125 / 176,125, 16×20), the
##   name (font 1, white) and rows of font 0, 15 px apart
##   (20,165): mode 0 "Armor:" and Head / Arms / Body / Legs (:
##   the largest of damage types 0..5 of the summed layers, "%.1f" right),
##   the current weapon's Attack / Defense / Damage, Encumbrance "%d/%d"
##    with "Overload!" in red, then "Knowledge of magic
##   schools"; mode 1 Strength / Dexterity / Intelligence, Health / Stamina /
##   Actions / Experience and Encumbrance;
## - left, modes 2..6: the info widget (at 0,100, 200×300)
##   with the mode's help (: "camphelp <id>", title font 0 white
##   at 15,10-185,25 two lines, body 30 lower, 16 lines, centred
##   word-wrapped): item shop 100, spell shop 101, repair 104, item / spell
##   constructor 102 / 103 until something is set, then the result's info;
## - right: the info widget (600,100): the hovered item's info
##   (: name, "Type:", then per kind; weapons and
##   armour "Material: %s x %d", "Weight:", "Durability:", "Damage: %d-%d
##   %s" / "Actions:" / "Attack change:" / "Defense change:" or "Range:", or
##   "Armor:", and the description, four lines centred) or the hovered
##   area's camphelp;
## - deal widget (0,400-200,500): "Your money: %d" (mode 1
##   "Your experience:") at 0,10-200,30 font 1 white centred; with a deal its
##   label (camp_item_trade, camp_repair_all, camp_item_constr, …) at
##   0,30-200,50 and "%+d" of minus the total (or "0") at 0,50-200,70; ✓
##   (12,450, tip 20200) is dimmed to 0.5 unless the deal is possible and
##   affordable, ✗ (148,450, tip 20201) unless there is something to cancel;
##   both are hidden in mode 0 without the item group or with i.noconstr;
## - mode title: strings mode_weapons … at 600,410-800,430
##   font 1 white centred; the eight mode buttons at colour 0.5, the current
##   one at 1.0.
## - camphelp per area (the widgets' hit tests): top row 2 / 3
##   (spells 1), armour 4 + type, rows 22 / 24 / 23
## piles 11 / 12 and 17 / 18, item
##   constructor 13 / 14 / 16 / 15, spell constructor 19 / 20
##   21 and the limit lines 26 / 27, repair 25
## Approx.:
## - item info: see _item_info; the enchanted items' pulsing colour;
## - the remake's action buttons (equip, put on the belt, learn, enchant…)
##   sit at the bottom of the right widget for the clicked item;
## - no drag and drop: a click selects an item, and in the trade screens it
##   also moves the item between the goods / bag and its pile;
## - which filter button is lit when a screen opens is not traced (the bag
##   starts on "all", the trader's row on "ready-made" or else the first
##   filter with goods).

signal picked(id: String, where: String)
## Yes pressed in a trade screen: items to buy from the trader, items to sell.
signal deal(buy: Array, sell: Array)
## Yes pressed in the repair screen.
signal repair(items: Array)
## Yes pressed in the item constructor: build (bp + material) or take apart;
## also the skills screen's train / perk and ✓'s repair of the worn items.
signal construct(cmd: Dictionary)
## The hero widget's arrows (hot areas 0,125-30,145 and
## 170,125-200,145): -1 / +1 through the party.
signal hero_step(dir: int)
signal mode_changed(mode: String)

const MODES := ["weapons", "spells", "spelltrade", "spellconstr", "itemtrade", "itemconstr", "repair"]
## Mode titles (the strings array by mode index).
const MODE_TITLES := {"weapons": "mode_weapons", "spells": "mode_spells", "spelltrade": "mode_spelltrade",
	"spellconstr": "mode_spellconstr", "itemtrade": "mode_itemtrade", "itemconstr": "mode_itemconstr",
	"repair": "mode_itemrepair"}
## The left info widget's help per mode (
const MODE_HELP := {"spelltrade": 101, "itemtrade": 100, "repair": 104, "itemconstr": 102, "spellconstr": 103}
## camphelp ids of the mode buttons (: hot areas 4..11 → 105
## 106, 101, 103, 100, 102, 104, 107).
const BUTTON_HELP := {"weapons": 105, "spells": 106, "exit": 107, "itemtrade": 100, "spelltrade": 101,
	"itemconstr": 102, "spellconstr": 103, "repair": 104}
## an armour slot's camphelp is 4 + its type (hl pl lg sh pt bt gl).
const ARMOR_HELP := [4, 5, 6, 7, 8, 9, 10]   # helm, cuirass, leggings, shirt, pants, boots, gloves
const DIM := Color8(0x82, 0x82, 0x82)        # COLORREF
const RED := Color8(0xff, 0, 0)              # COLORREF 0xff
const HL_PARTS := [["skull", "head"], ["arms", "arms"], ["torso", "torso"], ["legs", "legs"]]
const TOP_CELL_UV := [Rect2(14, 14, 100, 100), Rect2(142, 14, 100, 100)]
const ARMOR_CENTERS := [Vector2(250, 150), Vector2(250, 300), Vector2(250, 450), Vector2(550, 150),
	Vector2(550, 350), Vector2(550, 450), Vector2(550, 250)]
##  areas 2 / 3, painted in camp3 / camp4 (no separate buttons).
const TURN_RECTS := [Rect2(300, 470, 30, 30), Rect2(470, 470, 30, 30)]
## angle += / -= 2 * seconds.
const TURN_SPEED := 2.0
const BAG_CELLS := 7
const PILE_CELLS := 8
const REPAIR_CELLS := 16
## Filter buttons (ids 2..7) relative to their row: rects and icon UVs (base;
##  adds U 168 for the bag, 84 for spells and 0 for items).
const FILTER_RECTS := [Rect2(0, 5, 30, 30), Rect2(0, 35, 30, 30), Rect2(0, 65, 30, 30),
	Rect2(770, 5, 30, 30), Rect2(770, 35, 30, 30), Rect2(770, 65, 30, 30)]
const FILTER_UV := [Rect2(2, 130, 40, 40), Rect2(2, 172, 40, 40), Rect2(2, 214, 40, 40),
	Rect2(44, 130, 40, 40), Rect2(44, 172, 40, 40), Rect2(44, 214, 40, 40)]
## Per filter set: icon U offset, first tip, filter kinds.
const FILTER_SETS := {
	"bag": [168, 21100, ["make", "runes", "ready", "loot", "quest", "all"]],
	"items": [0, 21000, ["bp_weapon", "bp_light", "bp_heavy", "potions", "materials", "ready"]],
	"spells": [84, 21200, ["elemental", "sense", "astral", "rune_basic", "rune_special", "ready_spell"]],
}

## The side panels' buttons (textures.res "campinfo", 40×30
## 40×40 sprites; rects in the 800×600 layout, UVs in the original's v-up order):
## mode buttons (tips 20100..20106, shown per the trader's groups as
## mode_offered), Exit (tip 20107) and the Accept / Cancel pair (tips 20200 /
## 20201, hidden in the dressing screen without the item group).
const SIDE_BUTTONS := {
	"weapons": [Rect2(620, 430, 40, 30), Rect2(2, 193, 40, 30), 20100],
	"spells": [Rect2(620, 460, 40, 30), Rect2(2, 224, 40, 30), 20101],
	"itemtrade": [Rect2(660, 430, 40, 30), Rect2(43, 193, 40, 30), 20102],
	"itemconstr": [Rect2(700, 430, 40, 30), Rect2(84, 193, 40, 30), 20103],
	"repair": [Rect2(740, 430, 40, 30), Rect2(125, 193, 40, 30), 20104],
	"spelltrade": [Rect2(660, 460, 40, 30), Rect2(43, 224, 40, 30), 20105],
	"spellconstr": [Rect2(700, 460, 40, 30), Rect2(84, 224, 40, 30), 20106],
	"exit": [Rect2(740, 460, 40, 30), Rect2(125, 224, 40, 30), 20107],
	"accept": [Rect2(12, 450, 40, 40), Rect2(165, 172, 40, 40), 20200],
	"cancel": [Rect2(148, 450, 40, 40), Rect2(165, 214, 40, 40), 20201],
}

## The Exit button (tip 20107) was pressed.
signal exit_pressed

var hud: GameHUD
var mode := "weapons"
var _side_hover := ""
## The open trader (script var "constr.current", Shops); 0 = the dressing screen only.
var shop_id := 0
## The remake's action buttons for the clicked item (InventoryPanel fills it),
## at the bottom of the right info widget.
var right_panel: VBoxContainer
var filter := 5
var scroll := 0
var shop_filter := 5
var shop_scroll := 0
var buy_pile: Array = []
var sell_pile: Array = []
var repair_pile: Array = []
var c_bp := ""       # item constructor: blueprint, material name, ready item
var c_mat := ""
var c_ready := ""
var s_spell := ""    # spell constructor: the hero's spell and runes to add
var s_runes: Array = []
var selected_id := ""
var selected_where := ""

var _tex := {}
var _doll: Paperdoll
var _turn_dir := 0   # Godot Y: left -1, right +1 (the original's camera Y points down).
var _views := {}   # slot key -> ItemView
## The left / right info widgets' models: draws the shown item
##  at (x + 100, y + 200), depth 3, size 120, mode 9 — the
## item at vertex colour 0.5, unturned, under the info text.
var _info_views: Array[ItemView] = []
var _hover_key := ""
var _ctrl := false
var _content := {}   # slot key -> [item id, where]
var _sig := ""
var _unit: GameUnit
var _tutorial: TutorialPanel
var _ready_done := false
var _overlay: Control
var _canvas: CanvasItem = self
## Hover: an item id, a camphelp id, or a [title, text] description.
var _hover_item := ""
var _hover_help := -1
var _hover_desc: Array = []
## Skills screen rows hit areas: [rect, cmd or {}, description [title, text]].
var _skill_rows: Array = []   # [rect, command, description, kind]
var _perk_scroll := 0    # known abilities
var _avail_scroll := 0   # available abilities
var _hold_cmd := {}      # the held skill row's command
var _hold_t := 0.0

## The camp screen's tutorial ids (slot 41,:
## the mode — 0 camp_weapons, 1 camp_skills, 2 camp_spell_trade, 3
## camp_spell_constr, 4 camp_item_trade, 5 camp_item_constr, 6 camp_repair).
## The mode switch (also run by the build) ends with
## (0): each mode's tutorial shows on its first visit. The remake
## (The remake's skills screen is the original's mode 1.)
const TUTORIALS := {"weapons": "camp_weapons", "spells": "camp_skills", "spelltrade": "camp_spell_trade",
	"spellconstr": "camp_spell_constr", "itemtrade": "camp_item_trade",
	"itemconstr": "camp_item_constr", "repair": "camp_repair"}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	for n in ["campslots", "camp1", "camp2", "camp3", "camp4", "inventory01", "inventory02",
			"trade1", "trade2", "trade3", "trade4", "repair1", "repair2", "repair3", "repair4",
			"constritem1", "constritem2", "constritem3", "constritem4",
			"constrspell1", "constrspell2", "constrspell3", "constrspell4", "campinfo"]:
		var img := GameData.load_image(n) if GameData.is_open() else null
		if img:
			img.flip_y()
			_tex[n] = ImageTexture.create_from_image(img)
	_doll = Paperdoll.new()
	add_child(_doll)
	for k in _slot_keys():
		var v := ItemView.new()
		v.camp = true
		add_child(v)
		_views[k] = v
	# The info widgets' item models (mode 9).
	for x0 in [0, 600]:
		var v := ItemView.new()
		v.camp = true
		v.modulate = Color(0.5, 0.5, 0.5)
		add_child(v)
		_info_views.append(v)
	# The item rows' counts and prices go over the item views (the original's text
	# surfaces are drawn after the 3D items).
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	right_panel = VBoxContainer.new()
	right_panel.alignment = BoxContainer.ALIGNMENT_END
	add_child(right_panel)
	right_panel.clip_contents = true
	_ready_done = true
	resized.connect(_layout)
	_tutorial = TutorialPanel.new()
	add_child(_tutorial)
	set_mode(mode)


func _slot_keys() -> Array:
	var out := []
	for i in 8:
		out.append("top%d" % i)
	for i in 7:
		out.append("armor%d" % i)
	for i in BAG_CELLS:
		out.append("bag%d" % i)
		out.append("shop%d" % i)
	for i in PILE_CELLS:
		out.append("buy%d" % i)
		out.append("sell%d" % i)
	for i in REPAIR_CELLS:
		out.append("rep%d" % i)
	for k in ["cready", "cbp", "cspell", "sready", "skey"]:
		out.append(k)
	for i in PILE_CELLS:
		out.append("cmat%d" % i)
		out.append("srune%d" % i)
	return out


func trading() -> bool:
	return mode in ["itemtrade", "spelltrade"]


## Screens with the trader's goods row at the top (the item shop group's row
## 0x7c is created with its trade, constructor and repair screens).
func shop_row() -> bool:
	return not mode in ["weapons", "spells"]


## The spell group's screens (flag): their goods row is the spell shop's.
func spell_shop() -> bool:
	return mode in ["spelltrade", "spellconstr"]


## the spell group (flag = record) and the item group
## (= record), overridden by GS vars i.offspellconstr
## i.onspellconstr / i.offitemconstr / i.onitemconstr = 1; i.noconstr = 1
## hides both constructor buttons (tips 20106 / 20103).
func spell_group() -> bool:
	return _group("spell", Shops.sells_spells(shop_id))


func item_group() -> bool:
	return _group("item", Shops.sells_items(shop_id))


func _group(g: String, v: bool) -> bool:
	if shop_id == 0 or hud == null:
		return false
	var st := hud.game.session.state
	if is_equal_approx(st.get_var(0, "i.off%sconstr" % g), 1.0):
		v = false
	if is_equal_approx(st.get_var(0, "i.on%sconstr" % g), 1.0):
		v = true
	return v


func mode_offered(m: String) -> bool:
	var noconstr := hud != null and is_equal_approx(hud.game.session.state.get_var(0, "i.noconstr"), 1.0)
	match m:
		"spelltrade": return spell_group()
		"spellconstr": return spell_group() and not noconstr
		"itemtrade", "repair": return item_group()
		"itemconstr": return item_group() and not noconstr
	return shop_id != 0


## The screen a trader opens : item trade (4), else
## spell trade (2), else dressing (0).
func first_mode() -> String:
	if item_group():
		return "itemtrade"
	if spell_group():
		return "spelltrade"
	return "weapons"


func set_mode(m: String) -> void:
	var changed := m != mode
	if changed:
		_turn_dir = 0
		buy_pile.clear()
		sell_pile.clear()
		repair_pile.clear()
		_clear_constr()
		shop_scroll = 0
	mode = m
	if changed and shop_row() and hud:
		# Start on the first filter with goods ("ready-made" when there are any).
		for f in [5, 0, 1, 2, 3, 4]:
			shop_filter = f
			if not shop_items().is_empty():
				break
	_doll.visible = mode == "weapons"
	for k in _views:
		_views[k].visible = _key_shown(k)
	_sig = ""
	if changed:
		_hover_item = ""
		if _views.has(_hover_key):
			_views[_hover_key].spin = false
		_hover_key = ""
		_hover_help = -1
		_hover_desc = []
		selected_id = ""
		selected_where = ""
	_update_total()
	if changed:
		mode_changed.emit(mode)
		if is_visible_in_tree():
			screen_tutorial()


##  for the current mode (`forced`: the H key).
func screen_tutorial(forced := false) -> void:
	if TUTORIALS.has(mode):
		_tutorial.show_screen(TUTORIALS[mode], forced)


func tutorial_visible() -> bool:
	return _tutorial != null and _tutorial.visible


func _key_shown(k: String) -> bool:
	if k.begins_with("bag"):
		return true
	if trading():
		return k.begins_with("shop") or k.begins_with("buy") or k.begins_with("sell")
	if mode == "repair":
		return k.begins_with("rep") or k.begins_with("shop")
	if mode == "itemconstr":
		return k.begins_with("c") or k.begins_with("shop")
	if mode == "spellconstr":
		return k.begins_with("shop") or k in ["sready", "skey"] or k.begins_with("srune")
	if mode == "spells":
		return k.begins_with("top")
	return k.begins_with("top") or k.begins_with("armor")


## Screen scale and origin of the 800×600 layout.
func _s() -> float:
	return minf(size.x / 800.0, size.y / 600.0)


func _o() -> Vector2:
	return (size - Vector2(800, 600) * _s()) * 0.5


func _r(r: Rect2) -> Rect2:
	return Rect2(_o() + r.position * _s(), r.size * _s())


func _slot_rect(k: String) -> Rect2:
	var i := int(k.right(1))
	if k.begins_with("top"):
		return Rect2(i * 100, 0, 100, 100)
	if k.begins_with("armor"):
		return Rect2(ARMOR_CENTERS[i] - Vector2(50, 50), Vector2(100, 100))
	if k.begins_with("shop"):
		return Rect2(50 + i * 100, 0, 100, 100)
	if k.begins_with("buy"):
		return Rect2(200 + (i % 4) * 100, 100 + (i / 4) * 100, 100, 100)
	if k.begins_with("sell"):
		return Rect2(200 + (i % 4) * 100, 300 + (i / 4) * 100, 100, 100)
	match k:
		"cready": return Rect2(200, 250, 100, 100)
		"cbp": return Rect2(300, 200, 100, 100)
		"cspell": return Rect2(300, 300, 100, 100)
		"sready": return Rect2(200, 250, 100, 100)
		"skey": return Rect2(300, 250, 100, 100)
	if k.begins_with("srune"):
		i = int(k.substr(5))
		return Rect2(400 + (i / 4) * 100, 100 + (i % 4) * 100, 100, 100)
	if k.begins_with("cmat"):
		return Rect2(400 + (i / 4) * 100, 100 + (i % 4) * 100, 100, 100)
	if k.begins_with("rep"):
		i = int(k.substr(3))
		return Rect2(200 + (i % 4) * 100, 100 + (i / 4) * 100, 100, 100)
	return Rect2(50 + i * 100, 500, 100, 100)


func _layout() -> void:
	var s := _s()
	for k in _views:
		var r := _r(_slot_rect(k)).grow(-14 * s)
		if k.begins_with("buy") or k.begins_with("sell") or k.begins_with("rep") or k.begins_with("c") \
				or k in ["sready", "skey"] or k.begins_with("srune"):
			r = _r(_slot_rect(k)).grow(-20 * s)
			r.position.y -= 8 * s   # room for the price
		_views[k].position = r.position
		_views[k].size = r.size
		_views[k].item = "~"
	for i in _info_views.size():
		var x0 := 0.0 if i == 0 else 600.0
		_info_views[i].position = _r(Rect2(x0 + 40, 240, 120, 120)).position
		_info_views[i].size = Vector2(120, 120) * s
		_info_views[i].item = "~"
	_doll.view_size = Vector2i(maxi(64, int(190 * s)), maxi(64, int(300 * s)))
	_doll.custom_minimum_size = Vector2(_doll.view_size)
	_doll.position = _o() + Vector2(305, 130) * s
	_doll.size = Vector2(190, 300) * s
	var r := _r(Rect2(612, 300, 176, 90))
	right_panel.position = r.position
	right_panel.size = r.size
	right_panel.custom_minimum_size = r.size
	_sig = ""


## The hero's bag through the bag filter; items in the sell pile are left out
## (one per pile entry). Quest items are listed too.
func bag_items() -> Array:
	var st := hud.game.session.state
	var out := []
	if mode == "spellconstr":
		for sp: String in hero_spells():
			if sp != s_spell and _passes("spell:" + sp, false, FILTER_SETS.bag[2][filter]):
				out.append("spell:" + sp)
	for it: String in _unique(st.items + st.quest_items.keys()):
		if bag_count(it) > 0 and _passes(it, it in st.quest_items, FILTER_SETS.bag[2][filter]):
			out.append(it)
	return out


## The trader's goods of this screen through the trader's filter.
func shop_items() -> Array:
	var set: Array = FILTER_SETS["spells" if spell_shop() else "items"][2]
	var out := []
	for it: String in hud.game.session.shop_stock({"shop": shop_id}):
		var spellish := it.begins_with("spell:") or it.begins_with("rune:")
		if spellish == spell_shop() and shop_left(it) > 0 and _passes(it, false, set[shop_filter]):
			out.append(it)
	return out


## The trader's stack of `it` not yet in the buy pile or the constructor.
func shop_left(it: String) -> int:
	if hud == null:
		return 0
	var n := hud.game.session.shop_count(it, {"shop": shop_id}) - buy_pile.count(it)
	if mode == "itemconstr" and c_bp != "":
		var st := hud.game.session.state
		if it == c_bp and not c_bp in st.items:
			n -= 1
		if c_mat != "" and it == Items.material_unit(c_mat):
			n -= maxi(0, Items.components(c_bp) - st.items.count(it))
	return n


func _unique(a: Array) -> Array:
	var seen := {}
	var out := []
	for x in a:
		if not seen.has(x):
			seen[x] = true
			out.append(x)
	return out


func _passes(it: String, quest: bool, f: String) -> bool:
	var k := Items.kind(it)
	match f:
		"make": return k == "blueprint" or k == "material"
		"runes": return k == "rune"
		"ready": return k in ["weapon", "armor", "quick"] or it.begins_with("spell:")
		"loot": return k == "loot"
		"quest": return quest
		"all": return true
		"bp_weapon", "bp_light", "bp_heavy", "potions":
			if k != "blueprint":
				return f == "potions" and k == "quick"
			var r := Items.blueprint_row(it)
			var heavy := String(r.row.get("type", "")).to_lower() in ["helm", "plate", "leggins"]
			match f:
				"bp_weapon": return r.table == "weapons"
				"bp_light": return r.table == "armors" and not heavy
				"bp_heavy": return r.table == "armors" and heavy
			return r.table == "quick_items"
		"materials": return k == "material"
		"elemental", "sense", "astral":
			if not it.begins_with("spell:") or Spells.mods_of(it.substr(6)).size() > 0:
				return false
			var sub := String(Spells.parse(it.substr(6)).get("subtype", ""))
			return String(Skills.SCHOOL.get(sub, sub)) == f
		"rune_basic", "rune_special":
			if k != "rune":
				return false
			var special := int(Spells.mod_row(it.substr(5)).get("type", 0)) == 6
			return special == (f == "rune_special")
		"ready_spell": return it.begins_with("spell:") and Spells.mods_of(it.substr(6)).size() > 0
	return true


func hero_spells() -> Array:
	var h: Dictionary = _unit.get_meta("hero") if _unit and _unit.has_meta("hero") else {}
	return h.get("spells", [])


## The spell the constructor would make: the chosen spell plus the new runes.
func spell_preview() -> String:
	var sp := s_spell
	for r: String in s_runes:
		sp = Spells.with_mod(sp, r.substr(5))
	return sp


## Bag count less what waits in the sell pile.
## Option "switch_filters" (SwitchFilters, settings): when an item
## comes into a row (called by the camp screens' drops) and the
## row does not show everything, the row switches to the item's filter
## then it scrolls so the item is in view (scroll = index − 6
## when that is further right, index when the item is left of the view).
## Approx.: the remake notices items arriving in the bag by their counts (any
## command that adds one), and the trader's row is not switched.
var _bag_prev: Variant = null


func _track_bag() -> void:
	var st := hud.game.session.state
	var now := {}
	for it: String in _unique(st.items + st.quest_items.keys()):
		var n := bag_count(it)
		if n > 0:
			now[it] = n
	if _bag_prev is Dictionary:
		for it: String in now:
			if now[it] > int(_bag_prev.get(it, 0)):
				_bag_received(it)
	_bag_prev = now


func _bag_received(it: String) -> void:
	var quest: bool = it in hud.game.session.state.quest_items
	var kinds: Array = FILTER_SETS.bag[2]
	if kinds[filter] != "all" and GameData.option("switch_filters") and not _passes(it, quest, kinds[filter]):
		for f in kinds.size():
			if kinds[f] != "all" and _passes(it, quest, kinds[f]):
				filter = f
				break
	var idx := bag_items().find(it)
	if idx < 0:
		return
	if idx - 6 > scroll:
		scroll = idx - 6
	elif idx < scroll:
		scroll = idx


func bag_count(it: String) -> int:
	if it.begins_with("spell:"):
		return 0 if it.substr(6) == s_spell else 1
	var st := hud.game.session.state
	var n := st.items.count(it) + (1 if st.quest_items.has(it) else 0)
	var used := 1 if it == c_ready or it == c_bp else 0
	if c_mat != "" and it == Items.material_unit(c_mat) and c_bp != "":
		used = mini(Items.components(c_bp), n)
	return n - sell_pile.count(it) - repair_pile.count(it) - used - s_runes.count(it)


func count_in_bag(it: String) -> int:
	return bag_count(it)


func _price(it: String, buying: bool) -> int:
	return Items.buy_price(it) if buying else Items.sell_price(it)


##  deal: [label string key or "", total cost (negative =
## gain), ✓ possible, ✗ possible].
func deal_info() -> Array:
	var money: int = hud.game.session.state.money if hud else 0
	var label := ""
	var total := 0
	var can := false
	var cancel := false
	match mode:
		"weapons":
			if item_group() and not _noconstr():
				for it in _worn_items():
					total += Items.repair_price(it) if Items.wear(it) > 0.0 else 0
				can = total > 0
				if can:
					label = "camp_repair_all"
		"spells":
			pass
		"itemtrade", "spelltrade":
			if not buy_pile.is_empty() or not sell_pile.is_empty():
				label = "camp_item_trade" if mode == "itemtrade" else "camp_spell_trade"
				can = true
				cancel = true
				for it in buy_pile:
					total += _price(it, true)
				for it in sell_pile:
					total -= _price(it, false)
		"repair":
			if not repair_pile.is_empty():
				label = "camp_item_repair"
				can = true
				cancel = true
				for it in repair_pile:
					total += Items.repair_price(it)
		"itemconstr":
			cancel = c_ready != "" or c_bp != "" or c_mat != ""
			if c_ready != "":
				label = "camp_item_deconstr"
				can = true
				total = constr_cost()
			elif c_bp != "" and c_mat != "":
				label = "camp_item_constr"
				can = true
				total = constr_cost()
		"spellconstr":
			cancel = s_spell != ""
			if s_spell != "" and not s_runes.is_empty():
				label = "camp_spell_constr"
				can = _unit != null and _unit.has_meta("hero") \
					and Spells.usable_by(_unit.get_meta("hero"), _unit.max_mana, spell_preview())
	if mode != "spells" and total > money:
		can = false
	return [label, total, can, cancel]


## The deal widget's lines as plain text (tests): money, label, value.
func deal_text() -> String:
	var d := deal_info()
	var out := _money_line()
	if d[0] != "":
		out += "\n%s\n%s" % [_str(d[0]), "0" if d[1] == 0 else "%+d" % -int(d[1])]
	return out


func _money_line() -> String:
	if mode == "spells":
		var h: Dictionary = _unit.get_meta("hero") if _unit and _unit.has_meta("hero") else {}
		return "%s %d" % [_str("camp_current_exp"), int(h.get("exp", 0))]
	return "%s %d" % [_str("camp_current_money"), hud.game.session.state.money if hud else 0]


func _noconstr() -> bool:
	return hud != null and is_equal_approx(hud.game.session.state.get_var(0, "i.noconstr"), 1.0)


func _worn_items() -> Array:
	if _unit == null or not _unit.has_meta("hero"):
		return []
	var h: Dictionary = _unit.get_meta("hero")
	return Array(h.get("weapons", [])) + Array(h.get("armors", []))


## A texts.res "string <key>" first line.
static func _str(key: String) -> String:
	if not GameData.is_open():
		return key
	return GameData.text("string " + key).get_slice("\n", 0).strip_edges()


func _update_total() -> void:
	queue_redraw()


func _clear_constr() -> void:
	s_spell = ""
	s_runes.clear()
	c_bp = ""
	c_mat = ""
	c_ready = ""


## What the constructor's Yes costs: taking apart (deal mode 7), or building
## (Items.construct_price + pieces bought from the trader, as Session._construct).
func constr_cost() -> int:
	if c_ready != "":
		return Items.deconstruct_price(c_ready)
	if c_bp == "" or c_mat == "":
		return 0
	var st := hud.game.session.state
	var n := Items.components(c_bp)
	var cost := Items.construct_price(c_bp, c_mat)
	cost += maxi(0, n - st.items.count(Items.material_unit(c_mat))) * Items.buy_price(Items.material_unit(c_mat))
	if not c_bp in st.items:
		cost += Items.buy_price(c_bp)
	return cost


func _on_yes() -> void:
	if not deal_info()[2]:
		return
	if mode == "weapons":
		#  mode 0: "camp_repair_all", the worn weapons and armour.
		for it in _worn_items():
			if Items.wear(it) > 0.0:
				construct.emit({"t": "repair", "unit": _unit.uid, "item": it})
		return
	if mode == "spellconstr":
		var sp := s_spell
		for r: String in s_runes:
			construct.emit({"t": "enchant", "unit": _unit.uid if _unit else -1, "item": r, "spell": sp})
			sp = Spells.with_mod(sp, r.substr(5))
		s_spell = ""
		s_runes.clear()
		_sig = ""
		_update_total()
		return
	if mode == "itemconstr":
		if c_ready != "":
			construct.emit({"t": "deconstruct", "item": c_ready})
		elif c_bp != "" and c_mat != "":
			construct.emit({"t": "construct", "bp": c_bp, "mat": c_mat})
		_clear_constr()
		_sig = ""
		_update_total()
		return
	if mode == "repair":
		if not repair_pile.is_empty():
			repair.emit(repair_pile.duplicate())
		repair_pile.clear()
		_sig = ""
		_update_total()
		return
	if buy_pile.is_empty() and sell_pile.is_empty():
		return
	deal.emit(buy_pile.duplicate(), sell_pile.duplicate())
	buy_pile.clear()
	sell_pile.clear()
	_sig = ""
	_update_total()


func _on_cancel() -> void:
	_clear_constr()
	repair_pile.clear()
	buy_pile.clear()
	sell_pile.clear()
	_sig = ""
	_update_total()


func refresh(u: GameUnit) -> void:
	_unit = u
	_sig = ""
	if _ready_done:
		set_mode(mode)


func _process(_dt: float) -> void:
	if _turn_dir != 0:
		if not is_visible_in_tree() or mode != "weapons" or tutorial_visible() \
				or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_turn_dir = 0
		else:
			_doll.turn_by(_turn_dir * TURN_SPEED * _dt)
	var ctrl := Input.is_key_pressed(KEY_CTRL)
	if ctrl != _ctrl:
		_ctrl = ctrl
		queue_redraw()
	# a held skill rises every frame once 0.25 s past the
	# click's −0.5 s.
	if not _hold_cmd.is_empty():
		if mode != "spells" or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_hold_cmd = {}
		else:
			_hold_t += _dt
			if _hold_t >= 0.25:
				construct.emit(_hold_cmd)
	if not visible or hud == null:
		_bag_prev = null
		return
	_track_bag()
	var u := _unit
	var h: Dictionary = u.get_meta("hero") if u and u.has_meta("hero") else {}
	var bag := bag_items()
	scroll = clampi(scroll, 0, maxi(0, bag.size() - BAG_CELLS))
	var shop := shop_items() if shop_row() else []
	shop_scroll = clampi(shop_scroll, 0, maxi(0, shop.size() - BAG_CELLS))
	var sig := "%s|%s|%s|%s|%s|%d|%d|%s|%s|%s|%s|%d|%d|%d" % [u.uid if u else -1, h.get("weapons", []), h.get("armors", []),
		[h.get("quick", []), h.get("spells", []), h.get("perks", []), h.get("exp", 0), h.get("skills", {})], bag, filter, scroll, size, mode, shop, buy_pile + ["/"] + sell_pile + ["/"] + repair_pile + [c_bp, c_mat, c_ready, s_spell] + s_runes + hero_spells(), shop_filter, shop_scroll,
		hud.game.session.state.money] + str(hash(hud.game.session.state.shops.get(shop_id, {})))
	if sig == _sig:
		return
	_sig = sig
	for i in BAG_CELLS:
		var j := scroll + i
		_content["bag%d" % i] = [bag[j] if j < bag.size() else "", "bag"]
	if shop_row():
		for i in BAG_CELLS:
			var j := shop_scroll + i
			_content["shop%d" % i] = [shop[j] if j < shop.size() else "", "shop"]
	if trading():
		for i in PILE_CELLS:
			_content["buy%d" % i] = [buy_pile[i] if i < buy_pile.size() else "", "buy"]
			_content["sell%d" % i] = [sell_pile[i] if i < sell_pile.size() else "", "sell"]
	elif mode == "repair":
		for i in REPAIR_CELLS:
			_content["rep%d" % i] = [repair_pile[i] if i < repair_pile.size() else "", "rep"]
	elif mode == "spellconstr":
		var sp := spell_preview()
		_content["sready"] = ["spell:" + sp if sp != "" else "", "sready"]
		_content["skey"] = ["spell:" + sp.get_slice("{", 0) if sp != "" else "", "skey"]
		var runes: Array = Array(Spells.mods_of(s_spell)).map(func(c): return "rune:" + c) if s_spell != "" else []
		var n_old := runes.size()
		runes += s_runes
		for i in PILE_CELLS:
			_content["srune%d" % i] = [runes[i] if i < runes.size() else "", "srune" if i >= n_old else "srune_old"]
	elif mode == "itemconstr":
		# A ready item shows its parts; a blueprint + material the result.
		var bp := c_bp
		var mat := c_mat
		if c_ready != "":
			bp = Items.blueprint(Items.plain(c_ready))
			mat = String(Items.info(c_ready).material)
		var result := c_ready if c_ready != "" else ("%s.%s" % [bp.substr(3), mat] if bp != "" and mat != "" else "")
		_content["cready"] = [result, "cready"]
		_content["cbp"] = [bp, "cbp"]
		_content["cspell"] = ["", "cspell"]
		var n := Items.components(bp) if bp != "" else (1 if mat != "" else 0)
		for i in PILE_CELLS:
			_content["cmat%d" % i] = [Items.material_unit(mat) if mat != "" and i < n else "", "cmat"]
	elif mode == "spells":
		# Mode 1: the hero's spells along the top row (camphelp 1).
		var spells: Array = h.get("spells", [])
		for i in 8:
			_content["top%d" % i] = ["spell:" + String(spells[i]) if i < spells.size() else "", "known"]
	else:
		if u:
			_doll.show_unit(u)
		var armor_by_type := {}
		for a: String in h.get("armors", []):
			armor_by_type[int(Items.info(a).row.get("type_id", -1))] = a
		# the hero's weapons (hero) from the
		# left cell rightwards and its belt (hero)
		# the right cell leftwards.
		var weapons: Array = h.get("weapons", [])
		var quick: Array = h.get("quick", [])
		for i in 8:
			var id := ""
			if i < 4:
				id = weapons[i] if i < weapons.size() else ""
			elif 7 - i < quick.size():
				id = String(quick[7 - i])
			_content["top%d" % i] = [id, "worn" if i < 4 else "belt"]
		for i in 7:
			_content["armor%d" % i] = [armor_by_type.get(i, ""), "worn"]
	for k in _views:
		if _key_shown(k):
			_views[k].show_item(String(_content.get(k, [""])[0]))
	queue_redraw()


## Side buttons shown now (see SIDE_BUTTONS).
func side_buttons() -> Array:
	var out := []
	for b: String in SIDE_BUTTONS:
		match b:
			"exit": out.append(b)
			"accept", "cancel":
				if not (mode == "weapons" and (not item_group() or _noconstr())):
					out.append(b)
			"weapons", "spells":
				out.append(b)
			_:
				if mode_offered(b):
					out.append(b)
	return out


func _side_at(p: Vector2) -> String:
	for b: String in side_buttons():
		if (SIDE_BUTTONS[b][0] as Rect2).has_point(p):
			return b
	return ""


func _press_side(b: String) -> void:
	# the original: a new mode button "buttons\camp\slot.wav", exit
	# (mode 7) "buttons\globalmap\transit.wav"; accept
	# "buttons\camp\buy.wav"; cancel "buttons\messbox\cancel.wav".
	if GameSound.instance:
		var wav := "buttons\\camp\\slot.wav"
		match b:
			"exit": wav = "buttons\\globalmap\\transit.wav"
			"accept": wav = "buttons\\camp\\buy.wav"
			"cancel": wav = "buttons\\messbox\\cancel.wav"
		if b in ["exit", "accept", "cancel"] or b != mode:
			GameSound.instance.ui(wav)
	match b:
		"exit": exit_pressed.emit()
		"accept": _on_yes()
		"cancel": _on_cancel()
		_: set_mode(b)
	queue_redraw()


func _row_hit(p: Vector2, y0: float) -> int:
	# Filter buttons: 0..5; scroll left / right: 10 / 11; -1 none.
	for i in FILTER_RECTS.size():
		if Rect2(FILTER_RECTS[i].position + Vector2(0, y0), FILTER_RECTS[i].size).has_point(p):
			return i
	if Rect2(30, y0 + 35, 20, 30).has_point(p):
		return 10
	if Rect2(750, y0 + 35, 20, 30).has_point(p):
		return 11
	return -1


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT] \
			or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		_turn_dir = 0


func _input(e: InputEvent) -> void:
	#  captures the mouse; stops on release even
	# outside the arrow. Catch release before another control can consume it.
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		_turn_dir = 0


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_update_hover((e.position - _o()) / _s())
		return
	if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_hold_cmd = {}
		_turn_dir = 0
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = (e.position - _o()) / _s()
	if mode == "weapons":
		for i in TURN_RECTS.size():
			if TURN_RECTS[i].has_point(p):
				_turn_dir = -1 if i == 0 else 1
				if GameSound.instance:
					GameSound.instance.ui("buttons\\camp\\move.wav")
				accept_event()
				return
	var side := _side_at(p)
	if side:
		_press_side(side)
		accept_event()
		return
	# The hero widget's arrows (modes 0 / 1).
	if mode in ["weapons", "spells"]:
		for a in [[Rect2(0, 125, 30, 20), -1], [Rect2(170, 125, 30, 20), 1]]:
			if (a[0] as Rect2).has_point(p):
				if GameSound.instance:
					GameSound.instance.ui("buttons\\camp\\scroll.wav")
				hero_step.emit(a[1])
				accept_event()
				return
	if mode == "spells":
		for row: Array in _skill_rows:
			if not (row[0] as Rect2).has_point(p):
				continue
			var cmd: Dictionary = row[1]
			if row[3] == "arrow":
				if cmd.list == "known":
					_perk_scroll += int(cmd.d)
				else:
					_avail_scroll += int(cmd.d)
				queue_redraw()
				accept_event()
				return
			if GameSound.instance:
				GameSound.instance.ui("buttons\\camp\\perk.wav")
			if not cmd.is_empty():
				construct.emit(cmd)
				if row[3] == "skill":
					_hold_cmd = cmd
					_hold_t = -0.5
			accept_event()
			return
	var hit := _row_hit(p, 500)
	if hit >= 0:
		_row_sound(hit)
		if hit < 10:
			filter = hit
			scroll = 0
		else:
			scroll += -1 if hit == 10 else 1
		accept_event()
		return
	if shop_row():
		hit = _row_hit(p, 0)
		if hit >= 0:
			_row_sound(hit)
			if hit < 10:
				shop_filter = hit
				shop_scroll = 0
			else:
				shop_scroll += -1 if hit == 10 else 1
			accept_event()
			return
	for k in _content:
		if not _key_shown(k) or not _slot_rect(k).has_point(p) or _content[k][0] == "":
			continue
		var id: String = _content[k][0]
		var where: String = _content[k][1]
		selected_id = id
		selected_where = where
		if mode in ["weapons", "spells"]:
			picked.emit(id, where if where != "known" else "info")
		else:
			_move(id, where)
			picked.emit(id, "info")
		queue_redraw()
		accept_event()
		return


## What the right info widget shows for the point (the camp's mouse move
## xx: each widget's hit test gives an item
##  or a help id →; else the hero / skills widgets'
## descriptions).
func _update_hover(p: Vector2) -> void:
	var item := ""
	var key := ""
	var help := -1
	var desc: Array = []
	var side := _side_at(p)
	if side:
		help = int(BUTTON_HELP.get(side, -1))
	else:
		for k in _content:
			if _key_shown(k) and _slot_rect(k).has_point(p):
				if String(_content[k][0]) != "":
					item = _content[k][0]
					key = k
				else:
					help = _area_help(k)
				break
		if item == "" and help < 0:
			help = _limit_help(p)
		if item == "" and help < 0:
			if mode == "spells":
				for row: Array in _skill_rows:
					if (row[0] as Rect2).has_point(p):
						desc = row[2]
						break
			if desc.is_empty() and mode in ["weapons", "spells"]:
				desc = _hero_desc(p)
	if key != _hover_key:
		if _views.has(_hover_key):
			_views[_hover_key].spin = false
		_hover_key = key
		if _views.has(key):
			_views[key].spin = true
	if item != _hover_item or help != _hover_help or desc != _hover_desc:
		_hover_item = item
		_hover_help = help
		_hover_desc = desc
		queue_redraw()


## camphelp for an empty slot (approx.: by the texts' titles).
func _area_help(k: String) -> int:
	var spells := spell_shop() or mode == "spells"
	if k.begins_with("top"):
		if mode == "spells":
			return 1
		return 2 if int(k.substr(3)) < 4 else 3
	if k.begins_with("armor"):
		return ARMOR_HELP[int(k.substr(5))]
	if k.begins_with("bag"):
		return 22
	if k.begins_with("shop"):
		return 24 if spells else 23
	if k.begins_with("buy"):
		return 17 if spells else 11
	if k.begins_with("sell"):
		return 18 if spells else 12
	if k.begins_with("rep"):
		return 25
	if k.begins_with("cmat"):
		return 15
	if k.begins_with("srune"):
		return 21
	return {"cready": 13, "cbp": 14, "cspell": 16, "sready": 19, "skey": 20}.get(k, -1)


## The spell constructor's limit lines (hot areas 10 / 11
## camphelp 26 / 27).
func _limit_help(p: Vector2) -> int:
	if mode != "spellconstr":
		return -1
	if Rect2(200, 450, 200, 20).has_point(p):
		return 26
	if Rect2(200, 470, 200, 20).has_point(p):
		return 27
	return -1


## The hero widget rows' descriptions (approx.: the rows'
## description keys follow their labels).
func _hero_desc(p: Vector2) -> Array:
	if not Rect2(0, 100, 200, 300).has_point(p):
		return []
	var row := int(floorf((p.y - 165.0) / 15.0))
	var rows := _hero_rows()
	if row >= 0 and row < rows.size():
		return rows[row][3]
	return []


##  (an item row's mouse press): a scroll arrow
## "buttons\camp\scroll.wav", a filter button "buttons\camp\mode.wav".
func _row_sound(hit: int) -> void:
	if GameSound.instance:
		GameSound.instance.ui("buttons\\camp\\scroll.wav" if hit >= 10 else "buttons\\camp\\mode.wav")


## Trade screens: goods -> buy pile, bag -> sell pile, a pile -> back.
func _move(id: String, where: String) -> void:
	if mode == "spellconstr":
		if where == "bag" and id.begins_with("spell:"):
			s_spell = id.substr(6)
			s_runes.clear()
		elif where == "bag" and id.begins_with("rune:") and s_spell != "" and bag_count(id) > 0 \
				and Spells.can_add(spell_preview(), id.substr(5)):
			s_runes.append(id)
		elif where == "srune":
			s_runes.erase(id)
		elif where in ["sready", "skey"]:
			_clear_constr()
		_sig = ""
		_update_total()
		return
	if mode == "itemconstr" and where in ["bag", "shop"]:
		var k := Items.kind(id)
		if k == "blueprint":
			c_ready = ""
			c_bp = id
			if c_mat != "" and not _mat_fits(c_bp, c_mat):
				c_mat = ""
		elif k == "material":
			c_ready = ""
			var m := id.trim_prefix("material.")
			if c_bp == "" or _mat_fits(c_bp, m):
				c_mat = m
		elif where == "bag" and Items.can_deconstruct(id):
			_clear_constr()
			c_ready = id
		_sig = ""
		_update_total()
		return
	match where:
		"shop":
			if trading() and buy_pile.size() < PILE_CELLS and shop_left(id) > 0:
				buy_pile.append(id)
		"buy":
			buy_pile.erase(id)
		"sell":
			sell_pile.erase(id)
		"rep":
			repair_pile.erase(id)
		"cready":
			if c_ready != "":
				c_ready = ""
			else:
				c_mat = ""   # the preview: clearing the material undoes the build
		"cbp":
			c_bp = ""
			c_ready = ""
		"cmat":
			c_mat = ""
			c_ready = ""
		"bag":
			if mode == "repair":
				if Items.wear(id) > 0.0 and repair_pile.size() < REPAIR_CELLS and bag_count(id) > 0:
					repair_pile.append(id)
				_sig = ""
				_update_total()
				return
			# The same check as the row prices (_row_accepts).
			var ok := _row_accepts(id, false) and not id in hud.game.session.state.quest_items
			if ok and sell_pile.size() < PILE_CELLS and bag_count(id) > 0:
				sell_pile.append(id)
	_sig = ""
	_update_total()


##  (camp) for the item rows' prices: whether the
## screen takes the item now (from the trader's goods row, or the bag).
## Approx.: the spell constructor's knowledge / stamina limits for a keystone
## and the item constructor's spell slot are left out.
func _row_accepts(it: String, goods: bool) -> bool:
	var k := Items.kind(it)
	var spellish := it.begins_with("spell:") or k == "rune"
	match mode:
		"spelltrade":
			return spellish
		"itemtrade":
			return not spellish and k != "quest"
		"spellconstr":
			if not goods:
				return false
			if it.begins_with("spell:"):
				return s_spell == ""
			if k == "rune":
				return s_spell != "" and s_runes.size() < 8 and Spells.can_add(spell_preview(), it.substr(5))
			return false
		"itemconstr":
			if not goods:
				return false
			var empty := c_bp == "" and c_mat == "" and c_ready == ""
			if k == "blueprint" or Items.can_deconstruct(it):
				return empty
			if k == "material":
				return c_bp != "" and c_mat == "" and _mat_fits(c_bp, it.trim_prefix("material."))
			return false
		"repair":
			return goods and k in ["weapon", "armor"] and Items.wear(it) > 0.0
	return false


func _mat_fits(bp: String, mat: String) -> bool:
	return Items.materials_for(bp).any(func(m): return String(m.name).to_lower() == mat)


func _filter_set(y0: float) -> Array:
	if y0 > 0:
		return FILTER_SETS.bag
	return FILTER_SETS["spells" if spell_shop() else "items"]


func _get_tooltip(pos: Vector2) -> String:
	var p := (pos - _o()) / _s()
	var side := _side_at(p)
	if side:
		return GameData.text("tip %d" % SIDE_BUTTONS[side][2]).strip_edges()
	for y0 in ([500.0, 0.0] if shop_row() else [500.0]):
		var hit := _row_hit(p, y0)
		if hit >= 0 and hit < 10:
			return GameData.text("tip %d" % (int(_filter_set(y0)[1]) + hit)).strip_edges()
		if hit >= 10:
			return GameData.text("tip 20400").strip_edges()
	for k in _content:
		if _key_shown(k) and _slot_rect(k).has_point(p) and _content[k][0] != "":
			var it: String = _content[k][0]
			var n := bag_count(it) if _content[k][1] == "bag" else (shop_left(it) if _content[k][1] == "shop" else 1)
			var t := Items.title(it) + (" x%d" % n if n > 1 else "")
			match _content[k][1]:
				"shop", "buy": t += "\n%d" % _price(it, true)
				"sell": t += "\n%d" % _price(it, false)
				"rep": t += "\n%d" % Items.repair_price(it)
			return t
	return ""


## A sprite: `uv` in texture pixels; a negative width / height mirrors it
## (the original's u0 > u1 / v0 > v1 sprites).
func _region(tex: String, dest: Rect2, uv: Rect2, mod := Color.WHITE) -> void:
	if not _tex.has(tex):
		return
	var t: Texture2D = _tex[tex]
	if uv.size.x >= 0.0 and uv.size.y >= 0.0:
		draw_texture_rect_region(t, _r(dest), uv, mod)
		return
	var r := _r(dest)
	var ts := t.get_size()
	var u0 := uv.position / ts
	var u1 := (uv.position + uv.size) / ts
	draw_primitive(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([mod, mod, mod, mod]),
		PackedVector2Array([u0, Vector2(u1.x, u0.y), u1, Vector2(u0.x, u1.y)]), t)


## An item row (bag at y 500 on Inventory01, trader's goods at y 0 on
## Inventory02): cells, end caps (the left one mirrored), filters, arrows.
func _draw_row(y0: float, tex: String, fset: Array, sel: int) -> void:
	for i in BAG_CELLS:
		_region(tex, Rect2(50 + i * 100, y0, 100, 100), Rect2(14, 14, 100, 100))
	_region(tex, Rect2(0, y0, 50, 100), Rect2(192, 14, -50, 100))
	_region(tex, Rect2(750, y0, 50, 100), Rect2(142, 14, 50, 100))
	for i in FILTER_RECTS.size():
		var r: Rect2 = FILTER_RECTS[i]
		var uv: Rect2 = FILTER_UV[i]
		uv.position.x += fset[0]
		_region(tex, Rect2(r.position + Vector2(0, y0), r.size), uv, Color.WHITE if i == sel else Color(0.6, 0.6, 0.6))
	var s := _s()
	for side in [[Vector2(48, y0 + 50), -1.0], [Vector2(752, y0 + 50), 1.0]]:
		var c: Vector2 = _o() + side[0] * s
		var d: float = side[1]
		draw_colored_polygon(PackedVector2Array([c + Vector2(d * 2, 0) * s, c + Vector2(-d * 14, -12) * s,
			c + Vector2(-d * 14, 12) * s]), Color(0.85, 0.7, 0.35))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var s := _s()
	_draw_backdrop()
	if mode == "spells":
		# Spell slots: the campslots star frame (UV 14,142-114,242; approx.:
		# mode 1's top row widget is not traced).
		for i in 8:
			_region("campslots", Rect2(i * 100, 0, 100, 100), Rect2(14, 142, 100, 100))
	elif mode != "weapons":
		_draw_row(0, "inventory02", _filter_set(0), shop_filter)
		# Centre: 100×100 cells, UV origin alternating 28 / 128 (
		var base := "repair" if mode == "repair" else "trade"
		if mode in ["itemconstr", "spellconstr"]:
			for q in 4:
				_region(("constritem%d" if mode == "itemconstr" else "constrspell%d") % (q + 1), Rect2(200 + (q % 2) * 200, 100 + (q / 2) * 200, 200, 200),
					Rect2(28, 28, 200, 200))
		for yi in (0 if mode in ["itemconstr", "spellconstr"] else 4):
			for xi in 4:
				var t := "%s%d" % [base, (1 if xi < 2 else 2) + (0 if yi == 0 else 2)]
				_region(t, Rect2(200 + xi * 100, 100 + yi * 100, 100, 100),
					Rect2(28 if xi % 2 == 0 else 128, 28 if yi % 2 == 0 else 128, 100, 100))
	else:
		for i in 8:
			_region("campslots", Rect2(i * 100, 0, 100, 100), TOP_CELL_UV[0 if i < 4 else 1])
		for q in 4:
			_region("camp%d" % (q + 1), Rect2(200 + (q % 2) * 200, 100 + (q / 2) * 200, 200, 200), Rect2(28, 28, 200, 200))
	_draw_row(500, "inventory01", FILTER_SETS.bag, filter)
	_draw_side()
	var d := deal_info()
	for b: String in side_buttons():
		# the mode buttons (and Exit) at 0.5, the current one
		# 1.0;: ✓ / ✗ at 0.5 unless the deal can be made / undone.
		var lit: bool = b == mode
		if b == "accept":
			lit = d[2]
		elif b == "cancel":
			lit = d[3]
		_region("campinfo", SIDE_BUTTONS[b][0], SIDE_BUTTONS[b][1], Color.WHITE if lit else Color(0.5, 0.5, 0.5))
	# Selection.
	for k in _content:
		if _key_shown(k) and _content[k][0] != "" and _content[k][0] == selected_id and _content[k][1] == selected_where:
			draw_rect(_r(_slot_rect(k)).grow(-10 * s), Color(0.95, 0.8, 0.35), false, 2.0)
	_overlay.queue_redraw()


func _draw_overlay() -> void:
	_canvas = _overlay
	_draw_row_texts()
	var ids := _info_ids()
	if ids[0] != "":
		_draw_item_info(0, ids[0])
	if ids[1] != "":
		_draw_item_info(600, ids[1])
	_canvas = self


func _draw_row_texts() -> void:
	# Item rows (its draw): two text surfaces
	# 50,y+15-750,y+35 and 50,y+65-750,y+85; per cell (x+15..x+85) the stack
	# count when not 1 (font 1, right) and, unless the row's deal
	# mode is 9, its deal price (camp, centred) for the
	# items the camp's check (_row_accepts) passes.
	# Deal modes: the spell goods
	# row 0 (spell buy), the item goods row 4 (item buy); the bag 1 in the
	# spell trade, 5 in the item trade, else 9.
	for row in [["bag", 500.0], ["shop", 0.0]]:
		if row[0] == "shop" and not shop_row():
			continue
		for i in BAG_CELLS:
			var it: String = _content.get("%s%d" % [row[0], i], [""])[0]
			if it == "":
				continue
			var x := 50.0 + i * 100.0
			var y0: float = row[1]
			var n := bag_count(it) if row[0] == "bag" else shop_left(it)
			if n != 1:
				_t(Rect2(x + 15, y0 + 15, 70, 20), str(n), 1, Interface800.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
			var price := -1
			if row[0] == "shop":
				if _row_accepts(it, true):
					price = _price(it, true)
			elif trading() and _row_accepts(it, false):
				price = _price(it, false)
			if price >= 0:
				_t(Rect2(x + 15, y0 + 65, 70, 20), str(price), 1, Interface800.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	# The piles' prices the same way (x+15..85, y+65..85).
	var piles := []
	if mode == "repair":
		piles = ["rep"]
	elif trading():
		piles = ["buy", "sell"]
	for pile: String in piles:
		for i in (REPAIR_CELLS if pile == "rep" else PILE_CELLS):
			var it: String = _content.get("%s%d" % [pile, i], [""])[0]
			if it == "":
				continue
			var r := _slot_rect("%s%d" % [pile, i])
			var price := Items.repair_price(it) if pile == "rep" else _price(it, pile == "buy")
			_t(Rect2(r.position.x + 15, r.position.y + 65, 70, 20), str(price), 1, Interface800.TEXT,
				HORIZONTAL_ALIGNMENT_CENTER)


# ------------------------------------------------------------ side widgets

##  (see the header): the stone backdrop of the middle band.
func _draw_backdrop() -> void:
	if not _tex.has("campinfo"):
		for r in [Rect2(0, 100, 200, 400), Rect2(600, 100, 200, 400)]:
			draw_rect(_r(r), Color(0.09, 0.085, 0.07))
		return
	# the 100×100 tile UV 14,14-114,114, 8 × 4 times.
	for xi in 8:
		for yi in 4:
			_region("campinfo", Rect2(xi * 100, 100 + yi * 100, 100, 100), Rect2(14, 14, 100, 100))
	for x in [0, 200, 400, 600]:
		for yi in 4:
			_region("campinfo", Rect2(x, 100 + yi * 100, 21, 100), Rect2(254, 76, -21, 100))
			_region("campinfo", Rect2(x + 179, 100 + yi * 100, 21, 100), Rect2(233, 76, 21, 100))
		_region("campinfo", Rect2(x, 100, 100, 30), Rect2(254, 2, -100, 30))
		_region("campinfo", Rect2(x, 470, 100, 30), Rect2(254, 32, -100, -30))
		_region("campinfo", Rect2(x + 100, 100, 100, 30), Rect2(154, 2, 100, 30))
		_region("campinfo", Rect2(x + 100, 470, 100, 30), Rect2(154, 32, 100, -30))
	for xy in [Vector2(0, 380), Vector2(600, 380), Vector2(200, 280)]:
		_region("campinfo", Rect2(xy.x, xy.y, 100, 40), Rect2(254, 34, -100, 40))
		_region("campinfo", Rect2(xy.x + 100, xy.y, 100, 40), Rect2(154, 34, 100, 40))


func _fpx(fi: int) -> int:
	return maxi(6, int(round(800.0 * _s() * Interface800.FONT_EM[fi])))


## One font line in 800×600 units.
func _lh(fi: int) -> float:
	return Interface800.font().get_height(_fpx(fi)) / _s()


## one line from the rect's top (800 units), 1 px
## shadow; left text is cut with "...", right text spills left.
func _t(r: Rect2, txt: String, fi := 0, col := Interface800.TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if txt.is_empty():
		return
	var f := Interface800.font()
	var fs := _fpx(fi)
	var rr := _r(r)
	var w := rr.size.x
	if align == HORIZONTAL_ALIGNMENT_LEFT and f.get_string_size(txt, align, -1, fs).x > w:
		while txt.length() > 1 and f.get_string_size(txt + "...", align, -1, fs).x > w:
			txt = txt.substr(0, txt.length() - 1)
		txt += "..."
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > w:
			rr.position.x = rr.end.x - tw
			w = tw
	var y := rr.position.y + f.get_ascent(fs)
	var sh := maxf(1.0, round(_s()))
	_canvas.draw_string(f, Vector2(rr.position.x + sh, y + sh), txt, align, w, fs, Interface800.SHADOW)
	_canvas.draw_string(f, Vector2(rr.position.x, y), txt, align, w, fs, col)


func _wrap(txt: String, width: float, fi: int) -> PackedStringArray:
	var f := Interface800.font()
	var fs := _fpx(fi)
	var w := width * _s()
	var out := PackedStringArray()
	for para in txt.replace("\r", "").split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var t := word if line.is_empty() else line + " " + word
			if line.is_empty() or f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
				line = t
			else:
				out.append(line)
				line = word
		out.append(line)
	return out


##  with flags 0x11: centred word-wrapped text, at most
## `max_lines` lines. Returns the lines drawn.
func _tb(r: Rect2, txt: String, fi: int, col: Color, max_lines: int,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> int:
	var lines := _wrap(txt, r.size.x, fi)
	var n := mini(lines.size(), max_lines)
	var h := _lh(fi)
	for i in n:
		_t(Rect2(r.position.x, r.position.y + h * i, r.size.x, h), lines[i], fi, col, align)
	return n


##  text surface (approx.: placed at 200,450, where
## puts the hot areas 200,450-400,470 (camphelp 26) and 200,470-400,490
## (camphelp 27)): font 1, at (10,0)-(200,20) and (10,20)-(200,40):
## "infoitem_35" / "infoitem_36" alone, or with a spell set
## "%s %d (%d)": the hero's limit (camp) and the spell's
## complexity / stamina.
func _draw_constr_limits() -> void:
	var r1 := Rect2(210, 450, 190, 20)
	var r2 := Rect2(210, 470, 190, 20)
	if s_spell == "" or _unit == null or not _unit.has_meta("hero"):
		_t(r1, _lbl(35), 1, Interface800.TEXT)
		_t(r2, _lbl(36), 1, Interface800.TEXT)
		return
	var sp := spell_preview()
	var h: Dictionary = _unit.get_meta("hero")
	var pp := Spells.parse(sp)
	_t(r1, "%s %d (%d)" % [_lbl(35), int(Skills.knowledge(h, String(pp.subtype))), int(Spells.complexity(sp))], 1,
		Interface800.TEXT)
	_t(r2, "%s %d (%d)" % [_lbl(36), int(_unit.max_mana), int(pp.mana)], 1, Interface800.TEXT)


## The items the left / right info widgets show ("" for none).
func _info_ids() -> Array:
	var left := ""
	if not mode in ["weapons", "spells"]:
		left = _result_item()
	var right := ""
	if _hover_item != "":
		right = _hover_item
	elif _hover_help < 0 and _hover_desc.is_empty():
		right = selected_id
	return [left, right]


func _draw_side() -> void:
	var ids := _info_ids()
	for i in _info_views.size():
		_info_views[i].visible = ids[i] != ""
		_info_views[i].show_item(String(ids[i]))
	# Left widget (an item's info goes on the overlay, over its model).
	if mode in ["weapons", "spells"]:
		_draw_hero()
	elif ids[0] == "":
		_draw_help(0, int(MODE_HELP.get(mode, -1)))
	# Right widget: hover, else the clicked item.
	if ids[1] == "":
		if _hover_help >= 0:
			_draw_help(600, _hover_help)
		elif not _hover_desc.is_empty():
			_tb(Rect2(615, 110, 170, 15), String(_hover_desc[0]), 0, Color.WHITE, 2)
			_tb(Rect2(615, 140, 170, 15), String(_hover_desc[1]), 0, Interface800.TEXT, 16)
	_overlay.queue_redraw()
	if mode == "spellconstr":
		_draw_constr_limits()
	# Deal widget.
	var d := deal_info()
	_t(Rect2(0, 410, 200, 20), _money_line(), 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if d[0] != "":
		_t(Rect2(0, 430, 200, 20), _str(d[0]), 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		_t(Rect2(0, 450, 200, 20), "0" if int(d[1]) == 0 else "%+d" % -int(d[1]), 1, Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER)
	# Mode title.
	_t(Rect2(600, 410, 200, 20), _str(MODE_TITLES.get(mode, "")), 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	if mode == "spells":
		_draw_skills()


## The constructors' result shown in the left widget (
func _result_item() -> String:
	if mode == "itemconstr":
		return String(_content.get("cready", [""])[0])
	if mode == "spellconstr":
		return String(_content.get("sready", [""])[0])
	return ""


## "camphelp <id>" — title, then the text 30 lower.
func _draw_help(x0: float, id: int) -> void:
	if id < 0 or not GameData.is_open():
		return
	var t := GameData.text("camphelp %d" % id)
	if t.is_empty():
		return
	var lines := Array(t.split("\n"))
	var title := String(lines.pop_front()).strip_edges()
	var body := " ".join(lines.map(func(x): return String(x).strip_edges())).strip_edges()
	_tb(Rect2(x0 + 15, 110, 170, 15), title, 0, Color.WHITE, 2)
	_tb(Rect2(x0 + 15, 140, 170, 15), body, 0, Interface800.TEXT, 16)


func _lbl(n: int) -> String:
	return _str("infoitem_%d" % n)


## The info widget's text (and the per-kind functions it hands
## over to): the name (15,10-185,25, two lines, font 0, white, centred), rows
## of font 0 15 apart from y 40, one blank line, the description
## (centred, word-wrapped, `lines` lines) and the trailing rows.
func _draw_item_info(x0: float, id: String) -> void:
	# With Ctrl held (manager) an enchanted item shows its spell's info
	# ("(CTRL - view)").
	if _ctrl and Items.spell_of(id) != "":
		id = "spell:" + Items.spell_of(id)
	var inf := _item_info(id)
	_tb(Rect2(x0 + 15, 110, 170, 15), inf.name, 0, Color.WHITE, 2)
	var y := 140.0
	for r: String in inf.rows:
		_t(Rect2(x0 + 15, y, 170, 15), r, 0, Interface800.TEXT)
		y += 15.0
	y += float(inf.gap)
	if inf.desc != "":
		_tb(Rect2(x0 + 15, y, 170, 15), inf.desc, 0, Interface800.TEXT, int(inf.lines))
	y += float(inf.tail_at)
	for r: String in inf.tail:
		_t(Rect2(x0 + 15, y, 170, 15), r, 0, Interface800.TEXT)
		y += 15.0
	if inf.has("wrap"):
		_tb(Rect2(x0 + 15, y, 170, 15), inf.wrap, 0, Interface800.TEXT, 3, HORIZONTAL_ALIGNMENT_LEFT)


## The fields of _draw_item_info for one item: {name, rows, gap, desc,
## lines, tail_at, tail, [wrap]}.
## - weapons / armour / quick items / loot / quest items:
##   Type, Material "%s x %d" (matshort, components; not for loot, nor for a
##   quick item whose prototype has no material), Weight (not for quest
##   items); weapons, armour and wands Energy (item = prototype mana +
##   material mana) and Complexity "%d/%d"
##   (the attached spell's, item = prototype slots + material slots)
##   weapons / armour Durability "%d/%d"; weapons Damage "%d-%d %s",
##   Actions, Attack change, Range (bows, crossbows) or Defense change;
##   armour Armor "%.1f" (the general type, (0)) and
##   Vulnerability (the types below it, "string dmg_N"). A blank line, the
##   description (4 lines, loot 7), then — four lines on, one more for all
##   but weapons — "Spell: %s" and "(CTRL - view)" for an enchanted item;
## - potions: Type; with a spell Effect ("Constant" when the
##   prototype takes no effect runes) and Duration ("Immediately"
##   below 2 ticks, else ticks / 15 "s") and a blank line; 8 lines of text;
## - spells: Type, Stamina, Complexity, School
##   ("string school_N" of the prototype type_id), Effect, Speed (%d, or
##   "Immediately" below 1), Range "%d m", Area (π r² "%.1f m", or "Target"
##   for a unit spell, flag), Duration, Targets; the description
##   and four lines on "Runes:" with each rune's name, ", " between, "." at
##   the end (three lines, left);
## - runes: Type, Stamina, Complexity, 8 lines of text
## - blueprints: Type, Material "mattype_<type> x
##   components", Weight, Energy, Complexity (weapons, armour, wands),
##   Durability (weapons, armour), the weapon's Damage / Actions / Attack /
##   Range or Defense from the prototype, or Armor / Vulnerability of the
##   prototype's absorption × type factor × 10;
## - materials: Type, Class (mattype_), Weight, Energy
##   Complexity, Durability, Damage "%.1f", Armor and Vulnerability of the
##   material's resists.
## Approx.: a keystone (loot 2/3) is shown as a spell; the
## blueprint's description is its item's.
func _item_info(id: String) -> Dictionary:
	var out := {"name": Items.title(id), "rows": PackedStringArray(), "gap": 15.0, "desc": "", "lines": 4,
		"tail_at": 0.0, "tail": PackedStringArray()}
	var rows: PackedStringArray = out.rows
	var tt := Items.type_text(id)
	rows.append("%s %s" % [_lbl(37), tt])
	var k := Items.kind(id)
	if id.begins_with("spell:"):
		var sp := id.substr(6)
		var pp := Spells.parse(sp)
		out.name = Spells.title(String(pp.code))
		rows.append("%s %d" % [_lbl(7), int(pp.mana)])
		rows.append("%s %d" % [_lbl(14), int(Spells.complexity(sp))])
		rows.append("%s %s" % [_lbl(18), _str("school_%d" % int(pp.proto.get("type_id", 0)))])
		rows.append(_effect_row(pp))
		var spd := float(pp.proto.get("speed", 0.0))
		rows.append("%s %s" % [_lbl(9), ("%d" % int(spd)) if spd >= 1.0 else _lbl(21)])
		rows.append("%s %d%s" % [_lbl(10), int(pp.range), _lbl(26)])
		if int(pp.flags) & 0x10000000:
			rows.append("%s %s" % [_lbl(11), _lbl(22)])
		else:
			rows.append("%s %.1f%s" % [_lbl(11), PI * float(pp.radius) * float(pp.radius), _lbl(26)])
		rows.append(_duration_row(float(pp.duration)))
		rows.append("%s %d" % [_lbl(13), int(pp.targets)])
		out.desc = _text_body("spell " + String(pp.code))
		out.tail_at = 75.0
		var mods := Spells.mods_of(sp)
		if not mods.is_empty():
			var t := _lbl(19)
			for m in mods:
				t += " " + Spells.mod_title(m) + ","
			out.wrap = t.trim_suffix(",") + "."
		return out
	if k == "rune":
		var row := Spells.mod_row(id.substr(5))
		out.name = Spells.mod_title(id.substr(5))
		rows.append("%s %d" % [_lbl(7), int(float(row.get("mana", 0.0)))])
		rows.append("%s %d" % [_lbl(14), int(row.get("complex", 0))])
		out.desc = _text_body("modifier " + id.substr(5).to_lower())
		out.lines = 8
		return out
	if k == "blueprint":
		var r := Items.blueprint_row(id)
		var row: Dictionary = r.row
		var mt := String(row.get("material_type", "")).to_lower()
		rows.append("%s %s x %d" % [_lbl(1), _str("mattype_" + mt), int(row.get("components", 0))])
		rows.append("%s %d" % [_lbl(0), int(float(row.get("weight", 0.0)))])
		rows.append("%s %d" % [_lbl(2), int(float(row.get("mana", 0.0)))])
		rows.append("%s %d" % [_lbl(14), int(row.get("slots", 0))])
		if r.table in ["weapons", "armors"]:
			rows.append("%s %d" % [_lbl(3), int(float(row.get("durability", 0.0)))])
		if r.table == "weapons":
			_weapon_rows(rows, row, Vector2(float(row.get("min_damage", 0.0)),
				float(row.get("min_damage", 0.0)) + float(row.get("max_damage", 0.0))), Items.damage_types(id.substr(3)))
		elif r.table == "armors":
			var a: Array = Array(row.get("absorption", []))
			var l := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
			if a.size() >= 8:
				for t in 7:
					l[t] = float(a[1 + t]) * float(a[0]) * 10.0
			_armor_rows(rows, l)
		out.desc = Items.flavor(id.substr(3))
		return out
	if k == "material":
		var i := Items.info(id)
		var m: Dictionary = i.mat
		rows.append("%s %s" % [_lbl(17), _str("mattype_" + String(m.get("type", "")).to_lower())])
		rows.append("%s %d" % [_lbl(0), int(float(m.get("weight", 0.0)))])
		rows.append("%s %d" % [_lbl(2), int(float(m.get("mana", 0.0)))])
		rows.append("%s %d" % [_lbl(14), int(m.get("slots", 0))])
		rows.append("%s %d" % [_lbl(3), int(float(m.get("durability", 0.0)))])
		rows.append("%s %.1f" % [_lbl(15), float(m.get("damage", 0.0))])
		var res: Array = Array(m.get("resist", []))
		var l := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
		for t in mini(7, res.size()):
			l[t] = float(res[t])
		_armor_rows(rows, l)
		out.desc = Items.flavor(id)
		return out
	var i := Items.info(id)
	var wand := k == "quick" and "wand" in String(i.base)
	if k == "quick" and not wand:
		#  (potions).
		var ps := Items.potion_spell(id)
		out.gap = 0.0
		if ps:
			var pp := Spells.parse(ps)
			rows.append(_effect_row(pp))
			rows.append(_duration_row(float(pp.duration)))
			out.gap = 15.0
		out.desc = Items.flavor(id)
		out.lines = 8
		return out
	var mt := String(i.row.get("material_type", "none")).to_lower()
	if k != "loot" and not (k == "quick" and (mt == "" or mt == "none")):
		var mname := GameData.text("matshort " + String(i.material).replace(" ", "_")).get_slice("\n", 0).strip_edges() \
			if i.material else ""
		rows.append("%s %s x %d" % [_lbl(1), mname if mname else String(i.material).capitalize(), int(i.row.get("components", 0))])
	if k != "quest":
		rows.append("%s %d" % [_lbl(0), int(Items.weight(id))])
	var sp := Items.spell_of(id)
	if k in ["weapon", "armor"] or wand:
		rows.append("%s %d" % [_lbl(2), int(float(i.row.get("mana", 0.0)) + float(i.mat.get("mana", 0.0)))])
		var cx := int(Spells.complexity(sp)) if sp else 0
		rows.append("%s %d/%d" % [_lbl(14), cx, int(i.row.get("slots", 0)) + int(i.mat.get("slots", 0))])
	if k in ["weapon", "armor"]:
		rows.append("%s %d/%d" % [_lbl(3), maxi(0, int(Items.durability(id))), int(Items.max_durability(id))])
	if k == "weapon":
		_weapon_rows(rows, i.row, Items.damage(id), Items.damage_types(id))
	elif k == "armor":
		_armor_rows(rows, Items.armor_layer(id))
	out.desc = Items.flavor(id)
	out.lines = 7 if k == "loot" else 4
	out.tail_at = 60.0 + (0.0 if k == "weapon" else 15.0)
	if sp and (k in ["weapon", "armor"] or wand):
		out.tail.append("%s %s" % [_lbl(5), Spells.title(String(Spells.parse(sp).code))])
		out.tail.append(_lbl(6))
	return out


## The info widget's text as plain lines (name, rows, a blank line, the
## description, the trailing rows), for the remake's action area under the
## camp (InventoryPanel) — the same port as _draw_item_info.
func item_info_text(id: String) -> String:
	var inf := _item_info(id)
	var out := PackedStringArray([String(inf.name)])
	out.append_array(inf.rows)
	var desc := String(inf.desc).strip_edges()
	if desc != "":
		out.append("")
		out.append(desc)
	if not (inf.tail as PackedStringArray).is_empty():
		out.append("")
		out.append_array(inf.tail)
	return "\n".join(out)


func _weapon_rows(rows: PackedStringArray, row: Dictionary, dm: Vector2, f: PackedFloat32Array) -> void:
	var ty := ""
	for t in 7:
		if f[t] != 0.0:
			ty = _str("damage_%d" % t)
			break
	rows.append("%s %d-%d %s" % [_lbl(15), int(dm.x), int(dm.y), ty])
	rows.append("%s %d" % [_lbl(20), int(row.get("actions", 0))])
	rows.append("%s %d" % [_lbl(38), int(row.get("attack", 0))])
	if String(row.get("type", "")).to_lower() in ["bow", "crossbow"]:
		rows.append("%s %d" % [_lbl(10), int(row.get("range", 0))])
	else:
		rows.append("%s %d" % [_lbl(39), int(row.get("defence", 0))])


## (0): "%.1f" of the general armour (type 6), then the types
## 0..5 below it ("string dmg_N") as the vulnerability.
func _armor_rows(rows: PackedStringArray, l: PackedFloat32Array) -> void:
	rows.append("%s %.1f" % [_lbl(25), l[6]])
	var below := PackedStringArray()
	for t in 6:
		if l[t] < l[6]:
			below.append(_str("dmg_%d" % t))
	if not below.is_empty():
		rows.append("%s %s" % [_lbl(24), ", ".join(below)])


func _effect_row(pp: Dictionary) -> String:
	var mods: Array = Array(pp.proto.get("mods", []))
	if mods.size() > 3 and int(mods[3]) == 0:
		return "%s %s" % [_lbl(8), _lbl(28)]
	return "%s %d" % [_lbl(8), int(pp.effect)]


func _duration_row(d: float) -> String:
	if d < 2.0:
		return "%s %s" % [_lbl(12), _lbl(21)]
	return "%s %.1f%s" % [_lbl(12), d / 15.0, _lbl(27)]


## A texts.res entry's lines after the first, joined.
static func _text_body(key: String) -> String:
	var t := GameData.text(key) if GameData.is_open() else ""
	var ls := Array(t.split("\n")).map(func(x): return String(x).strip_edges())
	if not ls.is_empty():
		ls.pop_front()
	return " ".join(ls.filter(func(x): return x != "")).strip_edges()


## The hero widget's rows for the mode: [label, value, colour, description].
func _hero_rows() -> Array:
	var u := _unit
	if u == null or not u.has_meta("hero"):
		return []
	var h: Dictionary = u.get_meta("hero")
	var st: Dictionary = u.stats
	var out := []
	var perk := func(code: String) -> Array:
		var t := GameData.text("perk " + code) if GameData.is_open() else ""
		var ls := Array(t.split("\n"))
		var ttl := String(ls.pop_front()).strip_edges() if not ls.is_empty() else code
		return [ttl, " ".join(ls.map(func(x): return String(x).strip_edges())).strip_edges()]
	var load_row := func() -> void:
		var e: Array = perk.call("encumbrance")
		out.append([e[0], "%d/%d" % [int(st.get("load", 0)), int(st.get("max_load", 0))], Interface800.TEXT, e])
		out.append(["", _str("infounit_17") if float(st.get("load", 0)) > float(st.get("max_load", 0)) else "",
			RED, []])
	if mode == "spells":
		for a in [["strength", "str"], ["dexterity", "dex"], ["intelligence", "int"]]:
			var pr: Array = perk.call(a[0])
			out.append([pr[0], "%d" % int(st.get(a[1], h.get(a[1], 0))), Interface800.TEXT, pr])
		out.append(["", "", Interface800.TEXT, []])
		var hp: Array = perk.call("health")
		out.append([hp[0], "%d" % int(u.max_hp), Interface800.TEXT, hp])
		var mp: Array = perk.call("mana")
		out.append([mp[0], "%d" % int(u.max_mana), Interface800.TEXT, mp])
		var ac: Array = perk.call("actions")
		out.append([ac[0], "%d" % int(st.get("actions", 0)), Interface800.TEXT, ac])
		var ex: Array = perk.call("experience")
		out.append([ex[0], "%d" % int(h.get("exp_total", h.get("exp", 0))), Interface800.TEXT, ex])
		load_row.call()
		return out
	out.append([_lbl(25), "", Interface800.TEXT, []])
	var pa: Dictionary = st.get("part_armor", {})
	var nat: Array = Array(st.get("armor", []))
	for part: Array in HL_PARTS:
		var layers: PackedFloat32Array = pa.get(part[1], PackedFloat32Array())
		var best := 0.0
		for t in 6:
			var v := (float(nat[t]) if t < nat.size() else 0.0) + (layers[t] if t < layers.size() else 0.0)
			best = maxf(best, v)
		var key := "hl_" + String(part[0])
		out.append([_str(key), "%.1f" % best, Interface800.TEXT, [_str(key), _str(key + "_desc")]])
	out.append(["", "", Interface800.TEXT, []])
	var weapons: Array = h.get("weapons", [])
	if not weapons.is_empty():
		out.append([_str("infounit_14"), "", Interface800.TEXT, []])
		out.append(["     " + _str("infounit_3"), "%d" % int(st.get("to_hit", 0)), Interface800.TEXT, []])
		out.append(["     " + _str("infounit_4"), "%d" % int(st.get("parry", 0)), Interface800.TEXT, []])
		var ty := ""
		var f: PackedFloat32Array = st.get("dmg_types", PackedFloat32Array())
		for t in mini(7, f.size()):
			if f[t] != 0.0:
				ty = _str("damage_%d" % t)
				break
		out.append(["     %s %s" % [_str("infounit_9"), ty],
			"%d-%d" % [int(st.get("dmg_min", 0)), int(st.get("dmg_max", 0))], Interface800.TEXT, []])
		out.append(["", "", Interface800.TEXT, []])
	else:
		for i in 4:
			out.append(["", "", Interface800.TEXT, []])
	load_row.call()
	var ms := [_str("magic_skills"), _str("magic_skills_desc")]
	var know := PackedStringArray()
	for school in ["elemental", "sense", "astral"]:
		know.append("%s %d" % [Skills.title(school), int(Skills.knowledge(h, school))])
	ms[1] = String(ms[1]) + "\n" + ", ".join(know)
	out.append([ms[0], "", Interface800.TEXT, ms])
	return out


##  (see the header).
func _draw_hero() -> void:
	_region("campinfo", Rect2(14, 110, 86, 50), Rect2(231, 76, -86, 60))
	_region("campinfo", Rect2(100, 110, 86, 50), Rect2(145, 76, 86, 60))
	_region("campinfo", Rect2(176, 125, 16, 20), Rect2(2, 129, 16, 20))
	_region("campinfo", Rect2(8, 125, 16, 20), Rect2(18, 129, -16, 20))
	if _unit == null:
		return
	_t(Rect2(0, 127, 200, 16), _unit.display_name, 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var right := 175.0 if mode == "weapons" else 180.0
	var y := 165.0
	for row: Array in _hero_rows():
		var r := Rect2(20, y, right - 20, 15)
		_t(r, String(row[0]), 0, row[2])
		_t(r, String(row[1]), 0, row[2], HORIZONTAL_ALIGNMENT_RIGHT)
		y += 15.0


## The skills widget (build, data
## draw, clicks) on a surface at 200,100-600,500:
## - headings "string skills" (0,10-200,25), "perks" (0,205-200,220) and
##   "perks_av" (200,10-400,25), font 0, white, centred;
## - skill rows (15,35-180,50) 15 apart: Melee, Archery, (Backstab is skipped,
##   two lines), Elemental, Sense, Astral; Science on the gap at y 65. Name
##   left, the level "%d" right-aligned 40 px further left, and below level
##   100 the cost (: %d, %.1fk, %dk, %.1fm, %dm, %.1fg) right-
##   aligned, when the experience covers it, else, over the
##   campinfo plate UV 124,138-164,153 at x 350..390;
## - known abilities from y 230: up to 10 families from the scroll, "perk
##   <family>0" with " (" perk_level N ")" from rank 2, and the next rank's
##   cost with its plate while a rank is left
## - available abilities (215,35-380,50): 23 rows of the families not begun
##   (rank 1), name and cost, plate at x 550..590
## - scroll arrows (campinfo UV 130,3-150,13, flipped for down) at
##   360,320 / 360,480 (known) and 560,125 / 560,480 (available), shown while
##   the list can move that way
## - a click raises a skill or learns / upgrades an ability at once
##   (buttons\\camp\\perk.wav); a held skill keeps rising every frame from
##   0.75 s .
## Approx.: the hover descriptions in the right widget (the widget's hit test
##  is not traced).
func _draw_skills() -> void:
	_skill_rows.clear()
	if _unit == null or not _unit.has_meta("hero"):
		return
	var h: Dictionary = _unit.get_meta("hero")
	var xp := float(h.get("exp", 0.0))
	var mine := hud != null and _unit.controller == hud.game.session.my_index
	var o := Vector2(200, 100)
	_t(Rect2(o + Vector2(0, 10), Vector2(200, 15)), _str("skills"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_t(Rect2(o + Vector2(0, 205), Vector2(200, 15)), _str("perks"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_t(Rect2(o + Vector2(200, 10), Vector2(200, 15)), _str("perks_av"), 0, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var cost_col := func(c: int) -> Color:
		return Interface800.TEXT if xp >= c else DIM
	var plate := Rect2(124, 138, 40, 15)
	# Skills.
	var ys := {"melee": 35, "archery": 50, "science": 65, "elemental": 95, "sense": 110, "astral": 125}
	for sk: String in Skills.LIST:
		var r := Rect2(o + Vector2(15, ys[sk]), Vector2(165, 15))
		var lv := Skills.level(h, sk)
		_t(r, Skills.title(sk), 0, Interface800.TEXT)
		_t(Rect2(r.position - Vector2(40, 0), r.size), "%d" % lv, 0, Interface800.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		var c := Skills.cost(h, sk)
		if lv < 100:
			_region("campinfo", Rect2(350, r.position.y, 40, 15), plate)
			_t(r, _cost_text(c), 0, cost_col.call(c), HORIZONTAL_ALIGNMENT_RIGHT)
		var t := GameData.text("perk " + sk) if GameData.is_open() else ""
		var ls := Array(t.split("\n"))
		var ttl := String(ls.pop_front()).strip_edges() if not ls.is_empty() else sk
		_skill_rows.append([r, {"t": "train", "unit": _unit.uid, "stat": sk} if mine and lv < 100 and xp >= c else {},
			[ttl, " ".join(ls.map(func(x): return String(x).strip_edges())).strip_edges()], "skill"])
	# Known abilities: the highest rank of each family.
	var known := []
	var fams := {}
	for code: String in h.get("perks", []):
		var fam := code.rstrip("0123456789")
		var n := int(code.substr(fam.length())) if code.length() > fam.length() else 1
		if not fams.has(fam):
			known.append(fam)
		fams[fam] = maxi(int(fams.get(fam, 0)), n)
	_perk_scroll = clampi(_perk_scroll, 0, maxi(0, known.size() - 10))
	var y := 330.0
	for i in range(_perk_scroll, mini(known.size(), _perk_scroll + 10)):
		var fam: String = known[i]
		var n: int = fams[fam]
		var name := _perk_family(fam)
		if n >= 2:
			name = "%s (%s%d)" % [name, _str("perk_level"), n]
		var r := Rect2(215, y, 165, 15)
		_t(r, name, 0, Interface800.TEXT)
		var nxt := "%s%d" % [fam, n + 1]
		var cmd := {}
		if n < 3 and not Perks.get_perk(nxt).is_empty():
			var c := Perks.cost(nxt, h)
			_region("campinfo", Rect2(350, y, 40, 15), plate)
			_t(r, _cost_text(c), 0, cost_col.call(c), HORIZONTAL_ALIGNMENT_RIGHT)
			if mine and xp >= c:
				cmd = {"t": "perk", "unit": _unit.uid, "perk": nxt}
		_skill_rows.append([r, cmd, _perk_desc("%s%d" % [fam, n]), "perk"])
		y += 15.0
	# Available abilities: families not begun.
	var avail := Perks.available(h).filter(func(code): return String(code).ends_with("1"))
	_avail_scroll = clampi(_avail_scroll, 0, maxi(0, avail.size() - 23))
	y = 135.0
	for i in range(_avail_scroll, mini(avail.size(), _avail_scroll + 23)):
		var code: String = avail[i]
		var r := Rect2(415, y, 165, 15)
		var c := Perks.cost(code, h)
		_t(r, _perk_family(code.rstrip("0123456789")), 0, Interface800.TEXT)
		_region("campinfo", Rect2(550, y, 40, 15), plate)
		_t(r, _cost_text(c), 0, cost_col.call(c), HORIZONTAL_ALIGNMENT_RIGHT)
		_skill_rows.append([r, {"t": "perk", "unit": _unit.uid, "perk": code} if mine and xp >= c else {},
			_perk_desc(code), "perk"])
		y += 15.0
	# Scroll arrows.
	var up := Rect2(130, 3, 20, 10)
	var down := Rect2(130, 13, 20, -10)
	var arrows := [[Rect2(360, 320, 20, 10), up, _perk_scroll > 0, "known", -1],
		[Rect2(360, 480, 20, 10), down, _perk_scroll < known.size() - 10, "known", 1],
		[Rect2(560, 125, 20, 10), up, _avail_scroll > 0, "avail", -1],
		[Rect2(560, 480, 20, 10), down, _avail_scroll < avail.size() - 23, "avail", 1]]
	for a: Array in arrows:
		if a[2]:
			_region("campinfo", a[0], a[1])
			_skill_rows.append([a[0], {"t": "scroll", "list": a[3], "d": a[4]}, [], "arrow"])


## a skills-screen cost.
static func _cost_text(c: int) -> String:
	if c < 0:
		return "%.1fg" % (2147483647 * 1e-9)
	if c < 1000:
		return "%d" % c
	if c < 10000:
		return "%.1fk" % (c * 0.001)
	if c < 1000000:
		return "%dk" % (c / 1000)
	if c < 10000000:
		return "%.1fm" % (c * 1e-6)
	if c < 1000000000:
		return "%dm" % (c / 1000000)
	return "%.1fg" % (c * 1e-9)


## An ability family's name: "perk <family>0", first field.
static func _perk_family(fam: String) -> String:
	var t := GameData.text("perk %s0" % fam) if GameData.is_open() else ""
	var first := t.get_slice("\n", 0).strip_edges()
	return first if first else fam


func _perk_desc(code: String) -> Array:
	var t := GameData.text("perk " + code) if GameData.is_open() else ""
	var ls := Array(t.split("\n"))
	ls.pop_front()
	return [Perks.title(code), " ".join(ls.map(func(x): return String(x).strip_edges())).strip_edges()]
