class_name WikiEquipment
extends Control
## The camp's eight ready slots, central paperdoll, side panels and spell row.
signal slot_requested(slot: String)
var _buttons := {}
var _body: Control
var _canvas: Control
var _doll: Paperdoll
var _board: TextureRect
var left_panel: VBoxContainer
var right_panel: VBoxContainer
var _left_frame: PanelContainer
var _right_frame: PanelContainer
var _plan_hash := 0
var _positions := {"helm":Vector2(0,0),"plate":Vector2(0,150),"leggins":Vector2(0,300),"shirt":Vector2(300,0),"gloves":Vector2(300,100),"pants":Vector2(300,200),"boots":Vector2(300,300)}
const LABELS := {"weapon":"Weapons","quick":"Belt","helm":"Helmets","plate":"Chest armour","leggins":"Leggings","shirt":"Shirts","pants":"Trousers","gloves":"Gloves","boots":"Boots","spell":"Spells"}
static func slot_label(slot: String) -> String:
	var type := WikiPlan.slot_type(slot)
	return RemakeText.t(LABELS.get(type,"Equipment"))+(" "+slot.trim_prefix(type) if type!=slot else "")
func setup(plan: Dictionary,catalog: WikiCatalog) -> void:
	if not _canvas:_build()
	var identity := hash([plan.entries,catalog])
	if identity==_plan_hash:return
	_plan_hash=identity
	var armors := [];var weapons := []
	for row: Dictionary in plan.entries:
		if not row.get("slot","") or not row.key.begins_with("item/"):continue
		var kind := Items.kind(row.variant)
		if kind=="armor":armors.append(row.variant)
		elif kind=="weapon":weapons.append(row.variant)
	_doll.show_info({"prototype":"human hero","armors":armors,"weapons":weapons.slice(0,1)})
	for slot: String in _buttons:
		var button: Button=_buttons[slot]
		for child in button.get_children():button.remove_child(child);child.queue_free()
		button.tooltip_text=RemakeText.t("Choose equipment")+": "+slot_label(slot)
		for row: Dictionary in plan.entries:
			if row.get("slot","")!=slot:continue
			var id: String="spell:"+WikiPlan.spell(row) if row.key.begins_with("spell/") else row.variant
			button.tooltip_text=slot_label(slot)+": "+(catalog.display_item_title(id) if row.key.begins_with("item/") else WikiCatalog.spell_title(WikiPlan.spell(row)))
			var preview: Control
			if Items.is_spell_piece(id):
				var icon := TextureRect.new();icon.texture=WikiWorkbench.piece_icon(id);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;preview=icon
			else:
				var model := WikiPreview.new();preview=model;button.add_child(model);model.show_model({"kind":"item","value":id})
			if not preview.get_parent():button.add_child(preview)
			preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);preview.offset_left=10;preview.offset_top=10;preview.offset_right=-10;preview.offset_bottom=-10
			break
	_layout()
func _build() -> void:
	_canvas=Control.new();add_child(_canvas)
	_left_frame=PanelContainer.new();_left_frame.add_theme_stylebox_override("panel",WikiCampArt.panel_style());_canvas.add_child(_left_frame)
	left_panel=VBoxContainer.new();left_panel.add_theme_constant_override("separation",12);_left_frame.add_child(left_panel)
	_right_frame=PanelContainer.new();_right_frame.add_theme_stylebox_override("panel",WikiCampArt.panel_style());_canvas.add_child(_right_frame)
	right_panel=VBoxContainer.new();right_panel.add_theme_constant_override("separation",12);_right_frame.add_child(right_panel)
	_body=Control.new();_canvas.add_child(_body)
	_board=TextureRect.new();_board.texture=WikiWorkbench.frame("camp");_board.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_board.mouse_filter=Control.MOUSE_FILTER_IGNORE;_body.add_child(_board)
	_doll=Paperdoll.new();_doll.mouse_filter=Control.MOUSE_FILTER_IGNORE;_body.add_child(_doll)
	for slot: String in WikiPlan.SLOTS:_make_slot(slot)
	if not resized.is_connected(_layout):resized.connect(_layout)
func _make_slot(slot: String) -> void:
	var button := Button.new();button.set_meta("equipment_slot",true)
	button.pressed.connect(func():slot_requested.emit(slot));_buttons[slot]=button
	var parent: Control=_body if _positions.has(slot) else _canvas;parent.add_child(button)
	for state: String in ["normal","hover","pressed"]:
		if _positions.has(slot):
			var style := StyleBoxFlat.new();style.bg_color=Color(0.8,0.7,0.4,0.16) if state!="normal" else Color.TRANSPARENT;button.add_theme_stylebox_override(state,style)
		else:
			var style := StyleBoxTexture.new();style.texture=WikiCampArt.texture(WikiPlan.slot_type(slot));style.modulate_color=Color(1.2,1.15,0.9) if state!="normal" else Color.WHITE;button.add_theme_stylebox_override(state,style)
func _layout() -> void:
	if not _canvas:return
	var compact := size.x<760
	var factor := size.x/800.0
	if not compact:factor=minf(factor,maxf(1.0,(get_viewport_rect().size.y-200.0)/600.0))
	custom_minimum_size.y=(1400 if compact else 600)*factor
	_canvas.scale=Vector2.ONE*factor;_canvas.position.x=(size.x-800*factor)/2;_canvas.size=Vector2(800,1400 if compact else 600)
	_left_frame.position=Vector2(0,100);_left_frame.size=Vector2(200,400)
	_right_frame.position=Vector2(600,100);_right_frame.size=Vector2(200,400)
	_body.position=Vector2(200,100);_body.size=Vector2(400,400);_body.scale=Vector2.ONE
	_board.size=Vector2(400,400);_doll.position=Vector2(100,20);_doll.size=Vector2(200,360);_doll.custom_minimum_size=Vector2.ZERO
	for slot: String in _buttons:
		var button: Button=_buttons[slot];button.size=Vector2(100,100)
		if _positions.has(slot):button.position=_positions[slot]
		elif WikiPlan.slot_type(slot)=="spell":button.position=Vector2((int(slot.trim_prefix("spell"))-1)*100,500)
		else:button.position=Vector2(WikiPlan.SLOTS.find(slot)*100,0)
	if compact:
		_canvas.scale=Vector2.ONE;_canvas.position.x=0
		var cell := size.x/4
		_body.position=Vector2(0,cell*2);_body.scale=Vector2.ONE*size.x/400
		for slot: String in _buttons:
			if _positions.has(slot):continue
			var index := WikiPlan.SLOTS.find(slot) if WikiPlan.slot_type(slot)!="spell" else int(slot.trim_prefix("spell"))-1
			_buttons[slot].position=Vector2((index%4)*cell,(index/4)*cell+(cell*2+size.x if WikiPlan.slot_type(slot)=="spell" else 0))
			_buttons[slot].size=Vector2.ONE*cell
		_left_frame.position=Vector2(0,cell*4+size.x);_left_frame.size=Vector2(size.x,350)
		_right_frame.position=Vector2(0,cell*4+size.x+350);_right_frame.size=Vector2(size.x,350)
		custom_minimum_size.y=cell*4+size.x+700
