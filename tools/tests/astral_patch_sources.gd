extends Node
## Export parser-accurate input fingerprints for build_astral_patch_data.py.
## Supply --lia-cd-root, --lia-101-root, --lia-102-root and --lia-ast-output.
## The 1.02 fixture must include 1.01 first. All input files are read only.

func _ready() -> void:
	var roots := {}
	var output := ""
	for arg: String in OS.get_cmdline_user_args():
		for edition: String in ["cd","101","102"]:
			var prefix := "--lia-"+edition+"-root="
			if arg.begins_with(prefix):roots[edition]=arg.trim_prefix(prefix)
		if arg.begins_with("--lia-ast-output="):output=arg.trim_prefix("--lia-ast-output=")
	if roots.size()!=3 or output.is_empty():
		printerr("Provide all three edition roots and --lia-ast-output.")
		get_tree().quit(1);return
	var out := {}
	for edition: String in ["cd","101","102"]:
		var maps := {}
		for file: String in ["bz31j","bz32j","zone11dun2","zone13","zone14","zone16","zone1dun2","zone21","zone23","zone25","zone31","zone32","zone7"]:
			var path: String = roots[edition]+"/maps/"+file+".mob"
			if not FileAccess.file_exists(path):
				printerr("Missing source map: "+path);get_tree().quit(1);return
			var mob := EIMob.load_bytes(FileAccess.get_file_as_bytes(path))
			var ast := ScriptParser.parse(mob.script_text)
			if not ast.errors.is_empty():
				printerr(path+": "+str(ast.errors));get_tree().quit(1);return
			var data := AstralPatches.snapshot(ast)
			maps[file]={"ast":data,"hash":JSON.stringify(data,"",true,true).sha256_text()}
		out[edition]=maps
	var handle := FileAccess.open(output,FileAccess.WRITE)
	if handle==null:
		printerr("Cannot write AST export: "+output);get_tree().quit(1);return
	handle.store_string(JSON.stringify(out,"",true,true))
	print("AST_SOURCE_EXPORT ",out.size()," editions")
	TexUpscale.shutdown()
	get_tree().quit()
