class_name RackBars
extends ControlAffordance

## A row of steps as bars that stand out of the panel, taller and nearer the louder they are, coloured
## cool to hot. Press and drag across them to paint a line: the step under the hand follows the hand's
## height. A sequencer's sixteen knobs, as a landscape you can sculpt.

signal painted(step: int, v: float)
signal released(steps: Array)

var count := 16
var wide := 0.3
var tall := 0.09
var tint := Color(0.4, 0.75, 1.0)
var values := PackedFloat32Array()
var _bars: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
## The step lit as the sequencer's playhead, or -1.
var playhead := -1
var _last := -1
var _touched := {}
var _base: MeshInstance3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	if values.size() != count:
		values.resize(count)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(wide, tall, 0.03)
	shape.shape = box
	shape.position = Vector3(0, tall * 0.5, 0.015)
	add_child(shape)
	_base = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(wide, tall)
	_base.mesh = quad
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.01, 0.014, 0.025)
	glass.roughness = 0.2
	_base.material_override = glass
	_base.position = Vector3(0, tall * 0.5, 0.001)
	_base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_base)
	var each := wide / count
	for i in count:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(each * 0.74, 1.0, 1.0)
		bar.mesh = bm
		var m := StandardMaterial3D.new()
		m.emission_enabled = true
		m.roughness = 0.35
		bar.material_override = m
		bar.position.x = (i + 0.5) * each - wide * 0.5
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bar)
		_bars.append(bar)
		_mats.append(m)
	for i in count:
		_show(i)


func set_step(i: int, v: float) -> void:
	if i < 0 or i >= count:
		return
	if values.size() != count:
		values.resize(count)
	values[i] = clampf(v, 0.0, 1.0)
	if i < _bars.size():
		_show(i)


## The step the sequencer is on: lit white and pushed forward, the way a playhead would be. -1 for none.
func set_playhead(i: int) -> void:
	if i == playhead:
		return
	var was := playhead
	playhead = i
	if was >= 0 and was < _bars.size():
		_show(was)
	if i >= 0 and i < _bars.size():
		_show(i)


func _show(i: int) -> void:
	var v := values[i]
	var h := maxf(0.004, v * (tall - 0.006))
	var d := 0.004 + v * 0.026
	var bar := _bars[i]
	(bar.mesh as BoxMesh).size = Vector3((bar.mesh as BoxMesh).size.x, h, d)
	bar.position.y = 0.003 + h * 0.5
	bar.position.z = d * 0.5
	var c := tint.lerp(Color(1.0, 0.45, 0.25), v)
	_mats[i].albedo_color = c
	_mats[i].emission = c
	_mats[i].emission_energy_multiplier = 0.3 + v * 1.0
	if i == playhead:
		_mats[i].albedo_color = Color(1, 1, 1)
		_mats[i].emission = Color(1, 0.97, 0.85)
		_mats[i].emission_energy_multiplier = 2.2
		bar.position.z = d * 0.5 + 0.006


func hint() -> String:
	return "drag across the bars to paint the steps: the height of your hand is the value"


func _step_at(at: Vector3) -> Array:
	var l := to_local(at)
	var i := clampi(floori((l.x + wide * 0.5) / wide * count), 0, count - 1)
	return [i, clampf(l.y / tall, 0.0, 1.0)]


func _paint(at: Vector3) -> void:
	var s := _step_at(at)
	var i: int = s[0]
	var lo := i
	var hi := i
	if _last >= 0:
		lo = mini(_last, i)
		hi = maxi(_last, i)
	for n in range(lo, hi + 1):
		values[n] = s[1]
		_show(n)
		_touched[n] = true
		painted.emit(n, s[1])
	_last = i


func _on_grab_begin(at: Vector3) -> void:
	_last = -1
	_touched.clear()
	_paint(at)


func _on_grab_move(at: Vector3) -> void:
	_paint(at)


func _on_grab_end() -> void:
	_last = -1
	released.emit(_touched.keys())
	_touched.clear()
