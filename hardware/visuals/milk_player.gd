class_name MilkPlayer
extends RefCounted

## Plays one MilkDrop preset file (MilkFile) on a MilkScreen (docs/visuals.md). Written for this project
## from MilkDrop's published description of how a preset runs; no MilkDrop, projectM or Butterchurn code.
##
## Once, on loading: its per-frame and per-frame-init equations, and each custom wave's and shape's, are
## compiled to GDScript (MilkEel, MilkVM); its per-pixel equations are translated into a warp shader of
## its own (cached by their text), which runs them for every pixel and then does MilkDrop's warp: the
## zoom raised to `zoomexp^(rad*2-1)`, the stretch and the animated four-term wobble about the centre,
## the turn, the drift, and the fade, kept in an 8-bit-like gamma space so trails die as MilkDrop's do.
##
## Each step (`step`): the per-frame variables start again from the file's values, the music and the
## clock go in, the per-frame code runs, q1..q32 go to the shader and to every wave and shape. Then
## `draw` lays the ink into the buffer: the main wave in its mode (0..7), up to MAX_WAVES custom waves of
## at most MAX_POINTS points each (their per-point code run once per point), up to MAX_SHAPES custom shape
## instances (filled, bordered, textured with the last frame where asked), the borders and the motion
## vectors. `comp()` is what the glass does with it: gamma, echo, brighten, darken, solarize, invert.
##
## A MilkDrop 2 preset's HLSL warp and composite shaders are translated by MilkHlsl: the warp's runs in
## place of the plain fade, the composite is a spatial shader of its own for the glass (`comp_shader`).
## What is left out is said in `notes` (the finder's "approx"): a shader that does not translate or
## compile (the plain one plays instead), and code that does not compile, which is dropped.

const MAX_WAVES := 4
const MAX_POINTS := 256
const MAX_SHAPES := 8
const MAX_SIDES := 64
## Motion vector grid, at most.
const MAX_MV := Vector2i(32, 24)

## The variables the per-frame code reads and writes, besides the file's own starting values.
const FRAME_INPUTS := ["time", "fps", "frame", "progress", "bass", "mid", "treb", "bass_att", "mid_att",
		"treb_att", "meshx", "meshy", "aspectx", "aspecty", "pixelsx", "pixelsy", "monitor"]
const SHAPE_KEYS := ["x", "y", "rad", "ang", "tex_ang", "tex_zoom", "r", "g", "b", "a", "r2", "g2", "b2", "a2",
		"border_r", "border_g", "border_b", "border_a", "sides", "additive", "thickoutline", "textured", "num_inst"]
const WAVE_KEYS := ["r", "g", "b", "a", "samples", "sep", "bspectrum", "busedots", "bdrawthick", "badditive",
		"scaling", "smoothing"]
const PIXEL_VARS := ["x", "y", "rad", "ang", "zoom", "zoomexp", "rot", "warp", "cx", "cy", "dx", "dy", "sx", "sy"]
const PIXEL_FRAME := ["time", "fps", "frame", "progress", "bass", "mid", "treb", "bass_att", "mid_att", "treb_att",
		"meshx", "meshy", "aspectx", "aspecty"]

var file: MilkFile
## Why this preset does not play exactly as in MilkDrop, for the finder; empty when it does (as near as
## this player gets).
var notes := PackedStringArray()
## Whether the per-pixel code made it into the shader (true too when there is none).
var pixel_ok := true
var shader: Shader
## Its MilkDrop 2 composite, translated; null for MilkDrop's plain one (milk_comp.gdshader).
var comp_shader: Shader = null
## Whether `shader` runs its MilkDrop 2 warp shader; `warp_dropped` when it had one that did not translate
## (then the fade is held below 1, since that shader did the fading).
var warp_md2 := false
var warp_dropped := false
var main: MilkVM
var waves: Array[Dictionary] = []
var shapes: Array[Dictionary] = []
## This frame's per-frame variables, after the code: for the screen and a test.
var vars := {}

var _base := {}
var _q_init := PackedFloat32Array()
var _q := PackedFloat32Array()
var _frame := 0
var _rand_preset := Vector4.ZERO

static var _shader_cache := {}
static var _cache_order: Array[String] = []
const SHADER_CACHE := 24


func _init(f: MilkFile) -> void:
	file = f
	_base = f.base()
	_q_init.resize(32)
	_q.resize(32)
	var extra: Array = FRAME_INPUTS + _base.keys()
	for i in 32:
		extra.append("q%d" % (i + 1))
	var r := MilkEel.build({"init": f.per_frame_init, "frame": f.per_frame}, extra)
	if not r.ok:
		notes.append("per-frame code dropped (%s)" % r.error)
		r = MilkEel.build({"init": "", "frame": ""}, extra)
	main = r.vm
	_reset_frame_vars()
	main.call("init")
	for i in 32:
		_q_init[i] = main.take("q%d" % (i + 1))
	for w in f.waves.slice(0, MAX_WAVES):
		_add_wave(w)
	if f.waves.size() > MAX_WAVES:
		notes.append("only %d of its %d custom waves" % [MAX_WAVES, f.waves.size()])
	for s in f.shapes:
		_add_shape(s)
	_rand_preset = Vector4(randf(), randf(), randf(), randf())
	var swapped := false
	if f.warp_shader.strip_edges() != "":
		var t := MilkHlsl.translate(f.warp_shader)
		if t.ok:
			shader = shader_for(f.per_pixel, t)
		if shader != null:
			warp_md2 = true
			swapped = t.swapped
		else:
			warp_dropped = true
			notes.append("MilkDrop 2 warp shader not translated (%s)" % (t.error if not t.ok else "did not compile"))
	if shader == null:
		shader = shader_for(f.per_pixel)
	if shader == null:
		pixel_ok = false
		notes.append("per-pixel code dropped")
		shader = shader_for("")
	if f.comp_shader.strip_edges() != "":
		var t := MilkHlsl.translate(f.comp_shader)
		if t.ok:
			comp_shader = comp_for(t)
		if comp_shader != null:
			swapped = swapped or t.swapped
		else:
			notes.append("MilkDrop 2 composite shader not translated (%s)" % (t.error if not t.ok else "did not compile"))
	if swapped:
		notes.append("its own textures drawn as noise")


## Whether it plays approximately (something dropped).
func approx() -> bool:
	return not notes.is_empty()


func _qt_extra() -> Array:
	var extra: Array = FRAME_INPUTS.duplicate()
	for i in 32:
		extra.append("q%d" % (i + 1))
	for i in 8:
		extra.append("t%d" % (i + 1))
	return extra


func _add_wave(w: Dictionary) -> void:
	var extra := _qt_extra() + WAVE_KEYS
	var r := MilkEel.build({"init": w.init, "frame": w.per_frame}, extra, {"source": w.per_point})
	if not r.ok:
		notes.append("custom wave %d dropped (%s)" % [w.index, r.error])
		return
	var vm: MilkVM = r.vm
	_put_cfg(vm, w.cfg, WAVE_KEYS)
	_put_q(vm, _q_init)
	vm.call("init")
	waves.append({"vm": vm, "cfg": w.cfg})


func _add_shape(s: Dictionary) -> void:
	var extra := _qt_extra() + SHAPE_KEYS + ["instance"]
	var r := MilkEel.build({"init": s.init, "frame": s.per_frame}, extra)
	if not r.ok:
		notes.append("custom shape %d dropped (%s)" % [s.index, r.error])
		return
	var vm: MilkVM = r.vm
	_put_cfg(vm, s.cfg, SHAPE_KEYS)
	_put_q(vm, _q_init)
	vm.call("init")
	shapes.append({"vm": vm, "cfg": s.cfg})


static func _put_cfg(vm: MilkVM, cfg: Dictionary, keys: Array) -> void:
	for k in keys:
		vm.put(k, float(cfg.get(k, 0.0)))


static func _put_q(vm: MilkVM, q: PackedFloat32Array) -> void:
	for i in 32:
		vm.put("q%d" % (i + 1), q[i])


func _reset_frame_vars() -> void:
	for k in _base:
		main.put(k, float(_base[k]))


## One frame: the per-frame code run on the music `f` (MilkScreen's feature dictionary), the wave and
## shape code after it. Returns the per-frame variables.
func step(f: Dictionary, delta: float, aspect: float, buffer: Vector2i) -> Dictionary:
	_frame += 1
	_reset_frame_vars()
	_put_q(main, _q_init)
	main.put("time", float(f.t))
	main.put("fps", clampf(1.0 / maxf(delta, 0.001), 1.0, 240.0))
	main.put("frame", float(_frame))
	main.put("progress", clampf(float(f.get("progress", 0.0)), 0.0, 1.0))
	for k in ["bass", "mid", "treb", "bass_att", "mid_att", "treb_att"]:
		main.put(k, float(f[k]))
	main.put("meshx", 48.0)
	main.put("meshy", 36.0)
	main.put("aspectx", 1.0 / aspect if aspect > 1.0 else 1.0)
	main.put("aspecty", aspect if aspect < 1.0 else 1.0)
	main.put("pixelsx", float(buffer.x))
	main.put("pixelsy", float(buffer.y))
	main.call("frame")
	vars = {}
	for k in _base:
		vars[k] = main.take(k, float(_base[k]))
	for i in 32:
		_q[i] = main.take("q%d" % (i + 1))
	vars["time"] = float(f.t)
	vars["frame"] = float(_frame)
	for k in FRAME_INPUTS:
		if not vars.has(k):
			vars[k] = main.take(k)
	return vars


## Sets the warp shader's uniforms for this frame.
func apply_warp(m: ShaderMaterial, buffer: Vector2i) -> void:
	m.set_shader_parameter(&"u_aspect", float(buffer.x) / buffer.y)
	m.set_shader_parameter(&"texel", Vector2(1.0 / buffer.x, 1.0 / buffer.y))
	for k in ["zoom", "zoomexp", "rot", "warp", "cx", "cy", "dx", "dy", "sx", "sy", "warpanimspeed",
			"warpscale", "wrap", "darken_center"]:
		m.set_shader_parameter(StringName("u_" + k), float(vars.get(k, 0.0)))
	apply_shared(m, buffer)


## The uniforms the warp and a translated composite share: the clock, the music, q1..q32, the decay, and
## for MilkDrop 2 code the buffer's size, the random numbers and the noise.
func apply_shared(m: ShaderMaterial, buffer: Vector2i) -> void:
	var decay := float(vars.get("decay", 0.98))
	if warp_dropped:
		decay = minf(decay, 0.98)
	m.set_shader_parameter(&"u_decay", decay)
	for k in PIXEL_FRAME:
		m.set_shader_parameter(StringName("u_" + k), float(vars.get(k, 0.0)))
	m.set_shader_parameter(&"u_q", _q)
	if warp_md2 or comp_shader != null:
		m.set_shader_parameter(&"u_size", Vector2(buffer))
		m.set_shader_parameter(&"u_rand_frame", Vector4(randf(), randf(), randf(), randf()))
		m.set_shader_parameter(&"u_rand_preset", _rand_preset)
		m.set_shader_parameter(&"noise_lq", MilkHlsl.noise_2d())
		m.set_shader_parameter(&"noisevol", MilkHlsl.noise_3d())


## What the glass does: MilkDrop's composite settings.
func comp() -> Dictionary:
	return {
		"gamma": clampf(float(vars.get("gamma", 2.0)), 0.0, 8.0),
		"echo": clampf(float(vars.get("echo_alpha", 0.0)), 0.0, 1.0),
		"echo_zoom": clampf(float(vars.get("echo_zoom", 1.0)), 0.05, 8.0),
		"echo_orient": posmod(int(vars.get("echo_orient", 0.0)), 4),
		"brighten": 1.0 if float(vars.get("brighten", 0.0)) != 0.0 else 0.0,
		"darken": 1.0 if float(vars.get("darken", 0.0)) != 0.0 else 0.0,
		"solar": 1.0 if float(vars.get("solarize", 0.0)) != 0.0 else 0.0,
		"invert": 1.0 if float(vars.get("invert", 0.0)) != 0.0 else 0.0,
	}


# --- the ink -------------------------------------------------------------------------------------------

## Lays this frame's ink into the buffer: `ink` for blended strokes, `glow` for additive ones. `wave` is the
## music's (-1..1), `bars` its spectrum (0..1), `prev` the last frame (for textured shapes).
func draw(ink: MilkScreen.Ink, glow: MilkScreen.Ink, buffer: Vector2i, wave: PackedFloat32Array,
		bars: PackedFloat32Array, prev: Texture2D) -> void:
	var W := float(buffer.x)
	var H := float(buffer.y)
	var px := W / 512.0
	_borders(ink, W, H)
	_motion_vectors(ink, W, H, px)
	_main_wave(ink, glow, W, H, px, wave)
	for w in waves:
		_custom_wave(w, ink, glow, W, H, px, wave, bars)
	var left := MAX_SHAPES
	for s in shapes:
		left = _custom_shape(s, ink, glow, W, H, px, prev, left)
		if left <= 0:
			break


## MilkDrop's (x, y), 0..1 with y up, as a buffer pixel.
static func _px(x: float, y: float, W: float, H: float) -> Vector2:
	return Vector2(x * W, (1.0 - y) * H)


func _v(k: String, d := 0.0) -> float:
	return float(vars.get(k, d))


func _borders(ink: MilkScreen.Ink, W: float, H: float) -> void:
	var o := clampf(_v("ob_size"), 0.0, 0.5)
	var oc := Color(_v("ob_r"), _v("ob_g"), _v("ob_b"), clampf(_v("ob_a"), 0.0, 1.0))
	if o > 0.0 and oc.a > 0.004:
		_frame_rect(ink, Rect2(0, 0, W, H), o * H, oc)
	var i := clampf(_v("ib_size"), 0.0, 0.5)
	var ic := Color(_v("ib_r"), _v("ib_g"), _v("ib_b"), clampf(_v("ib_a"), 0.0, 1.0))
	if i > 0.0 and ic.a > 0.004:
		var m := o * H
		_frame_rect(ink, Rect2(m, m, W - 2.0 * m, H - 2.0 * m), i * H, ic)


## A border of thickness `t` round the inside of `r`, as triangles.
static func _frame_rect(ink: MilkScreen.Ink, r: Rect2, t: float, c: Color) -> void:
	var a := r.position
	var b := r.end
	for q in [Rect2(a.x, a.y, b.x - a.x, t), Rect2(a.x, b.y - t, b.x - a.x, t),
			Rect2(a.x, a.y + t, t, b.y - a.y - 2.0 * t), Rect2(b.x - t, a.y + t, t, b.y - a.y - 2.0 * t)]:
		var p0: Vector2 = q.position
		var p1: Vector2 = q.end
		ink.add_tri(p0, Vector2(p1.x, p0.y), p1, c, c, c)
		ink.add_tri(p0, p1, Vector2(p0.x, p1.y), c, c, c)


## The motion vectors: a grid of short strokes along where the warp carries each point.
func _motion_vectors(ink: MilkScreen.Ink, W: float, H: float, px: float) -> void:
	var a := clampf(_v("mv_a"), 0.0, 1.0)
	var nx := mini(int(_v("mv_x")), MAX_MV.x)
	var ny := mini(int(_v("mv_y")), MAX_MV.y)
	if a < 0.01 or nx < 1 or ny < 1:
		return
	var c := Color(_v("mv_r"), _v("mv_g"), _v("mv_b"), a)
	var zoom := maxf(_v("zoom", 1.0), 0.0001)
	var rot := _v("rot")
	var centre := Vector2(_v("cx", 0.5), _v("cy", 0.5))
	var segs := PackedVector2Array()
	var len := clampf(_v("mv_l"), 0.0, 5.0)
	for j in ny:
		for i in nx:
			var p := Vector2((i + 0.5) / nx + _v("mv_dx"), (j + 0.5) / ny + _v("mv_dy"))
			var u := (p - centre) / zoom
			u = u.rotated(rot) + centre - Vector2(_v("dx"), _v("dy"))
			var tail := p + (u - p) * len * 8.0
			segs.append(_px(p.x, p.y, W, H))
			segs.append(_px(tail.x, tail.y, W, H) + Vector2(0.0, 0.01))
	ink.strokes.append([segs, c, maxf(px, 1.0), 2])


## The music's wave at `n` points (left), and the same a little later as a right channel.
static func _channels(wave: PackedFloat32Array, n: int, sep: int) -> Array:
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n)
	r.resize(n)
	var m := wave.size()
	if m == 0:
		return [l, r]
	for i in n:
		var x := float(i) / maxf(n - 1, 1) * (m - 1)
		l[i] = wave[int(x)]
		r[i] = wave[(int(x) + sep + m / 5) % m]
	return [l, r]


func _main_wave(ink: MilkScreen.Ink, glow: MilkScreen.Ink, W: float, H: float, px: float, wave: PackedFloat32Array) -> void:
	var c := Color(_v("wave_r", 1.0), _v("wave_g", 1.0), _v("wave_b", 1.0), clampf(_v("wave_a", 0.8), 0.0, 1.0))
	var mode := posmod(int(_v("wave_mode")), 8)
	if _v("modwavealphabyvolume") != 0.0:
		var vol := (_v("bass") + _v("mid") + _v("treb")) / 3.0
		var lo := _v("modwavealphastart", 0.75)
		var hi := _v("modwavealphaend", 0.95)
		c.a *= clampf((vol - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)
	if mode == 3:
		c.a *= clampf(_v("treb") * _v("treb") * 0.5, 0.0, 1.0)
	if _v("wave_brighten", 1.0) != 0.0:
		var top := maxf(c.r, maxf(c.g, c.b))
		if top > 0.001:
			c = Color(c.r / top, c.g / top, c.b / top, c.a)
	if c.a < 0.004:
		return
	var n := 128
	var ch := _channels(wave, n, 0)
	var l: PackedFloat32Array = ch[0]
	var r: PackedFloat32Array = ch[1]
	var scale := _v("wave_scale", 1.0)
	var myst := _v("wave_mystery")
	var cx := _v("wave_x", 0.5)
	var cy := _v("wave_y", 0.5)
	var aspect := W / H
	var t := _v("time")
	var lines: Array[PackedVector2Array] = []
	var pts := PackedVector2Array()
	match mode:
		0:
			pts.resize(n + 1)
			for i in n + 1:
				var j := i % n
				var v := lerpf(l[j], l[0], clampf(float(j - (n - 10)) / 10.0, 0.0, 1.0))
				var rad := 0.25 + 0.25 * v * scale + myst * 0.25
				var ang := float(j) / n * TAU + t * 0.2
				pts[i] = _px(cx + rad * cos(ang) / aspect, cy + rad * sin(ang), W, H)
			lines.append(pts)
		1:
			pts.resize(n)
			for i in n:
				var rad := 0.3 + 0.3 * r[i] * scale + myst * 0.2
				var ang := l[i] * PI + t * 2.3
				pts[i] = _px(cx + rad * cos(ang) / aspect, cy + rad * sin(ang), W, H)
			lines.append(pts)
		2, 3:
			pts.resize(n)
			for i in n:
				pts[i] = _px(cx + l[i] * scale * 0.5 / aspect, cy + r[i] * scale * 0.5, W, H)
			lines.append(pts)
		4:
			pts.resize(n)
			for i in n:
				var d := (l[mini(i + 1, n - 1)] - l[i]) * 0.5
				pts[i] = _px(-0.05 + 1.1 * float(i) / (n - 1) + d * 0.2, cy + l[i] * 0.25 * scale, W, H)
			lines.append(pts)
		5:
			pts.resize(n)
			var cs := cos(t * 0.3)
			var sn := sin(t * 0.3)
			for i in n:
				var x := (l[i] * l[i] - r[i] * r[i]) * scale * 0.7
				var y := 2.0 * l[i] * r[i] * scale * 0.7
				pts[i] = _px(cx + (x * cs - y * sn) / aspect, cy + x * sn + y * cs, W, H)
			lines.append(pts)
		6, 7:
			var ang := myst * PI * 0.5
			var dir := Vector2(cos(ang), sin(ang))
			var nrm := Vector2(-dir.y, dir.x)
			var offsets := [0.0] if mode == 6 else [-0.1 - myst * 0.05, 0.1 + myst * 0.05]
			for o in range(offsets.size()):
				var src: PackedFloat32Array = l if o == 0 else r
				var line := PackedVector2Array()
				line.resize(n)
				for i in n:
					var along := (float(i) / (n - 1) - 0.5) * 1.6
					var p := Vector2(cx, cy) + dir * along + nrm * (src[i] * 0.25 * scale + float(offsets[o]))
					line[i] = _px(p.x, p.y, W, H)
				lines.append(line)
	var target := glow if _v("wave_additive") != 0.0 else ink
	var width := (2.5 if _v("wave_thick") != 0.0 else 1.25) * px
	for line in lines:
		target.strokes.append([line, c, width * (1.6 if _v("wave_usedots") != 0.0 else 1.0), 1 if _v("wave_usedots") != 0.0 else 0])


func _custom_wave(w: Dictionary, ink: MilkScreen.Ink, glow: MilkScreen.Ink, W: float, H: float, px: float,
		wave: PackedFloat32Array, bars: PackedFloat32Array) -> void:
	var vm: MilkVM = w.vm
	var cfg: Dictionary = w.cfg
	_put_cfg(vm, cfg, ["r", "g", "b", "a", "samples"])
	_put_q(vm, _q)
	for k in ["time", "fps", "frame", "progress", "bass", "mid", "treb", "bass_att", "mid_att", "treb_att"]:
		vm.put(k, _v(k))
	vm.call("frame")
	var n := clampi(int(vm.take("samples", 512.0)), 0, MAX_POINTS)
	if n < 2:
		return
	var sep := int(float(cfg.sep))
	var v1 := PackedFloat32Array()
	var v2 := PackedFloat32Array()
	var scaling := float(cfg.scaling)
	if float(cfg.bspectrum) != 0.0:
		v1.resize(n)
		v2.resize(n)
		var m := maxi(bars.size(), 1)
		for i in n:
			var b := bars[int(float(i) / n * m)] if not bars.is_empty() else 0.0
			v1[i] = b * scaling
			v2[i] = (bars[mini(int(float(i) / n * m) + sep / 8, m - 1)] if not bars.is_empty() else 0.0) * scaling
	else:
		var ch := _channels(wave, n, sep)
		v1 = ch[0]
		v2 = ch[1]
		for i in n:
			v1[i] *= scaling
			v2[i] *= scaling
	var out: PackedFloat32Array = vm.call("points", n, v1, v2)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	pts.resize(n)
	cols.resize(n)
	var any := false
	for i in n:
		var o := i * 6
		var x := MilkVM._fin(out[o])
		var y := MilkVM._fin(out[o + 1])
		pts[i] = _px(x, y, W, H)
		var c := Color(out[o + 2], out[o + 3], out[o + 4], clampf(out[o + 5], 0.0, 1.0))
		cols[i] = c
		any = any or c.a > 0.004
	if not any:
		return
	var target := glow if float(cfg.badditive) != 0.0 else ink
	var width := (2.5 if float(cfg.bdrawthick) != 0.0 else 1.25) * px
	if float(cfg.busedots) != 0.0:
		target.strokes.append([pts, cols, width * 1.6, 4])
	else:
		target.strokes.append([pts, cols, width, 3])


## Draws a shape's instances, at most `left` of them; returns how many are left.
func _custom_shape(s: Dictionary, ink: MilkScreen.Ink, glow: MilkScreen.Ink, W: float, H: float, px: float,
		prev: Texture2D, left: int) -> int:
	var vm: MilkVM = s.vm
	var cfg: Dictionary = s.cfg
	var inst := clampi(int(float(cfg.num_inst)), 1, left)
	for k in inst:
		_put_cfg(vm, cfg, SHAPE_KEYS)
		vm.put("instance", float(k))
		_put_q(vm, _q)
		for key in ["time", "fps", "frame", "progress", "bass", "mid", "treb", "bass_att", "mid_att", "treb_att"]:
			vm.put(key, _v(key))
		vm.call("frame")
		var sides := clampi(int(vm.take("sides", 4.0)), 3, MAX_SIDES)
		var centre := _px(vm.take("x", 0.5), vm.take("y", 0.5), W, H)
		var rad := vm.take("rad", 0.1) * H * 0.5
		var ang := vm.take("ang")
		var c_in := Color(vm.take("r"), vm.take("g"), vm.take("b"), clampf(vm.take("a"), 0.0, 1.0))
		var c_out := Color(vm.take("r2"), vm.take("g2"), vm.take("b2"), clampf(vm.take("a2"), 0.0, 1.0))
		var c_rim := Color(vm.take("border_r"), vm.take("border_g"), vm.take("border_b"), clampf(vm.take("border_a"), 0.0, 1.0))
		var target := glow if vm.take("additive") != 0.0 else ink
		var textured := vm.take("textured") != 0.0 and prev != null
		var tex_ang := vm.take("tex_ang")
		var tex_zoom := maxf(absf(vm.take("tex_zoom", 1.0)), 0.01)
		var rim := PackedVector2Array()
		rim.resize(sides + 1)
		for i in sides + 1:
			var a := ang + float(i % sides) / sides * TAU + PI * 0.25
			rim[i] = centre + Vector2(cos(a), -sin(a)) * rad
		if c_in.a > 0.004 or c_out.a > 0.004 or textured:
			for i in sides:
				if textured:
					var uv0 := Vector2(0.5, 0.5)
					var a0 := ang + float(i) / sides * TAU + PI * 0.25 + tex_ang
					var a1 := ang + float(i + 1) / sides * TAU + PI * 0.25 + tex_ang
					var ruv := Vector2(rad / W, rad / H) / tex_zoom
					target.add_tex_tri(centre, rim[i], rim[i + 1], c_in, c_out, c_out, uv0,
							uv0 + Vector2(cos(a0), -sin(a0)) * ruv, uv0 + Vector2(cos(a1), -sin(a1)) * ruv, prev)
				else:
					target.add_tri(centre, rim[i], rim[i + 1], c_in, c_out, c_out)
		if c_rim.a > 0.004:
			target.strokes.append([rim, c_rim, (2.5 if vm.take("thickoutline") != 0.0 else 1.25) * px, 0])
	return left - inst


# --- the warp shader -----------------------------------------------------------------------------------

## The warp shader for this per-pixel code and, when given, a MilkDrop 2 warp shader translated by
## MilkHlsl (cached by their text), or null when it does not compile.
static func shader_for(per_pixel: String, md2 := {}) -> Shader:
	var key := per_pixel.strip_edges()
	if not md2.is_empty():
		key += "\u0001" + String(md2.header) + "\u0001" + String(md2.body)
	return _cached(key, func() -> String: return shader_code(per_pixel.strip_edges(), md2))


## The composite shader for a MilkDrop 2 composite translated by MilkHlsl, or null when it does not compile.
static func comp_for(md2: Dictionary) -> Shader:
	var key := "comp\u0001" + String(md2.header) + "\u0001" + String(md2.body)
	return _cached(key, func() -> String: return comp_code(md2))


static func _cached(key: String, make: Callable) -> Shader:
	if _shader_cache.has(key):
		_cache_order.erase(key)
		_cache_order.append(key)
		return _shader_cache[key]
	var code: String = make.call()
	if code == "":
		return null
	var s := Shader.new()
	s.code = code
	# A shader that does not compile lists no uniforms; these always have some.
	if s.get_shader_uniform_list().is_empty():
		return null
	_shader_cache[key] = s
	_cache_order.append(key)
	while _cache_order.size() > SHADER_CACHE:
		_shader_cache.erase(_cache_order.pop_front())
	return s


static func _frame_uniforms() -> String:
	var out := PackedStringArray()
	for v in PIXEL_FRAME:
		out.append("uniform float u_%s;" % v)
	return "\n".join(out)


## A translated MilkDrop 2 composite's source.
static func comp_code(md2: Dictionary) -> String:
	return COMP_TEMPLATE.format({
		"frame_uniforms": _frame_uniforms(),
		"prelude": MilkHlsl.prelude(md2),
		"header": md2.header,
		"locals": MilkHlsl.BODY_LOCALS,
		"body": md2.body,
	})


## The warp shader's source for this per-pixel code (and MilkDrop 2 warp, when given); "" when the code
## cannot be translated.
static func shader_code(per_pixel: String, md2 := {}) -> String:
	var body := ""
	var locals := PackedStringArray()
	if per_pixel.strip_edges() != "":
		var r := MilkEel.parse(per_pixel)
		if not r.ok:
			return ""
		var g := MilkEel.glsl_block(r.ast)
		if not g.ok:
			return ""
		body = g.code
		var known := {}
		for v in PIXEL_VARS + PIXEL_FRAME:
			known[v] = true
		for i in 32:
			known["q%d" % (i + 1)] = true
		for v in MilkEel.vars_in(r.ast, {}):
			if not known.has(v):
				locals.append("\tfloat v_%s = 0.0;" % v)
	var frame_locals := PackedStringArray()
	for v in PIXEL_FRAME:
		frame_locals.append("\tfloat v_%s = u_%s;" % [v, v])
	var q_locals := PackedStringArray()
	for i in 32:
		q_locals.append("\tfloat v_q%d = u_q[%d];" % [i + 1, i])
	var finish := PLAIN_FINISH
	if not md2.is_empty():
		finish = MD2_FINISH.format({"locals": MilkHlsl.BODY_LOCALS, "body": md2.body})
	return WARP_TEMPLATE.format({
		"helpers": MilkEel.GLSL_HELPERS,
		"prelude": MilkHlsl.prelude(md2) if not md2.is_empty() else "",
		"header": md2.get("header", ""),
		"finish": finish,
		"frame_uniforms": _frame_uniforms(),
		"frame_locals": "\n".join(frame_locals),
		"q_locals": "\n".join(q_locals),
		"locals": "\n".join(locals),
		"code": body,
	})


const WARP_TEMPLATE := """// A MilkDrop preset's warp pass, generated by MilkPlayer from its per-pixel code.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D prev : filter_linear, repeat_enable;
uniform vec2 texel = vec2(0.002, 0.0037);
uniform float u_aspect = 1.8;
uniform float u_zoom = 1.0;
uniform float u_zoomexp = 1.0;
uniform float u_rot = 0.0;
uniform float u_warp = 0.0;
uniform float u_cx = 0.5;
uniform float u_cy = 0.5;
uniform float u_dx = 0.0;
uniform float u_dy = 0.0;
uniform float u_sx = 1.0;
uniform float u_sy = 1.0;
uniform float u_decay = 0.98;
uniform float u_warpanimspeed = 1.0;
uniform float u_warpscale = 1.0;
uniform float u_wrap = 1.0;
uniform float u_darken_center = 0.0;
uniform float u_q[32];
{frame_uniforms}

{helpers}
{prelude}
{header}

void fragment() {
	float _d = 0.0;
	float v_x = UV.x;
	float v_y = 1.0 - UV.y;
	vec2 dc = vec2((v_x - 0.5) * u_aspect, v_y - 0.5);
	float v_rad = length(dc) / length(vec2(u_aspect, 1.0) * 0.5);
	float v_ang = mod(atan(dc.y, dc.x), 6.2831853);
	float rad0 = v_rad;
	float v_zoom = u_zoom;
	float v_zoomexp = u_zoomexp;
	float v_rot = u_rot;
	float v_warp = u_warp;
	float v_cx = u_cx;
	float v_cy = u_cy;
	float v_dx = u_dx;
	float v_dy = u_dy;
	float v_sx = u_sx;
	float v_sy = u_sy;
{frame_locals}
{q_locals}
{locals}
{code}
	// MilkDrop's warp: zoom (shaped by zoomexp across the radius), stretch, wobble, turn, drift.
	float z = pow(max(abs(v_zoom), 0.0001), pow(max(abs(v_zoomexp), 0.0001), rad0 * 2.0 - 1.0));
	vec2 c = vec2(v_cx, v_cy);
	vec2 u = vec2(v_x, v_y) - c;
	u.x *= u_aspect;
	u /= z;
	u /= vec2(abs(v_sx) < 0.0001 ? 0.0001 : v_sx, abs(v_sy) < 0.0001 ? 0.0001 : v_sy);
	float wt = u_time * u_warpanimspeed;
	float wf = 1.0 / max(abs(u_warpscale), 0.01);
	float wa = v_warp * 0.0035;
	u.x += wa * sin(wt * 0.333 + wf * (v_x * 0.75 - v_y * 0.41)) + wa * cos(wt * 0.375 - wf * (v_x * 0.39 + v_y * 0.83));
	u.y += wa * cos(wt * 0.753 - wf * (v_x * 0.61 + v_y * 0.57)) + wa * sin(wt * 0.825 + wf * (v_x * 0.47 - v_y * 0.73));
	float cr = cos(v_rot);
	float sr = sin(v_rot);
	u = vec2(u.x * cr - u.y * sr, u.x * sr + u.y * cr);
	u.x /= u_aspect;
	vec2 s = u + c - vec2(v_dx, v_dy);
	vec2 suv = vec2(s.x, 1.0 - s.y);
	if (u_wrap < 0.5) {
		suv = clamp(suv, texel * 0.5, vec2(1.0) - texel * 0.5);
	}
{finish}
}
"""

## The end of the plain warp: the last frame read where the warp says, faded.
const PLAIN_FINISH := """
	vec3 col = texture(prev, suv).rgb;
	// Faded in gamma space and stepped down to 8-bit levels, so trails die out as MilkDrop's do.
	vec3 g = pow(clamp(col, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2));
	g = floor(g * clamp(u_decay, 0.0, 1.0) * 255.0) / 255.0;
	if (u_darken_center > 0.5) {
		g *= 1.0 - 0.07 * (1.0 - smoothstep(0.0, 0.14, rad0));
	}
	COLOR = vec4(pow(g, vec3(2.2)), 1.0);
"""

## The end of a MilkDrop 2 warp: the preset's own shader, given the warped `uv`, does the reading and the
## fading; what it leaves in `ret` (gamma space) is stepped to 8-bit levels as MilkDrop's buffer would.
const MD2_FINISH := """
	vec2 uv = suv;
	vec2 uv_orig = UV;
	float rad = rad0;
	float ang = v_ang;
{locals}
{body}
	vec3 gq = floor(clamp(ret, vec3(0.0), vec3(1.0)) * 255.0 + 0.01) / 255.0;
	COLOR = vec4(pow(gq, vec3(2.2)), 1.0);
"""

## A MilkDrop 2 composite: the preset's own shader draws the glass from the buffer, in gamma space.
const COMP_TEMPLATE := """// A MilkDrop preset's composite pass, generated by MilkPlayer from its MilkDrop 2 shader.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform float power = 1.0;
uniform vec3 wash = vec3(0.01, 0.012, 0.02);
uniform float u_decay = 0.98;
uniform float u_q[32];
{frame_uniforms}
{prelude}
{header}

void fragment() {
	vec2 uv = UV;
	vec2 uv_orig = UV;
	vec2 dc = vec2((uv.x - 0.5) * u_size.x / u_size.y, 0.5 - uv.y);
	float rad = length(dc) / length(vec2(u_size.x / u_size.y, 1.0) * 0.5);
	float ang = mod(atan(dc.y, dc.x), 6.2831853);
{locals}
{body}
	vec3 m = pow(clamp(ret, vec3(0.0), vec3(1.0)), vec3(2.2));
	ALBEDO = m * power + wash * (1.0 - power);
}
"""
