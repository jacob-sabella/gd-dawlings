class_name MilkHlsl
extends RefCounted

## A MilkDrop 2 preset's warp or composite shader (HLSL, as MilkDrop 2 runs it) translated into Godot
## shader code, a safe subset only (docs/visuals.md). Written for this project from the published
## description of what those shaders may use; nothing taken from MilkDrop, projectM or Butterchurn.
##
## Token by token: HLSL's types become GLSL's (float3 → vec3, float3x3 → mat3, int → float), number
## literals become floats, its functions become Godot's or a helper of MilkPlayer's template (lerp → mix,
## frac → fract, saturate, lum, mul with HLSL's argument order, tex2D and tex3D on MilkDrop's samplers,
## GetPixel, GetBlur1..3), and every name of the preset's own gets a prefix, so none collides with a
## Godot keyword. An assignment to a vector or float (`float3 x = 0;`, `ret = tex2D(...)`) is wrapped in a
## helper that splats a scalar or drops extra components, as HLSL does implicitly.
##
## What is not in the subset (a sampler passed around, tex2Dlod, structs, arrays...) leaves an unknown
## name, the shader then fails to compile, and the preset plays with the plain warp or composite instead.
## A texture the preset brings by name (MilkDrop's own pictures, not part of the pack) is drawn as noise:
## `swapped` says so.

## Names MilkDrop gives a shader (kept as they are; MilkPlayer's template defines them).
const KNOWN := ["uv", "uv_orig", "rad", "ang", "ret", "hue_shader", "time", "fps", "frame", "progress", "bass",
	"mid", "treb", "vol", "bass_att", "mid_att", "treb_att", "vol_att", "aspect", "texsize", "rand_frame",
	"rand_preset", "roam_cos", "roam_sin", "slow_roam_cos", "slow_roam_sin", "M_PI", "M_PI_2", "M_INV_PI",
	"M_INV_PI_2", "_qa", "_qb", "_qc", "_qd", "_qe", "_qf", "_qg", "_qh", "blur1_min", "blur1_max",
	"blur2_min", "blur2_max", "blur3_min", "blur3_max", "GetPixel", "GetBlur1", "GetBlur2", "GetBlur3",
	"lum", "texsize_noise_lq", "texsize_noise_mq", "texsize_noise_hq", "texsize_noise_lq_lite",
	"texsize_noisevol_lq", "texsize_noisevol_hq"]
## GLSL's own words and functions that HLSL shares.
const SAME := ["if", "else", "for", "while", "do", "break", "continue", "return", "const", "in", "out", "inout",
	"true", "false", "float", "bool", "vec2", "vec3", "vec4", "mat2", "mat3", "mat4", "void",
	"sin", "cos", "tan", "asin", "acos", "atan", "sqrt", "exp", "exp2", "log", "log2", "abs", "sign",
	"floor", "ceil", "round", "trunc", "step", "smoothstep", "length", "distance",
	"dot", "cross", "normalize", "reflect", "refract", "sinh", "cosh", "tanh", "degrees", "radians"]
const RENAME := {
	"float1": "float", "float2": "vec2", "float3": "vec3", "float4": "vec4", "half": "float", "half1": "float",
	"half2": "vec2", "half3": "vec3", "half4": "vec4", "double": "float", "int": "float", "uint": "float",
	"float2x2": "mat2", "float3x3": "mat3", "float4x4": "mat4", "half2x2": "mat2", "half3x3": "mat3",
	"int2": "vec2", "int3": "vec3", "int4": "vec4", "bool2": "vec2", "bool3": "vec3", "bool4": "vec4",
	"lerp": "_hmix", "pow": "_hpow", "min": "_hmin", "max": "_hmax", "clamp": "_hclamp", "frac": "fract", "fmod": "mod", "atan2": "atan", "rsqrt": "inversesqrt", "ddx": "dFdx",
	"ddy": "dFdy", "saturate": "_sat", "mul": "_mul", "log10": "_hlog10",
}
const DIMS := {"float": 1, "vec2": 2, "vec3": 3, "vec4": 4}
## MilkDrop's main-image samplers: the last frame, wrapped or clamped.
const MAIN_WRAP := ["sampler_main", "sampler_fw_main", "sampler_pw_main"]
const MAIN_CLAMP := ["sampler_fc_main", "sampler_pc_main"]
const NOISE_2D := ["sampler_noise_lq", "sampler_noise_mq", "sampler_noise_hq", "sampler_noise_lq_lite",
	"sampler_pw_noise_lq", "sampler_fw_noise_lq", "sampler_pc_noise_lq", "sampler_fc_noise_lq",
	"sampler_pw_noise_hq", "sampler_fw_noise_hq", "sampler_pw_noise_mq", "sampler_fw_noise_mq"]
const NOISE_3D := ["sampler_noisevol_lq", "sampler_noisevol_hq", "sampler_pw_noisevol_lq", "sampler_fw_noisevol_lq",
	"sampler_pw_noisevol_hq", "sampler_fw_noisevol_hq"]


## {ok, header, body, uses_blur, swapped (a named texture drawn as noise), error}. `src` is the joined
## `warp_N`/`comp_N` text; `body` is the shader_body block, braces and all.
static func translate(src: String) -> Dictionary:
	var out := {"ok": false, "header": "", "body": "", "uses_blur": false, "swapped": false, "error": ""}
	var at := src.find("shader_body")
	if at < 0:
		out.error = "no shader_body"
		return out
	var head_toks := _tokens(_strip_comments(src.left(at)))
	var body_toks := _tokens(_strip_comments(src.substr(at + "shader_body".length())))
	if head_toks.is_empty() and body_toks.is_empty():
		out.error = "empty"
		return out
	var ctx := {"uses_blur": false, "swapped": false, "error": "", "dims": {"ret": 3, "uv": 2, "uv_orig": 2,
			"rad": 1, "ang": 1, "hue_shader": 3}}
	var head := _rewrite(head_toks, ctx, true)
	var body := _rewrite(body_toks, ctx, false)
	if ctx.error != "":
		out.error = ctx.error
		return out
	var split := _constify(head)
	# A global declared without a value is a variable of the shader's: Godot has none, so it moves into
	# the body (a function of the preset's that uses it then fails, and the preset falls back).
	var moved: Array = split[1]
	var open_at := -1
	for k in body.size():
		if body[k][1] == "{":
			open_at = k
			break
	if not moved.is_empty() and open_at >= 0:
		body = body.slice(0, open_at + 1) + moved + body.slice(open_at + 1)
	out.header = _wrap_assignments(split[0], ctx)
	out.body = _wrap_assignments(body, ctx)
	out.uses_blur = ctx.uses_blur
	out.swapped = ctx.swapped
	out.ok = true
	return out


static func _strip_comments(s: String) -> String:
	var out := ""
	var i := 0
	var n := s.length()
	while i < n:
		if s[i] == "/" and i + 1 < n and s[i + 1] == "/":
			while i < n and s[i] != "\n":
				i += 1
		elif s[i] == "/" and i + 1 < n and s[i + 1] == "*":
			var e := s.find("*/", i + 2)
			i = n if e < 0 else e + 2
			out += " "
		else:
			out += s[i]
			i += 1
	return out


## Tokens: [kind, text]: id, num, op, nl (a line end, kept for #define lines).
static func _tokens(s: String) -> Array:
	var out: Array = []
	var i := 0
	var n := s.length()
	while i < n:
		var c := s[i]
		if c == "\n":
			out.append(["nl", "\n"])
			i += 1
		elif c == " " or c == "\t" or c == "\r" or c == "`":
			i += 1
		elif MilkEel._is_alpha(c) or c == "#":
			var j := i + 1
			while j < n and (MilkEel._is_alpha(s[j]) or MilkEel._is_digit(s[j])):
				j += 1
			out.append(["id", s.substr(i, j - i)])
			i = j
		elif MilkEel._is_digit(c) or (c == "." and i + 1 < n and MilkEel._is_digit(s[i + 1])):
			var j := i
			while j < n and (MilkEel._is_digit(s[j]) or s[j] == "."):
				j += 1
			if j < n and (s[j] == "e" or s[j] == "E") and j + 1 < n and (MilkEel._is_digit(s[j + 1]) or s[j + 1] in ["-", "+"]):
				j += 2
				while j < n and MilkEel._is_digit(s[j]):
					j += 1
			var text := s.substr(i, j - i)
			while j < n and s[j] in ["f", "F", "h", "H", "l", "L"]:
				j += 1
			out.append(["num", text])
			i = j
		else:
			var three := s.substr(i, 3)
			var two := s.substr(i, 2)
			if three in ["<<=", ">>="]:
				out.append(["op", three])
				i += 3
			elif two in ["++", "--", "+=", "-=", "*=", "/=", "%=", "==", "!=", "<=", ">=", "&&", "||", "<<", ">>"]:
				out.append(["op", two])
				i += 2
			else:
				out.append(["op", c])
				i += 1
	return out


static func _num(text: String) -> String:
	var t := text
	if t.begins_with("."):
		t = "0" + t
	if t.ends_with("."):
		t += "0"
	if not ("." in t or "e" in t or "E" in t):
		t += ".0"
	return t


## The tokens, translated; text pieces (one per token) for the assignment pass.
static func _rewrite(toks: Array, ctx: Dictionary, header: bool) -> Array:
	var out: Array = []
	var i := 0
	var n := toks.size()
	while i < n:
		var t: Array = toks[i]
		var k: String = t[0]
		var s: String = t[1]
		var prev: String = out[-1][1] if not out.is_empty() else ""
		var next: Array = toks[i + 1] if i + 1 < n else ["", ""]
		if k == "nl":
			if header:
				out.append(["nl", "\n"])
			i += 1
			continue
		if k == "num":
			out.append(["num", s if prev == "[" else _num(s)])
		elif k == "op":
			out.append(["op", s])
		elif s.begins_with("#"):
			if s != "#define":
				ctx.error = "preprocessor %s" % s
				return out
			out.append(["pp", "#define"])
		elif prev == ".":
			out.append(["id", s])
		elif s == "static":
			pass
		elif s == "sampler" or s == "sampler2D" or s == "sampler3D" or s == "texture":
			# A sampler declaration: the samplers are the template's; skip to the `;`.
			while i < n and not (toks[i][0] == "op" and toks[i][1] == ";"):
				i += 1
		elif s in ["float2x2", "float3x3", "float4x4", "half2x2", "half3x3"] and next[1] == "(":
			# Godot builds a matrix from its columns only; HLSL lists its rows (see _mul).
			out.append(["id", "_m" + s.right(1)])
		elif s == "int" and next[1] == "(":
			out.append(["id", "_hint"])
		elif s in ["tex2D", "tex3D"]:
			# tex2D(sampler_x, uv): the sampler decides the helper.
			if i + 3 >= n or toks[i + 1][1] != "(" or toks[i + 2][0] != "id" or toks[i + 3][1] != ",":
				ctx.error = "%s without a sampler" % s
				return out
			var sampler: String = toks[i + 2][1]
			var fn := _sampler_fn(sampler, s == "tex3D", ctx)
			# Used whole (not `.xyz`), the picture's colour is a float3 in practice: it is mixed with them.
			if fn.begins_with("_main") or fn.begins_with("_blur"):
				var d := 0
				var close := i + 1
				while close < n:
					if toks[close][1] == "(":
						d += 1
					elif toks[close][1] == ")":
						d -= 1
						if d == 0:
							break
					close += 1
				if close + 1 >= n or toks[close + 1][1] != ".":
					fn += "3"
			out.append(["id", fn])
			out.append(["op", "("])
			i += 4
			continue
		elif s.begins_with("sampler_"):
			ctx.error = "a sampler used outside tex2D (%s)" % s
			return out
		elif s.begins_with("texsize_"):
			out.append(["id", s if s in KNOWN else "texsize_noise_lq"])
		elif s.begins_with("GetBlur") or s.begins_with("blur"):
			ctx.uses_blur = true
			out.append(["id", s if s in KNOWN else "h_" + s])
		elif RENAME.has(s):
			out.append(["id", RENAME[s]])
		elif s in SAME or s in KNOWN:
			out.append(["id", s])
		elif s.length() >= 2 and s[0] == "q" and s.substr(1).is_valid_int() and int(s.substr(1)) >= 1 and int(s.substr(1)) <= 32:
			out.append(["id", s])
		else:
			out.append(["id", "h_" + s])
		i += 1
	return out


static func _sampler_fn(sampler: String, three_d: bool, ctx: Dictionary) -> String:
	if sampler in MAIN_WRAP:
		return "_main_w"
	if sampler in MAIN_CLAMP:
		return "_main_c"
	if sampler.begins_with("sampler_blur"):
		ctx.uses_blur = true
		return "_blur%s" % sampler.right(1)
	if three_d or sampler in NOISE_3D:
		return "_noisevol"
	if sampler in NOISE_2D:
		return "_noise"
	ctx.swapped = true
	return "_noise"


## A global outside any function, `vec3 h_tint = ...;`, is a constant in Godot's language: marked so.
## Returns [the tokens, the declarations without a value (taken out)]. A declaration of one of MilkDrop's
## own names (a `float4 texsize_x;` for a texture) is dropped: the template has it.
static func _constify(toks: Array) -> Array:
	var out: Array = []
	var moved: Array = []
	var depth := 0
	var last := ";"
	var i := 0
	var n := toks.size()
	while i < n:
		var t: Array = toks[i]
		if t[1] == "{":
			depth += 1
		elif t[1] == "}":
			depth -= 1
		if depth == 0 and t[0] == "id" and t[1] in ["float", "vec2", "vec3", "vec4", "mat2", "mat3", "mat4"] \
				and last in [";", "}"] and i + 2 < n and toks[i + 1][0] == "id" and toks[i + 2][1] != "(":
			var j := i
			var has_value := false
			while j < n and toks[j][1] != ";":
				if toks[j][1] == "=":
					has_value = true
				j += 1
			var decl := toks.slice(i, mini(j + 1, n))
			if not String(toks[i + 1][1]).begins_with("h_"):
				pass
			elif has_value:
				out.append(["id", "const"])
				out.append_array(decl)
			else:
				moved.append_array(decl)
			last = ";"
			i = j + 1
			continue
		out.append(t)
		if t[0] != "nl":
			last = t[1]
		i += 1
	return [out, moved]


## Joins the pieces, wrapping the right side of each assignment to a known float or vector in `_vN(...)`.
static func _wrap_assignments(toks: Array, ctx: Dictionary) -> String:
	var dims: Dictionary = ctx.dims
	# Every declaration's size, first: `vec3 h_x`, and each name after it in `vec3 h_a, h_b = 1.0;`.
	for i in toks.size() - 1:
		if toks[i][0] == "id" and DIMS.has(toks[i][1]) and toks[i + 1][0] == "id" and (i + 2 >= toks.size() or toks[i + 2][1] != "("):
			var j := i + 1
			var d := 0
			var expect_name := true
			while j < toks.size():
				var u: String = toks[j][1]
				if u == "(" or u == "[":
					d += 1
				elif u == ")" or u == "]":
					d -= 1
					if d < 0:
						break
				elif d == 0 and (u == ";" or u == "{" or u == "}"):
					break
				elif d == 0 and u == ",":
					expect_name = true
					j += 1
					continue
				if expect_name and d == 0 and toks[j][0] == "id":
					dims[u] = DIMS[toks[i][1]]
				expect_name = false
				j += 1
	var pieces := PackedStringArray()
	var i := 0
	var n := toks.size()
	var depth := 0
	# A constant's value must stay a constant expression: no helper call around it.
	var in_const := false
	while i < n:
		var t: Array = toks[i]
		var s: String = t[1]
		if t[0] == "id" and s == "const":
			in_const = true
		if t[0] == "op" and s in ["=", "+=", "-=", "*=", "/="] and depth == 0 and not in_const:
			var dim := _target_dim(toks, i, dims)
			# Find the statement's end, and whether its right side has a comma of its own.
			var j := i + 1
			var d := 0
			var comma := false
			while j < n:
				var u: String = toks[j][1]
				if u == "(" or u == "[":
					d += 1
				elif u == ")" or u == "]":
					if d == 0:
						break
					d -= 1
				elif d == 0 and (u == ";" or u == "{" or u == "}"):
					break
				elif d == 0 and u == ",":
					comma = true
				j += 1
			pieces.append(" %s " % s)
			if dim > 0 and not comma:
				pieces.append("_v%d(" % dim)
				for q in range(i + 1, j):
					pieces.append(_piece(toks, q))
				pieces.append(")")
				i = j
				continue
			i += 1
			continue
		if s == "(" or s == "[":
			depth += 1
		elif s == ")" or s == "]":
			depth = maxi(depth - 1, 0)
		elif s == ";" or s == "{" or s == "}":
			depth = 0
			in_const = false
		pieces.append(_piece(toks, i))
		i += 1
	return "".join(pieces)


static func _piece(toks: Array, i: int) -> String:
	var t: Array = toks[i]
	match t[0]:
		"nl":
			return "\n"
		"pp":
			return "\n#define "
		"op":
			if t[1] in [";", "{", "}"]:
				return t[1] + "\n"
			if t[1] in [".", "(", ")", "[", "]", ","]:
				return t[1]
			return " %s " % t[1]
	var nxt: String = toks[i + 1][1] if i + 1 < toks.size() else ""
	return t[1] + (" " if nxt != "" and toks[i + 1][0] in ["id", "num"] else "")


## The size of what is assigned at operator `at`: its swizzle's length, or its declared size; 0 unknown.
static func _target_dim(toks: Array, at: int, dims: Dictionary) -> int:
	var j := at - 1
	if j < 0 or toks[j][0] != "id":
		return 0
	var name: String = toks[j][1]
	if j >= 2 and toks[j - 1][1] == "." and toks[j - 2][0] == "id":
		if name.length() <= 4 and name.is_valid_identifier():
			for c in name:
				if not c in "xyzwrgba":
					return 0
			return name.length()
		return 0
	if j >= 1 and toks[j - 1][0] == "id" and DIMS.has(toks[j - 1][1]):
		return DIMS[toks[j - 1][1]]
	return int(dims.get(name, 0))


static var _noise_2d: ImageTexture = null
static var _noise_3d: ImageTexture3D = null


## The noise a translated shader reads for MilkDrop's noise samplers (and for a texture it names): fixed
## random bytes, 256 by 256, the same every run.
static func noise_2d() -> ImageTexture:
	if _noise_2d == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260
		var data := PackedByteArray()
		data.resize(256 * 256 * 4)
		for i in data.size():
			data[i] = rng.randi() & 255
		_noise_2d = ImageTexture.create_from_image(Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, data))
	return _noise_2d


## The same for MilkDrop's volume noise: 32 by 32 by 32.
static func noise_3d() -> ImageTexture3D:
	if _noise_3d == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261
		var layers: Array[Image] = []
		for z in 32:
			var data := PackedByteArray()
			data.resize(32 * 32 * 4)
			for i in data.size():
				data[i] = rng.randi() & 255
			layers.append(Image.create_from_data(32, 32, false, Image.FORMAT_RGBA8, data))
		_noise_3d = ImageTexture3D.new()
		_noise_3d.create(Image.FORMAT_RGBA8, 32, 32, 32, false, layers)
	return _noise_3d


## What every translated shader is given, after its template's uniforms (u_time, the music's u_bass...,
## u_q): MilkDrop's names for them, the last frame as a wrapped and a clamped sampler (main_w, main_c, read
## in gamma space as MilkDrop's 8-bit buffer was), the noise, and the helpers the translation calls.
## GetBlur1..3 are a ring of taps around the pixel, wider each level (MilkDrop keeps three blurred copies).
const PRELUDE := """
uniform sampler2D main_w : filter_linear, repeat_enable;
uniform sampler2D main_c : filter_linear, repeat_disable;
uniform sampler2D noise_lq : filter_linear, repeat_enable;
uniform sampler3D noisevol : filter_linear, repeat_enable;
uniform vec2 u_size = vec2(512.0, 288.0);
uniform vec4 u_rand_frame = vec4(0.5);
uniform vec4 u_rand_preset = vec4(0.5);

#define time u_time
#define fps u_fps
#define frame u_frame
#define progress u_progress
#define bass u_bass
#define mid u_mid
#define treb u_treb
#define vol ((u_bass + u_mid + u_treb) / 3.0)
#define bass_att u_bass_att
#define mid_att u_mid_att
#define treb_att u_treb_att
#define vol_att ((u_bass_att + u_mid_att + u_treb_att) / 3.0)
#define aspect vec4(u_size.x / u_size.y, 1.0, u_size.y / u_size.x, 1.0)
#define texsize vec4(u_size, 1.0 / u_size)
#define texsize_noise_lq vec4(256.0, 256.0, 1.0 / 256.0, 1.0 / 256.0)
#define texsize_noise_mq texsize_noise_lq
#define texsize_noise_hq texsize_noise_lq
#define texsize_noise_lq_lite texsize_noise_lq
#define texsize_noisevol_lq vec4(32.0, 32.0, 1.0 / 32.0, 1.0 / 32.0)
#define texsize_noisevol_hq texsize_noisevol_lq
#define rand_frame u_rand_frame
#define rand_preset u_rand_preset
#define roam_cos (0.5 + 0.5 * cos(u_time * vec4(0.3, 1.3, 5.0, 20.0)))
#define roam_sin (0.5 + 0.5 * sin(u_time * vec4(0.3, 1.3, 5.0, 20.0)))
#define slow_roam_cos (0.5 + 0.5 * cos(u_time * vec4(0.005, 0.008, 0.013, 0.022)))
#define slow_roam_sin (0.5 + 0.5 * sin(u_time * vec4(0.005, 0.008, 0.013, 0.022)))
#define M_PI 3.14159265359
#define M_PI_2 6.28318530718
#define M_INV_PI 0.31830988618
#define M_INV_PI_2 0.15915494309
#define blur1_min 0.0
#define blur1_max 1.0
#define blur2_min 0.0
#define blur2_max 1.0
#define blur3_min 0.0
#define blur3_max 1.0
#define q1 u_q[0]
#define q2 u_q[1]
#define q3 u_q[2]
#define q4 u_q[3]
#define q5 u_q[4]
#define q6 u_q[5]
#define q7 u_q[6]
#define q8 u_q[7]
#define q9 u_q[8]
#define q10 u_q[9]
#define q11 u_q[10]
#define q12 u_q[11]
#define q13 u_q[12]
#define q14 u_q[13]
#define q15 u_q[14]
#define q16 u_q[15]
#define q17 u_q[16]
#define q18 u_q[17]
#define q19 u_q[18]
#define q20 u_q[19]
#define q21 u_q[20]
#define q22 u_q[21]
#define q23 u_q[22]
#define q24 u_q[23]
#define q25 u_q[24]
#define q26 u_q[25]
#define q27 u_q[26]
#define q28 u_q[27]
#define q29 u_q[28]
#define q30 u_q[29]
#define q31 u_q[30]
#define q32 u_q[31]
#define _qa vec4(u_q[0], u_q[1], u_q[2], u_q[3])
#define _qb vec4(u_q[4], u_q[5], u_q[6], u_q[7])
#define _qc vec4(u_q[8], u_q[9], u_q[10], u_q[11])
#define _qd vec4(u_q[12], u_q[13], u_q[14], u_q[15])
#define _qe vec4(u_q[16], u_q[17], u_q[18], u_q[19])
#define _qf vec4(u_q[20], u_q[21], u_q[22], u_q[23])
#define _qg vec4(u_q[24], u_q[25], u_q[26], u_q[27])
#define _qh vec4(u_q[28], u_q[29], u_q[30], u_q[31])

float _v1(float a) { return a; }
float _v1(vec2 a) { return a.x; }
float _v1(vec3 a) { return a.x; }
float _v1(vec4 a) { return a.x; }
vec2 _v2(float a) { return vec2(a); }
vec2 _v2(vec2 a) { return a; }
vec2 _v2(vec3 a) { return a.xy; }
vec2 _v2(vec4 a) { return a.xy; }
vec3 _v3(float a) { return vec3(a); }
vec3 _v3(vec3 a) { return a; }
vec3 _v3(vec4 a) { return a.xyz; }
vec4 _v4(float a) { return vec4(a); }
vec4 _v4(vec2 a) { return vec4(a, 0.0, 1.0); }
vec4 _v4(vec3 a) { return vec4(a, 1.0); }
vec4 _v4(vec4 a) { return a; }
float _sat(float a) { return clamp(a, 0.0, 1.0); }
vec2 _sat(vec2 a) { return clamp(a, vec2(0.0), vec2(1.0)); }
vec3 _sat(vec3 a) { return clamp(a, vec3(0.0), vec3(1.0)); }
vec4 _sat(vec4 a) { return clamp(a, vec4(0.0), vec4(1.0)); }
float _hint(float a) { return trunc(a); }
vec2 _hint(vec2 a) { return trunc(a); }
vec3 _hint(vec3 a) { return trunc(a); }
vec4 _hint(vec4 a) { return trunc(a); }
float _hlog10(float a) { return log(a) * 0.4342944819; }
vec2 _hlog10(vec2 a) { return log(a) * 0.4342944819; }
vec3 _hlog10(vec3 a) { return log(a) * 0.4342944819; }
vec4 _hlog10(vec4 a) { return log(a) * 0.4342944819; }
float lum(vec3 c) { return dot(c, vec3(0.32, 0.49, 0.29)); }
float lum(vec4 c) { return dot(c.xyz, vec3(0.32, 0.49, 0.29)); }
mat2 _m2(float a, float b, float c, float d) { return mat2(vec2(a, b), vec2(c, d)); }
mat2 _m2(vec2 a, vec2 b) { return mat2(a, b); }
mat2 _m2(vec4 a) { return mat2(a.xy, a.zw); }
mat3 _m3(float a, float b, float c, float d, float e, float f, float g, float h, float i) { return mat3(vec3(a, b, c), vec3(d, e, f), vec3(g, h, i)); }
mat3 _m3(vec3 a, vec3 b, vec3 c) { return mat3(a, b, c); }
mat4 _m4(vec4 a, vec4 b, vec4 c, vec4 d) { return mat4(a, b, c, d); }
// HLSL's matrices are written row by row, GLSL's column by column: each is the other's transpose.
vec2 _mul(vec2 v, mat2 m) { return m * v; }
vec3 _mul(vec3 v, mat3 m) { return m * v; }
vec4 _mul(vec4 v, mat4 m) { return m * v; }
vec2 _mul(mat2 m, vec2 v) { return v * m; }
vec3 _mul(mat3 m, vec3 v) { return v * m; }
vec4 _mul(mat4 m, vec4 v) { return v * m; }
mat2 _mul(mat2 a, mat2 b) { return b * a; }
mat3 _mul(mat3 a, mat3 b) { return b * a; }
float _mul(float a, float b) { return a * b; }
vec4 _main_w(vec2 uv) { return vec4(pow(clamp(texture(main_w, uv).rgb, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2)), 1.0); }
vec4 _main_c(vec2 uv) { return vec4(pow(clamp(texture(main_c, uv).rgb, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2)), 1.0); }
vec4 _noise(vec2 uv) { return texture(noise_lq, uv); }
vec4 _noisevol(vec3 uvw) { return texture(noisevol, uvw); }
vec3 _ring(vec2 uv, float r) {
	vec2 t = r / u_size;
	vec3 s = _main_c(uv).rgb * 2.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398 + 0.3;
		vec2 d = vec2(cos(a), sin(a)) * t;
		s += _main_c(uv + d).rgb + _main_c(uv + d * 0.45).rgb * 1.5;
	}
	return s / 22.0;
}
vec4 _blur1(vec2 uv) { return vec4(_ring(uv, 3.0), 1.0); }
vec4 _blur2(vec2 uv) { return vec4(_ring(uv, 9.0), 1.0); }
vec4 _blur3(vec2 uv) { return vec4(_ring(uv, 24.0), 1.0); }
vec3 _main_w3(vec2 uv) { return _main_w(uv).rgb; }
vec3 _main_c3(vec2 uv) { return _main_c(uv).rgb; }
vec3 _blur13(vec2 uv) { return _ring(uv, 3.0); }
vec3 _blur23(vec2 uv) { return _ring(uv, 9.0); }
vec3 _blur33(vec2 uv) { return _ring(uv, 24.0); }
vec3 GetPixel(vec2 uv) { return _main_w(uv).rgb; }
vec3 GetBlur1(vec2 uv) { return _blur1(uv).rgb; }
vec3 GetBlur2(vec2 uv) { return _blur2(uv).rgb; }
vec3 GetBlur3(vec2 uv) { return _blur3(uv).rgb; }
"""

## The prelude for a translated `header` and `body`: PRELUDE, and the overloads of pow, min, max, lerp and
## clamp the code calls. Those take any mix of a float and vectors, as HLSL's do: a float is spread, a
## longer vector cut to the shorter.
static func prelude(md2: Dictionary) -> String:
	var text := String(md2.get("header", "")) + String(md2.get("body", ""))
	var out := PRELUDE
	for f in [["_hpow", "pow"], ["_hmin", "min"], ["_hmax", "max"]]:
		if text.contains(f[0] + "("):
			out += _overloads(f[0], f[1], 2)
	for f in [["_hmix", "mix"], ["_hclamp", "clamp"]]:
		if text.contains(f[0] + "("):
			out += _overloads(f[0], f[1], 3)
	return out


static func _overloads(name: String, glsl: String, args: int) -> String:
	const TY := ["", "float", "vec2", "vec3", "vec4"]
	var out := PackedStringArray()
	var combos: Array = []
	for a in range(1, 5):
		for b in range(1, 5):
			if args == 2:
				combos.append([a, b])
			else:
				for c in range(1, 5):
					combos.append([a, b, c])
	for dims: Array in combos:
		var r := 4
		var any := false
		for d: int in dims:
			if d > 1:
				r = mini(r, d)
				any = true
		if not any:
			r = 1
		var params := PackedStringArray()
		var call := PackedStringArray()
		for k in dims.size():
			params.append("%s a%d" % [TY[dims[k]], k])
			call.append("_v%d(a%d)" % [r, k])
		out.append("%s %s(%s) { return %s(%s); }" % [TY[r], name, ", ".join(params), glsl, ", ".join(call)])
	return "\n".join(out) + "\n"


## The names a translated body has to work with, set at the top of its fragment (after `uv`, `uv_orig`,
## `rad` and `ang`, which each template sets its own way). The hue is this project's own slow drift.
const BODY_LOCALS := """
	vec3 hue_shader = 0.6 + 0.4 * cos(u_time * vec3(0.27, 0.33, 0.41) + vec3(uv.x * 3.0, uv.y * 3.0 + 2.0, (uv.x + uv.y) * 2.0 + 4.0));
	vec3 ret = vec3(0.0);
"""
