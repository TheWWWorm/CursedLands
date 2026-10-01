class_name ScriptParser
extends RefCounted
## Parses the (decrypted) Evil Islands level script language into a compact AST.
##
##   GlobalVars ( name : type, ... )
##   DeclareScript Name ( param : type, ... )
##   Script Name ( if ( cond... ) then ( stmt... ) if (...) then (...) )
##   WorldScript ( stmt... )
##
## Statements: `var = expr`, `For( var, group ) ( stmt... )`, or a call.
## Expressions: number, "string", identifier or `Name( args )`.
##
## AST nodes are Arrays: [N_NUM, v] [N_STR, v] [N_VAR, name] [N_CALL, name, args]
## [S_SET, name, expr] [S_FOR, var, group_expr, body] [S_CALL, name, args]

enum { N_NUM, N_STR, N_VAR, N_CALL, S_SET, S_FOR, S_CALL }

var globals := {}      # name -> type string
var declares := {}     # name -> [param names]
var scripts := {}      # name -> {params: [...], blocks: [{conds: [...], body: [...]}]}
var world: Array = []  # WorldScript statements
var errors: PackedStringArray = []

var _t: PackedStringArray = []   # tokens; strings keep their leading quote
var _i := 0


static func parse(text: String) -> ScriptParser:
	var p := ScriptParser.new()
	p._tokenize(text)
	p._program()
	return p


func _tokenize(s: String) -> void:
	var n := s.length()
	var i := 0
	while i < n:
		var c := s[i]
		if c == " " or c == "\t" or c == "\r" or c == "\n":
			i += 1
		elif c == "/" and i + 1 < n and s[i + 1] == "/":
			while i < n and s[i] != "\n":
				i += 1
		elif c in "(),=:":
			_t.append(c)
			i += 1
		elif c == "\"":
			var j := s.find("\"", i + 1)
			if j < 0:
				j = n
			_t.append("\"" + s.substr(i + 1, j - i - 1))
			i = j + 1
		else:
			var j := i
			while j < n and not (s[j] in " \t\r\n(),=:\""):
				j += 1
			_t.append(s.substr(i, j - i))
			i = j


func _peek(o := 0) -> String:
	return _t[_i + o] if _i + o < _t.size() else ""


func _next() -> String:
	_i += 1
	return _t[_i - 1] if _i - 1 < _t.size() else ""


func _expect(tok: String) -> bool:
	if _peek() == tok:
		_i += 1
		return true
	errors.append("expected '%s' near token %d ('%s')" % [tok, _i, _peek()])
	return false


func _program() -> void:
	while _i < _t.size():
		var kw := _next()
		match kw:
			"GlobalVars":
				for d in _decls():
					globals[d[0]] = d[1]
			"DeclareScript":
				var name := _next()
				declares[name] = _decls().map(func(d): return d[0])
			"Script":
				var name := _next()
				# Custom (hand written) scripts may repeat the parameter list.
				if _peek() == "(" and _peek(1) == ")":
					_i += 2
				scripts[name] = {"params": declares.get(name, []), "blocks": _script_body()}
			"WorldScript":
				world = _block()
			_:
				errors.append("unexpected '%s'" % kw)
				return


## `( name : type, ... )`
func _decls() -> Array:
	var out := []
	if not _expect("("):
		return out
	while _peek() != ")" and _peek() != "":
		var name := _next()
		var type := "object"
		if _peek() == ":":
			_i += 1
			type = _next()
		out.append([name, type])
		if _peek() == ",":
			_i += 1
	_i += 1
	return out


func _script_body() -> Array:
	var blocks := []
	if not _expect("("):
		return blocks
	while _peek() == "if":
		_i += 1
		var conds := _block_exprs()
		if _peek() == "then":
			_i += 1
		blocks.append({"conds": conds, "body": _block()})
	_expect(")")
	return blocks


func _block_exprs() -> Array:
	var out := []
	if not _expect("("):
		return out
	while _peek() != ")" and _peek() != "":
		out.append(_expr())
	_i += 1
	return out


func _block() -> Array:
	var out := []
	if not _expect("("):
		return out
	while _peek() != ")" and _peek() != "":
		var st := _stmt()
		if st.is_empty():
			break
		out.append(st)
	_i += 1
	return out


func _stmt() -> Array:
	var name := _next()
	if name == "":
		return []
	if _peek() == "=":
		_i += 1
		return [S_SET, name, _expr()]
	if name == "For":
		var args := _args()
		var body := _block()
		return [S_FOR, args[0][1] if args.size() > 0 else "", args[1] if args.size() > 1 else [N_NUM, 0.0], body]
	if _peek() == "(":
		return [S_CALL, name, _args()]
	errors.append("bad statement '%s'" % name)
	return [S_CALL, "Nop", []]


func _args() -> Array:
	var out := []
	_expect("(")
	while _peek() != ")" and _peek() != "":
		out.append(_expr())
		if _peek() == ",":
			_i += 1
	_i += 1
	return out


func _expr() -> Array:
	var tok := _next()
	if tok.begins_with("\""):
		return [N_STR, tok.substr(1)]
	if tok.is_valid_float():
		return [N_NUM, tok.to_float()]
	if _peek() == "(":
		return [N_CALL, tok, _args()]
	return [N_VAR, tok]
