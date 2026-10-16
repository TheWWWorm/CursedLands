class_name WikiWorkbench
extends Control
## The camp's actual construction layout, with keyboard/touch slot actions.
signal rune_removed(index: int)
var _slots: Array[Control] = []
var _positions: Array[Vector2] = []
var _background: TextureRect
var _current := ""
var board_size := 320.0

static func piece_icon(id: String) -> Texture2D:
	var look := Items.look(id)
	if not look.has("texture"):return null
	var image := GameData.load_image(look.texture)
	if image==null:return null
	image.flip_y()
	return ImageTexture.create_from_image(image)

static func frame(family: String) -> Texture2D:
	var board := Image.create(400,400,false,Image.FORMAT_RGBA8)
	for quadrant in 4:
		var image := WikiCampArt.crop(family+str(quadrant+1),Rect2i(28,28,200,200))
		if image==null:return null
		board.blit_rect(image,Rect2i(0,0,200,200),Vector2i((quadrant%2)*200,(quadrant/2)*200))
	return ImageTexture.create_from_image(board)

func setup(magic: String,item := "") -> void:
	var identity := GameData.campaign_id+"|"+magic+"|"+item
	if _current==identity:return
	_current=identity
	for child in get_children():remove_child(child);child.queue_free()
	_slots.clear();_positions.clear()
	_background=TextureRect.new();_background.texture=frame("constrspell" if item.is_empty() else "constritem");_background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_background)
	if item.is_empty():
		_slot(Vector2(0,150),"spell:"+magic,RemakeText.t("Result"))
		_slot(Vector2(100,150),"keystone:"+magic.get_slice("{",0),RemakeText.t("Keystone"))
		var runes := Spells.mods_of(magic)
		for i in 8:
			var id := "rune:"+String(runes[i]) if i<runes.size() else ""
			_slot(Vector2(200+(i/4)*100,(i%4)*100),id,WikiCatalog.rune_title(runes[i]) if id else RemakeText.t("Empty rune slot"),i if id else -1)
	else:
		_slot(Vector2(0,150),item,RemakeText.t("Result"))
		var info := Items.info(item)
		_slot(Vector2(100,100),"bp:"+String(info.base),RemakeText.t("Blueprint"))
		_slot(Vector2(100,200),"spell:"+magic if magic else "",RemakeText.t("Spell"))
		var count := Items.components("bp:"+String(info.base))
		for i in 8:_slot(Vector2(200+(i/4)*100,(i%4)*100),Items.material_unit(info.material) if i<mini(count,8) else "",RemakeText.t("Materials"))
	if not resized.is_connected(_layout):resized.connect(_layout)
	_layout()

func _slot(at: Vector2,id: String,label: String,index := -1) -> void:
	var button := Button.new();button.tooltip_text=(RemakeText.t("Remove")+": " if index>=0 else "")+label;button.set_meta("workbench_slot",true)
	for state: String in ["normal","hover","pressed"]:button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new();focus.bg_color=Color(0,0,0,0);focus.border_color=Color("d8b56b");focus.set_border_width_all(2);button.add_theme_stylebox_override("focus",focus)
	add_child(button);_slots.append(button);_positions.append(at)
	if index>=0:button.pressed.connect(func():rune_removed.emit(index))
	else:button.focus_mode=Control.FOCUS_NONE;button.mouse_filter=Control.MOUSE_FILTER_IGNORE
	if id:
		if Items.is_spell_piece(id):
			var image := TextureRect.new();image.texture=piece_icon(id);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(image);image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);image.offset_left=12;image.offset_top=12;image.offset_right=-12;image.offset_bottom=-12
		else:
			var preview := WikiPreview.new();preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(preview);preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);preview.offset_left=12;preview.offset_top=12;preview.offset_right=-12;preview.offset_bottom=-12;preview.show_model({"kind":"item","value":id})

func _layout() -> void:
	var extent := minf(size.x,board_size)
	custom_minimum_size.y=extent
	if not _background:return
	_background.size=Vector2(extent,extent)
	for i in _slots.size():_slots[i].position=_positions[i]*extent/400;_slots[i].size=Vector2.ONE*extent/4

static func workshop_theme(base: Theme) -> Theme:
	var result := base.duplicate() as Theme
	result.default_font_size=16
	for type: String in ["Label","Button","OptionButton","LineEdit","SpinBox"]:
		result.set_color("font_color",type,Color("e8e1c8"))
		result.set_color("font_hover_color",type,Color("fff4d2"))
		result.set_color("font_pressed_color",type,Color("fff4d2"))
		result.set_color("font_focus_color",type,Color("fff4d2"))
		result.set_color("font_disabled_color",type,Color("929a83"))
	result.set_color("font_placeholder_color","LineEdit",Color("b7bea6"))
	result.set_color("default_color","RichTextLabel",Color("e8e1c8"))
	result.set_color("table_odd_row_bg","RichTextLabel",Color("202a1e"))
	result.set_color("table_even_row_bg","RichTextLabel",Color("202a1e"))
	result.set_constant("table_h_separation","RichTextLabel",16)
	result.set_constant("table_v_separation","RichTextLabel",5)
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color=Color("34422b") if state in ["hover","pressed"] else Color("253020")
		style.border_color=Color("c3a86b") if state in ["focus","pressed"] else Color("667053")
		style.set_border_width_all(1);style.set_corner_radius_all(3);style.set_content_margin_all(7)
		for type: String in ["Button","OptionButton","LineEdit"]:result.set_stylebox(state,type,style)
	return result

static func workshop_panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new();style.bg_color=Color("161e16");style.set_content_margin_all(20)
	return style
