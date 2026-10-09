class_name CampView
extends Control
const TrainingRefund := preload("res://src/game/training_refund.gd")
const REFUND_RECT := Rect2(20, 355, 160, 28)
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
##   ready item alone is taken apart (Session._deconstruct). An optional spell
##   is attached to the built weapon / armour and consumed.
## - "spellconstr" (draw): the centre
##   "constrspell1".."constrspell4" as the item constructor; the ready spell
##   at (250,300) (CItemSpell), its keystone at (350,300)
##   (loot kind 2 / 3) and up to 8 runes at x 450 / 550, y
##   150..450 (kind 2 / 4); the draw sums the complexity and
##   stamina it shows. The pile takes (mode 3, from the bag or
##   the trader's goods) a ready spell alone, or a keystone and then up to 8
##   fitting runes within the party's knowledge / stamina; ✓ takes a ready
##   spell apart (keystone + runes stay in the pile) or builds the keystone and
##   runes into a spell (which stays in the pile); see Session._spell_constr,
##   one "spell_constr" command answered by "constr_result". A rune clicked in
##   the pile goes back where it came from, the keystone / ready spell takes
##   the whole pile with it (case 6). The remake's heroes keep
##   their spells outside the bag, so here the bag row also lists the hero's
##   known spells (the original's spell items, put into the bag first).
## - "spells" (Skills/Spells, tip 20101, tutorial camp_skills): the top row
##   holds the hero's spells (camphelp 1, up to eight), the left widget the
##   attributes (mode 1) and the centre the skills widget (
##   _draw_skills; a click raises a skill or learns an ability at once).
## - All modes: the hero's bag row 500..600 (
##   "Inventory01"): seven cells at x 50..750, end caps, scroll buttons (tip
##   20400) and six filter buttons (mode 0, tips 21100-21105
##   icons at U + 168).
## textures.res images come out of EIMmp upside down against the original's UVs, so
## they are flipped once here. Spell pieces use flat slot artwork; other
## items show their 3D models.
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
## - "swap" (the original multiplayer game's player swap, screen 9:
## build, draw, per frame
##   press, commit; input, mouse
## keys): an empty name row at the top
##   (on "InventoryM01", its filter buttons hidden), the item
##   trade's centre with two piles — the upper the partner's offer («Swap:
##   receive», camphelp 28), the lower this player's (camphelp 29) —, the bag
##   row (area 1) and the right info widget (600,100). Left (text surfaces
## font 1, centred): with the partner's offer present its
##   reply heading xch_remote_header at 20,110-180,130 (white, two lines)
##   over xch_remote_ok / xch_remote_cancel at 0,150-200,170, the
##   heading xch_money_remote at 20,210-180,230 over the partner's money at
##   0,250-200,270; the divider (300); xch_money_offer
##   20,310-180,330 over the money field (at 0,350-200,366
##   centred font 1 white, caret, 9 characters, atoi); "%s %d"
##   xch_current_money at 0,410-200,430 and xch_accept at 0,430-200,450. ✓
##   (12,450, tip 41000) lit while not agreed, ✗ (148,450, tip 41001) while
##   agreed, Exit (740,460, tip 41003) at 0.5. A press on a bag item puts it
##   into the offer pile (put_on.wav), on one of the own pile back
##   (put_off.wav), on the partner's pile nothing (its
##    takes every item). See PlayerSwap.
## Approx.:
## - item info: see _item_info (the enchanted items' pulse is ItemView's);
## - one left press moves an item at once, as the original's item widgets do
##   (their button-up and move
##   handlers are empty, so there is no drag and drop): in the dressing and
##   skills screens a bag item goes on the hero, a hero's item into the bag
##   (_press), in the other screens between the goods / bag and the pile
##   (_move); a refused press plays messbox\cancel.wav;
## Rows start on filter 5: "all" for the bag, "ready-made" for traders.
## The remake's constructors select a combined relevant-items filter on entry;
## other modes keep the separate item/spell rows and their selected filters.

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
## The swap screen's command for PlayerSwap.send ("set", "agree", "disagree",
## "withdraw").
signal swap_cmd(cmd: Dictionary)

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
## The swap screen's tips for ✓ / ✗ / Exit (: 41000, 41001, 41003).
const SWAP_TIPS := {"accept": 41000, "cancel": 41001, "exit": 41003}

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
var _bag_scrolls := [0, 0, 0, 0, 0, 0]
var _shop_rows := {"items": {"filter": 5, "scroll": 0, "scrolls": [0, 0, 0, 0, 0, 0]},
	"spells": {"filter": 5, "scroll": 0, "scrolls": [0, 0, 0, 0, 0, 0]}}
var buy_pile: Array = []
var sell_pile: Array = []
var trade_wait := false
var _trade_req := 0
var repair_pile: Array = []
var c_bp := ""       # item constructor: blueprint, material name, ready item, spell
var c_mat := ""
var c_ready := ""
var c_spell: String = ""   # "spell:<id>", from the bag or the hero's known spells
var s_spell := ""    # spell constructor pile: code of a keystone or ready spell
var s_kind := "keystone"   # native loot3007/2/3 versus ready container3008
var s_from := ""     # where it came from: "bag", "known" (a hero's spell) or "shop"
var s_runes: Array = []        # the pile's runes ("rune:<code>")
var s_rune_from: Array = []    # "bag" / "shop" per rune
var s_wait := false  # ✓ sent, the host's "constr_result" not in yet
var _s_req := 0
var selected_id := ""
var selected_where := ""
## The last sounds of _press (file names), read by tools/camp_test.gd.
var press_sounds: Array = []

var _tex := {}
var _doll: Paperdoll
var _turn_dir := 0   # Original angle: area 2 adds, area 3 subtracts; screen direction unverified.
var _views := {}   # slot key -> ItemView
var _pile_clip: Control   # trade / repair depth mask, shared by their item views
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
## Shop transfer repeats only the captured item, even when its row scrolls.
## It stages copies locally; Accept still sends one atomic trade command.
const TRANSFER_DELAY := 0.5
const TRANSFER_INTERVAL := 0.075
var _transfer_hold := {}
var _transfer_t := 0.0
## Swap screen: the money field's text and when this player last changed
## its offer (the host's table wins again after a quiet moment).
var swap_money := ""
var _swap_sent_t := -10.0

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
	add_to_group("pad_panel")   # remake: gamepad snap targets (pad_targets)
	for n in ["campslots", "camp1", "camp2", "camp3", "camp4", "inventory01", "inventory02",
			"trade1", "trade2", "trade3", "trade4", "repair1", "repair2", "repair3", "repair4",
			"constritem1", "constritem2", "constritem3", "constritem4",
			"constrspell1", "constrspell2", "constrspell3", "constrspell4", "campinfo", "inventorym01"]:
		var img := GameData.load_image(n) if GameData.is_open() else null
		if img:
			img.flip_y()
			_tex[n] = ImageTexture.create_from_image(img)
	_doll = Paperdoll.new()
	_doll.camp_frame = true
	add_child(_doll)
	_pile_clip = Control.new()
	_pile_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pile_clip.clip_contents = true
	add_child(_pile_clip)
	for k in _slot_keys():
		var v := ItemView.new()
		v.camp = true
		if k.begins_with("buy") or k.begins_with("sell") or k.begins_with("rep"):
			_pile_clip.add_child(v)
		else:
			add_child(v)
		_views[k] = v
	# The info widgets' item models (mode 9).
	for x0 in [0, 600]:
		var v := ItemView.new()
		v.camp = true
		v.info = true
		v.modulate = Color8(127, 127, 127)
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
	GameData.options_changed.connect(_options_changed)
	_tutorial = TutorialPanel.new()
	add_child(_tutorial)
	set_mode(mode)


func _options_changed() -> void:
	_layout()
	_sig = ""
	queue_redraw()


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
	return not mode in ["weapons", "spells", "swap"]


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


## The original rebuilds the rows on opening the camp.
func reset_filters() -> void:
	_row_arrivals.clear()
	filter = 5
	scroll = 0
	shop_filter = 5
	shop_scroll = 0
	_bag_scrolls.fill(0)
	_shop_rows = {"items": {"filter": 5, "scroll": 0, "scrolls": [0, 0, 0, 0, 0, 0]},
		"spells": {"filter": 5, "scroll": 0, "scrolls": [0, 0, 0, 0, 0, 0]}}


func set_mode(m: String) -> void:
	if trade_wait: return
	_touch_spell_info = false
	var changed := m != mode
	if changed:
		_stop_transfer_hold()
		var rows := _row_counts()
		buy_pile.clear()
		sell_pile.clear()
		repair_pile.clear()
		_clear_constr()
		_rows_returned(rows)
		if shop_row():
			var old_row: Dictionary = _shop_rows["spells" if spell_shop() else "items"]
			old_row.filter = shop_filter
			old_row.scroll = shop_scroll
			old_row.scrolls[shop_filter] = shop_scroll
		_turn_dir = 0
	mode = m
	if changed and shop_row():
		var row: Dictionary = _shop_rows["spells" if spell_shop() else "items"]
		shop_filter = int(row.filter)
		shop_scroll = int(row.scroll)
	if changed and mode in ["spellconstr", "itemconstr"]:
		# Start with every usable category, including ready items to dismantle
		# and spells to enchant with. The other filters remain available.
		_set_bag_filter(0)
		_set_shop_filter(5)
		scroll = 0
		shop_scroll = 0
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
	if mode == "swap":
		return k.begins_with("buy") or k.begins_with("sell")
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
var _touch_zoom := 1.0
var _touch_pan := Vector2.ZERO
var _touch_spell_info := false

func _s() -> float:
	return minf(size.x / 800.0, size.y / 600.0) * _touch_zoom


func _o() -> Vector2:
	return (size - Vector2(800, 600) * _s()) * 0.5 + _touch_pan


func _r(r: Rect2) -> Rect2:
	return Rect2(_o() + r.position * _s(), r.size * _s())


func touch_hold(point: Vector2) -> void:
	var p := (point - _o()) / _s()
	_update_hover(p)
	if trading():
		for key: String in _content:
			if _key_shown(key) and _slot_rect(key).has_point(p):
				var id := String(_content[key][0])
				var where := String(_content[key][1])
				if _transfer_available(id, where):
					selected_id = id
					selected_where = where
					_move(id, where)
					_start_transfer_hold(id, where)
					picked.emit(id, "info")
				return
	# Hold the equipped weapon to make it active, without first unequipping it.
	if mode == "weapons" and _unit:
		for i in TURN_RECTS.size():
			if TURN_RECTS[i].has_point(p):
				_turn_dir = 1 if i == 0 else -1
				return
		var weapons := Session.weapon_slots(_unit.get_meta("hero", {}))
		for i in mini(4, weapons.size()):
			if _slot_rect("top%d" % i).has_point(p):
				construct.emit({"t": "select_weapon", "unit": _unit.uid, "item": weapons[i]})
				return
	# Holding either existing info column toggles the Ctrl-only spell view.
	if p.y >= 100 and p.y < 500 and (p.x < 200 or p.x >= 600):
		_touch_spell_info = not _touch_spell_info
	queue_redraw()


func touch_release() -> void:
	_turn_dir = 0
	_hold_cmd = {}
	_stop_transfer_hold()


func touch_scroll(point: Vector2, delta: Vector2) -> void:
	var p := (get_global_transform_with_canvas().affine_inverse() * point - _o()) / _s()
	if absf(delta.x) > absf(delta.y):
		var step := -1 if delta.x > 0 else 1
		if p.y < 100 and shop_row():
			shop_scroll = maxi(0, shop_scroll + step)
		elif p.y > 500:
			scroll = maxi(0, scroll + step)
	elif mode == "spells":
		if p.x < 200:
			_perk_scroll = maxi(0, _perk_scroll + (-1 if delta.y > 0 else 1))
		else:
			_avail_scroll = maxi(0, _avail_scroll + (-1 if delta.y > 0 else 1))
	queue_redraw()


func touch_transform(before: PackedVector2Array, after: PackedVector2Array) -> void:
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var old_mid := inverse * ((before[0] + before[1]) * 0.5)
	var mid := inverse * ((after[0] + after[1]) * 0.5)
	var anchor := (old_mid - _o()) / _s()
	_touch_zoom = clampf(_touch_zoom * after[0].distance_to(after[1]) / maxf(16.0, before[0].distance_to(before[1])), 1.0, 2.5)
	_touch_pan = mid - anchor * _s() - (size - Vector2(800, 600) * _s()) * 0.5
	var limit := (Vector2(800, 600) * _s() - size).max(Vector2.ZERO) * 0.5
	_touch_pan = _touch_pan.clamp(-limit, limit)
	_layout()
	queue_redraw()


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
	#  00627c50 clear depth over the whole pile panel, not
	# separately per cell. Items may extend across cell boundaries.
	var pile_rect := _r(Rect2(200, 100, 400, 400))
	_pile_clip.position = pile_rect.position
	_pile_clip.size = pile_rect.size
	for k in _views:
		var c := _slot_rect(k).get_center()
		var v: ItemView = _views[k]
		v.fit_slot = GameData.option("item_icon_fit") != 0
		# All slot builders pass width 100 to. Its scale is
		# 100 * K * z * 0.0009375, hence 37.5 px per model unit regardless
		# of z. Reuse the UI perspective with equivalent depth z / scale.
		v.unit_px = 37.5 * s
		v.screen_at = Vector3(c.x, c.y, 400.0 / ItemView.K / 37.5)
		#  masks worn armour to centre ±35; does
		# the same for its ready item and blueprint. Other slots are not
		# individually clipped. Leave room for the whole rotating figure.
		var extent := 70.0 if k.begins_with("armor") or k in ["cready", "cbp"] else 240.0
		if v.fit_slot:
			extent = minf(extent, 80.0)
		v.size = Vector2.ONE * extent * s
		v.position = _o() + c * s - v.size * 0.5
		if v.get_parent() == _pile_clip:
			v.position -= _pile_clip.position
		v.item = "~"
	for i in _info_views.size():
		var x0 := 0.0 if i == 0 else 600.0
		_info_views[i].position = _r(Rect2(x0, 100, 200, 300)).position
		_info_views[i].size = Vector2(200, 300) * s
		_info_views[i].screen_at = Vector3(x0 + 100, 300, 0)
		_info_views[i].item = "~"
	var figure_rect := _r(Paperdoll.CAMP_RECT)
	_doll.view_size = Vector2i(figure_rect.size.round())
	_doll.custom_minimum_size = Vector2(_doll.view_size)
	_doll.position = figure_rect.position
	_doll.size = figure_rect.size
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
	if mode in ["spellconstr", "itemconstr"]:
		for sp: String in hero_spells():
			if bag_count("spell:" + sp) > 0 and _passes("spell:" + sp, false, _filter_set(500)[2][filter]):
				out.append("spell:" + sp)
	for it: String in _unique(st.items + ([] if mode == "swap" else st.quest_items.keys())):
		if not it in out and bag_count(it) > 0 and _passes(it, it in st.quest_items, _filter_set(500)[2][filter]):
			out.append(it)
	return out


## The trader's goods of this screen through the trader's filter.
func shop_items() -> Array:
	var set: Array = _filter_set(0)[2]
	var out := []
	for it: String in hud.game.session.shop_stock({"shop": shop_id}):
		var spellish := Items.is_spell_piece(it)
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
	if mode == "spellconstr":
		n -= _s_used(it, "shop")
	return maxi(0,n) if trade_wait else n


## Spell constructor pile pieces `it` taken from `from` ("bag", "shop", "known").
func _s_used(it: String, from: String) -> int:
	var n := 1 if s_spell != "" and _s_item() == it and s_from == from else 0
	for i in s_runes.size():
		if s_runes[i] == it and s_rune_from[i] == from:
			n += 1
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
		"constructor":
			if quest:
				return false
			if mode == "spellconstr":
				return Items.is_spell_piece(it)
			return k in ["blueprint", "material"] or Items.can_deconstruct(it) or Items.is_spell_container(it)
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
			if not Items.is_keystone(it):
				return false
			var sub := String(Spells.parse(Items.spell_code(it)).get("subtype", ""))
			return String(Skills.SCHOOL.get(sub, sub)) == f
		"rune_basic", "rune_special":
			if k != "rune":
				return false
			var special := int(Spells.mod_row(it.substr(5)).get("type", 0)) == 6
			return special == (f == "rune_special")
		"ready_spell": return Items.is_spell_container(it)
	return true


func hero_spells() -> Array:
	var h: Dictionary = _unit.get_meta("hero") if _unit and _unit.has_meta("hero") else {}
	return h.get("spells", [])


## The spell the constructor would make: the keystone plus the pile's runes
## (a ready spell in the pile is itself).
func spell_preview() -> String:
	var sp := s_spell
	for r: String in s_runes:
		sp = Spells.with_mod(sp, r.substr(5))
	return sp


## A ready container lies in the pile: ✓ takes it apart, even without runes.
func s_ready() -> bool:
	return s_spell != "" and s_kind == "spell"


func _s_item() -> String:
	return ("spell:" if s_ready() else "keystone:") + s_spell if s_spell != "" else ""


## The party's best knowledge of the pile's school and best stamina
## (camp).
func _s_limits(spell: String) -> Vector2i:
	if hud == null:
		return Vector2i.ZERO
	var ss := hud.game.session
	return Spells.party_limits(ss.party_units(ss.my_index), String(Spells.parse(spell).subtype))


##  mode 3 (from the bag, param 1, or the trader's goods, 2): a
## ready spell only into an empty pile; a keystone into an empty pile when
## the party's knowledge ≥ its complexity and stamina ≥ its cost
## a rune only next to a keystone (no ready spell), fewer than 8
## runes, of a type the keystone allows, and with the pile's sums plus its own
## complexity / stamina within the party's limits.
func _spell_accepts(it: String) -> bool:
	if s_wait:
		return false
	if Items.is_spell_container(it) or Items.is_keystone(it):
		if s_spell != "":
			return false
		var sp := Items.spell_code(it)
		if Items.is_spell_container(it):
			return true
		if not Spells.mods_of(sp).is_empty():
			return false
		var need := Spells.constr_sums(sp, [])
		var lim := _s_limits(sp)
		return int(need.y) <= lim.y and int(need.x) <= lim.x
	if Items.kind(it) != "rune" or s_spell == "" or s_ready():
		return false
	if not Spells.constr_rune_fits(s_spell, s_runes.size(), it.substr(5)):
		return false
	var need := Spells.constr_sums(s_spell, s_runes + [it])
	var lim := _s_limits(s_spell)
	return int(need.x) <= lim.x and int(need.y) <= lim.y


##  mode 3: [label, total, ✓ possible]. A ready spell: take
## apart, trunc(price × 0.1) (deal mode 3); a keystone + runes: build,
## Σ trunc(piece × 0.2) (mode 2) when accepts it (else no label
## and 0). A piece from the trader adds its buy price (mode 0).
func _spell_deal() -> Array:
	if s_spell == "":
		return ["", 0, false]
	var ready := s_ready()
	var total := 0
	var ok := true
	var pieces: Array = [_s_item()] + s_runes
	var froms: Array = [s_from] + s_rune_from
	for i in pieces.size():
		if not ready:
			total += Items.deal_price(pieces[i], Items.Deal.SPELL_CONSTR)
		if froms[i] == "shop":
			total += Items.deal_price(pieces[i], Items.Deal.SPELL_BUY)
			ok = ok and shop_left(pieces[i]) >= 0
		else:
			ok = ok and bag_count(pieces[i]) >= 0
	if ready:
		total += Items.deal_price(pieces[0], Items.Deal.SPELL_DECONSTR)
		return ["camp_spell_deconstr", total, ok]
	if not Spells.constr_buildable(
			hud.game.session.party_units(hud.game.session.my_index), spell_preview()):
		return ["", 0, false]
	return ["camp_spell_constr", total, ok]


## Option "switch_filters" (SwitchFilters, settings): when an item
## comes into a row (called by the camp screens' drops) and the
## row does not show everything, the row switches to the item's filter
## then it scrolls so the item is in view (scroll = index − 6
## when that is further right, index when the item is left of the view).
## Only row drops/returns and accepted camp transactions trigger this:
##  006111e0 / 00611720 / 0062d0c0, not arbitrary pickups.
## Remote commands wait for their named result to arrive in the row.
var _row_arrivals: Array[Dictionary] = []


func _row_counts() -> Dictionary:
	var out := {"bag": {}, "shop": {}}
	if hud == null:
		return out
	var st := hud.game.session.state
	var items: Array = st.items + st.quest_items.keys()
	if mode == "spellconstr":
		items += hero_spells().map(func(sp): return "spell:" + sp)
	for it: String in _unique(items):
		out.bag[it] = bag_count(it)
	for it: String in hud.game.session.shop_stock({"shop": shop_id}):
		out.shop[it] = shop_left(it)
	return out


func _rows_returned(before: Dictionary) -> void:
	var after := _row_counts()
	for row: String in ["bag", "shop"]:
		for it: String in after[row]:
			if int(after[row][it]) > int(before[row].get(it, 0)):
				_row_received(row, it)


func _arrival_count(row: String, it: String) -> int:
	if row == "shop":
		return hud.game.session.shop_count(it, {"shop": shop_id})
	return hud.game.session.state.items.count(it)


func _expect_received(row: String, it: String) -> void:
	if it.is_empty() or hud == null:
		return
	_row_arrivals.append({"row": row, "item": it, "count": _arrival_count(row, it),
		"shop": shop_id, "until": Time.get_ticks_msec() + 10000})


func _track_arrivals() -> void:
	var pending: Array[Dictionary] = []
	for r: Dictionary in _row_arrivals:
		if int(r.shop) != shop_id or Time.get_ticks_msec() >= int(r.until):
			continue
		if _arrival_count(r.row, r.item) > int(r.count):
			_row_received(r.row, r.item)
		else:
			pending.append(r)
	_row_arrivals = pending


func _row_received(row: String, it: String) -> void:
	if row == "bag":
		_bag_received(it)
	else:
		_shop_received(it)


func _bag_received(it: String) -> void:
	var quest: bool = it in hud.game.session.state.quest_items
	var kinds: Array = _filter_set(500)[2]
	if kinds[filter] != "all" and GameData.option("switch_filters") and not _passes(it, quest, kinds[filter]):
		for f in kinds.size():
			if kinds[f] != "all" and _passes(it, quest, kinds[f]):
				_set_bag_filter(f)
				break
	var idx := bag_items().find(it)
	if idx < 0:
		return
	if idx - 6 > scroll:
		scroll = idx - 6
	elif idx < scroll:
		scroll = idx


## The original keeps its separate item/spell goods rows even while hidden.
func _shop_received(it: String) -> void:
	var spellish := Items.is_spell_piece(it)
	var name := "spells" if spellish else "items"
	var shown := shop_row() and spell_shop() == spellish
	var row: Dictionary = _shop_rows[name].duplicate(true)
	if shown:
		row.filter = shop_filter
		row.scroll = shop_scroll
	var kinds: Array = _filter_set(0)[2] if shown else FILTER_SETS[name][2]
	if GameData.option("switch_filters") and not _passes(it, false, kinds[int(row.filter)]):
		for f in kinds.size():
			if _passes(it, false, kinds[f]):
				row.scrolls[int(row.filter)] = int(row.scroll)
				row.filter = f
				row.scroll = int(row.scrolls[f])
				break
	var items := []
	for id: String in hud.game.session.shop_stock({"shop": shop_id}):
		var sp := Items.is_spell_piece(id)
		if sp == spellish and shop_left(id) > 0 and _passes(id, false, kinds[int(row.filter)]):
			items.append(id)
	var idx := items.find(it)
	if idx >= 0:
		if idx - 6 > int(row.scroll):
			row.scroll = idx - 6
		elif idx < int(row.scroll):
			row.scroll = idx
	_shop_rows[name] = row
	if shown:
		shop_filter = int(row.filter)
		shop_scroll = int(row.scroll)


##  keeps a scroll offset for every filter.
func _set_bag_filter(f: int) -> void:
	_stop_transfer_hold()
	_bag_scrolls[filter] = scroll
	filter = f
	scroll = int(_bag_scrolls[f])


func _set_shop_filter(f: int) -> void:
	_stop_transfer_hold()
	var row: Dictionary = _shop_rows["spells" if spell_shop() else "items"]
	row.scrolls[shop_filter] = shop_scroll
	shop_filter = f
	shop_scroll = int(row.scrolls[f])


func bag_count(it: String) -> int:
	if it.begins_with("spell:") and mode == "itemconstr":
		return 0 if it == c_spell else 1
	var st := hud.game.session.state
	if mode == "swap":   # offered copies are already in PlayerSwap's native escrow
		return st.items.count(it)
	if it.begins_with("spell:"):
		# The bag's copies, plus a hero's known spell in the spell constructor
		# (listed in the bag row there), less what lies in the pile.
		var ns := st.items.count(it) - sell_pile.count(it)
		if mode == "spellconstr":
			ns += (1 if it.substr(6) in hero_spells() else 0) - _s_used(it, "bag") - _s_used(it, "known")
		return maxi(0, ns) if trade_wait else ns
	var n := st.items.count(it) + (1 if st.quest_items.has(it) else 0)
	var used := 1 if it == c_ready or it == c_bp else 0
	if c_mat != "" and it == Items.material_unit(c_mat) and c_bp != "":
		used = mini(Items.components(c_bp), n)
	var left := n - sell_pile.count(it) - repair_pile.count(it) - used - _s_used(it, "bag")
	return maxi(0,left) if trade_wait else left


func count_in_bag(it: String) -> int:
	return bag_count(it)


func _price(it: String, buying: bool) -> int:
	var spellish := Items.is_spell_piece(it)
	var mode_id := (Items.Deal.SPELL_BUY if spellish else Items.Deal.BUY) if buying else (Items.Deal.SPELL_SELL if spellish else Items.Deal.SELL)
	return Items.deal_price(it,mode_id,Shops.coef(shop_id))


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
			cancel = c_ready != "" or c_bp != "" or c_mat != "" or c_spell != ""
			if c_ready != "":
				label = "camp_item_deconstr"
				can = true
				total = constr_cost()
			elif c_bp != "" and c_mat != "":
				label = "camp_item_constr"
				can = c_spell == "" or Items.can_enchant("%s.%s" % [c_bp.substr(3), c_mat], c_spell.trim_prefix("spell:"))
				total = constr_cost()
		"spellconstr":
			cancel = s_spell != ""
			var sd := _spell_deal()
			label = sd[0]
			total = sd[1]
			can = sd[2] and not s_wait
	if trade_wait:
		can = false
		cancel = false
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
	s_kind = "keystone"
	s_from = ""
	s_runes.clear()
	s_rune_from.clear()
	s_wait = false
	c_bp = ""
	c_mat = ""
	c_ready = ""
	c_spell = ""


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
	if c_spell != "":
		cost += Items.constr_piece_price("spell:" + c_spell.trim_prefix("spell:"))   # (piece, 6)
	return cost


func _on_yes() -> void:
	_stop_transfer_hold()
	if not deal_info()[2]:
		return
	if mode == "weapons":
		#  mode 0: "camp_repair_all", the worn weapons and armour.
		for it in _worn_items():
			if Items.wear(it) > 0.0:
				construct.emit({"t": "repair", "unit": _unit.uid, "item": it})
		return
	if mode == "spellconstr":
		# One host transaction (Session._spell_constr); the pile stays until
		# its answer (constr_result).
		var pile := [[_s_item(), s_from]]
		for i in s_runes.size():
			pile.append([s_runes[i], s_rune_from[i]])
		_s_req += 1
		s_wait = true
		_sig = ""
		construct.emit({"t": "spell_constr", "unit": _unit.uid if _unit else -1, "pile": pile, "req": _s_req})
		_update_total()
		return
	if mode == "itemconstr":
		if c_ready != "":
			var inf := Items.info(c_ready)
			_expect_received("bag", "bp:" + String(inf.base))
			_expect_received("bag", Items.material_unit(String(inf.material)))
			if Items.spell_of(c_ready) != "":
				_expect_received("bag", "spell:" + Items.spell_of(c_ready))
			construct.emit({"t": "deconstruct", "item": c_ready})
		elif c_bp != "" and c_mat != "":
			# Prefer the bag copy when the hero also knows this spell. The
			# host consumes "spell:<id>" from the bag, a bare id from the hero.
			var sp := c_spell if c_spell in hud.game.session.state.items else c_spell.trim_prefix("spell:")
			var result := "%s.%s" % [c_bp.substr(3), c_mat]
			if sp != "":
				result += "|" + sp.trim_prefix("spell:")
			_expect_received("bag", result)
			construct.emit({"t": "construct", "bp": c_bp, "mat": c_mat, "spell": sp,
				"unit": _unit.uid if _unit else -1})
		_clear_constr()
		_sig = ""
		_update_total()
		return
	if mode == "repair":
		if not repair_pile.is_empty():
			for it: String in repair_pile:
				_expect_received("bag", Items.with_wear(it, 0.0))
			repair.emit(repair_pile.duplicate())
		repair_pile.clear()
		_sig = ""
		_update_total()
		return
	if buy_pile.is_empty() and sell_pile.is_empty():
		return
	for it: String in buy_pile:
		_expect_received("bag", it)
	for it: String in sell_pile:
		if Items.kind(it) != "loot":
			_expect_received("shop", Items.with_wear(it, 0.0))
	_trade_req += 1
	trade_wait = true
	deal.emit(buy_pile.duplicate(), sell_pile.duplicate())
	_sig = ""
	_update_total()


## A map transfer can invalidate a request before the host accepts it.
## Drop its local offer and ignore any late result from that world.
func reset_transactions() -> void:
	_stop_transfer_hold()
	trade_wait = false
	_trade_req += 1
	_s_req += 1
	buy_pile.clear()
	sell_pile.clear()
	repair_pile.clear()
	_clear_constr()
	_row_arrivals.clear()
	_sig = ""


## Reliable state precedes this result, so the bag and all stacks change
## together. Keep an unsuccessful offer for correction or cancellation.
func trade_result(e: Dictionary) -> void:
	if not trade_wait or int(e.get("req", -1)) != _trade_req: return
	trade_wait = false
	if bool(e.get("ok", false)):
		buy_pile.clear()
		sell_pile.clear()
	else:
		_row_arrivals.clear()
	_sig = ""
	_update_total()


## The host's answer to this screen's "spell_constr" (mode 3):
## taken apart, the keystone and runes take the spell's place in the pile
## built, the new spell does. A refusal changes
## nothing and leaves the pile as it was.
func constr_result(e: Dictionary) -> void:
	if not s_wait or int(e.get("req", -1)) != _s_req:
		return
	s_wait = false
	var items: Array = e.get("items", [])
	if bool(e.get("ok", false)) and not items.is_empty():
		s_runes.clear()
		s_rune_from.clear()
		s_spell = Items.spell_code(String(items[0]))
		s_kind = Items.kind(String(items[0]))
		s_from = "known" if String(e.get("where", "")) == "known" else "bag"
		if String(e.get("op", "")) == "take_apart":
			for i in range(1, items.size()):
				s_runes.append(String(items[i]))
				s_rune_from.append("bag")
	_sig = ""
	_update_total()


func _on_cancel() -> void:
	_stop_transfer_hold()
	if trade_wait: return
	var rows := _row_counts()
	var returns: Array[Array] = []
	if mode in ["itemtrade", "spelltrade"]:
		#   for each whole pile, then
		#  once with that transfer's last inserted/merged item.
		# The goods return precedes the bag return; current inventory order
		# cannot recover the pile order after clearing the staged entries.
		if not buy_pile.is_empty():
			returns.append(["shop", String(buy_pile.back())])
		if not sell_pile.is_empty():
			returns.append(["bag", String(sell_pile.back())])
	elif mode == "repair" and not repair_pile.is_empty():
		returns.append(["bag", String(repair_pile.back())])
	_clear_constr()
	repair_pile.clear()
	buy_pile.clear()
	sell_pile.clear()
	if mode in ["itemtrade", "spelltrade", "repair"]:
		for r: Array in returns:
			_row_received(r[0], r[1])
	else:
		_rows_returned(rows)   # construction pieces retain their separate return path
	_sig = ""
	_update_total()


func refresh(u: GameUnit) -> void:
	if u != _unit:
		_stop_transfer_hold()
	_unit = u
	_sig = ""
	if _ready_done:
		set_mode(mode)


func _process(_dt: float) -> void:
	_process_transfer_hold(_dt)
	if _turn_dir != 0:
		if not is_visible_in_tree() or mode != "weapons" or tutorial_visible() \
				or not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or TouchInput.holding(self)):
			_turn_dir = 0
		else:
			_doll.turn_camp_by(_turn_dir * TURN_SPEED * _dt)
	var ctrl := Input.is_key_pressed(KEY_CTRL) or _touch_spell_info
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
		_row_arrivals.clear()
		return
	if mode == "swap":
		_swap_sync()
	_track_arrivals()
	var u := _unit
	var h: Dictionary = u.get_meta("hero") if u and u.has_meta("hero") else {}
	var bag := bag_items()
	scroll = clampi(scroll, 0, maxi(0, bag.size() - BAG_CELLS))
	var shop := shop_items() if shop_row() else []
	shop_scroll = clampi(shop_scroll, 0, maxi(0, shop.size() - BAG_CELLS))
	var sig := "%s|%s|%s|%s|%s|%d|%d|%s|%s|%s|%s|%d|%d|%d" % [u.uid if u else -1, h.get("weapons", []), h.get("armors", []),
		[h.get("quick", []), h.get("spells", []), h.get("perks", []), h.get("exp", 0), h.get("skills", {})], bag, filter, scroll, size, mode, shop, buy_pile + ["/"] + sell_pile + ["/"] + repair_pile + [c_bp, c_mat, c_ready, c_spell, s_spell, s_kind, s_from, s_wait, trade_wait] + s_runes + s_rune_from + hero_spells(), shop_filter, shop_scroll,
		hud.game.session.state.money] + str(hash(hud.game.session.state.shops.get(shop_id, {}))) + _swap_view()
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
	if trading() or mode == "swap":
		var buys := _unique(buy_pile) if trading() else buy_pile
		var sells := _unique(sell_pile) if trading() else sell_pile
		for i in PILE_CELLS:
			_content["buy%d" % i] = [buys[i] if i < buys.size() else "", "buy"]
			_content["sell%d" % i] = [sells[i] if i < sells.size() else "", "sell"]
	elif mode == "repair":
		for i in REPAIR_CELLS:
			_content["rep%d" % i] = [repair_pile[i] if i < repair_pile.size() else "", "rep"]
	elif mode == "spellconstr":
		# a ready spell at (250,300), a keystone at (350,300)
		# the runes four per column from (450,150).
		var ready := s_ready()
		_content["sready"] = [_s_item() if ready else "", "sready"]
		_content["skey"] = [_s_item() if not ready else "", "skey"]
		for i in PILE_CELLS:
			_content["srune%d" % i] = [s_runes[i] if i < s_runes.size() else "", "srune"]
	elif mode == "itemconstr":
		# A ready item shows its parts; a blueprint + material the result.
		var bp := c_bp
		var mat := c_mat
		if c_ready != "":
			bp = Items.blueprint(Items.plain(c_ready))
			mat = String(Items.info(c_ready).material)
		var result := c_ready if c_ready != "" else ("%s.%s" % [bp.substr(3), mat] if bp != "" and mat != "" else "")
		if c_ready == "" and c_spell != "" and Items.can_enchant(result, c_spell.trim_prefix("spell:")):
			result += "|" + c_spell.trim_prefix("spell:")
		_content["cready"] = [result, "cready"]
		_content["cbp"] = [bp, "cbp"]
		_content["cspell"] = [c_spell, "cspell"]
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
		var weapons := Session.weapon_slots(h)
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
			var id := String(_content.get(k, [""])[0])
			# Spell cards are drawn directly below. An empty SubViewport can
			# retain an opaque first frame, so it must not cover that artwork.
			_views[k].visible = not id.is_empty() and not Items.is_spell_piece(id)
			_views[k].show_item("" if Items.is_spell_piece(id) else id)
	queue_redraw()


## Side buttons shown now (see SIDE_BUTTONS).
func side_buttons() -> Array:
	if mode == "swap":
		return ["accept", "cancel", "exit"]
	var out := []
	for b: String in SIDE_BUTTONS:
		match b:
			"exit": out.append(b)
			"accept", "cancel":
				# Training applies on each skill/perk click; this screen has
				# no pending deal for these controls to accept or cancel.
				if mode == "spells" and GameData.option("ui_active_buttons") != 0:
					continue
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
	if TouchInput.enabled:
		var nearest := ""
		var distance := INF
		for b: String in side_buttons():
			var rect: Rect2 = SIDE_BUTTONS[b][0]
			var radius := maxf(0.0, (TouchInput.target_pixels() / _s() - rect.size.x) * 0.5)
			var d := p.distance_to(rect.get_center())
			if rect.grow(radius).has_point(p) and d < distance:
				nearest = b
				distance = d
		return nearest
	return ""


func _press_side(b: String) -> void:
	if mode == "swap":
		_swap_side(b)
		queue_redraw()
		return
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


## Remake, the gamepad (PadUI): the cells, mode buttons, filters and row
## arrows on show as snap targets, in viewport pixels; the D-pad moves between
## them and A clicks as the mouse does.
func pad_targets() -> Array:
	var out: Array = []
	var xf := get_global_transform_with_canvas()
	var add := func(r800: Rect2, id: String):
		out.append({"rect": xf * _r(r800), "id": id})
	for k: String in _slot_keys():
		if _key_shown(k):
			add.call(_slot_rect(k), k)
	for b: String in side_buttons():
		add.call(SIDE_BUTTONS[b][0], "side:" + b)
	if mode == "spells" and _unit and _unit.has_meta("hero"):
		add.call(REFUND_RECT, "refund_training")
	var rows := [500.0]
	if _key_shown("shop0"):
		rows.append(0.0)
	for y0: float in rows:
		for i in FILTER_RECTS.size():
			add.call(Rect2(FILTER_RECTS[i].position + Vector2(0, y0), FILTER_RECTS[i].size), "filter%d:%d" % [y0, i])
		add.call(_row_arrow_rect(y0, false), "left:%d" % y0)
		add.call(_row_arrow_rect(y0, true), "right:%d" % y0)
	return out


func pad_active() -> bool:
	return not tutorial_visible()


static func _row_arrow_rect(y0: float, right: bool) -> Rect2:
	# Keep the corrected target, including the adjacent cell's edge;
	# arrow hit tests run before item hit tests.
	return Rect2(738 if right else 30, y0 + 35, 32, 30)


func _row_hit(p: Vector2, y0: float) -> int:
	# Filter buttons: 0..5; scroll left / right: 10 / 11; -1 none.
	for right in [false, true]:
		var rect := _row_arrow_rect(y0, right)
		if TouchInput.enabled:
			rect = rect.grow_individual(0, 10, 0, 10)
		if rect.has_point(p):
			return 11 if right else 10
	for i in FILTER_RECTS.size():
		if Rect2(FILTER_RECTS[i].position + Vector2(0, y0), FILTER_RECTS[i].size).has_point(p):
			return i
	return -1


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT] \
			or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		_turn_dir = 0
		_hold_cmd = {}
		_stop_transfer_hold()


func _input(e: InputEvent) -> void:
	#  captures the mouse; stops on release even
	# outside the arrow. Catch release before another control can consume it.
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		_turn_dir = 0
		_hold_cmd = {}
		_stop_transfer_hold()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_update_hover((e.position - _o()) / _s())
		return
	if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_hold_cmd = {}
		_turn_dir = 0
	# The top row's right-button handler (widget
	# input = WM_RBUTTONDOWN):
	# a cell index below the hero's weapon count and below 4 plays
	# buttons\camp\change.wav and makes that weapon the current one (
	# shown by the hero widget), then the screen
	# refreshes. Remake: Session "select_weapon".
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and mode == "weapons" and _unit:
		var rp: Vector2 = (e.position - _o()) / _s()
		var weapons := Session.weapon_slots(_unit.get_meta("hero", {}))
		for i in mini(4, weapons.size()):
			if _slot_rect("top%d" % i).has_point(rp):
				if GameSound.instance:
					GameSound.instance.ui("buttons\\camp\\change.wav")
				construct.emit({"t": "select_weapon", "unit": _unit.uid, "item": weapons[i]})
				accept_event()
				return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	_stop_transfer_hold()
	var p: Vector2 = (e.position - _o()) / _s()
	if mode == "weapons":
		for i in TURN_RECTS.size():
			if TURN_RECTS[i].has_point(p):
				_turn_dir = 1 if i == 0 else -1
				if GameSound.instance:
					GameSound.instance.ui("buttons\\camp\\move.wav")
				accept_event()
				return
	var side := _side_at(p)
	if side:
		_press_side(side)
		accept_event()
		return
	# The hero widget's arrows (modes 0 / 1): plays
	# buttons\camp\hero.wav and steps the hero
	# (widget).
	if mode in ["weapons", "spells"]:
		for a in [[Rect2(0, 125, 30, 20), -1], [Rect2(170, 125, 30, 20), 1]]:
			if (a[0] as Rect2).has_point(p):
				if GameSound.instance:
					GameSound.instance.ui("buttons\\camp\\hero.wav")
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
			_set_bag_filter(hit)
		else:
			scroll += -1 if hit == 10 else 1
		accept_event()
		return
	if shop_row():
		hit = _row_hit(p, 0)
		if hit >= 0:
			_row_sound(hit)
			if hit < 10:
				_set_shop_filter(hit)
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
			_press(id, where)
			picked.emit(id, where if where == "bag" else "info")
		else:
			_move(id, where)
			_start_transfer_hold(id, where)
			picked.emit(id, "info")
		queue_redraw()
		accept_event()
		return


##  in the dressing (mode 0) and skills (mode 1) screens: the
## press acts at once. refuses with buttons\messbox\cancel.wav
## a bag item (area 1) goes on the hero through
## (put_on.wav first, then nothing when the list is full: weapons > 3, belt
## > 3, spells > 7; armour displaces the worn piece of its slot through
## put_off.wav), a hero's item (area 0: weapons, belt, armour
## spells) into the bag through (put_off.wav). The host commands
## check again (Session._item_command). Remake: away from a village and the
## map's camp (Session.camp_available) the press is refused the same way.
func _press(id: String, where: String) -> void:
	if _unit == null or not _unit.has_meta("hero"):
		return
	var h: Dictionary = _unit.get_meta("hero")
	var from_bag := where == "bag"
	if not _press_accepts(id, from_bag, h) or not hud.game.session.camp_available():
		_ui_sound("buttons\\messbox\\cancel.wav")
		return
	var cmd := {"unit": _unit.uid, "item": id}
	if from_bag:
		_ui_sound("buttons\\camp\\put_on.wav")
		var k := Items.kind(id)
		if id.begins_with("spell:"):
			if hero_spells().size() > 7:
				return
			cmd["t"] = "learn"
		elif k == "weapon":
			if Array(h.get("weapons", [])).size() > 3:
				return
			cmd["t"] = "equip"
		elif k == "armor":
			if Array(h.get("armors", [])).any(func(a): return Items.slot(a) == Items.slot(id)):
				_ui_sound("buttons\\camp\\put_off.wav")
				for old: String in h.get("armors", []):
					if Items.slot(old) == Items.slot(id):
						_expect_received("bag", old)
			cmd["t"] = "equip"
		else:
			if Array(h.get("quick", [])).size() >= CampaignState.BELT_SLOTS:
				return
			cmd["t"] = "give_quick"
	else:
		_ui_sound("buttons\\camp\\put_off.wav")
		_expect_received("bag", id)
		match where:
			"belt": cmd["t"] = "take_quick"
			"known": cmd["t"] = "unlearn"
			_: cmd["t"] = "unequip"
	construct.emit(cmd)


##  modes 0 / 1 (area 1 = the bag, else the hero): the dressing
## screen takes weapons, armour and quick items, but no broken weapon or
## armour from the bag (round(durability) < 1); the skills screen takes from
## the bag only a spell the hero can learn (complexity within round(knowledge),
## stamina), from the hero anything. Duplicate spell objects
## are accepted too; the eight-object cap is enforced by the put-on handler.
func _press_accepts(id: String, from_bag: bool, h: Dictionary) -> bool:
	var k := Items.kind(id)
	if mode == "weapons":
		if from_bag and k in ["weapon", "armor"] and Items.is_broken(id):
			return false
		return k in ["weapon", "armor", "quick"]
	if not from_bag:
		return true
	if not id.begins_with("spell:"):
		return false
	return Spells.usable_by(h, _unit.max_mana, id.substr(6))


func _ui_sound(wav: String) -> void:
	press_sounds.append(wav.get_file())
	if press_sounds.size() > 16:
		press_sounds.remove_at(0)
	if GameSound.instance:
		GameSound.instance.ui(wav)


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
		return 28 if mode == "swap" else (17 if spells else 11)   #  flag
	if k.begins_with("sell"):
		return 29 if mode == "swap" else (18 if spells else 12)
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


func _pile_accepts(pile: Array, id: String) -> bool:
	return buy_pile.size()+sell_pile.size() < Session.MAX_TRADE_ITEMS \
		and (pile.has(id) or _unique(pile).size() < PILE_CELLS)


func _transfer_available(id: String, where: String) -> bool:
	if id.is_empty() or hud == null or trade_wait or not trading():
		return false
	if where == "shop":
		return _row_accepts(id, true) and shop_left(id) > 0 and _pile_accepts(buy_pile, id)
	if where == "bag":
		return _row_accepts(id, false) and not id in hud.game.session.state.quest_items \
			and bag_count(id) > 0 and _pile_accepts(sell_pile, id)
	return false


func _start_transfer_hold(id: String, where: String) -> void:
	if not _transfer_available(id, where):
		return
	_transfer_hold = {"item": id, "where": where, "mode": mode, "shop": shop_id}
	_transfer_t = -TRANSFER_DELAY


func _stop_transfer_hold() -> void:
	_transfer_hold = {}
	_transfer_t = 0.0


func _process_transfer_hold(dt: float) -> void:
	if _transfer_hold.is_empty():
		return
	var held := _transfer_hold
	if not is_visible_in_tree() or tutorial_visible() or held.mode != mode or held.shop != shop_id \
			or not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or TouchInput.holding(self)) \
			or not _transfer_available(held.item, held.where):
		_stop_transfer_hold()
		return
	_transfer_t += dt
	if _transfer_t < 0.0:
		return
	# One copy per tick at most: a stalled frame must not dump a whole stack.
	_transfer_t = TRANSFER_INTERVAL * -1.0
	_move(held.item, held.where)
	if not _transfer_available(held.item, held.where):
		_stop_transfer_hold()


## Trade screens: goods -> buy pile, bag -> sell pile, a pile -> back.
func _move(id: String, where: String) -> void:
	var rows := _row_counts()
	_move_now(id, where)
	_rows_returned(rows)


func _move_now(id: String, where: String) -> void:
	if trade_wait: return
	if mode == "swap":
		_swap_move(id, where)
		return
	if mode == "spellconstr":
		if s_wait:
			return
		var have := shop_left(id) if where == "shop" else bag_count(id)
		if where in ["bag", "shop"] and have > 0 and _spell_accepts(id):
			var from := where
			if where == "bag" and id.begins_with("spell:"):
				# A bag copy first, else the hero's known spell.
				var st := hud.game.session.state
				from = "bag" if st.items.count(id) - _s_used(id, "bag") > 0 else "known"
			if Items.is_spell_container(id) or Items.is_keystone(id):
				s_spell = Items.spell_code(id)
				s_kind = Items.kind(id)
				s_from = from
			else:
				s_runes.append(id)
				s_rune_from.append(from)
		elif where == "srune":
			#  case 6: a rune goes back where it came .
			var i := s_runes.rfind(id)
			if i >= 0:
				s_runes.remove_at(i)
				s_rune_from.remove_at(i)
		elif where in ["sready", "skey"]:
			_clear_constr()   # the keystone / ready spell: the whole pile goes back
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
		elif id.begins_with("spell:") and _spell_fits(id):
			c_spell = id
		elif where == "bag" and Items.can_deconstruct(id):
			_clear_constr()
			c_ready = id
		_sig = ""
		_update_total()
		return
	match where:
		"shop":
			if trading() and _pile_accepts(buy_pile, id) and shop_left(id) > 0:
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
		"cspell":
			c_spell = ""
		"bag":
			if mode == "repair":
				if Items.wear(id) > 0.0 and repair_pile.size() < REPAIR_CELLS and bag_count(id) > 0:
					repair_pile.append(id)
				_sig = ""
				_update_total()
				return
			# The same check as the row prices (_row_accepts).
			var ok := _row_accepts(id, false) and not id in hud.game.session.state.quest_items
			if ok and _pile_accepts(sell_pile, id) and bag_count(id) > 0:
				sell_pile.append(id)
	_sig = ""
	_update_total()


##  (camp) for the item rows' prices: whether the
## screen takes the item now (from the trader's goods row, or the bag).
func _row_accepts(it: String, goods: bool) -> bool:
	var k := Items.kind(it)
	var spellish := Items.is_spell_piece(it)
	match mode:
		"spelltrade":
			return spellish
		"itemtrade":
			return not spellish and k != "quest"
		"spellconstr":
			return _spell_accepts(it)   # the same check for the bag and the goods
		"itemconstr":
			if not goods:
				return false
			if it.begins_with("spell:"):
				return _spell_fits(it)
			var empty := c_bp == "" and c_mat == "" and c_ready == ""
			if k == "blueprint" or Items.can_deconstruct(it):
				return empty
			if k == "material":
				return c_bp != "" and c_mat == "" and _mat_fits(c_bp, it.trim_prefix("material."))
			return false
		"repair":
			return goods and k in ["weapon", "armor"] and Items.wear(it) > 0.0
	return false


##  mode 5 for a spell: a blueprint and its material lie in the
## pile (the item makes), no spell yet, and the spell fits that
## item (Items.can_enchant).
func _spell_fits(spell: String) -> bool:
	if c_bp == "" or c_mat == "" or c_spell != "" or c_ready != "":
		return false
	return Items.can_enchant("%s.%s" % [c_bp.substr(3), c_mat], spell.trim_prefix("spell:"))


func _mat_fits(bp: String, mat: String) -> bool:
	return Items.materials_for(bp).any(func(m): return String(m.name).to_lower() == mat)


func _filter_set(y0: float) -> Array:
	var fset: Array = FILTER_SETS["bag" if y0 > 0 else ("spells" if spell_shop() else "items")]
	if mode in ["itemconstr", "spellconstr"]:
		fset = fset.duplicate(true)
		fset[2][0 if y0 > 0 else 5] = "constructor"
	return fset


func _get_tooltip(pos: Vector2) -> String:
	var p := (pos - _o()) / _s()
	var side := _side_at(p)
	if side:
		var tip: int = SWAP_TIPS[side] if mode == "swap" else SIDE_BUTTONS[side][2]
		return GameData.text("tip %d" % tip).strip_edges()
	for y0 in ([500.0, 0.0] if shop_row() else [500.0]):
		var hit := _row_hit(p, y0)
		if hit >= 0 and hit < 10:
			if _filter_set(y0)[2][hit] == "constructor":
				return _str(MODE_TITLES[mode])
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
static func _row_end_uv(pos: float, count: int, right: bool) -> Rect2:
	# the original shaded arrow is in the next 50-pixel
	# atlas strip. Figure shifts U by 50/256 while scrolling is possible.
	var show_arrow := pos < count - BAG_CELLS if right else pos > 0.0
	var u := (142 if right else 192) + (50 if show_arrow else 0)
	return Rect2(u, 14, 50 if right else -50, 100)


func _draw_row(y0: float, tex: String, fset: Array, sel: int) -> void:
	for i in BAG_CELLS:
		_region(tex, Rect2(50 + i * 100, y0, 100, 100), Rect2(14, 14, 100, 100))
	var pos := 0 if fset.is_empty() else (shop_scroll if y0 == 0 else scroll)
	var count := 0 if fset.is_empty() else (shop_items().size() if y0 == 0 else bag_items().size())
	_region(tex, Rect2(0, y0, 50, 100), _row_end_uv(pos, count, false))
	_region(tex, Rect2(750, y0, 50, 100), _row_end_uv(pos, count, true))
	if fset.is_empty():
		return   # the swap screen's name row (hides the filters)
	for i in FILTER_RECTS.size():
		var r: Rect2 = FILTER_RECTS[i]
		var uv: Rect2 = FILTER_UV[i]
		uv.position.x += fset[0]
		_region(tex, Rect2(r.position + Vector2(0, y0), r.size), uv, Color.WHITE if i == sel else Color(0.6, 0.6, 0.6))


func _draw() -> void:
	# Only the controls are inset. Keep the original black backdrop across
	# the whole window, including the phone's reserved cutout margins.
	draw_rect(get_global_transform_with_canvas().affine_inverse() * get_viewport_rect(), Color.BLACK)
	var s := _s()
	_draw_backdrop()
	if mode == "spells":
		# Spell slots: the campslots star frame (UV 14,142-114,242; approx.:
		# mode 1's top row widget is not traced).
		for i in 8:
			_region("campslots", Rect2(i * 100, 0, 100, 100), Rect2(14, 142, 100, 100))
	elif mode != "weapons":
		if mode == "swap":
			_draw_row(0, "inventorym01", [], -1)
		else:
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
	_draw_row(500, "inventory01", _filter_set(500), filter)
	_draw_side()
	var d := deal_info()
	for b: String in side_buttons():
		# the mode buttons (and Exit) at 0.5, the current one
		# 1.0;: ✓ / ✗ at 0.5 unless the deal can be made / undone.
		var lit := side_lit(b, d)
		if mode == "swap":
			# ✓ lit while this player has not agreed, ✗ once it has.
			var agreed := bool(_swap().mine().get("agreed", false))
			lit = (b == "accept" and not agreed) or (b == "cancel" and agreed)
		elif b == "accept":
			lit = d[2]
		elif b == "cancel":
			lit = d[3]
		_region("campinfo", SIDE_BUTTONS[b][0], SIDE_BUTTONS[b][1], Color.WHITE if lit else Color(0.5, 0.5, 0.5))
	# Spells, templates and runes fill the square cell with their own artwork.
	# The shared 3D item-card model leaves large perspective-dependent gaps.
	for k: String in _content:
		var id := String(_content[k][0])
		if not _key_shown(k) or not Items.is_spell_piece(id): continue
		var texture := String(Items.look(id).get("texture", ""))
		var picture := SpellSlots.icon(texture) if not texture.is_empty() else null
		if picture:
			var rect := _r(_slot_rect(k).grow(-10.0))
			draw_texture_rect(picture, rect, false)
			if Items.is_spell_container(id):
				# Keep the shop price and stack count clear. Camp cells have room
				# for one strip below the price; the small HUD uses two rows.
				SpellSlots.draw_runes(self, Items.spell_code(id), rect.grow_individual(0, 0, 0, 10.0 * s), Color.WHITE, 8)
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
			var count := 1 if pile == "rep" else (buy_pile.count(it) if pile == "buy" else sell_pile.count(it))
			if count > 1:
				_t(Rect2(r.position.x+15,r.position.y+15,70,20), str(count), 1, Interface800.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
			var price := Items.repair_price(it) if pile == "rep" else _price(it, pile == "buy")
			_t(Rect2(r.position.x + 15, r.position.y + 65, 70, 20), str(price), 1, Interface800.TEXT,
				HORIZONTAL_ALIGNMENT_CENTER)


# ------------------------------------------------------------ swap screen

func _swap() -> PlayerSwap:
	return hud.game.session.swap


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


## The swap screen opens (: both piles empty, the money field "").
func swap_open() -> void:
	set_mode("swap")
	sell_pile = (_swap().mine().get("items", []) as Array).duplicate()
	buy_pile = (_swap().partner_offer().get("items", []) as Array).duplicate()
	swap_money = ""
	_swap_sent_t = -10.0
	_sig = ""


## Per frame: the partner's pile is its offer
## as the host has it; this player's own pile and money follow the host's
## table too once it has not changed them for a moment (a refused change).
func _swap_sync() -> void:
	var sw := _swap()
	buy_pile = (sw.partner_offer().get("items", []) as Array).duplicate()
	var m := sw.mine()
	if m.is_empty() or _now() - _swap_sent_t < 0.75:
		return
	if m.items != sell_pile:
		sell_pile = (m.items as Array).duplicate()
	if int(m.money) != _swap_money_value():
		swap_money = str(m.money) if int(m.money) > 0 else ""


func _swap_money_value() -> int:
	return clampi(int(swap_money) if swap_money.is_valid_int() else 0, 0, PlayerSwap.MONEY_MAX)


## What the left side shows (the redraw signature).
func _swap_view() -> String:
	if mode != "swap" or hud == null:
		return ""
	var sw := _swap()
	return "%s|%s|%s" % [sw.mine(), sw.partner_offer(), swap_money]


## this player's offer as it is now.
func _swap_publish() -> void:
	_swap_sent_t = _now()
	swap_cmd.emit({"t": "set", "items": sell_pile.duplicate(), "money": _swap_money_value()})
	_sig = ""
	queue_redraw()


## The money field: digits and Backspace; each change is a new
## offer (reads the field's changed flag, atoi). True if used.
func swap_type(e: InputEventKey) -> bool:
	if mode != "swap":
		return false
	if e.keycode == KEY_BACKSPACE:
		if swap_money.is_empty():
			return false
		swap_money = swap_money.left(-1)
	elif e.unicode >= 48 and e.unicode <= 57:
		if swap_money.length() >= PlayerSwap.MONEY_DIGITS:
			return true
		swap_money += char(e.unicode)
	else:
		return false
	_swap_publish()
	return true


## ✓ agrees (buy.wav) when this player's offer is not agreed
## yet and its money covers the amount offered, else cancel.wav; ✗ takes the
## agreement back (cancel.wav); Exit withdraws the offer (transit.wav).
func _swap_side(b: String) -> void:
	var m := _swap().mine()
	match b:
		"accept":
			var st := hud.game.session.state
			if not m.is_empty() and not bool(m.agreed) and _swap_money_value() <= st.money \
					and not _swap().partner_offer().is_empty():
				_ui_sound("buttons\\camp\\buy.wav")
				swap_cmd.emit({"t": "agree", "rev": int(_swap().partner_offer().rev)})
			else:
				_ui_sound("buttons\\messbox\\cancel.wav")
		"cancel":
			if not m.is_empty() and bool(m.agreed):
				_ui_sound("buttons\\messbox\\cancel.wav")
				swap_cmd.emit({"t": "disagree"})
		"exit":
			_ui_sound("buttons\\globalmap\\transit.wav")
			swap_cmd.emit({"t": "withdraw"})


## a bag item into the offer pile (put_on.wav), an item of the
## own pile back to the bag (put_off.wav); the partner's pile takes no press.
## The remake's pile holds what its 8 cells show (cancel.wav when full).
func _swap_move(id: String, where: String) -> void:
	match where:
		"bag":
			if sell_pile.size() >= PILE_CELLS or bag_count(id) <= 0:
				_ui_sound("buttons\\messbox\\cancel.wav")
				return
			_ui_sound("buttons\\camp\\put_on.wav")
			sell_pile.append(id)
			_swap_publish()
		"sell":
			if sell_pile.has(id):
				_ui_sound("buttons\\camp\\put_off.wav")
				_expect_received("bag", id)
				sell_pile.erase(id)
				_swap_publish()


##  text surfaces (see the header) and (300).
func _draw_swap_side() -> void:
	var sw := _swap()
	var po := sw.partner_offer()
	if not po.is_empty():
		_tb(Rect2(20, 110, 160, 20), _lmp("xch_remote_header", "Your partner's response to proposed swap:"), 1, Color.WHITE, 2)
		_t(Rect2(0, 150, 200, 20), _lmp("xch_remote_ok", "Agreed") if bool(po.agreed) else _lmp("xch_remote_cancel", "Do not agree"),
			1, Interface800.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		_tb(Rect2(20, 210, 160, 20), _lmp("xch_money_remote", "Amount you are offered for a swap:"), 1, Color.WHITE, 2)
		_t(Rect2(0, 250, 200, 20), str(int(po.money)), 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_region("campinfo", Rect2(0, 280, 100, 40), Rect2(254, 34, -100, 40))
	_region("campinfo", Rect2(100, 280, 100, 40), Rect2(154, 34, 100, 40))
	_tb(Rect2(20, 310, 160, 20), _lmp("xch_money_offer", "Amount you offered for a swap:"), 1, Color.WHITE, 2)
	_t(Rect2(0, 350, 200, 16), swap_money, 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	# The field's caret after the text (colour).
	var f := Interface800.font()
	var w := f.get_string_size(swap_money, HORIZONTAL_ALIGNMENT_LEFT, -1, _fpx(1)).x / _s()
	if int(_now() * 2.0) % 2 == 0:
		draw_rect(_r(Rect2(100 + w * 0.5 + 1, 351, 1.5, 14)), Color8(0xff, 0xb3, 0x31))
	var money: int = hud.game.session.state.money
	_t(Rect2(0, 410, 200, 20), "%s %d" % [_lmp("xch_current_money", "Your money:"), money], 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_t(Rect2(0, 430, 200, 20), _lmp("xch_accept", "Confirm swap"), 1, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)


## A textslmp "string <key>" (GameData.text falls back to textsLmp.res).
static func _lmp(key: String, fallback: String) -> String:
	var t := _str(key) if GameData.is_open() else ""
	return fallback if t.is_empty() or t == key else t


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
	#  truncates the point size; CreatePointFont
	# then truncates DPI * tenths / 720. At 96 DPI, font 0 is 13 px at 800
	# wide and 24 px in the 1440-wide camp at 1920×1080, not 14 / 25.
	var tenths := int(_s() * [104, 112, 144][fi])
	return maxi(6, int(tenths * 96.0 / 720.0))


## One font line in 800×600 units.
func _lh(fi: int) -> float:
	return Interface800.font().get_height(_fpx(fi)) / _s()


## unwrapped text from the rect's top (800 units), with a
##  shadow. Approx.: overflow gets "..." on the left or spills left
## on the right; the original DrawText uses only the alignment flags.
func _t(r: Rect2, txt: String, fi := 0, col := Interface800.TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if txt.is_empty():
		return
	var f := Interface800.font()
	var fs := _fpx(fi)
	var rr := _r(r)
	#  adds two physical pixels after scaling the text rect.
	rr.size += Vector2(2, 2)
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
## "infoitem_35" / "infoitem_36" alone, or with a keystone in the pile
## "%s %d (%d)": the party's limit (camp) and the pile's
## complexity / stamina.
func _draw_constr_limits() -> void:
	var r1 := Rect2(210, 450, 190, 20)
	var r2 := Rect2(210, 470, 190, 20)
	# the numbers only with a keystone in the pile — the party's
	# best knowledge with the summed complexity, the best
	# stamina with __ftol(max(summed cost, the keystone's)).
	if s_spell == "" or s_ready():
		_t(r1, _lbl(35), 1, Interface800.TEXT)
		_t(r2, _lbl(36), 1, Interface800.TEXT)
		return
	var need := Spells.constr_sums(s_spell, s_runes)
	var lim := _s_limits(s_spell)
	var key_mana := float(Spells.parse(s_spell).proto.get("mana", 0.0))
	_t(r1, "%s %d (%d)" % [_lbl(35), lim.x, int(need.x)], 1, Interface800.TEXT)
	_t(r2, "%s %d (%d)" % [_lbl(36), lim.y, int(maxf(need.y, key_mana))], 1, Interface800.TEXT)


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
			if _hover_desc.size() > 2 and _hover_desc[2] is Dictionary and _hover_desc[2].get("t") == "perk":
				_draw_perk_desc(_hover_desc)
			elif _hover_desc.size() > 2 and _hover_desc[2] is Dictionary and _hover_desc[2].get("t") == "skill":
				_draw_skill_desc(_hover_desc)
			else:
				_tb(Rect2(615, 110, 170, 15), String(_hover_desc[0]), 0, Color.WHITE, 2)
				_tb(Rect2(615, 140, 170, 15), String(_hover_desc[1]), 0, Interface800.TEXT, 16)
	_overlay.queue_redraw()
	if mode == "spellconstr":
		_draw_constr_limits()
	if mode == "swap":
		_draw_swap_side()
		return
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
		if GameData.option("ui_active_buttons") != 0:
			_tb(Rect2(12, 450, 176, 15), RemakeText.t("Changes apply immediately."),
				0, Interface800.TEXT, 3)
		_draw_skills()


## The constructors' result shown in the left widget (
func _result_item() -> String:
	if mode == "itemconstr":
		return String(_content.get("cready", [""])[0])
	if mode == "spellconstr":
		#  mode 3 →: the ready spell, else the spell
		# the builder makes of the keystone and runes.
		return "spell:" + spell_preview() if s_spell != "" else ""
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
## A keystone uses the spell rows; a blueprint's name and
## description come from "instr <prototype>" (loot mode 2).
func _item_info(id: String) -> Dictionary:
	var out := {"name": Items.title(id), "rows": PackedStringArray(), "gap": 15.0, "desc": "", "lines": 4,
		"tail_at": 0.0, "tail": PackedStringArray()}
	var rows: PackedStringArray = out.rows
	var tt := Items.type_text(id)
	rows.append("%s %s" % [_lbl(37), tt])
	var k := Items.kind(id)
	if Items.is_spell_container(id) or Items.is_keystone(id):
		var sp := Items.spell_code(id)
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
		out.name = Items.log_name(id)
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
		out.desc = Items.flavor(id)
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
		rows.append("%s %d" % [_lbl(2), int(Items.energy(id))])
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
	if inf.has("wrap"):
		out.append("")
		out.append(String(inf.wrap))
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
## Skill and perk hover panes follow numeric
## skill rows and three-rank table; platform font/wrap metrics are separate.
func _draw_skills() -> void:
	_skill_rows.clear()
	if _unit == null or not _unit.has_meta("hero"):
		return
	var h: Dictionary = _unit.get_meta("hero")
	var xp := float(h.get("exp", 0.0))
	var mine := hud != null and _unit.controller == hud.game.session.my_index
	var at_camp := mine and hud.game.session.camp_available()
	var refundable := at_camp and not _unit.dead and TrainingRefund.amount(h) > 0.0
	_region("campinfo", REFUND_RECT, Rect2(124, 138, 40, 15))
	_t(Rect2(REFUND_RECT.position + Vector2(2, 6), REFUND_RECT.size - Vector2(4, 8)),
		RemakeText.t("Refund all points"), 0, Interface800.TEXT if refundable else DIM, HORIZONTAL_ALIGNMENT_CENTER)
	var refund_help := TrainingRefund.reason(h)
	if refund_help.is_empty():
		if not mine:
			refund_help = "You can only refund your own character's points."
		elif _unit.dead:
			refund_help = "A dead character cannot refund points."
		elif not at_camp:
			refund_help = "Points can be refunded in a village or camp."
		else:
			refund_help = "Resets all skills and abilities, including starting ranks and skill gifts, and refunds their points. Base attributes, equipment and earned XP stay."
	_skill_rows.append([REFUND_RECT, {"t": "refund_training", "unit": _unit.uid} if refundable else {},
		[RemakeText.t("Refund all points"), RemakeText.t(refund_help)], "refund"])
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
		_skill_rows.append([r, {"t": "train", "unit": _unit.uid, "stat": sk} if mine and lv < 100 and xp >= c else {},
			_skill_desc(sk, _unit), "skill"])
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
		_skill_rows.append([r, cmd, _perk_desc("%s%d" % [fam, n], n, h), "perk"])
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
			_perk_desc(code, 0, h), "perk"])
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


## Native info-widget cases1/2: raw skill level, then effective combat/use
## value for the relevant skills. These display rows do not train a skill.
static func _skill_desc(skill: String, u: GameUnit) -> Array:
	var t := GameData.text("perk " + skill) if GameData.is_open() else ""
	var ls := Array(t.split("\n"))
	var title := String(ls.pop_front()).strip_edges() if not ls.is_empty() else skill
	var body := " ".join(ls.map(func(x): return String(x).strip_edges())).strip_edges()
	var h: Dictionary = u.get_meta("hero", {})
	var level := Skills.level(h, skill)
	var numeric := ["%s %d" % [_str("infoskill_5"), level]]
	if skill in ["melee", "archery", "science"]:
		#  read the current float Dexterity
		# including temporary modifiers. Client runtime stats carry it too.
		var dex := float(PackedFloat32Array([float(u.stats.get("dex",
			float(h.get("dex", 20.0)) + Perks.attr_bonus(h, "dex")))])[0])
		numeric.append("%s %d" % [_str("infoskill_9" if skill == "science" else "infoskill_6"),
			int(level + dex - 25.0)])
	elif skill == "backstab":
		#  multiplies the unsigned perk modifier by a float32
		# 0.01, adds BackstabAdd and the pane truncates its percentage. Keep
		# that coefficient: native rank2 displays749%, not a rounded750%.
		var base := float(PackedFloat32Array([GameData.ai_value("RPG", "BackstabAdd", 3.0)])[0])
		var factor := float(PackedFloat32Array([0.01])[0])
		numeric.append("%s %d%%" % [_str("infoskill_7"), int((base + Perks.best(h, "bs") * factor) * 100.0)])
	return [title, body, {"t": "skill", "numeric": numeric}]


func _draw_skill_desc(desc: Array) -> void:
	_tb(Rect2(615, 110, 170, 15), String(desc[0]), 0, Color.WHITE, 2)
	var y := 140.0
	for line: String in desc[2].numeric:
		_t(Rect2(615, y, 170, 15), line)
		y += 15.0
	_tb(Rect2(615, y + 15, 170, 15), String(desc[1]), 0, Interface800.TEXT, 13)


static func _perk_desc(code: String, known := 0, h: Dictionary = {}) -> Array:
	#  strips the rank before loads "perk
	# <family>0": its first field is the title, the rest the description.
	var fam := code.rstrip("0123456789")
	var t := GameData.text("perk " + fam + "0") if GameData.is_open() else ""
	var ls := Array(t.split("\n"))
	var title := String(ls.pop_front()).strip_edges() if not ls.is_empty() else fam
	var body := " ".join(ls.map(func(x): return String(x).strip_edges())).strip_edges()
	var ranks := []
	var table := GameData.db.table("perks") if GameData.is_open() else []
	var first := table.find(Perks.get_perk(fam + "1"))
	if first >= 0:
		var group := first / 3
		for i in 3:
			if first + i >= table.size():
				break
			var row: Dictionary = table[first + i]
			var rank_code := String(row.get("code", ""))
			var rank := GameData.text("perk " + rank_code).get_slice("\n", 0).strip_edges()
			var effect := _perk_help_effect(group, int(row.get("modifier", 0)))
			var cost := Perks.cost(rank_code, h)
			ranks.append({"code": rank_code, "title": rank, "effect": effect,
				"cost": 2147483647 if cost < 0 else cost, "known": i < known})
	return [title if title else Perks.title(code), body, {"t": "perk", "ranks": ranks}]


##  perk-family switch: the label comes from infoskill_N.
## Values are the native display modifiers, separate from combat formulas.
static func _perk_help_effect(group: int, modifier: int) -> String:
	var key := -1
	var value := modifier
	var percent := false
	if group < 7:
		key = 10
	elif group < 15:
		key = 11
	elif group in [15, 16, 17, 18, 19, 20, 21, 22]:
		key = {15: 12, 16: 14, 17: 15, 18: 16, 19: 17, 20: 3, 21: 1, 22: 22}[group]
		value = (modifier + 100) >> 1 if group == 15 else modifier + (300 if group == 22 else 100)
		percent = true
	elif group < 26:
		key = 23
	if key < 0:
		return ""
	return "     %s %d%s" % [_str("infoskill_%d" % key), value, "%" if percent else ""]


## Native info-widget case3: a fixed two-line title, three rank blocks,
## learned mark aligned right, then at most six lines of family prose.
func _draw_perk_desc(desc: Array) -> void:
	_tb(Rect2(615, 110, 170, 15), String(desc[0]), 0, Color.WHITE, 2)
	var y := 140.0
	for row: Dictionary in desc[2].ranks:
		_t(Rect2(615, y, 170, 15), String(row.title))
		if row.known:
			_t(Rect2(615, y, 170, 15), _str("infoskill_21"), 0, Interface800.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		_t(Rect2(615, y + 15, 170, 15), String(row.effect))
		_t(Rect2(615, y + 30, 185, 15), "     %s %d" % [_str("infoskill_18"), int(row.cost)])
		y += 45.0
	_tb(Rect2(615, 290, 170, 15), String(desc[1]), 0, Interface800.TEXT, 6)


func side_lit(button: String, deal_state: Array = []) -> bool:
	var d := deal_info() if deal_state.is_empty() else deal_state
	if button == "accept":
		return bool(d[2])
	if button == "cancel":
		return bool(d[3])
	# User-requested availability feedback. Off preserves the original
	# mode-selection tint, where usable inactive buttons also look dim.
	return button == mode or (GameData.option("ui_active_buttons") != 0 and button in side_buttons())
