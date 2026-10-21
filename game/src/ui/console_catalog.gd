class_name ConsoleCatalog
extends RefCounted
## One source for discoverability, usage hints and non-executing completion.
## Examples only enter the editor; choosing a suggestion never runs a command.
const ROWS := [
	["help [filter]","Search commands and examples.","help teleport"],
	["thingamabob","Unlock console commands.","thingamabob"],
	["status","Show build, campaign, scene clock and party diagnostics.","status"],
	["party","List party names, IDs, health, energy and coordinates.","party"],
	["inspect [target]","Inspect selected units, hero, party, an ID or a script name.","inspect selected"],
	["heal [target]","Restore attached body parts and energy of living targets. Default: party.","heal party"],
	["god [on|off]","Show or change basic host-party invulnerability.","god on"],
	["teleport x y [target]","Place one living target on nearby walkable ground. Default: hero.","teleport 100 100 hero"],
	["zones [filter]","Find installed destinations by name or zone ID.","zones"],
	["travel zone [entrance]","Travel directly without completing quest requirements. Default entrance: 1.","travel gz1g 1"],
	["time [hour] [run|freeze]","Read, set or freeze scene time; the hour must be below 24.","time 12 freeze"],
	["give 0 money|exp amount","Give money or experience to the host party.","give 0 money 1000"],
	["getvar 0 name","Read a campaign variable.","getvar 0 gtime"],
	["setvar 0 name value","Change a campaign variable.","setvar 0 console_probe 1"],
	["listvar 0 [file]","Show or save campaign variables.","listvar 0 variables.txt"],
	["loadvar 0 file","Import campaign variables from a text file.","loadvar 0 variables.txt"],
	["exec file","Run console commands from a text file.","exec commands.txt"],
	["report [file]","Save build, renderer, campaign diagnostics and console output for a bug report.","report report.txt"],
	["log [file]","Save console output as plain text.","log console.txt"],
	["copy","Copy console output.","copy"],
	["clear","Clear console output.","clear"],
	["lastfps","Print rendered frames per second.","lastfps"],
	["console t|b|c|l|r|f","Place the console at the top, bottom, centre, left, right or fullscreen.","console f"],
	["history N","Set the number of retained output lines.","history 500"],
	["quit","Exit the game.","quit"],
	["exit","Exit the game.","exit"],
]

static func help_rows(filter: String = "") -> Array[Dictionary]:
	var all:Array[Dictionary]=[]
	for row:Array in ROWS:
		all.append({"name":String(row[0]).get_slice(" ",0),"syntax":row[0],"description":RemakeText.t(row[1]),"example":row[2]})
	for table:Dictionary in [ConsoleCommands.WRITES,ConsoleCommands.READS]:
		for name:String in table:
			var arguments:=PackedStringArray()
			for kind in String(table[name]):arguments.append(RemakeText.t("unit" if kind=="u" else ("text" if kind=="s" else "number")))
			var prefix:="@" if table==ConsoleCommands.WRITES else "#"
			var example:=prefix+name+"("+", ".join(arguments)+")"
			all.append({"name":name,"syntax":example,"description":RemakeText.t("Run a supported original script command." if prefix=="@" else "Read an original script expression."),"example":example})
	if filter.is_empty():return all
	var needle:=filter.to_lower().trim_prefix("@").trim_prefix("#")
	return all.filter(func(row):return (String(row.name)+" "+String(row.description)).to_lower().contains(needle))

static func hint(line: String) -> String:
	var token:=line.strip_edges().get_slice(" ",0)
	if token.begins_with("@") or token.begins_with("#"):
		token=token.substr(1).get_slice("(",0)
	for row:Dictionary in help_rows(token):
		if String(row.name).nocasecmp_to(token)==0:return row.syntax+"  ·  "+row.description
	return RemakeText.t("Tab: complete · Up/Down: suggestions or history · Enter: run · Ctrl+F: find output")

static func _word_char(ch: String) -> bool:
	return ch=="_" or ch.is_valid_int() or (ch.to_lower()>="a" and ch.to_lower()<="z")

static func _quote_start(text: String, caret: int) -> int:
	var start:=-1;var escaped:=false
	for i in caret:
		if escaped:escaped=false;continue
		if start>=0 and text[i]=="\\":escaped=true;continue
		if text[i]=='"':start=i if start<0 else -1
	return start

static func candidates(text: String, caret: int, s: Session = null) -> Array[Dictionary]:
	caret=clampi(caret,0,text.length())
	var script:=text.begins_with("@") or text.begins_with("#") or text.begins_with("$")
	var quote:=_quote_start(text,caret);var start:=caret;var end:=caret
	if quote>=0:
		start=quote+1
		while end<text.length() and text[end]!='"':end+=1
	else:
		while start>0 and (_word_char(text[start-1]) if script else text[start-1] not in [" ","\t"]):start-=1
		while end<text.length() and (_word_char(text[end]) if script else text[end] not in [" ","\t"]):end+=1
	var needle:=text.substr(start,caret-start).to_lower()
	var rows:Array[Dictionary]=[]
	if script and quote<0:
		if start==caret and caret>1 and text[caret-1] in [")", "]", "}"]:return []
		for row:Dictionary in help_rows():
			if not (ConsoleCommands.READS.has(row.name) or ConsoleCommands.WRITES.has(row.name)):continue
			# Write calls are valid only at the root of an @ expression.
			if ConsoleCommands.WRITES.has(row.name) and (not text.begins_with("@") or start!=1):continue
			var suffix:="" if text.substr(end).strip_edges().begins_with("(") else "()"
			rows.append({"text":row.name,"insert":row.name+suffix,"offset":String(row.name).length()+(1 if suffix else 0),"help":row.syntax+"  ·  "+row.description})
	elif script:
		var before:=text.substr(0,quote);var open:=before.rfind("(");var from:=open
		while from>0 and _word_char(before[from-1]):from-=1
		var caller:=before.substr(from,open-from) if open>=0 else ""
		if caller in ["GSGetVar","GSSetVar","GSSetVarMax","GSDelVar"]:_variables(rows,s)
		elif caller=="GetObjectByName":_units(rows,s,false)
	else:
		var before:=text.substr(0,quote if quote>=0 else start)
		var tokens:=ConsoleTools.words(before);var index:=tokens.size()-1
		var cmd:=tokens[0].to_lower() if not tokens.is_empty() else ""
		if tokens.is_empty() or cmd=="help":
			for row:Dictionary in help_rows():
				if tokens.is_empty() and (ConsoleCommands.READS.has(row.name) or ConsoleCommands.WRITES.has(row.name)):continue
				rows.append({"text":row.name,"insert":row.name+(" " if tokens.is_empty() and String(row.syntax).contains(" ") else ""),"help":row.syntax+"  ·  "+row.description})
		elif cmd=="god":_choices(rows,["on","off"])
		elif cmd=="console":_choices(rows,["t","b","c","l","r","f"])
		elif cmd=="time" and index==1:_choices(rows,["run","freeze"])
		elif cmd in ["give","getvar","setvar","listvar","loadvar"] and index==0:_choices(rows,["0"])
		elif cmd=="give" and index==1:_choices(rows,["money","exp"])
		elif cmd in ["getvar","setvar"] and index==1:_variables(rows,s)
		elif cmd=="travel" and index==0:
			for row:Dictionary in ConsoleTools.zone_rows(s):rows.append({"text":row.id,"insert":row.id,"help":row.title})
		elif (cmd in ["heal","inspect"] and index==0) or (cmd=="teleport" and index==2):
			_choices(rows,["hero","selected"]+(["party"] if cmd!="teleport" else []));_units(rows,s,true)
		elif cmd in ["exec","loadvar"]:
			if DirAccess.dir_exists_absolute("user://console"):
				for file:String in DirAccess.get_files_at("user://console"):
					if file.ends_with(".txt"):_choices(rows,[file])
	var out:Array[Dictionary]=[]
	rows.sort_custom(func(a,b):
		if a.get("priority",1)!=b.get("priority",1):return a.get("priority",1)<b.get("priority",1)
		return String(a.text).naturalnocasecmp_to(String(b.text))<0)
	for row:Dictionary in rows:
		if not String(row.text).to_lower().begins_with(needle):continue
		row.start=start;row.end=end
		if quote<0 and not script and String(row.insert).contains(" ") and not tokens_empty_prefix(text,start):
			row.insert=JSON.stringify(row.insert)
		if not row.has("offset"):row.offset=String(row.insert).length()
		out.append(row)
		if out.size()>=16:break
	return out

static func tokens_empty_prefix(text: String, start: int) -> bool:
	return text.substr(0,start).strip_edges().is_empty()

static func _choices(rows: Array[Dictionary], values: Array) -> void:
	for value:String in values:rows.append({"text":value,"insert":value,"help":"","priority":0})

static func _variables(rows: Array[Dictionary], s: Session) -> void:
	if not s or not s.state:return
	for key:String in s.state.vars:
		if key.begins_with("0:"):
			var name:=key.trim_prefix("0:")
			rows.append({"text":name,"insert":name,"help":RemakeText.t("Current value: %s")%str(s.state.get_var(0,name))})

static func _units(rows: Array[Dictionary], s: Session, ids: bool) -> void:
	if not s or not s.world:return
	for u:GameUnit in s.world.unit_rows():
		var name:=str(u.uid) if ids else String(u.info.get("name",""))
		if name.is_empty():continue
		rows.append({"text":name,"insert":name,"help":u.display_name})

static func highlighter() -> CodeHighlighter:
	var h:=CodeHighlighter.new()
	h.number_color=Color("efc277");h.symbol_color=Color("bac8dd");h.function_color=Color("84c5f4");h.member_variable_color=Color("e0b0ef")
	h.add_color_region('"','"',Color("a1d3a1"))
	for row:Dictionary in help_rows():h.add_keyword_color(row.name,Color("84c5f4"))
	for word in ["on","off","hero","party","selected","run","freeze"]:h.add_keyword_color(word,Color("d5b0f0"))
	return h
