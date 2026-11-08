class_name RackCushion
extends RefCounted

## The buffer between the rack engine's stream and the speakers (RackVoice's direct feed). The engine makes
## sound in real time and a reader thread files it here (`put`); once a frame the main thread asks what the
## audio generator should be given (`pull`).
##
## Godot's mixer takes the generator's sound 512 frames (10.7 ms) at a time, so a generator fed only what
## arrived since the last frame (it held 8 ms on average) ran dry many times a second: each gap a click.
## So: nothing is pushed until `TARGET` frames are in hand (the cushion); the generator is then kept full
## of what the engine makes; if it runs dry anyway (a stalled frame longer than the cushion) it fills up
## again before it plays on, with a cushion as deep as the stall that emptied it (a jitter buffer: it
## grows to what this machine's frames need and creeps back when they behave); and if the cushion has grown
## past the target (the engine's clock and the sound card's differ) the sound is played a little fast,
## `CATCH_UP` at most, until it is back, rather than dropped.

## The latency the cushion starts with, in frames (60 ms at 48 kHz).
const TARGET := 2880
## The deepest it grows to after stalls (200 ms).
const DEEPEST := 9600
## A stall in the first seconds (the window opening, the patch loading) says nothing of the frames to come.
const WARM_UP := 144000
## Calm this long (frames: 5 s) and the cushion gives 10 ms back, down to `TARGET`.
const CALM := 240000
const GIVE_BACK := 480
## How far over the target the sound may be before it is hurried.
const SLACK := 960
## The most it is hurried: 3 % (half a semitone, heard as a slight lift for a second or two).
const CATCH_UP := 0.03
## A listener that stopped taking sound must not grow the queue without end: the last half second is kept.
const MOST_QUEUED := 24000

var _queue := PackedVector2Array()
var _lock := Mutex.new()
## Whether the cushion is full and the generator is being fed.
var primed := false
## The cushion in force now, `TARGET` to `DEEPEST`.
var target := TARGET
var _pulled := 0
var _calm := 0
## Counts, for the probe and the tests: the generator ran dry, frames dropped by the safety limit,
## frames saved by playing faster.
var underruns := 0
var dropped := 0
var hurried := 0


## Frames from the engine, any thread.
func put(frames: PackedVector2Array) -> void:
	_lock.lock()
	_queue.append_array(frames)
	if _queue.size() > MOST_QUEUED:
		dropped += _queue.size() - MOST_QUEUED
		_queue = _queue.slice(_queue.size() - MOST_QUEUED)
	_lock.unlock()


## How many frames are waiting.
func queued() -> int:
	_lock.lock()
	var n := _queue.size()
	_lock.unlock()
	return n


## The frames taken so far, at most `most`, oldest first, with no cushion (what the reader has done).
func take(most: int) -> PackedVector2Array:
	_lock.lock()
	var n := mini(most, _queue.size())
	var out := _queue.slice(0, n)
	_queue = _queue.slice(n)
	_lock.unlock()
	return out


## Forget what is waiting and begin again with an empty cushion of the starting depth.
func clear() -> void:
	target = TARGET
	_pulled = 0
	_calm = 0
	_lock.lock()
	_queue = PackedVector2Array()
	_lock.unlock()
	primed = false


## What to push to a generator that holds `fill` frames and has room for `space` more: nothing until the
## cushion is in hand; then what has come in, played faster while the cushion is over its target.
func pull(fill: int, space: int) -> PackedVector2Array:
	var waiting := queued()
	if primed and fill <= 0:
		primed = false
		underruns += 1
		_calm = 0
		if _pulled > WARM_UP:
			# What came in while it was dry is the stall: the next one should find that much in hand.
			target = clampi(maxi(target * 5 / 4, waiting + GIVE_BACK), TARGET, DEEPEST)
	if not primed:
		if fill + waiting < target:
			return PackedVector2Array()
		primed = true
	var out := take(space)
	_pulled += out.size()
	_calm += out.size()
	if _calm > CALM and target > TARGET:
		_calm = 0
		target = maxi(target - GIVE_BACK, TARGET)
	var over := fill + waiting - target - SLACK
	if over > 0 and out.size() > 1:
		var ratio := 1.0 + CATCH_UP * minf(float(over) / target, 1.0)
		var quick := hurry(out, ratio)
		hurried += out.size() - quick.size()
		return quick
	return out


## `frames` played `ratio` (>= 1) times as fast: linear interpolation, so there is no step in it.
static func hurry(frames: PackedVector2Array, ratio: float) -> PackedVector2Array:
	var n := int(float(frames.size() - 1) / ratio) + 1
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var at := float(i) * ratio
		var j := int(at)
		var k := mini(j + 1, frames.size() - 1)
		out[i] = frames[j].lerp(frames[k], at - j)
	return out
