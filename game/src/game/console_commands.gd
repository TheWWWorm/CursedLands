class_name ConsoleCommands
extends RefCounted
## Original console syntax over the existing campaign VM. Changes run only on
## the authority for its owner; a network guest cannot send arbitrary scripts.
const READS := {"Add":"nn","Sub":"nn","Mul":"nn","Div":"nn","Not":"n","IsEqual":"nn","IsLess":"nn","IsGreater":"nn","IsEqualString":"ss","GSGetVar":"ns","GetObjectByName":"s","GetObjectByID":"s","GetObject":"n","GetX":"u","GetY":"u","GetZ":"u","HP":"u","MaxHP":"u","IsAlive":"u","IsDead":"u","GetObjectID":"u","GetWorldTime":"","GetMoney":"n",
	"GetUnitOfPlayer":"nn","GetLeader":"n","GetMercsNumber":"n","GetFutureX":"u","GetFutureY":"u","DistanceUnitUnit":"uu","DistanceUnitPoint":"unn","IsUnitBlocked":"u","WasLooted":"u","GetLeverState":"u","IsInArea":"nnn","HaveItem":"ns","GetDiplomacy":"nn"}
const WRITES := {"GSSetVar":"nsn","GSSetVarMax":"nsn","GSDelVar":"ns","GiveMoney":"nn","GiveItem":"ns","GiveQuestItem":"ns","SetCP":"unnn","SetCPFast":"unnn","BlockUnit":"un","Run":"u","Walk":"u","Idle":"u","PlayAnimation":"us",
	"GodMode":"nn","Crawl":"u","Lie":"u","Stand":"u","EnableLever":"un","SwitchLeverState":"un","SwitchLeverStateEx":"unn","ActivateTrap":"un","FixWorldTime":"n","RunWorldTime":"n"}
const ERROR := "Invalid console command or arguments."

static func execute(s: Session, line: String, player := 0, selection: Array = []) -> PackedStringArray:
	if not s.is_host or player != 0: return [RemakeText.t("Only the host can change the campaign through the console.")]
	if s.loading_game or s.movie_active() or s.ending_active or s.world == null or s.world.vm == null:
		return [RemakeText.t("Console gameplay commands are unavailable during loading or cinematics.")]
	line=line.strip_edges()
	if line.length()>65536:return [RemakeText.t(ERROR)]
	var words:=ConsoleTools.words(line)
	if words.is_empty():return [] if line.is_empty() else [RemakeText.t(ERROR)]
	var command:=words[0].to_lower()
	if command in ConsoleTools.NAMES:return ConsoleTools.execute(s,line,selection)
	if command=="give":
		if words.size()!=4 or words[1]!="0" or not words[3].is_valid_float():return [RemakeText.t("Usage: give 0 money|exp amount")]
		var amount:=float(words[3])
		if not is_finite(amount) or amount<0 or amount>100000000:return [RemakeText.t(ERROR)]
		if words[2].to_lower()=="money":s.state.money+=int(amount)
		elif words[2].to_lower()=="exp":
			# Native give divides equally, then each member's intelligence applies.
			var party:=s.party_units(0).filter(func(u):return not u.dead and u.has_meta("hero"))
			for u:GameUnit in party:XpRules.gain(s,u,u.get_meta("hero"),amount/maxi(1,party.size()))
		else:return [RemakeText.t("Usage: give 0 money|exp amount")]
		s.sync_state();return [RemakeText.t("Done.")]
	if command=="getvar" or command=="setvar":
		if words.size()!=(3 if command=="getvar" else 4) or words[1]!="0":return [RemakeText.t(ERROR)]
		if command=="getvar":return [str(s.state.get_var(0,words[2]))]
		if not words[3].is_valid_float() or not is_finite(float(words[3])):return [RemakeText.t(ERROR)]
		s.state.set_var(0,words[2],float(words[3]));s.sync_state();return [RemakeText.t("Done.")]
	if command=="listvar":
		if words.size()!=2 or not words[1].is_valid_int():return [RemakeText.t(ERROR)]
		var owner:=int(words[1]);var out:=PackedStringArray();var prefix:=str(owner)+":"
		for key:String in s.state.vars:
			if key.begins_with(prefix):
				var name:=key.trim_prefix(prefix)
				out.append(JSON.stringify(name)+" "+str(s.state.get_var(owner,name)))
		out.sort();return out
	if command=="loadvars":
		# UI imports an original-style dump as validated, bounded JSON in one
		# request. Validate the entire batch before changing any variable.
		var rows:Variant=JSON.parse_string(line.trim_prefix(words[0]).strip_edges())
		if not rows is Dictionary or rows.size()>2048:return [RemakeText.t(ERROR)]
		for key:Variant in rows:
			if not key is String or key.is_empty() or key.length()>256 or not (rows[key] is float or rows[key] is int) or not is_finite(float(rows[key])):return [RemakeText.t(ERROR)]
		for key:String in rows:s.state.set_var(0,key,float(rows[key]))
		s.sync_state();return [RemakeText.t("Done.")]
	if line[0] not in ["@","#","$"]:return [RemakeText.t("Unknown command.")]
	var parser:=ScriptParser.new();parser._tokenize(line.substr(1))
	# Bound nesting before invoking the campaign parser's recursive descent.
	var nesting:=0
	for token:String in parser._t:
		if token=="(":nesting+=1
		elif token==")":nesting-=1
		if nesting<0 or nesting>16:return [RemakeText.t(ERROR)]
	if nesting!=0 or line.count('"')%2!=0:return [RemakeText.t(ERROR)]
	var expr:=parser._expr()
	if not parser.errors.is_empty() or parser._i!=parser._t.size() or not _valid(expr,line[0]=="@",0):return [RemakeText.t(ERROR)]
	var result:=_eval(expr,s.world.vm,0)
	if not result.ok:return [RemakeText.t(ERROR)]
	if line[0]=="@":s.sync_state();return [RemakeText.t("Done.")]
	if line[0]=="#" and not (result.value is float or result.value is int):return [RemakeText.t(ERROR)]
	if line[0]=="$" and not result.value is String:return [RemakeText.t(ERROR)]
	return [str(result.value)]

static func _valid(e:Array,write:bool,depth:int) -> bool:
	if depth>16 or e.size()<2:return false
	if e[0] in [ScriptParser.N_NUM,ScriptParser.N_STR]:return e.size()==2
	if e[0]!=ScriptParser.N_CALL or e.size()!=3:return false
	var sig:String=READS.get(e[1],WRITES.get(e[1],"") if write else "")
	if not READS.has(e[1]) and not (write and WRITES.has(e[1])):return false
	return e[2].size()==sig.length() and e[2].all(func(a):return _valid(a,false,depth+1))

static func _eval(e:Array,vm:ScriptVM,depth:int) -> Dictionary:
	if e[0] in [ScriptParser.N_NUM,ScriptParser.N_STR]:
		var value:Variant=vm._eval(e,ScriptVM.Instance.new())
		return {"ok":not value is float or is_finite(value),"value":value}
	var sig:String=READS.get(e[1],WRITES.get(e[1],""))
	var args:=[];var inst:=ScriptVM.Instance.new()
	for i in e[2].size():
		var r:=_eval(e[2][i],vm,depth+1)
		if not r.ok:return r
		var v:Variant=r.value
		if (sig[i]=="n" and (not (v is float or v is int) or not is_finite(float(v)))) or (sig[i]=="s" and not v is String) or (sig[i]=="u" and not (v is Node3D and is_instance_valid(v))):
			return {"ok":false}
		if e[1]=="Div" and i==1 and float(v)==0.0:return {"ok":false}
		if e[1]=="GodMode" and ((i==0 and float(v)!=int(v)) or (i==1 and float(v) not in [0.0,1.0])):return {"ok":false}
		var key:="console_argument_"+str(i);inst.locals[key]=v;args.append([ScriptParser.N_VAR,key])
	var value:Variant=vm._eval([ScriptParser.N_CALL,e[1],args],inst)
	return {"ok":not value is float or is_finite(value),"value":value}
