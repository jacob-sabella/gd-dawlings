class_name MilkHlslParse
extends RefCounted

## Reads a MilkDrop 2 shader (HLSL) as a language and writes it in Godot's, knowing the type of every
## expression (docs/visuals.md). HLSL converts between sizes by itself: a float spreads over a vector, a
## longer vector is cut to the shorter one in `a + b`, a comparison can be multiplied. Godot's language does
## none of that, so each conversion is written out here, where both sides' types are known.
##
## Written for this project from the published description of HLSL and of what MilkDrop gives a shader;
## nothing taken from MilkDrop, projectM or Butterchurn.
##
## How the differences are bridged:
## - Godot has no variables outside a function. A preset's globals become locals of the body (`g_name`), and a
##   function that uses one, or MilkDrop's `uv`, `ret`..., is handed it as an extra `inout` parameter.
## - Godot has no 2x3 or 4x3 matrices: one is kept in the square matrix that holds it, row by row.
## - int is float, as MilkDrop's shader model mostly treats it; `(int)x` truncates.
## - `#define` and `#if` are resolved here, before parsing.

const BINARY: Array = [["||"], ["&&"], ["==", "!="], ["<", ">", "<=", ">="], ["+", "-"], ["*", "/", "%"]]
const ASSIGN := ["=", "+=", "-=", "*=", "/=", "%="]
## Functions that work on each component, with what they are called in Godot's language.
const COMPONENTWISE := {
	"sin": "sin", "cos": "cos", "tan": "tan", "asin": "asin", "acos": "acos", "atan": "atan", "atan2": "atan",
	"sinh": "sinh", "cosh": "cosh", "tanh": "tanh", "exp": "exp", "exp2": "exp2", "log": "log", "log2": "log2",
	"log10": "_hlog10", "sqrt": "sqrt", "rsqrt": "inversesqrt", "abs": "abs", "sign": "sign", "floor": "floor",
	"ceil": "ceil", "round": "round", "trunc": "trunc", "frac": "fract", "degrees": "degrees",
	"radians": "radians", "ddx": "dFdx", "ddy": "dFdy", "fwidth": "fwidth", "saturate": "_sat", "sat": "_sat",
	"pow": "pow", "min": "min", "max": "max", "fmod": "_hfmod", "step": "step", "lerp": "mix", "clamp": "clamp",
	"smoothstep": "smoothstep",
}
## What MilkDrop's shader names are (MilkHlsl's PRELUDE defines them).
const BUILTIN := {
	"time": "float", "fps": "float", "frame": "float", "progress": "float", "bass": "float", "mid": "float",
	"treb": "float", "vol": "float", "bass_att": "float", "mid_att": "float", "treb_att": "float",
	"vol_att": "float", "aspect": "vec4", "texsize": "vec4", "rand_frame": "vec4", "rand_preset": "vec4",
	"roam_cos": "vec4", "roam_sin": "vec4", "slow_roam_cos": "vec4", "slow_roam_sin": "vec4", "M_PI": "float",
	"M_PI_2": "float", "M_INV_PI": "float", "M_INV_PI_2": "float", "_qa": "vec4", "_qb": "vec4", "_qc": "vec4",
	"_qd": "vec4", "_qe": "vec4", "_qf": "vec4", "_qg": "vec4", "_qh": "vec4", "blur1_min": "float",
	"blur1_max": "float", "blur2_min": "float", "blur2_max": "float", "blur3_min": "float", "blur3_max": "float",
	"texsize_noise_lq": "vec4", "texsize_noise_mq": "vec4", "texsize_noise_hq": "vec4",
	"texsize_noise_lq_lite": "vec4", "texsize_noisevol_lq": "vec4", "texsize_noisevol_hq": "vec4",
}
## The fragment's own variables: a function reaches them through `inout` parameters.
const FRAGMENT := {"uv": "vec2", "uv_orig": "vec2", "rad": "float", "ang": "float", "ret": "vec3", "hue_shader": "vec3"}

var error := ""
var uses_blur := false
var swapped := false
var header := ""
var body := ""

var _t: Array = []
var _p := 0
var _scopes: Array[Dictionary] = []
var _fns := {}
## name → {c, ty, decl}: the preset's globals, in the order they were declared.
var _globals := {}
var _global_lines := PackedStringArray()
var _functions := PackedStringArray()
var _in_fn := false
var _carried := {}
var _ret_ty := "void"
var _unique := 0


## Parses `src` (the shader, `shader_body` and all); `error` is "" when it worked.
func run(src: String) -> void:
	_t = _preprocess(MilkHlsl._tokens(MilkHlsl._strip_comments(src)))
	if error != "":
		return
	_shadow_assigned_builtins()
	while error == "" and _p < _t.size():
		if _peek() == "shader_body":
			_p += 1
			_main()
			break
		_top_level()
	if error == "" and body == "":
		_fail("no shader_body")
	header = "\n".join(_functions)


func _fail(why: String) -> void:
	if error == "":
		error = why


func _peek(ahead := 0) -> String:
	var i := _p + ahead
	return String(_t[i][1]) if i < _t.size() else ""


func _kind(ahead := 0) -> String:
	var i := _p + ahead
	return String(_t[i][0]) if i < _t.size() else ""


func _accept(s: String) -> bool:
	if _peek() == s:
		_p += 1
		return true
	return false


func _expect(s: String) -> void:
	if not _accept(s):
		_fail("expected %s before %s" % [s, _peek()])
		_p = _t.size()


# ---- The preprocessor ----

func _preprocess(toks: Array) -> Array:
	var out: Array = []
	var defs := {}
	# One entry per open #if: [this branch is on, a branch was already taken, the enclosing #if is on].
	var stack: Array = []
	var i := 0
	var n := toks.size()
	while i < n:
		var t: Array = toks[i]
		if t[0] == "nl":
			i += 1
			continue
		if t[0] == "id" and String(t[1]).begins_with("#"):
			var word := String(t[1]).substr(1)
			i += 1
			if word == "" and i < n and toks[i][0] == "id":
				word = toks[i][1]
				i += 1
			var line: Array = []
			while i < n and toks[i][0] != "nl":
				line.append(toks[i])
				i += 1
			var on: bool = stack.is_empty() or stack[-1][0]
			match word:
				"define":
					if on and not line.is_empty():
						if line.size() > 1 and line[1][1] == "(":
							_fail("a #define with arguments")
							return []
						defs[line[0][1]] = line.slice(1)
				"undef":
					if on and not line.is_empty():
						defs.erase(line[0][1])
				"if", "ifdef", "ifndef":
					var v := false
					if on:
						if word == "if":
							v = _pp_value(line, defs)
						elif not line.is_empty():
							v = defs.has(line[0][1]) == (word == "ifdef")
					stack.append([on and v, v, on])
				"elif", "else":
					if stack.is_empty():
						_fail("#%s without #if" % word)
						return []
					var top: Array = stack[-1]
					var v: bool = not top[1] and (word == "else" or (top[2] and _pp_value(line, defs)))
					top[0] = top[2] and v
					top[1] = top[1] or v
				"endif":
					if stack.is_empty():
						_fail("#endif without #if")
						return []
					stack.pop_back()
				_:
					_fail("preprocessor #%s" % word)
					return []
			continue
		if stack.is_empty() or stack[-1][0]:
			_expand(t, defs, out, 0)
		i += 1
	return out


func _expand(t: Array, defs: Dictionary, out: Array, depth: int) -> void:
	if t[0] == "id" and defs.has(t[1]) and depth < 16:
		for u: Array in defs[t[1]]:
			_expand(u, defs, out, depth + 1)
	else:
		out.append(t)


## An #if's condition: numbers and operators only, a name counting as its #define or 0.
func _pp_value(line: Array, defs: Dictionary) -> bool:
	var parts := PackedStringArray()
	var i := 0
	while i < line.size():
		var t: Array = line[i]
		if t[1] == "defined":
			var at := i + 1
			if at < line.size() and line[at][1] == "(":
				at += 1
			parts.append("1" if at < line.size() and defs.has(line[at][1]) else "0")
			i = at + 1
			if i < line.size() and line[i][1] == ")" and line[i - 2][1] == "(":
				i += 1
			continue
		var flat: Array = []
		_expand(t, defs, flat, 0)
		for u: Array in flat:
			if u[0] == "num" or (u[0] == "op" and u[1] in ["(", ")", "+", "-", "*", "/", "<", ">", "<=", ">=", "==", "!=", "&&", "||", "!"]):
				parts.append(u[1])
			else:
				parts.append("0")
		i += 1
	var e := Expression.new()
	if e.parse(" ".join(parts)) != OK:
		return false
	var v: Variant = e.execute([], null, false)
	if e.has_execute_failed():
		return false
	return bool(v)


## A preset may write to what is a uniform here (`rand_preset = ...`): that name becomes a variable of its own.
func _shadow_assigned_builtins() -> void:
	for i in _t.size() - 1:
		var s := String(_t[i][1])
		if _t[i][0] != "id" or (i > 0 and _t[i - 1][1] == "."):
			continue
		if not (BUILTIN.has(s) or _is_q(s)):
			continue
		var after := String(_t[i + 1][1])
		if after == "." and i + 3 < _t.size():
			after = String(_t[i + 3][1])
		if (after in ASSIGN or after in ["++", "--"]) and not _globals.has(s):
			var ty: String = BUILTIN.get(s, "float")
			var c := "g_" + s
			_globals[s] = {"c": c, "ty": ty, "decl": "inout %s %s" % [ty, c]}
			_global_lines.append("%s %s = %s;" % [ty, c, s])


static func _is_q(s: String) -> bool:
	return s.length() >= 2 and s[0] == "q" and s.substr(1).is_valid_int() and int(s.substr(1)) >= 1 and int(s.substr(1)) <= 32


# ---- Types ----

## The type a word names ("float", "vec3", "bool", "m23" for a matrix of 2 rows and 3 columns), or "".
static func _type_of(s: String) -> String:
	for base in ["float", "half", "double", "fixed", "uint", "int", "bool"]:
		if not s.begins_with(base):
			continue
		var rest := s.substr(String(base).length())
		if rest == "" or rest == "1":
			return "bool" if base == "bool" else "float"
		if rest.length() == 1 and rest in ["2", "3", "4"]:
			return "vec" + rest
		if rest.length() == 3 and rest[1] == "x" and rest[0] in "1234" and rest[2] in "1234":
			return "m%s%s" % [rest[0], rest[2]]
	return ""


static func _is_mat(ty: String) -> bool:
	return ty.length() == 3 and ty[0] == "m"


## 1 for a float or bool, N for a vector, 0 for a matrix or an array.
static func _dim(ty: String) -> int:
	if ty == "float" or ty == "bool":
		return 1
	if ty.length() == 4 and ty.begins_with("vec"):
		return int(ty[3])
	return 0


static func _vec(n: int) -> String:
	return "float" if n == 1 else "vec%d" % n


## The square matrix a matrix type is kept in.
static func _side(ty: String) -> int:
	return maxi(int(ty[1]), int(ty[2]))


static func _glsl(ty: String) -> String:
	return "mat%d" % _side(ty) if _is_mat(ty) else ty


static func _swizzle(code: String, s: String) -> String:
	return "%s.%s" % [code, s] if code.is_valid_identifier() else "(%s).%s" % [code, s]


## `code` of type `from`, converted to `to` the way HLSL does it by itself.
func _coerce(code: String, from: String, to: String) -> String:
	if from == to:
		return code
	if to == "bool":
		return _cond(code, from)
	if from == "bool":
		return _coerce("float(%s)" % code, "float", to)
	var fd := _dim(from)
	var td := _dim(to)
	if _is_mat(to):
		if _is_mat(from):
			return "%s(%s)" % [_glsl(to), code] if _side(from) != _side(to) else code
		var side := _side(to)
		var v := "vec%d(%s)" % [side, code] if fd == 1 else _coerce(code, from, "vec%d" % side)
		var cols := PackedStringArray()
		for _i in side:
			cols.append(v)
		return "mat%d(%s)" % [side, ", ".join(cols)]
	if _is_mat(from):
		if td == 0:
			_fail("a matrix used as %s" % to)
			return code
		if td == 4 and from == "m22":
			return "vec4(%s[0], %s[1])" % [code, code]
		return _coerce("%s[0]" % code, "vec%d" % _side(from), to)
	if fd == 0 or td == 0:
		_fail("an array used as a value")
		return code
	if fd == 1:
		return "%s(%s)" % [to, code]
	if td < fd:
		return _swizzle(code, "xyzw".left(td))
	# Wider than it was: HLSL presets rely on this only for colours, which end in an opaque alpha.
	var fill := PackedStringArray([code])
	for k in range(fd, td):
		fill.append("1.0" if k == 3 else "0.0")
	return "%s(%s)" % [to, ", ".join(fill)]


## As a condition: not zero.
func _cond(code: String, ty: String) -> String:
	if ty == "bool":
		return code
	var d := _dim(ty)
	if d == 1:
		# In brackets of its own: the condition can be an assignment, `if (a = b)`.
		return "((%s) != 0.0)" % code
	if d > 1:
		return "any(notEqual(%s, %s(0.0)))" % [code, ty]
	_fail("a matrix or array as a condition")
	return code


# ---- Top level ----

func _top_level() -> void:
	while _peek() in ["static", "const", "uniform", "inline", "extern", "shared", "volatile"]:
		_p += 1
	var s := _peek()
	if s == ";":
		_p += 1
		return
	if s in ["sampler", "sampler2D", "sampler3D", "samplerCUBE", "texture", "texture2D", "texture3D"]:
		_skip_declaration()
		return
	var ty := "void" if s == "void" else _type_of(s)
	if ty == "":
		_fail("unknown word at the top: %s" % s)
		return
	_p += 1
	if _kind() != "id":
		_fail("expected a name after %s" % s)
		return
	if _peek(1) == "(":
		_function(ty)
		return
	_global(ty)


## To the `;` that ends it, past a `sampler_state { ...; }`.
func _skip_declaration() -> void:
	var depth := 0
	while _p < _t.size():
		var u := _peek()
		_p += 1
		if u == "{":
			depth += 1
		elif u == "}":
			depth -= 1
		elif u == ";" and depth <= 0:
			return


func _global(ty: String) -> void:
	while error == "":
		var name := _peek()
		_p += 1
		var size := _array_size()
		if name.begins_with("texsize_") or BUILTIN.has(name):
			# MilkDrop's own (a `float4 texsize_x;` for a texture): the prelude has it.
			if _accept("="):
				_assign()
		else:
			var c := "g_" + name
			var suffix := "[%d]" % size if size > 0 else ""
			_globals[name] = {"c": c, "ty": ty + suffix, "decl": "inout %s %s%s" % [_glsl(ty), c, suffix]}
			var value := _initial(ty, size)
			if value == "":
				value = _zero(ty, size)
			_global_lines.append("%s %s%s = %s;" % [_glsl(ty), c, suffix, value])
		if not _accept(","):
			break
	_expect(";")


func _zero(ty: String, size: int) -> String:
	if size > 0:
		var zeros := PackedStringArray()
		for _i in size:
			zeros.append(_zero(ty, 0))
		return "{%s}" % ", ".join(zeros)
	if ty == "bool":
		return "false"
	return _coerce("0.0", "float", ty)


func _array_size() -> int:
	if not _accept("["):
		return 0
	var n := int(_peek())
	_p += 1
	_expect("]")
	if n <= 0:
		_fail("an array without a size")
	return n


## After a declared name: `= value` or `= {list}`, converted; "" when there is none.
func _initial(ty: String, size: int) -> String:
	if not _accept("="):
		return ""
	if _peek() != "{":
		var e := _assign()
		return _coerce(e[0], e[1], ty)
	var parts := _list()
	if size == 0:
		return _construct(ty, parts)[0]
	var elem := _dim(ty) if _dim(ty) > 0 else int(ty[1]) * int(ty[2])
	var comps: Array = []
	for p: Array in parts:
		comps.append_array(_components(p))
	var out := PackedStringArray()
	for k in size:
		var some: Array = []
		for q in elem:
			var at: int = k * elem + q
			some.append([comps[at] if at < comps.size() else "0.0", "float"])
		out.append(_construct(ty, some)[0])
	return "{%s}" % ", ".join(out)


## `{a, b, {c, d}}`, flattened.
func _list() -> Array:
	var out: Array = []
	_expect("{")
	while error == "" and _peek() != "}" and _p < _t.size():
		if _peek() == "{":
			out.append_array(_list())
		else:
			out.append(_assign())
		if not _accept(","):
			break
	_expect("}")
	return out


func _function(ret: String) -> void:
	var name := _peek()
	_p += 2
	_scopes = [{}]
	_in_fn = true
	_carried = {}
	_ret_ty = ret
	var params: Array = []
	var decls := PackedStringArray()
	while error == "" and _peek() != ")" and _p < _t.size():
		var mod := ""
		while _peek() in ["in", "out", "inout", "const", "uniform"]:
			if _peek() in ["out", "inout"]:
				mod = _peek() + " "
			_p += 1
		if _peek().begins_with("sampler"):
			_fail("a sampler handed to a function")
			return
		var ty := _type_of(_peek())
		if ty == "":
			_fail("unknown parameter type %s" % _peek())
			return
		_p += 1
		var pname := _peek()
		_p += 1
		var size := _array_size()
		if _accept(":"):
			_p += 1
		var suffix := "[%d]" % size if size > 0 else ""
		var c := _declare(pname, ty + suffix)
		params.append(ty + suffix)
		decls.append("%s%s %s%s" % [mod, _glsl(ty), c, suffix])
		if not _accept(","):
			break
	_expect(")")
	if _accept(":"):
		_p += 1
	if _accept(";"):
		_in_fn = false
		return
	var overloads: Array = _fns.get(name, [])
	# Two HLSL overloads can be the same here (int and float are both float), so each has its own name.
	var c_name := "h_%s" % name if overloads.is_empty() else "h_%s_o%d" % [name, overloads.size() + 1]
	var fn := {"c": c_name, "ret": ret, "params": params, "carried": {}}
	# Declared before its body so that it can be found; the carried names are filled in after.
	overloads.append(fn)
	_fns[name] = overloads
	var code := _block(false)
	if ret != "void" and not code.contains("return "):
		# HLSL lets it through with a warning; Godot's language wants a return.
		code = code.left(code.rfind("}")) + "return %s;\n}\n" % _zero(ret, 0)
	fn.carried = _carried.duplicate()
	for k in _carried:
		decls.append(_carried[k])
	_functions.append("%s %s(%s) %s" % ["void" if ret == "void" else _glsl(ret), c_name, ", ".join(decls), code])
	_in_fn = false
	_carried = {}
	_scopes = []


func _main() -> void:
	_scopes = [{}]
	_in_fn = false
	var code := _block(false)
	if error == "":
		body = "{\n%s\n%s}\n" % ["\n".join(_global_lines), code]
	_scopes = []


# ---- Statements ----

func _declare(name: String, ty: String) -> String:
	var scope: Dictionary = _scopes[-1]
	var c := "h_" + name
	if scope.has(name):
		_unique += 1
		c = "h_%s_r%d" % [name, _unique]
	scope[name] = {"c": c, "ty": ty}
	return c


func _block(new_scope := true) -> String:
	_expect("{")
	if new_scope:
		_scopes.append({})
	var out := PackedStringArray()
	while error == "" and _peek() != "}" and _p < _t.size():
		out.append(_statement())
	_expect("}")
	if new_scope:
		_scopes.pop_back()
	return "{\n%s}\n" % "".join(out)


func _statement() -> String:
	var s := _peek()
	match s:
		"{":
			return _block()
		";":
			_p += 1
			return ""
		"if":
			_p += 1
			_expect("(")
			var c := _expression()
			_expect(")")
			var out := "if (%s) %s" % [_coerce(c[0], c[1], "bool"), _substatement()]
			if _accept("else"):
				out += "else %s" % _substatement()
			return out
		"while":
			_p += 1
			_expect("(")
			var c := _expression()
			_expect(")")
			return "while (%s) %s" % [_coerce(c[0], c[1], "bool"), _substatement()]
		"do":
			_p += 1
			var inner := _substatement()
			_expect("while")
			_expect("(")
			var c := _expression()
			_expect(")")
			_expect(";")
			return "do %s while (%s);\n" % [inner, _coerce(c[0], c[1], "bool")]
		"for":
			return _for()
		"return":
			_p += 1
			if _accept(";"):
				return "return;\n"
			var e := _expression()
			_expect(";")
			if _ret_ty == "void":
				return "return;\n"
			return "return %s;\n" % _coerce(e[0], e[1], _ret_ty)
		"break", "continue":
			_p += 1
			_expect(";")
			return s + ";\n"
	if _at_declaration():
		var lines := _declaration()
		_expect(";")
		return "".join(lines.map(func(l: String) -> String: return l + ";\n"))
	var parts := _expression_list()
	_expect(";")
	return "".join(parts.map(func(l: String) -> String: return l + ";\n"))


## The statement of an `if` or loop, in braces of its own (a declaration there has a scope).
func _substatement() -> String:
	if _peek() == "{":
		return _block()
	_scopes.append({})
	var inner := _statement()
	_scopes.pop_back()
	return "{\n%s}\n" % inner


func _for() -> String:
	_p += 1
	_expect("(")
	_scopes.append({})
	var init := ""
	var declared := false
	if _peek() != ";":
		if _at_declaration():
			declared = true
			var lines := _declaration()
			init = lines[0] if lines.size() == 1 else ""
			if lines.size() != 1:
				_fail("a for with several declarations")
		else:
			var e := _expression()
			init = e[0]
	_expect(";")
	var cond := "true"
	if _peek() != ";":
		var c := _expression()
		cond = _coerce(c[0], c[1], "bool")
	_expect(";")
	var step := ""
	if _peek() != ")":
		var e := _expression()
		step = e[0]
	_expect(")")
	var inner := _substatement()
	_scopes.pop_back()
	# Godot's `for` starts with a declaration: an assignment there goes just before it.
	if not declared:
		_unique += 1
		return "{\n%s;\nfor (float _l%d = 0.0; %s; %s) %s}\n" % [init, _unique, cond, step, inner] \
				if init != "" else "for (float _l%d = 0.0; %s; %s) %s" % [_unique, cond, step, inner]
	return "for (%s; %s; %s) %s" % [init, cond, step, inner]


func _at_declaration() -> bool:
	var k := 0
	while _peek(k) in ["const", "static"]:
		k += 1
	return _type_of(_peek(k)) != "" and _kind(k + 1) == "id"


func _declaration() -> Array:
	while _peek() in ["const", "static"]:
		_p += 1
	var ty := _type_of(_peek())
	_p += 1
	var out: Array = []
	while error == "":
		var name := _peek()
		_p += 1
		var size := _array_size()
		var suffix := "[%d]" % size if size > 0 else ""
		# The value is read before the name exists: `float x = x * 2;` means the outer x.
		var value := _initial(ty, size)
		var c := _declare(name, ty + suffix)
		out.append("%s %s%s%s" % [_glsl(ty), c, suffix, " = " + value if value != "" else ""])
		if not _accept(","):
			break
	return out


# ---- Expressions: each is [code, type] ----

func _expression() -> Array:
	var parts := _expression_list()
	return [parts[-1] if not parts.is_empty() else "", _last_ty]


var _last_ty := "float"


func _expression_list() -> Array:
	var out: Array = []
	while error == "":
		var e := _assign()
		out.append(e[0])
		_last_ty = e[1]
		if not _accept(","):
			break
	return out


func _assign() -> Array:
	var lhs := _ternary()
	var op := _peek()
	if error != "" or not op in ASSIGN:
		return lhs
	_p += 1
	var rhs := _assign()
	if op == "%=":
		var m := _modulo(lhs, rhs)
		return ["%s = %s" % [lhs[0], _coerce(m[0], m[1], lhs[1])], lhs[1]]
	if op != "=" and _is_mat(lhs[1]) and _dim(rhs[1]) == 1:
		return ["%s %s %s" % [lhs[0], op, _coerce(rhs[0], rhs[1], "float")], lhs[1]]
	return ["%s %s %s" % [lhs[0], op, _coerce(rhs[0], rhs[1], lhs[1])], lhs[1]]


func _ternary() -> Array:
	var c := _binary(0)
	if error != "" or not _accept("?"):
		return c
	var a := _assign()
	_expect(":")
	var b := _assign()
	var ty := _common(a[1], b[1])
	var ca := _coerce(a[0], a[1], ty)
	var cb := _coerce(b[0], b[1], ty)
	var d := _dim(c[1])
	if d > 1 and _dim(ty) >= 1:
		var n := d if _dim(ty) == 1 else mini(d, _dim(ty))
		var v := _vec(n)
		return ["mix(%s, %s, %s)" % [_coerce(cb, ty, v), _coerce(ca, ty, v), _coerce(c[0], c[1], v)], v]
	return ["(%s ? %s : %s)" % [_coerce(c[0], c[1], "bool"), ca, cb], ty]


## The type two values meet at: the shorter vector, a vector over a float, a float over a bool.
func _common(a: String, b: String) -> String:
	if a == b:
		return a
	if _is_mat(a) or _is_mat(b):
		return a if _is_mat(a) else b
	var da := _dim(a)
	var db := _dim(b)
	if da == 1 and db == 1:
		return "float"
	if da == 1:
		return b
	if db == 1:
		return a
	return _vec(mini(da, db))


func _binary(level: int) -> Array:
	if level >= BINARY.size():
		return _unary()
	var a := _binary(level + 1)
	while error == "" and _peek() in BINARY[level]:
		var op := _peek()
		_p += 1
		var b := _binary(level + 1)
		if error != "":
			return a
		match level:
			0, 1:
				a = _logic(op, a, b)
			2, 3:
				a = _compare(op, a, b)
			_:
				a = _modulo(a, b) if op == "%" else _arith(op, a, b)
	return a


func _logic(op: String, a: Array, b: Array) -> Array:
	if _dim(a[1]) > 1 or _dim(b[1]) > 1:
		var ty := _common(a[1], b[1])
		var ca := _coerce(a[0], a[1], ty)
		var cb := _coerce(b[0], b[1], ty)
		var zero := "%s(0.0)" % ty
		var one := "%s(1.0)" % ty
		var fa := "%s(notEqual(%s, %s))" % [ty, ca, zero]
		var fb := "%s(notEqual(%s, %s))" % [ty, cb, zero]
		return ["(%s * %s)" % [fa, fb] if op == "&&" else "min(%s + %s, %s)" % [fa, fb, one], ty]
	return ["(%s %s %s)" % [_coerce(a[0], a[1], "bool"), op, _coerce(b[0], b[1], "bool")], "bool"]


func _compare(op: String, a: Array, b: Array) -> Array:
	var ty := _common(a[1], b[1])
	if a[1] == "bool" and b[1] == "bool" and op in ["==", "!="]:
		return ["(%s %s %s)" % [a[0], op, b[0]], "bool"]
	if ty == "bool":
		ty = "float"
	var ca := _coerce(a[0], a[1], ty)
	var cb := _coerce(b[0], b[1], ty)
	if _dim(ty) == 1:
		return ["(%s %s %s)" % [ca, op, cb], "bool"]
	if _dim(ty) == 0:
		_fail("a matrix compared")
		return a
	const FN := {"<": "lessThan", ">": "greaterThan", "<=": "lessThanEqual", ">=": "greaterThanEqual", "==": "equal", "!=": "notEqual"}
	return ["%s(%s(%s, %s))" % [ty, FN[op], ca, cb], ty]


func _modulo(a: Array, b: Array) -> Array:
	var ty := _common(a[1], b[1])
	if ty == "bool":
		ty = "float"
	if _dim(ty) == 0:
		_fail("% on a matrix")
		return a
	return ["_hfmod(%s, %s)" % [_coerce(a[0], a[1], ty), _coerce(b[0], b[1], ty)], ty]


func _arith(op: String, a: Array, b: Array) -> Array:
	var ta: String = a[1]
	var tb: String = b[1]
	var ca: String = _coerce(a[0], ta, "float") if ta == "bool" else a[0]
	var cb: String = _coerce(b[0], tb, "float") if tb == "bool" else b[0]
	ta = "float" if ta == "bool" else ta
	tb = "float" if tb == "bool" else tb
	if _is_mat(ta) or _is_mat(tb):
		if _dim(ta) == 1 or _dim(tb) == 1:
			return ["(%s %s %s)" % [ca, op, cb], ta if _is_mat(ta) else tb]
		if _is_mat(ta) and _is_mat(tb):
			var cc := _coerce(cb, tb, ta)
			if op == "*":
				return ["matrixCompMult(%s, %s)" % [ca, cc], ta]
			return ["(%s %s %s)" % [ca, op, cc], ta]
		return _mul([ca, ta], [cb, tb])
	if _dim(ta) == 0 or _dim(tb) == 0:
		_fail("an array in arithmetic")
		return a
	if _dim(ta) > 1 and _dim(tb) > 1 and ta != tb:
		var ty := _common(ta, tb)
		return ["(%s %s %s)" % [_coerce(ca, ta, ty), op, _coerce(cb, tb, ty)], ty]
	return ["(%s %s %s)" % [ca, op, cb], ta if _dim(ta) > 1 else tb]


func _unary() -> Array:
	var s := _peek()
	if s == "-" or s == "+":
		_p += 1
		var e := _unary()
		var ty: String = "float" if e[1] == "bool" else e[1]
		var c := _coerce(e[0], e[1], ty)
		if s == "-" and _is_mat(ty):
			return ["(%s * -1.0)" % c, ty]
		return [c if s == "+" else "(-%s)" % c, ty]
	if s == "!":
		_p += 1
		var e := _unary()
		if _dim(e[1]) > 1:
			return ["%s(equal(%s, %s(0.0)))" % [e[1], e[0], e[1]], e[1]]
		return ["(!%s)" % _coerce(e[0], e[1], "bool"), "bool"]
	if s == "++" or s == "--":
		_p += 1
		var e := _unary()
		return ["%s%s" % [s, e[0]], e[1]]
	if s == "(" and _type_of(_peek(1)) != "" and _peek(2) == ")":
		var word := _peek(1)
		_p += 3
		var e := _unary()
		var ty := _type_of(word)
		if word.begins_with("int"):
			var d := _dim(e[1])
			if d >= 1:
				var f := _coerce(e[0], e[1], "float") if e[1] == "bool" else String(e[0])
				return [_coerce("trunc(%s)" % f, "float" if e[1] == "bool" else e[1], ty), ty]
		return [_coerce(e[0], e[1], ty), ty]
	return _postfix()


func _postfix() -> Array:
	var e := _primary()
	while error == "":
		var s := _peek()
		if s == ".":
			_p += 1
			e = _member(e, _peek())
			_p += 1
		elif s == "[":
			_p += 1
			var i := _expression()
			_expect("]")
			e = _index(e, i)
		elif s == "++" or s == "--":
			_p += 1
			e = ["%s%s" % [e[0], s], e[1]]
		else:
			break
	return e


func _member(e: Array, name: String) -> Array:
	var d := _dim(e[1])
	if d == 0 or name.length() > 4 or name == "":
		_fail("a member .%s" % name)
		return e
	var norm := ""
	for ch in name:
		var k := "xyzw".find(ch)
		if k < 0:
			k = "rgba".find(ch)
		if k < 0 or k >= d:
			_fail("a member .%s of %s" % [name, e[1]])
			return e
		norm += "xyzw"[k]
	if d == 1:
		var f: String = _coerce(e[0], e[1], "float")
		return [f if norm.length() == 1 else "%s(%s)" % [_vec(norm.length()), f], _vec(norm.length())]
	return [_swizzle(e[0], norm), _vec(norm.length())]


func _index(e: Array, i: Array) -> Array:
	var at: String = i[0]
	at = at.trim_suffix(".0") if at.ends_with(".0") and at.trim_suffix(".0").is_valid_int() else "int(%s)" % _coerce(i[0], i[1], "float")
	var ty: String = e[1]
	var code := "%s[%s]" % [e[0], at]
	if ty.ends_with("]"):
		return [code, ty.left(ty.find("["))]
	if _is_mat(ty):
		var cols := int(ty[2])
		var row := "vec%d" % cols
		if cols == _side(ty):
			return [code, row]
		return [_swizzle(code, "xyzw".left(cols)), row]
	if _dim(ty) > 1:
		return [code, "float"]
	_fail("an index on %s" % ty)
	return e


func _primary() -> Array:
	var s := _peek()
	var k := _kind()
	if s == "(":
		_p += 1
		var e := _expression()
		_expect(")")
		return ["(%s)" % e[0], e[1]]
	if k == "num":
		_p += 1
		return [MilkHlsl._num(s), "float"]
	if k != "id":
		_fail("unexpected %s" % s)
		_p = _t.size()
		return ["0.0", "float"]
	_p += 1
	if s == "true" or s == "false":
		return [s, "bool"]
	if _peek() == "(":
		_p += 1
		return _call(s)
	return _name(s)


func _name(s: String) -> Array:
	for i in range(_scopes.size() - 1, -1, -1):
		if _scopes[i].has(s):
			return [_scopes[i][s].c, _scopes[i][s].ty]
	if _globals.has(s):
		var g: Dictionary = _globals[s]
		if _in_fn:
			_carried[g.c] = g.decl
		return [g.c, g.ty]
	if FRAGMENT.has(s):
		if _in_fn:
			_carried[s] = "inout %s %s" % [FRAGMENT[s], s]
		return [s, FRAGMENT[s]]
	if s.begins_with("blur") and BUILTIN.has(s):
		uses_blur = true
	if BUILTIN.has(s):
		return [s, BUILTIN[s]]
	if _is_q(s):
		return [s, "float"]
	if s.begins_with("texsize_"):
		return ["texsize_noise_lq", "vec4"]
	var rot := _rotation(s)
	if rot != "":
		return [rot, "m43"]
	if s.begins_with("sampler_"):
		_fail("a sampler used outside tex2D (%s)" % s)
	else:
		_fail("unknown name %s" % s)
	return ["0.0", "float"]


## MilkDrop's turning matrices, `rot_s1` (slow) to `rot_uf4` (ultra fast) and `rot_rand1`: 4 rows of 3.
func _rotation(s: String) -> String:
	const SPEED := {"s": 0.02, "d": 0.08, "f": 0.3, "vf": 0.8, "uf": 2.0}
	if not s.begins_with("rot_") or s.length() < 6 or not s.right(1) in ["1", "2", "3", "4"]:
		return ""
	var kind := s.substr(4, s.length() - 5)
	var n := float(s.right(1))
	if kind == "rand":
		return "_rot(u_rand_preset.x * 6.2831853 * %.1f)" % n
	if not SPEED.has(kind):
		return ""
	return "_rot(u_time * %s + %.1f)" % [SPEED[kind], n * 1.7]


func _args() -> Array:
	var out: Array = []
	while error == "" and _peek() != ")" and _p < _t.size():
		out.append(_assign())
		if not _accept(","):
			break
	_expect(")")
	return out


func _call(name: String) -> Array:
	if _fns.has(name):
		return _call_own(name, _args())
	var ty := _type_of(name)
	if ty != "":
		var args := _args()
		if name.begins_with("int") and args.size() == 1 and _dim(args[0][1]) >= 1:
			var a: Array = args[0]
			var f: String = _coerce(a[0], a[1], "float") if a[1] == "bool" else a[0]
			return [_coerce("trunc(%s)" % f, "float" if a[1] == "bool" else a[1], ty), ty]
		return _construct(ty, args)
	match name.to_lower():
		"tex2d", "tex3d", "tex2dlod", "tex2dbias":
			return _texture(name.to_lower())
	var args := _args()
	if error != "":
		return ["0.0", "float"]
	if COMPONENTWISE.has(name):
		return _componentwise(name, args)
	match name:
		"GetPixel", "GetMain":
			return ["GetPixel(%s)" % _arg(args, 0, "vec2"), "vec3"]
		"GetBlur1", "GetBlur2", "GetBlur3":
			uses_blur = true
			return ["%s(%s)" % [name, _arg(args, 0, "vec2")], "vec3"]
		"lum":
			return ["lum(%s)" % _arg(args, 0, "vec3"), "float"]
		"mul":
			if args.size() == 2:
				return _mul(args[0], args[1])
		"modf":
			if args.size() == 2 and _dim(args[1][1]) >= 1:
				var mt: String = args[1][1]
				return ["modf(%s, %s)" % [_arg(args, 0, mt), args[1][0]], mt]
		"dot", "distance":
			if args.size() == 2:
				var ty2 := _common(args[0][1], args[1][1])
				ty2 = "float" if ty2 == "bool" else ty2
				var a := _coerce(args[0][0], args[0][1], ty2)
				var b := _coerce(args[1][0], args[1][1], ty2)
				if _dim(ty2) == 1:
					return ["(%s * %s)" % [a, b] if name == "dot" else "abs(%s - %s)" % [a, b], "float"]
				return ["%s(%s, %s)" % [name, a, b], "float"]
		"length":
			if args.size() == 1:
				var a: Array = args[0]
				if _dim(a[1]) == 1:
					return ["abs(%s)" % _coerce(a[0], a[1], "float"), "float"]
				return ["length(%s)" % a[0], "float"]
		"normalize":
			if args.size() == 1:
				var a: Array = args[0]
				if _dim(a[1]) == 1:
					return ["sign(%s)" % _coerce(a[0], a[1], "float"), "float"]
				return ["normalize(%s)" % a[0], a[1]]
		"cross":
			return ["cross(%s, %s)" % [_arg(args, 0, "vec3"), _arg(args, 1, "vec3")], "vec3"]
		"reflect":
			if args.size() == 2:
				var ty2 := _vec(maxi(2, _dim(_common(args[0][1], args[1][1]))))
				return ["reflect(%s, %s)" % [_arg(args, 0, ty2), _arg(args, 1, ty2)], ty2]
		"refract":
			if args.size() == 3:
				var ty2 := _vec(maxi(2, _dim(_common(args[0][1], args[1][1]))))
				return ["refract(%s, %s, %s)" % [_arg(args, 0, ty2), _arg(args, 1, ty2), _arg(args, 2, "float")], ty2]
		"all", "any":
			if args.size() == 1:
				var a: Array = args[0]
				if _dim(a[1]) == 1:
					return [_coerce(a[0], a[1], "bool"), "bool"]
				return ["%s(notEqual(%s, %s(0.0)))" % [name, a[0], a[1]], "bool"]
		"transpose":
			if args.size() == 1 and _is_mat(args[0][1]):
				return ["transpose(%s)" % args[0][0], "m%s%s" % [args[0][1][2], args[0][1][1]]]
		"determinant":
			if args.size() == 1 and _is_mat(args[0][1]):
				return ["determinant(%s)" % args[0][0], "float"]
	_fail("unknown function %s" % name)
	return ["0.0", "float"]


func _arg(args: Array, i: int, ty: String) -> String:
	if i >= args.size():
		_fail("too few arguments")
		return "0.0"
	return _coerce(args[i][0], args[i][1], ty)


func _componentwise(name: String, args: Array) -> Array:
	if args.is_empty():
		_fail("%s without arguments" % name)
		return ["0.0", "float"]
	var n := 0
	for a: Array in args:
		var d := _dim(a[1])
		if d == 0:
			_fail("%s of a matrix" % name)
			return ["0.0", "float"]
		if d > 1:
			n = d if n == 0 else mini(n, d)
	var ty := _vec(maxi(n, 1))
	var parts := PackedStringArray()
	for a: Array in args:
		parts.append(_coerce(a[0], a[1], ty))
	return ["%s(%s)" % [COMPONENTWISE[name], ", ".join(parts)], ty]


func _texture(kind: String) -> Array:
	var sampler := _peek()
	if _kind() != "id":
		_fail("%s without a sampler" % kind)
		return ["0.0", "float"]
	_p += 1
	_expect(",")
	var at := _assign()
	# tex2Dlod's and tex2Dbias' extra numbers (a level of detail) are dropped.
	while error == "" and _accept(","):
		_assign()
	_expect(")")
	var ctx := {"uses_blur": false, "swapped": false}
	var fn := MilkHlsl._sampler_fn(sampler, kind == "tex3d", ctx)
	uses_blur = uses_blur or ctx.uses_blur
	swapped = swapped or ctx.swapped
	var want := "vec3" if fn == "_noisevol" else "vec2"
	return ["%s(%s)" % [fn, _coerce(at[0], at[1], want)], "vec4"]


func _call_own(name: String, args: Array) -> Array:
	var best: Dictionary = {}
	var best_cost := 1 << 30
	for fn: Dictionary in _fns[name]:
		if fn.params.size() != args.size():
			continue
		var cost := 0
		for k in args.size():
			cost += _cost(args[k][1], fn.params[k])
		if cost < best_cost:
			best_cost = cost
			best = fn
	if best.is_empty():
		_fail("no %s for these arguments" % name)
		return ["0.0", "float"]
	var parts := PackedStringArray()
	for k in args.size():
		parts.append(_coerce(args[k][0], args[k][1], best.params[k]))
	for c in best.carried:
		parts.append(c)
		if _in_fn:
			_carried[c] = best.carried[c]
	return ["%s(%s)" % [best.c, ", ".join(parts)], best.ret]


## How far a value is from a parameter's type, for picking between overloads.
func _cost(from: String, to: String) -> int:
	if from == to:
		return 0
	var fd := _dim(from)
	var td := _dim(to)
	if fd == 0 or td == 0:
		return 100
	if fd == 1:
		return 1
	return 2 if td < fd else 4


func _mul(a: Array, b: Array) -> Array:
	var ta: String = a[1]
	var tb: String = b[1]
	if _is_mat(ta) and _is_mat(tb):
		var side := maxi(_side(ta), _side(tb))
		var s := "mat%d" % side
		var ca := _coerce(a[0], ta, "m%d%d" % [side, side])
		var cb := _coerce(b[0], tb, "m%d%d" % [side, side])
		return ["_mul(%s(%s), %s(%s))" % [s, ca, s, cb], "m%s%s" % [ta[1], tb[2]]]
	if _is_mat(tb):
		# A row vector times a matrix: as long as its rows, giving as long as its columns.
		var v := _coerce(_coerce(a[0], ta, _vec(int(tb[1]))), _vec(int(tb[1])), "vec%d" % _side(tb))
		var out := "_mul(%s, %s)" % [v, b[0]]
		return [_coerce(out, "vec%d" % _side(tb), _vec(int(tb[2]))), _vec(int(tb[2]))]
	if _is_mat(ta):
		var v := _coerce(_coerce(b[0], tb, _vec(int(ta[2]))), _vec(int(ta[2])), "vec%d" % _side(ta))
		var out := "_mul(%s, %s)" % [a[0], v]
		return [_coerce(out, "vec%d" % _side(ta), _vec(int(ta[1]))), _vec(int(ta[1]))]
	return _arith("*", a, b)


## `float3(...)`, `float2x2(...)`: from any mix of sizes, as HLSL allows.
func _construct(ty: String, args: Array) -> Array:
	if args.is_empty():
		_fail("%s without values" % ty)
		return ["0.0", ty]
	if args.size() == 1 and (_dim(args[0][1]) >= 1 or _is_mat(args[0][1])):
		var one: Array = args[0]
		if not (_is_mat(ty) and _dim(one[1]) > 1):
			return [_coerce(one[0], one[1], ty), ty]
	var comps: Array = []
	for a: Array in args:
		comps.append_array(_components(a))
	if _dim(ty) >= 1:
		var n := _dim(ty)
		if n == 1:
			return [_coerce(comps[0], "float", ty), ty]
		var parts := PackedStringArray()
		var used := 0
		var whole := true
		for a: Array in args:
			var d := _dim(a[1])
			if d == 0 or used + d > n:
				whole = false
				break
			parts.append(_coerce(a[0], a[1], _vec(d)))
			used += d
		if whole and used == n:
			return ["%s(%s)" % [ty, ", ".join(parts)], ty]
		var fill := PackedStringArray()
		for k in n:
			fill.append(comps[k] if k < comps.size() else "0.0")
		return ["%s(%s)" % [ty, ", ".join(fill)], ty]
	if not _is_mat(ty):
		_fail("cannot build %s" % ty)
		return ["0.0", ty]
	var rows := int(ty[1])
	var cols := int(ty[2])
	var side := _side(ty)
	var out_rows := PackedStringArray()
	for r in side:
		var row := PackedStringArray()
		for q in side:
			var at := r * cols + q
			row.append(comps[at] if r < rows and q < cols and at < comps.size() else "0.0")
		out_rows.append("vec%d(%s)" % [side, ", ".join(row)])
	return ["mat%d(%s)" % [side, ", ".join(out_rows)], ty]


func _components(e: Array) -> Array:
	var ty: String = e[1]
	if ty == "float":
		return [e[0]]
	if ty == "bool":
		return ["float(%s)" % e[0]]
	var out: Array = []
	var d := _dim(ty)
	if d > 1:
		for k in d:
			out.append(_swizzle(e[0], "xyzw"[k]))
	elif _is_mat(ty):
		for r in int(ty[1]):
			for q in int(ty[2]):
				out.append("%s[%d][%d]" % [e[0], r, q])
	else:
		_fail("an array where a value goes")
	return out
