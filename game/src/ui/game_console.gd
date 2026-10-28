extends CanvasLayer
## Local editor and output. Campaign commands always pass through Session's
## authenticated console command path, including the separate local host.
const Commands = preload("res://src/game/console_commands.gd")
const HELP = ConsoleCatalog.ROWS
const FONT = preload("res://fonts/LiberationMono-Regular.ttf")
var panel:PanelContainer
var output:RichTextLabel
var input:CodeEdit
var prompt:Label
var search:LineEdit
var suggestions:ItemList
var hint:Label
var title:Label
var unlock_button:Button
var unlocked:=false
var placement:="t"
var history:=PackedStringArray()
var lines:=PackedStringArray()
var line_limit:=500
var history_index:=0
var font_size:=16
var _draft:=""
var _session:Session
var _request:=0
var _dump_files:={}
var _reports:={}
var _exec_depth:=0
var _exec_remaining:=0
var _candidates:Array[Dictionary]=[]
var _editing:=false
var _buttons:Array[Dictionary]=[]
var _cursor_interval:=0.0
var _cursor_next_usec:=0

func _button(parent:Control,text:String,tip:String,action:Callable) -> Button:
	var b:=Button.new();b.text=RemakeText.t(text);b.tooltip_text=RemakeText.t(tip)
	b.pressed.connect(action);parent.add_child(b);_buttons.append({"button":b,"text":text,"tip":tip})
	return b

func _ready():
	process_mode=Node.PROCESS_MODE_ALWAYS;layer=120;visible=false
	set_process(false)
	panel=PanelContainer.new();add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color("151d2af5")
	style.border_color=Color("486184");style.set_border_width_all(1);style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel",style);panel.add_theme_font_override("font",FONT)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",6);panel.add_child(box)
	var header:=HFlowContainer.new();box.add_child(header)
	title=Label.new();title.add_theme_color_override("font_color",Color("9ecfff"));header.add_child(title)
	unlock_button=_button(header,"Enable commands","Unlock console commands.",func():run("thingamabob");input.grab_focus())
	_button(header,"Help","Search commands and examples.",func():run("help");input.grab_focus())
	_button(header,"Find","Find in console output (Ctrl+F).",_find_output)
	_button(header,"Copy","Copy console output.",func():run("copy"))
	_button(header,"A−","Decrease console text size.",func():_resize_text(-1))
	_button(header,"A+","Increase console text size.",func():_resize_text(1))
	_button(header,"×","Close console (Esc).",_close)
	search=LineEdit.new();search.visible=false;search.max_length=256;box.add_child(search)
	search.text_changed.connect(func(_text):_render_output())
	output=RichTextLabel.new();output.size_flags_vertical=Control.SIZE_EXPAND_FILL
	output.scroll_following=true;output.selection_enabled=true;output.bbcode_enabled=false
	output.add_theme_font_override("normal_font",FONT);output.add_theme_color_override("default_color",Color("d5deed"));box.add_child(output)
	suggestions=ItemList.new();suggestions.visible=false;suggestions.allow_reselect=true
	suggestions.focus_mode=Control.FOCUS_NONE;suggestions.custom_minimum_size.y=100
	suggestions.item_selected.connect(func(index):_accept_completion(index));box.add_child(suggestions)
	var row:=HBoxContainer.new();box.add_child(row)
	prompt=Label.new();prompt.text=">";prompt.add_theme_color_override("font_color",Color("9ecfff"));row.add_child(prompt)
	input=CodeEdit.new();input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	input.syntax_highlighter=ConsoleCatalog.highlighter();input.auto_brace_completion_enabled=true
	input.auto_brace_completion_highlight_matching=true;input.line_folding=false;input.indent_automatic=false
	input.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;input.highlight_current_line=false
	input.add_theme_color_override("font_color",Color("eef3fa"));row.add_child(input)
	input.text_changed.connect(_changed);input.caret_changed.connect(func():if not _editing:_complete.call_deferred(false))
	hint=Label.new();hint.clip_text=true;hint.add_theme_color_override("font_color",Color("acbbd0"));box.add_child(hint)
	_load_preferences();_refresh_labels();get_viewport().size_changed.connect(_layout);_layout()
	visibility_changed.connect(func():
		if visible:_refresh_labels();_render_output();_bind_session();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;input.grab_focus()
	)

## Cursor diagnostics use local real time, including while the console is closed
## or the campaign is paused. A delayed frame produces one sample, no catch-up burst.
func _process(_dt:float):
	if _cursor_interval<=0.0:return
	var now:=Time.get_ticks_usec()
	if now<_cursor_next_usec:return
	_cursor_next_usec=now+roundi(_cursor_interval*1000000.0)
	_log_cursor()

func _log_cursor():
	var point:=get_viewport().get_mouse_position()
	var text:=_cursor_text(point)
	# Keep hidden-console sampling cheap; reopening redraws retained output.
	lines.append(text)
	while lines.size()>line_limit:lines.remove_at(0)
	if visible:_render_output()
	print("[cursor] ",text)

func _cursor_text(point:Vector2) -> String:
	var seconds:=Time.get_ticks_msec()/1000.0
	var s:=_bind_session()
	if s and not s.loading_game and not s._remote_loading and is_instance_valid(s.game) \
			and is_instance_valid(s.world) and s.game.world==s.world and s.world.terrain \
			and is_instance_valid(s.game.rig) and is_instance_valid(s.game.rig.camera) \
			and get_viewport().get_visible_rect().has_point(point):
		# Use the same terrain/BASE-face projection as gameplay orders. These
		# are EI map x/y, not viewport pixels or Godot x/z coordinates.
		var ground:Variant=s.game.pick_ground(point)
		var bounds:=Vector2(s.world.nav.size)*NavGrid.CELL
		if ground is Vector2 and ground.is_finite() and Rect2(Vector2.ZERO,bounds).has_point(ground):
			# Truncate inside the map so formatting a point next to the outer
			# edge cannot round it up to teleport's excluded upper bound.
			ground=Vector2(floorf(ground.x*1000.0),floorf(ground.y*1000.0))/1000.0
			var command:="teleport %.3f %.3f"%[ground.x,ground.y]
			return RemakeText.t("Cursor at %.3f s: map x=%.3f, y=%.3f | %s")%[seconds,ground.x,ground.y,command]
	return RemakeText.t("Cursor at %.3f s: x=%.1f, y=%.1f px")%[seconds,point.x,point.y]+" | "+RemakeText.t("No map ground under cursor.")

func _cursor(words:PackedStringArray):
	if words.size()==1:_log_cursor();return
	if words.size()==2 and words[1].to_lower()=="off":
		_cursor_interval=0.0;set_process(false)
		append(RemakeText.t("Cursor logging stopped."));return
	var valid:=words.size() in [2,3] and words[1].to_lower()=="on"
	if valid and words.size()==3:valid=words[2].is_valid_float()
	var interval:=float(words[2]) if valid and words.size()==3 else 0.1
	if not valid or not is_finite(interval) or interval<0.05 or interval>10.0:
		append(RemakeText.t("Usage: %s")%"cursor [on [0.05..10]|off]");return
	_cursor_interval=interval
	_cursor_next_usec=Time.get_ticks_usec()+roundi(interval*1000000.0)
	append(RemakeText.t("Cursor logging every %.2f s. Use cursor off to stop.")%interval)
	_log_cursor();set_process(true)

func _refresh_labels():
	title.text=RemakeText.t("Developer console")
	for row:Dictionary in _buttons:
		row.button.text=RemakeText.t(row.text);row.button.tooltip_text=RemakeText.t(row.tip)
	unlock_button.visible=not unlocked
	search.placeholder_text=RemakeText.t("Find in output…")
	input.placeholder_text=RemakeText.t("Type a command or help…")
	_hint()

func _layout():
	var size:=get_viewport().get_visible_rect().size
	panel.add_theme_font_size_override("font_size",font_size)
	output.add_theme_font_size_override("normal_font_size",font_size)
	input.add_theme_font_size_override("font_size",font_size)
	input.custom_minimum_size.y=font_size*3
	suggestions.custom_minimum_size.y=font_size*5
	var rect:=Rect2(Vector2.ZERO,Vector2(size.x,minf(size.y,maxf(300,size.y*0.6))))
	match placement:
		"b":rect.position.y=size.y-rect.size.y
		"c":rect.position.y=(size.y-rect.size.y)*0.5
		"l":rect.size=Vector2(maxf(size.x*0.5,minf(480,size.x)),size.y)
		"r":rect.size=Vector2(maxf(size.x*0.5,minf(480,size.x)),size.y);rect.position.x=size.x-rect.size.x
		"f":rect.size=size
	panel.position=rect.position;panel.size=rect.size

func _resize_text(delta:int):
	font_size=clampi(font_size+delta,12,28);_layout();_save_preferences()

func _close():
	visible=false;suggestions.hide();input.release_focus();search.release_focus()

func _find_output():
	suggestions.hide();search.show();search.grab_focus();search.select_all()

func _input(e:InputEvent):
	if not e is InputEventKey or not e.pressed:return
	if e.physical_keycode==KEY_QUOTELEFT and not e.echo:
		if visible:_close()
		else:visible=true
		get_viewport().set_input_as_handled();return
	if not visible:return
	var ctrl:bool=e.ctrl_pressed or e.meta_pressed
	if ctrl and e.keycode==KEY_F:_find_output()
	elif ctrl and e.shift_pressed and e.keycode==KEY_C:run("copy")
	elif ctrl and e.keycode==KEY_L:run("clear")
	elif ctrl and e.keycode==KEY_R:
		input.grab_focus();_history_choices()
	elif ctrl and e.keycode==KEY_SPACE:
		input.grab_focus();_complete(true)
	elif UiInput.is_cancel(e):
		if suggestions.visible:suggestions.hide()
		elif search.visible:search.text="";search.hide();_render_output();input.grab_focus()
		else:_close()
	elif e.keycode in [KEY_PAGEUP,KEY_PAGEDOWN]:
		var bar:=output.get_v_scroll_bar();bar.value+=(-1 if e.keycode==KEY_PAGEUP else 1)*bar.page
	elif input.has_focus():
		match e.keycode:
			KEY_ENTER,KEY_KP_ENTER:_submit(input.text)
			KEY_TAB:
				if not suggestions.visible:_complete(true)
				if suggestions.visible:_accept_completion(_suggestion_index())
			KEY_UP,KEY_DOWN:
				var direction:=-1 if e.keycode==KEY_UP else 1
				if suggestions.visible:
					var index:=posmod(_suggestion_index()+direction,_candidates.size())
					suggestions.select(index);suggestions.ensure_current_is_visible();_hint(index)
				else:_recall(direction)
			_:return
	else:return
	get_viewport().set_input_as_handled()

func _set_input(text:String,caret:int=-1):
	_editing=true;input.text=text;input.set_caret_column(text.length() if caret<0 else caret);_editing=false
	suggestions.hide();_hint()

func _changed():
	if _editing:return
	var text:=input.text.replace("\n"," ").replace("\r"," ").substr(0,4096)
	if text!=input.text:
		var caret:=input.get_caret_column()
		for i in input.get_caret_line():caret+=input.get_line(i).length()+1
		_set_input(text,mini(caret,text.length()))
	_complete(false)

func _complete(force:bool=false):
	if _editing or not visible or not input.has_focus():return
	_hint()
	if input.text.is_empty() and not force:suggestions.hide();return
	_candidates=ConsoleCatalog.candidates(input.text,input.get_caret_column(),_bind_session())
	_show_candidates()

func _show_candidates():
	suggestions.clear()
	for row:Dictionary in _candidates:
		var label:=String(row.text)
		if not String(row.get("help","")).is_empty():label+="   ·   "+String(row.help)
		suggestions.add_item(label);suggestions.set_item_tooltip(suggestions.item_count-1,label)
	suggestions.visible=not _candidates.is_empty()
	if suggestions.visible:suggestions.select(0);_hint(0)

func _suggestion_index() -> int:
	var selected:=suggestions.get_selected_items()
	return selected[0] if not selected.is_empty() else 0

func _accept_completion(index:int):
	if index<0 or index>=_candidates.size():return
	var row:=_candidates[index]
	var text:=input.text.substr(0,row.start)+String(row.insert)+input.text.substr(row.end)
	_set_input(text.substr(0,4096),int(row.start)+int(row.offset));input.grab_focus()

func _hint(index:int=-1):
	if not hint:return
	hint.text=String(_candidates[index].get("help","")) if index>=0 and index<_candidates.size() else ConsoleCatalog.hint(input.text)
	if hint.text.is_empty():hint.text=ConsoleCatalog.hint(input.text)
	hint.tooltip_text=hint.text

func _recall(direction:int):
	if history_index==history.size():_draft=input.text
	history_index=clampi(history_index+direction,0,history.size())
	_set_input(history[history_index] if history_index<history.size() else _draft)

func _history_choices():
	_candidates=[]
	for i in range(history.size()-1,-1,-1):
		if not history[i].to_lower().contains(input.text.to_lower()):continue
		_candidates.append({"text":history[i],"insert":history[i],"start":0,"end":input.text.length(),"offset":history[i].length(),"help":RemakeText.t("Command history")})
		if _candidates.size()>=16:break
	_show_candidates()

func append(text:String):
	for line:String in text.split("\n"):lines.append(line)
	while lines.size()>line_limit:lines.remove_at(0)
	_render_output()

func _render_output():
	var bar:=output.get_v_scroll_bar();var at:=bar.value;var following:=at+bar.page>=bar.max_value-2
	var query:=search.text.to_lower()
	output.clear();output.scroll_following=following
	for line:String in lines:
		if not query.is_empty() and not line.to_lower().contains(query):continue
		output.push_color(Color("9ecfff") if line.begins_with("> ") else Color("d5deed"))
		output.add_text(line+"\n");output.pop()
	if not following:bar.set_deferred("value",at)

func _find_session(node:Node) -> Session:
	var fallback:Session
	if node is Session and not node.local_host.worker:
		if node.local_host.frontend or node.is_host:return node
		fallback=node
	for child:Node in node.get_children():
		var found:=_find_session(child)
		if found:
			if found.local_host.frontend or found.is_host:return found
			if fallback==null:fallback=found
	return fallback

func _bind_session() -> Session:
	var s:=_find_session(get_tree().root)
	if s!=_session:
		if is_instance_valid(_session) and _session.console_output.is_connected(_received):_session.console_output.disconnect(_received)
		_dump_files.clear();_reports.clear();_session=s
		if s:s.console_output.connect(_received)
	return s

func _received(result:PackedStringArray,request:int):
	if _dump_files.has(request):
		_write(_dump_files[request],"\n".join(result)+"\n");_dump_files.erase(request)
	elif _reports.has(request):
		var report:Dictionary=_reports[request];_reports.erase(request)
		_write(report.path,report.header+"\n"+"\n".join(result)+"\n\n"+report.log)
	else:
		for line:String in result:append(line)

func _path(name:String) -> String:
	if name.is_empty() or name!=name.get_file() or name in [".","..","history.json","settings.json"] or name.contains(":") or name.contains("\\"):return ""
	DirAccess.make_dir_recursive_absolute("user://console")
	return "user://console/"+name

func _write(path:String,contents:String):
	var f:=FileAccess.open(path,FileAccess.WRITE) if not path.is_empty() else null
	if f:
		f.store_string(contents)
		if f.get_error()==OK:append(RemakeText.t("Saved to %s")%ProjectSettings.globalize_path(path));return
	append(RemakeText.t("Could not read or write the console file."))

func _load_preferences():
	var path:="user://console/settings.json"
	if FileAccess.file_exists(path):
		var f:=FileAccess.open(path,FileAccess.READ)
		if f and f.get_length()<65536:
			var value:Variant=JSON.parse_string(f.get_as_text())
			if value is Dictionary:
				font_size=clampi(int(value.get("font_size",16)),12,28)
				if value.get("placement","t") in ["t","b","c","l","r","f"]:placement=value.placement
				line_limit=clampi(int(value.get("line_limit",500)),20,5000)
	path="user://console/history.json"
	if FileAccess.file_exists(path):
		var f:=FileAccess.open(path,FileAccess.READ)
		if f and f.get_length()<8388608:
			var value:Variant=JSON.parse_string(f.get_as_text())
			if value is Array:
				for row in value.slice(maxi(0,value.size()-200)):
					if row is String and row.length()<=4096:history.append(row)
	history_index=history.size()

func _save_preferences():
	DirAccess.make_dir_recursive_absolute("user://console")
	var f:=FileAccess.open("user://console/settings.json",FileAccess.WRITE)
	if f:f.store_string(JSON.stringify({"font_size":font_size,"placement":placement,"line_limit":line_limit}))

func _submit(line:String):
	_set_input("");line=line.strip_edges()
	if line.is_empty():return
	if history.is_empty() or history[-1]!=line:history.append(line)
	while history.size()>200:history.remove_at(0)
	history_index=history.size();_draft="";append("> "+line)
	DirAccess.make_dir_recursive_absolute("user://console")
	var f:=FileAccess.open("user://console/history.json",FileAccess.WRITE)
	if f:f.store_string(JSON.stringify(Array(history)))
	run(line)

func _report(name:String):
	var path:=_path(name)
	if path.is_empty():append(RemakeText.t("Could not read or write the console file."));return
	var header:=RemakeText.t("Version: %s | Platform: %s")%[str(ProjectSettings.get_setting("application/config/version","?")),OS.get_name()]
	header+="\n"+RemakeText.t("Renderer: %s | Adapter: %s | FPS: %d")%[RenderingServer.get_current_rendering_method(),RenderingServer.get_video_adapter_name(),Engine.get_frames_per_second()]
	var s:=_bind_session()
	if s and (s.is_host or s.local_host.frontend) and not s.loading_game and not s.movie_active() and not s.ending_active:
		_request+=1;_reports[_request]={"path":path,"header":header,"log":"\n".join(lines)}
		s.submit({"t":"console","line":"status","request":_request})
	else:_write(path,header+"\n\n"+"\n".join(lines))

func run(line:String):
	var words:=ConsoleTools.words(line)
	if words.is_empty():
		if not line.strip_edges().is_empty():append(RemakeText.t(Commands.ERROR))
		return
	var cmd:=words[0].to_lower()
	if cmd=="thingamabob" and words.size()==1:unlocked=true;_refresh_labels();append(RemakeText.t("Activated!"));return
	match cmd:
		"help":
			var rows:=ConsoleCatalog.help_rows(" ".join(words.slice(1)))
			for row:Dictionary in rows:
				append(row.syntax+" — "+row.description)
				if words.size()>1:append(RemakeText.t("Example: %s")%row.example)
			if rows.is_empty():append(RemakeText.t("No matches."))
			append(RemakeText.t("Console files are stored in %s.")%ProjectSettings.globalize_path("user://console"));return
		"console":
			if words.size()!=2 or not words[1] in ["t","b","c","l","r","f"]:append(RemakeText.t("Usage: %s")%"console t|b|c|l|r|f");return
			placement=words[1];_layout();_save_preferences();return
		"history":
			if words.size()!=2 or not words[1].is_valid_int():append(RemakeText.t("Usage: %s")%"history 20..5000");return
			line_limit=clampi(int(words[1]),20,5000);_save_preferences();append(RemakeText.t("Done."));return
		"clear":lines.clear();output.clear();return
		"copy":DisplayServer.clipboard_set("\n".join(lines));append(RemakeText.t("Console output copied."));return
		"log","report":
			if words.size()>2:append(RemakeText.t("Usage: %s")%(cmd+" [file]"));return
			var name:=words[1] if words.size()==2 else cmd+".txt"
			if cmd=="report":_report(name)
			else:_write(_path(name),"\n".join(lines)+"\n")
			return
		"lastfps":append(str(Engine.get_frames_per_second()));return
		"cursor":_cursor(words);return
	if not unlocked:append(RemakeText.t("Type thingamabob to unlock console commands."));return
	if cmd in ["quit","exit"]:get_tree().quit();return
	var s:=_bind_session()
	if s==null:append(RemakeText.t("Start or load a campaign first."));return
	if not s.is_host and not s.local_host.frontend:append(RemakeText.t("Only the host can change the campaign through the console."));return
	if s.loading_game or s.movie_active() or s.ending_active:append(RemakeText.t("Console gameplay commands are unavailable during loading or cinematics."));return
	_request+=1
	if cmd=="listvar" and words.size()==3:
		if words[1]!="0":append(RemakeText.t(Commands.ERROR));return
		var path:=_path(words[2])
		if path.is_empty():append(RemakeText.t("Could not read or write the console file."));return
		_dump_files[_request]=path;line="listvar 0"
	elif cmd in ["loadvar","exec"]:
		if words.size()!=(3 if cmd=="loadvar" else 2) or (cmd=="loadvar" and words[1]!="0"):
			append(RemakeText.t(Commands.ERROR));return
		var path:=_path(words[-1]);var f:=FileAccess.open(path,FileAccess.READ) if not path.is_empty() else null
		if f==null or f.get_length()>65536:append(RemakeText.t("Could not read or write the console file."));return
		var contents:=f.get_as_text()
		if cmd=="exec":
			if _exec_depth>=4:append(RemakeText.t(Commands.ERROR));return
			if _exec_depth==0:_exec_remaining=256
			_exec_depth+=1
			for row:String in contents.split("\n"):
				if row.strip_edges().is_empty():continue
				if _exec_remaining<=0:append(RemakeText.t("Command file limit reached (256 commands)."));break
				_exec_remaining-=1;run(row.strip_edges())
			_exec_depth-=1;return
		var values:={}
		for row:String in contents.split("\n"):
			var fields:=ConsoleTools.words(row.strip_edges())
			if fields.is_empty():continue
			if fields.size()!=2 or not fields[1].is_valid_float() or not is_finite(float(fields[1])):append(RemakeText.t(Commands.ERROR));return
			values[fields[0]]=float(fields[1])
		line="loadvars "+JSON.stringify(values)
	var selection:Array=[]
	if is_instance_valid(s.game):
		for u:GameUnit in s.game.selected:selection.append(u.uid)
	s.submit({"t":"console","line":line,"request":_request,"selection":selection})
