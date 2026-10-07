class_name VUMeter
extends Node3D

## A segmented level ladder.
##
## Polls the state cache every frame rather than subscribing to a signal. Reaper streams meters
## at roughly 30Hz per channel, so on a 32-track project that is ~1000 updates a second; fanning
## those out as signals to every surface drawing that track costs more than simply reading two
## floats per meter per frame.
##
## PEAK HOLD AND DECAY LIVE HERE, not in Reaper's data. Reaper sends an instantaneous level; the
## ballistics that make a meter readable -- fast attack, slow release, a peak marker that sits
## for a moment -- are a property of the meter, and different meters in this scene legitimately
## have different ones.

const SEGMENTS := 14
const SEG_HEIGHT := 0.0055
const SEG_GAP := 0.0015
const WIDTH := 0.008

## dB/s. 20 is roughly a PPM-style release: slow enough to read, fast enough to follow a vocal.
const DECAY_PER_SEC := 1.8
const PEAK_HOLD_SEC := 1.2

@export var track_index: int = 0
## Where the level comes from, when it is not a track. The master section sets this; an FX
## return or a monitor path would do the same. A Callable rather than a second meter class,
## because the ballistics, the colour boundaries and the segment count are the whole of what a
## meter IS and none of them change with the thing being metered.
var read_level: Callable = Callable()

var _segments: Array[MeshInstance3D] = []
var _level := 0.0
var _peak := 0.0
var _peak_age := 0.0


func total_height() -> float:
	return SEGMENTS * (SEG_HEIGHT + SEG_GAP)


func _ready() -> void:
	for i in SEGMENTS:
		var seg := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(WIDTH, SEG_HEIGHT, 0.0015)
		seg.mesh = mesh
		seg.position = Vector3(0, i * (SEG_HEIGHT + SEG_GAP), 0.0)
		seg.material_override = Materials.led(_colour_at(i), false)
		add_child(seg)
		_segments.append(seg)


## Green to about -9dB, amber to -3, red at the top two. The colour boundaries are the only
## calibration a meter at a glance actually conveys.
func _colour_at(index: int) -> Color:
	var f := float(index) / float(SEGMENTS - 1)
	if f > 0.92:
		return Color(0.98, 0.22, 0.18)
	if f > 0.76:
		return Color(0.95, 0.68, 0.18)
	return Color(0.30, 0.86, 0.42)


func _process(delta: float) -> void:
	var incoming := 0.0
	if read_level.is_valid():
		incoming = read_level.call()
	else:
		var t := DAW.state.track(track_index, false)
		if t != null:
			incoming = maxf(t.vu_l, t.vu_r)

	# Attack is instant, release is damped. The asymmetry is the whole of meter ballistics: a
	# symmetric filter either misses transients or looks like it is lagging.
	_level = incoming if incoming > _level else maxf(0.0, _level - DECAY_PER_SEC * delta)

	if _level >= _peak:
		_peak = _level
		_peak_age = 0.0
	else:
		_peak_age += delta
		if _peak_age > PEAK_HOLD_SEC:
			_peak = maxf(_level, _peak - DECAY_PER_SEC * delta)

	var lit_count := int(round(_level * SEGMENTS))
	var peak_seg := int(round(_peak * SEGMENTS)) - 1
	for i in _segments.size():
		var on := i < lit_count or i == peak_seg
		_segments[i].material_override = Materials.led(_colour_at(i), on)
