class_name ScopeScreen
extends Node3D

## A glowing oscilloscope screen: dark glass, a graticule, and a trace (`set_wave`, points -1..1) with
## a phosphor smear of its last few frames. Used small on a SCOPE module's panel and large as the TV
## on the annex wall; both show what the engine's SCOPE module saw at the point it is patched in.
##
## The trace (the wave and the XY figure) is drawn as an analogue scope's beam (scope_beam.gdshader):
## bright where the signal lingers, faint where it swings fast. The bars fall as cava's do (CavaBars).

const POINTS := 96
const TRAILS := 4
const BEAM := preload("res://hardware/visuals/scope_beam.gdshader")
## The beam's spot (one sigma) against the screen's height.
const BEAM_SIGMA := 0.011
## What the screen draws: the wave (SCOPE), bars low to high (SPECTRUM), one signal against another (VECTOR),
## two level bars (METER), a flowing picture (PLASMA).
enum Mode { WAVE, BARS, XY, METER, PLASMA }

## The screen mode of a rack module type, or -1 if it has no screen.
static func mode_of(type: String) -> int:
	match type:
		"builtin.scope": return Mode.WAVE
		"builtin.spectrum": return Mode.BARS
		"builtin.vector": return Mode.XY
		"builtin.meter": return Mode.METER
		"builtin.plasma": return Mode.PLASMA
	return -1

var mode: int = Mode.WAVE
var _fill := MeshInstance3D.new()
var _fill_mat := StandardMaterial3D.new()
var _bars: PackedFloat32Array = PackedFloat32Array()
## The bars' fall and smoothing; the engine's SPECTRUM already scales them, so no auto-gain.
var _cava := CavaBars.new(POINTS)
var _bars_at := -1

var size := Vector2(0.4, 0.18)
var tint := Color(0.4, 1.0, 0.7):
	set(v):
		tint = v
		_restyle()
var _trace: Array[MeshInstance3D] = []
var _history: Array[PackedFloat32Array] = []
var _grid_mat := StandardMaterial3D.new()
var _glass := MeshInstance3D.new()
var _glow := OmniLight3D.new()
var _built := false


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	var bezel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x + size.y * 0.16, size.y * 1.16, 0.012)
	bezel.mesh = bm
	bezel.position = Vector3(0, 0, -0.008)
	var bz := StandardMaterial3D.new()
	bz.albedo_color = Color(0.03, 0.03, 0.035)
	bz.roughness = 0.5
	bz.metallic = 0.6
	bezel.material_override = bz
	add_child(bezel)
	var quad := QuadMesh.new()
	quad.size = size
	_glass.mesh = quad
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.005, 0.02, 0.015)
	gm.roughness = 0.15
	gm.metallic = 0.3
	_glass.material_override = gm
	_glass.position = Vector3(0, 0, -0.001)
	add_child(_glass)
	for m in [_grid_mat]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_grid()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.vertex_color_use_as_albedo = true
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# `_quad` winds its cells counter-clockwise, Godot's back face: culled, the bars, the meter and the plasma
	# drew nothing at all.
	_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill.mesh = ImmediateMesh.new()
	_fill.material_override = _fill_mat
	_fill.position = Vector3(0, 0, 0.0007)
	add_child(_fill)
	for t in TRAILS:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.material_override = _beam_material(t)
		mi.position = Vector3(0, 0, 0.001 + t * 0.0001)
		add_child(mi)
		_trace.append(mi)
	_glow.omni_range = maxf(size.x * 2.5, 0.8)
	_glow.light_energy = 0.0
	_glow.shadow_enabled = false
	_glow.position = Vector3(0, 0, maxf(size.x * 0.5, 0.15))
	add_child(_glow)
	_restyle()
	set_wave(PackedFloat32Array())


func _beam_material(t: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BEAM
	m.set_shader_parameter(&"sigma", size.y * BEAM_SIGMA)
	m.set_shader_parameter(&"fade", 1.0 if t == 0 else 0.45 / float(t + 1))
	m.set_meta(&"trail", t)
	return m


## The beam along `pts` (screen units) into `im`: a quad a few sigmas round each segment, carrying where
## a point is along and across it (UV) and the segment's length (UV2), for the beam shader. Nothing for
## fewer than two points.
func _beam(im: ImmediateMesh, pts: PackedVector2Array) -> void:
	im.clear_surfaces()
	if pts.size() < 2:
		return
	var w := size.y * BEAM_SIGMA * 3.0
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var a := pts[i]
		var d := pts[i + 1] - a
		var length := d.length()
		var dir := d / length if length > 1e-6 else Vector2.RIGHT
		var n := Vector2(-dir.y, dir.x) * w
		var back := a - dir * w
		var front := a + dir * (length + w)
		var corners := [[back - n, Vector2(-w, -w)], [front - n, Vector2(length + w, -w)], [front + n, Vector2(length + w, w)],
				[back - n, Vector2(-w, -w)], [front + n, Vector2(length + w, w)], [back + n, Vector2(-w, w)]]
		for c: Array in corners:
			im.surface_set_uv(c[1])
			im.surface_set_uv2(Vector2(length, 0.0))
			var p: Vector2 = c[0]
			im.surface_add_vertex(Vector3(p.x, p.y, 0))
	im.surface_end()


func _grid() -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	for i in range(-4, 5):
		var x := hw * i / 4.0
		im.surface_add_vertex(Vector3(x, -hh, 0))
		im.surface_add_vertex(Vector3(x, hh, 0))
	for j in range(-2, 3):
		var y := hh * j / 2.0
		im.surface_add_vertex(Vector3(-hw, y, 0))
		im.surface_add_vertex(Vector3(hw, y, 0))
	im.surface_end()
	mi.mesh = im
	mi.material_override = _grid_mat
	mi.position = Vector3(0, 0, 0.0005)
	add_child(mi)


func _restyle() -> void:
	if not _built:
		return
	_grid_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.12)
	for t in _trace.size():
		(_trace[t].material_override as ShaderMaterial).set_shader_parameter(&"tint", Color(tint.r, tint.g, tint.b, 1.0))
	_glow.light_color = tint


## Draws `wave` (up to POINTS values, -1..1) as the trace; an empty one is a flat line.
func set_wave(wave: PackedFloat32Array) -> void:
	if not _built:
		build()
	var pts := wave
	if pts.is_empty():
		pts = PackedFloat32Array()
		pts.resize(POINTS)
	if mode != Mode.WAVE:
		_draw_mode(pts)
		return
	_fill.visible = false
	_history.push_front(pts)
	if _history.size() > TRAILS:
		_history.pop_back()
	var hw := size.x * 0.5
	var hh := size.y * 0.5 * 0.92
	var peak := 0.0
	for t in _history.size():
		_trace[t].visible = true
		var w: PackedFloat32Array = _history[t]
		var n := w.size()
		var line := PackedVector2Array()
		line.resize(n)
		for i in n:
			if t == 0:
				peak = maxf(peak, absf(w[i]))
			line[i] = Vector2(-hw + size.x * i / float(maxi(n - 1, 1)), clampf(w[i], -1.0, 1.0) * hh)
		_beam(_trace[t].mesh as ImmediateMesh, line)
	_glow.light_energy = clampf(peak, 0.0, 1.0) * 0.6


func _quad(im: ImmediateMesh, x0: float, y0: float, x1: float, y1: float, c: Color) -> void:
	for v in [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y0), Vector2(x1, y1), Vector2(x0, y1)]:
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(v.x, v.y, 0))


## A colour of the tint's hue turned by `turn` (0..1 round the wheel), `v` bright.
func _hued(turn: float, v: float, a := 1.0) -> Color:
	return Color.from_hsv(fposmod(tint.h + turn, 1.0), 0.75, clampf(v, 0.0, 1.0), a)


func _draw_mode(pts: PackedFloat32Array) -> void:
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	var im := _fill.mesh as ImmediateMesh
	im.clear_surfaces()
	_fill.visible = true
	var peak := 0.0
	match mode:
		Mode.BARS:
			_hide_trace()
			var n := mini(pts.size(), POINTS)
			var bw := size.x / n
			var fell := _fall_bars(pts.slice(0, n))
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in n:
				var v := clampf(fell[i], 0.0, 1.0)
				peak = maxf(peak, v)
				var x := -hw + bw * i
				_quad(im, x + bw * 0.12, -hh, x + bw * 0.88, -hh + size.y * v, _hued(float(i) / n * 0.45, 0.55 + 0.45 * v))
			im.surface_end()
		Mode.XY:
			_fill.visible = false
			_history.push_front(pts)
			if _history.size() > TRAILS:
				_history.pop_back()
			for t in _history.size():
				_trace[t].visible = true
				var w: PackedFloat32Array = _history[t]
				var figure := PackedVector2Array()
				for i in w.size() / 2:
					if t == 0:
						peak = maxf(peak, maxf(absf(w[i * 2]), absf(w[i * 2 + 1])))
					figure.append(Vector2(clampf(w[i * 2], -1.0, 1.0) * hw * 0.92, clampf(w[i * 2 + 1], -1.0, 1.0) * hh * 0.92))
				_beam(_trace[t].mesh as ImmediateMesh, figure)
		Mode.METER:
			_hide_trace()
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			for c in 2:
				var y0 := hh * (0.62 - c * 1.0) - hh * 0.28
				var y1 := y0 + hh * 0.56
				var rms := clampf(pts[c * 3], 0.0, 1.0)
				var cells := 32
				var cw := size.x * 0.92 / cells
				for i in cells:
					var f := float(i + 1) / cells
					if f > rms:
						_quad(im, -hw * 0.92 + cw * i + cw * 0.1, y0, -hw * 0.92 + cw * (i + 1) - cw * 0.1, y1, Color(1, 1, 1, 0.05))
						continue
					var col := Color(0.2, 0.9, 0.4) if f < 0.7 else (Color(1.0, 0.8, 0.2) if f < 0.9 else Color(1.0, 0.25, 0.2))
					_quad(im, -hw * 0.92 + cw * i + cw * 0.1, y0, -hw * 0.92 + cw * (i + 1) - cw * 0.1, y1, col)
				var pk := clampf(pts[c * 3 + 2], 0.0, 1.0)
				var px := -hw * 0.92 + size.x * 0.92 * pk
				_quad(im, px - cw * 0.3, y0 - hh * 0.06, px + cw * 0.3, y1 + hh * 0.06, Color(1, 1, 1, 0.9))
				peak = maxf(peak, rms)
			im.surface_end()
		Mode.PLASMA:
			_hide_trace()
			var r := clampf(pts[0], 0.0, 1.0)
			var g := clampf(pts[1], 0.0, 1.0)
			var b := clampf(pts[2], 0.0, 1.0)
			var t := pts[3]
			var hue := pts[4]
			var cols := 28
			var rows := 12
			var cw := size.x / cols
			var rh := size.y / rows
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			for j in rows:
				for i in cols:
					var u := float(i) / cols
					var w := float(j) / rows
					var a := sin(u * 7.0 + t * 1.3 + r * 6.0) + sin(w * 9.0 - t * 0.9 + g * 6.0) \
							+ sin((u + w) * 6.0 + t * 0.7 + b * 6.0) + sin(sqrt((u - 0.5) * (u - 0.5) + (w - 0.5) * (w - 0.5)) * 14.0 - t * 1.6)
					var f := a * 0.25 + 0.5
					var c := _hued(hue + f * 0.5 + (r - b) * 0.2, 0.25 + 0.75 * f * (0.5 + 0.5 * maxf(r, maxf(g, b))))
					_quad(im, -hw + cw * i, -hh + rh * j, -hw + cw * (i + 1), -hh + rh * (j + 1), c)
					peak = maxf(peak, f)
			im.surface_end()
	_glow.light_energy = clampf(peak, 0.0, 1.0) * 0.6


## The SPECTRUM's bars as cava would show them: rising at once, falling under gravity, a little smoothed.
func _fall_bars(raw: PackedFloat32Array) -> PackedFloat32Array:
	var now := Time.get_ticks_msec()
	var delta := clampf(float(now - _bars_at) / 1000.0, 0.0, 0.1) if _bars_at >= 0 else 1.0 / 60.0
	_bars_at = now
	_cava.auto_sens = false
	_cava.smoothing = 0.35
	return _cava.step(raw, maxf(delta, 0.001))


func _hide_trace() -> void:
	for m in _trace:
		m.visible = false
