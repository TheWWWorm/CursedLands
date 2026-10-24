extends RefCounted
## Upgrade only continuations from verified official script editions. The
## authored threads retain their locals, sleeps, loop items and completed work.
const P := preload("res://src/game/script/script_parser.gd")


static func stamp(vm: ScriptVM, saved: Dictionary) -> Dictionary:
	if vm.ast != null and vm.ast.has_meta(AstralPatches.META):
		var source: Dictionary = vm.ast.get_meta(AstralPatches.META)
		saved.lia_patch={"revision":source.revision,"script":source.canonical}
	return saved


static func migrate(vm: ScriptVM, saved: Dictionary) -> Dictionary:
	# A VM without a parsed script (no zone script) has no edition to upgrade.
	if vm.ast == null or not vm.ast.has_meta(AstralPatches.META) or saved.has("lia_patch"): return saved
	var source: Dictionary = vm.ast.get_meta(AstralPatches.META)
	var patch: Dictionary = AstralPatches.DATA.scripts[source.zone]
	var variant: Dictionary = patch.variants.get(source.source,{})
	if variant.is_empty(): return saved
	var out := saved.duplicate(true)
	var worlds := 0
	for instance: Dictionary in out.get("instances",[]):
		var name := String(instance.s)
		if name=="WorldScript":
			var root: bool = instance.get("src","" if worlds==0 else "?")==""
			worlds+=1
			if not root:continue
		var blocks: Dictionary = variant.continuations.get(name,{})
		var block := "0" if name=="WorldScript" else str(int(instance.get("b",-1)))
		if not blocks.has(block):continue
		var mapping: Dictionary = blocks[block]
		if int(mapping.target)<0:
			instance.k=true;instance.b=-1;instance.i=0;instance.f=[]
			continue
		if name!="WorldScript":instance.b=int(mapping.target)
		var body: Dictionary = mapping.body
		var frames: Array = instance.get("f",[])
		if frames.is_empty():
			instance.i=_position(body,int(instance.get("i",0)))
			continue
		var restored := []
		for old_frame: Dictionary in frames:
			var frame := old_frame.duplicate(true)
			frame.i=_position(body,int(old_frame.i))
			restored.append(frame)
			var loop: Dictionary = body.loops.get(str(int(old_frame.i)-1),{})
			if loop.is_empty():break
			body=loop.body
		instance.f=restored
		instance.i=int(restored[0].i) if not restored.is_empty() else 0
	return out


static func _position(body: Dictionary, index: int) -> int:
	var positions: Array = body.ip
	return int(positions[clampi(index,0,positions.size()-1)])


static func _live(vm: ScriptVM, name: String) -> bool:
	return vm.instances.any(func(i):return i.sname==name and (not i.killed or not i.frames.is_empty()))


static func _pending_call(vm: ScriptVM, name: String) -> bool:
	for instance: ScriptVM.Instance in vm.instances:
		for frame: Dictionary in instance.frames:
			for statement: Array in frame.body.slice(int(frame.i)):
				if statement[0]==P.S_CALL and statement[1]==name:return true
	return false


static func _ensure(vm: ScriptVM, name: String) -> void:
	if not _live(vm,name) and not _pending_call(vm,name):vm.spawn(name,[null])


static func _flag(vm: ScriptVM, name: String) -> float:
	return vm.session.state.get_var(0,name)


static func _enable(vm: ScriptVM, id: int) -> void:
	if vm.world.levers.has(id):vm.world.levers[id].enabled=true


static func _unfinished(vm: ScriptVM, quest: String) -> bool:
	return _flag(vm,quest)<2.0


static func prepare(vm: ScriptVM) -> void:
	if vm.ast == null or not vm.ast.has_meta(AstralPatches.META):return
	var source: Dictionary = vm.ast.get_meta(AstralPatches.META)
	# CD performed this transfer in the previous hub. The destination may
	# have no saved VM yet, so protect both first loads and restored worlds.
	if source.zone=="gz32j" and vm.session.state.current_party=="Jigran1" and _flag(vm,"b.BSon.brief_318")==2:
		vm.session.state.set_var(0,"b.BSon.brief_318",3)


static func recover(vm: ScriptVM, saved: Dictionary) -> void:
	if vm.ast == null or not vm.ast.has_meta(AstralPatches.META) or saved.has("lia_patch"):return
	prepare(vm)
	var source: Dictionary = vm.ast.get_meta(AstralPatches.META)
	var state := vm.session.state
	# A restored map was already initialized. The new first-visit block must
	# not disable levers partway through an older campaign.
	match String(source.zone):
		"gz13g":
			# Before the quest starts, replace the CD setup's removed lever
			# disabling. Once it has started, retain the player's progress.
			if _flag(vm,"start_zone13")==0 and _flag(vm,"q.gz13g.q17g.1")==0:
				for name: String in ["LeverL","LeverF"]:
					var id := vm._obj_id(vm.globals.get(name))
					if vm.world.levers.has(id):vm.world.levers[id].enabled=false
			state.set_var(0,"start_zone13",maxf(1.0,_flag(vm,"start_zone13")))
			if _flag(vm,"q.gz13g.q17g.1")>=1 and _unfinished(vm,"q.gz13g.q17g"):
				for name: String in ["VCheck#0#3","VCheck#0#4","VCheck#0#5","VCheck#0#6"]:_ensure(vm,name)
		"gz14g":_ensure(vm,"VCheck#0#6")
		"gz1d2":_ensure(vm,"Barell#4")
		"gz16g":
			if _flag(vm,"q.gz16g.q22g.1")>=1 and _unfinished(vm,"q.gz16g.q22g"):
				_enable(vm,4948)
				if _flag(vm,"q.gz16g.q22g.2")<2:_ensure(vm,"VCheck#1#3")
			_rearm(vm,"VCheck#3#1","b.shava.fq10","q.gz16g.fq10",[4955])
			_rearm(vm,"VCheck#4#1","b.shava.fq12","q.gz16g.fq12",[3398867,2139693])
		"gz21k":_rearm(vm,"VCheck#8#1","b.Haburu.fq16","q.gz21k.fq16",[2016001])
		"gz23k":_rearm(vm,"VCheck#5#1","b.Haburu.fq15","q.gz23k.fq15",[4216])
		"gz31j":
			if _flag(vm,"q.gz31j.q8j.1")>=1 and _flag(vm,"q.gz31j.q8j.2")<2 and _unfinished(vm,"q.gz31j.q8j"):
				_ensure(vm,"VCheck#3#3")
		"bz31j":
			# An old offer could be set before Quiet Cemeteries was complete.
			# Withdraw only an unconsumed offer; never undo a finished briefing.
			if _flag(vm,"b.merc2.brief_317")==1 and _flag(vm,"q.gz31j.q6j")!=2:
				state.set_var(0,"b.merc2.brief_317",0)
			_ensure(vm,"VCheck#0#9")
		"bz32j":
			if _flag(vm,"b.merc2.brief_317")==2 and _flag(vm,"b.BSon.brief_318")==0:
				state.set_var(0,"b.BSon.brief_318",1)
		"gz32j":
			_ensure(vm,"VCheck#2#4")


static func _rearm(vm: ScriptVM, script: String, briefing: String, quest: String, ids: Array) -> void:
	if _flag(vm,briefing)!=2 or not _unfinished(vm,quest):return
	if ids.any(func(id):return vm.world.levers.has(id) and not bool(vm.world.levers[id].get("enabled",true))):
		_ensure(vm,script)
