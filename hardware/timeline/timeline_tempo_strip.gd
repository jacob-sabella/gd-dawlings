class_name TimelineTempoStrip
extends Node3D

## The tempo's changes, under the middle of the timeline. Everything here acts on the change the
## playhead is under (the last one at or before it; the first is the song's own tempo): BPM sets
## its tempo when let go, ADD puts a new one at the start of the playhead's bar, RAMP makes the
## tempo glide from this change to the next rather than jump there, DEL takes it away. Each is one
## undo step, as `DAW.set_tempo_map` is.

const PITCH := 0.028
const CAPTION := Color(0.62, 0.64, 0.68)
## The BPM knob's sweep.
const BPM_LOW := 40.0
const BPM_HIGH := 240.0

## The TimelineSurface. Typed loosely so the files load in any order.
var surface: Node

var bpm: Knob
var add: PanelButton
var ramp: PanelButton
var remove: PanelButton


func _ready() -> void:
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(4 * PITCH + 0.008, 0.036, 0.004)
	plate.mesh = box
	plate.material_override = Materials.chassis()
	plate.position = Vector3(1.5 * PITCH, -0.004, -0.002)
	add_child(plate)
	bpm = Knob.new()
	bpm.name = "TempoBpm"
	bpm.position = Vector3(0, 0, 0.004)
	bpm.scale = Vector3(0.75, 0.75, 0.75)
	bpm.describe_title = func() -> String: return "TEMPO  " + _which()
	bpm.describe_value = func(v: float) -> String: return "%.1f bpm" % _bpm(v)
	bpm.value_committed.connect(_set_bpm)
	add_child(bpm)
	_caption("BPM", 0)
	add = _key("TempoAdd", "ADD", 1, Color(0.55, 0.85, 0.55), "TEMPO  ADD", _add,
			func() -> String: return "a tempo change at bar %d" % _bar_here())
	ramp = _key("TempoRamp", "RAMP", 2, Color(0.9, 0.8, 0.4), "TEMPO  RAMP", _ramp,
			func() -> String:
				var i := current()
				if i + 1 >= _points().size():
					return "add a change after this one to ramp to"
				return "glide to the next change" if not ramp.lit else "jump at the next change instead")
	remove = _key("TempoRemove", "DEL", 3, Color(0.95, 0.38, 0.34), "TEMPO  REMOVE", _remove,
			func() -> String: return "this change" if current() > 0 else "the song's own tempo stays")
	DAW.transport_changed.connect(refresh)
	refresh()


## The map's points, with the song's tempo as the first, whatever is stored.
func _points() -> Array:
	var s := DAW.state
	if s.tempo_points.is_empty():
		return [[0.0, s.tempo, DawKitTempoMap.HOLD]]
	var out: Array = s.tempo_points.duplicate(true)
	out[0][1] = s.tempo
	return out


## Which point the playhead is under.
func current() -> int:
	var at := DAW.state.beat_at(DAW.state.position_seconds)
	var points := _points()
	var i := 0
	while i + 1 < points.size() and points[i + 1][0] <= at + 0.000001:
		i += 1
	return i


func refresh() -> void:
	var points := _points()
	var i := current()
	bpm.snap_to(clampf((float(points[i][1]) - BPM_LOW) / (BPM_HIGH - BPM_LOW), 0.0, 1.0))
	add.lit = true
	ramp.lit = int(points[i][2]) != DawKitTempoMap.HOLD and i + 1 < points.size()
	remove.lit = i > 0


func _bpm(v: float) -> float:
	return snappedf(lerpf(BPM_LOW, BPM_HIGH, v), 0.1)


func _which() -> String:
	var i := current()
	return "AT BAR %d" % _bar_of(_points()[i][0]) if i > 0 else "OF THE SONG"


func _bar_of(beat: float) -> int:
	return int(floorf(beat / float(maxi(DAW.state.beats_per_bar, 1)))) + 1


func _bar_here() -> int:
	return _bar_of(DAW.state.beat_at(DAW.state.position_seconds))


func _set_bpm(v: float) -> void:
	var points := _points()
	points[current()][1] = _bpm(v)
	_commit(points)


func _add() -> void:
	var points := _points()
	var i := current()
	var beat := float(_bar_here() - 1) * float(maxi(DAW.state.beats_per_bar, 1))
	if is_equal_approx(float(points[i][0]), beat):
		return
	var here := DAW.state.tempo_map().bpm_at(beat)
	points.insert(i + 1, [beat, snappedf(here, 0.1), DawKitTempoMap.HOLD])
	_commit(points)


func _ramp() -> void:
	var points := _points()
	var i := current()
	if i + 1 >= points.size():
		return
	points[i][2] = DawKitTempoMap.HOLD if int(points[i][2]) != DawKitTempoMap.HOLD else DawKitTempoMap.RAMP_BEATS
	_commit(points)


func _remove() -> void:
	var points := _points()
	var i := current()
	if i == 0:
		return
	points.remove_at(i)
	_commit(points)


## One point left is one tempo, stored as no map at all.
func _commit(points: Array) -> void:
	if points.size() == 1:
		if not DAW.state.tempo_points.is_empty():
			DAW.set_tempo_map([])
		if not is_equal_approx(DAW.state.tempo, float(points[0][1])):
			DAW.set_tempo(float(points[0][1]))
		return
	DAW.set_tempo_map(points)


func _key(key_name: String, caption: String, slot: int, colour: Color, title: String,
		act: Callable, what: Callable) -> PanelButton:
	var key := PanelButton.new()
	key.name = key_name
	key.led_colour = colour
	key.lamp_scale = Vector2(0.8, 0.5)
	key.scale = Vector3(1.4, 1.4, 1.4)
	key.position = Vector3(slot * PITCH, 0.0, 0.003)
	key.pressed.connect(act)
	key.describe_title = func() -> String: return title
	key.describe_value = func(_v: float) -> String: return what.call()
	add_child(key)
	_caption(caption, slot)
	return key


func _caption(text: String, slot: int) -> void:
	var l: Label3D = surface._text(text, 22, CAPTION)
	l.position = Vector3(slot * PITCH, -0.015, 0.0016)
	add_child(l)
