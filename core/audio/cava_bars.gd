class_name CavaBars
extends RefCounted

## Bars that feel right: the smoothing of cava (github.com/karlstav/cava, MIT), re-done here from its
## description rather than copied. Three things make its bars good to watch:
##
##  - integral smoothing: each bar keeps a share of what it was (`smoothing`, 0..1), so noise settles;
##  - gravity: a bar that drops does not follow the sound down but falls like a thrown thing, slowly at
##    first and faster each frame (`gravity`), until the sound catches it again; a rise is taken at once;
##  - "monstercat": a loud bar lifts its neighbours, less with each step away (`monstercat`, 0 for off),
##    so the shape reads as a range rather than a picket fence;
##
## and auto-sensitivity: the gain creeps up while nothing reaches the top and backs off when a bar
## overshoots, so a quiet mix and a loud one both fill the height.
##
## Frame-rate independent: `step(levels, delta)` scales each rule by the frame's length, so a 144 Hz
## and a 60 Hz screen show the same motion.

## The share of the last value an integral keeps per 60th of a second.
var smoothing := 0.55
## How hard a falling bar accelerates (1 is cava's default feel).
var gravity := 1.0
## Neighbour lift (0 off; around 1.5 to 3 is cava's range).
var monstercat := 0.0
## Whether the gain follows the sound (`sensitivity`); off, the levels are taken as they come.
var auto_sens := true
var sensitivity := 1.0
## The shown bars, 0..1.
var bars := PackedFloat32Array()

var _mem := PackedFloat32Array()
var _peak := PackedFloat32Array()
var _fall := PackedFloat32Array()
var _first := true


func _init(count := 32) -> void:
	resize(count)


func resize(count: int) -> void:
	# Packed arrays are values: each is made afresh here, not through a list of them (that would resize copies).
	bars = _zeros(count)
	_mem = _zeros(count)
	_peak = _zeros(count)
	_fall = _zeros(count)


static func _zeros(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	out.fill(0.0)
	return out


## Take one frame of `levels` (raw, 0..1-ish, one per bar) `delta` seconds after the last; returns `bars`.
func step(levels: PackedFloat32Array, delta: float) -> PackedFloat32Array:
	var n := bars.size()
	if levels.size() != n:
		resize(levels.size())
		n = levels.size()
	var frames := clampf(delta * 60.0, 0.05, 6.0)
	var keep := pow(clampf(smoothing, 0.0, 0.98), frames)
	var overshoot := false
	var silent := true
	for i in n:
		var v := maxf(levels[i], 0.0) * sensitivity
		if v > 0.0001:
			silent = false
		# Gravity: a fall accelerates from where the bar last peaked.
		if v < _peak[i]:
			_fall[i] += 0.028 * frames
			v = maxf(_peak[i] * (1.0 - _fall[i] * _fall[i] * gravity), v)
		else:
			_peak[i] = v
			_fall[i] = 0.0
		# The integral, after gravity, as cava runs them.
		v = _mem[i] * keep + v * (1.0 - keep)
		_mem[i] = v
		if v > 1.0:
			overshoot = true
		bars[i] = v
	if monstercat > 0.0:
		_spread(n)
	if auto_sens and not silent:
		if overshoot:
			sensitivity *= pow(0.98, frames)
			_first = false
		else:
			sensitivity *= pow(1.1 if _first else 1.002, frames)
		sensitivity = clampf(sensitivity, 0.02, 400.0)
	for i in n:
		bars[i] = clampf(bars[i], 0.0, 1.0)
	return bars


func _spread(n: int) -> void:
	var base := maxf(monstercat * 1.5, 1.01)
	for z in n:
		var v := bars[z]
		var de := 1.0
		for m in range(z - 1, -1, -1):
			var lifted := v / pow(base, de)
			if lifted < 0.002:
				break
			bars[m] = maxf(bars[m], lifted)
			de += 1.0
		de = 1.0
		for m in range(z + 1, n):
			var lifted := v / pow(base, de)
			if lifted < 0.002:
				break
			bars[m] = maxf(bars[m], lifted)
			de += 1.0
