class_name ScopeScreen
extends Node3D

## A glowing oscilloscope screen: dark glass, a graticule, and a trace (`set_wave`, points -1..1) with
## a phosphor smear of its last few frames. Used small on a SCOPE module's panel and large as the TV
## on the annex wall; both show what the engine's SCOPE module saw at the point it is patched in.

const POINTS := 96
const TRAILS := 4

var size := Vector2(0.4, 0.18)
var tint := Color(0.4, 1.0, 0.7):
	set(v):
		tint = v
		_restyle()
var _trace: Array[MeshInstance3D] = []
var _history: Array[PackedFloat32Array] = []
var _line_mat := StandardMaterial3D.new()
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
	for m in [_line_mat, _grid_mat]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_grid()
	for t in TRAILS:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.material_override = _line_mat if t == 0 else _trail_material(t)
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


func _trail_material(t: int) -> StandardMaterial3D:
	var m := _line_mat.duplicate() as StandardMaterial3D
	m.set_meta(&"trail", t)
	return m


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
	_line_mat.albedo_color = Color(tint.r, tint.g, tint.b, 1.0) * 1.1
	_grid_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.12)
	for t in range(1, _trace.size()):
		(_trace[t].material_override as StandardMaterial3D).albedo_color = \
				Color(tint.r, tint.g, tint.b, 0.45 / float(t + 1))
	_glow.light_color = tint


## Draws `wave` (up to POINTS values, -1..1) as the trace; an empty one is a flat line.
func set_wave(wave: PackedFloat32Array) -> void:
	if not _built:
		build()
	var pts := wave
	if pts.is_empty():
		pts = PackedFloat32Array()
		pts.resize(POINTS)
	_history.push_front(pts)
	if _history.size() > TRAILS:
		_history.pop_back()
	var hw := size.x * 0.5
	var hh := size.y * 0.5 * 0.92
	var peak := 0.0
	for t in _history.size():
		var im := _trace[t].mesh as ImmediateMesh
		im.clear_surfaces()
		var w: PackedFloat32Array = _history[t]
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var n := w.size()
		for i in n:
			if t == 0:
				peak = maxf(peak, absf(w[i]))
			im.surface_add_vertex(Vector3(-hw + size.x * i / float(maxi(n - 1, 1)), clampf(w[i], -1.0, 1.0) * hh, 0))
		im.surface_end()
	_glow.light_energy = clampf(peak, 0.0, 1.0) * 0.6
