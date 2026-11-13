class_name MilkEel
extends RefCounted

## MilkDrop's equation language, read and translated (docs/visuals.md): the per-frame, per-pixel, wave
## and shape code of a `.milk` preset. Written for this project from the language's published description.
##
## `parse` turns code into a tree of statements. Statements are separated by `;` (a line break between
## two complete statements counts as one too, since presets forget them). The operators are assignment
## (`=`, `+=`, `-=`, `*=`, `/=`, `%=`, right to left and usable inside an expression), `||`, `&&`, `|` and
## `&` (bitwise, on the integer parts), comparisons, `+ -`, `* / %`, unary `- + !` and `^` (power). Function
## arguments and parentheses may hold several `;`-separated expressions, worth the last. Names are case
## blind, every variable starts at 0, and `//` and `/* */` are comments.
##
## A tree is then translated, either to GDScript (`gd_*`, `build`: a MilkVM with one member per variable,
## compiled at run time) for the code that runs once a frame or once per point of a wave, or to Godot
## shader code (`glsl_*`) for the per-pixel code, which runs in the warp shader for every pixel.
##
## The tree: ["num", value], ["var", name], ["assign", name, op, expr], ["bin", op, a, b], ["neg", a],
## ["not", a], ["call", name, [args]], ["seq", [exprs]].

## The functions, with how many arguments each takes.
const FUNCS := {
	"sin": 1, "cos": 1, "tan": 1, "asin": 1, "acos": 1, "atan": 1, "atan2": 2, "sqr": 1, "sqrt": 1,
	"invsqrt": 1, "pow": 2, "exp": 1, "log": 1, "log10": 1, "abs": 1, "sign": 1, "min": 2, "max": 2,
	"rand": 1, "int": 1, "above": 2, "below": 2, "equal": 2, "if": 3, "bnot": 1, "band": 2, "bor": 2,
	"sigmoid": 2, "floor": 1, "ceil": 1, "exec2": 2, "exec3": 3,
}
const CONSTS := {"$pi": PI, "$e": 2.718281828459045, "$phi": 1.618033988749895}
const ASSIGN_OPS := ["=", "+=", "-=", "*=", "/=", "%="]
## How tightly each binary operator binds; assignment loosest, `^` tightest.
const BP := {
	"=": 10, "+=": 10, "-=": 10, "*=": 10, "/=": 10, "%=": 10,
	"||": 20, "&&": 30, "|": 40, "&": 50,
	"==": 60, "!=": 60, "<": 60, ">": 60, "<=": 60, ">=": 60,
	"+": 70, "-": 70, "*": 80, "/": 80, "%": 80, "^": 90,
}
const PREFIX_BP := 85

var _toks: Array = []
var _at := 0
var _error := ""


## Code to statements: {ok, ast (Array of statements), error}.
static func parse(src: String) -> Dictionary:
	var p := MilkEel.new()
	var toks := tokenize(src)
	if toks.is_empty() or toks[0][0] == "error":
		return {"ok": false, "ast": [], "error": toks[0][1] if not toks.is_empty() else "empty"}
	p._toks = toks
	var ast := p._program()
	if p._error != "":
		return {"ok": false, "ast": [], "error": p._error}
	return {"ok": true, "ast": ast, "error": ""}


## Code to tokens: each [kind, text or value, after a line break]. Kinds: num, id, op, end; or a single
## ["error", message].
static func tokenize(src: String) -> Array:
	var out: Array = []
	var i := 0
	var n := src.length()
	var nl := false
	while i < n:
		var c := src[i]
		if c == "\n" or c == "\r":
			nl = true
			i += 1
			continue
		if c == " " or c == "\t" or c == "`":
			i += 1
			continue
		if c == "/" and i + 1 < n and src[i + 1] == "/":
			while i < n and src[i] != "\n":
				i += 1
			continue
		if c == "/" and i + 1 < n and src[i + 1] == "*":
			var close := src.find("*/", i + 2)
			i = n if close < 0 else close + 2
			continue
		if _is_digit(c) or (c == "." and i + 1 < n and _is_digit(src[i + 1])):
			var j := i
			while j < n and (_is_digit(src[j]) or src[j] == "."):
				j += 1
			if j < n and (src[j] == "e" or src[j] == "E") and j + 1 < n \
					and (_is_digit(src[j + 1]) or ((src[j + 1] == "-" or src[j + 1] == "+") and j + 2 < n and _is_digit(src[j + 2]))):
				j += 2
				while j < n and _is_digit(src[j]):
					j += 1
			out.append(["num", src.substr(i, j - i).to_float(), nl])
			nl = false
			i = j
			continue
		if _is_alpha(c) or c == "$":
			var j := i + 1
			while j < n and (_is_alpha(src[j]) or _is_digit(src[j])):
				j += 1
			var word := src.substr(i, j - i).to_lower()
			if word.begins_with("$"):
				if not CONSTS.has(word):
					return [["error", "unknown constant %s" % word]]
				out.append(["num", CONSTS[word], nl])
			else:
				out.append(["id", word, nl])
			nl = false
			i = j
			continue
		var two := src.substr(i, 2)
		if two in ["+=", "-=", "*=", "/=", "%=", "==", "!=", "<=", ">=", "&&", "||"]:
			out.append(["op", two, nl])
			i += 2
		elif c in ["+", "-", "*", "/", "%", "^", "&", "|", "=", "<", ">", "!", "(", ")", ",", ";"]:
			out.append(["op", c, nl])
			i += 1
		else:
			return [["error", "unexpected character '%s'" % c]]
		nl = false
	out.append(["end", "", nl])
	return out


static func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


static func _is_alpha(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


# --- the parser (Pratt) ------------------------------------------------------------------------------

func _peek() -> Array:
	return _toks[_at]


func _next() -> Array:
	var t: Array = _toks[_at]
	if _at < _toks.size() - 1:
		_at += 1
	return t


func _fail(msg: String) -> void:
	if _error == "":
		_error = msg


func _is(t: Array, text: String) -> bool:
	return t[0] == "op" and t[1] == text


func _program() -> Array:
	var out: Array = []
	while _error == "" and _peek()[0] != "end":
		if _is(_peek(), ";"):
			_next()
			continue
		var e: Variant = _expr(0)
		if _error != "":
			break
		out.append(e)
		var t := _peek()
		if _is(t, ";"):
			_next()
		elif t[0] != "end" and not t[2]:
			_fail("expected ; before '%s'" % str(t[1]))
	return out


func _expr(rbp: int) -> Variant:
	var left: Variant = _nud(_next())
	while _error == "":
		var t := _peek()
		if t[0] != "op" or not BP.has(t[1]) or BP[t[1]] <= rbp:
			break
		_next()
		left = _led(t, left)
	return left


func _nud(t: Array) -> Variant:
	match t[0]:
		"num":
			return ["num", t[1]]
		"id":
			if _is(_peek(), "("):
				_next()
				var name: String = t[1]
				if not FUNCS.has(name):
					_fail("unknown function %s" % name)
					return ["num", 0.0]
				var args: Array = []
				if not _is(_peek(), ")"):
					while _error == "":
						args.append(_sequence([",", ")"]))
						if _is(_peek(), ","):
							_next()
						else:
							break
				if not _is(_next(), ")"):
					_fail("expected ) after %s's arguments" % name)
				if args.size() != int(FUNCS[name]):
					_fail("%s takes %d arguments, not %d" % [name, FUNCS[name], args.size()])
				if name == "exec2" or name == "exec3":
					return ["seq", args]
				return ["call", name, args]
			return ["var", t[1]]
		"op":
			match t[1]:
				"(":
					var e: Variant = _sequence([")"])
					if not _is(_next(), ")"):
						_fail("expected )")
					return e
				"-":
					return ["neg", _expr(PREFIX_BP)]
				"+":
					return _expr(PREFIX_BP)
				"!":
					return ["not", _expr(PREFIX_BP)]
	_fail("unexpected '%s'" % str(t[1]) if t[0] != "end" else "unexpected end")
	return ["num", 0.0]


## One or more expressions separated by `;`, up to one of `stops`; worth the last.
func _sequence(stops: Array) -> Variant:
	var parts: Array = []
	while _error == "":
		if _is(_peek(), ";"):
			_next()
			continue
		if _peek()[0] == "op" and _peek()[1] in stops:
			break
		parts.append(_expr(0))
		if not _is(_peek(), ";"):
			break
	if parts.is_empty():
		_fail("empty expression")
		return ["num", 0.0]
	return parts[0] if parts.size() == 1 else ["seq", parts]


func _led(t: Array, left: Variant) -> Variant:
	var op: String = t[1]
	if op in ASSIGN_OPS:
		if not (left is Array and left[0] == "var"):
			_fail("only a variable can be assigned")
			return left
		return ["assign", left[1], op, _expr(BP[op] - 1)]
	if op == "^":
		return ["bin", op, left, _expr(BP[op] - 1)]
	return ["bin", op, left, _expr(BP[op])]


## Every variable a tree reads or writes, into `into` (name → true).
static func vars_in(node: Variant, into: Dictionary) -> Dictionary:
	if node is Array and not node.is_empty() and node[0] is String:
		match node[0]:
			"var":
				into[node[1]] = true
			"assign":
				into[node[1]] = true
				vars_in(node[3], into)
			"bin":
				vars_in(node[2], into)
				vars_in(node[3], into)
			"neg", "not":
				vars_in(node[1], into)
			"call":
				for a in node[2]:
					vars_in(a, into)
			"seq":
				for a in node[1]:
					vars_in(a, into)
	elif node is Array:
		for s in node:
			vars_in(s, into)
	return into


# --- to GDScript --------------------------------------------------------------------------------------

static func _num(v: float) -> String:
	if is_nan(v) or is_inf(v):
		return "0.0"
	var s := var_to_str(v)
	if not ("." in s or "e" in s):
		s += ".0"
	return s


## An expression as GDScript; `setters` collects the variables assigned inside an expression.
static func gd_expr(n: Array, setters: Dictionary) -> String:
	match n[0]:
		"num":
			return _num(n[1])
		"var":
			return "v_" + n[1]
		"assign":
			setters[n[1]] = true
			return "_s_%s(%s)" % [n[1], _gd_assigned(n, setters)]
		"neg":
			return "(-%s)" % gd_expr(n[1], setters)
		"not":
			return "_bnot(%s)" % gd_expr(n[1], setters)
		"seq":
			var parts := PackedStringArray()
			for a in n[1]:
				parts.append(gd_expr(a, setters))
			return "float([%s][-1])" % ", ".join(parts)
		"bin":
			var a := gd_expr(n[2], setters)
			var b := gd_expr(n[3], setters)
			match n[1]:
				"+", "-", "*":
					return "(%s %s %s)" % [a, n[1], b]
				"/":
					return "_div(%s, %s)" % [a, b]
				"%":
					return "_mod(%s, %s)" % [a, b]
				"^":
					return "_pow(%s, %s)" % [a, b]
				"&":
					return "_bits_and(%s, %s)" % [a, b]
				"|":
					return "_bits_or(%s, %s)" % [a, b]
				"==":
					return "_equal(%s, %s)" % [a, b]
				"!=":
					return "_bnot(_equal(%s, %s))" % [a, b]
				"<", ">", "<=", ">=":
					return "(1.0 if %s %s %s else 0.0)" % [a, n[1], b]
				"&&":
					return "(1.0 if (%s != 0.0 and %s != 0.0) else 0.0)" % [a, b]
				"||":
					return "(1.0 if (%s != 0.0 or %s != 0.0) else 0.0)" % [a, b]
		"call":
			var args := PackedStringArray()
			for a in n[2]:
				args.append(gd_expr(a, setters))
			match n[1]:
				"if":
					return "(%s if %s != 0.0 else %s)" % [args[1], args[0], args[2]]
				"sin", "cos", "atan", "abs", "floor", "ceil":
					return "%s(%s)" % [{"abs": "absf", "floor": "floorf", "ceil": "ceilf"}.get(n[1], n[1]), args[0]]
				"min", "max":
					return "%sf(%s, %s)" % [n[1], args[0], args[1]]
				_:
					return "_%s(%s)" % [n[1], ", ".join(args)]
	return "0.0"


## An assignment's new value: `a += e` is `a + e`.
static func _gd_assigned(n: Array, setters: Dictionary) -> String:
	var v: String = "v_" + n[1]
	var e := gd_expr(n[3], setters)
	match n[2]:
		"+=":
			return "(%s + %s)" % [v, e]
		"-=":
			return "(%s - %s)" % [v, e]
		"*=":
			return "(%s * %s)" % [v, e]
		"/=":
			return "_div(%s, %s)" % [v, e]
		"%=":
			return "_mod(%s, %s)" % [v, e]
	return e


## Statements as GDScript lines, indented by `indent`.
static func gd_block(ast: Array, setters: Dictionary, indent := "\t") -> String:
	var lines := PackedStringArray()
	for s in ast:
		if s[0] == "assign":
			lines.append("%sv_%s = %s" % [indent, s[1], _gd_assigned(s, setters)])
		else:
			lines.append("%s_d = %s" % [indent, gd_expr(s, setters)])
	if lines.is_empty():
		lines.append(indent + "pass")
	return "\n".join(lines)


## Compiles a MilkVM from named blocks of code: {function name: source}; each becomes a method running
## that code. `extra` names variables the caller sets or reads even when no code mentions them. A
## `point` dictionary {source, outputs} adds `points(n, v1, v2)` (see MilkPlayer). Returns {ok, vm, error}.
static func build(blocks: Dictionary, extra: Array = [], point := {}) -> Dictionary:
	var asts := {}
	var names := {}
	for k in blocks:
		var r := parse(String(blocks[k]))
		if not r.ok:
			return {"ok": false, "vm": null, "error": "%s: %s" % [k, r.error]}
		asts[k] = r.ast
		vars_in(r.ast, names)
	var point_ast: Array = []
	if not point.is_empty():
		var r := parse(String(point.get("source", "")))
		if not r.ok:
			return {"ok": false, "vm": null, "error": "per_point: %s" % r.error}
		point_ast = r.ast
		vars_in(point_ast, names)
		for v in ["sample", "value1", "value2", "x", "y", "r", "g", "b", "a"]:
			names[v] = true
	for v in extra:
		names[String(v).to_lower()] = true
	var setters := {}
	var body := PackedStringArray()
	for k in asts:
		body.append("func %s() -> void:\n%s\n" % [k, gd_block(asts[k], setters)])
	if not point.is_empty():
		body.append("""func points(n: int, v1: PackedFloat32Array, v2: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n * 6)
	var r0 := v_r
	var g0 := v_g
	var b0 := v_b
	var a0 := v_a
	var last := float(maxi(n - 1, 1))
	for i in n:
		v_sample = float(i) / last
		v_value1 = v1[i]
		v_value2 = v2[i]
		v_x = 0.5 + v_value1 * 0.5
		v_y = 0.5 + v_value2 * 0.5
		v_r = r0
		v_g = g0
		v_b = b0
		v_a = a0
%s
		var o := i * 6
		out[o] = v_x
		out[o + 1] = v_y
		out[o + 2] = v_r
		out[o + 3] = v_g
		out[o + 4] = v_b
		out[o + 5] = v_a
	v_r = r0
	v_g = g0
	v_b = b0
	v_a = a0
	return out
""" % gd_block(point_ast, setters, "\t\t"))
	var head := PackedStringArray(["extends MilkVM", ""])
	var sorted := names.keys()
	sorted.sort()
	for v in sorted:
		head.append("var v_%s := 0.0" % v)
	head.append("")
	for v in setters:
		head.append("func _s_%s(x: float) -> float:\n\tv_%s = x\n\treturn x\n" % [v, v])
	var src := "\n".join(head) + "\n" + "\n".join(body)
	var script := GDScript.new()
	script.source_code = src
	if script.reload() != OK:
		return {"ok": false, "vm": null, "error": "did not compile", "source": src}
	return {"ok": true, "vm": script.new(), "error": "", "source": src}


## Runs `src` once against `vars` (name → value, any case), writing every variable back into it: the
## simple way in, for a test or a one-off. Returns "" or the error.
static func run_on(src: String, vars: Dictionary) -> String:
	var r := build({"run": src}, vars.keys())
	if not r.ok:
		return r.error
	var vm: MilkVM = r.vm
	for k in vars:
		vm.put(String(k), float(vars[k]))
	vm.call("run")
	var got := vm.vars()
	for k in got:
		vars[k] = got[k]
	return ""


# --- to Godot shader code -----------------------------------------------------------------------------

## An expression as shader code, or "" with `err[0]` set when it uses what a shader cannot do here
## (an assignment inside an expression, a sequence).
static func glsl_expr(n: Array, err: Array) -> String:
	match n[0]:
		"num":
			return _num(n[1])
		"var":
			return "v_" + n[1]
		"assign", "seq":
			err[0] = "an assignment or sequence inside an expression"
			return "0.0"
		"neg":
			return "(-%s)" % glsl_expr(n[1], err)
		"not":
			return "_bnot(%s)" % glsl_expr(n[1], err)
		"bin":
			var a := glsl_expr(n[2], err)
			var b := glsl_expr(n[3], err)
			match n[1]:
				"+", "-", "*":
					return "(%s %s %s)" % [a, n[1], b]
				"/":
					return "_div(%s, %s)" % [a, b]
				"%":
					return "_mod(%s, %s)" % [a, b]
				"^":
					return "_pow(%s, %s)" % [a, b]
				"&":
					return "float(int(%s) & int(%s))" % [a, b]
				"|":
					return "float(int(%s) | int(%s))" % [a, b]
				"==":
					return "_equal(%s, %s)" % [a, b]
				"!=":
					return "_bnot(_equal(%s, %s))" % [a, b]
				"<", ">", "<=", ">=":
					return "((%s %s %s) ? 1.0 : 0.0)" % [a, n[1], b]
				"&&":
					return "((%s != 0.0 && %s != 0.0) ? 1.0 : 0.0)" % [a, b]
				"||":
					return "((%s != 0.0 || %s != 0.0) ? 1.0 : 0.0)" % [a, b]
		"call":
			var args := PackedStringArray()
			for a in n[2]:
				args.append(glsl_expr(a, err))
			match n[1]:
				"if":
					return "((%s != 0.0) ? %s : %s)" % [args[0], args[1], args[2]]
				"sin", "cos", "tan", "atan", "abs", "sign", "floor", "ceil", "min", "max":
					return "%s(%s)" % [n[1], ", ".join(args)]
				"atan2":
					return "atan(%s, %s)" % [args[0], args[1]]
				"rand":
					return "_rand(%s, UV * 1.618 + vec2(fract(u_time * 7.31)))" % args[0]
				_:
					return "_%s(%s)" % [n[1], ", ".join(args)]
	err[0] = "unknown node"
	return "0.0"


## Statements as shader lines; {ok, code, error}.
static func glsl_block(ast: Array, indent := "\t") -> Dictionary:
	var err := [""]
	var lines := PackedStringArray()
	for s in ast:
		if s[0] == "assign":
			var e := glsl_expr(s[3], err)
			var v: String = "v_" + s[1]
			match s[2]:
				"=":
					lines.append("%s%s = %s;" % [indent, v, e])
				"+=", "-=", "*=":
					lines.append("%s%s = %s %s %s;" % [indent, v, v, s[2].left(1), e])
				"/=":
					lines.append("%s%s = _div(%s, %s);" % [indent, v, v, e])
				"%=":
					lines.append("%s%s = _mod(%s, %s);" % [indent, v, v, e])
		else:
			lines.append("%s_d = %s;" % [indent, glsl_expr(s, err)])
		if err[0] != "":
			return {"ok": false, "code": "", "error": err[0]}
	return {"ok": true, "code": "\n".join(lines), "error": ""}


## The shader functions the translated code calls, MilkDrop's rules as in MilkVM.
const GLSL_HELPERS := """float _div(float a, float b) { return b == 0.0 ? 0.0 : a / b; }
float _mod(float a, float b) { int ib = int(b); return ib == 0 ? 0.0 : float(int(a) % ib); }
float _pow(float a, float b) { float r = pow(abs(a), b); return (a < 0.0 && mod(b, 2.0) == 1.0) ? -r : r; }
float _sqr(float a) { return a * a; }
float _sqrt(float a) { return sqrt(abs(a)); }
float _invsqrt(float a) { return _div(1.0, sqrt(abs(a))); }
float _exp(float a) { return exp(clamp(a, -80.0, 80.0)); }
float _log(float a) { return a > 0.0 ? log(a) : 0.0; }
float _log10(float a) { return a > 0.0 ? log(a) / log(10.0) : 0.0; }
float _asin(float a) { return asin(clamp(a, -1.0, 1.0)); }
float _acos(float a) { return acos(clamp(a, -1.0, 1.0)); }
float _int(float a) { return trunc(a); }
float _above(float a, float b) { return a > b ? 1.0 : 0.0; }
float _below(float a, float b) { return a < b ? 1.0 : 0.0; }
float _equal(float a, float b) { return abs(a - b) < 0.00001 ? 1.0 : 0.0; }
float _bnot(float a) { return a == 0.0 ? 1.0 : 0.0; }
float _band(float a, float b) { return (a != 0.0 && b != 0.0) ? 1.0 : 0.0; }
float _bor(float a, float b) { return (a != 0.0 || b != 0.0) ? 1.0 : 0.0; }
float _sigmoid(float a, float c) { return _div(1.0, 1.0 + _exp(-a * c)); }
float _rand(float a, vec2 p) { float h = fract(sin(dot(p + vec2(a * 0.123), vec2(12.9898, 78.233))) * 43758.5453); return a >= 1.0 ? floor(h * floor(a)) : 0.0; }
"""
