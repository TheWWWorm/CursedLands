extends RefCounted
## Remake side of cases_ext_quest_scheduler.py: the production ScriptVM
## scheduler. The program is written as original script text and parsed by
## the production ScriptParser; each step is one ScriptVM.tick(SLEEP_UNIT).
## Overrides only record calls and then defer to the production methods.

## Automatic zone-briefing polling (Briefings.tick) is outside this contract.
class QuietBriefings extends Briefings:
	func tick() -> void:
		pass

class SchedulerVM extends ScriptVM:
	var cond_roots: Array = []   # [[condition AST, label]]
	var body_labels: Array = []  # [[body AST, label]]
	var trace: Array = []
	## Record every copy's evaluation, as the native walk performs it.
	func _init() -> void:
		condition_memo = false
	func label(body: Array) -> String:
		for row in body_labels:
			if is_same(row[0], body): return row[1]
		return "?"
	func _eval(e: Array, inst: ScriptVM.Instance):
		for row in cond_roots:
			if is_same(e, row[0]): trace.append("c:" + row[1])
		return super._eval(e, inst)
	## Called by _run exactly when a block's conditions hold and its body starts.
	func _once_per_world(inst: ScriptVM.Instance) -> bool:
		trace.append("fire:%s.%d" % [inst.sname, inst.block_index])
		return super._once_per_world(inst)
	## Native traces 0x4b6760 only for threads with statements left (ip <
	## count); an empty WorldScript body is the remake's only frame that
	## starts with nothing left to run.
	func _run(inst: ScriptVM.Instance) -> void:
		if SchedulerVM.pending(inst):
			trace.append("run:" + label(inst.frames[0].body))
		super._run(inst)
	static func pending(inst: ScriptVM.Instance) -> bool:
		return not inst.frames.is_empty() and not (inst.frames.size() == 1 and inst.frames[0].body.is_empty())

func kinds() -> Array:
	return ["quest_scheduler"]

func _number(value) -> String:
	var text := str(float(value))
	if not text.is_valid_float():
		push_error("Unrepresentable scheduler literal: " + text)
	return text

func _expr(value) -> String:
	if value == null: return "NULL"
	if value is Dictionary:
		if value.has("global"): return String(value.global)
		if value.has("local"): return String(value.local)
		if value.has("string"): return "\"" + String(value.string) + "\""
		var args := []
		for arg in value.args: args.append(_expr(arg))
		return "%s( %s )" % [String(value.call), ", ".join(args)]
	return _number(value)

func _stmt(row: Dictionary) -> String:
	if row.has("set"): return "%s = %s" % [String(row.set), _expr(row.value)]
	var args := []
	for arg in row.get("args", []): args.append(_expr(arg))
	return "%s( %s )" % [String(row.script if row.has("script") else row.call), ", ".join(args)]

func _body(rows: Array) -> String:
	var lines := []
	for row: Dictionary in rows: lines.append("  " + _stmt(row))
	return "(\n%s\n)" % "\n".join(lines)

func program_text(data: Dictionary) -> String:
	var decls := []
	var names: Array = data.globals.keys()
	names.sort()
	for name: String in names: decls.append("%s : float" % name)
	var text := "GlobalVars ( %s )\n" % ", ".join(decls)
	for script: Dictionary in data.scripts:
		var params := []
		for p: Array in script.get("params", []): params.append("%s : %s" % [p[0], p[1]])
		text += "DeclareScript %s ( %s )\n" % [script.name, ", ".join(params)]
	for script: Dictionary in data.scripts:
		text += "Script %s\n(\n" % script.name
		for block: Dictionary in script.blocks:
			var conds := []
			for c in block.conds: conds.append("    " + _expr(c))
			text += "  if\n  (\n%s\n  )\n  then\n  %s\n" % ["\n".join(conds), _body(block.body)]
		text += ")\n"
	return text + "WorldScript\n" + _body(data.world) + "\n"

func capture(_kind: String, data: Dictionary, trace: Node) -> Array:
	var world := GameWorld.new()
	var session: Session = trace.quest_session()
	session.state = trace.quest_state({}, {})
	var vm := SchedulerVM.new()
	vm.world = world
	vm.session = session
	vm.briefings = QuietBriefings.new(vm)
	vm.ast = ScriptParser.parse(program_text(data))
	if not vm.ast.errors.is_empty():
		push_error("Scheduler program did not parse: " + str(vm.ast.errors))
		return []
	for name: String in data.globals: vm.globals[name] = trace.f32(float(data.globals[name]))
	for script: Dictionary in data.scripts:
		var blocks: Array = vm.ast.scripts[script.name].blocks
		for b in blocks.size():
			var label := "%s.%d" % [script.name, b]
			for c in blocks[b].conds.size(): vm.cond_roots.append([blocks[b].conds[c], "%s.%d" % [label, c]])
			vm.body_labels.append([blocks[b].body, label])
	vm.body_labels.append([vm.ast.world, "World"])
	vm._start_world(vm.ast.world)
	var states := []
	for tick: Dictionary in data.ticks:
		vm.trace = []
		for name: String in tick.get("globals", {}): vm.globals[name] = trace.f32(float(tick.globals[name]))
		if tick.has("briefing"):
			# Briefings.complete: the completion flag, then fire_event.
			var event: Dictionary = tick.briefing
			vm.globals[String(event.flag)] = 2.0
			var args := []
			for arg in event.get("args", []):
				args.append(String(arg.string) if arg is Dictionary else trace.f32(float(arg)))
			vm.fire_event(String(event.script), args)
		vm.tick(ScriptVM.SLEEP_UNIT)
		var scripts := {}
		var bodies := {}
		for inst: ScriptVM.Instance in vm.instances:
			if inst.sname != "WorldScript" and not inst.killed:
				scripts[inst.sname] = int(scripts.get(inst.sname, 0)) + 1
			if SchedulerVM.pending(inst):
				var name := vm.label(inst.frames[0].body)
				bodies[name] = int(bodies.get(name, 0)) + 1
		var values := {}
		for name: String in data.globals:
			var value = vm.globals.get(name)
			values[name] = trace.bits(0.0 if value == null else float(value))
		states.append({"trace": vm.trace.duplicate(), "globals": values, "scripts": scripts,
			"bodies": bodies, "fatal": ""})
	vm.briefings = null
	session.free()
	world.free()
	return states
