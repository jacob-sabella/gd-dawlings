class_name MilkHlsl
extends RefCounted

## A MilkDrop 2 preset's warp or composite shader (HLSL, as MilkDrop 2 runs it) translated into Godot
## shader code (docs/visuals.md). MilkHlslParse does the reading and writing, type by type; this holds the
## tokens, the samplers, the noise and the PRELUDE every translated shader starts from. Written for this
## project from the published description of what those shaders may use; nothing taken from MilkDrop,
## projectM or Butterchurn.
##
## What cannot be translated (a sampler passed around, a #define with arguments...) fails with a reason, and
## the preset plays with the plain warp or composite instead. A texture the preset brings by name
## (MilkDrop's own pictures, not part of the pack) is drawn as noise: `swapped` says so.

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
	if src.find("shader_body") < 0:
		out.error = "no shader_body"
		return out
	var p := MilkHlslParse.new()
	p.run(src)
	if p.error != "":
		out.error = p.error
		return out
	out.header = p.header
	out.body = p.body
	out.uses_blur = p.uses_blur
	out.swapped = p.swapped
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


static func _sampler_fn(sampler: String, three_d: bool, ctx: Dictionary) -> String:
	if sampler in MAIN_WRAP:
		return "_main_w"
	if sampler in MAIN_CLAMP:
		return "_main_c"
	# `sampler_fc_blur1`: the filter and wrap prefix does not change which picture it is.
	var plain := sampler
	for prefix in ["sampler_fw_", "sampler_fc_", "sampler_pw_", "sampler_pc_"]:
		if plain.begins_with(prefix):
			plain = "sampler_" + plain.substr(String(prefix).length())
	if plain in ["sampler_blur1", "sampler_blur2", "sampler_blur3"]:
		ctx.uses_blur = true
		return "_blur%s" % plain.right(1)
	if three_d or sampler in NOISE_3D:
		return "_noisevol"
	if sampler in NOISE_2D:
		return "_noise"
	ctx.swapped = true
	return "_noise"


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

float _sat(float a) { return clamp(a, 0.0, 1.0); }
vec2 _sat(vec2 a) { return clamp(a, vec2(0.0), vec2(1.0)); }
vec3 _sat(vec3 a) { return clamp(a, vec3(0.0), vec3(1.0)); }
vec4 _sat(vec4 a) { return clamp(a, vec4(0.0), vec4(1.0)); }
float _hfmod(float a, float b) { return a - b * trunc(a / b); }
vec2 _hfmod(vec2 a, vec2 b) { return a - b * trunc(a / b); }
vec3 _hfmod(vec3 a, vec3 b) { return a - b * trunc(a / b); }
vec4 _hfmod(vec4 a, vec4 b) { return a - b * trunc(a / b); }
float _hlog10(float a) { return log(a) * 0.4342944819; }
vec2 _hlog10(vec2 a) { return log(a) * 0.4342944819; }
vec3 _hlog10(vec3 a) { return log(a) * 0.4342944819; }
vec4 _hlog10(vec4 a) { return log(a) * 0.4342944819; }
float lum(vec3 c) { return dot(c, vec3(0.32, 0.49, 0.29)); }
// HLSL's matrices are written row by row, GLSL's column by column: each is the other's transpose.
vec2 _mul(vec2 v, mat2 m) { return m * v; }
vec3 _mul(vec3 v, mat3 m) { return m * v; }
vec4 _mul(vec4 v, mat4 m) { return m * v; }
vec2 _mul(mat2 m, vec2 v) { return v * m; }
vec3 _mul(mat3 m, vec3 v) { return v * m; }
vec4 _mul(mat4 m, vec4 v) { return v * m; }
mat2 _mul(mat2 a, mat2 b) { return b * a; }
mat3 _mul(mat3 a, mat3 b) { return b * a; }
mat4 _mul(mat4 a, mat4 b) { return b * a; }
// MilkDrop's turning matrices: three axes at their own rates, rows as HLSL writes them.
mat4 _rot(float t) {
	float a = t, b = t * 0.77 + 1.0, c = t * 0.53 + 2.0;
	mat3 x = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(a), sin(a)), vec3(0.0, -sin(a), cos(a)));
	mat3 y = mat3(vec3(cos(b), 0.0, -sin(b)), vec3(0.0, 1.0, 0.0), vec3(sin(b), 0.0, cos(b)));
	mat3 z = mat3(vec3(cos(c), sin(c), 0.0), vec3(-sin(c), cos(c), 0.0), vec3(0.0, 0.0, 1.0));
	mat3 r = x * y * z;
	return mat4(vec4(r[0], 0.0), vec4(r[1], 0.0), vec4(r[2], 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
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
vec3 GetPixel(vec2 uv) { return _main_w(uv).rgb; }
vec3 GetBlur1(vec2 uv) { return _blur1(uv).rgb; }
vec3 GetBlur2(vec2 uv) { return _blur2(uv).rgb; }
vec3 GetBlur3(vec2 uv) { return _blur3(uv).rgb; }
"""

## The names a translated body has to work with, set at the top of its fragment (after `uv`, `uv_orig`,
## `rad` and `ang`, which each template sets its own way). The hue is this project's own slow drift.
const BODY_LOCALS := """
	vec3 hue_shader = 0.6 + 0.4 * cos(u_time * vec3(0.27, 0.33, 0.41) + vec3(uv.x * 3.0, uv.y * 3.0 + 2.0, (uv.x + uv.y) * 2.0 + 4.0));
	vec3 ret = vec3(0.0);
"""
